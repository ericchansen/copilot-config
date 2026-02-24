#!/usr/bin/env bash
# Setup script for Copilot CLI configuration, skills, MCP servers, and external repos.
#
# Backs up existing ~/.copilot/ config, symlinks config files, patches config.json
# with portable settings, symlinks local custom skills, clones/pulls external skill
# repos, links their skills into ~/.copilot/skills/, builds local MCP servers,
# validates env vars, and generates ~/.copilot/mcp-config.json.
#
# Idempotent — safe to re-run at any time.
#
# Usage:
#   ./setup.sh                                            # Interactive — prompts for options
#   ./setup.sh --work-skills --power-bi                   # Include work skills + Power BI
#   ./setup.sh --non-interactive                          # No prompts, base only (safe for cron)
#   ./setup.sh --non-interactive --work-skills --power-bi # No prompts, everything enabled

set -uo pipefail

# =============================================================================
# Preflight: Bash version + dependencies
# =============================================================================
if ((BASH_VERSINFO[0] < 4)); then
    echo "Error: Bash 4+ required (you have ${BASH_VERSION})."
    echo "macOS ships with Bash 3.2 — install a newer version:"
    echo "  brew install bash"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required for JSON processing."
    echo "Install:"
    echo "  macOS:  brew install jq"
    echo "  Ubuntu: sudo apt install jq"
    echo "  Fedora: sudo dnf install jq"
    exit 1
fi

# =============================================================================
# Configuration
# =============================================================================
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_COPILOT_DIR="$REPO_ROOT/.copilot"
REPO_SKILLS_DIR="$REPO_COPILOT_DIR/skills"
EXTERNAL_DIR="$REPO_ROOT/external"
MCP_SERVERS_JSON="$REPO_ROOT/mcp-servers.json"

COPILOT_HOME="$HOME/.copilot"
COPILOT_SKILLS_HOME="$COPILOT_HOME/skills"
CONFIG_JSON="$COPILOT_HOME/config.json"
PORTABLE_JSON="$REPO_COPILOT_DIR/config.portable.json"

# Git auth state
GH_AVAILABLE=false
SSH_AVAILABLE=false
PREFER_SSH=false

# Config files to symlink
CONFIG_FILE_LINKS=("copilot-instructions.md" "lsp-config.json")

# Keys allowed to be patched from config.portable.json into config.json
PORTABLE_ALLOWED_KEYS=("banner" "model" "render_markdown" "theme" "experimental" "reasoning_effort")

# External skill repositories (JSON)
EXTERNAL_REPOS_JSON=$(cat <<'REPOS_EOF'
[
  {
    "name": "anthropic",
    "displayName": "anthropics/skills",
    "repo": "https://github.com/anthropics/skills.git",
    "cloneDir": "anthropic-skills",
    "skillsSubdir": "skills",
    "category": "base",
    "exclude": [
      "skill-creator", "mcp-builder", "algorithmic-art", "brand-guidelines",
      "canvas-design", "doc-coauthoring", "internal-comms", "slack-gif-creator"
    ]
  },
  {
    "name": "github",
    "displayName": "github/awesome-copilot",
    "repo": "https://github.com/github/awesome-copilot.git",
    "cloneDir": "awesome-copilot",
    "skillsSubdir": "skills",
    "category": "base",
    "exclude": [
      "git-commit", "make-repo-contribution", "copilot-cli-quickstart",
      "microsoft-docs", "microsoft-skill-creator",
      "agentic-eval", "finnish-humanizer", "legacy-circuit-mockups",
      "nano-banana-pro-openrouter", "penpot-uiux-design", "scoutqa-test",
      "snowflake-semanticview", "pdftk-server", "sponsor-finder",
      "plantuml-ascii", "prd", "meeting-minutes", "webapp-testing"
    ]
  }
]
REPOS_EOF
)

OPTIONAL_REPOS_JSON=$(cat <<'REPOS_EOF'
[
  {
    "name": "msx-mcp",
    "displayName": "mcaps-microsoft/MSX-MCP",
    "repo": "https://github.com/mcaps-microsoft/MSX-MCP.git",
    "cloneDir": "msx-mcp",
    "skillsSubdir": "skills",
    "category": "work",
    "exclude": []
  },
  {
    "name": "spt-iq",
    "displayName": "mcaps-microsoft/SPT-IQ",
    "repo": "https://github.com/mcaps-microsoft/SPT-IQ.git",
    "cloneDir": "SPT-IQ",
    "skillsSubdir": "skills",
    "category": "work",
    "exclude": []
  }
]
REPOS_EOF
)

# =============================================================================
# Parse command-line flags
# =============================================================================
WORK_SKILLS=false
POWER_BI=false
CLEAN_ORPHANS=false
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --work-skills)    WORK_SKILLS=true ;;
        --power-bi)       POWER_BI=true ;;
        --clean-orphans)  CLEAN_ORPHANS=true ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        -h|--help)
            echo "Usage: $0 [--work-skills] [--power-bi] [--clean-orphans] [--non-interactive]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# =============================================================================
# Summary counters
# =============================================================================
SUMMARY_BACKED_UP=false
declare -a SUMMARY_CONFIG_LINKED=()
declare -a SUMMARY_CONFIG_SKIPPED=()
SUMMARY_CONFIG_PATCHED=false
SUMMARY_TRUSTED_FOLDER=false
SUMMARY_BEADS_REMOVED=false
declare -a SUMMARY_SKILLS_CREATED=()
declare -a SUMMARY_SKILLS_EXISTED=()
declare -a SUMMARY_SKILLS_SKIPPED=()
declare -a SUMMARY_SKILLS_FAILED=()
declare -a SUMMARY_EXTERNAL_CLONED=()
declare -a SUMMARY_EXTERNAL_PULLED=()
declare -a SUMMARY_EXTERNAL_FAILED=()
declare -a SUMMARY_CONFLICTS=()
declare -a SUMMARY_MCP_BUILT=()
declare -a SUMMARY_MCP_FAILED=()
declare -a SUMMARY_MCP_ENV_MISSING=()
SUMMARY_MCP_GENERATED=false

# =============================================================================
# Helper Functions
# =============================================================================

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

write_success() { echo -e "  ${GREEN}✓ $1${NC}"; }
write_info()    { echo -e "  ${CYAN}ℹ $1${NC}"; }
write_warn()    { echo -e "  ${YELLOW}⚠ $1${NC}"; }
write_err()     { echo -e "  ${RED}✗ $1${NC}"; }
write_step()    { echo ""; echo -e "${CYAN}▸ $1${NC}"; }

resolve_path() {
    # Portable realpath: works on macOS and Linux
    local target="$1"
    if command -v realpath &>/dev/null; then
        realpath "$target" 2>/dev/null || echo "$target"
    elif command -v python3 &>/dev/null; then
        python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$target"
    elif [[ -d "$target" ]]; then
        (cd "$target" && pwd)
    elif [[ -f "$target" ]]; then
        echo "$(cd "$(dirname "$target")" && pwd)/$(basename "$target")"
    else
        echo "$target"
    fi
}

