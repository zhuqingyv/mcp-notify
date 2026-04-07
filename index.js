#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { spawnSync, spawn } from "child_process";
import { readdirSync } from "fs";
import { fileURLToPath } from "url";
import { join, dirname } from "path";
import net from "net";
import crypto from "crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ICONS_DIR = join(__dirname, "icons");

// macOS: terminal bundle IDs for --activate (focus terminal on notification click)
const TERMINAL_BUNDLE_IDS = {
  "WarpTerminal":  "dev.warp.Warp-Stable",
  "iTerm.app":     "com.googlecode.iterm2",
  "Apple_Terminal":"com.apple.Terminal",
  "vscode":        "com.microsoft.VSCode",
  "cursor":        "com.todesktop.230313mzl4w4u92",
  "alacritty":     "org.alacritty",
  "kitty":         "net.kovidgoyal.kitty",
  "Hyper":         "co.zeit.hyper",
  "tmux":          "com.apple.Terminal",
};

// Custom notification app bundle path
const MCP_NOTIFY_APP = `${process.env.HOME}/Applications/MCPNotify.app`;

// --- Platform-specific send functions ---

const SOCKET_PATH = "/tmp/mcp-notify.sock";

// Connect to daemon socket, send JSON message, return response
function sendToSocket(payload) {
  return new Promise((resolve) => {
    const client = net.createConnection(SOCKET_PATH);
    let response = "";

    client.on("connect", () => {
      client.write(JSON.stringify(payload) + "\n");
    });
    client.on("data", (d) => { response += d.toString(); });
    client.on("end", () => {
      try {
        resolve({ data: JSON.parse(response.trim()) });
      } catch {
        resolve({ data: { ok: true } });
      }
    });
    client.on("error", (err) => resolve({ error: err.message }));
  });
}

// Launch daemon and wait until socket is ready (max ~3s)
async function ensureDaemon() {
  // Quick check: try connecting first
  const first = await sendToSocket({ action: "ping" });
  if (!first.error) return true;

  // Not running — launch it
  spawn("open", ["-n", "-a", MCP_NOTIFY_APP], { detached: true, stdio: "ignore" });

  // Retry every 200ms, up to 15 attempts (~3s)
  for (let i = 0; i < 15; i++) {
    await new Promise((r) => setTimeout(r, 200));
    const result = await sendToSocket({ action: "ping" });
    if (!result.error) return true;
  }
  return false;
}

async function sendMacOS({ title, message, subtitle, sound, iconPath, duration, persistent }) {
  const ready = await ensureDaemon();
  if (!ready) {
    return { error: "mcp-notify daemon failed to start" };
  }

  const bundleId = TERMINAL_BUNDLE_IDS[process.env.TERM_PROGRAM];
  const payload = {
    action:   "send",
    id:       crypto.randomUUID(),
    message,
    sound:    sound ?? "Glass",
    ...(title      && { title }),
    ...(subtitle   && { subtitle }),
    ...(iconPath   && { icon: iconPath }),
    ...(bundleId   && { activate: bundleId }),
    ...(duration != null && { duration }),
    ...(persistent && { persistent: true }),
  };

  const result = await sendToSocket(payload);
  if (result.error) return { error: `mcp-notify: ${result.error}` };
  return {};
}

function sendLinux({ title, message, iconPath }) {
  const args = [];
  if (iconPath) args.push("-i", iconPath);
  args.push(title ?? "Notification", message);

  const result = spawnSync("notify-send", args, { encoding: "utf8" });
  if (result.error) {
    return { error: "notify-send not found. Please install libnotify: sudo apt install libnotify-bin" };
  }
  if (result.status !== 0) {
    return { error: `notify-send failed: ${result.stderr ?? "unknown error"}` };
  }
  return {};
}

