import React, { useEffect, useState } from "react";
import { Link, NavLink, Outlet, useNavigate } from "react-router-dom";
import { apiFetch, clearToken } from "../api.js";

export default function Shell() {
  const nav = useNavigate();

  const [me, setMe] = useState(null);
  const [models, setModels] = useState([]);
  const [projects, setProjects] = useState([]);
  const [chats, setChats] = useState([]);
  const [users, setUsers] = useState([]);
  const [plan, setPlan] = useState("free");

  async function loadAll() {
    const meData = await apiFetch("/api/auth/me");
    setMe(meData);

    const modelsData = await apiFetch("/api/models");
    setModels(modelsData);

    const projectsData = await apiFetch("/api/projects");
    setProjects(projectsData);

    const chatsData = await apiFetch("/api/chats");
    setChats(chatsData);

    setUsers([{ id: meData.id, username: meData.username, role: meData.role }]);

    try {
      const planData = await apiFetch("/api/org/plan");
      setPlan(planData.plan);
    } catch {
      setPlan("free");
    }
  }

  useEffect(() => {
    loadAll().catch(() => {
      clearToken();
      nav("/login");
    });
  }, []);

  async function createChat() {
    const defaultModel = models[0]?.name || "clown 1.3";
    const data = await apiFetch("/api/chats", {
      method: "POST",
      body: JSON.stringify({ title: "New chat", model_name: defaultModel, project_id: null }),
    });
    await loadAll();
    nav(`/app/chat/${data.id}`);
  }

  async function createProject() {
    const name = prompt("Project name");
    if (!name || !name.trim()) return;
    await apiFetch("/api/projects", {
      method: "POST",
      body: JSON.stringify({ name: name.trim(), description: "", visibility: "private" }),
    });
    await loadAll();
    nav(`/app/projects`);
  }

  function logout() {
    clearToken();
    nav("/login");
  }

  const visibleChats = chats.filter((c) => !c.project_id);

  return (
    <div className="container">
      <aside className="sidebar">
        <div className="brand">
          <ClownLogo />
          <div style={{ minWidth: 0 }}>
            <div className="brandTitle">ClownGPT</div>
            <div className="brandSub">Workspace</div>
          </div>
        </div>

        <div className="userRow stickyUser" style={{ cursor: "pointer" }} onClick={() => nav("/app/plan")}>
          <div className="userMeta">
            <div className="userName">{me?.username || "User"}</div>
            <div className="userRole">{me?.role || "Member"} · {plan}</div>
          </div>
          <button className="btn" style={{ width: "auto" }} onClick={(e) => { e.stopPropagation(); logout(); }}>Log out</button>
        </div>

        <div className="sidebarActions">
          <button className="btn btnAccent" onClick={createChat}>New chat</button>
          <button className="btn" onClick={createProject}>New project</button>
        </div>

        <div>
          <div className="sectionTitle">Navigation</div>
          <div className="list">
            <div className="listItem">
              <NavLink to="/app/settings" className={({ isActive }) => `listLink ${isActive ? "activeRow" : ""}`}>
                <span className="listLinkTitle">Settings</span>
              </NavLink>
              <span className="badge">&gt;</span>
            </div>
            <div className="listItem">
              <NavLink to="/app/plan" className={({ isActive }) => `listLink ${isActive ? "activeRow" : ""}`}>
                <span className="listLinkTitle">Plan</span>
              </NavLink>
              <span className="badge">{plan}</span>
            </div>
          </div>
        </div>

        <div className="sidebarScroll">
          <div>
            <div className="sectionTitle">Projects</div>
            <div className="list">
              <div className="listItem">
                <NavLink to="/app/projects" className={({ isActive }) => `listLink ${isActive ? "activeRow" : ""}`}>
                  <span className="listLinkTitle">All projects</span>
                </NavLink>
                <span className="badge">{projects.length}</span>
              </div>
            </div>
          </div>

          <div>
            <div className="sectionTitle">Chats</div>
            <div className="list chatList">
              <div className="listItem">
                <Link to="/app/chat/new" className="listLink">
                  <span className="listLinkTitle">Start a new chat</span>
                </Link>
                <span className="badge">+</span>
              </div>
              {visibleChats.map((c) => (
                <div className="listItem" key={c.id}>
                  <NavLink to={`/app/chat/${c.id}`} className={({ isActive }) => `listLink ${isActive ? "activeRow" : ""}`}>
                    <span className="listLinkTitle">{c.title}</span>
                  </NavLink>
                  <span className="badge">{c.model_name}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </aside>

      <main className="main">
        <div className="topbar">
          <div className="topbarTitle">ClownGPT</div>
          <div className="topbarRight">
            <span className="badge">Dark</span>
            <span className="badge">API</span>
          </div>
        </div>

        <div className="content">
          <Outlet context={{ me, models, projects, chats, plan, reloadAll: loadAll }} />
        </div>
      </main>
    </div>
  );
}

function ClownLogo() {
  return (
    <svg width="34" height="34" viewBox="0 0 64 64" aria-hidden="true">
      <circle cx="32" cy="32" r="30" fill="rgba(255,255,255,0.03)" stroke="rgba(255,255,255,0.10)" />
      <circle cx="32" cy="36" r="16" fill="rgba(255,255,255,0.03)" stroke="rgba(255,255,255,0.10)" />
      <circle cx="26.5" cy="33.5" r="2.6" fill="rgba(167,139,250,0.95)" />
      <circle cx="37.5" cy="33.5" r="2.6" fill="rgba(59,130,246,0.85)" />
      <circle cx="32" cy="39.5" r="5" fill="rgba(251,113,133,0.88)" />
      <path d="M24 45c2.5 3.2 5.3 4.8 8 4.8s5.5-1.6 8-4.8" fill="none" stroke="rgba(229,231,235,0.75)" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}