ensure_dir() {
    [[ -d "$1" ]] || mkdir -p "$1"
}

is_symlink() {
    [[ -L "$1" ]]
}

get_link_target() {
    # Returns the target of a symlink
    if [[ -L "$1" ]]; then
        readlink "$1" 2>/dev/null || true
    fi
}

# Return value for symlink/clone functions
FUNC_RESULT=""

create_file_symlink() {
    # Create a file symlink. Sets FUNC_RESULT to: created | exists | skipped | copied | failed
    local link_path="$1" target_path="$2" display_name="$3"

    if [[ -e "$link_path" ]] || [[ -L "$link_path" ]]; then
        if is_symlink "$link_path"; then
            local existing
            existing=$(get_link_target "$link_path")
            local resolved_target resolved_existing
            resolved_target=$(resolve_path "$target_path")
            resolved_existing=$(resolve_path "$existing" 2>/dev/null || echo "")
            if [[ "$resolved_existing" == "$resolved_target" ]]; then
                FUNC_RESULT="exists"
                return
            fi
            # Wrong target — remove and re-create
            rm -f "$link_path"
        else
            # Real file exists
            write_warn "$display_name already exists as a real file at $link_path"
            if $NON_INTERACTIVE; then
                FUNC_RESULT="skipped"
                return
            fi
            read -rp "    Replace with symlink? [y/N] " answer
            if [[ "${answer,,}" != "y" ]]; then
                FUNC_RESULT="skipped"
                return
            fi
            rm -f "$link_path"
        fi
    fi

    if ln -s "$target_path" "$link_path" 2>/dev/null; then
        FUNC_RESULT="created"
    else
        # Fallback: copy the file
        if cp "$target_path" "$link_path" 2>/dev/null; then
            FUNC_RESULT="copied"
        else
            FUNC_RESULT="failed"
        fi
    fi
}

create_dir_symlink() {
    # Create a directory symlink. Sets FUNC_RESULT to: created | exists | skipped | failed
    local link_path="$1" target_path="$2" display_name="$3" ask_before="${4:-false}"

    if [[ -e "$link_path" ]] || [[ -L "$link_path" ]]; then
        if is_symlink "$link_path"; then
            local existing
            existing=$(get_link_target "$link_path")
            local resolved_target resolved_existing
            resolved_target=$(resolve_path "$target_path")
            resolved_existing=$(resolve_path "$existing" 2>/dev/null || echo "")
            if [[ "$resolved_existing" == "$resolved_target" ]]; then
                FUNC_RESULT="exists"
                return
            fi
            # Wrong target — remove and re-create
            rm -f "$link_path"
        else
            if [[ "$ask_before" == "true" ]]; then
                write_warn "$display_name already exists as a real directory at $link_path"
                read -rp "    Replace with symlink? [y/N] " answer
                if [[ "${answer,,}" != "y" ]]; then
                    FUNC_RESULT="skipped"
                    return
                fi
            fi
            rm -rf "$link_path"
        fi
    fi

    if ln -s "$target_path" "$link_path" 2>/dev/null; then
        FUNC_RESULT="created"
    else
        FUNC_RESULT="failed"
    fi
}

