from fastapi import APIRouter

from service_api.auth.dependencies import (
    AuthenticatedUserWithRolesDep,
    ServiceClientDep,
)

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/users")
async def list_all_users(
    supabase: ServiceClientDep, current_user: AuthenticatedUserWithRolesDep
):
    """List all users in the system. Requires admin privileges."""

    current_user.raise_if_not_admin()
    response = await supabase.table("private_table").select("*").execute()
    return response.data
