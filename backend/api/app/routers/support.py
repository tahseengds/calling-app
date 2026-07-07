import secrets
from pathlib import Path
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, Response, status
from fastapi.responses import RedirectResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from fastapi.templating import Jinja2Templates
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.dependencies import get_admin_user, get_current_user, get_db, rate_limit
from app.models.user import User
from app.schemas.support import (
    SupportFeedbackRequest,
    SupportFeedbackResponse,
    SupportRequestList,
    SupportStatus,
)
from app.services import support_service
from app.utils.security import verify_password

router = APIRouter()

templates = Jinja2Templates(
    directory=str(Path(__file__).resolve().parents[1] / "templates")
)

# Browser-friendly auth for the HTML admin page. auto_error=False so we can
# return a 401 with a WWW-Authenticate header ourselves, which makes the
# browser show its native username/password dialog.
_basic = HTTPBasic(auto_error=False)


async def _is_admin_basic(
    db: AsyncSession, credentials: HTTPBasicCredentials | None
) -> bool:
    """
    Validate HTTP Basic credentials for the support-admin HTML page.

    Username must be an email in ADMIN_EMAILS. The password matches if it
    equals the shared ADMIN_PANEL_PASSWORD (when configured) OR the admin's
    own Lumio account password.
    """
    if credentials is None:
        return False
    email = credentials.username.strip().lower()
    if not email or email not in settings.admin_emails:
        return False

    # Option A: shared panel password (constant-time compare).
    panel = settings.ADMIN_PANEL_PASSWORD
    if panel and secrets.compare_digest(credentials.password, panel):
        return True

    # Option B: the admin's own account password.
    result = await db.execute(
        select(User).where(func.lower(User.email) == email)
    )
    user = result.scalar_one_or_none()
    if user and user.is_active and user.password_hash:
        return verify_password(credentials.password, user.password_hash)
    return False


def _basic_challenge() -> Response:
    """401 with WWW-Authenticate so the browser shows its login dialog."""
    return Response(
        content="Authentication required.",
        status_code=status.HTTP_401_UNAUTHORIZED,
        headers={"WWW-Authenticate": 'Basic realm="Lumio Support Admin"'},
    )


@router.post(
    "/feedback",
    response_model=SupportFeedbackResponse,
    status_code=status.HTTP_201_CREATED,
)
async def submit_feedback(
    req: SupportFeedbackRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    # Bound how fast a single user can create support rows (unbounded DB growth).
    _rl: None = Depends(rate_limit("submit_feedback", 10, 60)),
) -> SupportFeedbackResponse:
    return await support_service.submit_feedback(db, current_user, req)


# ── Admin: view submitted support requests ───────────────────────────────────
# Gated by get_admin_user (ADMIN_EMAILS env). Two shapes: JSON for tooling and
# a rendered HTML table for eyeballing in a browser.

@router.get("/requests", response_model=SupportRequestList)
async def list_support_requests(
    limit: int = Query(default=200, ge=1, le=1000),
    offset: int = Query(default=0, ge=0),
    _admin: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db),
) -> SupportRequestList:
    return await support_service.list_requests(db, limit=limit, offset=offset)


@router.get("/requests/view")
async def view_support_requests(
    request: Request,
    limit: int = Query(default=200, ge=1, le=1000),
    offset: int = Query(default=0, ge=0),
    credentials: HTTPBasicCredentials | None = Depends(_basic),
    db: AsyncSession = Depends(get_db),
):
    # Browser-openable: gate with HTTP Basic so the browser shows a login
    # prompt (a raw GET can't carry a Bearer token). On failure, return 401
    # with WWW-Authenticate so the browser re-prompts.
    if not await _is_admin_basic(db, credentials):
        return _basic_challenge()
    data = await support_service.list_requests(db, limit=limit, offset=offset)
    return templates.TemplateResponse(
        request=request,
        name="support_requests.html",
        context={"data": data},
    )


@router.post("/requests/{request_id}/status")
async def set_support_request_status(
    request_id: UUID,
    new_status: SupportStatus = Query(..., alias="status"),
    credentials: HTTPBasicCredentials | None = Depends(_basic),
    db: AsyncSession = Depends(get_db),
):
    """
    Admin-only triage: move a request to open / in_progress / resolved.

    Same HTTP Basic gate as the HTML view, so the status buttons on that page
    work with the browser's stored credentials. After updating we 303-redirect
    back to the view (POST/redirect/GET) so a refresh doesn't re-submit.
    """
    if not await _is_admin_basic(db, credentials):
        return _basic_challenge()
    admin_email = credentials.username.strip().lower()
    await support_service.update_status(db, request_id, new_status, admin_email)
    return RedirectResponse(
        url="/api/support/requests/view",
        status_code=status.HTTP_303_SEE_OTHER,
    )
