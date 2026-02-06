#!/usr/bin/env bash
#
# Detect untracked skills in ~/.copilot/skills/ and adopt them into the repo.
#

set -e

SKILLS_TARGET="$HOME/.copilot/skills"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SKILLS="$SCRIPT_DIR/.copilot/skills"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
GRAY='\033[0;90m'
NC='\033[0m'

success() { echo -e "  ${GREEN}✓${NC} $1"; }
info()    { echo -e "  ${CYAN}$1${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }

echo ""
echo -e "${CYAN}🔍 Scanning for untracked skills...${NC}"
echo ""

untracked=()

for skill_dir in "$SKILLS_TARGET"/*/; do
    [[ ! -d "$skill_dir" ]] && continue
    name="$(basename "$skill_dir")"

    # Skip symlinks
    [[ -L "$skill_dir" ]] && continue
    # On Linux, junctions don't exist — but check anyway
    [[ -L "${skill_dir%/}" ]] && continue

    # Must have SKILL.md
    [[ ! -f "$skill_dir/SKILL.md" ]] && continue

    # Skip if already in repo
    [[ -d "$REPO_SKILLS/$name" ]] && continue

    untracked+=("$name")
done

if [[ ${#untracked[@]} -eq 0 ]]; then
    info "No untracked skills found. Everything is in sync!"
    echo ""
    exit 0
fi

echo "  Found ${#untracked[@]} untracked skill(s):"
echo ""

adopted=0
skipped=0

for name in "${untracked[@]}"; do
    skill_dir="$SKILLS_TARGET/$name"
    desc=""
    if [[ -f "$skill_dir/SKILL.md" ]]; then
        desc=$(grep -m1 'description:' "$skill_dir/SKILL.md" | sed "s/^.*description:\s*['\"]*//" | sed "s/['\"]$//" | cut -c1-80)
    fi

    echo -e "  📦 ${NC}$name${NC}"
    [[ -n "$desc" ]] && echo -e "     ${GRAY}$desc${NC}"

    read -rp "     Adopt into repo? [Y/n]: " answer
    if [[ "$answer" == "n" || "$answer" == "N" ]]; then
        ((skipped++))
        echo ""
        continue
    fi

    dest_dir="$REPO_SKILLS/$name"

    # Move into repo
    mv "$skill_dir" "$dest_dir"

    # Create symlink back
    ln -s "$dest_dir" "$skill_dir"
    if [[ $? -eq 0 ]]; then
        success "$name → adopted and linked"
        ((adopted++))
    else
        warn "$name — moved but symlink failed (run setup.sh to fix)"
        ((adopted++))
    fi
    echo ""
done

echo -e "${CYAN}═══════════════════════════════${NC}"
echo -e "  ${GREEN}Adopted: $adopted${NC}"
[[ $skipped -gt 0 ]] && echo -e "  ${YELLOW}Skipped: $skipped${NC}"
echo ""

if [[ $adopted -gt 0 ]]; then
    echo "  Next steps:"
    echo -e "    ${GRAY}cd $(basename "$SCRIPT_DIR")${NC}"
    echo -e "    ${GRAY}git add -A && git commit -m 'feat: Adopt new skills'${NC}"
    echo -e "    ${GRAY}git push${NC}"
    echo ""
fi
