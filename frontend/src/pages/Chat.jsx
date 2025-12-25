import React, { useEffect, useRef, useState } from "react";
import { useNavigate, useOutletContext, useParams, useSearchParams } from "react-router-dom";
import { apiFetch } from "../api.js";

export default function Chat({ isNew = false }) {
  const nav = useNavigate();
  const { chatId } = useParams();
  const [searchParams] = useSearchParams();
  const { models, reloadAll, projects } = useOutletContext();

  const [currentChat, setCurrentChat] = useState(null);
  const [messages, setMessages] = useState([]);
  const [draft, setDraft] = useState("");
  const [selectedModel, setSelectedModel] = useState(models[0]?.name || "clown 1.3");
  const bottomRef = useRef(null);
  const defaultProjectId = searchParams.get("projectId");

  const isNewRoute = isNew || chatId === "new";

  useEffect(() => {
    if (isNewRoute) {
      setCurrentChat(null);
      setMessages([]);
      if (models[0]?.name) setSelectedModel(models[0].name);
      return;
    }

    (async () => {
      const all = await apiFetch("/api/chats");
      const found = all.find((c) => c.id === chatId) || null;
      setCurrentChat(found);

      if (found?.model_name) {
        setSelectedModel(found.model_name);
      } else if (models[0]?.name) {
        setSelectedModel(models[0].name);
      }

      if (!found) {
        setMessages([]);
        return;
      }

      const msgs = await apiFetch(`/api/chats/${chatId}/messages?limit=200`);
      setMessages(msgs);
    })().catch(() => {
      setMessages([]);
    });
  }, [chatId, isNewRoute, models]);

  async function ensureChat() {
    if (!isNewRoute) return chatId;
    const created = await apiFetch("/api/chats", {
      method: "POST",
      body: JSON.stringify({
        title: "New chat",
        model_name: selectedModel,
        project_id: defaultProjectId || null,
      }),
    });
    await reloadAll();
    nav(`/app/chat/${created.id}`, { replace: true });
    return created.id;
  }

  async function onSend(e) {
    e.preventDefault();
    const text = draft.trim();
    if (!text) return;

    const id = await ensureChat();
    const createdMsgs = await apiFetch(`/api/chats/${id}/messages`, {
      method: "POST",
      body: JSON.stringify({ content: text }),
    });
    setMessages((prev) => [...prev, ...createdMsgs]);
    setDraft("");
    if (!currentChat || currentChat.title === "New chat") {
      const cleaned = text.replace(/\s+/g, " ").trim();
      const title = cleaned ? (cleaned.length > 60 ? `${cleaned.slice(0, 60)}…` : cleaned) : "New chat";
      await apiFetch(`/api/chats/${id}`, {
        method: "PATCH",
        body: JSON.stringify({ title }),
      }).catch(() => {});
      setCurrentChat((prev) => (prev ? { ...prev, title } : prev));
    }
    await reloadAll();
  }

  async function onModelChange(next) {
    setSelectedModel(next);
    if (!currentChat) return;
    await apiFetch(`/api/chats/${currentChat.id}`, {
      method: "PATCH",
      body: JSON.stringify({ model_name: next }),
    });
    await reloadAll();
  }

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const headerTitle = currentChat?.title || "New chat";
  const chatMissing = !isNewRoute && !currentChat;
  const projectName = currentChat?.project_id
    ? projects.find((p) => String(p.id) === String(currentChat.project_id))?.name
    : null;

  return (
    <div className="chatPage">
      <div className="topbar" style={{ borderBottom: "1px solid var(--border)" }}>
        <div className="topbarTitle">{headerTitle}</div>
        <div className="topbarRight">
          {projectName && <span className="badge">{projectName}</span>}
          <select className="select selectModel" value={selectedModel} onChange={(e) => onModelChange(e.target.value)}>
            {models.map((m) => (
              <option key={m.id} value={m.name}>{m.name}</option>
            ))}
          </select>
          <span className="badge">model</span>
        </div>
      </div>

      <div className="chatMessages">
        <div className="chatShell">
          {chatMissing ? (
            <div className="msg">
              <div className="msgHeader">Chat not found</div>
              <div className="msgBody">
                This chat is unavailable. Start a new one to keep going.
              </div>
            </div>
          ) : messages.length === 0 ? (
            <div className="msg">
              <div className="msgHeader">ClownGPT</div>
              <div className="msgBody">No messages yet. Say hi to start the conversation.</div>
            </div>
          ) : (
            messages.map((m) => (
              <div className="msg" key={m.id}>
                <div className="msgHeader">{m.sender_type === "user" ? "You" : "ClownGPT"}</div>
                <div className="msgBody">{m.content}</div>
              </div>
            ))
          )}
          <div ref={bottomRef} />
        </div>
      </div>

      <div className="composerWrap">
        <form className="composer" onSubmit={onSend}>
          <input className="input" value={draft} onChange={(e) => setDraft(e.target.value)} placeholder="Message ClownGPT..." />
          <button className="btn btnAccent" type="submit">Send</button>
        </form>
        <div className="smallNote">Messages are stored per chat. Switch model above any time.</div>
      </div>
    </div>
  );
}
