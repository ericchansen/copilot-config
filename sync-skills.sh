#!/usr/bin/env bash
# Detect untracked skills in ~/.copilot/skills/ and adopt them into the repo.
#
# Scans ~/.copilot/skills/ for real directories (not symlinks) that
# don't exist in the repo's .copilot/skills/. Offers to move each one into
# the repo and replace it with a symlink.
#
# Usage:
#   ./sync-skills.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_TARGET="$HOME/.copilot/skills"
REPO_SKILLS="$SCRIPT_DIR/.copilot/skills"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

write_success() { echo -e "  ${GREEN}✓ $1${NC}"; }
write_info()    { echo -e "  ${CYAN}$1${NC}"; }
write_warn()    { echo -e "  ${YELLOW}⚠ $1${NC}"; }

echo ""
echo -e "${CYAN}🔍 Scanning for untracked skills...${NC}"
echo ""

untracked=()

if [[ -d "$SKILLS_TARGET" ]]; then
    for dir in "$SKILLS_TARGET"/*/; do
        [[ -d "$dir" ]] || continue
        dir="${dir%/}"
        name=$(basename "$dir")

        # Skip symlinks
        [[ -L "$dir" ]] && continue

        # Check for SKILL.md
        if [[ -f "$dir/SKILL.md" ]]; then
            # Check if already in repo
            if [[ ! -d "$REPO_SKILLS/$name" ]]; then
                untracked+=("$dir")
            fi
        fi
    done
fi

if [[ ${#untracked[@]} -eq 0 ]]; then
    write_info "No untracked skills found. Everything is in sync!"
    echo ""
    exit 0
fi

echo -e "  ${WHITE}Found ${#untracked[@]} untracked skill(s):${NC}"
echo ""

adopted=0
skipped=0

for skill_path in "${untracked[@]}"; do
    name=$(basename "$skill_path")
    skill_md="$skill_path/SKILL.md"
    desc=""

    # Extract description from frontmatter
    if [[ -f "$skill_md" ]]; then
        desc=$(grep -m1 'description:' "$skill_md" 2>/dev/null | sed "s/^.*description:[[:space:]]*['\"]*//" | sed "s/['\"].*$//" | cut -c1-80)
    fi

    echo -e "  ${WHITE}📦 $name${NC}"
    [[ -n "$desc" ]] && echo -e "     ${GRAY}$desc${NC}"

    read -rp "     Adopt into repo? [Y/n] " answer
    if [[ "${answer,,}" == "n" ]]; then
        ((skipped++))
        echo ""
        continue
    fi

    dest_dir="$REPO_SKILLS/$name"

    # Move the real directory into the repo
    mv "$skill_path" "$dest_dir"

    # Create symlink back to ~/.copilot/skills/
    if ln -s "$dest_dir" "$skill_path" 2>/dev/null; then
        write_success "$name → adopted and linked"
        ((adopted++))
    else
        write_warn "$name — moved but symlink failed (run setup.sh to fix)"
        ((adopted++))
    fi
    echo ""
done

echo -e "${CYAN}═══════════════════════════════${NC}"
echo -e "  ${GREEN}Adopted: $adopted${NC}"
[[ $skipped -gt 0 ]] && echo -e "  ${YELLOW}Skipped: $skipped${NC}"
echo ""

if [[ $adopted -gt 0 ]]; then
    echo -e "  ${WHITE}Next steps:${NC}"
    echo -e "    ${GRAY}cd $(basename "$SCRIPT_DIR")${NC}"
    echo -e "    ${GRAY}git add -A && git commit -m 'feat: Adopt new skills'${NC}"
    echo -e "    ${GRAY}git push${NC}"
    echo ""
fi