function sendWindows({ title, message }) {
  const safeTitle = (title ?? "Notification").replace(/'/g, "\\'");
  const safeMessage = message.replace(/'/g, "\\'");
  const script = [
    "Add-Type -AssemblyName System.Windows.Forms",
    "$notify = New-Object System.Windows.Forms.NotifyIcon",
    "$notify.Icon = [System.Drawing.SystemIcons]::Information",
    `$notify.BalloonTipTitle = '${safeTitle}'`,
    `$notify.BalloonTipText = '${safeMessage}'`,
    "$notify.Visible = $true",
    "$notify.ShowBalloonTip(5000)",
    "Start-Sleep -Milliseconds 5500",
    "$notify.Dispose()",
  ].join("; ");

  const result = spawnSync("powershell", ["-NoProfile", "-Command", script], { encoding: "utf8" });
  if (result.error) {
    return { error: `powershell not found: ${result.error.message}` };
  }
  if (result.status !== 0) {
    return { error: `PowerShell notification failed: ${result.stderr ?? "unknown error"}` };
  }
  return {};
}

async function sendNotify({ title, message, subtitle, sound, iconPath, duration, persistent }) {
  const platform = process.platform;
  if (platform === "darwin") {
    return sendMacOS({ title, message, subtitle, sound, iconPath, duration, persistent });
  } else if (platform === "linux") {
    return sendLinux({ title, message, iconPath });
  } else if (platform === "win32") {
    return sendWindows({ title, message });
  } else {
    return { error: `Unsupported platform: ${platform}` };
  }
}

// --- List sounds helper ---

function listSounds() {
  const platform = process.platform;
  if (platform === "darwin") {
    try {
      return readdirSync("/System/Library/Sounds")
        .filter((f) => f.endsWith(".aiff"))
        .map((f) => f.replace(".aiff", ""))
        .sort();
    } catch {
      return ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
              "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
              "Submarine", "Tink"];
    }
  } else if (platform === "linux") {
    try {
      return readdirSync("/usr/share/sounds")
        .filter((f) => f.endsWith(".oga") || f.endsWith(".wav") || f.endsWith(".ogg"))
        .map((f) => f.replace(/\.\w+$/, ""))
        .sort();
    } catch {
      return ["System sounds not available on this Linux setup. Install a sound theme (e.g. apt install sound-theme-freedesktop)."];
    }
  } else if (platform === "win32") {
    return ["Windows system sounds are not enumerable via this tool. Use sound names like: Default, Asterisk, Exclamation, Hand, Question."];
  } else {
    return [`Sound listing not supported on platform: ${platform}`];
  }
}

// --- MCP Server ---

const server = new McpServer({
  name: "mcp-ding",
  version: "1.0.0",
});

server.tool(
  "send_notification",
  `Send a desktop "ding" to the user — a native OS notification with optional icon and sound.

USE PROACTIVELY when:
- A long-running task (build, deploy, test suite) completes — the user may have switched windows
- An error or blocker needs user attention and you cannot proceed without input
- The user explicitly asks to be notified

DO NOT use for:
- Routine status updates the user is already watching
- Every single tool call or minor step — only meaningful milestones

ICON SELECTION: Pick an icon that matches the context. If discussing OpenAI code, use "openai"; for Claude-related work, use "claude"; for a generic alert, omit the icon. Call list_icons once per session if you need the full list.

SOUND: Keep the default unless the user asks for a specific sound. Call list_sounds only if the user wants to pick one.`,
  {
    title: z.string().optional().describe("Short notification title, e.g. 'Build Complete' or 'Error'"),
    message: z.string().describe("Notification body — be concise, the user will read this in a small popup"),
    subtitle: z.string().optional().describe("Secondary line below the title (macOS only)"),
    sound: z.string().optional().default("Glass").describe("macOS sound name. Default: Glass. Only change if user requests it"),
    icon: z.string().optional().describe("AI brand icon name (without .png). Match to context: 'claude', 'openai', 'deepseek', etc. Omit for generic alerts"),
    duration: z.number().optional().describe("Display duration in seconds. Default: 5. Set to 0 for persistent notification that stays until dismissed"),
    persistent: z.boolean().optional().default(false).describe("If true, notification stays until user dismisses it (right-swipe or click). Use for important blockers that need user attention"),
  },
  async ({ title, message, subtitle, sound, icon, duration, persistent }) => {
    const iconPath = icon ? join(ICONS_DIR, icon + ".png") : undefined;

    const result = await sendNotify({ title, message, subtitle, sound, iconPath, duration, persistent });

    if (result.error) {
      return {
        content: [{ type: "text", text: `Notification failed: ${result.error}` }],
        isError: true,
      };
    }

    return {
      content: [{ type: "text", text: `Notification sent: ${title ? `[${title}] ` : ""}${message}` }],
    };
  }
);

server.tool(
  "list_sounds",
  "List available system sounds for notifications. Only call this when the user wants to pick or preview a specific sound — do NOT call before every notification.",
  {},
  async () => {
    const sounds = listSounds();
    return {
      content: [{ type: "text", text: sounds.join("\n") }],
    };
  }
);

server.tool(
  "list_icons",
  "List all available AI brand icon names. Call once per session if needed — do NOT call before every notification. Available icons: claude, openai, gemini, deepseek, kimi, qwen, doubao, coze, copilot, cursor, grok, perplexity, zhipu, ernie-bot, xunfei-spark.",
  {},
  async () => {
    let icons;
    try {
      icons = readdirSync(ICONS_DIR)
        .filter((f) => f.endsWith(".png"))
        .map((f) => f.replace(".png", ""))
        .sort();
    } catch {
      icons = ["claude", "openai", "gemini", "deepseek", "kimi", "qwen", "doubao",
               "coze", "copilot", "cursor", "grok", "perplexity", "zhipu",
               "ernie-bot", "xunfei-spark"];
    }
    return {
      content: [{ type: "text", text: icons.join("\n") }],
    };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
