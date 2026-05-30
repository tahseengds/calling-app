from pathlib import Path

from fastapi import APIRouter, Depends, Query, Request, status
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_admin_user, get_current_user, get_db
from app.models.user import User
from app.schemas.support import (
    SupportFeedbackRequest,
    SupportFeedbackResponse,
    SupportRequestList,
)
from app.services import support_service

router = APIRouter()

templates = Jinja2Templates(
    directory=str(Path(__file__).resolve().parents[1] / "templates")
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


@router.get("/requests/view", response_class=HTMLResponse)
async def view_support_requests(
    request: Request,
    limit: int = Query(default=200, ge=1, le=1000),
    offset: int = Query(default=0, ge=0),
    _admin: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db),
) -> HTMLResponse:
    data = await support_service.list_requests(db, limit=limit, offset=offset)
    return templates.TemplateResponse(
        request=request,
        name="support_requests.html",
        context={"data": data},
    )
