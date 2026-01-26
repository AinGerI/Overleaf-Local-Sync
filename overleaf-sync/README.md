# Overleaf Local Sync (Unofficial)

Sync a **local folder** (opened in VS Code / Cursor) to a **self-hosted Overleaf (Community Edition) started via `./start.sh`**.

This uses Overleaf's existing **upload endpoints** to upsert files (same as “Upload” in the UI), so changes can appear in the web editor quickly.

## What you get

- A real filesystem project folder you can edit with Cursor/VS Code + AI.
- `watch` mode: save locally → auto-upload to Overleaf.
- `push` mode: one-shot sync local → Overleaf.
- `projects` mode: list your Overleaf projects (name + id).

## What you do NOT get (by default)

- True “two-way live sync”. This is **local → Overleaf** by default.
- Safe automatic deletes. Remote deletion is **disabled by default**.

## Prerequisites

- Node.js 18+ (this repo already has Node; on macOS you likely have it).
- uv (for launching the GUI with an in-project virtualenv).
- A running Overleaf instance (toolkit): `./start.sh`
- A normal Overleaf user account (email + password) on your local instance.
- Docker installed (used to read the project's `rootFolderId` from the local MongoDB; also used to auto-detect private API credentials on some stacks).

## Quick start

### GUI (recommended)

If you prefer a click-based workflow (no copying project IDs), start the local GUI:

```bash
cd overleaf-sync
uv run python gui.py
```

Requires Python with Tkinter (`tkinter`). On macOS, the system Python usually includes it; on conda/miniforge you may need to install `tk`.

It can list projects, create/link a local folder, run `push`, and start/stop `watch`.
It also supports creating a brand new local folder under a parent directory, and running multiple watches at once.
It can also download an existing Overleaf project into a new local folder (pull).
It can also detect changes made in the web editor, accumulate a pending counter, stage them locally (inbox), then apply them (last-write wins).
The GUI polls the remote project list every ~30s (no popups) and performs incremental backups every ~2 minutes.
The first time, enter email/password once; afterwards the session cookie cache is reused.

1) List projects and grab the `projectId`:

```bash
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost
# optional: show only active projects (hide archived/trashed)
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost --active-only
# optional: debug why the list looks incomplete
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost --debug
```

You will be asked to log in once; the tool caches your **session cookie** locally so you don't need to re-enter the password every time.

2) Link the current folder to a project (writes `.ol-sync.json` into the folder):

```bash
node overleaf-sync/ol-sync.mjs link --project-id <PROJECT_ID> --dir .
```

If `.ol-sync.json` already exists, re-run with `--force` to replace it.

3) One-shot migrate (optional):

```bash
node overleaf-sync/ol-sync.mjs push --dir .
```

4) Start watching:

```bash
node overleaf-sync/ol-sync.mjs watch --dir .
```

## Common commands

```bash
# List projects as JSON (useful for scripting / GUIs)
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost --json

# Create a new empty project from a local folder and write .ol-sync.json
node overleaf-sync/ol-sync.mjs create --base-url http://localhost --dir . --name "My Project"

# Download an existing project into an empty local folder and write .ol-sync.json
node overleaf-sync/ol-sync.mjs pull --base-url http://localhost --project-id <PROJECT_ID> --dir ./my-local-folder

# Check remote changes vs local folder and write an inbox batch (JSON output)
node overleaf-sync/ol-sync.mjs fetch --base-url http://localhost --dir . --json

# Apply the latest inbox batch into the local folder (last-write wins, with backups)
node overleaf-sync/ol-sync.mjs apply --base-url http://localhost --dir .

# One-shot push of all files (skips ignored paths)
node overleaf-sync/ol-sync.mjs push --dir . --project-id <PROJECT_ID>
# (after `link`) project id is read from .ol-sync.json
node overleaf-sync/ol-sync.mjs push --dir .

# Dry run: show what would be uploaded
node overleaf-sync/ol-sync.mjs push --dir . --project-id <PROJECT_ID> --dry-run

# Faster push with a small worker pool (default is 4)
node overleaf-sync/ol-sync.mjs push --dir . --concurrency 8

# Watch mode with a custom Overleaf URL
node overleaf-sync/ol-sync.mjs watch --dir . --base-url http://localhost
```

