import React from "react";

export default function Settings() {
  return (
    <div className="pageScroll" style={{ maxWidth: 920, margin: "0 auto" }}>
      <h2 style={{ marginTop: 6 }}>Settings</h2>
      <p style={{ color: "var(--muted)" }}>
        Service documentation is available in Swagger UI.
      </p>

      <div style={{ display: "grid", gap: 12 }}>
        <a className="btn" href="http://localhost:8000/docs" target="_blank" rel="noreferrer">
          Open Swagger docs
        </a>
      </div>
    </div>
  );
}
