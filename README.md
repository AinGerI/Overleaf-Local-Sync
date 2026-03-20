# Overleaf Local Sync (Unofficial)

Keep self-hosted Overleaf projects mapped to clear local folders.

You can keep doing final polish in the Overleaf web editor, sync those changes back into a readable local workspace, and quickly send local edits upstream again. The key goal is not just "edit locally", but making remote files and local files easy to understand and correspond to each other. This repository includes a Node.js CLI, a lightweight cross-platform Tkinter GUI, and a native macOS SwiftUI app.

This project is not affiliated with Overleaf. Use it only with an Overleaf instance you own or control.

## Why this exists

Overleaf is excellent for browser-based collaboration, and many people still prefer to do the last round of writing, cleanup, or formatting directly in the web UI. The painful part is that remote files and local files are often hard to map cleanly, and moving edits back and forth is awkward.

This project is for that gap. It gives each project a clear local folder that stays understandable on disk, while still fitting a web-first Overleaf workflow. You do not need to dig through Overleaf internals just to find the files you care about.

Why that helps:

- better editor ergonomics
- easier use of local tools such as VS Code, Cursor, scripts, and AI-assisted editing
- batch refactors and local tooling
- local backups and filesystem visibility
- a clearer one-to-one mental model between Overleaf files and local files

This project bridges that gap for self-hosted Overleaf deployments.

## What it can do

- List projects from your self-hosted Overleaf instance.
- Link a local folder to a project by writing `.ol-sync.json`.
- Push a local folder to Overleaf once with `push`.
- Watch a local folder and auto-upload on save with `watch`.
- Detect remote edits from the web UI and apply them locally with backups.
- Use the workflow from the CLI, a Tkinter GUI, or a native macOS app.

## Safety by default

- This is not a conflict-resolving real-time sync engine.
- Remote deletes are intentionally conservative.
- Remote-to-local apply keeps backups.
- Session state is stored explicitly instead of hidden in the repo.

The design goal is practical daily sync for personal or small-team self-hosted Overleaf usage, not a fully automatic distributed merge system.

## What it is not

- It does not bundle or replace Overleaf itself.
- It is not intended for the hosted overleaf.com service.
- It does not promise perfect two-way real-time sync with conflict resolution.
- It should not be treated as a substitute for normal backups.

## Repository layout

- `overleaf-sync/`: Node.js CLI and the Tkinter GUI.
- `overleaf-sync-macos-app/`: native macOS app built with SwiftUI.

## Quick start

### 1. Start your self-hosted Overleaf

Make sure your local or private Overleaf instance is running and reachable, for example:

```text
http://localhost
```

### 2. List projects

```bash
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost
```

### 3. Link a local folder

```bash
node overleaf-sync/ol-sync.mjs link \
  --base-url http://localhost \
  --project-id <PROJECT_ID> \
  --dir /path/to/local/folder
```

### 4. Push once

```bash
node overleaf-sync/ol-sync.mjs push \
  --base-url http://localhost \
  --dir /path/to/local/folder
```

### 5. Watch for local changes

```bash
node overleaf-sync/ol-sync.mjs watch \
  --base-url http://localhost \
  --dir /path/to/local/folder
```

## GUI options

### Tkinter GUI

Good for quick setup and cross-platform use.

```bash
cd overleaf-sync
uv run python gui.py
```

### macOS app

Good if you want a native UI for project browsing, linking, watch management, and remote-change handling.

```bash
cd overleaf-sync-macos-app
./build-app.sh --force
open dist
```

## Typical workflow

1. Start your self-hosted Overleaf instance.
2. List projects and choose one.
3. Link a local folder to that project.
4. Edit locally in your preferred editor.
5. Use `watch` for continuous upload, or `push` when you want a manual sync step.
6. Optionally fetch and apply remote edits back into the local folder.

## Security notes

- Session cookies are cached at `~/.config/overleaf-sync/session.json`. Treat that file like a credential.
- Do not commit your real project content to a public repository by accident.
- Keep separate backups of your papers or documents if they matter.

## License

MIT. See `LICENSE`.

---

# Overleaf Local Sync（非官方）

让自建 Overleaf 项目始终对应到清晰本地文件夹的同步工具。

