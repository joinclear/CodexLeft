# CodexLeft

[中文说明](README.zh-CN.md)

A native macOS menu bar app showing your remaining **5-hour** and **weekly** Codex quota. Built with Swift and AppKit, with no third-party dependencies or Dock icon.

## Requirements

- macOS 13 or later.
- Codex signed in with a ChatGPT account.
- Xcode Command Line Tools to build from source.

## Build and Run

```bash
./scripts/build.sh
open build/CodexLeft.app
```

## Usage

Click “显示方式” (Display Mode) to switch modes. Your choice is saved. Menus are in Chinese.

```text
Quota only:          ⚡ 5h77% W80%
Quota + reset times: ⚡ 5h77% 13:16 W80% 10/20
```

Syncs on launch and every 60 seconds. Click “立即同步” (Sync Now) to refresh manually.

Times use your local time zone; hover for full reset timestamps. Unavailable quota is shown as `--%`, with errors listed in the menu.

## Uninstall

Run from the project directory:

```bash
pkill -x CodexLeft || true
rm -rf build/CodexLeft.app
defaults delete com.joinclear.codexleft 2>/dev/null || true
```

If you moved the app elsewhere, delete it from that location.

## Data and Privacy

Reads existing credentials from `~/.codex/auth.json` without modifying it and queries only `https://chatgpt.com/backend-api/wham/usage`. Credentials and usage history are not saved; tokens and responses are not logged.

## License

[MIT](LICENSE)