clone_or_pull_repo() {
    # Clone or pull a git repo. Sets FUNC_RESULT to:
    #   cloned | pulled | pull-failed | clone-failed | skipped | aborted | identity-check-failed
    # Also sets RESOLVED_CLONE_PATH if the path changes (manual clone).
    local repo_url="$1" target_path="$2" display_name="$3" category="${4:-base}"
    RESOLVED_CLONE_PATH="$target_path"

    # Resolve preferred URL (SSH when available)
    local clone_url="$repo_url"
    if $PREFER_SSH && [[ "$repo_url" =~ ^https://github\.com/(.+)$ ]]; then
        clone_url="git@github.com:${BASH_REMATCH[1]}"
    fi
    local auth_method="HTTPS"
    [[ "$clone_url" =~ ^git@ ]] && auth_method="SSH"

    if [[ -d "$target_path/.git" ]]; then
        pushd "$target_path" > /dev/null

        # Validate repo identity
        local current_remote
        current_remote=$(git remote get-url origin 2>/dev/null || true)
        if [[ -n "$current_remote" ]]; then
            local expected_slug="" actual_slug=""
            if [[ "$repo_url" =~ github\.com[:/](.+?)(.git)?$ ]]; then
                expected_slug="${BASH_REMATCH[1]%.git}"
            fi
            if [[ "$current_remote" =~ github\.com[:/](.+?)(.git)?$ ]]; then
                actual_slug="${BASH_REMATCH[1]%.git}"
            fi
            if [[ -n "$expected_slug" && -n "$actual_slug" && "$expected_slug" != "$actual_slug" ]]; then
                write_err "$display_name — path contains a different repo ($actual_slug, expected $expected_slug)"
                popd > /dev/null
                FUNC_RESULT="identity-check-failed"
                return
            fi
        fi

        # Upgrade remote to SSH if preferred
        if [[ -n "$current_remote" && "$current_remote" != "$clone_url" ]] && $PREFER_SSH; then
            git remote set-url origin "$clone_url" 2>/dev/null || true
            write_info "$display_name — remote updated to $auth_method"
        fi

        # Pull the current branch (don't force checkout — respect user's branch choice)
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        if [[ -n "$current_branch" ]]; then
            write_info "$display_name — on branch $current_branch"
        fi

        if git pull --quiet 2>/dev/null; then
            popd > /dev/null
            FUNC_RESULT="pulled"
        else
            write_warn "$display_name — failed to pull (may be offline)"
            popd > /dev/null

            # Interactive recovery for pull failures
            if [[ "$NON_INTERACTIVE" != "true" ]]; then
                echo ""
                echo "    [C] Continue       — use existing local copy (default)"
                echo "    [R] Retry          — try pulling again"
                echo "    [S] Skip           — skip this repo entirely"
                echo "    [A] Abort          — stop processing remaining repos"
                echo ""
                while true; do
                    read -rp "    Choice [C/r/s/a]: " choice
                    choice=$(echo "${choice:-c}" | tr '[:upper:]' '[:lower:]')
                    case "$choice" in
                        a) FUNC_RESULT="aborted"; return ;;
                        s) FUNC_RESULT="skipped"; return ;;
                        r)
                            pushd "$target_path" > /dev/null
                            if git pull --quiet 2>/dev/null; then
                                popd > /dev/null
                                FUNC_RESULT="pulled"
                                return
                            fi
                            popd > /dev/null
                            write_warn "$display_name — pull failed again"
                            continue
                            ;;
                        *)
                            FUNC_RESULT="pull-failed"
                            return
                            ;;
                    esac
                done
            fi

            FUNC_RESULT="pull-failed"
        fi
        return
    fi

    # Clone
    local parent_dir
    parent_dir=$(dirname "$target_path")
    ensure_dir "$parent_dir"

    while true; do
        # Clean up partial clone from prior attempt
        if [[ -e "$target_path" ]]; then
            if [[ -d "$target_path/.git" ]]; then
                FUNC_RESULT="cloned"
                return
            fi
            rm -rf "$target_path" 2>/dev/null || true
        fi

        write_info "$display_name — cloning via $auth_method ($category)"
        local attempted_methods=()

        # Try preferred URL first
        if git clone --quiet "$clone_url" "$target_path" 2>/dev/null; then
            FUNC_RESULT="cloned"
            return
        fi
        attempted_methods+=("git clone ($auth_method)")
        [[ -e "$target_path" ]] && rm -rf "$target_path" 2>/dev/null

        # Try gh CLI with auth token
        if $GH_AVAILABLE; then
            local repo_slug=""
            if [[ "$repo_url" =~ github\.com/([^/]+/[^/]+?)(.git)?$ ]]; then
                repo_slug="${BASH_REMATCH[1]}"
            fi
            if [[ -n "$repo_slug" ]]; then
                write_warn "$display_name — $auth_method clone failed, trying gh CLI..."
                local gh_token
                gh_token=$(gh auth token 2>/dev/null || true)
                if [[ -n "$gh_token" ]]; then
                    local saved_gh_token="${GH_TOKEN:-}"
                    local saved_gh_prompt="${GH_PROMPT_DISABLED:-}"
                    local saved_gcm="${GCM_INTERACTIVE:-}"
                    export GH_TOKEN="$gh_token"
                    export GH_PROMPT_DISABLED="1"
                    export GCM_INTERACTIVE="never"
                    if echo "" | gh repo clone "$repo_slug" "$target_path" 2>/dev/null; then
                        # Restore env
                        [[ -z "$saved_gh_token" ]] && unset GH_TOKEN || export GH_TOKEN="$saved_gh_token"
                        [[ -z "$saved_gh_prompt" ]] && unset GH_PROMPT_DISABLED || export GH_PROMPT_DISABLED="$saved_gh_prompt"
                        [[ -z "$saved_gcm" ]] && unset GCM_INTERACTIVE || export GCM_INTERACTIVE="$saved_gcm"
                        FUNC_RESULT="cloned"
                        return
                    fi
                    # Restore env
                    [[ -z "$saved_gh_token" ]] && unset GH_TOKEN || export GH_TOKEN="$saved_gh_token"
                    [[ -z "$saved_gh_prompt" ]] && unset GH_PROMPT_DISABLED || export GH_PROMPT_DISABLED="$saved_gh_prompt"
                    [[ -z "$saved_gcm" ]] && unset GCM_INTERACTIVE || export GCM_INTERACTIVE="$saved_gcm"
                else
                    write_warn "$display_name — gh CLI not authenticated, skipping gh clone"
                fi
                attempted_methods+=("gh repo clone")
                [[ -e "$target_path" ]] && rm -rf "$target_path" 2>/dev/null
            fi
        fi

        # Final fallback: HTTPS with token auth, no prompts
        if [[ "$clone_url" != "$repo_url" ]]; then
            write_warn "$display_name — falling back to HTTPS (token-only, no browser)..."
            local saved_git_prompt="${GIT_TERMINAL_PROMPT:-}"
            local saved_gcm2="${GCM_INTERACTIVE:-}"
            export GIT_TERMINAL_PROMPT="0"
            export GCM_INTERACTIVE="never"
            local https_url="$repo_url"
            if $GH_AVAILABLE; then
                local token
                token=$(gh auth token 2>/dev/null || true)
                if [[ -n "$token" && "$repo_url" =~ ^https:// ]]; then
                    https_url="${repo_url/https:\/\//https://x-access-token:${token}@}"
                fi
            fi
            if git clone --quiet "$https_url" "$target_path" 2>/dev/null; then
                [[ -z "$saved_git_prompt" ]] && unset GIT_TERMINAL_PROMPT || export GIT_TERMINAL_PROMPT="$saved_git_prompt"
                [[ -z "$saved_gcm2" ]] && unset GCM_INTERACTIVE || export GCM_INTERACTIVE="$saved_gcm2"
                FUNC_RESULT="cloned"
                return
            fi
            [[ -z "$saved_git_prompt" ]] && unset GIT_TERMINAL_PROMPT || export GIT_TERMINAL_PROMPT="$saved_git_prompt"
            [[ -z "$saved_gcm2" ]] && unset GCM_INTERACTIVE || export GCM_INTERACTIVE="$saved_gcm2"
            attempted_methods+=("git clone (HTTPS token-only)")
            [[ -e "$target_path" ]] && rm -rf "$target_path" 2>/dev/null
        fi

        # Interactive recovery
        if ! $NON_INTERACTIVE; then
            echo ""
            write_warn "Failed to clone $display_name after: $(IFS=', '; echo "${attempted_methods[*]}")"
            echo ""
            echo -e "    ${WHITE}[R] Retry          — try again (fix auth in another terminal first)${NC}"
            echo -e "    ${WHITE}[L] Login & retry  — run 'gh auth login' then retry${NC}"
            echo -e "    ${WHITE}[M] Manual clone   — you clone it yourself, tell me the path${NC}"
            echo -e "    ${WHITE}[S] Skip           — skip this repo, continue with others${NC}"
            echo -e "    ${WHITE}[A] Abort          — stop cloning remaining repos${NC}"
            echo ""
            read -rp "    Choice [R/l/m/s/a] " choice
            case "${choice,,}" in
                a) FUNC_RESULT="aborted"; return ;;
                s) FUNC_RESULT="skipped"; return ;;
                l)
                    write_info "Launching 'gh auth login'..."
                    gh auth login || true
                    continue ;;
                m)
                    echo ""
                    echo -e "    ${YELLOW}Clone it yourself using:${NC}"
                    echo -e "    ${CYAN}  git clone $clone_url <path>${NC}"
                    echo ""
                    read -rp "    Enter the path where you cloned it [$target_path] " manual_path
                    [[ -z "$manual_path" ]] && manual_path="$target_path"
                    manual_path="${manual_path/#\~/$HOME}"
                    manual_path=$(resolve_path "$manual_path")
                    if [[ -d "$manual_path/.git" ]]; then
                        write_success "$display_name — found at $manual_path"
                        RESOLVED_CLONE_PATH="$manual_path"
                        FUNC_RESULT="cloned"
                        return
                    else
                        write_err "No git repo found at $manual_path"
                        continue
                    fi ;;
                *) continue ;;
            esac
        fi

        # Non-interactive: just fail
        echo ""
        write_err "Failed to clone $display_name"
        echo -e "    ${YELLOW}You can manually clone:${NC}"
        echo -e "    ${CYAN}  git clone $clone_url $target_path${NC}"
        echo ""
        FUNC_RESULT="clone-failed"
        return
    done
}

