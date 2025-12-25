import os
from uuid import UUID

from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError

from .db import get_db
from .models import User, UserProfile, LLMModel, Project, Chat, Message, Organization
from .schemas import (
    TokenResponse,
    RegisterRequest,
    LoginRequest,
    UserMe,
    ModelRead,
    ProjectCreate,
    ProjectRead,
    ChatCreate,
    ChatRead,
    ChatUpdate,
    MessageRead,
    MessageCreate,
    UserListItem,
    PlanResponse,
    PlanUpdate,
    BatchImportRequest,
    BatchImportResult,
    UserActivityReport,
    ProjectSummaryReport,
    DailyModelUsage,
)
from .security import (
    hash_password,
    verify_password,
    create_access_token,
    get_current_user,
    require_admin,
)
from .timeutil import utcnow
from . import crud, seed

app = FastAPI(title="ClownGPT API")

cors_origins = [o.strip() for o in os.getenv("CORS_ORIGINS", "http://localhost:5173").split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
def health():
    return {"status": "ok"}

@app.on_event("startup")
def _run_seed():
    seed.run_seed_if_enabled()

# ---------------- AUTH ----------------

@app.post("/api/auth/register", response_model=TokenResponse)
def register(payload: RegisterRequest, db: Session = Depends(get_db)):
    username = payload.username.strip()
    email = payload.email.strip().lower()

    if len(username) < 3:
        raise HTTPException(400, "Username too short")

    exists = db.execute(select(User).where(User.username == username)).scalar_one_or_none()
    if exists:
        raise HTTPException(409, "Username already exists")
    email_exists = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if email_exists:
        raise HTTPException(409, "Email already exists")

    now = utcnow()

    u = User(
        username=username,
        email=email,
        password_hash=hash_password(payload.password),
        role="member",
        is_active=True,
        email_verified=False,
        created_at=now,
        updated_at=now,
        settings={"theme": "dark"},
    )
    db.add(u)
    db.flush()

    db.add(
        UserProfile(
            user_id=u.id,
            display_name=username,
            bio="",
            avatar_url=None,
            locale="ru-RU",
            timezone="Europe/Moscow",
            preferences={"darkOnly": True},
            created_at=now,
            updated_at=now,
        )
    )

    crud.ensure_personal_org(db, u)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "User or email already exists")

    token = create_access_token(str(u.id))
    return TokenResponse(access_token=token)

