import React from "react";
import { Routes, Route, Navigate } from "react-router-dom";
import Login from "./pages/Login.jsx";
import Register from "./pages/Register.jsx";
import Shell from "./pages/Shell.jsx";
import Chat from "./pages/Chat.jsx";
import Projects from "./pages/Projects.jsx";
import ProjectView from "./pages/ProjectView.jsx";
import Settings from "./pages/Settings.jsx";
import { getToken } from "./api.js";
import Plan from "./pages/Plan.jsx";

function isAuthed() {
  return Boolean(getToken());
}

function Protected({ children }) {
  if (!isAuthed()) return <Navigate to="/login" replace />;
  return children;
}

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to="/login" replace />} />
      <Route path="/login" element={<Login />} />
      <Route path="/register" element={<Register />} />

      <Route
        path="/app"
        element={
          <Protected>
            <Shell />
          </Protected>
        }
      >
        <Route index element={<Navigate to="chat/new" replace />} />
        <Route path="chat/new" element={<Chat isNew />} />
        <Route path="chat/:chatId" element={<Chat />} />
        <Route path="projects" element={<Projects />} />
        <Route path="project/:projectId" element={<ProjectView />} />
        <Route path="settings" element={<Settings />} />
        <Route path="plan" element={<Plan />} />
      </Route>

      <Route path="*" element={<Navigate to="/login" replace />} />
    </Routes>
  );
}