get_skill_folders() {
    # Print skill folder names from a directory (folders containing SKILL.md), one per line.
    # Output format: name<TAB>path
    local base_path="$1"
    if [[ -d "$base_path" ]]; then
        for dir in "$base_path"/*/; do
            [[ -d "$dir" ]] || continue
            dir="${dir%/}"
            if [[ -f "$dir/SKILL.md" ]]; then
                echo "$(basename "$dir")"$'\t'"$dir"
            fi
        done
    fi
}

jq_inplace() {
    # jq in-place edit: jq_inplace 'filter' file [args...]
    local filter="$1" file="$2"
    shift 2
    local tmp
    tmp=$(mktemp)
    if jq "$@" "$filter" "$file" > "$tmp"; then
        mv "$tmp" "$file"
    else
        rm -f "$tmp"
        return 1
    fi
}

# =============================================================================
# Interactive option prompts
# =============================================================================

INCLUDE_WORK_SKILLS=false
if $WORK_SKILLS; then
    INCLUDE_WORK_SKILLS=true
elif ! $NON_INTERACTIVE; then
    read -rp "  Include work-specific skills (msx-mcp, SPT-IQ)? [y/N] " answer
    [[ "${answer,,}" == "y" ]] && INCLUDE_WORK_SKILLS=true
fi

INCLUDE_POWER_BI=false
if $POWER_BI; then
    INCLUDE_POWER_BI=true
elif ! $NON_INTERACTIVE; then
    read -rp "  Include Power BI Remote MCP server? [y/N] " answer
    [[ "${answer,,}" == "y" ]] && INCLUDE_POWER_BI=true
fi

INCLUDE_CLEAN_ORPHANS=false
if $CLEAN_ORPHANS; then
    INCLUDE_CLEAN_ORPHANS=true
elif ! $NON_INTERACTIVE; then
    read -rp "  Remove skills not managed by this repo? [y/N] " answer
    [[ "${answer,,}" == "y" ]] && INCLUDE_CLEAN_ORPHANS=true
fi

# Merge repos if work skills included
if $INCLUDE_WORK_SKILLS; then
    REPOS_JSON=$(echo "$EXTERNAL_REPOS_JSON" "$OPTIONAL_REPOS_JSON" | jq -s 'add')
else
    REPOS_JSON="$EXTERNAL_REPOS_JSON"
fi

# =============================================================================
# Main Script
# =============================================================================

echo ""
echo -e "${CYAN}📦 Copilot Config & Skills Setup${NC}"
echo -e "${CYAN}=================================${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Preflight: Git authentication
# ─────────────────────────────────────────────────────────────────────────────
write_step "Preflight: Git authentication"

# Check for GitHub CLI
if command -v gh &>/dev/null; then
    GH_AVAILABLE=true
    local_gh_status=$(gh auth status 2>&1 || true)
    accounts=$(echo "$local_gh_status" | grep -oP 'account \K\S+' || true)
    if [[ -n "$accounts" ]]; then
        account_list=$(echo "$accounts" | tr '\n' ', ' | sed 's/,$//')
        write_success "GitHub CLI — logged in ($account_list)"
    else
        write_warn "GitHub CLI found but not authenticated — run: gh auth login"
    fi
else
    write_warn "GitHub CLI (gh) not installed — credential prompts may appear"
    write_info "Install: https://cli.github.com"
fi

# Check SSH connectivity to github.com
ssh_result=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 || true)
if [[ "$ssh_result" =~ Hi\ (.+)! ]]; then
    SSH_AVAILABLE=true
    PREFER_SSH=true
    ssh_user="${BASH_REMATCH[1]}"
    write_success "SSH to github.com — OK (as $ssh_user, will prefer SSH URLs)"
else
    write_info "SSH to github.com not available — using HTTPS"
    if ! $GH_AVAILABLE; then
        write_warn "No SSH and no gh CLI — git may prompt for credentials"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Backup ~/.copilot/
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 1: Backup existing ~/.copilot/"

BACKUP_TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

if [[ -d "$COPILOT_HOME" ]]; then
    BACKUP_DIR="$HOME/.copilot-backup-$BACKUP_TIMESTAMP"
    ensure_dir "$BACKUP_DIR"

    # Back up config files (not sessions/logs/caches)
    for f in config.json copilot-instructions.md lsp-config.json mcp-config.json; do
        src="$COPILOT_HOME/$f"
        if [[ -e "$src" ]]; then
            cp "$src" "$BACKUP_DIR/$f" 2>/dev/null || true
        fi
    done

    # Back up skills directory
    if [[ -d "$COPILOT_SKILLS_HOME" ]]; then
        skills_backup="$BACKUP_DIR/skills"
        ensure_dir "$skills_backup"
        for dir in "$COPILOT_SKILLS_HOME"/*/; do
            [[ -d "$dir" ]] || continue
            dir="${dir%/}"
            name=$(basename "$dir")
            if [[ -L "$dir" ]]; then
                target=$(get_link_target "$dir")
                echo "$name -> $target" >> "$skills_backup/_junctions.txt"
            else
                cp -r "$dir" "$skills_backup/$name" 2>/dev/null || true
            fi
        done
    fi

    write_success "Backed up to $BACKUP_DIR"
    SUMMARY_BACKED_UP=true
else
    write_info "No existing ~/.copilot/ to back up"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Ensure directories exist
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 2: Ensure directories"

ensure_dir "$COPILOT_HOME"
ensure_dir "$COPILOT_SKILLS_HOME"
write_success "~/.copilot/ and ~/.copilot/skills/ exist"

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Symlink config files
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 3: Symlink config files"

for cfg_name in "${CONFIG_FILE_LINKS[@]}"; do
    target_path="$REPO_COPILOT_DIR/$cfg_name"
    link_path="$COPILOT_HOME/$cfg_name"

    if [[ ! -f "$target_path" ]]; then
        write_warn "$cfg_name — source not found in repo, skipping"
        continue
    fi

    create_file_symlink "$link_path" "$target_path" "$cfg_name"

    case "$FUNC_RESULT" in
        created)
            write_success "$cfg_name → linked"
            SUMMARY_CONFIG_LINKED+=("$cfg_name") ;;
        copied)
            write_warn "$cfg_name → copied (symlinks may need elevated permissions)"
            SUMMARY_CONFIG_LINKED+=("$cfg_name") ;;
        exists)
            write_info "$cfg_name — already linked correctly" ;;
        skipped)
            write_warn "$cfg_name — skipped (user declined)"
            SUMMARY_CONFIG_SKIPPED+=("$cfg_name") ;;
        failed)
            write_err "$cfg_name — failed to create symlink" ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Patch config.json with portable settings
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 4: Patch config.json"

