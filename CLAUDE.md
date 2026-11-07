# Claude Code — project context

<!-- cloude-code-toolbox:token-optimization-begin -->

### Token Optimization (Claude Code ToolBox)

_Active level: concise_

- Respond concisely: 1-3 sentences max unless the user asks for detail.
- Never restate the user's question or echo file contents back verbatim.
- When showing code changes, show only modified lines with 2 lines of context.
- Skip meta-commentary ("I'll now...", "Let me...", "Here's what I did...").
- Before reading a file, check `.claude/project-map.md` for structural context.
- If you already read a file this session and it hasn't changed, reference your memory instead of re-reading.
- Do not read files matching `.claudeignore` patterns unless explicitly asked.

<!-- cloude-code-toolbox:token-optimization-end -->
<!-- cloude-code-toolbox:mcp-skills-awareness-begin -->

### MCP & Skills awareness (Claude Code ToolBox)

_Last synced: 2026-11-07T17:53:16.128Z._

- **Full report:** `.claude/cloude-code-toolbox-mcp-skills-awareness.md` in this workspace (auto-overwritten on each scan). Use it as ground truth for configured servers and skill folders.
- **MCP:** For **live tools** in Claude Code, enable the matching server via `/mcp`. Servers are configured in `~/.claude.json` (user) and `.mcp.json` (project).
- **When the user’s task matches a server** (e.g. Confluence work and a **Confluence** / **Atlassian** MCP is listed), **prefer that server id** and plan on tool use—not only file search.
- **Skills:** Folders below contain `SKILL.md`; attach or cite paths in chat when relevant.

#### Workspace MCP

- `d:\AutoTrades\Nixo_v5.03_Telegram_DualRoulette_Package\.mcp.json` _(workspace: Nixo_v5.03_Telegram_DualRoulette_Package)_ — _file missing_

_No active workspace servers in mcp.json._

#### User MCP

- `C:\Users\Behnam\.claude.json` — _file missing_

_No active user-scoped servers in mcp.json._

#### Project skills

_None found (or no workspace open)._

#### User skills

_None found._

<!-- cloude-code-toolbox:mcp-skills-awareness-end -->
