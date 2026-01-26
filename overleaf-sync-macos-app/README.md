# Overleaf Local Sync (macOS App)

A small macOS SwiftUI app that provides a native UI for the `overleaf-sync/ol-sync.mjs` CLI (projects list, link/push/watch, etc.).

This app **does not** bundle Overleaf itself. It simply runs the existing Node CLI in this repository.

## Requirements

- macOS 13+ (recommended)
- Xcode 15+ (recommended) or Apple Swift toolchain
- Node.js available in `$PATH`
- A running local Overleaf instance (e.g. started via `./start.sh`)

## Run (Development)

1. Open the Swift package in Xcode:
   - Open `overleaf-sync-macos-app/Package.swift`
2. Press **Run**.

## Build a `.app` (Local install)

From the repo root:

```bash
cd overleaf-sync-macos-app
./build-app.sh
open dist
```

Then drag `Overleaf Local Sync.app` into `/Applications`.

Notes:

- The script refuses to overwrite an existing app bundle unless you pass `--force` (and it will archive the old bundle under `dist/backups/`).
- When launched from Finder, your shell `$PATH` is not used; this app injects common paths like `/opt/homebrew/bin` and `/usr/local/bin` so it can find `node` and `docker`.

The first time you use it, you may need to log in once so `overleaf-sync` can cache a session at:

- `~/.config/overleaf-sync/session.json`

## Notes

- The app never stores your password. Session cookies are cached by `overleaf-sync` (same as when you run the CLI in a terminal).

---

# Overleaf Local Sync（macOS 应用）

一个 macOS SwiftUI 小应用，为仓库里的 `overleaf-sync/ol-sync.mjs` 命令行工具提供原生 UI（项目列表、link/push/watch 等）。

它**不会**打包 Overleaf 本体，只是调用仓库里已有的 Node CLI 来完成同步。

## 运行环境

- macOS 13+（推荐）
- Xcode 15+（推荐）或 Apple Swift 工具链
- 系统 `$PATH` 中可用的 Node.js
- 本地 Overleaf 已启动（例如通过 `./start.sh`）

## 开发运行

1. 用 Xcode 打开 Swift Package：
   - 打开 `overleaf-sync-macos-app/Package.swift`
2. 点击 **Run** 运行。

## 构建 `.app`（本地安装）

在仓库根目录执行：

```bash
cd overleaf-sync-macos-app
./build-app.sh
open dist
```

然后把 `Overleaf Local Sync.app` 拖到 `/Applications`。

说明：

- 脚本默认不会覆盖已存在的 app 包；如需覆盖请加 `--force`（旧的 app 会被归档到 `dist/backups/`）。
- 从 Finder 启动时不会继承你终端里的 `$PATH`；应用会主动注入 `/opt/homebrew/bin`、`/usr/local/bin` 等常见路径，以便找到 `node` 和 `docker`。

首次使用可能需要登录一次，`overleaf-sync` 会把 session 缓存到：

- `~/.config/overleaf-sync/session.json`

## 说明

- 应用不会保存你的密码；session cookie 由 `overleaf-sync` 缓存（和你在终端运行 CLI 的行为一致）。