# Create config.json if it doesn't exist
if [[ ! -f "$CONFIG_JSON" ]]; then
    echo '{}' > "$CONFIG_JSON"
fi

if [[ -f "$PORTABLE_JSON" ]]; then
    for key in "${PORTABLE_ALLOWED_KEYS[@]}"; do
        val=$(jq ".$key // null" "$PORTABLE_JSON")
        if [[ "$val" != "null" ]]; then
            jq_inplace ".$key = \$v" "$CONFIG_JSON" --argjson v "$val"
        fi
    done
    write_success "Patched config.json with portable settings"
    SUMMARY_CONFIG_PATCHED=true
else
    write_warn "config.portable.json not found in repo — skipping patch"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Add repo path to trusted_folders
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 5: Trusted folders"

RESOLVED_REPO_ROOT=$(resolve_path "$REPO_ROOT")

if jq -e ".trusted_folders // [] | map(select(. == \"$RESOLVED_REPO_ROOT\")) | length > 0" "$CONFIG_JSON" &>/dev/null; then
    write_info "Repo already in trusted_folders"
else
    jq_inplace '.trusted_folders = ((.trusted_folders // []) + [$path])' "$CONFIG_JSON" --arg path "$RESOLVED_REPO_ROOT"
    write_success "Added $RESOLVED_REPO_ROOT to trusted_folders"
    SUMMARY_TRUSTED_FOLDER=true
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: Remove beads marketplace
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 6: Remove beads marketplace"

if jq -e '.marketplaces' "$CONFIG_JSON" &>/dev/null; then
    # Handle object with named keys
    if jq -e '.marketplaces."beads-marketplace"' "$CONFIG_JSON" &>/dev/null; then
        jq_inplace 'del(.marketplaces."beads-marketplace")' "$CONFIG_JSON"
        write_success "Removed beads-marketplace entry"
        SUMMARY_BEADS_REMOVED=true
    # Handle array with name/key/id field
    elif jq -e '.marketplaces | type == "array"' "$CONFIG_JSON" &>/dev/null; then
        original_count=$(jq '.marketplaces | length' "$CONFIG_JSON")
        jq_inplace '.marketplaces = [.marketplaces[] | select((.key // .name // .id) != "beads-marketplace")]' "$CONFIG_JSON"
        new_count=$(jq '.marketplaces | length' "$CONFIG_JSON")
        if [[ "$original_count" != "$new_count" ]]; then
            write_success "Removed beads-marketplace entry"
            SUMMARY_BEADS_REMOVED=true
        else
            write_info "No beads-marketplace found in marketplaces array"
        fi
    else
        write_info "No beads-marketplace found"
    fi
else
    write_info "No marketplaces key in config.json"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: Symlink local custom skills
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 7: Symlink local custom skills"

# Collect local skills
declare -A LOCAL_SKILL_PATHS=()
while IFS=$'\t' read -r skill_name skill_path; do
    LOCAL_SKILL_PATHS["$skill_name"]="$skill_path"
done < <(get_skill_folders "$REPO_SKILLS_DIR")

local_count=${#LOCAL_SKILL_PATHS[@]}
if [[ $local_count -eq 0 ]]; then
    write_info "No local skills found in $REPO_SKILLS_DIR"
else
    write_info "Local: $local_count skills found in $REPO_SKILLS_DIR"
    for skill_name in $(echo "${!LOCAL_SKILL_PATHS[@]}" | tr ' ' '\n' | sort); do
        skill_path="${LOCAL_SKILL_PATHS[$skill_name]}"
        link_path="$COPILOT_SKILLS_HOME/$skill_name"
        ask=$( ! $NON_INTERACTIVE && echo "true" || echo "false")
        create_dir_symlink "$link_path" "$skill_path" "$skill_name" "$ask"

        case "$FUNC_RESULT" in
            created)
                write_success "$skill_name"
                SUMMARY_SKILLS_CREATED+=("$skill_name") ;;
            exists)
                write_info "$skill_name — already linked"
                SUMMARY_SKILLS_EXISTED+=("$skill_name") ;;
            skipped)
                write_warn "$skill_name — skipped (real dir, user declined)"
                SUMMARY_SKILLS_SKIPPED+=("$skill_name") ;;
            failed)
                write_err "$skill_name — symlink failed"
                SUMMARY_SKILLS_FAILED+=("$skill_name") ;;
        esac
    done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 8: Clone/pull external skill repos and symlink
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 8: External skill repositories"

# Track all skills: linked_skills[name] = source, skill_paths[name] = path
declare -A LINKED_SKILLS=()
declare -A SKILL_PATHS=()

# Register local skills first (local wins)
for skill_name in "${!LOCAL_SKILL_PATHS[@]}"; do
    LINKED_SKILLS["$skill_name"]="local"
    SKILL_PATHS["$skill_name"]="${LOCAL_SKILL_PATHS[$skill_name]}"
done

# Load or create .external-paths.json
EXTERNAL_PATHS_FILE="$REPO_ROOT/.external-paths.json"
if [[ ! -f "$EXTERNAL_PATHS_FILE" ]]; then
    echo '{}' > "$EXTERNAL_PATHS_FILE"
fi

ABORT_REMAINING_EXTERNAL=false