## Notes & caveats

- Session cache file (default): `~/.config/overleaf-sync/session.json` (contains cookies; treat it like a credential).
- GUI state (last selected folders, counters): `~/.config/overleaf-sync/gui.json`
- Inbox batches: `~/.config/overleaf-sync/inbox/<host>/<projectId>/<batchId>/` (downloaded snapshots + manifest).
- Backups: `~/.config/overleaf-sync/backups/<host>/<projectId>/...` (pre-apply copies + scheduled backups).
- Non-interactive login: set `OVERLEAF_SYNC_EMAIL` / `OVERLEAF_SYNC_PASSWORD` (or pass `--email` / `--password`).
- If you edit the same file in web UI and locally at the same time, you can overwrite each other.
- This tool uploads files via HTTP; large binary assets are supported but will be slower.
- Ignore rules are conservative (ignore `.git`, `.vscode`, `.idea`, `node_modules`, `__pycache__`, `.DS_Store`).

## Troubleshooting

### `projects` shows fewer projects than expected

- Make sure `--base-url` points to the right instance.
  - `http://localhost` queries your **local toolkit instance** (its MongoDB). It will **not** automatically include projects from `overleaf.com` even if you use the same email.
- Run with debug:

```bash
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost --debug
```

- On the toolkit stack, you can confirm how many projects exist in the local DB (read-only):

```bash
docker exec mongo mongosh sharelatex --quiet --eval 'db.projects.countDocuments({})'
```

- If the session cache is stale, move it aside to force a re-login (non-destructive):

```bash
mv ~/.config/overleaf-sync/session.json ~/.config/overleaf-sync/session.json.bak
```

---

# Overleaf 本地同步（非官方）

把 **本地文件夹**（VS Code / Cursor 工作区）同步到 **通过 `./start.sh` 启动的本地 Overleaf（社区版）网页端**。

实现方式是复用 Overleaf 自带的 **上传接口**（相当于网页端“上传文件”），用 upsert 语义更新文件，因此网页端能较快看到变更。

## 你会得到什么

- 每个项目对应一个真实的本地目录：Cursor/VS Code 直接编辑 + AI。
- `watch` 模式：本地保存 → 自动上传到网页端。
- `push` 模式：一次性把本地目录推到网页端。
- `projects` 模式：列出你的 Overleaf 项目（名称 + id）。

## 默认不会提供什么

- 真正意义上的“双向实时同步”。默认是 **本地 → Overleaf**。
- 自动删除远端文件（默认关闭，避免误删）。

## 前置条件

- Node.js 18+（本仓库/本机一般已具备）。
- uv（用于以项目内虚拟环境方式启动 GUI）。
- Overleaf Toolkit 已启动：`./start.sh`
- 你的本地 Overleaf 账号（email + password）。
- Docker 已安装（用于从本地 MongoDB 读取项目 `rootFolderId`；在部分栈上也用于自动读取私有 API 凭据）。

## 快速开始

### GUI（推荐）

如果你不想复制项目 ID、希望“点一点就能同步”，可以直接启动本地 GUI：

```bash
cd overleaf-sync
uv run python gui.py
```

需要 Python 自带的 Tkinter（`tkinter`）。macOS 系统一般自带；如果你用的是 conda/miniforge，可能需要额外安装 `tk`。

它支持：列出项目、创建/绑定本地目录、执行 `push`、启动/停止 `watch`。
也支持：在指定父目录下创建一个全新的本地项目目录，并同时运行多个 watch。
也支持：把现有 Overleaf 项目下载到新的本地目录（pull）。
也支持：检测网页端的改动并累计“待处理”计数，放入“待合并区”（inbox），再以“最后写入生效”的方式应用到本地。
GUI 默认每约 30 秒后台检测一次（不弹窗打扰），并每约 2 分钟做一次增量备份。
首次需要输入一次账号密码；之后会复用 session cookie 缓存，不用反复登录。

1) 先列项目，拿到 `projectId`：

```bash
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost
# 可选：只看活跃项目（隐藏 archived/trashed）
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost --active-only
# 可选：开启 debug，排查为什么“看起来少了项目”
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost --debug
```

