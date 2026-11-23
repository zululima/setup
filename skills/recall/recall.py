#!/usr/bin/env python3
"""recall: one search over what earlier Claude Code sessions said, memory notes
and meeting notes, by keywords (SQLite FTS5, BM25), by meaning (an embedding
model in a local Ollama) and by regex.

  recall.py "query" [--kind K,K] [--project P] [--role R] [--since DATE]
                    [--until DATE] [--regex PATTERN] [--limit N] [--all-sessions]
  recall.py --regex PATTERN [...]   the newest text matching the pattern
  recall.py show ID [--around N]    a hit with the messages around it
  recall.py index                   add what changed and embed everything left
  recall.py status                  what the index holds

A search first adds what changed since the last run, then embeds new text for
up to RECALL_BUDGET seconds (default 30), newest first. RECALL_MODEL names the
embedding model (default qwen3-embedding:0.6b); without Ollama or the model a
search runs on keywords alone. Meaning hits under RECALL_MIN_SIMILARITY (cosine,
default 0.45) are dropped, and RECALL_DEBUG=1 prints each hit's scores. The
index lives in ~/.claude/state/recall and
never leaves this machine. sources.txt beside this script may list more files,
one "<kind> <glob>" per line.
"""

import atexit
import fcntl
import glob
import hashlib
import heapq
import json
import math
import os
import re
import shutil
import signal
import sqlite3
import struct
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
CLAUDE = os.path.join(HOME, ".claude")
STATE = os.path.join(CLAUDE, "state", "recall")
DB_PATH = os.path.join(STATE, "index.db")
HERE = os.path.dirname(os.path.realpath(__file__))
MODEL = os.environ.get("RECALL_MODEL", "qwen3-embedding:0.6b")
BUDGET = float(os.environ.get("RECALL_BUDGET", "30"))
_host = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434").replace("0.0.0.0", "127.0.0.1")
API = _host if _host.startswith("http") else "http://" + _host
VEC_MIN = float(os.environ.get("RECALL_MIN_SIMILARITY", "0.45"))
DEBUG = os.environ.get("RECALL_DEBUG") == "1"
DIMS = 512
CHUNK = 1500
OVERLAP = 200
MAX_PARTS = 40
EMBED_PARTS = 3
QUERY_PREFIX = ("Instruct: Given a search query, retrieve passages from earlier conversations "
                "and notes that answer it\nQuery: ") if "qwen3" in MODEL else ""

REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
NOT_TYPED = ("<command-name>", "<command-message>", "<local-command-", "Caveat: The messages below",
             "Base directory for this skill", "[Request interrupted", "<task-notification>",
             "<side-sessions-event>", "<ci-monitor-event>", "This session is being continued")


def utc(ts):
    return ts[:19] + "Z" if ts else ""


def local_time(ts):
    try:
        t = datetime.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
        return t.astimezone().strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return ts


def tilde(path):
    return "~" + path[len(HOME):] if path.startswith(HOME) else path


def project_of(path, cwd=None):
    m = re.match(re.escape(CLAUDE) + r"/projects/([^/]+)/", path)
    d = m.group(1) if m else (cwd or "")
    if not d:
        m = re.match(re.escape(CLAUDE) + r"/meetings/([^/]+)/", path)
        return m.group(1) if m else ""
    if "scratch-workspaces" in d:
        return "no-folder"
    if cwd and not m:
        return os.path.basename(cwd.rstrip("/")) or "home"
    if re.match(r"^-(Users|home)-[^-]+$", d):
        return "home"
    return re.sub(r"^Projects-", "", re.sub(r"^-(Users|home)-[^-]+-", "", d))


