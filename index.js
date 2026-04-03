import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { spawnSync, execSync } from "child_process";
import { readdirSync } from "fs";
import { fileURLToPath } from "url";
import { join, dirname } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ICONS_DIR = join(__dirname, "icons");

// macOS: dynamic terminal-notifier path
let TERMINAL_NOTIFIER;
try {
  TERMINAL_NOTIFIER = execSync("which terminal-notifier", { encoding: "utf8" }).trim();
} catch {
  TERMINAL_NOTIFIER = "/opt/homebrew/bin/terminal-notifier";
}

// --- Platform-specific send functions ---

function sendMacOS({ title, message, subtitle, sound, iconPath }) {
  const args = [
    "-message", message,
    "-sound", sound ?? "Hero",
    "-group", "mcp-notify",
  ];
  if (title) args.push("-title", title);
  if (subtitle) args.push("-subtitle", subtitle);
  if (iconPath) args.push("-contentImage", iconPath);

  const result = spawnSync(TERMINAL_NOTIFIER, args, { encoding: "utf8" });
  if (result.error || result.status !== 0) {
    const err = result.error?.message ?? result.stderr ?? "unknown error";
    return { error: `terminal-notifier failed: ${err}` };
  }
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

function sendNotify({ title, message, subtitle, sound, iconPath }) {
  const platform = process.platform;
  if (platform === "darwin") {
    return sendMacOS({ title, message, subtitle, sound, iconPath });
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
  name: "notify",
  version: "1.0.0",
});

server.tool(
  "send_notification",
  "Send a native desktop notification (macOS, Linux, Windows)",
  {
    title: z.string().optional().describe("Notification title"),
    message: z.string().describe("Notification body (required)"),
    subtitle: z.string().optional().describe("Subtitle (macOS only)"),
    sound: z.string().optional().default("Hero").describe("Sound name, default Hero. Use list_sounds to see available values (macOS only)"),
    icon: z.string().optional().default("claude").describe("Icon name without .png extension, default claude. Use list_icons to see available values. Works on macOS and Linux."),
  },
  async ({ title, message, subtitle, sound, icon }) => {
    const iconName = icon ?? "claude";
    const iconPath = join(ICONS_DIR, iconName + ".png");

    const result = sendNotify({ title, message, subtitle, sound, iconPath });

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
  "List available notification sounds for the current platform",
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
  "List all available AI brand icon names (usable as the icon parameter in send_notification)",
  {},
  async () => {
    let icons;
    try {
      icons = readdirSync(ICONS_DIR)
        .filter((f) => f.endsWith(".png"))
        .map((f) => f.replace(".png", ""))
        .sort();
    } catch {
      icons = ["claude", "openai", "gemini", "grok", "deepseek", "kimi", "qwen"];
    }
    return {
      content: [{ type: "text", text: icons.join("\n") }],
    };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
