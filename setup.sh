#!/usr/bin/env bash
#
# Setup script to install Copilot CLI skills from multiple sources.
# Clones external skill repositories and creates symlinks to ~/.copilot/skills.
# Handles conflicts interactively, letting users choose which source to use.
#

set -e

# =============================================================================
# Configuration
# =============================================================================
DEFAULT_REPOS_DIR="$HOME/repos"
SKILLS_TARGET_DIR="$HOME/.copilot/skills"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# External repositories to clone (defined as parallel arrays for bash 3 compat)
EXTERNAL_NAMES=("anthropic" "github")
EXTERNAL_DISPLAY=("anthropics/skills" "github/awesome-copilot")
EXTERNAL_REPOS=("https://github.com/anthropics/skills.git" "https://github.com/github/awesome-copilot.git")
EXTERNAL_CLONE_DIRS=("anthropic-skills" "awesome-copilot")
EXTERNAL_SKILLS_SUBDIRS=("skills" "skills")

# =============================================================================
# Helper Functions
# =============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

success() { echo -e "  ${GREEN}✓${NC} $1"; }
info() { echo -e "  ${CYAN}$1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
err() { echo -e "  ${RED}✗${NC} $1"; }

ensure_directory() {
    mkdir -p "$1"
}

clone_or_pull_repo() {
    local repo_url="$1"
    local target_path="$2"
    
    if [[ -d "$target_path/.git" ]]; then
        # Repo exists, pull latest
        pushd "$target_path" > /dev/null
        if ! git pull --quiet 2>/dev/null; then
            warn "Failed to pull updates (may be offline)"
        fi
        popd > /dev/null
    else
        # Clone fresh
        local parent_dir
        parent_dir="$(dirname "$target_path")"
        ensure_directory "$parent_dir"
        if ! git clone --quiet "$repo_url" "$target_path" 2>/dev/null; then
            echo "Failed to clone $repo_url" >&2
            return 1
        fi
    fi
}

get_skills() {
    local base_path="$1"
    
    if [[ -d "$base_path" ]]; then
        for skill_dir in "$base_path"/*/; do
            if [[ -f "${skill_dir}SKILL.md" ]]; then
                basename "$skill_dir"
            fi
        done
    fi
}

create_symlink() {
    local link_path="$1"
    local target_path="$2"
    
    if [[ -L "$link_path" ]]; then
        # Already a symlink - check if it points to the right place
        local existing_target
        existing_target="$(readlink "$link_path")"
        if [[ "$existing_target" == "$target_path" ]]; then
            echo "exists"
            return
        fi
        # Remove old symlink to replace it
        rm "$link_path"
    elif [[ -e "$link_path" ]]; then
        # It's a real file/directory, skip
        echo "skipped"
        return
    fi
    
    # Create symlink
    if ln -s "$target_path" "$link_path" 2>/dev/null; then
        echo "created"
    else
        echo "failed"
    fi
}

# =============================================================================
# Main Script
# =============================================================================

echo ""
echo -e "${CYAN}📦 Copilot Skills Setup${NC}"
echo -e "${CYAN}=======================${NC}"
echo ""

# Step 1: Ask where to clone external repositories
echo "External repositories will be cloned to your local machine."
echo -e "${GRAY}Default location: $DEFAULT_REPOS_DIR${NC}"
echo ""

read -rp "Clone repositories to [$DEFAULT_REPOS_DIR]: " repos_dir
if [[ -z "$repos_dir" ]]; then
    repos_dir="$DEFAULT_REPOS_DIR"
fi
# Expand ~ if used
repos_dir="${repos_dir/#\~/$HOME}"
# Get absolute path
repos_dir="$(cd "$(dirname "$repos_dir")" 2>/dev/null && pwd)/$(basename "$repos_dir")" || repos_dir="$DEFAULT_REPOS_DIR"

echo ""

# Build sources dynamically based on chosen directory
declare -A SOURCE_NAMES SOURCE_PATHS SOURCE_REPOS SOURCE_CLONE_TO
SOURCE_ORDER=("local")

SOURCE_NAMES[local]="Local skills"
SOURCE_PATHS[local]="$SCRIPT_DIR/skills"
SOURCE_REPOS[local]=""
SOURCE_CLONE_TO[local]=""

for i in "${!EXTERNAL_NAMES[@]}"; do
    name="${EXTERNAL_NAMES[$i]}"
    clone_path="$repos_dir/${EXTERNAL_CLONE_DIRS[$i]}"
    skills_path="$clone_path/${EXTERNAL_SKILLS_SUBDIRS[$i]}"
    
    SOURCE_ORDER+=("$name")
    SOURCE_NAMES[$name]="${EXTERNAL_DISPLAY[$i]}"
    SOURCE_PATHS[$name]="$skills_path"
    SOURCE_REPOS[$name]="${EXTERNAL_REPOS[$i]}"
    SOURCE_CLONE_TO[$name]="$clone_path"
done

# Step 2: Fetch all repositories
echo "Fetching repositories..."

declare -A ALL_SKILLS_SOURCES  # skill_name -> space-separated list of sources
declare -A SKILL_PATHS         # source:skill_name -> full path
declare -A SOURCE_STATS        # source -> count

for source in "${SOURCE_ORDER[@]}"; do
    repo="${SOURCE_REPOS[$source]}"
    clone_to="${SOURCE_CLONE_TO[$source]}"
    display_name="${SOURCE_NAMES[$source]}"
    skills_path="${SOURCE_PATHS[$source]}"
    
    if [[ -n "$repo" ]]; then
        if ! clone_or_pull_repo "$repo" "$clone_to"; then
            err "$display_name: Failed to clone"
            SOURCE_STATS[$source]=0
            continue
        fi
    fi
    
    skills=()
    while IFS= read -r skill; do
        [[ -n "$skill" ]] && skills+=("$skill")
    done < <(get_skills "$skills_path")
    
    SOURCE_STATS[$source]=${#skills[@]}
    
    for skill in "${skills[@]}"; do
        if [[ -z "${ALL_SKILLS_SOURCES[$skill]}" ]]; then
            ALL_SKILLS_SOURCES[$skill]="$source"
        else
            ALL_SKILLS_SOURCES[$skill]="${ALL_SKILLS_SOURCES[$skill]} $source"
        fi
        SKILL_PATHS["$source:$skill"]="$skills_path/$skill"
    done
    
    success "$display_name (${#skills[@]} skills)"
done

echo ""

# Step 2: Detect conflicts
declare -A CONFLICTS      # skill_name -> space-separated sources (only if >1)
declare -A SELECTED       # skill_name -> selected source

for skill in "${!ALL_SKILLS_SOURCES[@]}"; do
    sources_str="${ALL_SKILLS_SOURCES[$skill]}"
    read -ra sources_arr <<< "$sources_str"
    
    if [[ ${#sources_arr[@]} -gt 1 ]]; then
        CONFLICTS[$skill]="$sources_str"
    else
        # Auto-select non-conflicting skills
        SELECTED[$skill]="${sources_arr[0]}"
    fi
done

# Step 3: Resolve conflicts interactively
if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Conflicts detected (${#CONFLICTS[@]}):${NC}"
    echo ""
    
    for skill in $(echo "${!CONFLICTS[@]}" | tr ' ' '\n' | sort); do
        echo -e "   ${NC}$skill${NC}"
        sources_str="${CONFLICTS[$skill]}"
        read -ra sources_arr <<< "$sources_str"
        
        i=1
        for src in "${sources_arr[@]}"; do
            path="${SKILL_PATHS[$src:$skill]}"
            echo -e "     ${GRAY}[$i] $path${NC}"
            ((i++))
        done
        echo ""
        
        while true; do
            read -rp "   Select source for '$skill' [1-${#sources_arr[@]}]: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#sources_arr[@]} ]]; then
                SELECTED[$skill]="${sources_arr[$((choice-1))]}"
                break
            else
                warn "Please enter a number between 1 and ${#sources_arr[@]}"
            fi
        done
        echo ""
    done
fi

# Step 4: Show summary and confirm
echo ""
echo -e "${CYAN}📋 Skills to install (${#SELECTED[@]} total):${NC}"
echo ""

for source in "${SOURCE_ORDER[@]}"; do
    display_name="${SOURCE_NAMES[$source]}"
    skills_for_source=()
    
    for skill in $(echo "${!SELECTED[@]}" | tr ' ' '\n' | sort); do
        if [[ "${SELECTED[$skill]}" == "$source" ]]; then
            skills_for_source+=("$skill")
        fi
    done
    
    if [[ ${#skills_for_source[@]} -gt 0 ]]; then
        echo -e "  ${NC}$display_name (${#skills_for_source[@]}):${NC}"
        for skill in "${skills_for_source[@]}"; do
            conflict_marker=""
            [[ -n "${CONFLICTS[$skill]}" ]] && conflict_marker=" ←"
            echo -e "    ${GRAY}[x] $skill$conflict_marker${NC}"
        done
        echo ""
    fi
done

read -rp "Proceed with installation? [Y/n]: " proceed
if [[ "$proceed" == "n" || "$proceed" == "N" ]]; then
    echo -e "${YELLOW}Installation cancelled.${NC}"
    exit 0
fi

# Step 5: Create target directory and symlinks
echo ""
echo "Installing skills to $SKILLS_TARGET_DIR ..."
echo ""

ensure_directory "$SKILLS_TARGET_DIR"

created=0
existed=0
skipped=0
failed=0

for skill in $(echo "${!SELECTED[@]}" | tr ' ' '\n' | sort); do
    source="${SELECTED[$skill]}"
    skill_path="${SKILL_PATHS[$source:$skill]}"
    link_path="$SKILLS_TARGET_DIR/$skill"
    
    result=$(create_symlink "$link_path" "$skill_path")
    
    case "$result" in
        created)
            success "$skill"
            ((created++))
            ;;
        exists)
            info "$skill (already linked)"
            ((existed++))
            ;;
        skipped)
            warn "$skill (skipped - real directory exists)"
            ((skipped++))
            ;;
        failed)
            err "$skill (failed to create symlink)"
            ((failed++))
            ;;
    esac
done

# Step 6: Summary
echo ""
echo -e "${GREEN}✨ Done!${NC}"
echo ""
echo "Summary:"
echo -e "  ${GREEN}Created: $created${NC}"
[[ $existed -gt 0 ]] && echo -e "  ${CYAN}Already linked: $existed${NC}"
[[ $skipped -gt 0 ]] && echo -e "  ${YELLOW}Skipped: $skipped${NC}"
[[ $failed -gt 0 ]] && echo -e "  ${RED}Failed: $failed${NC}"
echo ""