def pieces(text):
    if len(text) <= CHUNK:
        return [text]
    out, i = [], 0
    while i < len(text) and len(out) < MAX_PARTS:
        j = min(len(text), i + CHUNK)
        if j < len(text):
            k = max(text.rfind("\n", i + CHUNK // 2, j), text.rfind(" ", i + CHUNK - 200, j))
            if k > i:
                j = k
        out.append(text[i:j].strip())
        if j >= len(text):
            break
        i = j - OVERLAP if j - OVERLAP > i else j
    return [p for p in out if p]


def message_text(o):
    if o.get("type") not in ("user", "assistant") or o.get("isMeta") or o.get("isCompactSummary"):
        return None
    c = (o.get("message") or {}).get("content")
    if isinstance(c, str):
        parts = [c]
    elif isinstance(c, list):
        parts = [b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text"]
    else:
        return None
    t = REMINDER.sub("", "\n".join(parts)).strip()
    return None if not t or t.startswith(NOT_TYPED) else t


def connect():
    os.makedirs(STATE, exist_ok=True)
    db = sqlite3.connect(DB_PATH, timeout=30)
    db.execute("PRAGMA journal_mode=WAL")
    db.executescript("""
        CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY, size INTEGER, mtime REAL,
            ino INTEGER, offset INTEGER, line INTEGER);
        CREATE TABLE IF NOT EXISTS chunks(id INTEGER PRIMARY KEY, path TEXT, kind TEXT,
            project TEXT, session TEXT, ts TEXT, role TEXT, line INTEGER, part INTEGER,
            hash TEXT, embed INTEGER);
        CREATE INDEX IF NOT EXISTS chunks_path ON chunks(path, line, part);
        CREATE INDEX IF NOT EXISTS chunks_embed ON chunks(embed, ts);
        CREATE VIRTUAL TABLE IF NOT EXISTS fts USING fts5(text, tokenize="unicode61 remove_diacritics 0");
        CREATE TABLE IF NOT EXISTS vec(id INTEGER PRIMARY KEY, bits BLOB, v BLOB);
        CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
    """)
    row = db.execute("SELECT v FROM meta WHERE k='model'").fetchone()
    if row and row[0] != "%s/%d" % (MODEL, DIMS):
        db.execute("DELETE FROM vec")
        db.execute("UPDATE chunks SET embed=1 WHERE embed=2")
    db.execute("INSERT OR REPLACE INTO meta VALUES('model', ?)", ("%s/%d" % (MODEL, DIMS),))
    db.commit()
    return db


def sources():
    out = []
    sessions = glob.glob(CLAUDE + "/projects/*/*.jsonl")
    out += [("session", p) for p in sessions]
    out += [("subagent", p) for p in glob.glob(CLAUDE + "/projects/*/*/subagents/*.jsonl")]
    out += [("memory", p) for p in glob.glob(CLAUDE + "/projects/*/memory/*.md")]
    out += [("meeting", p) for p in glob.glob(CLAUDE + "/projects/*/meetings/**/*.md", recursive=True)]
    out += [("meeting", p) for p in glob.glob(CLAUDE + "/meetings/**/*.md", recursive=True)]
    have = {os.path.basename(p)[:-6] for p in sessions}
    out += [("prompt", p) for p in glob.glob(CLAUDE + "/prompt-log/*.jsonl")
            if os.path.basename(p)[:-6] not in have]
    listed = os.path.join(HERE, "sources.txt")
    if os.path.exists(listed):
        for line in open(listed, encoding="utf-8"):
            parts = line.split(None, 1)
            if len(parts) == 2 and not parts[0].startswith("#"):
                pattern = os.path.expanduser(parts[1].strip())
                out += [(parts[0], p) for p in glob.glob(pattern, recursive=True) if os.path.isfile(p)]
    return out


def drop(db, path):
    ids = [r[0] for r in db.execute("SELECT id FROM chunks WHERE path=?", (path,))]
    for n in range(0, len(ids), 500):
        batch = ids[n:n + 500]
        marks = ",".join("?" * len(batch))
        for table, key in (("fts", "rowid"), ("vec", "id"), ("chunks", "id")):
            db.execute("DELETE FROM %s WHERE %s IN (%s)" % (table, key, marks), batch)


def add(db, path, kind, project, session, ts, role, line, text):
    for part, p in enumerate(pieces(text)):
        want = 1 if kind != "subagent" and part < EMBED_PARTS else 0
        cur = db.execute(
            "INSERT INTO chunks(path,kind,project,session,ts,role,line,part,hash,embed)"
            " VALUES(?,?,?,?,?,?,?,?,?,?)",
            (path, kind, project, session, ts, role, line, part,
             hashlib.sha1(p.encode()).hexdigest()[:16], want))
        db.execute("INSERT INTO fts(rowid, text) VALUES(?, ?)", (cur.lastrowid, p))


def index_jsonl(db, path, kind, start, line):
    with open(path, "rb") as f:
        f.seek(start)
        data = f.read()
    end = data.rfind(b"\n") + 1
    stem = os.path.basename(path)[:-6]
    for raw in data[:end].split(b"\n")[:-1]:
        line += 1
        try:
            o = json.loads(raw)
        except ValueError:
            continue
        if kind == "prompt":
            text = REMINDER.sub("", o.get("prompt") or "").strip()
            if text and not text.startswith(NOT_TYPED):
                add(db, path, kind, project_of(path, o.get("cwd")), o.get("session_id") or stem,
                    utc(o.get("timestamp")), "user", line, text)
            continue
        text = message_text(o)
        if text:
            add(db, path, kind, project_of(path), o.get("sessionId") or stem,
                utc(o.get("timestamp")), o["type"], line, text)
    return start + end, line


def index_text(db, path, kind, st):
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return
    ts = datetime.fromtimestamp(st.st_mtime, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    paras, cur = [], ""
    for para in re.split(r"\n\s*\n", text):
        if cur and len(cur) + len(para) > CHUNK:
            paras.append(cur)
            cur = ""
        cur = (cur + "\n\n" + para).strip()
    if cur:
        paras.append(cur)
    for n, p in enumerate(paras):
        add(db, path, kind, project_of(path), None, ts, "", n + 1, p)


def update(db, verbose=False):
    seen, changed = set(), 0
    for kind, path in sources():
        seen.add(path)
        try:
            st = os.stat(path)
        except OSError:
            continue
        row = db.execute("SELECT size, mtime, ino, offset, line FROM files WHERE path=?",
                         (path,)).fetchone()
        if row and row[0] == st.st_size and row[1] == st.st_mtime and row[2] == st.st_ino:
            continue
        if path.endswith(".jsonl"):
            # A file sync replaces a growing transcript with a new inode, so only a shrink
            # means a rewrite.
            start, line = (row[3], row[4]) if row and st.st_size >= row[3] else (0, 0)
            if start == 0 and row:
                drop(db, path)
            offset, line = index_jsonl(db, path, kind, start, line)
        else:
            if row:
                drop(db, path)
            index_text(db, path, kind, st)
            offset, line = 0, 0
        db.execute("INSERT OR REPLACE INTO files VALUES(?,?,?,?,?,?)",
                   (path, st.st_size, st.st_mtime, st.st_ino, offset, line))
        changed += 1
        if changed % 200 == 0:
            db.commit()
            if verbose:
                print("indexed %d files" % changed, file=sys.stderr)
    for (path,) in db.execute("SELECT path FROM files").fetchall():
        if path not in seen:
            drop(db, path)
            db.execute("DELETE FROM files WHERE path=?", (path,))
    db.commit()
    return changed


class Ollama:
    def __init__(self):
        self.proc = None
        self.ready = None

    def call(self, route, body=None, timeout=300):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(API + route, data=data, headers={"Content-Type": "application/json"})
        return json.load(urllib.request.urlopen(req, timeout=timeout))

    def up(self):
        if self.ready is not None:
            return self.ready
        self.ready = False
        try:
            self.call("/api/version", timeout=2)
        except Exception:
            if not shutil.which("ollama"):
                self.why = "Ollama is not installed"
                return False
            log = open(os.path.join(STATE, "ollama.log"), "ab")
            self.proc = subprocess.Popen(["ollama", "serve"], stdout=log, stderr=log,
                                         stdin=subprocess.DEVNULL, start_new_session=True)
            atexit.register(self.down)
            for _ in range(60):
                time.sleep(0.25)
                try:
                    self.call("/api/version", timeout=2)
                    break
                except Exception:
                    pass
            else:
                self.why = "Ollama did not start"
                return False
        try:
            names = {m.get("name") for m in self.call("/api/tags").get("models", [])}
        except Exception as e:
            self.why = "Ollama did not answer (%s)" % e
            return False
        if MODEL not in names and MODEL + ":latest" not in names:
            self.why = "the model %s is not pulled (ollama pull %s)" % (MODEL, MODEL)
            return False
        self.ready = True
        return True

    def down(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(10)
            except subprocess.TimeoutExpired:
                self.proc.kill()

    def embed(self, texts):
        return self.call("/api/embed", {"model": MODEL, "input": texts, "truncate": True,
                                        "keep_alive": "60s"})["embeddings"]


def pack(vector):
    v = vector[:DIMS]
    norm = math.sqrt(sum(x * x for x in v)) or 1.0
    v = [x / norm for x in v]
    bits = 0
    for i, x in enumerate(v):
        if x > 0:
            bits |= 1 << i
    return bits.to_bytes(DIMS // 8, "little"), struct.pack("<%de" % DIMS, *v)


def waiting(db):
    return db.execute("SELECT count(*) FROM chunks WHERE embed=1").fetchone()[0]


def embed_pending(db, ollama, budget=None, verbose=False):
    if budget == 0 or not waiting(db) or not ollama.up():
        return
    deadline = time.time() + budget if budget is not None else None
    done = 0
    while deadline is None or time.time() < deadline:
        rows = db.execute("SELECT c.id, f.text FROM chunks c JOIN fts f ON f.rowid = c.id"
                          " WHERE c.embed=1 ORDER BY c.ts DESC LIMIT 32").fetchall()
        if not rows:
            break
        for (cid, _), e in zip(rows, ollama.embed([t[:CHUNK] for _, t in rows])):
            bits, v = pack(e)
            db.execute("INSERT OR REPLACE INTO vec VALUES(?,?,?)", (cid, bits, v))
            db.execute("UPDATE chunks SET embed=2 WHERE id=?", (cid,))
        db.commit()
        done += len(rows)
        if verbose and done % 640 < 32:
            print("embedded %d, %d waiting" % (done, waiting(db)), file=sys.stderr)


def with_lock(block):
    os.makedirs(STATE, exist_ok=True)
    fh = open(os.path.join(STATE, "update.lock"), "w")
    try:
        fcntl.flock(fh, fcntl.LOCK_EX | (0 if block else fcntl.LOCK_NB))
        return fh
    except BlockingIOError:
        fh.close()
        return None


def filters(args):
    conds, params = [], []
    if args["kind"]:
        kinds = args["kind"].split(",")
        conds.append("c.kind IN (%s)" % ",".join("?" * len(kinds)))
        params += kinds
    for key, cond, value in (("project", "c.project LIKE ?", "%%%s%%"), ("role", "c.role = ?", "%s"),
                             ("since", "c.ts >= ?", "%s"), ("until", "c.ts <= ?", "%sT23:59:59Z"),
                             ("session", "c.session LIKE ?", "%s%%")):
        if args[key]:
            conds.append(cond)
            params.append(value % args[key])
    current = os.environ.get("CLAUDE_CODE_SESSION_ID")
    if current and not args["all_sessions"]:
        conds.append("(c.session IS NULL OR c.session != ?)")
        params.append(current)
    return "".join(" AND " + c for c in conds), params


def chunk_rows(db, ids):
    out = {}
    for n in range(0, len(ids), 500):
        batch = ids[n:n + 500]
        for r in db.execute("SELECT c.id, c.kind, c.project, c.session, c.ts, c.role, c.path,"
                            " c.line, c.hash, f.text FROM chunks c JOIN fts f ON f.rowid = c.id"
                            " WHERE c.id IN (%s)" % ",".join("?" * len(batch)), batch):
            out[r[0]] = r
    return out


def snippet(text, terms, width=300):
    flat = re.sub(r"\s+", " ", text)
    low = flat.lower()
    hits = [low.find(t.lower()) for t in terms if low.find(t.lower()) >= 0]
    start = max(0, min(hits) - width // 3) if hits else 0
    out = flat[start:start + width]
    return ("..." if start else "") + out + ("..." if start + width < len(flat) else "")


def search(db, ollama, args):
    where, params = filters(args)
    query, terms, lists, notes, cosine = args["query"], [], [], [], {}
    rx = re.compile(args["regex"], re.I) if args["regex"] else None
    if query:
        terms = [w for w in re.findall(r"\w+", query) if len(w) >= 2]
        if terms:
            match = " OR ".join('"%s"*' % w for w in terms)
            lists.append([r[0] for r in db.execute(
                "SELECT c.id FROM fts JOIN chunks c ON c.id = fts.rowid WHERE fts MATCH ?" + where +
                " ORDER BY bm25(fts) LIMIT 80", [match] + params)])
        if ollama.up():
            qbits, qv = pack(ollama.embed([QUERY_PREFIX + query])[0])
            qi = int.from_bytes(qbits, "little")
            near = heapq.nsmallest(800, ((bin(int.from_bytes(b, "little") ^ qi).count("1"), i)
                                         for i, b in db.execute("SELECT id, bits FROM vec")))
            ids = [i for _, i in near]
            qf = struct.unpack("<%de" % DIMS, qv)
            scored = []
            for n in range(0, len(ids), 500):
                batch = ids[n:n + 500]
                for i, v in db.execute("SELECT c.id, v.v FROM chunks c JOIN vec v ON v.id = c.id"
                                       " WHERE c.id IN (%s)" % ",".join("?" * len(batch)) + where,
                                       batch + params):
                    scored.append((sum(a * b for a, b in zip(qf, struct.unpack("<%de" % DIMS, v))), i))
            top = sorted(scored, reverse=True)[:80]
            cosine = {i: s for s, i in top}
            lists.append([i for s, i in top if s >= VEC_MIN])
            left = waiting(db)
            if left:
                notes.append("%d newer chunks wait for embeddings and match by keywords only;"
                             " recall.py index embeds them" % left)
        else:
            notes.append("keywords only: " + ollama.why)
    score = {}
    for ranked in lists:
        for rank, cid in enumerate(ranked):
            score[cid] = score.get(cid, 0) + 1.0 / (60 + rank)
    order = sorted(score, key=score.get, reverse=True)
    rows = chunk_rows(db, order)
    if rx and not query:
        order, rows = [], {}
        for r in db.execute("SELECT c.id, c.kind, c.project, c.session, c.ts, c.role, c.path,"
                            " c.line, c.hash, f.text FROM chunks c JOIN fts f ON f.rowid = c.id"
                            " WHERE 1=1" + where + " ORDER BY c.ts DESC", params):
            if rx.search(r[9]):
                order.append(r[0])
                rows[r[0]] = r
                if len(order) >= args["limit"] * 3:
                    break
    shown, seen = 0, set()
    for cid in order:
        r = rows.get(cid)
        if not r:
            continue
        # A reply rewritten after a hook, or a meeting kept in two places, starts the same.
        opening = re.sub(r"\s+", " ", r[9])[:150]
        if opening in seen or (rx and not rx.search(r[9])):
            continue
        seen.add(opening)
        shown += 1
        _, kind, project, session, ts, role, path, line, _, text = r
        head = " ".join(x for x in ("%d. [%d]" % (shown, cid), local_time(ts), kind, project,
                                    (session or "")[:8], role) if x)
        if DEBUG:
            head += "  rrf %.4f cos %s" % (score.get(cid, 0), "%.3f" % cosine[cid] if cid in cosine else "-")
        print(head)
        found = [m.group(0) for m in rx.finditer(text)][:1] if rx and not terms else terms
        print("   " + snippet(text, found))
        print("   %s:%d" % (tilde(path), line))
        if shown >= args["limit"]:
            break
    if not shown:
        print("no hits")
    for note in notes:
        print("(%s)" % note)


def show(db, cid, around):
    row = db.execute("SELECT path FROM chunks WHERE id=?", (cid,)).fetchone()
    if not row:
        sys.exit("no chunk %d" % cid)
    ids = [r[0] for r in db.execute("SELECT id FROM chunks WHERE path=? ORDER BY line, part", row)]
    at = ids.index(cid)
    rows = chunk_rows(db, ids[max(0, at - around):at + around + 1])
    print(tilde(row[0]))
    for i in ids[max(0, at - around):at + around + 1]:
        r = rows[i]
        mark = ">>>" if i == cid else "---"
        print("\n%s [%d] %s %s line %d" % (mark, i, local_time(r[4]), r[5] or r[1], r[7]))
        print(r[9])


def status(db):
    total = db.execute("SELECT count(*) FROM chunks").fetchone()[0]
    print("index %s, %.0f MB, model %s" % (tilde(DB_PATH), os.path.getsize(DB_PATH) / 1e6, MODEL))
    print("%d chunks from %d files, %d embedded, %d waiting" % (
        total, db.execute("SELECT count(*) FROM files").fetchone()[0],
        db.execute("SELECT count(*) FROM vec").fetchone()[0], waiting(db)))
    for kind, n, newest in db.execute("SELECT kind, count(*), max(ts) FROM chunks GROUP BY kind"
                                      " ORDER BY count(*) DESC"):
        print("  %-10s %7d  newest %s" % (kind, n, local_time(newest or "")))


def main(argv):
    if argv and argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))
    db = connect()
    ollama = Ollama()
    if argv and argv[0] == "index":
        lock = with_lock(True)
        update(db, verbose=True)
        embed_pending(db, ollama, verbose=True)
        if waiting(db) and not ollama.up():
            print("not embedded: " + ollama.why, file=sys.stderr)
        status(db)
        return
    if argv and argv[0] == "status":
        status(db)
        return
    if argv and argv[0] == "show":
        around = int(argv[argv.index("--around") + 1]) if "--around" in argv else 4
        show(db, int(argv[1]), around)
        return
    args = {"query": "", "kind": None, "project": None, "role": None, "since": None, "until": None,
            "session": None, "regex": None, "limit": 10, "all_sessions": False}
    words, it = [], iter(argv)
    for a in it:
        key = a[2:].replace("-", "_")
        if a == "--all-sessions":
            args["all_sessions"] = True
        elif a.startswith("--") and key in args:
            args[key] = int(next(it)) if key == "limit" else next(it)
        else:
            words.append(a)
    args["query"] = " ".join(words).strip()
    if not args["query"] and not args["regex"]:
        sys.exit(__doc__.strip())
    lock = with_lock(False)
    if lock:
        update(db)
        embed_pending(db, ollama, budget=BUDGET)
        lock.close()
    search(db, ollama, args)


if __name__ == "__main__":
    main(sys.argv[1:])
