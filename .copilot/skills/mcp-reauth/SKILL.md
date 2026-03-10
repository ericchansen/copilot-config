---
name: mcp-reauth
description: 'Manage MCP server OAuth tokens — list cached tokens, clear specific servers to force re-login, or clear all. Use when user says "re-login", "reauth", "wrong account", "switch account", "clear tokens", "mcp login", "mcp auth", "refresh auth", "token cache", or any variant of MCP server re-authentication.'
license: MIT
allowed-tools: powershell, read_powershell, write_powershell, ask_user
---

# MCP Server Re-Authentication

Manage OAuth token caches for remote MCP servers (Power BI, Dataverse, Outlook, Teams, SharePoint, Word, etc.). Copilot CLI caches OAuth tokens as `<hash>.tokens.json` files in `~/.copilot/`. This skill lets you inspect, clear, and force re-authentication.

## Token Storage

Copilot CLI stores remote MCP server auth state as pairs of files in `~/.copilot/`:

| File | Purpose |
|------|---------|
| `<hash>.json` | Server metadata (URL, name) — **do not delete** |
| `<hash>.tokens.json` | Cached OAuth tokens — **delete to force re-login** |

The `<hash>` is a SHA-256 of the server URL. The `.json` file maps hash → server URL. The `.tokens.json` file holds the cached access/refresh tokens.

## Workflow

### 1. Discover cached tokens

Scan `~/.copilot/` for `*.tokens.json` files and resolve each to its server by reading the companion `<hash>.json`:

```powershell
Get-ChildItem "$env:USERPROFILE\.copilot" -Filter "*.json" |
  Where-Object { $_.Name -match "^[a-f0-9]{64}\.json$" } |
  ForEach-Object {
    $hash = $_.BaseName
    $tokensFile = Join-Path $_.DirectoryName "$hash.tokens.json"
    $meta = Get-Content $_.FullName -Raw | ConvertFrom-Json
    if ($null -ne $meta.serverUrl) {
      $serverUrl = $meta.serverUrl
    } elseif ($null -ne $meta.url) {
      $serverUrl = $meta.url
    } elseif ($null -ne $meta.name) {
      $serverUrl = $meta.name
    } else {
      $serverUrl = "unknown"
    }
    $hasTokens = Test-Path $tokensFile
    $tokensAge = if ($hasTokens) { (Get-Item $tokensFile).LastWriteTime } else { $null }
    [PSCustomObject]@{
      Hash       = $hash.Substring(0, 12) + "..."
      Server     = $serverUrl
      HasTokens  = $hasTokens
      LastAuth   = $tokensAge
      FullHash   = $hash
    }
  }
```

### 2. Assign friendly names

Map server URLs to human-readable names using these known patterns:

| URL Pattern | Friendly Name |
|-------------|---------------|
| `api.fabric.microsoft.com` | Power BI / Fabric |
| `crm.dynamics.com` | MSX Dataverse |
| `mcp_CalendarTools` | Outlook Calendar |
| `mcp_MailTools` | Outlook Mail |
| `mcp_ODSPRemoteServer` | SharePoint / OneDrive |
| `mcp_WordServer` | Word |
| `mcp_TeamsServer` | Teams |

For unknown URLs, use the URL itself as the display name.

### 3. Present status to user

Display a table of all cached tokens:

```
🔐 MCP Server Token Cache

  Server                  Status    Last Auth
  ─────────────────────   ────────  ─────────────────
  Power BI / Fabric       cached    10 min ago
  MSX Dataverse           cached    2 hours ago
  Outlook Calendar        cached    2 hours ago
  Outlook Mail            cached    2 hours ago
  SharePoint / OneDrive   cached    2 hours ago
  Word                    cached    1 hour ago
  Teams                   cached    2 hours ago
```

### 4. Determine action

Based on the user's request:

- **"list" / "status" / "show tokens"** → Show the table above. Done.
- **Specific server mentioned** (e.g., "reauth Power BI", "wrong account for Dataverse") → Skip to step 5 with those servers pre-selected.
- **"clear all" / "reauth everything"** → Confirm with user, then clear all `.tokens.json` files.
- **General "reauth" / "wrong account"** → Use `ask_user` to let them pick which servers.

### 5. Ask which servers to clear (if not already determined)

Use `ask_user` with a multi-select checklist of the discovered servers:

```json
{
  "message": "Which MCP servers should I clear tokens for? You'll re-authenticate on next use.",
  "requestedSchema": {
    "properties": {
      "servers": {
        "type": "array",
        "title": "Servers to re-authenticate",
        "description": "Select the MCP servers you need to re-login to",
        "items": {
          "type": "string",
          "enum": ["<dynamically populated from discovered servers>"]
        },
        "minItems": 1
      }
    },
    "required": ["servers"]
  }
}
```

Always include an "ALL — clear everything" option at the end.

### 6. Clear selected tokens

For each selected server, delete ONLY the `.tokens.json` file (not the `.json` metadata):

```powershell
$tokensFile = "$env:USERPROFILE\.copilot\$($fullHash).tokens.json"
Remove-Item $tokensFile -Force -ErrorAction SilentlyContinue
```

### 7. Report results

```
✅ Cleared OAuth tokens:
  • Power BI / Fabric
  • MSX Dataverse

⚠️  Restart your CLI session to trigger fresh login prompts.
   Run: /quit → relaunch Copilot CLI
   On first use of each cleared server, your browser will open for OAuth login.
```

### 8. Handle edge cases

- **No tokens found**: Report "No cached MCP tokens found. Tokens are created when you first use a remote MCP server."
- **Token file already missing**: Skip silently, report as "already cleared".
- **User says "which account am I logged in as?"**: The `.tokens.json` files contain OAuth tokens but typically don't include human-readable account info. Suggest using the MCP server itself to check (e.g., `msx_auth_status` for Dataverse, or making a test query).

## Trigger Phrases

Activate this skill on any of these patterns:
- "reauth", "re-auth", "re-login", "relogin"
- "wrong account", "switch account", "change account"
- "clear tokens", "clear cache", "clear auth"
- "mcp login", "mcp auth", "mcp tokens"
- "refresh auth", "force login"
- "token cache", "cached tokens"
- "logged into wrong", "wrong credentials"
