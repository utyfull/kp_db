from pydantic import BaseModel, EmailStr
from typing import Optional, List, Literal
from uuid import UUID
from datetime import datetime

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"

class UserMe(BaseModel):
    id: UUID
    username: str
    email: str
    role: str

class RegisterRequest(BaseModel):
    username: str
    email: EmailStr
    password: str

class LoginRequest(BaseModel):
    username: str
    password: str

class ModelRead(BaseModel):
    id: int
    name: str
    is_active: bool
    context_window: int

class ProjectCreate(BaseModel):
    name: str
    description: str = ""
    visibility: str = "private"

class ProjectRead(BaseModel):
    id: UUID
    name: str
    description: str
    visibility: str
    owner_user_id: UUID
    organization_id: Optional[UUID]
    created_at: datetime
    updated_at: datetime

class ChatCreate(BaseModel):
    title: str
    model_name: str
    project_id: Optional[UUID] = None

class ChatRead(BaseModel):
    id: UUID
    title: str
    status: str
    pinned: bool
    model_id: int
    model_name: str
    project_id: Optional[UUID]
    created_at: datetime
    updated_at: datetime

class ChatUpdate(BaseModel):
    title: Optional[str] = None
    pinned: Optional[bool] = None
    status: Optional[str] = None
    model_name: Optional[str] = None

class MessageRead(BaseModel):
    id: int
    chat_id: UUID
    sender_type: str
    sender_user_id: Optional[UUID]
    content: str
    created_at: datetime

class MessageCreate(BaseModel):
    content: str

class UserListItem(BaseModel):
    id: UUID
    username: str
    role: str

class PlanResponse(BaseModel):
    plan: str

class PlanUpdate(BaseModel):
    plan: Literal["free", "pro", "enterprise"]

# Batch import
class BatchProjectIn(BaseModel):
    id: Optional[UUID] = None
    name: str
    description: str = ""
    visibility: str = "private"
    owner_user_id: UUID
    organization_id: Optional[UUID] = None

class BatchChatIn(BaseModel):
    id: Optional[UUID] = None
    title: str
    model_name: str
    owner_user_id: UUID
    project_id: Optional[UUID] = None

class BatchMessageIn(BaseModel):
    chat_id: UUID
    sender_user_id: Optional[UUID] = None
    sender_type: str
    content: str
    created_at: Optional[datetime] = None

class BatchImportRequest(BaseModel):
    projects: List[BatchProjectIn] = []
    chats: List[BatchChatIn] = []
    messages: List[BatchMessageIn] = []

class BatchImportResult(BaseModel):
    projects_created: int
    chats_created: int
    messages_created: int
    errors: list[str] = []

# Reports
class UserActivityReport(BaseModel):
    user_id: UUID
    username: str
    role: str
    owned_chats: int
    user_messages: int
    assistant_messages: int

class ProjectSummaryReport(BaseModel):
    project_id: UUID
    name: str
    visibility: str
    chat_count: int
    message_count: int
    last_activity_at: Optional[datetime]

class DailyModelUsage(BaseModel):
    day: datetime
    model_name: Optional[str]
    calls: int
    tokens_in: int
    tokens_out: int
    cost: float
