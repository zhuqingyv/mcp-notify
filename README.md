# mcp-notify

MCP server for macOS native notifications with AI brand icons.

Send desktop notifications from Claude Code with one-line tool calls — complete with 67 AI/Agent brand icons and system sound support.

---

## Quick Start

Just tell your AI agent:

> Install mcp-notify from https://github.com/zhuqingyv/mcp-notify and set it up for Claude Code.

The agent will clone the repo, install dependencies, register the MCP server, and configure permissions automatically.

---

## Features

- **`send_notification`** — Send macOS native notifications via terminal-notifier, with title, subtitle, sound, and icon
- **`list_icons`** — List all 67 available AI brand icons
- **`list_sounds`** — List all macOS system sounds
- **67 AI brand icons** — Covers major providers (Anthropic, OpenAI, Google, DeepSeek, Kimi, and more)
- **Cross-Mac compatible** — Dynamic terminal-notifier path detection for both Apple Silicon and Intel Macs

---

## Screenshots / Preview

> _Coming soon_

---

## Prerequisites

- **Node.js** 18+
- **terminal-notifier**

```bash
brew install terminal-notifier
```

---

## Installation

```bash
git clone https://github.com/zhuqingyv/mcp-notify.git
cd mcp-notify
npm install
```

---

## Setup with Claude Code

### Register the MCP server

```bash
claude mcp add notify -s user -- node /absolute/path/to/mcp-notify/index.js
```

### Pre-authorize tools (skip confirmation prompts)

Add to `~/.claude/settings.json` under `permissions.allow`:

```json
"mcp__notify__send_notification",
"mcp__notify__list_sounds",
"mcp__notify__list_icons"
```

---

## Usage

### Send a notification

```
Send a notification: task complete
```

### Send a notification with an icon

```
Send a notification with the openai icon: code review done
```

Equivalent tool call:

```json
{
  "tool": "send_notification",
  "arguments": {
    "title": "Claude Code",
    "message": "Code review done",
    "icon": "openai",
    "sound": "Hero"
  }
}
```

### List available icons

```
List all available notification icons
```

Calls `list_icons` — returns all icon names (without `.png` extension).

### List available sounds

```
What notification sounds are available?
```

Calls `list_sounds` — returns system sound names usable in the `sound` parameter.

---

## Available Icons

67 icons total. All are 128×128 PNG with brand color background and white label.

### International Providers (37)

| Icon name | Provider | Product |
|---|---|---|
| `claude` | Anthropic | Claude |
| `openai` | OpenAI | ChatGPT / GPT |
| `gemini` | Google | Gemini |
| `google-ai-studio` | Google | Google AI Studio |
| `meta-ai` | Meta | LLaMA / Meta AI |
| `copilot` | Microsoft | Copilot |
| `azure-openai` | Microsoft | Azure OpenAI |
| `grok` | xAI | Grok |
| `mistral` | Mistral AI | Mistral |
| `cohere` | Cohere | Command / Coral |
| `perplexity` | Perplexity AI | Perplexity |
| `stability-ai` | Stability AI | Stable Diffusion |
| `midjourney` | Midjourney | Midjourney |
| `cursor` | Cursor | Cursor |
| `replit` | Replit | Replit |
| `github-copilot` | GitHub | GitHub Copilot |
| `amazon-bedrock` | Amazon | Bedrock |
| `amazon-q` | Amazon | Amazon Q |
| `apple-intelligence` | Apple | Apple Intelligence |
| `hugging-face` | Hugging Face | Hugging Face |
| `runway` | Runway | Runway ML |
| `elevenlabs` | ElevenLabs | ElevenLabs |
| `suno` | Suno | Suno |
| `pi-ai` | Inflection AI | Pi |
| `character-ai` | Character.AI | Character.AI |
| `pika` | Pika Labs | Pika |
| `kling` | Kling AI | Kling |
| `groq` | Groq | Groq |
| `together-ai` | Together AI | Together AI |
| `replicate` | Replicate | Replicate |
| `ai21` | AI21 Labs | Jamba / Jurassic |
| `aleph-alpha` | Aleph Alpha | Luminous |
| `nvidia` | Nvidia | Nvidia AI / NIM |
| `luma-ai` | Luma AI | Dream Machine |
| `adobe-firefly` | Adobe | Adobe Firefly |
| `notion-ai` | Notion | Notion AI |
| `grammarly` | Grammarly | Grammarly AI |

### Chinese Providers (25)

| Icon name | Provider | Product |
|---|---|---|
| `ernie-bot` | 百度 | 文心一言 / ERNIE Bot |
| `qwen` | 阿里巴巴 | 通义千问 / Qwen |
| `doubao` | 字节跳动 | 豆包 / Doubao |
| `coze` | 字节跳动 | Coze (扣子) |
| `zhipu` | 智谱AI | GLM / ChatGLM |
| `kimi` | Moonshot AI | Kimi |
| `deepseek` | DeepSeek | DeepSeek |
| `yi-ai` | 01.AI | Yi 系列 |
| `minimax` | MiniMax | 海螺AI |
| `baichuan` | 百川智能 | Baichuan |
| `tiangong` | 昆仑万维 | 天工AI |
| `sensenova` | 商汤科技 | 日日新 / SenseNova |
| `xunfei-spark` | 科大讯飞 | 星火 / Spark |
| `hunyuan` | 腾讯 | 混元 / Hunyuan |
| `step-ai` | 阶跃星辰 | Step |
| `tencent-yuanbao` | 腾讯 | 元宝 |
| `youdao-ai` | 网易有道 | 有道AI |
| `360-ai` | 360 | 智脑 / 360AI |
| `pangu` | 华为 | 盘古大模型 |
| `xiaomi-ai` | 小米 | 小爱同学 / MiAI |
| `sogou-ai` | 搜狗/腾讯 | 搜狗AI |
| `zidong-taichi` | 中科院 | 紫东太初 |
| `mobvoi` | 出门问问 | 序列猴子 |
| `characterglm` | 聆心智能 | CharacterGLM |
| `xverse` | 光年之外 | 元象 XVERSE |

### AI Dev Tools & Platforms (5)

| Icon name | Provider | Product |
|---|---|---|
| `langchain` | LangChain | LangChain |
| `llamaindex` | LlamaIndex | LlamaIndex |
| `wandb` | Weights & Biases | W&B / Wandb |
| `vercel-ai` | Vercel | Vercel AI SDK |
| `supabase-ai` | Supabase | Supabase AI |

---

## Adding Custom Icons

Place any 128×128 PNG in the `icons/` directory. The filename (without `.png`) becomes the icon name usable in the `icon` parameter.

```bash
cp my-icon.png /path/to/mcp-notify/icons/my-icon.png
# then use: "icon": "my-icon"
```

To regenerate all built-in icons from scratch:

```bash
python3 gen_icons.py
```

---

## Notification Hook Integration

Auto-notify when Claude finishes a task. Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "bash -c 'MSG=$(cat); TITLE=$(echo \"$MSG\" | python3 -c \"import sys,json; d=json.load(sys.stdin); print(d.get(\\\"title\\\",\\\"Claude Code\\\"))\" 2>/dev/null || echo \"Claude Code\"); BODY=$(echo \"$MSG\" | python3 -c \"import sys,json; d=json.load(sys.stdin); print(d.get(\\\"message\\\",\\\"Done\\\"))\" 2>/dev/null || echo \"Done\"); terminal-notifier -title \"$TITLE\" -message \"$BODY\" -sound Hero -group claude-notify'"
      }]
    }]
  }
}
```

---

## License

MIT
