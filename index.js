import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { spawnSync, execFileSync, execSync } from "child_process";
import { readdirSync } from "fs";
import { fileURLToPath } from "url";
import { join, dirname } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ICONS_DIR = join(__dirname, "icons");

let TERMINAL_NOTIFIER;
try {
  TERMINAL_NOTIFIER = execSync("which terminal-notifier", { encoding: "utf8" }).trim();
} catch {
  TERMINAL_NOTIFIER = "/opt/homebrew/bin/terminal-notifier";
}

const server = new McpServer({
  name: "notify",
  version: "1.0.0",
});

server.tool(
  "send_notification",
  "发送 macOS 原生通知（通过 terminal-notifier）",
  {
    title: z.string().optional().describe("通知标题"),
    message: z.string().describe("通知正文（必填）"),
    subtitle: z.string().optional().describe("副标题"),
    sound: z.string().optional().default("Hero").describe("铃声名称，默认 Hero。可通过 list_sounds 查看可用值"),
    icon: z.string().optional().default("claude").describe("图标名称（不含 .png 后缀），默认 claude。可通过 list_icons 查看可用值，例如：openai、gemini、grok、deepseek、kimi、qwen 等"),
  },
  async ({ title, message, subtitle, sound, icon }) => {
    const args = [
      "-message", message,
      "-sound", sound ?? "Hero",
      "-group", "claude-notify",
    ];
    if (title) args.push("-title", title);
    if (subtitle) args.push("-subtitle", subtitle);
    const iconName = icon ?? "claude";
    const iconPath = join(ICONS_DIR, iconName + ".png");
    args.push("-contentImage", iconPath);

    const result = spawnSync(TERMINAL_NOTIFIER, args, { encoding: "utf8" });

    if (result.error || result.status !== 0) {
      const errMsg = result.error?.message ?? result.stderr ?? "unknown error";
      return {
        content: [{ type: "text", text: `通知发送失败: ${errMsg}` }],
        isError: true,
      };
    }

    return {
      content: [{ type: "text", text: `通知已发送: ${title ? `[${title}] ` : ""}${message}` }],
    };
  }
);

server.tool(
  "list_sounds",
  "列出 macOS 系统铃声列表",
  {},
  async () => {
    let sounds;
    try {
      sounds = readdirSync("/System/Library/Sounds")
        .filter((f) => f.endsWith(".aiff"))
        .map((f) => f.replace(".aiff", ""))
        .sort();
    } catch {
      sounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
                "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
                "Submarine", "Tink"];
    }
    return {
      content: [{ type: "text", text: sounds.join("\n") }],
    };
  }
);

server.tool(
  "list_icons",
  "列出所有可用的 AI 厂商图标名称（可用于 send_notification 的 icon 参数）",
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
