import datetime
import logging
import time
from functools import lru_cache
from importlib.metadata import version
from typing import Annotated

import httpx
from fastapi import Depends, FastAPI, File, HTTPException, UploadFile, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from gotrue.types import UserResponse
from pydantic import BaseModel
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
    admin_role_name: str = "relife_admin"
    bucket_name: str = "example_bucket"


@lru_cache
def get_settings():
    """Get cached application settings."""

    return Settings()


SettingsDep = Annotated[Settings, Depends(get_settings)]


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


class KeycloakRole(BaseModel):
    id: str
    name: str
    description: str | None = None
    composite: bool | None = None
    clientRole: bool | None = None
    containerId: str | None = None


class AuthenticatedUser(BaseModel):
    token: str
    user: UserResponse
    keycloak_roles: list[KeycloakRole] | None = None

    @property
    def has_admin_role(self) -> bool:
        if not self.keycloak_roles:
            return False

        settings = get_settings()

        return any(
            role.name == settings.admin_role_name for role in self.keycloak_roles
        )

    @property
    def user_id(self) -> str:
        return self.user.user.id

    @property
    def email(self) -> str | None:
        return self.user.user.email

    def raise_if_not_admin(self):
        if not self.has_admin_role:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="User does not have admin role",
            )


async def _get_authenticated_user(
    settings: SettingsDep,
    credentials: HTTPAuthorizationCredentials = Depends(security),
    fetch_roles: bool = False,
) -> AuthenticatedUser:
    """Authenticates user and optionally fetches their Keycloak roles."""

    try:
        token = credentials.credentials
        client = await get_service_client(settings)
        user = await client.auth.get_user(token)
        result = AuthenticatedUser(token=token, user=user)

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

        result.keycloak_roles = [KeycloakRole(**role) for role in roles]

        return result
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))


async def get_authenticated_user_without_roles(
    settings: SettingsDep,
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> AuthenticatedUser:
    """Authenticates user without fetching Keycloak roles."""

    return await _get_authenticated_user(
        settings=settings, credentials=credentials, fetch_roles=False
    )


async def get_authenticated_user_with_roles(
    settings: SettingsDep,
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> AuthenticatedUser:
    """Authenticates user and fetches their Keycloak roles."""

    return await _get_authenticated_user(
        settings=settings, credentials=credentials, fetch_roles=True
    )


AuthenticatedUser = Annotated[
    AuthenticatedUser, Depends(get_authenticated_user_without_roles)
]

AuthenticatedUserWithRoles = Annotated[
    AuthenticatedUser, Depends(get_authenticated_user_with_roles)
]


async def get_service_client(settings: SettingsDep) -> AsyncClient:
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
    current_user: AuthenticatedUser, settings: SettingsDep
) -> AsyncClient:
    """Create a Supabase client with user context.
    This client respects Row Level Security policies based on the user's token."""

    client = await create_async_client(
        settings.supabase_url,
        settings.supabase_key,
        options=ClientOptions(
            headers={"Authorization": f"Bearer {current_user.token}"}
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
async def whoami_with_roles(
    current_user: AuthenticatedUserWithRoles,
) -> AuthenticatedUser:
    """Return authenticated user's information including their Keycloak roles."""

    return current_user


@app.post("/report-request")
async def create_report_request(supabase: UserClient, current_user: AuthenticatedUser):
    """Create a new report request. This endpoint respects Row Level Security."""

    description = f"Request generated at {datetime.datetime.now().isoformat()} for testing purposes"

    response = (
        await supabase.table("report_requests")
        .insert(
            {
                "user_id": current_user.user_id,
                "description": description,
            }
        )
        .execute()
    )

    return response.data


@app.get("/report-request")
async def list_report_requests(supabase: UserClient, current_user: AuthenticatedUser):
    """Get all report requests for the current user. This endpoint respects Row Level Security."""

    response = (
        await supabase.table("report_requests")
        .select("*")
        .eq("user_id", current_user.user_id)
        .execute()
    )

    return response.data


@app.get("/admin/users")
async def list_all_users(
    supabase: ServiceClient, current_user: AuthenticatedUserWithRoles
):
    """List all users in the system. Requires admin privileges."""

    current_user.raise_if_not_admin()
    response = await supabase.table("private_table").select("*").execute()
    return response.data


class FileUploadResponse(BaseModel):
    """Response model for file upload endpoint."""

    message: str
    path: str
    public_url: str


class StorageFileInfo(BaseModel):
    """Model representing information about a stored file."""

    name: str
    size: int
    created_at: str
    public_url: str


@app.post("/storage", response_model=FileUploadResponse)
async def upload_file(
    supabase: UserClient,
    current_user: AuthenticatedUser,
    settings: SettingsDep,
    file: UploadFile = File(...),
):
    """Upload a file to Supabase Storage. Files are stored in a user-specific folder."""

    file_path = f"{current_user.user_id}/{file.filename}"
    file_content = await file.read()

    try:
        response = await supabase.storage.from_(settings.bucket_name).upload(
            path=file_path,
            file=file_content,
            file_options={"content-type": file.content_type},
        )

        _logger.debug("Uploaded file: %s", response.full_path)

        public_url = await supabase.storage.from_(settings.bucket_name).get_public_url(
            file_path
        )

        return FileUploadResponse(
            message="File uploaded successfully",
            path=file_path,
            public_url=public_url,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to upload file: {str(e)}",
        )


@app.get("/storage", response_model=list[StorageFileInfo])
async def list_files(
    supabase: UserClient,
    current_user: AuthenticatedUser,
    settings: SettingsDep,
):
    """List all files uploaded by the current user."""

    try:
        response = await supabase.storage.from_(settings.bucket_name).list(
            current_user.user_id
        )

        files = []

        for file in response:
            public_url = await supabase.storage.from_(
                settings.bucket_name
            ).get_public_url(f"{current_user.user_id}/{file['name']}")

            files.append(
                StorageFileInfo(
                    name=file["name"],
                    size=file["metadata"]["size"],
                    created_at=file["created_at"],
                    public_url=public_url,
                )
            )

        return files
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to list files: {str(e)}",
        )
