import os
import random
import threading
from datetime import datetime, timedelta

import requests
from faker import Faker
from uuid import uuid4
import logging


BASE_URL = os.getenv("SEED_BASE_URL", "http://localhost:8000")
ADMIN_USERNAME = os.getenv("SEED_ADMIN_USER", "admin")
ADMIN_PASSWORD = os.getenv("SEED_ADMIN_PASS", "admin")

USER_COUNT = int(os.getenv("SEED_USERS", "30"))
PROJECTS_RANGE = tuple(int(x) for x in os.getenv("SEED_PROJECTS_RANGE", "2,5").split(","))
CHATS_PER_PROJECT_RANGE = tuple(int(x) for x in os.getenv("SEED_CHATS_PER_PROJECT_RANGE", "3,8").split(","))
MSGS_PER_CHAT_RANGE = tuple(int(x) for x in os.getenv("SEED_MSGS_PER_CHAT_RANGE", "8,20").split(","))
UNASSIGNED_CHATS_RANGE = tuple(int(x) for x in os.getenv("SEED_UNASSIGNED_CHATS_RANGE", "2,6").split(","))

faker = Faker()
Faker.seed(1234)
random.seed(1234)
logger = logging.getLogger("seed")
logger.setLevel(logging.INFO)
handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter("%(asctime)s [seed] %(levelname)s %(message)s"))
logger.addHandler(handler)


def _login(username: str, password: str) -> tuple[str, str]:
    """Authenticate and return (token, user_id)."""
    r = requests.post(
        f"{BASE_URL}/api/auth/login",
        json={"username": username, "password": password},
        timeout=10,
    )
    r.raise_for_status()
    token = r.json()["access_token"]
    me = requests.get(f"{BASE_URL}/api/auth/me", headers={"Authorization": f"Bearer {token}"}, timeout=10)
    me.raise_for_status()
    user_id = me.json()["id"]
    return token, user_id


def _register(username: str, email: str, password: str) -> str:
    """Register a user and return access token."""
    r = requests.post(
        f"{BASE_URL}/api/auth/register",
        json={"username": username, "email": email, "password": password},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()["access_token"]


def _get_or_create_user(username: str, email: str, password: str) -> tuple[str, str]:
    """Register or login existing user, returning (token, user_id)."""
    try:
        token = _register(username, email, password)
        me = requests.get(f"{BASE_URL}/api/auth/me", headers={"Authorization": f"Bearer {token}"}, timeout=10)
        me.raise_for_status()
        return token, me.json()["id"]
    except requests.HTTPError as e:
        if e.response is not None and e.response.status_code in (400, 401, 409):
            # user might already exist, try login
            token, uid = _login(username, password)
            return token, uid
        raise


def _get_models(token: str) -> list[str]:
    """Return available model names."""
    r = requests.get(f"{BASE_URL}/api/models", headers={"Authorization": f"Bearer {token}"}, timeout=5)
    r.raise_for_status()
    data = r.json()
    return [m["name"] for m in data] or ["clown 1.3"]


def _seed():
    """Populate database with realistic data through batch-import."""
    try:
        admin_token, _ = _login(ADMIN_USERNAME, ADMIN_PASSWORD)
    except Exception:
        logger.exception("Failed to login as admin")
        return

    try:
        models = _get_models(admin_token)
        users: list[dict] = []

        # Создаем пользователей
        for _ in range(USER_COUNT):
            username = faker.unique.user_name()
            email = faker.unique.email()
            password = "Passw0rd!"

            try:
                token, user_id = _get_or_create_user(username, email, password)
                users.append({"id": user_id, "username": username})
            except Exception:
                logger.warning("Skip user create/login %s", username)
                continue

        projects_payload = []
        chats_payload = []
        messages_payload = []

        for user in users:
            project_num = random.randint(*PROJECTS_RANGE)
            user_projects = []

            for _ in range(project_num):
                pid = str(uuid4())
                user_projects.append(pid)
                projects_payload.append(
                    {
                        "id": pid,
                        "name": faker.company(),
                        "description": faker.catch_phrase(),
                        "visibility": "private",
                        "owner_user_id": user["id"],
                        "organization_id": None,
                    }
                )

            # chats per project
            for pid in user_projects:
                chats_num = random.randint(*CHATS_PER_PROJECT_RANGE)
                for _ in range(chats_num):
                    chat_id = str(uuid4())
                    title = faker.sentence(nb_words=4).rstrip(".")
                    chats_payload.append(
                        {
                            "id": chat_id,
                            "title": title,
                            "model_name": random.choice(models),
                            "owner_user_id": user["id"],
                            "project_id": pid,
                        }
                    )
                    msg_num = random.randint(*MSGS_PER_CHAT_RANGE)
                    for _ in range(msg_num):
                        sender_type = "user" if random.random() < 0.7 else "assistant"
                        sender_user_id = user["id"] if sender_type == "user" else None
                        messages_payload.append(
                            {
                                "chat_id": chat_id,
                                "sender_user_id": sender_user_id,
                                "sender_type": sender_type,
                                "content": faker.paragraph(nb_sentences=2),
                                "created_at": (datetime.utcnow() - timedelta(minutes=random.randint(0, 60 * 24 * 14))).isoformat(),
                            }
                        )

            # unassigned chats
            extra_chats = random.randint(*UNASSIGNED_CHATS_RANGE)
            for _ in range(extra_chats):
                chat_id = str(uuid4())
                title = faker.bs().title()
                chats_payload.append(
                    {
                        "id": chat_id,
                        "title": title,
                        "model_name": random.choice(models),
                        "owner_user_id": user["id"],
                        "project_id": None,
                    }
                )
                msg_num = random.randint(*MSGS_PER_CHAT_RANGE)
                for _ in range(msg_num):
                    sender_type = "user" if random.random() < 0.7 else "assistant"
                    sender_user_id = user["id"] if sender_type == "user" else None
                    messages_payload.append(
                        {
                            "chat_id": chat_id,
                            "sender_user_id": sender_user_id,
                            "sender_type": sender_type,
                            "content": faker.paragraph(nb_sentences=2),
                            "created_at": (datetime.utcnow() - timedelta(minutes=random.randint(0, 60 * 24 * 14))).isoformat(),
                        }
                    )

        payload = {
            "projects": projects_payload,
            "chats": chats_payload,
            "messages": messages_payload,
        }

        if projects_payload or chats_payload or messages_payload:
            try:
                r = requests.post(f"{BASE_URL}/api/batch-import", json=payload, timeout=60)
                r.raise_for_status()
                logger.info("Seeded: %s projects, %s chats, %s messages", len(projects_payload), len(chats_payload), len(messages_payload))
            except Exception:
                logger.exception("Batch import failed")
    except Exception:
        logger.exception("Seed failed")
        return


def run_seed_if_enabled():
    """Start seeding in background thread on startup."""
    threading.Thread(target=_seed, daemon=True).start()
