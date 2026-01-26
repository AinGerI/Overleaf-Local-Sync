from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import tkinter as tk
from datetime import datetime, timezone
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from urllib.parse import urlparse


REPO_ROOT = Path(__file__).resolve().parents[1]
OL_SYNC = REPO_ROOT / "overleaf-sync" / "ol-sync.mjs"
DEFAULT_CREATE_PARENT_DIR = REPO_ROOT / "overleaf-projects"
PROJECT_ID_RE = re.compile(r"^Created\s+([0-9a-f]{24})\s*$", re.IGNORECASE | re.MULTILINE)
GUI_STATE_PATH = Path.home() / ".config" / "overleaf-sync" / "gui.json"
INBOX_ROOT = Path.home() / ".config" / "overleaf-sync" / "inbox"
BACKUP_ROOT = Path.home() / ".config" / "overleaf-sync" / "backups"

REMOTE_POLL_INTERVAL_SEC = 30
BACKUP_INTERVAL_SEC = 120
OUTGOING_SUPPRESS_SEC = 90


def _build_env(email: str, password: str) -> dict[str, str]:
    env = os.environ.copy()
    if email.strip():
        env["OVERLEAF_SYNC_EMAIL"] = email.strip()
    if password:
        env["OVERLEAF_SYNC_PASSWORD"] = password
    return env


