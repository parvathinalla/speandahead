"""Owner-isolated, opt-in CreditPilot AI memory repository.

No passwords, OAuth tokens, raw account IDs or full banking snapshots are
stored. The AI gets only the selected user's relevant preferences/history.
TigerData PostgreSQL is independent of DEMO_STORE and supports Nessie mode.
"""
from __future__ import annotations
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sqlite3
from typing import Any

def _as_iso():
    return datetime.now(timezone.utc).isoformat()

class AgentMemory:
    def __init__(self, sqlite_path: str | Path, pg_url: str | None = None):
        self.sqlite_path = str(sqlite_path)
        self.pg_url = pg_url or None
        if self.pg_url:
            # Reuse strict private connection/TLS logic; does NOT seed 500 users.
            from tigerdata_store import TigerDataStore
            self.tiger = TigerDataStore(self.pg_url)
            self.mode = "tigerdata"
        else:
            self.mode = "sqlite"

    def _connect(self):
        if self.mode == "tigerdata":
            return self.tiger.connect()
        path = Path(self.sqlite_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(path, timeout=15)
        conn.row_factory = sqlite3.Row
        return conn

    def _sql(self, sqlite_stmt, pg_stmt):
        return pg_stmt if self.mode == "tigerdata" else sqlite_stmt

    def _run(self, conn, statement, args=()):
        if self.mode == "tigerdata":
            statement = statement.replace("?", "%s")
        return conn.execute(statement, args)

    def init(self):
        with self._connect() as conn:
            if self.mode == "tigerdata":
                conn.execute("""CREATE TABLE IF NOT EXISTS cp_ai_settings (
                    owner_sub TEXT PRIMARY KEY, enabled BOOLEAN NOT NULL DEFAULT false,
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT now())""")
                conn.execute("""CREATE TABLE IF NOT EXISTS cp_ai_memories (
                    id TEXT PRIMARY KEY, owner_sub TEXT NOT NULL,
                    note TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now())""")
                conn.execute("""CREATE INDEX IF NOT EXISTS cp_ai_memories_owner
                    ON cp_ai_memories(owner_sub, created_at DESC)""")
                conn.execute("""CREATE TABLE IF NOT EXISTS cp_ai_messages (
                    id BIGSERIAL PRIMARY KEY, owner_sub TEXT NOT NULL,
                    role TEXT NOT NULL CHECK(role IN ('user','assistant')),
                    content TEXT NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT now())""")
                conn.execute("""CREATE INDEX IF NOT EXISTS cp_ai_messages_owner
                    ON cp_ai_messages(owner_sub, id DESC)""")
            else:
                conn.execute("""CREATE TABLE IF NOT EXISTS cp_ai_settings (
                    owner_sub TEXT PRIMARY KEY, enabled INTEGER NOT NULL DEFAULT 0,
                    updated_at TEXT NOT NULL)""")
                conn.execute("""CREATE TABLE IF NOT EXISTS cp_ai_memories (
                    id TEXT PRIMARY KEY, owner_sub TEXT NOT NULL,
                    note TEXT NOT NULL, created_at TEXT NOT NULL)""")
                conn.execute("""CREATE INDEX IF NOT EXISTS cp_ai_memories_owner
                    ON cp_ai_memories(owner_sub, created_at DESC)""")
                conn.execute("""CREATE TABLE IF NOT EXISTS cp_ai_messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    owner_sub TEXT NOT NULL, role TEXT NOT NULL,
                    content TEXT NOT NULL, created_at TEXT NOT NULL)""")
                conn.execute("""CREATE INDEX IF NOT EXISTS cp_ai_messages_owner
                    ON cp_ai_messages(owner_sub, id DESC)""")
            conn.commit()

    def enabled(self, user: str) -> bool:
        with self._connect() as conn:
            row = self._run(conn, "SELECT enabled FROM cp_ai_settings WHERE owner_sub=?", (user,)).fetchone()
            return bool(row[0]) if row else False

    def set_enabled(self, user: str, enabled: bool) -> dict:
        with self._connect() as conn:
            self._run(conn, """INSERT INTO cp_ai_settings(owner_sub,enabled,updated_at)
                VALUES(?,?,?) ON CONFLICT(owner_sub) DO UPDATE SET
                enabled=excluded.enabled,updated_at=excluded.updated_at""",
                (user, enabled, _as_iso()))
            if not enabled:
                # Opting out removes context, not merely hides it.
                self._run(conn, "DELETE FROM cp_ai_messages WHERE owner_sub=?", (user,))
                self._run(conn, "DELETE FROM cp_ai_memories WHERE owner_sub=?", (user,))
            conn.commit()
        return {"memory_enabled": enabled, "previous_memory_deleted": not enabled}

    def remember(self, user: str, note_id: str, note: str) -> dict:
        if not self.enabled(user):
            raise ValueError("Enable AI memory before saving a preference")
        with self._connect() as conn:
            count = self._run(conn, "SELECT COUNT(*) FROM cp_ai_memories WHERE owner_sub=?", (user,)).fetchone()[0]
            if count >= 50:
                raise ValueError("Maximum 50 saved preferences; remove an old one")
            self._run(conn, "INSERT INTO cp_ai_memories(id,owner_sub,note,created_at) VALUES(?,?,?,?)",
                      (note_id, user, note, _as_iso()))
            conn.commit()
        return {"id": note_id, "note": note}

    def memories(self, user: str):
        if not self.enabled(user):
            return []
        with self._connect() as conn:
            rows = self._run(conn,
                "SELECT id,note FROM cp_ai_memories WHERE owner_sub=? ORDER BY created_at DESC LIMIT 50",
                (user,)).fetchall()
            return [{"id": row[0], "note": row[1]} for row in rows]

    def history(self, user: str, limit=20):
        if not self.enabled(user):
            return []
        with self._connect() as conn:
            rows = self._run(conn,
                "SELECT role,content FROM cp_ai_messages WHERE owner_sub=? ORDER BY id DESC LIMIT ?",
                (user, min(max(limit, 1), 40))).fetchall()
            return [{"role": row[0], "content": row[1]} for row in reversed(rows)]

    def append(self, user: str, role: str, content: str):
        if role not in ("user", "assistant") or len(content) > 4000:
            raise ValueError("Invalid chat entry")
        # No retention unless explicitly opted in.
        with self._connect() as conn:
            row = self._run(conn, "SELECT enabled FROM cp_ai_settings WHERE owner_sub=?", (user,)).fetchone()
            if not row or not row[0]:
                return False
            self._run(conn, "INSERT INTO cp_ai_messages(owner_sub,role,content,created_at) VALUES(?,?,?,?)",
                      (user, role, content, _as_iso()))
            self._run(conn, """DELETE FROM cp_ai_messages
                WHERE owner_sub=? AND id NOT IN (
                SELECT id FROM cp_ai_messages WHERE owner_sub=? ORDER BY id DESC LIMIT 100)""", (user, user))
            conn.commit()
            return True

    def remove(self, user: str, note_id: str) -> bool:
        with self._connect() as conn:
            cursor = self._run(conn, "DELETE FROM cp_ai_memories WHERE owner_sub=? AND id=?", (user,note_id))
            conn.commit()
            return cursor.rowcount > 0

    def clear(self, user: str):
        with self._connect() as conn:
            self._run(conn, "DELETE FROM cp_ai_memories WHERE owner_sub=?", (user,))
            self._run(conn, "DELETE FROM cp_ai_messages WHERE owner_sub=?", (user,))
            conn.commit()
        return {"cleared": True}