while IFS= read -r repo_json; do
    $ABORT_REMAINING_EXTERNAL && break

    repo_name=$(echo "$repo_json" | jq -r '.name')
    display_name=$(echo "$repo_json" | jq -r '.displayName')
    repo_url=$(echo "$repo_json" | jq -r '.repo')
    clone_dir=$(echo "$repo_json" | jq -r '.cloneDir')
    skills_subdir=$(echo "$repo_json" | jq -r '.skillsSubdir')
    category=$(echo "$repo_json" | jq -r '.category')

    resolved_path=""

    # 1. Check stored path from .external-paths.json
    stored_path=$(jq -r --arg n "$repo_name" '.[$n] // empty' "$EXTERNAL_PATHS_FILE")
    if [[ -n "$stored_path" && -d "$stored_path" ]]; then
        resolved_path="$stored_path"
        write_info "$display_name — using stored path: $resolved_path"
    fi

    if [[ -z "$resolved_path" ]]; then
        # Auto-detect: check external/<CloneDir>
        detected_path=""
        ext_path="$EXTERNAL_DIR/$clone_dir"
        if [[ -d "$ext_path" ]]; then
            detected_path=$(resolve_path "$ext_path")
        fi

        # 2. Interactive: prompt for parent directory
        if ! $NON_INTERACTIVE; then
            parent_suggestion="${detected_path:+$(dirname "$detected_path")}"
            [[ -z "$parent_suggestion" ]] && parent_suggestion="$EXTERNAL_DIR"
            read -rp "    Clone directory for $display_name [$parent_suggestion] " user_dir
            if [[ -n "$user_dir" ]]; then
                user_dir="${user_dir/#\~/$HOME}"
                resolved_path=$(resolve_path "$user_dir/$clone_dir")
            else
                resolved_path=$(resolve_path "$parent_suggestion/$clone_dir")
            fi
        # 3. Non-interactive: use detected or fallback
        else
            if [[ -n "$detected_path" ]]; then
                resolved_path="$detected_path"
                write_info "$display_name — auto-detected at $resolved_path"
            else
                resolved_path=$(resolve_path "$EXTERNAL_DIR/$clone_dir")
            fi
        fi
    fi

    skills_path="$resolved_path/$skills_subdir"

    clone_or_pull_repo "$repo_url" "$resolved_path" "$display_name" "$category"
    resolved_path="$RESOLVED_CLONE_PATH"

    skip_repo=false
    case "$FUNC_RESULT" in
        cloned)
            write_success "$display_name — cloned"
            SUMMARY_EXTERNAL_CLONED+=("$display_name") ;;
        pulled)
            write_success "$display_name — updated"
            SUMMARY_EXTERNAL_PULLED+=("$display_name") ;;
        skipped)
            write_warn "$display_name — skipped by user"
            skip_repo=true ;;
        aborted)
            write_warn "$display_name — aborting remaining external repo clones"
            ABORT_REMAINING_EXTERNAL=true ;;
        pull-failed)
            write_warn "$display_name — using existing local copy (pull failed)"
            SUMMARY_EXTERNAL_FAILED+=("$display_name") ;;
        *failed*)
            write_err "$display_name — $FUNC_RESULT"
            SUMMARY_EXTERNAL_FAILED+=("$display_name")
            skip_repo=true ;;
    esac
    $ABORT_REMAINING_EXTERNAL && break
    $skip_repo && continue

    # Store resolved path
    jq_inplace --arg n "$repo_name" --arg p "$resolved_path" '.[$n] = $p' "$EXTERNAL_PATHS_FILE"

    # Enumerate skills, respecting exclude list
    skills_path="$resolved_path/$skills_subdir"
    excluded_count=0
    while IFS=$'\t' read -r skill_name skill_path; do
        # Check exclude list
        if echo "$repo_json" | jq -e --arg s "$skill_name" '.exclude | index($s) != null' &>/dev/null; then
            ((excluded_count++))
            continue
        fi

        # Skip if already registered (local wins, first external wins)
        if [[ -n "${LINKED_SKILLS[$skill_name]+x}" ]]; then
            existing_source="${LINKED_SKILLS[$skill_name]}"
            if [[ "$existing_source" == "local" ]]; then
                write_warn "$skill_name — conflict with $display_name (local wins)"
                SUMMARY_CONFLICTS+=("$skill_name (local wins over $display_name)")
            fi
            # If from another external, first one wins (already registered)
            continue
        fi

        LINKED_SKILLS["$skill_name"]="$repo_name"
        SKILL_PATHS["$skill_name"]="$skill_path"
    done < <(get_skill_folders "$skills_path")

    ext_skill_count=$(get_skill_folders "$skills_path" | wc -l)
    write_info "$display_name: $ext_skill_count skills found in $skills_path"
    if [[ $excluded_count -gt 0 ]]; then
        write_info "$display_name: $excluded_count skill(s) excluded"
    fi
done < <(echo "$REPOS_JSON" | jq -c '.[]')

# Link external skills
for skill_name in $(echo "${!LINKED_SKILLS[@]}" | tr ' ' '\n' | sort); do
    source="${LINKED_SKILLS[$skill_name]}"
    [[ "$source" == "local" ]] && continue  # Already linked in Step 7
    skill_path="${SKILL_PATHS[$skill_name]}"
    link_path="$COPILOT_SKILLS_HOME/$skill_name"
    ask=$( ! $NON_INTERACTIVE && echo "true" || echo "false")

    create_dir_symlink "$link_path" "$skill_path" "$skill_name ($source)" "$ask"

    case "$FUNC_RESULT" in
        created)
            write_success "$skill_name ($source)"
            SUMMARY_SKILLS_CREATED+=("$skill_name") ;;
        exists)
            write_info "$skill_name — already linked"
            SUMMARY_SKILLS_EXISTED+=("$skill_name") ;;
        skipped)
            write_warn "$skill_name — skipped"
            SUMMARY_SKILLS_SKIPPED+=("$skill_name") ;;
        failed)
            write_err "$skill_name — symlink failed"
            SUMMARY_SKILLS_FAILED+=("$skill_name") ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Step 9: Resolve & build local MCP servers
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 9: Resolve & build local MCP servers"

# Determine enabled categories
ENABLED_CATEGORIES='["base"]'
$INCLUDE_WORK_SKILLS && ENABLED_CATEGORIES=$(echo "$ENABLED_CATEGORIES" | jq '. + ["work"]')
$INCLUDE_POWER_BI && ENABLED_CATEGORIES=$(echo "$ENABLED_CATEGORIES" | jq '. + ["powerbi"]')

ENABLED_SERVERS=$(jq -c --argjson cats "$ENABLED_CATEGORIES" '[.servers[] | select(.category as $c | $cats | index($c) != null)]' "$MCP_SERVERS_JSON")
ENABLED_COUNT=$(echo "$ENABLED_SERVERS" | jq 'length')

# Load or create .mcp-paths.json
MCP_PATHS_FILE="$REPO_ROOT/.mcp-paths.json"
if [[ ! -f "$MCP_PATHS_FILE" ]]; then
    echo '{}' > "$MCP_PATHS_FILE"
fi

ABORT_REMAINING_MCP=false

