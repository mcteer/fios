import React, { useState, useEffect, useRef, useCallback } from "react";
import { createRoot } from "react-dom/client";
import Markdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeHighlight from "rehype-highlight";
import {
  Plus,
  ArrowUp,
  Paperclip,
  Copy,
  Check,
  X,
  PanelLeftClose,
  PanelLeftOpen,
  Search,
  MessageSquare,
  Trash2,
  ChevronDown,
  Square,
  Code2,
  FileText,
  Image as ImageIcon,
  ArrowRight,
  RefreshCw,
  LogOut,
  LockKeyhole,
  AlertCircle,
  LoaderCircle,
  Terminal,
  Sparkles,
  Layers,
} from "lucide-react";
import { sseEvents } from "./stream.js";
import { useModelCatalog } from "./useModelCatalog.js";
import "./styles.css";

async function api(path, options = {}) {
  const res = await fetch("/api" + path, {
    ...options,
    headers:
      options.body instanceof FormData
        ? {}
        : { "Content-Type": "application/json", ...options.headers },
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    const e = new Error(data.error || `Request failed (${res.status})`);
    e.status = res.status;
    throw e;
  }
  return res.status === 204 ? null : res.json();
}
function Brand({ compact = false }) {
  return (
    <div className={"brand " + (compact ? "compact" : "")}>
      <span className="brand-mark">
        f<span>•</span>
      </span>
      {!compact && (
        <span>
          fios<span className="brand-period">.</span>
        </span>
      )}
    </div>
  );
}
function IconButton({ label, children, ...props }) {
  return (
    <button className="icon-button" aria-label={label} title={label} {...props}>
      {children}
    </button>
  );
}
function CopyButton({ text, label = "Copy text" }) {
  const [copied, setCopied] = useState(false),
    [failed, setFailed] = useState(false);
  useEffect(() => {
    if (!copied && !failed) return;
    const t = setTimeout(() => {
      setCopied(false);
      setFailed(false);
    }, 2000);
    return () => clearTimeout(t);
  }, [copied, failed]);
  return (
    <button
      className={"copy-button " + (copied ? "copied" : "")}
      aria-label={copied ? "Copied" : label}
      title={label}
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(text);
          setCopied(true);
        } catch {
          setFailed(true);
        }
      }}
    >
      {copied ? <Check size={14} /> : <Copy size={14} />}
      <span>
        {failed
          ? "Copy unavailable"
          : copied
            ? "Copied"
            : label === "Copy code"
              ? "Copy code"
              : ""}
      </span>
    </button>
  );
}
function CodeBlock({ children }) {
  const ref = useRef(null);
  const lang =
    /language-([^\s]+)/.exec(children?.props?.className || "")?.[1] || "code";
  return (
    <div className="code-block">
      <div className="code-toolbar">
        <span>
          <Terminal size={13} />
          {lang}
        </span>
        <CodeCopy codeRef={ref} />
      </div>
      <pre ref={ref}>{children}</pre>
    </div>
  );
}
function CodeCopy({ codeRef }) {
  const [text, setText] = useState("");
  useEffect(() => {
    setText(codeRef.current?.textContent || "");
  });
  return <CopyButton text={text} label="Copy code" />;
}
const mdComponents = {
  pre: CodeBlock,
  a: (props) => <a {...props} target="_blank" rel="noopener noreferrer" />,
  img: ({ alt }) => (
    <span className="muted">[Image: {alt || "external image blocked"}]</span>
  ),
};
function RichText({ content }) {
  return (
    <Markdown
      remarkPlugins={[remarkGfm]}
      rehypePlugins={[rehypeHighlight]}
      components={mdComponents}
    >
      {content}
    </Markdown>
  );
}
function ModelPicker({
  pickerRef,
  picker,
  setPicker,
  generating,
  modelsState,
  selected,
  models,
  setSelected,
  refreshModels,
}) {
  return (
    <div className="model-picker" ref={pickerRef}>
      <button
        type="button"
        className="model-trigger"
        aria-label="Choose model"
        aria-expanded={picker}
        onClick={() => {
          if (!picker) void refreshModels();
          setPicker(!picker);
        }}
        disabled={generating}
        title={selected}
      >
        <Layers size={13} />
        <span>
          {modelsState === "loading"
            ? "Connecting…"
            : modelsState === "error"
              ? "Models unavailable"
              : modelName(selected)}
        </span>
        <ChevronDown size={12} />
        <span
          className={"status-dot " + (modelsState === "error" ? "offline" : "")}
        />
      </button>
      {picker && (
        <div className="model-menu">
          <div className="model-menu-heading">
            Models{" "}
            <IconButton
              type="button"
              label="Refresh models"
              onClick={refreshModels}
            >
              <RefreshCw size={13} />
            </IconButton>
          </div>
          {models.length === 0 ? (
            <p>No chat models available.</p>
          ) : (
            models.map((m) => (
              <button
                type="button"
                className={
                  "model-option " + (m.id === selected ? "selected" : "")
                }
                key={m.id}
                disabled={modelsState !== "ready"}
                onClick={() => {
                  setSelected(m.id);
                  setPicker(false);
                }}
              >
                <span>
                  <strong>{modelName(m.id)}</strong>
                  <small>
                    {m.peer || "This Mac"}
                    {m.capabilities.includes("vision")
                      ? " · Vision"
                      : ""} · {m.loaded ? "Loaded" : "On demand"}
                  </small>
                </span>
                {m.id === selected && <Check size={15} />}
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
}
function modelName(id) {
  return (id || "").split("@")[0].split("/").pop() || "Choose a model";
}
function displaySize(size) {
  return size >= 1024 * 1024
    ? (size / 1024 / 1024).toFixed(1) + " MB"
    : Math.max(1, Math.round(size / 1024)) + " KB";
}
function FileChip({ file, remove }) {
  return (
    <div className="file-chip">
      {file.kind === "image" || file.type?.startsWith("image/") ? (
        <ImageIcon size={18} />
      ) : (
        <FileText size={18} />
      )}
      <span>
        <strong>{file.name}</strong>
        <small>{displaySize(file.size)}</small>
      </span>
      {remove && (
        <IconButton label={`Remove ${file.name}`} onClick={remove}>
          <X size={13} />
        </IconButton>
      )}
    </div>
  );
}
function Login({ onLogin }) {
  const [password, setPassword] = useState(""),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  return (
    <main className="login-page">
      <div className="login-card">
        <Brand />
        <div className="eyebrow">
          <LockKeyhole size={13} /> YOUR PRIVATE WORKSPACE
        </div>
        <h1>
          A little space
          <br />
          for big ideas.
        </h1>
        <p>
          Thoughtful conversations. Better code.
          <br />
          Powered by your models, on your Macs.
        </p>
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            setError("");
            try {
              await api("/login", {
                method: "POST",
                body: JSON.stringify({ password }),
              });
              onLogin();
            } catch (e) {
              setError(e.message);
            } finally {
              setBusy(false);
            }
          }}
        >
          <label htmlFor="password">Access password</label>
          <input
            id="password"
            type="password"
            autoComplete="current-password"
            autoFocus
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Enter your workspace password"
          />
          {error && (
            <div className="form-error" role="alert">
              {error}
            </div>
          )}
          <button className="primary-button" disabled={busy}>
            {busy ? (
              <LoaderCircle className="spin" size={16} />
            ) : (
              <>
                Enter workspace <ArrowRight size={16} />
              </>
            )}
          </button>
        </form>
        <small className="login-note">
          <span className="status-dot" /> Private by design. Local by default.
        </small>
      </div>
    </main>
  );
}
function App() {
  const [session, setSession] = useState(null),
    [sessionError, setSessionError] = useState("");
  useEffect(() => {
    api("/session")
      .then((x) => setSession(x.authenticated))
      .catch((e) => setSessionError(e.message));
  }, []);
  if (sessionError)
    return (
      <main className="loading-screen">
        <p>{sessionError}</p>
        <button onClick={() => location.reload()}>Try again</button>
      </main>
    );
  if (session === null)
    return (
      <main className="loading-screen">
        <Brand />
        <LoaderCircle className="spin" />
      </main>
    );
  if (!session) return <Login onLogin={() => setSession(true)} />;
  return <Workspace onLogout={() => setSession(false)} />;
}
function Workspace({ onLogout }) {
  const [chats, setChats] = useState([]),
    [chat, setChat] = useState(null);
  const {
    models,
    selected,
    setSelected,
    modelsState,
    modelsError,
    refreshModels,
  } = useModelCatalog(api);
  const [query, setQuery] = useState(""),
    [sidebar, setSidebar] = useState(false),
    [picker, setPicker] = useState(false),
    [draft, setDraft] = useState(""),
    [files, setFiles] = useState([]),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [loading, setLoading] = useState(false),
    [deleteChat, setDeleteChat] = useState(null),
    [reasoning, setReasoning] = useState("");
  const inputRef = useRef(null),
    fileRef = useRef(null),
    scrollRef = useRef(null),
    shouldScroll = useRef(true),
    controller = useRef(null),
    sendLock = useRef(false),
    pickerRef = useRef(null),
    dialogRef = useRef(null);
  const refreshChats = useCallback(
    async () => setChats(await api("/chats")),
    [],
  );
  useEffect(() => {
    refreshChats().catch((e) => setError(e.message));
  }, [refreshChats]);
  useEffect(() => {
    const close = (e) => {
      if (!pickerRef.current?.contains(e.target)) setPicker(false);
    };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, []);
  useEffect(() => {
    const escape = (e) => {
      if (e.key === "Escape") {
        setPicker(false);
        setSidebar(false);
        setDeleteChat(null);
      }
    };
    document.addEventListener("keydown", escape);
    return () => document.removeEventListener("keydown", escape);
  }, []);
  useEffect(() => {
    if (deleteChat) dialogRef.current?.showModal();
    else dialogRef.current?.close();
  }, [deleteChat]);
  useEffect(() => {
    if (shouldScroll.current)
      scrollRef.current?.scrollTo({
        top: scrollRef.current.scrollHeight,
        behavior: "instant",
      });
  }, [chat?.messages, reasoning, busy]);
  useEffect(() => {
    if (inputRef.current) {
      inputRef.current.style.height = "auto";
      inputRef.current.style.height =
        Math.min(inputRef.current.scrollHeight, 180) + "px";
    }
  }, [draft]);
  useEffect(() => () => controller.current?.abort(), []);
  // A refreshed page can reconnect to the saved partial conversation while the prior request settles.
  useEffect(() => {
    if (!chat?.generating || busy) return;
    const timer = setInterval(async () => {
      try {
        const next = await api("/chats/" + chat.id);
        setChat(next);
      } catch {}
    }, 1000);
    return () => clearInterval(timer);
  }, [chat?.id, chat?.generating, busy]);
  const generating = busy || chat?.generating;
  async function openChat(id) {
    if (generating) return;
    setLoading(true);
    setSidebar(false);
    setError("");
    try {
      const next = await api("/chats/" + id);
      setChat(next);
      if (next.model) setSelected(next.model);
      setDraft("");
      setFiles([]);
      setReasoning("");
      shouldScroll.current = true;
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }
  function newChat() {
    if (generating) return;
    setChat(null);
    setDraft("");
    setFiles([]);
    setError("");
    setReasoning("");
    setSidebar(false);
    inputRef.current?.focus();
  }
  function addFiles(items) {
    const incoming = Array.from(items),
      combined = [...files, ...incoming];
    if (combined.length > 5)
      return setError("Attach up to 5 files per message.");
    if (combined.some((f) => f.size > 10 * 1024 * 1024))
      return setError("Each file must be 10 MiB or smaller.");
    if (combined.reduce((s, f) => s + f.size, 0) > 20 * 1024 * 1024)
      return setError("Attachments must total 20 MiB or less.");
    setFiles(combined);
    setError("");
  }
  async function send(e) {
    e?.preventDefault();
    if (
      sendLock.current ||
      generating ||
      (!draft.trim() && !files.length) ||
      !selected ||
      modelsState !== "ready" ||
      !models.some((m) => m.id === selected)
    )
      return;
    sendLock.current = true;
    setBusy(true);
    setError("");
    setReasoning("");
    shouldScroll.current = true;
    let id = chat?.id,
      accepted = false;
    const body = new FormData();
    body.set("content", draft);
    body.set("model", selected);
    files.forEach((f) => body.append("files", f));
    try {
      if (!id) {
        const created = await api("/chats", { method: "POST" });
        id = created.id;
        setChat({ ...created, messages: [] });
        await refreshChats();
      }
      controller.current = new AbortController();
      const res = await fetch(`/api/chats/${id}/messages`, {
        method: "POST",
        body,
        signal: controller.current.signal,
      });
      if (!res.ok) {
        const data = await res.json();
        throw new Error(data.error || "Could not send message.");
      }
      let done = false;
      for await (const { event, data } of sseEvents(res.body)) {
        if (event === "meta") {
          accepted = true;
          setDraft("");
          setFiles([]);
          setChat((prev) => ({
            ...prev,
            ...data.chat,
            messages: [...(prev?.messages || []), data.user, data.assistant],
          }));
          refreshChats().catch(() => {});
        }
        if (event === "delta")
          setChat((prev) => ({
            ...prev,
            messages: prev.messages.map((m, i) =>
              i === prev.messages.length - 1
                ? { ...m, content: m.content + data.content }
                : m,
            ),
          }));
        if (event === "reasoning") setReasoning((prev) => prev + data.content);
        if (event === "error") setError(data.error);
        if (event === "done") done = true;
      }
      if (!done)
        throw new Error(
          "The connection ended early. Any partial response has been saved.",
        );
    } catch (e) {
      if (e.name !== "AbortError") setError(e.message);
    } finally {
      controller.current = null;
      if (id) {
        try {
          setChat(await api("/chats/" + id));
          await refreshChats();
        } catch (e) {
          setError(e.message);
        }
      }
      setBusy(false);
      sendLock.current = false;
      if (accepted) inputRef.current?.focus();
    }
  }
  async function stop() {
    try {
      await api("/chats/" + chat.id + "/stop", { method: "POST" });
    } catch (e) {
      setError(e.message);
      controller.current?.abort();
    }
  }
  const visibleChats = chats.filter((c) =>
    c.title.toLowerCase().includes(query.toLowerCase()),
  );
  const empty = !chat?.messages?.length;
  const displayError = error || modelsError;
  return (
    <div className={"workspace " + (empty ? "is-empty" : "has-messages")}>
      {sidebar && (
        <button
          className="sidebar-backdrop"
          aria-label="Close navigation"
          onClick={() => setSidebar(false)}
        />
      )}
      <aside className={"sidebar " + (sidebar ? "is-open" : "")}>
        <div className="sidebar-brand">
          <span className="sidebar-title"><img className="brand-wordmark" src="/fios-wordmark.svg" alt="fios" /></span>
          <IconButton
            label="Close navigation"
            onClick={() => setSidebar(false)}
          >
            <PanelLeftClose size={18} />
          </IconButton>
        </div>
        <div className="sidebar-navigation">
          <button
            className="new-chat sidebar-link"
            onClick={newChat}
            disabled={generating}
          >
            <MessageSquare size={16} />
            <span>New conversation</span>
            <Plus size={14} />
          </button>
        </div>
        <label className="search">
          <Search size={15} />
          <input
            aria-label="Search conversations"
            placeholder="Search conversations"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          {query && (
            <button aria-label="Clear search" onClick={() => setQuery("")}>
              <X size={13} />
            </button>
          )}
        </label>
        <div className="history-heading">
          <span>Sessions</span>
          <IconButton
            label="New conversation"
            disabled={generating}
            onClick={newChat}
          >
            <Plus size={14} />
          </IconButton>
        </div>
        <nav className="history" aria-label="Conversation history">
          {!visibleChats.length ? (
            query ? (
              <div className="history-empty">
                <p>No matching conversations</p>
              </div>
            ) : (
              <button
                className="default-session"
                disabled={generating}
                onClick={newChat}
              >
                <MessageSquare size={13} />
                <span>New Chat</span>
              </button>
            )
          ) : (
            visibleChats.map((c) => (
              <div
                className={"chat-row " + (chat?.id === c.id ? "active" : "")}
                key={c.id}
              >
                <button
                  className="chat-open"
                  disabled={generating}
                  onClick={() => openChat(c.id)}
                >
                  <MessageSquare size={15} />
                  <span>{c.title}</span>
                </button>
                <IconButton
                  label={`Delete ${c.title}`}
                  disabled={generating}
                  onClick={() => setDeleteChat(c)}
                >
                  <Trash2 size={14} />
                </IconButton>
              </div>
            ))
          )}
        </nav>
        <div className="sidebar-footer">
          <div className="local-label">
            <span
              className={
                "status-dot " + (modelsState === "error" ? "offline" : "")
              }
            />
            <div>
              <strong>Local intelligence</strong>
              <small>
                {modelsState === "error"
                  ? "Gateway unavailable"
                  : "Powered by MLX-Serve"}
              </small>
            </div>
            <LockKeyhole size={14} />
          </div>
          <button
            className="account"
            onClick={async () => {
              try {
                await api("/logout", { method: "POST" });
                onLogout();
              } catch (e) {
                setError(e.message);
              }
            }}
            disabled={generating}
          >
            <span className="avatar">M</span>
            <span>
              My workspace<small>Private · On your Macs</small>
            </span>
            <LogOut size={15} />
          </button>
        </div>
      </aside>
      <main className="main-panel">
        <header className="topbar">
          <div className="topbar-left">
            <IconButton
              label="Open navigation"
              onClick={() => setSidebar(true)}
            >
              <PanelLeftOpen size={19} />
            </IconButton>
            <span className="workspace-wordmark"><img className="brand-wordmark" src="/fios-wordmark.svg" alt="fios" /></span>
          </div>
          <span className="private-badge">
            <LockKeyhole size={12} />
            Private workspace
          </span>
        </header>
        <div
          className={"conversation-scroll " + (empty ? "empty-scroll" : "")}
          ref={scrollRef}
          onScroll={(e) => {
            const el = e.currentTarget;
            shouldScroll.current =
              el.scrollHeight - el.scrollTop - el.clientHeight < 130;
          }}
        >
          {loading ? (
            <div className="conversation-loading">
              <LoaderCircle className="spin" size={22} />
            </div>
          ) : empty ? (
            <section className="welcome">
              <h1>How can I help you today?</h1>
              <div className="suggestions">
                {[
                  {
                    icon: Code2,
                    title: "Build something",
                    text: "Turn an idea into working code",
                    prompt: "Help me build ",
                  },
                  {
                    icon: Terminal,
                    title: "Make it better",
                    text: "Review, refactor, and find the fix",
                    prompt:
                      "Can you review this code and suggest improvements?\n\n",
                  },
                  {
                    icon: Sparkles,
                    title: "Think it through",
                    text: "A fresh perspective on a hard problem",
                    prompt: "Help me think through ",
                  },
                ].map((s) => (
                  <button
                    key={s.title}
                    onClick={() => {
                      setDraft(s.prompt);
                      inputRef.current?.focus();
                    }}
                  >
                    <s.icon size={14} />
                    <strong>{s.title}</strong>
                  </button>
                ))}
              </div>
            </section>
          ) : (
            <div className="messages">
              {chat.messages.map((m) => (
                <article className={"message " + m.role} key={m.id}>
                  <div className="message-avatar">
                    {m.role === "assistant" ? (
                      <Brand compact />
                    ) : (
                      <span>You</span>
                    )}
                  </div>
                  <div className="message-body">
                    <div className="message-heading">
                      {m.role === "assistant" ? "Fios" : "You"}
                      {m.role === "assistant" && (
                        <span>{modelName(m.model || chat.model)}</span>
                      )}
                    </div>
                    {m.attachments?.length > 0 && (
                      <div className="message-files">
                        {m.attachments.map((f, i) => (
                          <FileChip key={f.id || i} file={f} />
                        ))}
                      </div>
                    )}
                    {m.role === "user" ? (
                      <div className="user-text">{m.content}</div>
                    ) : (
                      <div className="prose">
                        {m.content ? (
                          <RichText content={m.content} />
                        ) : m.status === "streaming" ? (
                          <div className="thinking">
                            <span />
                            <span />
                            <span />
                            <span className="sr-only">Generating response</span>
                          </div>
                        ) : (
                          <span className="muted">
                            {m.status === "error"
                              ? "No response received. Check the error below or try again."
                              : "Response stopped before any text was received."}
                          </span>
                        )}
                        {m.status === "streaming" && m.content && (
                          <span className="stream-cursor" />
                        )}
                      </div>
                    )}
                    {m.role === "assistant" &&
                      ["interrupted", "error"].includes(m.status) && (
                        <div className="response-status">
                          <AlertCircle size={12} />
                          {m.status === "error"
                            ? "Response could not be completed"
                            : "Response stopped"}{" "}
                          · partial output saved
                        </div>
                      )}
                    {m.content && m.status !== "streaming" && (
                      <div className="message-actions">
                        <CopyButton text={m.content} />
                      </div>
                    )}
                  </div>
                </article>
              ))}
              {busy && reasoning && (
                <details className="reasoning">
                  <summary>Thinking through the response</summary>
                  <pre>{reasoning}</pre>
                </details>
              )}
            </div>
          )}
        </div>
        <div className={"composer-area " + (empty ? "welcome-composer" : "")}>
          {displayError && (
            <div className="error-banner" role="alert">
              <AlertCircle size={16} />
              <span>{displayError}</span>
              {modelsState === "error" && (
                <button
                  onClick={() => {
                    setError("");
                    refreshModels();
                  }}
                >
                  Reconnect
                </button>
              )}
              {error && (
                <IconButton label="Dismiss error" onClick={() => setError("")}>
                  <X size={14} />
                </IconButton>
              )}
            </div>
          )}
          <form
            className={"composer " + (generating ? "is-generating" : "")}
            onSubmit={send}
            onDragOver={(e) => e.preventDefault()}
            onDrop={(e) => {
              e.preventDefault();
              if (!generating) addFiles(e.dataTransfer.files);
            }}
          >
            {!!files.length && (
              <div className="pending-files">
                {files.map((f, i) => (
                  <FileChip
                    key={i}
                    file={f}
                    remove={() =>
                      setFiles((prev) => prev.filter((_, j) => j !== i))
                    }
                  />
                ))}
              </div>
            )}
            <textarea
              ref={inputRef}
              value={draft}
              maxLength={100000}
              onChange={(e) => setDraft(e.target.value)}
              disabled={generating}
              aria-label="Message Fios"
              placeholder={
                generating
                  ? "Fios is working on your response…"
                  : "Ask me anything…"
              }
              rows={1}
              onKeyDown={(e) => {
                if (
                  e.key === "Enter" &&
                  !e.shiftKey &&
                  !e.nativeEvent.isComposing
                ) {
                  e.preventDefault();
                  send();
                }
              }}
            />
            <div className="composer-tools">
              <div className="attachment-tools">
                <IconButton
                  type="button"
                  label="Attach files (text, source, PDF or images)"
                  disabled={generating}
                  onClick={() => fileRef.current?.click()}
                >
                  <Paperclip size={19} />
                </IconButton>
                <ModelPicker
                  pickerRef={pickerRef}
                  picker={picker}
                  setPicker={setPicker}
                  generating={generating}
                  modelsState={modelsState}
                  selected={selected}
                  models={models}
                  setSelected={setSelected}
                  refreshModels={refreshModels}
                />
                <input
                  ref={fileRef}
                  className="sr-only"
                  tabIndex={-1}
                  type="file"
                  multiple
                  onChange={(e) => {
                    addFiles(e.target.files);
                    e.target.value = "";
                  }}
                />
              </div>
              <div className="send-tools">
                <span className="keyboard-hint">↵ to send</span>
                {generating ? (
                  <button
                    type="button"
                    className="send-button stop"
                    aria-label="Stop response"
                    onClick={stop}
                  >
                    <Square size={14} fill="currentColor" />
                  </button>
                ) : (
                  <button
                    className="send-button"
                    type="submit"
                    aria-label="Send message"
                    disabled={
                      (!draft.trim() && !files.length) ||
                      !selected ||
                      loading ||
                      modelsState !== "ready" ||
                      !models.some((m) => m.id === selected)
                    }
                  >
                    <ArrowUp size={20} />
                  </button>
                )}
              </div>
            </div>
          </form>
          <p className="composer-footnote">
            <span className="status-dot" /> Runs on your Macs
            <span className="footnote-separator">·</span>Fios can make mistakes.
            Check important details.
          </p>
        </div>
      </main>
      <dialog
        ref={dialogRef}
        className="delete-dialog"
        onCancel={() => setDeleteChat(null)}
      >
        <div className="dialog-icon">
          <Trash2 size={22} />
        </div>
        <h2>Delete this conversation?</h2>
        <p>
          “{deleteChat?.title}” and its attachments will be permanently removed.
          This can’t be undone.
        </p>
        <div className="dialog-actions">
          <button onClick={() => setDeleteChat(null)}>Keep conversation</button>
          <button
            className="danger"
            onClick={async () => {
              try {
                await api("/chats/" + deleteChat.id, { method: "DELETE" });
                if (chat?.id === deleteChat.id) newChat();
                setDeleteChat(null);
                await refreshChats();
              } catch (e) {
                setError(e.message);
                setDeleteChat(null);
              }
            }}
          >
            Delete conversation
          </button>
        </div>
      </dialog>
    </div>
  );
}
createRoot(document.getElementById("root")).render(<App />);