def _run_node(args: list[str], env: dict[str, str]) -> tuple[int, str, str]:
    cmd = ["node", str(OL_SYNC), *args]
    proc = subprocess.run(
        cmd,
        cwd=str(REPO_ROOT),
        env=env,
        text=True,
        capture_output=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


def _load_gui_state() -> dict:
    try:
        raw = GUI_STATE_PATH.read_text(encoding="utf-8")
        parsed = json.loads(raw)
        return parsed if isinstance(parsed, dict) else {}
    except Exception:
        return {}


def _save_gui_state(state: dict) -> None:
    GUI_STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = GUI_STATE_PATH.with_suffix(f".json.tmp-{os.getpid()}-{int(time.time()*1000)}")
    tmp_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp_path.replace(GUI_STATE_PATH)
    try:
        os.chmod(GUI_STATE_PATH, 0o600)
    except Exception:
        pass


def _sanitize_folder_name(name: str, fallback: str) -> str:
    raw = (name or "").strip()
    if not raw:
        return fallback
    cleaned = re.sub(r"[\\/:\0]+", "_", raw).strip()
    return cleaned or fallback


def _unique_child_dir(parent: Path, name: str) -> Path:
    candidate = parent / name
    if not candidate.exists():
        return candidate
    for i in range(1, 1000):
        cand = parent / f"{name} ({i})"
        if not cand.exists():
            return cand
    raise RuntimeError("Could not find a free folder name.")


def _normalize_base_url(base_url: str) -> str:
    return str(base_url or "").rstrip("/")


def _safe_component(value: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9._-]+", "_", str(value or "")).strip("_")
    return cleaned or "overleaf"


def _safe_host(base_url: str) -> str:
    try:
        host = urlparse(str(base_url)).netloc
    except Exception:
        host = str(base_url)
    return _safe_component(host or str(base_url))


def _project_key(base_url: str, project_id: str) -> str:
    return f"{_normalize_base_url(base_url)}|{project_id}"


class OverleafSyncGui:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("Overleaf Local Sync (Unofficial)")
        self.root.geometry("980x720")

        self._state = _load_gui_state()

        self.base_url = tk.StringVar(value="http://localhost")
        self.email = tk.StringVar(value="")
        self.password = tk.StringVar(value="")
        self.active_only = tk.BooleanVar(value=True)
        self.force = tk.BooleanVar(value=False)
        self.dry_run = tk.BooleanVar(value=False)
        self.concurrency = tk.StringVar(value="4")
        self.local_dir = tk.StringVar(value=self._state.get("local_dir") or "")
        self.new_project_name = tk.StringVar(value="")
        self.create_parent_dir = tk.StringVar(
            value=self._state.get("create_parent_dir")
            or (str(DEFAULT_CREATE_PARENT_DIR) if DEFAULT_CREATE_PARENT_DIR.is_dir() else "")
        )
        self.download_parent_dir = tk.StringVar(value=self._state.get("download_parent_dir") or "")
        self.init_main_tex = tk.BooleanVar(value=True)
        self.push_after_create = tk.BooleanVar(value=True)
        self.auto_watch_after_create = tk.BooleanVar(value=True)

        self.remote_pending_var = tk.StringVar(value="Remote pending: 0")

        self._projects: list[dict] = []
        self._watches: dict[str, subprocess.Popen[str]] = {}
        self._watch_threads: dict[str, threading.Thread] = {}
        self._inbox_manifest: dict | None = None
        self._dirty_files: dict[str, set[str]] = {}
        self._dir_project_key: dict[str, str] = {}
        self._last_outgoing: dict[str, float] = {}
        self._stop_event = threading.Event()
        self._last_remote_poll_error_at = 0.0
        self._last_backup_error_at = 0.0

        self._build_ui()
        self._start_background_tasks()

    def _build_ui(self) -> None:
        frm = ttk.Frame(self.root, padding=12)
        frm.pack(fill="both", expand=True)
        frm.columnconfigure(0, weight=1)
        frm.columnconfigure(1, weight=1)

        conn = ttk.LabelFrame(frm, text="Connection", padding=10)
        conn.grid(row=0, column=0, sticky="nsew", padx=(0, 8), pady=(0, 8))
        conn.columnconfigure(1, weight=1)

        ttk.Label(conn, text="Base URL").grid(row=0, column=0, sticky="w")
        ttk.Entry(conn, textvariable=self.base_url).grid(row=0, column=1, sticky="ew", padx=(8, 0))

        ttk.Label(conn, text="Email").grid(row=1, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(conn, textvariable=self.email).grid(row=1, column=1, sticky="ew", padx=(8, 0), pady=(8, 0))

        ttk.Label(conn, text="Password").grid(row=2, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(conn, textvariable=self.password, show="*").grid(
            row=2, column=1, sticky="ew", padx=(8, 0), pady=(8, 0)
        )

        opt_row = ttk.Frame(conn)
        opt_row.grid(row=3, column=0, columnspan=2, sticky="ew", pady=(10, 0))
        ttk.Checkbutton(opt_row, text="Active only", variable=self.active_only).pack(side="left")
        ttk.Button(opt_row, text="Load projects", command=self.load_projects).pack(side="right")

        projects = ttk.LabelFrame(frm, text="Projects", padding=10)
        projects.grid(row=1, column=0, sticky="nsew", padx=(0, 8), pady=(0, 8))
        projects.rowconfigure(0, weight=1)
        projects.columnconfigure(0, weight=1)

        cols = ("name", "id", "access", "archived", "trashed")
        self.tree = ttk.Treeview(projects, columns=cols, show="headings", selectmode="browse")
        self.tree.heading("name", text="Name")
        self.tree.heading("id", text="Project ID")
        self.tree.heading("access", text="Access")
        self.tree.heading("archived", text="Archived")
        self.tree.heading("trashed", text="Trashed")
        self.tree.column("name", width=320)
        self.tree.column("id", width=220)
        self.tree.column("access", width=90, anchor="center")
        self.tree.column("archived", width=80, anchor="center")
        self.tree.column("trashed", width=80, anchor="center")
        self.tree.grid(row=0, column=0, sticky="nsew")
        self.tree.bind("<<TreeviewSelect>>", self._on_select_project)

        scroll = ttk.Scrollbar(projects, orient="vertical", command=self.tree.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.tree.configure(yscrollcommand=scroll.set)

        actions = ttk.LabelFrame(frm, text="Sync actions", padding=10)
        actions.grid(row=0, column=1, rowspan=2, sticky="nsew", pady=(0, 8))
        actions.columnconfigure(1, weight=1)

        ttk.Label(actions, text="Local folder").grid(row=0, column=0, sticky="w")
        ttk.Entry(actions, textvariable=self.local_dir).grid(row=0, column=1, sticky="ew", padx=(8, 0))
        ttk.Button(actions, text="Browse", command=self._browse_dir).grid(row=0, column=2, padx=(8, 0))

        ttk.Checkbutton(actions, text="Force overwrite .ol-sync.json", variable=self.force).grid(
            row=1, column=0, columnspan=3, sticky="w", pady=(8, 0)
        )

        ttk.Label(actions, text="Concurrency (push)").grid(row=2, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(actions, textvariable=self.concurrency, width=6).grid(row=2, column=1, sticky="w", padx=(8, 0), pady=(8, 0))
        ttk.Checkbutton(actions, text="Dry run", variable=self.dry_run).grid(row=2, column=2, sticky="e", pady=(8, 0))

        btn_row = ttk.Frame(actions)
        btn_row.grid(row=3, column=0, columnspan=3, sticky="ew", pady=(10, 0))
        self.btn_link = ttk.Button(btn_row, text="Link", command=self.link_selected)
        self.btn_push = ttk.Button(btn_row, text="Push", command=self.push)
        self.btn_pull = ttk.Button(btn_row, text="Pull (download)", command=self.pull_selected)
        self.btn_watch = ttk.Button(btn_row, text="Watch", command=self.watch)
        self.btn_stop = ttk.Button(btn_row, text="Stop watch (this folder)", command=self.stop_watch)
        self.btn_link.pack(side="left")
        self.btn_push.pack(side="left", padx=(8, 0))
        self.btn_pull.pack(side="left", padx=(8, 0))
        self.btn_watch.pack(side="left", padx=(8, 0))
        self.btn_stop.pack(side="right")

        watches = ttk.LabelFrame(actions, text="Active watches", padding=8)
        watches.grid(row=4, column=0, columnspan=3, sticky="nsew", pady=(12, 0))
        watches.columnconfigure(0, weight=1)
        watches.rowconfigure(0, weight=1)

        watch_cols = ("path", "pid", "remote_pending")
        self.watch_tree = ttk.Treeview(watches, columns=watch_cols, show="headings", selectmode="browse", height=6)
        self.watch_tree.heading("path", text="Folder")
        self.watch_tree.heading("pid", text="PID")
        self.watch_tree.heading("remote_pending", text="Remote")
        self.watch_tree.column("path", width=460)
        self.watch_tree.column("pid", width=80, anchor="center")
        self.watch_tree.column("remote_pending", width=80, anchor="center")
        self.watch_tree.grid(row=0, column=0, sticky="nsew")

        watch_scroll = ttk.Scrollbar(watches, orient="vertical", command=self.watch_tree.yview)
        watch_scroll.grid(row=0, column=1, sticky="ns")
        self.watch_tree.configure(yscrollcommand=watch_scroll.set)

        watch_btns = ttk.Frame(watches)
        watch_btns.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(8, 0))
        ttk.Button(watch_btns, text="Stop selected", command=self.stop_selected_watch).pack(side="left")
        ttk.Button(watch_btns, text="Stop all", command=self.stop_all_watches).pack(side="left", padx=(8, 0))

        inbox = ttk.LabelFrame(actions, text="Incoming changes (from web)", padding=8)
        inbox.grid(row=5, column=0, columnspan=3, sticky="nsew", pady=(12, 0))
        inbox.columnconfigure(0, weight=1)
        inbox.rowconfigure(1, weight=1)

        inbox_btns = ttk.Frame(inbox)
        inbox_btns.grid(row=0, column=0, sticky="ew")
        ttk.Button(inbox_btns, text="Check remote", command=self.fetch_remote_changes).pack(side="left")
        ttk.Button(inbox_btns, text="Apply (last-write wins)", command=self.apply_remote_changes).pack(
            side="left", padx=(8, 0)
        )
        ttk.Label(inbox_btns, textvariable=self.remote_pending_var).pack(side="left", padx=(12, 0))
        ttk.Button(inbox_btns, text="Open inbox folder", command=self.open_inbox_folder).pack(
            side="right"
        )

        inbox_cols = ("path", "kind")
        self.inbox_tree = ttk.Treeview(inbox, columns=inbox_cols, show="headings", selectmode="browse", height=6)
        self.inbox_tree.heading("path", text="Path")
        self.inbox_tree.heading("kind", text="Kind")
        self.inbox_tree.column("path", width=520)
        self.inbox_tree.column("kind", width=120, anchor="center")
        self.inbox_tree.grid(row=1, column=0, sticky="nsew", pady=(8, 0))

        inbox_scroll = ttk.Scrollbar(inbox, orient="vertical", command=self.inbox_tree.yview)
        inbox_scroll.grid(row=1, column=1, sticky="ns", pady=(8, 0))
        self.inbox_tree.configure(yscrollcommand=inbox_scroll.set)

        create = ttk.LabelFrame(frm, text="Create project", padding=10)
        create.grid(row=2, column=0, sticky="nsew", padx=(0, 8))
        create.columnconfigure(1, weight=1)

        ttk.Label(create, text="New project name").grid(row=0, column=0, sticky="w")
        ttk.Entry(create, textvariable=self.new_project_name).grid(row=0, column=1, sticky="ew", padx=(8, 0))

        create_opts = ttk.Frame(create)
        create_opts.grid(row=1, column=0, columnspan=3, sticky="w", pady=(8, 0))
        ttk.Checkbutton(create_opts, text="Init main.tex", variable=self.init_main_tex).pack(side="left")
        ttk.Checkbutton(create_opts, text="Push after create", variable=self.push_after_create).pack(
            side="left", padx=(12, 0)
        )
        ttk.Checkbutton(create_opts, text="Auto watch", variable=self.auto_watch_after_create).pack(
            side="left", padx=(12, 0)
        )

        create_btns = ttk.Frame(create)
        create_btns.grid(row=2, column=0, columnspan=3, sticky="ew", pady=(10, 0))
        ttk.Button(create_btns, text="Create project…", command=self.create_project_flow).pack(side="left")

        logs = ttk.LabelFrame(frm, text="Logs", padding=10)
        logs.grid(row=2, column=1, sticky="nsew")
        logs.rowconfigure(0, weight=1)
        logs.columnconfigure(0, weight=1)

        self.log_text = tk.Text(logs, height=14, wrap="word")
        self.log_text.grid(row=0, column=0, sticky="nsew")
        log_scroll = ttk.Scrollbar(logs, orient="vertical", command=self.log_text.yview)
        log_scroll.grid(row=0, column=1, sticky="ns")
        self.log_text.configure(yscrollcommand=log_scroll.set)

        self._set_buttons_enabled(False)

    def _start_background_tasks(self) -> None:
        remote_thread = threading.Thread(target=self._remote_poll_loop, daemon=True)
        remote_thread.start()
        backup_thread = threading.Thread(target=self._backup_loop, daemon=True)
        backup_thread.start()

    def shutdown(self) -> None:
        self._stop_event.set()
        self.stop_all_watches()

    def _sync_info_for_dir(self, abs_dir: str) -> tuple[str, str, str, str] | None:
        cfg_path = Path(abs_dir) / ".ol-sync.json"
        try:
            cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
        except Exception:
            return None

        base_url = _normalize_base_url(str(cfg.get("baseUrl") or self.base_url.get().strip()))
        project_id = str(cfg.get("projectId") or "").strip()
        if not base_url or not project_id:
            return None
        key = _project_key(base_url, project_id)
        host = _safe_host(base_url)
        self._dir_project_key[abs_dir] = key

        remote_projects = self._state.setdefault("remote_projects", {})
        entry = remote_projects.setdefault(key, {})
        entry["baseUrl"] = base_url
        entry["projectId"] = project_id
        entry["dir"] = abs_dir
        return base_url, project_id, key, host

    def _remote_pending_total(self) -> int:
        remote_projects = self._state.get("remote_projects") or {}
        total = 0
        for entry in remote_projects.values():
            try:
                total += int(entry.get("pending") or 0)
            except Exception:
                continue
        return total

    def _remote_pending_for_dir(self, abs_dir: str) -> int:
        info = self._sync_info_for_dir(abs_dir)
        if not info:
            return 0
        _base_url, _project_id, key, _host = info
        entry = (self._state.get("remote_projects") or {}).get(key) or {}
        try:
            return int(entry.get("pending") or 0)
        except Exception:
            return 0

    def _update_remote_ui(self) -> None:
        self.remote_pending_var.set(f"Remote pending: {self._remote_pending_total()}")
        self._refresh_watch_list()

    def _remote_poll_loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                self._poll_remote_once()
            except Exception as exc:  # noqa: BLE001 - best-effort background loop
                now = time.time()
                if now - self._last_remote_poll_error_at > 300:
                    self._last_remote_poll_error_at = now
                    self._append_log_safe(f"[remote poll error] {exc}")
            self._stop_event.wait(REMOTE_POLL_INTERVAL_SEC)

    def _poll_remote_once(self) -> None:
        dirs: set[str] = set(self._watches.keys())
        local = self.local_dir.get().strip()
        if local:
            try:
                dirs.add(str(Path(local).resolve()))
            except Exception:
                pass

        tracked: dict[str, dict] = {}
        for abs_dir in dirs:
            info = self._sync_info_for_dir(abs_dir)
            if not info:
                continue
            base_url, project_id, key, _host = info
            tracked[key] = {"baseUrl": base_url, "projectId": project_id, "dir": abs_dir}

        if not tracked:
            return

        env = _build_env(self.email.get(), self.password.get())

        by_base: dict[str, set[str]] = {}
        for info in tracked.values():
            by_base.setdefault(info["baseUrl"], set()).add(info["projectId"])

        now = time.time()
        changed_any = False

        for base_url in sorted(by_base.keys()):
            code, out, err = _run_node(["projects", "--base-url", base_url, "--json"], env)
            if code != 0:
                if now - self._last_remote_poll_error_at > 300:
                    self._last_remote_poll_error_at = now
                    self._append_log_safe(err or out or f"[remote poll] projects failed: code={code}")
                continue
            try:
                projects = json.loads(out)
            except Exception:
                if now - self._last_remote_poll_error_at > 300:
                    self._last_remote_poll_error_at = now
                    self._append_log_safe(out)
                continue

            id_to_last: dict[str, str] = {}
            for p in projects or []:
                pid = str(p.get("id") or "")
                if not pid:
                    continue
                last = str(p.get("lastUpdated") or "")
                if last:
                    id_to_last[pid] = last

            remote_projects = self._state.setdefault("remote_projects", {})
            for key, info in tracked.items():
                if info["baseUrl"] != base_url:
                    continue
                project_id = info["projectId"]
                last = id_to_last.get(project_id)
                if not last:
                    continue
                entry = remote_projects.setdefault(key, {})
                prev = str(entry.get("lastUpdated") or "")
                entry["lastCheckedAt"] = datetime.now(timezone.utc).isoformat()
                entry["baseUrl"] = base_url
                entry["projectId"] = project_id
                entry["dir"] = info["dir"]

                if not prev:
                    entry["lastUpdated"] = last
                    changed_any = True
                    continue
                if last == prev:
                    continue

                entry["lastUpdated"] = last
                outgoing_ts = float(self._last_outgoing.get(key) or 0.0)
                if now - outgoing_ts <= OUTGOING_SUPPRESS_SEC:
                    changed_any = True
                    continue

                pending = int(entry.get("pending") or 0) + 1
                entry["pending"] = pending
                entry["dirty"] = True
                entry["lastChangedAt"] = datetime.now(timezone.utc).isoformat()
                changed_any = True

        if changed_any:
            _save_gui_state(self._state)
            self.root.after(0, self._update_remote_ui)

    def _backup_loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                self._backup_once()
            except Exception as exc:  # noqa: BLE001 - best-effort background loop
                now = time.time()
                if now - self._last_backup_error_at > 300:
                    self._last_backup_error_at = now
                    self._append_log_safe(f"[backup error] {exc}")
            self._stop_event.wait(BACKUP_INTERVAL_SEC)

    def _backup_once(self) -> None:
        # 1) local incremental backups (changed files since last run)
        if self._dirty_files:
            for abs_dir, rel_set in list(self._dirty_files.items()):
                if not rel_set:
                    continue
                info = self._sync_info_for_dir(abs_dir)
                if not info:
                    continue
                base_url, project_id, _key, host = info
                timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
                dest_root = BACKUP_ROOT / host / project_id / "local" / timestamp
                copied = 0
                for rel_posix in sorted(rel_set):
                    src = Path(abs_dir) / Path(*str(rel_posix).split("/"))
                    if not src.is_file():
                        continue
                    dst = dest_root / Path(*str(rel_posix).split("/"))
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(src, dst)
                    copied += 1
                if copied:
                    self._append_log_safe(f"[backup local] {project_id} files={copied} -> {dest_root}")
                rel_set.clear()

        # 2) remote snapshot backups (when remote changed)
        remote_projects = self._state.get("remote_projects") or {}
        dirty_keys = [k for k, v in remote_projects.items() if v.get("dirty")]
        if not dirty_keys:
            return

        env = _build_env(self.email.get(), self.password.get())
        for key in sorted(dirty_keys):
            entry = remote_projects.get(key) or {}
            abs_dir = str(entry.get("dir") or "")
            base_url = str(entry.get("baseUrl") or "").strip()
            project_id = str(entry.get("projectId") or "").strip()
            if not abs_dir or not base_url or not project_id:
                continue

            code, out, err = _run_node(["fetch", "--base-url", base_url, "--dir", abs_dir, "--json"], env)
            if code != 0:
                self._append_log_safe(err or out or f"[backup remote] fetch failed: code={code}")
                continue
            try:
                manifest = json.loads(out)
            except Exception:
                self._append_log_safe(out)
                continue

            batch_id = str(manifest.get("batchId") or "")
            inbox_dir = str(manifest.get("inboxDir") or "")
            if not batch_id or not inbox_dir:
                continue

            host = _safe_host(base_url)
            dest_root = BACKUP_ROOT / host / project_id / "remote" / batch_id
            changes = manifest.get("changes") or {}
            files = list(changes.get("added") or []) + [
                (e or {}).get("path") for e in (changes.get("modified") or [])
            ]
            copied = 0
            for rel_posix in sorted({f for f in files if f}):
                src = Path(inbox_dir) / Path(*str(rel_posix).split("/"))
                if not src.is_file():
                    continue
                dst = dest_root / Path(*str(rel_posix).split("/"))
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
                copied += 1

            entry["dirty"] = False
            entry["lastRemoteBackupAt"] = datetime.now(timezone.utc).isoformat()
            remote_projects[key] = entry
            _save_gui_state(self._state)
            if copied:
                self._append_log_safe(f"[backup remote] {project_id} files={copied} -> {dest_root}")

    def _mark_outgoing_for_dir(self, dir_path: str) -> None:
        try:
            abs_dir = str(Path(dir_path).resolve())
        except Exception:
            abs_dir = str(dir_path)
        info = self._sync_info_for_dir(abs_dir)
        if not info:
            return
        _base_url, _project_id, key, _host = info
        self._last_outgoing[key] = time.time()

    def _append_log(self, text: str) -> None:
        self.log_text.insert("end", text)
        if not text.endswith("\n"):
            self.log_text.insert("end", "\n")
        self.log_text.see("end")

    def _append_log_safe(self, text: str) -> None:
        self.root.after(0, lambda: self._append_log(text))

    def _set_buttons_enabled(self, enabled: bool) -> None:
        state = "normal" if enabled else "disabled"
        self.btn_link.configure(state=state)
        self.btn_push.configure(state=state)
        self.btn_pull.configure(state=state)
        self.btn_watch.configure(state=state)

    def _selected_project_id(self) -> str | None:
        sel = self.tree.selection()
        if not sel:
            return None
        item = self.tree.item(sel[0])
        values = item.get("values") or []
        if len(values) < 2:
            return None
        return str(values[1])

    def _selected_project_name(self) -> str | None:
        sel = self.tree.selection()
        if not sel:
            return None
        item = self.tree.item(sel[0])
        values = item.get("values") or []
        if not values:
            return None
        return str(values[0])

    def _browse_dir(self) -> None:
        initial = self.local_dir.get().strip() or self._state.get("local_dir") or None
        path = filedialog.askdirectory(title="Select local project folder", initialdir=initial)
        if path:
            self._set_local_dir(path)

    def _set_local_dir(self, path: str) -> None:
        self.local_dir.set(path)
        if path:
            self._state["local_dir"] = path
            _save_gui_state(self._state)

    def _on_select_project(self, _event: object) -> None:
        self._set_buttons_enabled(True)

    def load_projects(self) -> None:
        def work() -> None:
            env = _build_env(self.email.get(), self.password.get())
            base = self.base_url.get().strip()
            args = ["projects", "--base-url", base, "--json"]
            if self.active_only.get():
                args.append("--active-only")
            code, out, err = _run_node(args, env)
            if code != 0:
                self._append_log_safe(err or out or f"Command failed: {code}")
                self.root.after(
                    0,
                    lambda: messagebox.showerror(
                        "Load projects failed",
                        err or out or f"Exit code: {code}",
                    ),
                )
                return
            try:
                projects = json.loads(out)
            except Exception as exc:  # noqa: BLE001 - show UI error
                self._append_log_safe(out)
                self.root.after(
                    0,
                    lambda: messagebox.showerror(
                        "Parse error",
                        f"Failed to parse JSON output: {exc}",
                    ),
                )
                return

            def update_ui() -> None:
                self._projects = projects
                for child in self.tree.get_children():
                    self.tree.delete(child)
                for p in projects:
                    self.tree.insert(
                        "",
                        "end",
                        values=(
                            p.get("name", ""),
                            p.get("id", ""),
                            p.get("accessLevel", ""),
                            "yes" if p.get("archived") else "no",
                            "yes" if p.get("trashed") else "no",
                        ),
                    )
                self._set_buttons_enabled(False)

            self.root.after(0, update_ui)

        threading.Thread(target=work, daemon=True).start()

    def link_selected(self) -> None:
        project_id = self._selected_project_id()
        if not project_id:
            messagebox.showwarning("No project selected", "Please select a project first.")
            return
        dir_path = self.local_dir.get().strip()
        if not dir_path:
            messagebox.showwarning("No local folder", "Please choose a local folder.")
            return

        def work() -> None:
            env = _build_env(self.email.get(), self.password.get())
            base = self.base_url.get().strip()
            args = ["link", "--base-url", base, "--project-id", project_id, "--dir", dir_path]
            if self.force.get():
                args.append("--force")
            code, out, err = _run_node(args, env)
            self._append_log_safe(out or err)
            if code != 0:
                self.root.after(
                    0,
                    lambda: messagebox.showerror(
                        "Link failed",
                        err or out or f"Exit code: {code}",
                    ),
                )

        threading.Thread(target=work, daemon=True).start()

    def push(self) -> None:
        dir_path = self.local_dir.get().strip()
        if not dir_path:
            messagebox.showwarning("No local folder", "Please choose a local folder.")
            return

        conc = self.concurrency.get().strip() or "4"

        def work() -> None:
            env = _build_env(self.email.get(), self.password.get())
            base = self.base_url.get().strip()
            args = ["push", "--base-url", base, "--dir", dir_path, "--concurrency", conc]
            if self.dry_run.get():
                args.append("--dry-run")
            code, out, err = _run_node(args, env)
            self._append_log_safe(out or err)
            if code != 0:
                self.root.after(
                    0,
                    lambda: messagebox.showerror(
                        "Push failed",
                        err or out or f"Exit code: {code}",
                    ),
                )
                return
            self._mark_outgoing_for_dir(dir_path)

        threading.Thread(target=work, daemon=True).start()

    def pull_selected(self) -> None:
        project_id = self._selected_project_id()
        project_name = self._selected_project_name()
        if not project_id or not project_name:
            messagebox.showwarning("No project selected", "Please select a project first.")
            return

        ok = messagebox.askyesno(
            "Download project",
            f"Download '{project_name}' ({project_id}) to a local folder?",
        )
        if not ok:
            return

        initial = self.download_parent_dir.get().strip() or self.create_parent_dir.get().strip() or None
        base_dir = filedialog.askdirectory(
            title="Select destination folder (parent)",
            initialdir=initial,
        )
        if not base_dir:
            return

        self.download_parent_dir.set(base_dir)
        self._state["download_parent_dir"] = base_dir
        _save_gui_state(self._state)

        safe_name = _sanitize_folder_name(project_name, project_id)
        dest_parent = Path(base_dir).expanduser().resolve()
        dest_dir = _unique_child_dir(dest_parent, safe_name)

        try:
            dest_dir.mkdir(parents=True, exist_ok=False)
        except Exception as exc:  # noqa: BLE001 - UI surface
            messagebox.showerror("Create folder failed", str(exc))
            return

        self._set_local_dir(str(dest_dir))

        def work() -> None:
            env = _build_env(self.email.get(), self.password.get())
            base = self.base_url.get().strip()
            args = ["pull", "--base-url", base, "--project-id", project_id, "--dir", str(dest_dir)]
            code, out, err = _run_node(args, env)
            self._append_log_safe(out or err)
            if code != 0:
                self.root.after(
                    0,
                    lambda: messagebox.showerror(
                        "Pull failed",
                        err or out or f"Exit code: {code}",
                    ),
                )
                return

            self.root.after(
                0,
                lambda: messagebox.showinfo(
                    "Download complete",
                    f"Downloaded to:\n{dest_dir}",
                ),
            )

        threading.Thread(target=work, daemon=True).start()

    def watch(self) -> None:
        dir_path = self.local_dir.get().strip()
        if not dir_path:
            messagebox.showwarning("No local folder", "Please choose a local folder.")
            return

        abs_dir = str(Path(dir_path).resolve())
        existing = self._watches.get(abs_dir)
        if existing is not None and existing.poll() is None:
            messagebox.showinfo("Watch running", "This folder is already being watched.")
            return

        env = _build_env(self.email.get(), self.password.get())
        base = self.base_url.get().strip()
        args = ["watch", "--base-url", base, "--dir", abs_dir]
        cmd = ["node", str(OL_SYNC), *args]

        try:
            proc: subprocess.Popen[str] = subprocess.Popen(
                cmd,
                cwd=str(REPO_ROOT),
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
        except FileNotFoundError:
            messagebox.showerror("Missing dependency", "Cannot find `node` in PATH.")
            return

        self._watches[abs_dir] = proc
        self._refresh_watch_list()

        label = Path(abs_dir).name or abs_dir

        def pump() -> None:
            assert proc.stdout is not None
            for line in proc.stdout:
                clean = line.rstrip("\n")
                if clean.startswith("synced "):
                    rel = clean[len("synced ") :].strip()
                    if rel:
                        self._dirty_files.setdefault(abs_dir, set()).add(rel)
                        key = self._dir_project_key.get(abs_dir)
                        if not key:
                            info = self._sync_info_for_dir(abs_dir)
                            key = info[2] if info else None
                        if key:
                            self._last_outgoing[key] = time.time()
                self._append_log_safe(f"[watch:{label}] {clean}")
            rc = proc.wait()
            self._append_log_safe(f"[watch:{label} exited] code={rc}")
            self._watches.pop(abs_dir, None)
            self._watch_threads.pop(abs_dir, None)
            self.root.after(0, self._refresh_watch_list)

        thread = threading.Thread(target=pump, daemon=True)
        self._watch_threads[abs_dir] = thread
        thread.start()
        self._append_log_safe(f"[watch started] {abs_dir}")

    def stop_watch(self) -> None:
        dir_path = self.local_dir.get().strip()
        if not dir_path:
            messagebox.showwarning("No local folder", "Please choose a local folder.")
            return
        abs_dir = str(Path(dir_path).resolve())
        proc = self._watches.get(abs_dir)
        if proc is None or proc.poll() is not None:
            messagebox.showinfo("Not watching", "No watch process is running for this folder.")
            return
        try:
            proc.terminate()
        except Exception:
            pass

    def stop_selected_watch(self) -> None:
        sel = self.watch_tree.selection()
        if not sel:
            messagebox.showinfo("No selection", "Please select a watch entry first.")
            return
        item = self.watch_tree.item(sel[0])
        values = item.get("values") or []
        if not values:
            return
        abs_dir = str(values[0])
        proc = self._watches.get(abs_dir)
        if proc is None or proc.poll() is not None:
            self._watches.pop(abs_dir, None)
            self._watch_threads.pop(abs_dir, None)
            self._refresh_watch_list()
            return
        try:
            proc.terminate()
        except Exception:
            pass

    def stop_all_watches(self) -> None:
        for proc in list(self._watches.values()):
            if proc.poll() is not None:
                continue
            try:
                proc.terminate()
            except Exception:
                pass

    def _refresh_watch_list(self) -> None:
        for child in self.watch_tree.get_children():
            self.watch_tree.delete(child)
        for abs_dir, proc in sorted(self._watches.items(), key=lambda kv: kv[0]):
            if proc.poll() is not None:
                continue
            pending = self._remote_pending_for_dir(abs_dir)
            self.watch_tree.insert(
                "",
                "end",
                values=(abs_dir, str(proc.pid or ""), str(pending) if pending else ""),
            )

    def fetch_remote_changes(self) -> None:
        dir_path = self.local_dir.get().strip()
        if not dir_path:
            messagebox.showwarning("No local folder", "Please choose a local folder.")
            return

        def work() -> None:
            env = _build_env(self.email.get(), self.password.get())
            base = self.base_url.get().strip()
            args = ["fetch", "--base-url", base, "--dir", dir_path, "--json"]
            code, out, err = _run_node(args, env)
            if code != 0:
                self._append_log_safe(err or out)
                self.root.after(
                    0,
                    lambda: messagebox.showerror(
                        "Check remote failed",
                        err or out or f"Exit code: {code}",
                    ),
                )
                return
            try:
                manifest = json.loads(out)
            except Exception as exc:  # noqa: BLE001 - UI surface
                self._append_log_safe(out)
                self.root.after(
                    0,
                    lambda: messagebox.showerror(
                        "Parse error",
                        f"Failed to parse JSON output: {exc}",
                    ),
                )
                return

            def update_ui() -> None:
                self._inbox_manifest = manifest
                for child in self.inbox_tree.get_children():
                    self.inbox_tree.delete(child)
                changes = (manifest or {}).get("changes") or {}
                for p in changes.get("added") or []:
                    self.inbox_tree.insert("", "end", values=(p, "added"))
                for e in changes.get("modified") or []:
                    self.inbox_tree.insert("", "end", values=(e.get("path", ""), "modified"))
                for p in changes.get("deleted") or []:
                    self.inbox_tree.insert("", "end", values=(p, "deleted (remote)"))

                counts = (
                    f"added={len(changes.get('added') or [])} "
                    f"modified={len(changes.get('modified') or [])} "
                    f"deleted={len(changes.get('deleted') or [])}"
                )
                self._append_log(f"[inbox] batch={manifest.get('batchId')} {counts}")

            self.root.after(0, update_ui)

        threading.Thread(target=work, daemon=True).start()

    def apply_remote_changes(self) -> None:
        dir_path = self.local_dir.get().strip()
        if not dir_path:
            messagebox.showwarning("No local folder", "Please choose a local folder.")
            return

        manifest = self._inbox_manifest or {}
        batch_id = manifest.get("batchId")
        changes = manifest.get("changes") or {}
        n_apply = len(changes.get("added") or []) + len(changes.get("modified") or [])

        if batch_id:
            prompt = (
                f"Apply {n_apply} change(s) into:\n{dir_path}\n\n"
                "Mode: last-write wins.\n"
                "A backup will be created under ~/.config/overleaf-sync/backups/.\n\nProceed?"
            )
        else:
            prompt = (
                f"No inbox batch yet.\n\n"
                f"Fetch latest remote changes and apply into:\n{dir_path}\n\n"
                "Mode: last-write wins.\n"
                "A backup will be created under ~/.config/overleaf-sync/backups/.\n\nProceed?"
            )

        ok = messagebox.askyesno("Apply incoming changes", prompt)
        if not ok:
            return

        def work() -> None:
            env = _build_env(self.email.get(), self.password.get())
            base = self.base_url.get().strip()
            nonlocal manifest, batch_id, n_apply

            if not batch_id:
                fetch_code, fetch_out, fetch_err = _run_node(
                    ["fetch", "--base-url", base, "--dir", dir_path, "--json"],
                    env,
                )
                self._append_log_safe(fetch_out or fetch_err)
                if fetch_code != 0:
                    self.root.after(
                        0,
                        lambda: messagebox.showerror(
                            "Check remote failed",
                            fetch_err or fetch_out or f"Exit code: {fetch_code}",
                        ),
                    )
                    return
                try:
                    manifest = json.loads(fetch_out)
                except Exception as exc:  # noqa: BLE001 - UI surface
                    self.root.after(
                        0,
                        lambda: messagebox.showerror(
                            "Parse error",
                            f"Failed to parse JSON output: {exc}",
                        ),
                    )
                    return
                batch_id = manifest.get("batchId")
                changes = manifest.get("changes") or {}
                n_apply = len(changes.get("added") or []) + len(changes.get("modified") or [])
                self._inbox_manifest = manifest
                self.root.after(0, self._update_remote_ui)

            if not batch_id:
                self.root.after(
                    0,
                    lambda: messagebox.showerror(
                        "Apply failed",
                        "Missing inbox batch id.",
                    ),
                )
                return

            args = ["apply", "--base-url", base, "--dir", dir_path, "--batch", str(batch_id)]
            code, out, err = _run_node(args, env)
            self._append_log_safe(out or err)
            if code != 0:
                self.root.after(
                    0,
                    lambda: messagebox.showerror(
                        "Apply failed",
                        err or out or f"Exit code: {code}",
                    ),
                )
                return
            base_url = _normalize_base_url(str(manifest.get("baseUrl") or base))
            project_id = str(manifest.get("projectId") or "").strip()
            if base_url and project_id:
                key = _project_key(base_url, project_id)
                remote_projects = self._state.setdefault("remote_projects", {})
                entry = remote_projects.setdefault(key, {})
                entry["pending"] = 0
                entry["dirty"] = False
                entry["lastAppliedAt"] = datetime.now(timezone.utc).isoformat()
                remote_projects[key] = entry
                _save_gui_state(self._state)
                self.root.after(0, self._update_remote_ui)

        threading.Thread(target=work, daemon=True).start()

    def open_inbox_folder(self) -> None:
        manifest = self._inbox_manifest or {}
        inbox_dir = manifest.get("inboxDir")
        if not inbox_dir:
            messagebox.showinfo("No inbox", "No inbox batch yet. Click 'Check remote' first.")
            return
        try:
            if sys.platform == "darwin":
                subprocess.Popen(["open", str(inbox_dir)])
            elif os.name == "nt":
                os.startfile(str(inbox_dir))  # type: ignore[attr-defined]
            else:
                subprocess.Popen(["xdg-open", str(inbox_dir)])
        except Exception as exc:  # noqa: BLE001 - UI surface
            messagebox.showerror("Open folder failed", str(exc))

    def create_project_flow(self) -> None:
        dir_path = self.local_dir.get().strip()
        if dir_path:
            ok = messagebox.askyesno(
                "Create project",
                "Use the selected Local folder?\n\n"
                "Yes: create+link in Local folder (migrate existing files)\n"
                "No: choose a parent directory and create a new project folder",
            )
            if ok:
                self.create_project()
                return
        self.create_new_local_project()

    def create_project(self) -> None:
        dir_path = self.local_dir.get().strip()
        if not dir_path:
            messagebox.showwarning("No local folder", "Please choose a local folder.")
            return
        name = self.new_project_name.get().strip() or Path(dir_path).name

        def work() -> None:
            env = _build_env(self.email.get(), self.password.get())
            base = self.base_url.get().strip()
            args = ["create", "--base-url", base, "--dir", dir_path, "--name", name]
            if self.force.get():
                args.append("--force")
            code, out, err = _run_node(args, env)
            self._append_log_safe(out or err)
            if code != 0:
                self.root.after(
                    0,
                    lambda: messagebox.showerror(
                        "Create failed",
                        err or out or f"Exit code: {code}",
                    ),
                )
                return
            created_id = None
            match = PROJECT_ID_RE.search(out or "")
            if match:
                created_id = match.group(1)

            if self.push_after_create.get():
                conc = self.concurrency.get().strip() or "4"
                push_args = ["push", "--base-url", base, "--dir", dir_path, "--concurrency", conc]
                push_code, push_out, push_err = _run_node(push_args, env)
                self._append_log_safe(push_out or push_err)
                if push_code != 0:
                    self.root.after(
                        0,
                        lambda: messagebox.showerror(
                            "Initial push failed",
                            push_err or push_out or f"Exit code: {push_code}",
                        ),
                    )
                    return
                self._mark_outgoing_for_dir(dir_path)
            self.load_projects()
            if self.auto_watch_after_create.get():
                self.root.after(0, self.watch)
            if created_id:
                self._append_log_safe(f"[created project] {created_id}")

        threading.Thread(target=work, daemon=True).start()

    def create_new_local_project(self) -> None:
        initial = self.create_parent_dir.get().strip() or self._state.get("create_parent_dir") or None
        parent = filedialog.askdirectory(
            title="Select parent folder for the new project",
            initialdir=initial,
        )
        if not parent:
            return
        self.create_parent_dir.set(parent)
        self._state["create_parent_dir"] = parent
        _save_gui_state(self._state)

        raw_name = self.new_project_name.get().strip()
        if not raw_name:
            messagebox.showwarning("Missing name", "Please enter a project name.")
            return

        folder_name = Path(raw_name).name
        if folder_name != raw_name:
            messagebox.showwarning("Invalid name", "Project name must not contain path separators.")
            return

        parent_path = Path(parent).expanduser()
        target_dir = (parent_path / folder_name).resolve()

        try:
            if target_dir.exists():
                if not target_dir.is_dir():
                    messagebox.showerror("Path exists", f"{target_dir} exists and is not a directory.")
                    return
                non_empty = any(target_dir.iterdir())
                if non_empty:
                    ok = messagebox.askyesno(
                        "Folder not empty",
                        f"{target_dir} is not empty.\nContinue and create/link the Overleaf project anyway?",
                    )
                    if not ok:
                        return
            else:
                target_dir.mkdir(parents=True, exist_ok=False)
        except Exception as exc:  # noqa: BLE001 - UI surface
            messagebox.showerror("Create folder failed", str(exc))
            return

        if self.init_main_tex.get():
            main_tex = target_dir / "main.tex"
            if not main_tex.exists():
                try:
                    main_tex.write_text(
                        "\\documentclass{article}\n"
                        "\\begin{document}\n"
                        "Hello, Overleaf!\n"
                        "\\end{document}\n",
                        encoding="utf-8",
                    )
                except Exception as exc:  # noqa: BLE001 - UI surface
                    messagebox.showerror("Write file failed", str(exc))
                    return

        self._set_local_dir(str(target_dir))
        self.create_project()


def main() -> None:
    root = tk.Tk()
    ttk.Style().theme_use("clam")
    app = OverleafSyncGui(root)
    root.protocol("WM_DELETE_WINDOW", lambda: (app.shutdown(), root.destroy()))
    root.mainloop()


if __name__ == "__main__":
    main()
