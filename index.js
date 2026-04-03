import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { spawnSync, execFileSync } from "child_process";
import { readdirSync } from "fs";

const TERMINAL_NOTIFIER = "/opt/homebrew/bin/terminal-notifier";

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
    sound: z.string().optional().default("Hero").describe("铃声名称，默认 Hero"),
  },
  async ({ title, message, subtitle, sound }) => {
    const args = [
      "-message", message,
      "-sound", sound ?? "Hero",
      "-activate", "dev.warp.Warp-Stable",
      "-group", "claude-notify",
    ];
    if (title) args.push("-title", title);
    if (subtitle) args.push("-subtitle", subtitle);

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

const transport = new StdioServerTransport();
await server.connect(transport);
