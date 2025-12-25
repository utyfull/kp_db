import React, { useMemo } from "react";
import { Link, useNavigate, useOutletContext, useParams } from "react-router-dom";

export default function ProjectView() {
  const { projectId } = useParams();
  const { projects, chats } = useOutletContext();
  const nav = useNavigate();

  const project = useMemo(
    () => projects.find((p) => String(p.id) === String(projectId)) || null,
    [projects, projectId]
  );

  const linkedChats = useMemo(
    () =>
      chats.filter(
        (c) => String(c.project_id || "") === String(projectId) || String(c.project_id || "") === String(project?.id || "")
      ),
    [chats, projectId, project]
  );

  if (!project) {
    return (
      <div style={{ maxWidth: 920, margin: "0 auto" }}>
        <h2>Project not found</h2>
        <Link to="/app/projects" className="badge">Back to projects</Link>
      </div>
    );
  }

  return (
    <div className="pageScroll" style={{ maxWidth: 920, margin: "0 auto" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 6 }}>
        <Link to="/app/projects" className="badge">Back</Link>
        <h2 style={{ margin: 0 }}>{project.name}</h2>
        <button className="btn btnAccent" style={{ width: "auto", padding: "8px 12px" }} onClick={() => nav(`/app/chat/new?projectId=${project.id}`)}>
          New chat in project
        </button>
      </div>
      <p style={{ color: "var(--muted)", marginTop: 0 }}>
        {project.description?.trim() ? project.description : "No description yet."}
      </p>

      <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginBottom: 12 }}>
        <span className="badge">Visibility: {project.visibility}</span>
        <span className="badge">Updated: {new Date(project.updated_at).toLocaleString()}</span>
      </div>

      <div className="sectionTitle">Project chats</div>
      <div className="list">
        {linkedChats.length === 0 ? (
          <div className="listItem">
            <div className="listLink">
              <span className="listLinkTitle">No chats linked yet.</span>
            </div>
            <span className="badge">0</span>
          </div>
        ) : (
          linkedChats.map((c) => (
            <div className="listItem" key={c.id}>
              <Link className="listLink" to={`/app/chat/${c.id}`}>
                <span className="listLinkTitle">{c.title}</span>
              </Link>
              <span className="badge">{c.model_name}</span>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