它的核心目标，不只是“支持本地编辑”，而是让自建 Overleaf 项目始终对应到一个清晰、可读、容易理解的本地文件夹。你依然可以像平时一样在 Overleaf 网页端做最后的收尾编辑，也可以随时把这些改动同步回本地；而本地编辑器中的修改，同样能很快再推回网页端。最关键的是，远端文件和本地文件之间的关系会变得直观，不需要再去 Overleaf 那些不够友好的内部目录里翻找。这个仓库同时提供 Node.js CLI、轻量级跨平台 Tkinter GUI，以及一个原生 macOS SwiftUI 应用。

本项目与 Overleaf 官方无关联。请仅用于你自己拥有或可控的 Overleaf 实例。

## 为什么会有这个项目

Overleaf 很适合浏览器协作，而且很多人最后一轮修改、收尾、排版检查，仍然习惯直接在网页端完成。真正麻烦的是：本地文件和远端文件往往不够直观地对应，来回同步也不够顺手。

这个项目就是为了解决这条缝隙。它让每个项目在本地都有一个结构清晰、磁盘上可理解的文件夹，同时又不破坏你以网页端为核心的 Overleaf 使用习惯。你不用再为了找到对应文件，去翻 Overleaf 那些不够直观的内部目录。

它带来的帮助主要是：

- 编辑器体验更好
- 更方便使用 VS Code、Cursor、脚本和 AI 工具
- 方便批量重构和本地工具处理
- 更容易做本地备份和查看文件结构
- 让 Overleaf 文件和本地文件之间的对应关系更清楚

这个项目就是为自建 Overleaf 补上这条链路。

## 它能做什么

- 列出自建 Overleaf 实例中的项目。
- 通过写入 `.ol-sync.json` 把本地目录绑定到项目。
- 用 `push` 一次性把本地目录推送到 Overleaf。
- 用 `watch` 监听本地目录，保存即自动上传。
- 检测网页端改动，并带备份地应用回本地。
- 你可以用 CLI、Tkinter GUI 或原生 macOS 应用来完成这些操作。

## 默认偏安全

- 它不是一个带冲突解决的“实时同步引擎”。
- 对远端删除默认非常保守。
- 远端改动回写到本地时会保留备份。
- session 状态会显式保存在用户目录里，而不是藏在仓库内部。

它的设计目标是服务于个人或小团队在“自建 Overleaf + 本地编辑”之间的日常同步，而不是做一个全自动分布式合并系统。

## 它不是什么

- 它不会打包或替代 Overleaf 本体。
- 它不是给 overleaf.com 托管服务设计的。
- 它不承诺具备完善冲突解决的双向实时同步。
- 它不能替代你正常的备份策略。

## 仓库结构

- `overleaf-sync/`：Node.js CLI 和 Tkinter GUI。
- `overleaf-sync-macos-app/`：基于 SwiftUI 的原生 macOS 应用。

## 快速开始

### 1. 启动你的自建 Overleaf

确保你的本地或私有 Overleaf 实例已经运行，并且可以访问，例如：

```text
http://localhost
```

### 2. 列出项目

```bash
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost
```

### 3. 绑定本地目录

```bash
node overleaf-sync/ol-sync.mjs link \
  --base-url http://localhost \
  --project-id <PROJECT_ID> \
  --dir /path/to/local/folder
```

### 4. 先推送一次

```bash
node overleaf-sync/ol-sync.mjs push \
  --base-url http://localhost \
  --dir /path/to/local/folder
```

### 5. 监听本地改动

```bash
node overleaf-sync/ol-sync.mjs watch \
  --base-url http://localhost \
  --dir /path/to/local/folder
```

## GUI 方式

### Tkinter GUI

适合快速上手，也适合跨平台使用。

```bash
cd overleaf-sync
uv run python gui.py
```

### macOS 应用

如果你希望用原生界面来浏览项目、绑定目录、管理 watch 和处理远端改动，这一套会更舒服。

```bash
cd overleaf-sync-macos-app
./build-app.sh --force
open dist
```

## 典型工作流

1. 启动你的自建 Overleaf 实例。
2. 列出项目并选择目标项目。
3. 把一个本地目录绑定到该项目。
4. 在你喜欢的编辑器中本地编辑。
5. 想持续同步就用 `watch`，想手动控制就用 `push`。
6. 如有需要，再把网页端改动拉回本地并应用。

## 安全提醒

- session cookie 会缓存到 `~/.config/overleaf-sync/session.json`，请把它当成凭据来保管。
- 不要误把真实论文或项目正文提交到公开仓库。
- 重要文稿请始终保留独立备份。

## License

MIT，见 `LICENSE`。
