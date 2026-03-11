---
name: mcp-reauth
description: 'Manage MCP server OAuth tokens — list cached tokens, clear specific servers to force re-login, or clear all. Use when user says "re-login", "reauth", "wrong account", "switch account", "clear tokens", "mcp login", "mcp auth", "refresh auth", "token cache", or any variant of MCP server re-authentication.'
license: MIT
allowed-tools: powershell, read_powershell, write_powershell, ask_user
---

# MCP Server Re-Authentication

Manage OAuth token caches for remote MCP servers (Power BI, Dataverse, Outlook, Teams, SharePoint, Word, etc.). Copilot CLI caches OAuth tokens as `<hash>.tokens.json` files in `~/.copilot/mcp-oauth-config/`. This skill lets you inspect, clear, and force re-authentication.

## Token Storage

Copilot CLI stores remote MCP server auth state as files in `~/.copilot/mcp-oauth-config/`:

| File | Purpose |
|------|---------|
| `<hash>.json` | Server metadata (URL, client ID, redirect URI) — **do not delete** |
| `<hash>.tokens.json` | Cached OAuth tokens (access + refresh) — **delete to force re-login** |
| `<hash>.verifier` | PKCE verifier from an in-progress or stale OAuth flow — **delete if auth is stuck** |

The `<hash>` is a SHA-256 of the server URL. The `.json` file maps hash → server URL. The `.tokens.json` file holds the cached access/refresh tokens.

## Workflow

### 1. Discover cached tokens

Scan `~/.copilot/mcp-oauth-config/` for `*.json` metadata files and resolve each to its server:

```powershell
$oauthDir = Join-Path $HOME ".copilot" "mcp-oauth-config"
if (-not (Test-Path $oauthDir)) { return @() }
Get-ChildItem $oauthDir -Filter "*.json" |
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
    $verifierFile = Join-Path $_.DirectoryName "$hash.verifier"
    $verifierAge = if (Test-Path $verifierFile) { (Get-Item $verifierFile).LastWriteTime } else { $null }
    $hasStaleVerifier = $null -ne $verifierAge -and $verifierAge -lt (Get-Date).AddMinutes(-2) -and -not $hasTokens
    [PSCustomObject]@{
      Hash       = $hash.Substring(0, 12) + "..."
      Server     = $serverUrl
      HasTokens  = $hasTokens
      LastAuth   = $tokensAge
      StaleAuth  = $hasStaleVerifier
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

  Server                  Status         Last Auth
  ─────────────────────   ────────────   ─────────────────
  Power BI / Fabric       ⚠️ stale auth  (auth flow stuck)
  MSX Dataverse           cached         2 hours ago
  Outlook Calendar        cached         2 hours ago
  Outlook Mail            cached         2 hours ago
  SharePoint / OneDrive   cached         2 hours ago
  Word                    cached         1 hour ago
  Teams                   cached         2 hours ago
```

Status values:
- **cached** — tokens exist and were last refreshed at the shown time
- **⚠️ stale auth** — a `.verifier` file older than 2 minutes exists without valid cached tokens. This means a previous OAuth flow was interrupted or failed. Auth will keep failing until cleared. (A `.verifier` with valid tokens is normal — the tokens succeeded despite the leftover verifier. A `.verifier` younger than 2 minutes may indicate an active in-progress flow — don't clear it.)
- **no tokens** — no cached tokens (will prompt login on next use)

### 4. Determine action

Based on the user's request:

- **"list" / "status" / "show tokens"** → Show the table above. Done.
- **Specific server mentioned** (e.g., "reauth Power BI", "wrong account for Dataverse") → Skip to step 5 with those servers pre-selected.
- **"clear all" / "reauth everything"** → Confirm with user, then clear all `.tokens.json` files.
- **General "reauth" / "wrong account"** → Use `ask_user` to let them pick which servers.
- **User reports `AADSTS9010010` or "Authorization Failed" loops** → Recommend nuclear clear (step 6b) for the affected server. The normal token clear won't fix this — the stale `.json` config with a hardcoded redirect port is the root cause.

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

For each selected server, delete the `.tokens.json` file AND any `.verifier` file (stale PKCE state):

```powershell
$oauthDir = Join-Path $HOME ".copilot" "mcp-oauth-config"
$tokensFile = Join-Path $oauthDir "$($fullHash).tokens.json"
$verifierFile = Join-Path $oauthDir "$($fullHash).verifier"
Remove-Item $tokensFile -Force -ErrorAction SilentlyContinue
Remove-Item $verifierFile -Force -ErrorAction SilentlyContinue
```

**Do NOT delete the `<hash>.json` metadata file** — it maps the hash to the server URL and is needed for re-discovery.

### 6b. Nuclear clear (if normal clear doesn't fix auth)

If clearing tokens + verifier still fails with `AADSTS9010010` ("resource doesn't match requested scopes"), the `.json` config file itself may have a **stale redirect URI** with a hardcoded port from a previous session. Delete ALL files for that hash to force the CLI to rediscover the endpoint from scratch via RFC 9728:

```powershell
$oauthDir = Join-Path $HOME ".copilot" "mcp-oauth-config"
if (Test-Path $oauthDir) {
    Get-ChildItem $oauthDir -Filter "$($fullHash)*" | Remove-Item -Force
}
```

**When to use nuclear clear:**
- `AADSTS9010010` persists after normal token clear + CLI restart
- The `.json` config has a `redirectUri` with a port that was valid in a previous session but is no longer listening
- The server changed its OAuth discovery metadata since the config was cached

After nuclear clear, the CLI will do fresh RFC 9728 discovery on next use — new config, new port, new tokens.

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

- **No tokens found**: Report "No cached MCP tokens found in `~/.copilot/mcp-oauth-config/`. Tokens are created when you first use a remote MCP server."
- **Token file already missing**: Skip silently, report as "already cleared".
- **Stale verifier without tokens**: This means a previous OAuth flow was interrupted. Clear the `.verifier` file — it blocks all future auth attempts for that server.
- **`AADSTS9010010` after clearing tokens**: The `.json` config has a stale `redirectUri` with a hardcoded port. Use nuclear clear (step 6b) to delete all files for that hash, then restart CLI. This forces fresh RFC 9728 discovery.
- **Auth keeps failing on every CLI restart**: Multiple browser tabs opening with "Authorization Failed" — this is the stale config + verifier cycle. Nuclear clear resolves it.
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
