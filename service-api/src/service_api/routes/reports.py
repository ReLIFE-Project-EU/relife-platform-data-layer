import datetime

from fastapi import APIRouter

from service_api.auth.dependencies import AuthenticatedUserDep, UserClientDep

router = APIRouter(tags=["reports"])


@router.post("/report-request")
async def create_report_request(
    supabase: UserClientDep, current_user: AuthenticatedUserDep
):
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


@router.get("/report-request")
async def list_report_requests(
    supabase: UserClientDep, current_user: AuthenticatedUserDep
):
    """Get all report requests for the current user. This endpoint respects Row Level Security."""

    response = (
        await supabase.table("report_requests")
        .select("*")
        .eq("user_id", current_user.user_id)
        .execute()
    )

    return response.data
