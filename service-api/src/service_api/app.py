import logging
import time
from functools import lru_cache
from importlib.metadata import version
from typing import Annotated, Optional
from urllib.parse import urlparse

import httpx
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic_settings import BaseSettings
from supabase import AsyncClient, create_async_client
from supabase.client import ClientOptions


class Settings(BaseSettings):
    supabase_url: str
    # Service role key - this is a special API key with admin privileges that bypasses
    # Row Level Security (RLS) policies and has full access to the database. It should
    # only be used server-side and never exposed to clients.
    supabase_key: str
    keycloak_client_id: str
    keycloak_client_secret: str


@lru_cache
def get_settings():
    return Settings()


async def get_service_client(settings: Settings = Depends(get_settings)) -> AsyncClient:
    """Get Supabase client with service role (admin)"""

    client = await create_async_client(
        settings.supabase_url,
        settings.supabase_key,
        options=ClientOptions(),
    )

    return client


async def get_user_client(
    user_token: str,
    settings: Settings = Depends(get_settings),
) -> AsyncClient:
    """Get Supabase client with user context"""

    client = await create_async_client(
        settings.supabase_url,
        settings.supabase_key,
        options=ClientOptions(),
    )

    # Set the user's access token in the Authorization header
    client.auth.headers["Authorization"] = f"Bearer {user_token}"
    return client


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


async def get_keycloak_token(
    keycloak_url: str, client_id: str, client_secret: str
) -> str:
    """Get admin access token from Keycloak"""

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
    """Get user roles from Keycloak"""

    role_mapper_base_url = keycloak_url.replace("/realms", "/admin/realms").rstrip("/")
    role_mapper_url = f"{role_mapper_base_url}/users/{user_id}/role-mappings/realm"

    async with httpx.AsyncClient() as client:
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
    return await get_authenticated_user(credentials, settings, fetch_roles=True)


ServiceClient = Annotated[AsyncClient, Depends(get_service_client)]
UserClient = Annotated[AsyncClient, Depends(get_user_client)]
CurrentUser = Annotated[dict, Depends(get_authenticated_user)]
CurrentUserWithRoles = Annotated[dict, Depends(get_authenticated_user_with_roles)]


@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": int(time.time())}


@app.get("/whoami")
async def whoami(current_user: CurrentUser):
    return current_user


@app.get("/whoami-with-roles")
async def whoami_with_roles(current_user: CurrentUserWithRoles):
    return current_user


# Example protected endpoint using service role
@app.get("/admin/users")
async def list_all_users(supabase: ServiceClient):
    # Check the admin role here?
    response = (
        await supabase.table("users").select("id, email, created_at, role").execute()
    )
    return response.data