while IFS= read -r server_json; do
    $ABORT_REMAINING_MCP && break

    server_type=$(echo "$server_json" | jq -r '.type')
    [[ "$server_type" != "local" ]] && continue

    server_name=$(echo "$server_json" | jq -r '.name')
    server_repo=$(echo "$server_json" | jq -r '.repo')
    server_clone_dir=$(echo "$server_json" | jq -r '.cloneDir')
    server_category=$(echo "$server_json" | jq -r '.category')

    resolved_path=""

    # 1. Check stored path
    stored_path=$(jq -r --arg n "$server_name" '.[$n] // empty' "$MCP_PATHS_FILE")
    if [[ -n "$stored_path" && -d "$stored_path" ]]; then
        resolved_path="$stored_path"
        write_info "$server_name — using stored path: $resolved_path"
    fi

    if [[ -z "$resolved_path" ]]; then
        # Auto-detect from defaultPaths and external/
        detected_path=""
        while IFS= read -r dp; do
            expanded="${dp/#\~/$HOME}"
            if [[ -d "$expanded" ]]; then
                detected_path=$(resolve_path "$expanded")
                break
            fi
        done < <(echo "$server_json" | jq -r '.defaultPaths[]? // empty')

        if [[ -z "$detected_path" ]]; then
            ext_path="$EXTERNAL_DIR/$server_clone_dir"
            if [[ -d "$ext_path" ]]; then
                detected_path=$(resolve_path "$ext_path")
            fi
        fi

        # 2. Interactive: prompt
        if ! $NON_INTERACTIVE; then
            suggestion="${detected_path:-$EXTERNAL_DIR/$server_clone_dir}"
            read -rp "    Path to $server_name repo [$suggestion] " user_path
            if [[ -n "$user_path" ]]; then
                user_path="${user_path/#\~/$HOME}"
                resolved_path=$(resolve_path "$user_path")
            else
                resolved_path=$(resolve_path "$suggestion")
            fi
        # 3. Non-interactive: use detected or fallback
        else
            if [[ -n "$detected_path" ]]; then
                resolved_path="$detected_path"
                write_info "$server_name — auto-detected at $resolved_path"
            else
                resolved_path=$(resolve_path "$EXTERNAL_DIR/$server_clone_dir")
            fi
        fi
    fi

    # Clone if needed
    if [[ ! -d "$resolved_path" ]]; then
        write_info "$server_name — cloning to $resolved_path..."
        clone_or_pull_repo "$server_repo" "$resolved_path" "$server_name" "$server_category"
        resolved_path="$RESOLVED_CLONE_PATH"
        case "$FUNC_RESULT" in
            aborted)
                write_warn "$server_name — aborting remaining MCP clones"
                ABORT_REMAINING_MCP=true
                break ;;
            skipped)
                write_warn "$server_name — skipped by user"
                SUMMARY_MCP_FAILED+=("$server_name")
                continue ;;
            *failed*)
                write_err "$server_name — clone failed: $FUNC_RESULT"
                SUMMARY_MCP_FAILED+=("$server_name")
                continue ;;
        esac
    fi

    # Store resolved path
    jq_inplace --arg n "$server_name" --arg p "$resolved_path" '.[$n] = $p' "$MCP_PATHS_FILE"

    # Build
    build_cmds=$(echo "$server_json" | jq -r '.build[]? // empty')
    if [[ -n "$build_cmds" ]]; then
        write_info "$server_name — building..."
        build_failed=false
        pushd "$resolved_path" > /dev/null
        while IFS= read -r cmd; do
            if ! eval "$cmd" &>/dev/null; then
                write_err "$server_name — '$cmd' failed"
                build_failed=true
                break
            fi
        done <<< "$build_cmds"
        popd > /dev/null

        if $build_failed; then
            SUMMARY_MCP_FAILED+=("$server_name")
        else
            write_success "$server_name — built successfully"
            SUMMARY_MCP_BUILT+=("$server_name")
        fi
    fi
done < <(echo "$ENABLED_SERVERS" | jq -c '.[]')

local_server_count=$(echo "$ENABLED_SERVERS" | jq '[.[] | select(.type == "local")] | length')
if [[ ${#SUMMARY_MCP_BUILT[@]} -eq 0 && ${#SUMMARY_MCP_FAILED[@]} -eq 0 && "$local_server_count" -eq 0 ]]; then
    write_info "No local MCP servers to build"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 10: Validate MCP server environment variables
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 10: Validate MCP environment variables"

while IFS= read -r server_json; do
    server_name=$(echo "$server_json" | jq -r '.name')
    env_vars=$(echo "$server_json" | jq -r '.envVars[]? // empty')
    [[ -z "$env_vars" ]] && continue

    while IFS= read -r var_name; do
        val="${!var_name:-}"
        if [[ -n "$val" ]]; then
            write_info "$var_name — set ✓"
        elif ! $NON_INTERACTIVE; then
            write_warn "$var_name (required by $server_name) is not set"
            read -rp "    Enter value for $var_name (or press Enter to skip) " input_val
            if [[ -n "$input_val" ]]; then
                export "$var_name=$input_val"
                write_success "$var_name — set for this session"
                write_warn "  To persist, add to your shell profile: export $var_name=\"$input_val\""
            else
                write_warn "$var_name — skipped (MCP server $server_name may not work)"
                SUMMARY_MCP_ENV_MISSING+=("$var_name ($server_name)")
            fi
        else
            write_warn "$var_name (required by $server_name) is not set — server may not work at runtime"
            SUMMARY_MCP_ENV_MISSING+=("$var_name ($server_name)")
        fi
    done <<< "$env_vars"
done < <(echo "$ENABLED_SERVERS" | jq -c '.[]')

# ─────────────────────────────────────────────────────────────────────────────
# Step 11: Generate ~/.copilot/mcp-config.json
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 11: Generate mcp-config.json"

MCP_CONFIG='{"mcpServers":{}}'

while IFS= read -r server_json; do
    server_name=$(echo "$server_json" | jq -r '.name')
    server_type=$(echo "$server_json" | jq -r '.type')
    tools=$(echo "$server_json" | jq '.tools')

    entry='{}'
    case "$server_type" in
        npx)
            package=$(echo "$server_json" | jq -r '.package')
            args=$(echo "$server_json" | jq '[.args[]? // empty]')
            npx_args=$(echo "null" | jq --arg pkg "$package" --argjson extra "$args" '["-y", $pkg] + $extra')
            entry=$(jq -n --argjson tools "$tools" --argjson args "$npx_args" \
                '{"type":"local","command":"npx","tools":$tools,"args":$args}')
            ;;
        http)
            url=$(echo "$server_json" | jq -r '.url')
            headers=$(echo "$server_json" | jq '.headers // null')
            entry=$(jq -n --arg url "$url" --argjson tools "$tools" \
                '{"type":"http","url":$url,"tools":$tools}')
            if [[ "$headers" != "null" ]]; then
                entry=$(echo "$entry" | jq --argjson h "$headers" '.headers = $h')
            fi
            ;;
        local)
            command_name=$(echo "$server_json" | jq -r '.command')
            entry_point=$(echo "$server_json" | jq -r '.entryPoint')
            server_path=$(jq -r --arg n "$server_name" '.[$n] // empty' "$MCP_PATHS_FILE")
            if [[ -n "$server_path" ]]; then
                full_entry_point="$server_path/$entry_point"
            else
                clone_dir=$(echo "$server_json" | jq -r '.cloneDir')
                full_entry_point="$EXTERNAL_DIR/$clone_dir/$entry_point"
            fi
            full_entry_point=$(resolve_path "$full_entry_point")
            entry=$(jq -n --arg cmd "$command_name" --argjson tools "$tools" --arg ep "$full_entry_point" \
                '{"type":"local","command":$cmd,"tools":$tools,"args":[$ep]}')
            ;;
    esac

    MCP_CONFIG=$(echo "$MCP_CONFIG" | jq --arg name "$server_name" --argjson entry "$entry" \
        '.mcpServers[$name] = $entry')
done < <(echo "$ENABLED_SERVERS" | jq -c '.[]')

MCP_CONFIG_PATH="$COPILOT_HOME/mcp-config.json"
echo "$MCP_CONFIG" | jq '.' > "$MCP_CONFIG_PATH"
write_success "Generated $MCP_CONFIG_PATH ($ENABLED_COUNT servers)"
SUMMARY_MCP_GENERATED=true

