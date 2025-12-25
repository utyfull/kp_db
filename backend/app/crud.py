from sqlalchemy.orm import Session
from sqlalchemy import select, text
from uuid import UUID

from .models import (
    User,
    LLMModel,
    Organization,
    OrganizationMember,
    Chat,
    Message,
)
from .timeutil import utcnow
from . import llm


def set_actor(db: Session, user_id: UUID) -> None:
    db.execute(
        text("SELECT set_config('clown_gpt.current_user_id', :v, true)"),
        {"v": str(user_id)},
    )


def ensure_personal_org(db: Session, user: User) -> Organization:
    org = (
        db.execute(
            select(Organization)
            .join(OrganizationMember, OrganizationMember.organization_id == Organization.id)
            .where(OrganizationMember.user_id == user.id)
        )
        .scalar_one_or_none()
    )
    if org:
        return org

    now = utcnow()
    slug = user.username.lower()

    org = Organization(
        slug=slug,
        name=f"{user.username}'s org",
        owner_user_id=user.id,
        billing_email=user.email,
        plan="free",
        is_active=True,
        created_at=now,
        updated_at=now,
        settings={"darkOnly": True},
    )
    db.add(org)
    db.flush()

    db.add(
        OrganizationMember(
            organization_id=org.id,
            user_id=user.id,
            member_role="owner",
            can_billing=True,
            joined_at=now,
            invited_by=None,
            is_active=True,
        )
    )
    return org


def get_active_model_by_name(db: Session, model_name: str) -> LLMModel:
    m = db.execute(
        select(LLMModel).where(LLMModel.name == model_name, LLMModel.is_active == True)
    ).scalar_one_or_none()
    if not m:
        raise ValueError("Model not found or inactive")
    return m


def ensure_chat_member_owner(db: Session, chat_id, user_id) -> None:
    db.execute(
        text(
            """
            INSERT INTO chat_members(chat_id, user_id, member_role, muted, joined_at)
            VALUES (:c, :u, 'owner', false, now())
            ON CONFLICT (chat_id, user_id) DO NOTHING
            """
        ),
        {"c": str(chat_id), "u": str(user_id)},
    )


def ensure_project_member_owner(db: Session, project_id, user_id) -> None:
    db.execute(
        text(
            """
            INSERT INTO project_members(project_id, user_id, member_role, can_invite, is_favorite, joined_at)
            VALUES (:p, :u, 'owner', true, true, now())
            ON CONFLICT (project_id, user_id) DO NOTHING
            """
        ),
        {"p": str(project_id), "u": str(user_id)},
    )


def add_message_with_assistant(db: Session, chat: Chat, user: User, content: str) -> list[Message]:
    """
    Persist a user message, call the LLM (OpenAI if configured) and persist the assistant reply.
    Falls back to an offline stub if the LLM is unavailable.
    """
    now = utcnow()

    # Derive a title for fresh chats from the first user prompt
    if chat.title.strip().lower().startswith("new chat"):
        trimmed = " ".join(content.strip().split())
        if trimmed:
            chat.title = (trimmed[:60] + ("…" if len(trimmed) > 60 else ""))

    user_msg = Message(
        chat_id=chat.id,
        sender_user_id=user.id,
        sender_type="user",
        content=content,
        token_input=0,
        token_output=0,
        cost_estimated=0,
        meta={"source": "ui"},
        created_at=now,
    )
    db.add(user_msg)
    db.flush()

    recent = (
        db.execute(
            select(Message)
            .where(Message.chat_id == chat.id, Message.deleted_at.is_(None))
            .order_by(Message.id.desc())
            .limit(15)
        )
        .scalars()
        .all()
    )
    # reverse to chronological order for the prompt
    history = list(reversed(recent))

    model_name = (
        db.execute(select(LLMModel.name).where(LLMModel.id == chat.model_id)).scalar_one_or_none()
        or "gpt-3.5-turbo"
    )
    assistant_text = llm.generate_reply(model_name=model_name, history=history, user_input=content)

    bot_msg = Message(
        chat_id=chat.id,
        sender_user_id=None,
        sender_type="assistant",
        content=assistant_text,
        token_input=0,
        token_output=0,
        cost_estimated=0,
        meta={"source": "llm"},
        created_at=utcnow(),
    )
    db.add(bot_msg)
    db.flush()

    chat.updated_at = utcnow()

    return [user_msg, bot_msg]
