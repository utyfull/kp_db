import React, { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { apiFetch, setToken } from "../api.js";

export default function Register() {
  const nav = useNavigate();
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");

  async function onSubmit(e) {
    e.preventDefault();
    setError("");
    try {
      const data = await apiFetch("/api/auth/register", {
        method: "POST",
        body: JSON.stringify({ username, email, password }),
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
        <div className="authTitle">Create account</div>
        <p className="authSub">One minute setup: we create a profile and personal org for you.</p>

        <form onSubmit={onSubmit}>
          <div className="row">
            <div className="label">Username</div>
            <input className="input" value={username} onChange={(e) => setUsername(e.target.value)} />
          </div>
          <div className="row">
            <div className="label">Email</div>
            <input className="input" value={email} onChange={(e) => setEmail(e.target.value)} />
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
            <button className="btn btnAccent" type="submit">Create account</button>
            <div className="linkRow">
              Already have one? <Link to="/login">Sign in</Link>
            </div>
          </div>
        </form>
      </div>
    </div>
  );
}
