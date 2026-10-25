import { DatabaseSync } from "node:sqlite";
import { randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

export function openStore(path) {
  if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
    CREATE TABLE IF NOT EXISTS chats(id TEXT PRIMARY KEY, title TEXT NOT NULL, model TEXT NOT NULL, updated INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY, chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE, role TEXT NOT NULL, content TEXT NOT NULL, status TEXT NOT NULL, created INTEGER NOT NULL, model TEXT NOT NULL DEFAULT '');
    CREATE TABLE IF NOT EXISTS attachments(id TEXT PRIMARY KEY, message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE, name TEXT NOT NULL, mime TEXT NOT NULL, size INTEGER NOT NULL, kind TEXT NOT NULL, text TEXT, data BLOB);
    CREATE INDEX IF NOT EXISTS messages_chat ON messages(chat_id,created);
    CREATE INDEX IF NOT EXISTS attachments_message ON attachments(message_id);
    UPDATE messages SET status='interrupted' WHERE status='streaming';`);
  if (
    !db
      .prepare("PRAGMA table_info(messages)")
      .all()
      .some((c) => c.name === "model")
  ) {
    db.exec(
      "ALTER TABLE messages ADD COLUMN model TEXT NOT NULL DEFAULT ''; UPDATE messages SET model=(SELECT model FROM chats WHERE chats.id=messages.chat_id) WHERE role='assistant';",
    );
  }
  const messages = (id) =>
    db
      .prepare("SELECT * FROM messages WHERE chat_id=? ORDER BY created,rowid")
      .all(id);
  const attachments = (id) =>
    db
      .prepare(
        "SELECT a.* FROM attachments a JOIN messages m ON m.id=a.message_id WHERE m.chat_id=?",
      )
      .all(id);
  return {
    db,
    messages,
    attachments,
    list: () => db.prepare("SELECT * FROM chats ORDER BY updated DESC").all(),
    get: (id) => db.prepare("SELECT * FROM chats WHERE id=?").get(id),
    create(model) {
      const chat = {
        id: randomUUID(),
        title: "New conversation",
        model,
        updated: Date.now(),
      };
      db.prepare("INSERT INTO chats VALUES(?,?,?,?)").run(
        chat.id,
        chat.title,
        model,
        chat.updated,
      );
      return chat;
    },
    detail(id) {
      const chat = this.get(id);
      if (!chat) return null;
      const files = attachments(id);
      return {
        ...chat,
        messages: messages(id).map((m) => ({
          ...m,
          attachments: files
            .filter((a) => a.message_id === m.id)
            .map(({ data, text, ...a }) => a),
        })),
      };
    },
    remove: (id) => db.prepare("DELETE FROM chats WHERE id=?").run(id),
    add(id, role, content, status = "complete", model = "") {
      const m = {
        id: randomUUID(),
        chat_id: id,
        role,
        content,
        status,
        created: Date.now(),
        model,
      };
      db.prepare("INSERT INTO messages VALUES(?,?,?,?,?,?,?)").run(
        m.id,
        id,
        role,
        content,
        status,
        m.created,
        model,
      );
      return m;
    },
    update(id, content, status) {
      db.prepare("UPDATE messages SET content=?,status=? WHERE id=?").run(
        content,
        status,
        id,
      );
    },
    touch(id, model, title) {
      db.prepare(
        "UPDATE chats SET updated=?,model=?,title=COALESCE(?,title) WHERE id=?",
      ).run(Date.now(), model, title || null, id);
    },
    file(messageId, a) {
      db.prepare("INSERT INTO attachments VALUES(?,?,?,?,?,?,?,?)").run(
        randomUUID(),
        messageId,
        a.name,
        a.mime,
        a.size,
        a.kind,
        a.text || null,
        a.data || null,
      );
    },
  };
}
