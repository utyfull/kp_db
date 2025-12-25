import React, { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { apiFetch, setToken } from "../api.js";

export default function Login() {
  const nav = useNavigate();
  const [username, setUsername] = useState("admin");
  const [password, setPassword] = useState("admin");
  const [error, setError] = useState("");

  async function onSubmit(e) {
    e.preventDefault();
    setError("");
    try {
      const data = await apiFetch("/api/auth/login", {
        method: "POST",
        body: JSON.stringify({ username, password }),
      });
      setToken(data.access_token);
      nav("/app/chat/new");
    } catch (e2) {
      setError(String(e2));
    }
  }

  return (
    <div className="authWrap">
      <div className="authCard">
        <div className="authTitle">ClownGPT</div>
        <p className="authSub">Sign in to continue. Default seed credentials: admin / admin.</p>

        <form onSubmit={onSubmit}>
          <div className="row">
            <div className="label">Username</div>
            <input className="input" value={username} onChange={(e) => setUsername(e.target.value)} />
          </div>
          <div className="row">
            <div className="label">Password</div>
            <input className="input" type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
          </div>

          {error && (
            <div style={{ border: "1px solid var(--border)", borderRadius: 12, padding: 10, color: "var(--danger)" }}>
              {error}
            </div>
          )}

          <div className="authActions">
            <button className="btn btnAccent" type="submit">Sign in</button>
            <div className="linkRow">
              Need an account? <Link to="/register">Create one</Link>
            </div>
          </div>
        </form>
      </div>
    </div>
  );
}
