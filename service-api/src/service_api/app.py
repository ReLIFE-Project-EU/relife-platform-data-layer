import datetime
import logging
import time
from functools import lru_cache
from importlib.metadata import version
from typing import Annotated

import httpx
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic_settings import BaseSettings
from supabase import AsyncClient, create_async_client
from supabase.client import ClientOptions

_logger = logging.getLogger("uvicorn")

try:
    __version__ = version("service-api")
except ImportError:
    __version__ = "development"

app = FastAPI(
    title="Service API",
    description="An example of a ReLIFE service as an HTTP API",
    version=__version__,
)

security = HTTPBearer()


class Settings(BaseSettings):
    """Configuration settings for the service API loaded from environment variables."""

    supabase_url: str
    # Service role key - this is a special API key with admin privileges that bypasses
    # Row Level Security (RLS) policies and has full access to the database. It should
    # only be used server-side and never exposed to clients.
    supabase_key: str
    keycloak_client_id: str
    keycloak_client_secret: str


@lru_cache
def get_settings():
    """Get cached application settings."""

    return Settings()


async def get_keycloak_token(
    keycloak_url: str, client_id: str, client_secret: str
) -> str:
    """Obtain an admin access token from Keycloak using client credentials flow.
    Raises HTTPException if token request fails."""

    token_url = f"{keycloak_url}/protocol/openid-connect/token"

    data = {
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
    }

    async with httpx.AsyncClient() as client:
        response = await client.post(token_url, data=data)

        try:
            response.raise_for_status()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))

        return response.json()["access_token"]


async def get_keycloak_user_roles(
    keycloak_url: str, admin_token: str, user_id: str
) -> list:
    """Fetch a user's realm roles from Keycloak's admin API.
    Requires an admin token with appropriate permissions."""

    role_mapper_base_url = keycloak_url.replace("/realms", "/admin/realms").rstrip("/")
    role_mapper_url = f"{role_mapper_base_url}/users/{user_id}/role-mappings/realm"

    async with httpx.AsyncClient() as client:
        _logger.debug("Requesting roles for user %s from %s", user_id, role_mapper_url)

        response = await client.get(
            role_mapper_url, headers={"Authorization": f"Bearer {admin_token}"}
        )

        response.raise_for_status()
        return response.json()


async def get_authenticated_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    settings: Settings = Depends(get_settings),
    fetch_roles: bool = False,
) -> dict:
    """Authenticate a user using their bearer token and optionally fetch their Keycloak roles.
    Returns user info and token, with roles if requested.
    Raises HTTPException if authentication fails."""

    try:
        token = credentials.credentials
        client = await get_service_client(settings)
        user = await client.auth.get_user(token)
        result = {"token": token, "user": user}

        if not fetch_roles:
            return result

        user_metadata = user.user.user_metadata
        keycloak_user_id = user_metadata["provider_id"]
        keycloak_url = user_metadata["iss"]

        realm_client_token = await get_keycloak_token(
            keycloak_url,
            settings.keycloak_client_id,
            settings.keycloak_client_secret,
        )

        roles = await get_keycloak_user_roles(
            keycloak_url, realm_client_token, keycloak_user_id
        )

        result["keycloak_roles"] = roles

        return result
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))


async def get_authenticated_user_with_roles(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    settings: Settings = Depends(get_settings),
) -> dict:
    """Convenience wrapper to get authenticated user with their Keycloak roles included."""

    return await get_authenticated_user(credentials, settings, fetch_roles=True)


CurrentUser = Annotated[dict, Depends(get_authenticated_user)]
CurrentUserWithRoles = Annotated[dict, Depends(get_authenticated_user_with_roles)]


async def get_service_client(settings: Settings = Depends(get_settings)) -> AsyncClient:
    """Create a Supabase client with service role (admin) privileges.
    This client bypasses Row Level Security and has full database access.
    Should only be used for admin/service operations."""

    client = await create_async_client(
        settings.supabase_url,
        settings.supabase_key,
        options=ClientOptions(),
    )

    return client


async def get_user_client(
    current_user: CurrentUser,
    settings: Settings = Depends(get_settings),
) -> AsyncClient:
    """Create a Supabase client with user context.
    This client respects Row Level Security policies based on the user's token."""

    client = await create_async_client(
        settings.supabase_url,
        settings.supabase_key,
        options=ClientOptions(
            headers={"Authorization": f"Bearer {current_user['token']}"}
        ),
    )

    return client


ServiceClient = Annotated[AsyncClient, Depends(get_service_client)]
UserClient = Annotated[AsyncClient, Depends(get_user_client)]


@app.get("/health")
async def health_check():
    """Basic health check endpoint that returns service status and current timestamp."""

    return {"status": "healthy", "timestamp": int(time.time())}


@app.get("/whoami")
async def whoami_with_roles(current_user: CurrentUserWithRoles):
    """Return authenticated user's information including their Keycloak roles."""

    return current_user


@app.post("/report-request")
async def report_request(supabase: UserClient, current_user: CurrentUser):
    """Create a new report request."""

    response = (
        await supabase.table("report_requests")
        .insert(
            {
                "user_id": current_user["user"].user.id,
                "description": f"Request generated at {datetime.datetime.now().isoformat()} for testing purposes",
            }
        )
        .execute()
    )

    return response.data


@app.get("/report-request")
async def report_request(supabase: UserClient, current_user: CurrentUser):
    """Get all report requests for the current user."""

    response = (
        await supabase.table("report_requests")
        .select("*")
        .eq("user_id", current_user["user"].user.id)
        .execute()
    )

    return response.data


# Example protected endpoint using service role
@app.get("/admin/users")
async def list_all_users(supabase: ServiceClient):
    """List all users in the system. Requires admin privileges."""

    # Check the admin role here?
    response = (
        await supabase.table("users").select("id, email, created_at, role").execute()
    )
    return response.data