# ─────────────────────────────────────────────────────────────────────────────
# Step 12: Clean up stale skill symlinks
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 12: Clean up stale skill symlinks"

stale_count=0
orphan_count=0

if $INCLUDE_CLEAN_ORPHANS; then
    # Remove ALL items in skills dir that aren't in the linked set
    for dir in "$COPILOT_SKILLS_HOME"/*/; do
        [[ -d "$dir" ]] || continue
        dir="${dir%/}"
        name=$(basename "$dir")
        if [[ -z "${LINKED_SKILLS[$name]+x}" ]]; then
            if [[ -L "$dir" ]]; then
                write_warn "Removing orphan symlink: $name"
                rm -f "$dir"
            else
                write_warn "Removing orphan skill: $name"
                rm -rf "$dir"
            fi
            ((orphan_count++))
        fi
    done
else
    # Default: only remove stale symlinks pointing into managed directories
    managed_repo_root=$(resolve_path "$REPO_ROOT")
    managed_external=$(resolve_path "$EXTERNAL_DIR")

    for dir in "$COPILOT_SKILLS_HOME"/*/; do
        [[ -d "$dir" ]] || continue
        dir="${dir%/}"
        name=$(basename "$dir")
        if [[ -L "$dir" ]]; then
            target=$(get_link_target "$dir")
            if [[ -n "$target" ]]; then
                resolved=$(resolve_path "$target")
                is_managed=false
                [[ "$resolved" == "$managed_repo_root"* ]] && is_managed=true
                [[ "$resolved" == "$managed_external"* ]] && is_managed=true
                if $is_managed && [[ -z "${LINKED_SKILLS[$name]+x}" ]]; then
                    write_warn "Removing stale symlink: $name → $target"
                    rm -f "$dir"
                    ((stale_count++))
                fi
            fi
        fi
    done
fi

total_cleaned=$((stale_count + orphan_count))
if [[ $total_cleaned -eq 0 ]]; then
    write_info "No stale symlinks to clean up"
else
    parts=()
    [[ $stale_count -gt 0 ]] && parts+=("$stale_count stale")
    [[ $orphan_count -gt 0 ]] && parts+=("$orphan_count orphan")
    write_success "Cleaned up $(IFS=', '; echo "${parts[*]}") skill(s)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 13: Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}═══════════════════════════════════${NC}"
echo -e "  ${GREEN}✨ Setup Complete${NC}"
echo -e "${CYAN}═══════════════════════════════════${NC}"
echo ""

if $SUMMARY_BACKED_UP; then
    echo -e "  ${WHITE}Backup:           ~/.copilot-backup-$BACKUP_TIMESTAMP/${NC}"
fi

linked_count=${#SUMMARY_CONFIG_LINKED[@]}
skipped_cfg=${#SUMMARY_CONFIG_SKIPPED[@]}
if [[ $linked_count -gt 0 || $skipped_cfg -gt 0 ]]; then
    echo -e "  ${WHITE}Config symlinks:  $linked_count linked, $skipped_cfg skipped${NC}"
fi

if $SUMMARY_CONFIG_PATCHED; then
    echo -e "  ${WHITE}Config patched:   $(IFS=', '; echo "${PORTABLE_ALLOWED_KEYS[*]}")${NC}"
fi

if $SUMMARY_TRUSTED_FOLDER; then
    echo -e "  ${WHITE}Trusted folder:   $RESOLVED_REPO_ROOT (added)${NC}"
fi

if $SUMMARY_BEADS_REMOVED; then
    echo -e "  ${WHITE}Marketplace:      beads-marketplace removed${NC}"
fi

created_count=${#SUMMARY_SKILLS_CREATED[@]}
existed_count=${#SUMMARY_SKILLS_EXISTED[@]}
skipped_count=${#SUMMARY_SKILLS_SKIPPED[@]}
failed_count=${#SUMMARY_SKILLS_FAILED[@]}

echo ""
echo -e "  ${CYAN}Skills (no allowlist — all linked):${NC}"
[[ $created_count -gt 0 ]] && echo -e "    ${GREEN}Created:        $created_count${NC}"
[[ $existed_count -gt 0 ]] && echo -e "    ${CYAN}Already linked: $existed_count${NC}"
[[ $skipped_count -gt 0 ]] && echo -e "    ${YELLOW}Skipped:        $skipped_count${NC}"
[[ $failed_count  -gt 0 ]] && echo -e "    ${RED}Failed:         $failed_count${NC}"
if [[ $created_count -eq 0 && $existed_count -eq 0 && $skipped_count -eq 0 && $failed_count -eq 0 ]]; then
    echo -e "    ${GRAY}(none)${NC}"
fi

ext_cloned=${#SUMMARY_EXTERNAL_CLONED[@]}
ext_pulled=${#SUMMARY_EXTERNAL_PULLED[@]}
ext_failed=${#SUMMARY_EXTERNAL_FAILED[@]}
if [[ $ext_cloned -gt 0 || $ext_pulled -gt 0 || $ext_failed -gt 0 ]]; then
    echo ""
    echo -e "  ${CYAN}External repos:${NC}"
    [[ $ext_cloned -gt 0 ]] && echo -e "    ${GREEN}Cloned:         $ext_cloned${NC}"
    [[ $ext_pulled -gt 0 ]] && echo -e "    ${CYAN}Updated:        $ext_pulled${NC}"
    [[ $ext_failed -gt 0 ]] && echo -e "    ${RED}Failed:         $ext_failed${NC}"
fi

if [[ ${#SUMMARY_CONFLICTS[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${YELLOW}Conflicts resolved:${NC}"
    for c in "${SUMMARY_CONFLICTS[@]}"; do
        echo -e "    ${YELLOW}• $c${NC}"
    done
fi

if $SUMMARY_MCP_GENERATED; then
    echo ""
    echo -e "  ${CYAN}MCP servers:${NC}"
    echo -e "    ${GREEN}Configured:     $ENABLED_COUNT${NC}"
    if [[ ${#SUMMARY_MCP_BUILT[@]} -gt 0 ]]; then
        echo -e "    ${GREEN}Built:          $(IFS=', '; echo "${SUMMARY_MCP_BUILT[*]}")${NC}"
    fi
    if [[ ${#SUMMARY_MCP_FAILED[@]} -gt 0 ]]; then
        echo -e "    ${RED}Build failed:   $(IFS=', '; echo "${SUMMARY_MCP_FAILED[*]}")${NC}"
    fi
    if [[ ${#SUMMARY_MCP_ENV_MISSING[@]} -gt 0 ]]; then
        echo -e "    ${YELLOW}Env missing:    $(IFS=', '; echo "${SUMMARY_MCP_ENV_MISSING[*]}")${NC}"
    fi
fi

echo ""
