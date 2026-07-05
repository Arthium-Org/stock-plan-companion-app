# MCP GPT Reviewer — Standalone Tool Spec

## Purpose

MCP server that provides a `review_spec` tool for Claude Code. Sends a file to OpenAI GPT for review and returns structured feedback. Works across any project.

## Setup

```bash
mkdir ~/Projects/mcp-gpt-reviewer && cd ~/Projects/mcp-gpt-reviewer
```

## Requirements

1. **Standalone MCP server** — Node.js/TypeScript
2. **Tool:** `review_spec`
   - Input: `file_path` (string), `model` (optional, default "gpt-4o"), `prompt` (optional)
   - Reads the file content
   - Sends to OpenAI Chat Completions API
   - Returns GPT's response as text
3. **Config:** `OPENAI_API_KEY` environment variable
4. **No project dependency** — works with any file from any project

## Tool Schema

```json
{
  "name": "review_spec",
  "description": "Send a spec/design document to GPT for review. Returns structured feedback.",
  "parameters": {
    "file_path": {
      "type": "string",
      "description": "Absolute path to the file to review"
    },
    "model": {
      "type": "string",
      "description": "OpenAI model to use",
      "default": "gpt-4o"
    },
    "prompt": {
      "type": "string",
      "description": "Custom review prompt. If omitted, uses default.",
      "default": null
    },
    "context_files": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Optional additional file paths for context (e.g., related specs, invariants doc)",
      "default": []
    }
  },
  "required": ["file_path"]
}
```

## Default Review Prompt

```
You are reviewing a software spec/design document. Analyze for:

1. Correctness — are the technical decisions sound?
2. Completeness — are there missing requirements or edge cases?
3. Consistency — do different sections contradict each other?
4. Data handling — are there assumptions about data that could be wrong?
5. Edge cases — what happens in boundary conditions?

For each issue found:
- State whether it's Critical (must fix), Important (should fix), or Minor
- Explain the problem clearly
- Suggest a specific fix

End with:
- "What You Got Right" — things that are correct and should not be changed
- "Final Fix Checklist" — numbered list of changes to make

Be direct. Do not pad with unnecessary praise.
```

## Implementation

### package.json

```json
{
  "name": "mcp-gpt-reviewer",
  "version": "1.0.0",
  "type": "module",
  "main": "src/index.ts",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "openai": "^4.0.0"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "@types/node": "^20.0.0"
  }
}
```

### src/index.ts (skeleton)

```typescript
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import OpenAI from "openai";
import { readFileSync } from "fs";

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const DEFAULT_PROMPT = `You are reviewing a software spec/design document...`; // full prompt above

const server = new Server(
  { name: "mcp-gpt-reviewer", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler("tools/list", async () => ({
  tools: [{
    name: "review_spec",
    description: "Send a spec/design document to GPT for review",
    inputSchema: {
      type: "object",
      properties: {
        file_path: { type: "string", description: "Absolute path to file" },
        model: { type: "string", default: "gpt-4o" },
        prompt: { type: "string", description: "Custom review prompt" },
        context_files: { type: "array", items: { type: "string" }, default: [] }
      },
      required: ["file_path"]
    }
  }]
}));

server.setRequestHandler("tools/call", async (request) => {
  const { file_path, model = "gpt-4o", prompt, context_files = [] } = request.params.arguments;
  
  // Read main file
  const content = readFileSync(file_path, "utf-8");
  
  // Read context files
  const contextContent = context_files
    .map(f => `--- ${f} ---\n${readFileSync(f, "utf-8")}`)
    .join("\n\n");
  
  const systemPrompt = prompt || DEFAULT_PROMPT;
  const userMessage = contextContent 
    ? `${content}\n\n--- Additional Context ---\n${contextContent}`
    : content;
  
  const response = await openai.chat.completions.create({
    model,
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content: userMessage }
    ],
    max_tokens: 4096
  });
  
  return {
    content: [{
      type: "text",
      text: response.choices[0].message.content
    }]
  };
});

const transport = new StdioServerTransport();
await server.connect(transport);
```

## Claude Code Integration

Add to `~/.claude/settings.json` (global, works across all projects):

```json
{
  "mcpServers": {
    "gpt-reviewer": {
      "command": "node",
      "args": ["/Users/kirandev/Projects/mcp-gpt-reviewer/dist/index.js"],
      "env": {
        "OPENAI_API_KEY": "sk-..."
      }
    }
  }
}
```

## Usage (from any Claude Code session)

```
Claude, review the spec at docs/specs/M21-tranche-timeline/requirements.md using the review_spec tool
```

Claude calls the MCP tool → sends to GPT-4o → gets feedback → reviews it → updates spec.

## Optional Enhancements (Phase 2)

- `review_code` tool — reviews code files with different prompt
- `compare_spec_code` tool — checks if code matches spec
- Model selection via CLI arg
- Response caching (same file + same hash = cached response)
- Cost tracking (log tokens used per call)
