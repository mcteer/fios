"use strict";

const select = (id) => document.getElementById(id);
const csrf = document.querySelector('meta[name="chat-csrf"]').content;
const thread = select("thread");
const historyList = select("history");
const statusLine = select("status");
const titles = select("title");
const promptBox = select("prompt");
const alias = select("alias");
const busy = new Set(["active", "queued", "preparing", "running", "stopping"]);
let conversation = null;
let currentTurn = null;
let nextHistory = null;
let catalog = null;
let submitting = false;
let pending = null;
let readVersion = 0;
let activeStream = null;

async function api(action, data = null, suffix = "") {
  const response = await fetch("/api/v1/chat/" + action + suffix, data === null ? {} : {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Chat-CSRF": csrf },
    body: JSON.stringify(data),
  });
  if (!response.ok) {
    const problem = await response.json();
    throw new Error(problem.reason);
  }
  return response.json();
}

function report(error) {
  const messages = {
    quota: "Conversation storage is full.",
    ledger_changed: "The service was restored. Reopen the conversation before retrying.",
    conversation_changed: "This conversation has changed. Reopen it before sending.",
    unqualified: "This model is unavailable.",
    too_large: "This message exceeds the size limit.",
  };
  statusLine.textContent = messages[error.message] ?? "Chat is temporarily unavailable.";
}

function controls() {
  select("inventory").disabled = alias.value !== "general-chat";
  select("send").disabled = submitting || busy.has(currentTurn?.state) ||
    !catalog?.aliases[alias.value]?.available;
  select("stop").disabled = submitting || !busy.has(currentTurn?.state) || currentTurn?.state === "stopping";
  select("delete").disabled = submitting || conversation === null;
}

async function loadCatalog() {
  catalog = await api("catalog");
  const labels = { "general-chat": "General chat", coding: "Coding", "paired-coding": "Paired Studio coding" };
  const reasons = { unqualified: "unavailable", occupied: "busy", waiting_capacity: "waiting for capacity" };
  for (const option of alias.options) {
    const model = catalog.aliases[option.value];
    option.disabled = !model?.available;
    option.textContent = labels[option.value] + (reasons[model?.reason] ? " · " + reasons[model?.reason] : "");
  }
  if (alias.selectedOptions[0]?.disabled) {
    const available = Array.from(alias.options).find((item) => !item.disabled);
    if (available) alias.value = available.value;
  }
  controls();
}

async function loadHistory(before = null) {
  const data = await api("history", null, before ? "?before=" + before : "");
  if (!before) historyList.replaceChildren();
  for (const item of data.conversations) {
    const entry = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = item.title;
    button.addEventListener("click", () => openConversation(item.id).catch(report));
    entry.append(button);
    historyList.append(entry);
  }
  nextHistory = data.next;
  select("more").hidden = !nextHistory;
}

async function readThread(id = conversation) {
  if (!id) return;
  const revision = ++readVersion;
  const data = await api("conversation", null, "/" + id);
  if (conversation !== id || revision !== readVersion) return;
  const wasBusy = busy.has(currentTurn?.state);
  titles.textContent = data.title;
  thread.replaceChildren();
  for (const turn of data.turns) {
    for (const [label, value] of [["You", turn.prompt], ["fios", turn.answer]]) {
      if (!value) continue;
      const entry = document.createElement("article");
      const name = document.createElement("strong");
      const text = document.createElement("pre");
      name.textContent = label;
      text.textContent = value;
      entry.append(name, text);
      thread.append(entry);
    }
  }
  currentTurn = data.turns.at(-1) ?? null;
  if (currentTurn) {
    const states = { active: "Waiting for a worker", preparing: "Preparing model",
      running: "Generating", stopping: "Stopping", cancelled: "Stopped", denied: "Withheld",
      failed: "Interrupted", expired: "Expired", interrupted: "Interrupted",
      completed: "Completed", succeeded: "Completed" };
    const display = states[currentTurn.state] ?? "Waiting";
    const revisionText = currentTurn.revision ? " · " + currentTurn.revision.slice(0, 12) : "";
    const usage = ["input", "output"].map((name) => {
      const count = currentTurn.usage?.[name];
      return name + " " + (count?.value ?? "unknown");
    }).join(" · ");
    statusLine.textContent = display + revisionText +
      (currentTurn.usage ? " · " + usage : "");
  }
  controls();
  if (wasBusy && !busy.has(currentTurn?.state)) await loadHistory();
}

