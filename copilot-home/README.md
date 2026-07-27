# copilot-home — portable Copilot CLI config (home profile)

Checked-in copies of the user-level Copilot CLI config for the **home / personal
machine**, deployed into `~/.copilot/` so the same setup works across machines.

The work machine has its own profile in `erichansen_microsoft/copilot-marketplace-work`
under `copilot-home/`; the two profiles share structure but differ in what's
enabled by default (this home profile enables only the personal plugins and the
general dev MCP servers).

| File | Purpose |
|------|---------|
| `settings.json` | Preferences + `extraKnownMarketplaces` (copilot-marketplace) + `enabledPlugins` (personal plugins) |
| `mcp-config.json` | General dev MCP servers: context7, msft-learn, playwright, chrome-devtools |
| `lsp-config.json` | LSP servers: typescript, python, rust |
| `link.ps1` | Deploys the config into `~/.copilot/` |
| `copilot-instructions.md` | Global custom instructions, symlinked into `~/.copilot/` |

## Bootstrap a machine

```powershell
# 1. Provide secrets via env (never committed):
#    CONTEXT7_API_KEY raises Context7's rate limits (get one at context7.com/dashboard).
[Environment]::SetEnvironmentVariable("CONTEXT7_API_KEY", "<your-key>", "User")

# 2. Deploy the config into ~/.copilot:
#   - mcp-config.json / lsp-config.json / copilot-instructions.md are symlinked
#     (need Developer Mode or
#     elevation; pass -Copy to fall back to plain copies)
#   - settings.json is merged + written as a real file, preserving any
#     machine-injected entries (e.g. Windows Terminal's wt-local marketplace)
pwsh ./copilot-home/link.ps1

# 3. Start Copilot — enabledPlugins auto-installs from the marketplace.
copilot
```

## Notes

- Plugins install from `ericchansen/copilot-marketplace` (`copilot-marketplace`).
  Run `link.ps1` only after that repo's default branch has the current plugin layout.
- MCP/LSP servers are intentionally **not** bundled in plugins; they live here.
- Machine-specific, tool-injected entries (like `wt-local` / `wt-agent-hooks`)
  are deliberately kept **out** of the committed `settings.json`. `link.ps1`
  preserves them locally so they keep working without polluting source.
