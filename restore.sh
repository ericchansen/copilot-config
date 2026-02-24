#!/usr/bin/env bash
# Undo what setup.sh did: remove symlinks in ~/.copilot/ that point
# into this repo. Optionally restore from the most recent backup.
# Safe: only removes symlinks, never deletes real files/directories.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTERNAL_DIR="$REPO_ROOT/external"
COPILOT_HOME="$HOME/.copilot"

# Directories whose symlinks we own and may remove
OWNED_ROOTS=()
for p in \
    "$REPO_ROOT" \
    "$HOME/repos/skills" \
    "$HOME/repos/copilot-config" \
    "$HOME/repos/msx-mcp" \
    "$HOME/repos/SPT-IQ" \
    "$EXTERNAL_DIR"; do
    if [[ -d "$p" ]]; then
        OWNED_ROOTS+=("$(cd "$p" && pwd)")
    else
        OWNED_ROOTS+=("$p")
    fi
done

# =============================================================================
# Helpers
# =============================================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
WHITE='\033[1;37m'
NC='\033[0m'

write_success() { echo -e "  ${GREEN}✓ $1${NC}"; }
write_info()    { echo -e "  ${CYAN}ℹ $1${NC}"; }
write_warn()    { echo -e "  ${YELLOW}⚠ $1${NC}"; }
write_err()     { echo -e "  ${RED}✗ $1${NC}"; }
write_step()    { echo ""; echo -e "${CYAN}▸ $1${NC}"; }

resolve_path() {
    if command -v realpath &>/dev/null; then
        realpath "$1" 2>/dev/null || echo "$1"
    elif command -v python3 &>/dev/null; then
        python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1"
    elif [[ -d "$1" ]]; then
        (cd "$1" && pwd)
    elif [[ -f "$1" ]]; then
        echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    else
        echo "$1"
    fi
}

points_into_owned_root() {
    local target="$1"
    [[ -z "$target" ]] && return 1
    local resolved
    resolved=$(resolve_path "$target")
    for root in "${OWNED_ROOTS[@]}"; do
        if [[ "$resolved" == "$root"* ]]; then
            return 0
        fi
    done
    return 1
}

remove_owned_links() {
    # Scan a directory for symlinks pointing into owned roots and remove them.
    # Prints removed paths to stdout.
    local scan_dir="$1"
    for item in "$scan_dir"/*; do
        [[ -e "$item" ]] || [[ -L "$item" ]] || continue
        if [[ -L "$item" ]]; then
            local target
            target=$(readlink "$item" 2>/dev/null || true)
            if points_into_owned_root "$target"; then
                local rel_name="${item/$COPILOT_HOME/~\/.copilot}"
                write_warn "Removing: $rel_name → $target"
                rm -f "$item"
                echo "$rel_name"
            fi
        fi
    done
}

# =============================================================================
# Main
# =============================================================================

echo ""
echo -e "${CYAN}🔄 Copilot Config & Skills Restore${NC}"
echo -e "${CYAN}====================================${NC}"

removed=()

# Step 1: Find and remove symlinks in ~/.copilot/
write_step "Step 1: Scan ~/.copilot/ for symlinks pointing into this repo"

if [[ ! -d "$COPILOT_HOME" ]]; then
    write_info "~/.copilot/ does not exist — nothing to do"
else
    while IFS= read -r path; do
        removed+=("$path")
    done < <(remove_owned_links "$COPILOT_HOME")

    skills_dir="$COPILOT_HOME/skills"
    if [[ -d "$skills_dir" ]]; then
        while IFS= read -r path; do
            removed+=("$path")
        done < <(remove_owned_links "$skills_dir")

        # Remove skills dir if now empty
        if [[ -d "$skills_dir" ]] && [[ -z "$(ls -A "$skills_dir" 2>/dev/null)" ]]; then
            rmdir "$skills_dir"
            write_info "Removed empty ~/.copilot/skills/"
        fi
    fi
fi

# Step 2: Offer to restore from backup
write_step "Step 2: Check for backups"

backups=()
if [[ -d "$HOME" ]]; then
    while IFS= read -r bdir; do
        backups+=("$bdir")
    done < <(find "$HOME" -maxdepth 1 -type d -name '.copilot-backup-*' 2>/dev/null | sort -r)
fi

if [[ ${#backups[@]} -gt 0 ]]; then
    latest="${backups[0]}"
    latest_name=$(basename "$latest")
    write_info "Found ${#backups[@]} backup(s). Most recent: $latest_name"
    read -rp "  Restore from $latest_name? [y/N] " answer

    if [[ "${answer,,}" == "y" ]]; then
        # Restore config files
        for f in "$latest"/*; do
            [[ -f "$f" ]] || continue
            name=$(basename "$f")
            dest="$COPILOT_HOME/$name"
            if [[ ! -e "$dest" ]]; then
                cp "$f" "$dest"
                write_success "Restored $name"
            else
                write_info "$name already exists, skipping"
            fi
        done

        # Restore skills
        backup_skills="$latest/skills"
        if [[ -d "$backup_skills" ]]; then
            skills_dir="$COPILOT_HOME/skills"
            mkdir -p "$skills_dir"
            for sdir in "$backup_skills"/*/; do
                [[ -d "$sdir" ]] || continue
                sdir="${sdir%/}"
                name=$(basename "$sdir")
                dest="$skills_dir/$name"
                if [[ ! -e "$dest" ]]; then
                    cp -r "$sdir" "$dest"
                    write_success "Restored skill: $name"
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
echo -e "  ${GREEN}✨ Restore Complete${NC}"
echo -e "${CYAN}═══════════════════════════════════${NC}"
echo ""
if [[ ${#removed[@]} -eq 0 ]]; then
    echo -e "  ${WHITE}No symlinks were found pointing into this repo.${NC}"
else
    echo -e "  ${WHITE}Removed ${#removed[@]} symlink(s):${NC}"
    for r in "${removed[@]}"; do
        echo -e "    ${YELLOW}• $r${NC}"
    done
fi
echo ""
