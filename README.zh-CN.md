# CodexLeft

[English](README.md)

原生 macOS 菜单栏工具，显示 Codex 的 **5 小时剩余额度**和**一周剩余额度**。使用 Swift + AppKit，无第三方依赖，无 Dock 图标。

## 使用要求

- macOS 13 或更高版本。
- 已使用 ChatGPT 账号登录 Codex。
- 从源码构建需要 Xcode Command Line Tools。

## 构建与运行

```bash
./scripts/build.sh
open build/CodexLeft.app
```

## 使用

点击「显示方式」切换模式，选择会自动保存。

```text
仅显示额度：     ⚡ 5h77% W80%
额度 + 重置时间：⚡ 5h77% 13:16 W80% 10/20
```

启动立即同步，此后每 60 秒刷新。点击「立即同步」可手动刷新。

时间使用系统本地时区，悬停可查看完整重置时间。无法获取的额度显示 `--%`，错误原因在菜单中显示。

## 卸载

在项目目录执行：

```bash
pkill -x CodexLeft || true
rm -rf build/CodexLeft.app
defaults delete com.joinclear.codexleft 2>/dev/null || true
```

如果已将应用移到其他位置，请删除对应位置的应用。

## 数据与隐私

只读 `~/.codex/auth.json` 中的已有凭据，仅向 `https://chatgpt.com/backend-api/wham/usage` 请求用量。不保存凭据或用量历史，不记录令牌或响应内容。

## 许可证

[MIT](LICENSE)
