import { DatabaseSync } from "node:sqlite";
import { randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import {validateManifest,validateTransition} from '../src/agent/web-protocol.js';

export function openStore(path) {
  if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
    CREATE TABLE IF NOT EXISTS chats(id TEXT PRIMARY KEY, title TEXT NOT NULL, model TEXT NOT NULL, updated INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY, chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE, role TEXT NOT NULL, content TEXT NOT NULL, status TEXT NOT NULL, created INTEGER NOT NULL, model TEXT NOT NULL DEFAULT '');
    CREATE TABLE IF NOT EXISTS attachments(id TEXT PRIMARY KEY, message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE, name TEXT NOT NULL, mime TEXT NOT NULL, size INTEGER NOT NULL, kind TEXT NOT NULL, text TEXT, data BLOB);
    CREATE INDEX IF NOT EXISTS messages_chat ON messages(chat_id,created);
    CREATE INDEX IF NOT EXISTS attachments_message ON attachments(message_id);
    CREATE TABLE IF NOT EXISTS web_retrieval(message_id TEXT PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE, schema_version INTEGER NOT NULL, phase TEXT NOT NULL, outcome TEXT NOT NULL, evidence_state TEXT NOT NULL, updated_at INTEGER NOT NULL, manifest_json TEXT NOT NULL);
    UPDATE messages SET status='interrupted' WHERE status='streaming';`);
  for (const row of db.prepare("SELECT w.* FROM web_retrieval w JOIN messages m ON m.id=w.message_id WHERE m.status='interrupted'").all()) {
    try {
      const old=validateManifest(JSON.parse(row.manifest_json));
      if(old.phase!=='finished') {
        const next={...old,phase:'finished',outcome:'cancelled',reason:'run_cancelled'};
        db.prepare('UPDATE web_retrieval SET phase=?,outcome=?,updated_at=?,manifest_json=? WHERE message_id=?').run(next.phase,next.outcome,Date.now(),JSON.stringify(next),row.message_id);
      }
    } catch { /* Invalid metadata is never rendered or silently trusted. */ }
  }
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
    readWeb(id) {
      const row=db.prepare('SELECT * FROM web_retrieval WHERE message_id=?').get(id);
      if(!row) return null;
      try {
        if(Buffer.byteLength(row.manifest_json)>65536) throw new Error();
        const value=validateManifest(JSON.parse(row.manifest_json));
        if(row.schema_version!==value.v||row.phase!==value.phase||row.outcome!==value.outcome||row.evidence_state!==value.evidence_state) throw new Error();
        return value;
      } catch { return {v:1,phase:'finished',outcome:'unavailable',reason:'retrieval_unavailable',tool_attempted:true,evidence_state:'none',retrieved_at:null,sources:[]}; }
    },
    web(id,value) {
      validateManifest(value);
      if(db.prepare('SELECT role FROM messages WHERE id=?').get(id)?.role!=='assistant') throw new Error('Invalid provenance owner.');
      const old=this.readWeb(id);
      if(old) validateTransition(old,value);
      db.prepare('INSERT INTO web_retrieval VALUES(?,?,?,?,?,?,?) ON CONFLICT(message_id) DO UPDATE SET phase=excluded.phase,outcome=excluded.outcome,evidence_state=excluded.evidence_state,updated_at=excluded.updated_at,manifest_json=excluded.manifest_json').run(id,value.v,value.phase,value.outcome,value.evidence_state,Date.now(),JSON.stringify(value));
    },
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
          ...(m.role==='assistant'?{web:this.readWeb(m.id)}:{}),
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
