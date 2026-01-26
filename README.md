# Overleaf Local Sync (Unofficial)

Local-first sync helpers (CLI + GUI) for a **self-hosted Overleaf** instance: edit in VS Code/Cursor → push/watch to the web editor.

This project is **not affiliated with Overleaf**. Use it only against an Overleaf instance you own/control.

## What it does

- List projects, link a local folder to a project (writes `.ol-sync.json`).
- `push`: one-shot local → remote upload.
- `watch`: keep watching a local folder and auto-upload on save.
- Optional: detect remote (web UI) edits and apply them locally (last-write wins, with backups).
- macOS app UI (SwiftUI) and a cross-platform Tkinter GUI.

## What it is NOT

- Not a conflict-resolving real-time 2-way sync.
- Not a replacement for Overleaf itself (it does not bundle Overleaf).
- Remote deletes are intentionally conservative (avoid accidental data loss).

## Quick start (CLI)

1) Start your self-hosted Overleaf and make sure it’s reachable (e.g. `http://localhost`).

2) List projects:

```bash
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost
```

3) Link a local folder:

```bash
node overleaf-sync/ol-sync.mjs link --base-url http://localhost --project-id <PROJECT_ID> --dir /path/to/local/folder
```

4) Push once (optional):

```bash
node overleaf-sync/ol-sync.mjs push --base-url http://localhost --dir /path/to/local/folder
```

5) Watch:

```bash
node overleaf-sync/ol-sync.mjs watch --base-url http://localhost --dir /path/to/local/folder
```

## GUI options

### Tkinter GUI (recommended for quick use)

```bash
cd overleaf-sync
uv run python gui.py
```

### macOS app (SwiftUI)

```bash
cd overleaf-sync-macos-app
./build-app.sh --force
open dist
```

## Security notes

- The tool caches a session cookie at `~/.config/overleaf-sync/session.json`. Treat it like a credential.
- Do **not** commit your `overleaf-projects/` folder (your actual papers/projects) to GitHub.

## License

MIT. See `LICENSE`.

---

# Overleaf Local Sync（非官方）

面向 **自建 Overleaf** 的“本地优先同步”工具（CLI + GUI）：用 VS Code/Cursor 在本地编辑 → 推送/监听同步到网页端编辑器。

本项目与 Overleaf 官方**无任何关联**。请仅用于你自己拥有/控制的 Overleaf 实例。

## 它能做什么

- 列出项目，把本地目录绑定到项目（写入 `.ol-sync.json`）。
- `push`：一次性把本地目录上传到网页端。
- `watch`：监听本地目录，保存即自动上传。
- 可选：检测网页端改动并应用到本地（最后写入生效，且会做备份）。
- 提供 macOS 原生 UI（SwiftUI）以及跨平台 Tkinter GUI。

## 它不是什么

- 不是“带冲突解决的双向实时同步”。
- 不是 Overleaf 本体（不会打包/启动 Overleaf）。
- 出于安全考虑，对远端删除非常保守（避免误删）。

## 快速开始（命令行）

1) 启动你的自建 Overleaf，并确保可访问（例如 `http://localhost`）。

2) 列项目：

```bash
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost
```

3) 绑定本地目录：

```bash
node overleaf-sync/ol-sync.mjs link --base-url http://localhost --project-id <PROJECT_ID> --dir /path/to/local/folder
```

4) 可选：先全量推一次：

```bash
node overleaf-sync/ol-sync.mjs push --base-url http://localhost --dir /path/to/local/folder
```

5) 开始监听同步：

```bash
node overleaf-sync/ol-sync.mjs watch --base-url http://localhost --dir /path/to/local/folder
```

## GUI 两种方式

### Tkinter GUI（更快上手）

```bash
cd overleaf-sync
uv run python gui.py
```

### macOS 应用（SwiftUI）

```bash
cd overleaf-sync-macos-app
./build-app.sh --force
open dist
```

## 安全提醒

- 工具会把 session cookie 缓存到 `~/.config/overleaf-sync/session.json`，请当作敏感凭据对待。
- 千万不要把 `overleaf-projects/`（你的论文/项目正文）提交到 GitHub。

## License

MIT，见 `LICENSE`。