async function streamTurn(id, job) {
  const controller = new AbortController();
  activeStream = controller;
  let sequence = 0;
  let buffer = "";
  try {
    const response = await fetch("/api/v1/chat/stream/" + id + "/" + job,
      { signal: controller.signal });
    if (!response.ok || !response.body) throw new Error("stream_unavailable");
    const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += value;
      const lines = buffer.split("\n");
      buffer = lines.pop();
      for (const line of lines) {
        const event = JSON.parse(line);
        if (event.job !== job || event.sequence !== ++sequence) throw new Error("invalid_stream");
        if (conversation !== id || currentTurn?.job !== job || controller.signal.aborted) return;
        if (event.type === "state" && event.state === "running") {
          statusLine.textContent = "Generating";
        } else if (event.type === "text") {
          let answer = select("incoming-answer");
          if (!answer) {
            answer = document.createElement("pre");
            answer.id = "incoming-answer";
            thread.append(answer);
          }
          answer.append(document.createTextNode(event.text));
        }
      }
    }
    if (conversation === id) await readThread(id);
  } catch (error) {
    if (!controller.signal.aborted) report(error);
  } finally {
    if (activeStream === controller) activeStream = null;
  }
}

async function openConversation(id) {
  if (submitting) return;
  ++readVersion;
  activeStream?.abort();
  activeStream = null;
  conversation = id;
  currentTurn = null;
  pending = null;
  thread.replaceChildren();
  statusLine.textContent = "";
  titles.textContent = "New conversation";
  controls();
  if (id) await readThread(id);
}

function key() {
  return crypto.randomUUID().replaceAll("-", "");
}

select("composer").addEventListener("submit", async (event) => {
  event.preventDefault();
  if (select("send").disabled) return;
  submitting = true;
  controls();
  try {
    if (!pending) pending = { createKey: key(), key: key(), prompt: promptBox.value,
      alias: alias.value, inventory: alias.value === "general-chat" && select("inventory").checked,
      incarnation: catalog.incarnation, parent: currentTurn?.job ?? null };
    if (!conversation) {
      const created = await api("create", { key: pending.createKey });
      conversation = created.id;
    }
    const { key: requestKey, prompt, alias: selectedModel, incarnation, parent, inventory } = pending;
    const turn = await api("submit", { id: conversation, key: requestKey, prompt,
      alias: selectedModel, incarnation, parent, inventory });
    currentTurn = { job: turn.job, state: "active" };
    pending = null;
    promptBox.value = "";
    await readThread();
    if (busy.has(currentTurn?.state)) streamTurn(conversation, turn.job);
    await loadHistory();
  } catch (error) {
    if (["quota", "ledger_changed", "conversation_changed", "unqualified", "too_large"].includes(error.message)) {
      pending = null;
    }
    report(error);
  } finally {
    submitting = false;
    controls();
  }
});

select("stop").addEventListener("click", async () => {
  try {
    await api("stop", { job: currentTurn.job });
    activeStream?.abort();
    activeStream = null;
    await readThread();
  } catch (error) { report(error); }
});

select("delete").addEventListener("click", async () => {
  if (!conversation || !confirm('Delete "' + titles.textContent + '"?')) return;
  try {
    await api("delete", { id: conversation });
    await openConversation(null);
    await loadHistory();
  } catch (error) { report(error); }
});

select("new").addEventListener("click", () => openConversation(null).catch(report));
select("more").addEventListener("click", () => loadHistory(nextHistory).catch(report));
alias.addEventListener("change", controls);

async function refresh() {
  try {
    await loadCatalog();
    if (!submitting && !activeStream && busy.has(currentTurn?.state)) await readThread();
  } catch (error) { report(error); }
  setTimeout(refresh, 1000);
}

loadHistory().catch(report);
refresh();
