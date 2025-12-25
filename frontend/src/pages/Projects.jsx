import React, { useMemo } from "react";
import { Link, useOutletContext } from "react-router-dom";

export default function Projects() {
  const { projects, chats } = useOutletContext();

  const enriched = useMemo(
    () =>
      projects.map((p) => ({
        ...p,
        chatCount: chats.filter((c) => String(c.project_id || "") === String(p.id)).length,
      })),
    [projects, chats]
  );

  return (
    <div className="pageScroll" style={{ maxWidth: 920, margin: "0 auto" }}>
      <h2 style={{ marginTop: 6 }}>Projects</h2>
      <p style={{ color: "var(--muted)" }}>
        Organize chats by project and keep related threads together.
      </p>

      {enriched.length === 0 ? (
        <div className="msg" style={{ marginTop: 16 }}>
          <div className="msgHeader">No projects yet</div>
          <div className="msgBody">Create a project from the sidebar to get started.</div>
        </div>
      ) : (
        <div className="list">
          {enriched.map((p) => (
            <div className="listItem" key={p.id}>
              <Link className="listLink" to={`/app/project/${p.id}`}>
                <span className="listLinkTitle">{p.name}</span>
              </Link>
              <span className="badge">{p.chatCount} chats</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
