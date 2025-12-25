import React, { useEffect, useState } from "react";
import { useOutletContext } from "react-router-dom";
import { apiFetch } from "../api.js";

const plans = ["free", "pro", "enterprise"];

export default function Plan() {
  const { reloadAll } = useOutletContext();
  const [current, setCurrent] = useState("free");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    apiFetch("/api/org/plan")
      .then((p) => setCurrent(p.plan))
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false));
  }, []);

  async function onSave(e) {
    e.preventDefault();
    setSaved(false);
    setError("");
    try {
      const res = await apiFetch("/api/org/plan", {
        method: "POST",
        body: JSON.stringify({ plan: current }),
      });
      setCurrent(res.plan);
      setSaved(true);
      await reloadAll();
    } catch (err) {
      setError(String(err));
    }
  }

  return (
    <div className="pageScroll" style={{ maxWidth: 640, margin: "0 auto" }}>
      <h2 style={{ marginTop: 6 }}>Plan</h2>
      <p style={{ color: "var(--muted)" }}>
        Switch between Free, Pro, and Enterprise. This only updates your stored plan name.
      </p>

      {loading ? (
        <div className="msg">
          <div className="msgBody">Loading plan…</div>
        </div>
      ) : (
        <form className="msg" onSubmit={onSave} style={{ display: "grid", gap: 12 }}>
          <div>
            <div className="label">Select plan</div>
            <select className="select selectModel" value={current} onChange={(e) => setCurrent(e.target.value)}>
              {plans.map((p) => (
                <option key={p} value={p}>{p}</option>
              ))}
            </select>
          </div>
          {error && <div style={{ color: "var(--danger)" }}>{error}</div>}
          {saved && <div style={{ color: "var(--muted)" }}>Plan updated.</div>}
          <div>
            <button className="btn btnAccent" type="submit">Save plan</button>
          </div>
        </form>
      )}
    </div>
  );
}