@app.post("/api/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    u = db.execute(select(User).where(User.username == payload.username)).scalar_one_or_none()
    if not u or not u.is_active:
        raise HTTPException(401, "Invalid credentials")

    if not verify_password(payload.password, u.password_hash):
        raise HTTPException(401, "Invalid credentials")

    u.last_login_at = utcnow()
    u.updated_at = utcnow()

    crud.ensure_personal_org(db, u)
    db.commit()

    token = create_access_token(str(u.id))
    return TokenResponse(access_token=token)

@app.get("/api/auth/me", response_model=UserMe)
def me(user: User = Depends(get_current_user)):
    return UserMe(id=user.id, username=user.username, email=user.email, role=user.role)

# ---------------- MODELS ----------------

@app.get("/api/models", response_model=list[ModelRead])
def list_models(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    rows = db.execute(select(LLMModel).where(LLMModel.is_active == True).order_by(LLMModel.id)).scalars().all()
    return [ModelRead(id=m.id, name=m.name, is_active=m.is_active, context_window=m.context_window) for m in rows]

# ---------------- PLAN ----------------

ALLOWED_PLANS = {"free", "pro", "enterprise"}


def _get_primary_org(db: Session, user: User) -> Organization:
    org = (
        db.execute(select(Organization).where(Organization.owner_user_id == user.id).order_by(Organization.created_at))
        .scalar_one_or_none()
    )
    if not org:
        org = crud.ensure_personal_org(db, user)
        db.commit()
        db.refresh(org)
    return org


@app.get("/api/org/plan", response_model=PlanResponse)
def get_plan(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    org = _get_primary_org(db, user)
    return PlanResponse(plan=org.plan)


@app.post("/api/org/plan", response_model=PlanResponse)
def update_plan(payload: PlanUpdate, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    if payload.plan not in ALLOWED_PLANS:
        raise HTTPException(400, "Plan not allowed")
    org = _get_primary_org(db, user)
    org.plan = payload.plan
    org.updated_at = utcnow()
    db.commit()
    db.refresh(org)
    return PlanResponse(plan=org.plan)

# ---------------- BATCH IMPORT (service token protected) ----------------

@app.post("/api/batch-import", response_model=BatchImportResult, tags=["admin"])
def batch_import(payload: BatchImportRequest, dry_run: bool = False, db: Session = Depends(get_db)):
    created_projects = 0
    created_chats = 0
    created_messages = 0
    errors: list[str] = []
    now = utcnow()

    try:
        for p in payload.projects:
            try:
                proj = Project(
                    id=p.id,
                    organization_id=p.organization_id,
                    owner_user_id=p.owner_user_id,
                    name=p.name.strip(),
                    description=p.description or "",
                    visibility=p.visibility,
                    archived=False,
                    settings={"darkOnly": True},
                    created_at=now,
                    updated_at=now,
                    deleted_at=None,
                )
                db.add(proj)
                db.flush()
                crud.ensure_project_member_owner(db, proj.id, p.owner_user_id)
                created_projects += 1
            except Exception as e:
                db.rollback()
                errors.append(f"project {p.id}: {e}")
                db.begin()

        for c in payload.chats:
            try:
                model = crud.get_active_model_by_name(db, c.model_name)
                chat = Chat(
                    id=c.id,
                    project_id=c.project_id,
                    organization_id=None,
                    owner_user_id=c.owner_user_id,
                    title=c.title.strip() or "New chat",
                    status="active",
                    pinned=False,
                    model_id=model.id,
                    temperature=0.70,
                    max_output_tokens=1024,
                    system_prompt="",
                    chat_metadata={"batch": True},
                    created_at=now,
                    updated_at=now,
                    deleted_at=None,
                )
                db.add(chat)
                db.flush()
                crud.ensure_chat_member_owner(db, chat.id, c.owner_user_id)
                created_chats += 1
            except Exception as e:
                db.rollback()
                errors.append(f"chat {c.id}: {e}")
                db.begin()

        for m in payload.messages:
            try:
                msg = Message(
                    chat_id=m.chat_id,
                    sender_user_id=m.sender_user_id,
                    sender_type=m.sender_type,
                    content=m.content,
                    token_input=0,
                    token_output=0,
                    cost_estimated=0,
                    meta={"batch": True},
                    created_at=m.created_at or now,
                    edited_at=None,
                    deleted_at=None,
                )
                db.add(msg)
                created_messages += 1
            except Exception as e:
                db.rollback()
                errors.append(f"message in chat {m.chat_id}: {e}")
                db.begin()

        if dry_run:
            db.rollback()
        else:
            db.commit()
    except Exception:
        db.rollback()
        raise

    return BatchImportResult(
        projects_created=created_projects,
        chats_created=created_chats,
        messages_created=created_messages,
        errors=errors,
    )

# ---------------- REPORTS (service token protected) ----------------

@app.get("/api/reports/user-activity", response_model=list[UserActivityReport], tags=["reports"])
def report_user_activity(db: Session = Depends(get_db)):
    rows = db.execute(
        text(
            """
            SELECT user_id, username, role, owned_chats, user_messages, assistant_messages
            FROM view_user_activity
            ORDER BY user_messages DESC NULLS LAST
            """
        )
    ).all()
    return [UserActivityReport(**dict(r._mapping)) for r in rows]


@app.get("/api/reports/project-summary", response_model=list[ProjectSummaryReport], tags=["reports"])
def report_project_summary(db: Session = Depends(get_db)):
    rows = db.execute(
        text(
            """
            SELECT project_id, name, visibility, chat_count, message_count, last_activity_at
            FROM view_project_summary
            ORDER BY last_activity_at DESC NULLS LAST, chat_count DESC
            """
        )
    ).all()
    return [ProjectSummaryReport(**dict(r._mapping)) for r in rows]


@app.get("/api/reports/model-usage", response_model=list[DailyModelUsage], tags=["reports"])
def report_model_usage(db: Session = Depends(get_db)):
    rows = db.execute(
        text(
            """
            SELECT day, model_name, calls, tokens_in, tokens_out, cost
            FROM view_daily_model_usage
            ORDER BY day DESC, model_name
            """
        )
    ).all()
    return [DailyModelUsage(**dict(r._mapping)) for r in rows]

# ---------------- USERS (sidebar list) ----------------

@app.get("/api/users", response_model=list[UserListItem])
def list_users(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    rows = (
        db.execute(select(User).where(User.is_active == True).order_by(User.created_at.desc()).limit(20))
        .scalars()
        .all()
    )
    return [UserListItem(id=u.id, username=u.username, role=u.role) for u in rows]

# ---------------- PROJECTS ----------------

@app.get("/api/projects", response_model=list[ProjectRead])
def list_projects(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    rows = (
        db.execute(select(Project).where(Project.owner_user_id == user.id).order_by(Project.updated_at.desc()))
        .scalars()
        .all()
    )
    return rows

@app.post("/api/projects", response_model=ProjectRead)
def create_project(payload: ProjectCreate, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    crud.set_actor(db, user.id)

    now = utcnow()
    p = Project(
        organization_id=None,
        owner_user_id=user.id,
        name=payload.name.strip(),
        description=payload.description or "",
        visibility=payload.visibility,
        archived=False,
        settings={"darkOnly": True},
        created_at=now,
        updated_at=now,
        deleted_at=None,
    )
    db.add(p)
    db.flush()

    crud.ensure_project_member_owner(db, p.id, user.id)
    db.commit()
    db.refresh(p)
    return p

# ---------------- CHATS ----------------

@app.get("/api/chats", response_model=list[ChatRead])
def list_chats(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    chats = db.execute(select(Chat).where(Chat.owner_user_id == user.id).order_by(Chat.updated_at.desc())).scalars().all()
    models = {m.id: m.name for m in db.execute(select(LLMModel)).scalars().all()}

    return [
        ChatRead(
            id=c.id,
            title=c.title,
            status=c.status,
            pinned=c.pinned,
            model_id=c.model_id,
            model_name=models.get(c.model_id, "unknown"),
            project_id=c.project_id,
            created_at=c.created_at,
            updated_at=c.updated_at,
        )
        for c in chats
    ]

@app.post("/api/chats", response_model=ChatRead)
def create_chat(payload: ChatCreate, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    crud.set_actor(db, user.id)

    try:
        m = crud.get_active_model_by_name(db, payload.model_name)
    except ValueError:
        raise HTTPException(400, "Model not found")

    if payload.project_id:
        p = db.execute(select(Project).where(Project.id == payload.project_id, Project.owner_user_id == user.id)).scalar_one_or_none()
        if not p:
            raise HTTPException(403, "Project not found or not yours")

    now = utcnow()
    c = Chat(
        project_id=payload.project_id,
        organization_id=None,
        owner_user_id=user.id,
        title=(payload.title.strip() or "New chat"),
        status="active",
        pinned=False,
        model_id=m.id,
        temperature=0.70,
        max_output_tokens=1024,
        system_prompt="",
        chat_metadata={"ui": "clown-gpt"},
        created_at=now,
        updated_at=now,
        deleted_at=None,
    )
    db.add(c)
    db.flush()

    crud.ensure_chat_member_owner(db, c.id, user.id)
    db.commit()

    return ChatRead(
        id=c.id,
        title=c.title,
        status=c.status,
        pinned=c.pinned,
        model_id=c.model_id,
        model_name=m.name,
        project_id=c.project_id,
        created_at=c.created_at,
        updated_at=c.updated_at,
    )

@app.patch("/api/chats/{chat_id}", response_model=ChatRead)
def update_chat(chat_id: UUID, payload: ChatUpdate, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    crud.set_actor(db, user.id)

    c = db.execute(select(Chat).where(Chat.id == chat_id, Chat.owner_user_id == user.id)).scalar_one_or_none()
    if not c:
        raise HTTPException(404, "Chat not found")

    if payload.title is not None:
        c.title = payload.title.strip()
    if payload.pinned is not None:
        c.pinned = payload.pinned
    if payload.status is not None:
        c.status = payload.status
    if payload.model_name is not None:
        try:
            m = crud.get_active_model_by_name(db, payload.model_name)
        except ValueError:
            raise HTTPException(400, "Model not found")
        c.model_id = m.id

    c.updated_at = utcnow()
    db.commit()

    model_name = db.execute(select(LLMModel.name).where(LLMModel.id == c.model_id)).scalar_one()
    return ChatRead(
        id=c.id,
        title=c.title,
        status=c.status,
        pinned=c.pinned,
        model_id=c.model_id,
        model_name=model_name,
        project_id=c.project_id,
        created_at=c.created_at,
        updated_at=c.updated_at,
    )

# ---------------- MESSAGES ----------------

@app.get("/api/chats/{chat_id}/messages", response_model=list[MessageRead])
def list_messages(
    chat_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    limit: int = 50,
):
    c = db.execute(select(Chat).where(Chat.id == chat_id, Chat.owner_user_id == user.id)).scalar_one_or_none()
    if not c:
        raise HTTPException(404, "Chat not found")

    msgs = (
        db.execute(
            select(Message)
            .where(Message.chat_id == chat_id, Message.deleted_at.is_(None))
            .order_by(Message.id.asc())
            .limit(min(max(limit, 1), 200))
        )
        .scalars()
        .all()
    )

    return [
        MessageRead(
            id=m.id,
            chat_id=m.chat_id,
            sender_type=m.sender_type,
            sender_user_id=m.sender_user_id,
            content=m.content,
            created_at=m.created_at,
        )
        for m in msgs
    ]

@app.post("/api/chats/{chat_id}/messages", response_model=list[MessageRead])
def create_message(chat_id: UUID, payload: MessageCreate, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    crud.set_actor(db, user.id)

    c = db.execute(select(Chat).where(Chat.id == chat_id, Chat.owner_user_id == user.id)).scalar_one_or_none()
    if not c:
        raise HTTPException(404, "Chat not found")

    content = payload.content.strip()
    if not content:
        raise HTTPException(400, "Empty message")

    created = crud.add_message_with_assistant(db, c, user, content)
    db.commit()

    return [
        MessageRead(
            id=m.id,
            chat_id=m.chat_id,
            sender_type=m.sender_type,
            sender_user_id=m.sender_user_id,
            content=m.content,
            created_at=m.created_at,
        )
        for m in created
    ]
