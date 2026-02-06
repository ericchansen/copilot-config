#!/usr/bin/env bash
# Undo what setup.sh did: remove symlinks in ~/.copilot/ that point into this
# repo. Optionally restore from the most recent backup.
# Safe: only removes symlinks, never deletes real files or directories.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTERNAL_DIR="$REPO_ROOT/external"
COPILOT_HOME="$HOME/.copilot"

OWNED_ROOTS=(
    "$(cd "$REPO_ROOT" && pwd)"
    "$HOME/repos/skills"
    "$HOME/repos/copilot-config"
    "$(cd "$EXTERNAL_DIR" 2>/dev/null && pwd || echo "$EXTERNAL_DIR")"
)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

write_success() { echo -e "  ${GREEN}✓${NC} $1"; }
write_info()    { echo -e "  ${CYAN}ℹ${NC} $1"; }
write_warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
write_err()     { echo -e "  ${RED}✗${NC} $1"; }
write_step()    { echo ""; echo -e "${CYAN}▸ $1${NC}"; }

# Resolve symlink target to absolute path
resolve_link() {
    local target
    target="$(readlink "$1" 2>/dev/null)" || return 1
    # Make relative targets absolute
    if [[ "$target" != /* ]]; then
        target="$(cd "$(dirname "$1")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")"
    fi
    echo "$target"
}

# Check if a resolved target starts with any of our owned roots
points_into_owned() {
    local target="$1"
    for root in "${OWNED_ROOTS[@]}"; do
        [[ -z "$root" ]] && continue
        if [[ "$target" == "$root"* ]]; then return 0; fi
    done
    return 1
}

# Remove owned symlinks from a directory, appending to REMOVED
remove_owned_links() {
    local scan_dir="$1"
    for item in "$scan_dir"/*; do
        [[ -e "$item" || -L "$item" ]] || continue
        if [[ -L "$item" ]]; then
            target="$(resolve_link "$item")" || continue
            if points_into_owned "$target"; then
                rel_name="${item/#$COPILOT_HOME/~\/.copilot}"
                write_warn "Removing: $rel_name → $target"
                rm "$item"
                REMOVED+=("$rel_name")
            fi
        fi
    done
}

echo ""
echo -e "${CYAN}🔄 Copilot Config & Skills Restore${NC}"
echo -e "${CYAN}====================================${NC}"

REMOVED=()

# Step 1: Find and remove symlinks in ~/.copilot/
write_step "Step 1: Scan ~/.copilot/ for symlinks pointing into this repo"

if [[ ! -d "$COPILOT_HOME" ]]; then
    write_info "~/.copilot/ does not exist — nothing to do"
else
    remove_owned_links "$COPILOT_HOME"

    if [[ -d "$COPILOT_HOME/skills" ]]; then
        remove_owned_links "$COPILOT_HOME/skills"
        # Remove skills dir if now empty
        if [[ -z "$(ls -A "$COPILOT_HOME/skills" 2>/dev/null)" ]]; then
            rmdir "$COPILOT_HOME/skills"
            write_info "Removed empty ~/.copilot/skills/"
        fi
    fi
fi

# Step 2: Offer to restore from backup
write_step "Step 2: Check for backups"

# Find backup dirs, sorted newest first
mapfile -t BACKUPS < <(find "$HOME" -maxdepth 1 -type d -name ".copilot-backup-*" 2>/dev/null | sort -r)

if [[ ${#BACKUPS[@]} -gt 0 ]]; then
    latest="${BACKUPS[0]}"
    latest_name="$(basename "$latest")"
    write_info "Found ${#BACKUPS[@]} backup(s). Most recent: $latest_name"
    read -r -p "  Restore from $latest_name? [y/N] " answer

    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        # Restore config files
        for f in "$latest"/*; do
            [[ -f "$f" ]] || continue
            fname="$(basename "$f")"
            dest="$COPILOT_HOME/$fname"
            if [[ ! -e "$dest" ]]; then
                cp "$f" "$dest"
                write_success "Restored $fname"
            else
                write_info "$fname already exists, skipping"
            fi
        done

        # Restore skills (real dirs from backup)
        if [[ -d "$latest/skills" ]]; then
            mkdir -p "$COPILOT_HOME/skills"
            for skill_dir in "$latest/skills"/*/; do
                [[ -d "$skill_dir" ]] || continue
                skill_name="$(basename "$skill_dir")"
                dest="$COPILOT_HOME/skills/$skill_name"
                if [[ ! -e "$dest" ]]; then
                    cp -r "$skill_dir" "$dest"
                    write_success "Restored skill: $skill_name"
                fi
            done
        fi
        write_success "Restore complete"
    else
        write_info "Skipping restore"
    fi
else
    write_info "No ~/.copilot-backup-* directories found"
fi

# Summary
echo ""
echo -e "${CYAN}═══════════════════════════════════${NC}"
echo -e "${GREEN}  ✨ Restore Complete${NC}"
echo -e "${CYAN}═══════════════════════════════════${NC}"
echo ""
if [[ ${#REMOVED[@]} -eq 0 ]]; then
    echo "  No symlinks were found pointing into this repo."
else
    echo "  Removed ${#REMOVED[@]} symlink(s):"
    for r in "${REMOVED[@]}"; do echo -e "    ${YELLOW}• $r${NC}"; done
fi
echo ""