首次会要求登录一次；工具会在本机缓存 **session cookie**，后续就不需要反复输入密码了。

2) 把当前目录“绑定”到某个项目（在目录下写入 `.ol-sync.json`）：

```bash
node overleaf-sync/ol-sync.mjs link --project-id <PROJECT_ID> --dir .
```

如果目录里已经有 `.ol-sync.json`，需要加 `--force` 才会覆盖。

3) 一次性迁移（可选）：

```bash
node overleaf-sync/ol-sync.mjs push --dir .
```

4) 开始监听同步：

```bash
node overleaf-sync/ol-sync.mjs watch --dir .
```

## 常用命令

```bash
# JSON 输出（适合脚本/GUI 调用）
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost --json

# 从本地目录创建一个“空项目”，并在目录下写入 .ol-sync.json
node overleaf-sync/ol-sync.mjs create --base-url http://localhost --dir . --name "我的新项目"

# 下载一个现有项目到空的本地目录，并写入 .ol-sync.json
node overleaf-sync/ol-sync.mjs pull --base-url http://localhost --project-id <PROJECT_ID> --dir ./my-local-folder

# 检测网页端改动（对比本地目录），写入一份 inbox 记录（JSON 输出）
node overleaf-sync/ol-sync.mjs fetch --base-url http://localhost --dir . --json

# 把最新的一份 inbox 变更应用到本地目录（最后写入生效，并会备份本地原文件）
node overleaf-sync/ol-sync.mjs apply --base-url http://localhost --dir .

# 一次性 push（会跳过 ignore 的路径）
node overleaf-sync/ol-sync.mjs push --dir . --project-id <PROJECT_ID>
#（执行过 `link` 后）projectId 会从 .ol-sync.json 读取
node overleaf-sync/ol-sync.mjs push --dir .

# Dry-run：只打印将要上传的文件，不实际上传
node overleaf-sync/ol-sync.mjs push --dir . --project-id <PROJECT_ID> --dry-run

# 更快的 push（默认并发=4）
node overleaf-sync/ol-sync.mjs push --dir . --concurrency 8

# 自定义 Overleaf 地址
node overleaf-sync/ol-sync.mjs watch --dir . --base-url http://localhost
```

## 备注与限制

- Session 缓存文件（默认）：`~/.config/overleaf-sync/session.json`（包含 cookies，请当作凭据妥善保管）。
- GUI 状态（最近选择的目录、计数器等）：`~/.config/overleaf-sync/gui.json`
- 待合并区（inbox）：`~/.config/overleaf-sync/inbox/<host>/<projectId>/<batchId>/`（下载快照 + manifest）。
- 备份目录：`~/.config/overleaf-sync/backups/<host>/<projectId>/...`（应用前备份 + 定时增量备份）。
- 非交互登录：设置 `OVERLEAF_SYNC_EMAIL` / `OVERLEAF_SYNC_PASSWORD`（或传 `--email` / `--password`）。
- 同一文件如果网页端和本地同时编辑，可能互相覆盖。
- 本工具用 HTTP 上传文件；大文件也能传，但会更慢。
- Ignore 规则偏保守（默认忽略 `.git`、`.vscode`、`.idea`、`node_modules`、`__pycache__`、`.DS_Store`）。

## 排障

### `projects` 显示的项目比你预期少

- 先确认 `--base-url` 指向的是你想查询的实例：
  - `http://localhost` 查询的是 **本机 toolkit 实例**（对应它自己的 MongoDB），即使 email 一样，也**不会自动包含** `overleaf.com` 上的项目。
- 开启 debug 看接口/分页信息：

```bash
node overleaf-sync/ol-sync.mjs projects --base-url http://localhost --debug
```

- 在 toolkit 场景下，你可以只读确认本地数据库里一共有多少个项目：

```bash
docker exec mongo mongosh sharelatex --quiet --eval 'db.projects.countDocuments({})'
```

- 如果 session 缓存失效，建议先“移动备份”来强制重新登录（非破坏性）：

```bash
mv ~/.config/overleaf-sync/session.json ~/.config/overleaf-sync/session.json.bak
```
