import time
from functools import lru_cache
from importlib.metadata import version
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic_settings import BaseSettings
from supabase import Client, create_client
from supabase.client import ClientOptions


class Settings(BaseSettings):
    supabase_url: str
    # Service role key
    supabase_key: str


@lru_cache
def get_settings():
    return Settings()


def get_service_client(settings: Settings = Depends(get_settings)) -> Client:
    """Get Supabase client with service role (admin)"""

    return create_client(
        settings.supabase_url,
        settings.supabase_key,
        options=ClientOptions(
            auth={
                "auto_refresh_token": False,
                "persist_session": False,
            }
        ),
    )


def get_user_client(
    user_token: str,
    settings: Settings = Depends(get_settings),
) -> Client:
    """Get Supabase client with user context"""

    client = create_client(
        settings.supabase_url,
        settings.supabase_key,
        options=ClientOptions(
            auth={
                "auto_refresh_token": False,
                "persist_session": False,
            }
        ),
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


async def verify_token(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    settings: Settings = Depends(get_settings),
) -> dict:
    try:
        token = credentials.credentials
        client = get_service_client(settings)
        user = await client.auth.get_user(token)
        return {"token": token, "user": user}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
            headers={"WWW-Authenticate": "Bearer"},
        )


# Dependencies
ServiceClient = Annotated[Client, Depends(get_service_client)]
UserClient = Annotated[Client, Depends(get_user_client)]
CurrentUser = Annotated[dict, Depends(verify_token)]


@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": int(time.time())}


# Example protected endpoint using service role
@app.get("/admin/users")
async def list_all_users(supabase: ServiceClient):
    # Check the admin role here?
    response = (
        await supabase.table("users").select("id, email, created_at, role").execute()
    )

    return response.data


# Example endpoint acting on behalf of user
@app.get("/my-profile")
async def get_user_profile(
    current_user: CurrentUser,
    supabase: UserClient,
):
    response = (
        await supabase.table("profiles")
        .select("id, username, avatar_url")
        .eq("id", current_user["user"].id)
        .execute()
    )

    return response.data
