# mcp-notify

Claude Code 的 MCP 通知服务，通过 terminal-notifier 发送 macOS 原生通知。

## 功能

- `send_notification` — 发送 macOS 通知，支持 title、message、subtitle、sound，点击通知自动聚焦回终端
- `list_sounds` — 列出 macOS 系统铃声列表

## 依赖

- [terminal-notifier](https://github.com/julienXX/terminal-notifier)

```bash
brew install terminal-notifier
```

## 安装

```bash
git clone https://github.com/zhuqingyv/mcp-notify.git
cd mcp-notify
npm install
```

## 注册到 Claude Code

```bash
claude mcp add notify -s user -- node /path/to/mcp-notify/index.js
```

## 预授权（免每次确认）

在 `~/.claude/settings.json` 的 `permissions.allow` 数组中添加：

```json
"mcp__notify__send_notification",
"mcp__notify__list_sounds"
```

## 使用

注册后在 Claude Code 会话中直接调用：

```
发一条通知：任务完成了
```

Claude 会调用 `send_notification` 工具，通知弹出在右上角，点击自动回到终端。

## Notification Hook 集成

在 `~/.claude/settings.json` 中配置 Notification hook，让 Claude 空闲等待时自动发通知：

```json
{
  "hooks": {
    "Notification": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "bash -c 'MSG=$(cat); TITLE=$(echo \"$MSG\" | python3 -c \"import sys,json; d=json.load(sys.stdin); print(d.get(\\\"title\\\",\\\"Claude Code\\\"))\" 2>/dev/null || echo \"Claude Code\"); BODY=$(echo \"$MSG\" | python3 -c \"import sys,json; d=json.load(sys.stdin); print(d.get(\\\"message\\\",\\\"有新通知\\\"))\" 2>/dev/null || echo \"有新通知\"); /opt/homebrew/bin/terminal-notifier -title \"$TITLE\" -message \"$BODY\" -sound Hero -activate dev.warp.Warp-Stable -group claude-notify'"
      }]
    }]
  }
}
```
