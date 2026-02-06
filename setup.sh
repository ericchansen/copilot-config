#!/usr/bin/env bash
#
# Setup script for Copilot CLI configuration, skills, and external repos.
#
# Backs up existing ~/.copilot/ config, symlinks config files, patches config.json
# with portable settings, symlinks local custom skills, clones/pulls external skill
# repos, and links their skills into ~/.copilot/skills/.
#
# Idempotent — safe to re-run at any time.
#
# Usage: ./setup.sh

set -e

# =============================================================================
# Configuration
# =============================================================================
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_COPILOT_DIR="$REPO_ROOT/.copilot"
REPO_SKILLS_DIR="$REPO_COPILOT_DIR/skills"
EXTERNAL_DIR="$REPO_ROOT/external"

COPILOT_HOME="$HOME/.copilot"
COPILOT_SKILLS_HOME="$COPILOT_HOME/skills"
CONFIG_JSON_PATH="$COPILOT_HOME/config.json"
PORTABLE_JSON_PATH="$REPO_COPILOT_DIR/config.portable.json"

# Config files to symlink (file symlinks)
CONFIG_FILE_LINKS=("copilot-instructions.md" "mcp-config.json" "mcp.json=mcp-config.json")

# Keys allowed to be patched from config.portable.json into config.json
PORTABLE_ALLOWED_KEYS=("banner" "model" "render_markdown" "theme" "experimental" "reasoning_effort")

# External skill repositories (parallel arrays)
EXTERNAL_NAMES=("anthropic" "github")
EXTERNAL_DISPLAY=("anthropics/skills" "github/awesome-copilot")
EXTERNAL_REPOS=("https://github.com/anthropics/skills.git" "https://github.com/github/awesome-copilot.git")
EXTERNAL_CLONE_DIRS=("anthropic-skills" "awesome-copilot")
EXTERNAL_SKILLS_SUBDIRS=("skills" "skills")

# =============================================================================
# Summary counters
# =============================================================================
SUMMARY_BACKED_UP=false
SUMMARY_BACKUP_DIR=""
SUMMARY_CONFIG_FILES_LINKED=()
SUMMARY_CONFIG_FILES_SKIPPED=()
SUMMARY_CONFIG_PATCHED=false
SUMMARY_TRUSTED_FOLDER_ADDED=false
SUMMARY_BEADS_REMOVED=false
SUMMARY_SKILLS_CREATED=()
SUMMARY_SKILLS_EXISTED=()
SUMMARY_SKILLS_SKIPPED=()
SUMMARY_SKILLS_FAILED=()
SUMMARY_EXTERNAL_CLONED=()
SUMMARY_EXTERNAL_PULLED=()
SUMMARY_EXTERNAL_FAILED=()
SUMMARY_CONFLICTS_RESOLVED=()

# =============================================================================
# Helper Functions
# =============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
GRAY='\033[0;90m'
NC='\033[0m'

write_success() { echo -e "  ${GREEN}✓${NC} $1"; }
write_info()    { echo -e "  ${CYAN}ℹ${NC} $1"; }
write_warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
write_err()     { echo -e "  ${RED}✗${NC} $1"; }
write_step()    { echo ""; echo -e "${CYAN}▸ $1${NC}"; }

ensure_directory() {
    mkdir -p "$1"
}

# Resolve a path to its absolute canonical form (without requiring it to exist)
resolve_path() {
    local dir base
    dir="$(dirname "$1")"
    base="$(basename "$1")"
    if [[ -d "$dir" ]]; then
        echo "$(cd "$dir" && pwd)/$base"
    else
        echo "$1"
    fi
}

# Check if a path is a symlink
is_symlink() {
    [[ -L "$1" ]]
}

# Get the resolved target of a symlink
get_link_target() {
    if [[ -L "$1" ]]; then
        readlink "$1"
    fi
}

# Create a file symlink. Returns: created | exists | skipped | failed
create_file_symlink() {
    local link_path="$1"
    local target_path="$2"
    local display_name="$3"

    if [[ -e "$link_path" || -L "$link_path" ]]; then
        if is_symlink "$link_path"; then
            local existing resolved_target resolved_existing
            existing="$(get_link_target "$link_path")"
            resolved_target="$(resolve_path "$target_path")"
            resolved_existing="$(resolve_path "$existing")"
            if [[ "$resolved_existing" == "$resolved_target" ]]; then
                echo "exists"
                return
            fi
            # Wrong target — remove and re-create
            rm -f "$link_path"
        else
            # Real file exists — ask user
            write_warn "$display_name already exists as a real file at $link_path"
            read -rp "    Replace with symlink? [y/N] " answer
            if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
                echo "skipped"
                return
            fi
            rm -f "$link_path"
        fi
    fi

    if ln -s "$target_path" "$link_path" 2>/dev/null; then
        echo "created"
    else
        echo "failed"
    fi
}

# Create a directory symlink. Returns: created | exists | skipped | failed
create_dir_symlink() {
    local link_path="$1"
    local target_path="$2"
    local display_name="$3"
    local ask_before_replace="${4:-false}"

    if [[ -e "$link_path" || -L "$link_path" ]]; then
        if is_symlink "$link_path"; then
            local existing resolved_target resolved_existing
            existing="$(get_link_target "$link_path")"
            resolved_target="$(resolve_path "$target_path")"
            resolved_existing="$(resolve_path "$existing")"
            if [[ "$resolved_existing" == "$resolved_target" ]]; then
                echo "exists"
                return
            fi
            # Wrong target — remove and re-create
            rm -f "$link_path"
        else
            if [[ "$ask_before_replace" == "true" ]]; then
                write_warn "$display_name already exists as a real directory at $link_path"
                read -rp "    Replace with symlink? [y/N] " answer
                if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
                    echo "skipped"
                    return
                fi
            fi
            rm -rf "$link_path"
        fi
    fi

    if ln -s "$target_path" "$link_path" 2>/dev/null; then
        echo "created"
    else
        echo "failed"
    fi
}

# Clone or pull a git repo. Returns: cloned | pulled | clone-failed | pull-failed
clone_or_pull_repo() {
    local repo_url="$1"
    local target_path="$2"
    local display_name="$3"

    if [[ -d "$target_path/.git" ]]; then
        pushd "$target_path" > /dev/null
        if git pull --quiet 2>/dev/null; then
            popd > /dev/null
            echo "pulled"
        else
            popd > /dev/null
            write_warn "$display_name — failed to pull (may be offline)"
            echo "pull-failed"
        fi
    else
        local parent_dir
        parent_dir="$(dirname "$target_path")"
        ensure_directory "$parent_dir"
        if git clone --quiet "$repo_url" "$target_path" 2>/dev/null; then
            echo "cloned"
        else
            echo ""
            write_err "Failed to clone $display_name"
            echo -e "    ${YELLOW}You can manually clone:${NC}"
            echo -e "      ${CYAN}git clone $repo_url $target_path${NC}"
            echo ""
            echo "clone-failed"
        fi
    fi
}

# Return skill folder names from a directory (folders containing SKILL.md)
get_skill_folders() {
    local base_path="$1"
    if [[ -d "$base_path" ]]; then
        for skill_dir in "$base_path"/*/; do
            [[ -d "$skill_dir" ]] || continue
            if [[ -f "${skill_dir}SKILL.md" ]]; then
                basename "$skill_dir"
            fi
        done
    fi
}

# =============================================================================
# JSON helpers — prefer jq, fall back to python3
# =============================================================================
JSON_TOOL=""

detect_json_tool() {
    if command -v jq &>/dev/null; then
        JSON_TOOL="jq"
    elif command -v python3 &>/dev/null; then
        JSON_TOOL="python3"
    elif command -v python &>/dev/null; then
        JSON_TOOL="python"
    else
        write_err "Neither jq nor python3 found — cannot patch config.json"
        write_warn "Install jq: https://jqlang.github.io/jq/download/"
        JSON_TOOL=""
    fi
}

# Read a JSON file, merge allowed keys from portable, write back.
# Usage: json_patch_config <config_path> <portable_path> <allowed_keys...>
json_patch_config() {
    local config_path="$1"
    local portable_path="$2"
    shift 2
    local allowed_keys=("$@")

    if [[ "$JSON_TOOL" == "jq" ]]; then
        # Build a jq filter that picks only allowed keys from portable
        local select_filter
        select_filter=$(printf '"%s",' "${allowed_keys[@]}")
        select_filter="[${select_filter%,}]"

        local portable_subset
        portable_subset=$(jq --argjson keys "$select_filter" 'with_entries(select(.key as $k | $keys | index($k)))' "$portable_path")

        # Merge: config * portable_subset (portable wins for allowed keys)
        jq --argjson patch "$portable_subset" '. * $patch' "$config_path" > "${config_path}.tmp"
        mv "${config_path}.tmp" "$config_path"
    else
        # python3 / python fallback
        local keys_json
        keys_json=$(printf '"%s",' "${allowed_keys[@]}")
        keys_json="[${keys_json%,}]"

        $JSON_TOOL -c "
import json, sys
config_path = sys.argv[1]
portable_path = sys.argv[2]
allowed = json.loads(sys.argv[3])

with open(config_path, 'r') as f:
    config = json.load(f)
with open(portable_path, 'r') as f:
    portable = json.load(f)

for key in allowed:
    if key in portable:
        config[key] = portable[key]

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')
" "$config_path" "$portable_path" "$keys_json"
    fi
}

# Add a value to a JSON array field if not already present.
# Usage: json_add_to_array <file> <field> <value>
json_add_to_array() {
    local file="$1"
    local field="$2"
    local value="$3"

    if [[ "$JSON_TOOL" == "jq" ]]; then
        jq --arg f "$field" --arg v "$value" '
            if (.[$f] // [] | map(. == $v) | any) then .
            else .[$f] = ((.[$f] // []) + [$v])
            end
        ' "$file" > "${file}.tmp"
        mv "${file}.tmp" "$file"
    else
        $JSON_TOOL -c "
import json, sys
file_path = sys.argv[1]
field = sys.argv[2]
value = sys.argv[3]

with open(file_path, 'r') as f:
    data = json.load(f)

arr = data.get(field, [])
if value not in arr:
    arr.append(value)
    data[field] = arr
    with open(file_path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
" "$file" "$field" "$value"
    fi
}

# Check if a value is in a JSON array field.
# Usage: json_array_contains <file> <field> <value>  — returns 0 if found
json_array_contains() {
    local file="$1"
    local field="$2"
    local value="$3"

    if [[ "$JSON_TOOL" == "jq" ]]; then
        jq -e --arg f "$field" --arg v "$value" '(.[$f] // []) | map(. == $v) | any' "$file" >/dev/null 2>&1
    else
        $JSON_TOOL -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
arr = data.get(sys.argv[2], [])
sys.exit(0 if sys.argv[3] in arr else 1)
" "$file" "$field" "$value"
    fi
}

# Remove beads-marketplace from config.json marketplaces.
# Usage: json_remove_beads_marketplace <file>  — returns 0 if removed
json_remove_beads_marketplace() {
    local file="$1"

    if [[ "$JSON_TOOL" == "jq" ]]; then
        # Check if marketplaces key exists
        if ! jq -e '.marketplaces' "$file" >/dev/null 2>&1; then
            return 1
        fi

        # Handle object with "beads-marketplace" key
        if jq -e '.marketplaces | type == "object" and has("beads-marketplace")' "$file" >/dev/null 2>&1; then
            jq 'del(.marketplaces["beads-marketplace"])' "$file" > "${file}.tmp"
            mv "${file}.tmp" "$file"
            return 0
        fi

        # Handle array of objects with key/name/id == "beads-marketplace"
        if jq -e '.marketplaces | type == "array"' "$file" >/dev/null 2>&1; then
            local before_count after_count
            before_count=$(jq '.marketplaces | length' "$file")
            jq '.marketplaces = [.marketplaces[] | select((.key // .name // .id) != "beads-marketplace")]' "$file" > "${file}.tmp"
            after_count=$(jq '.marketplaces | length' "${file}.tmp")
            if [[ "$before_count" != "$after_count" ]]; then
                mv "${file}.tmp" "$file"
                return 0
            fi
            rm -f "${file}.tmp"
        fi

        return 1
    else
        $JSON_TOOL -c "
import json, sys

file_path = sys.argv[1]
with open(file_path, 'r') as f:
    data = json.load(f)

mp = data.get('marketplaces')
if mp is None:
    sys.exit(1)

removed = False

if isinstance(mp, dict) and 'beads-marketplace' in mp:
    del mp['beads-marketplace']
    data['marketplaces'] = mp
    removed = True
elif isinstance(mp, list):
    filtered = [x for x in mp if not any(
        x.get(k) == 'beads-marketplace' for k in ('key', 'name', 'id') if k in x
    )]
    if len(filtered) != len(mp):
        data['marketplaces'] = filtered
        removed = True

if removed:
    with open(file_path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    sys.exit(0)
else:
    sys.exit(1)
" "$file"
    fi
}

# =============================================================================
# Main Script
# =============================================================================

echo ""
echo -e "${CYAN}📦 Copilot Config & Skills Setup${NC}"
echo -e "${CYAN}=================================${NC}"
echo ""

detect_json_tool

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Backup ~/.copilot/
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 1: Backup existing ~/.copilot/"

if [[ -d "$COPILOT_HOME" ]]; then
    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    BACKUP_DIR="$HOME/.copilot-backup-$TIMESTAMP"
    ensure_directory "$BACKUP_DIR"

    # Back up config files (not sessions/logs/caches)
    for f in config.json copilot-instructions.md mcp.json; do
        src="$COPILOT_HOME/$f"
        if [[ -f "$src" ]]; then
            cp "$src" "$BACKUP_DIR/$f"
        fi
    done

    # Back up skills directory
    if [[ -d "$COPILOT_SKILLS_HOME" ]]; then
        skills_backup="$BACKUP_DIR/skills"
        ensure_directory "$skills_backup"
        for entry in "$COPILOT_SKILLS_HOME"/*/; do
            [[ -d "$entry" ]] || continue
            entry_name="$(basename "$entry")"
            if is_symlink "${entry%/}"; then
                target="$(get_link_target "${entry%/}")"
                echo "$entry_name -> $target" >> "$skills_backup/_symlinks.txt"
            else
                cp -r "$entry" "$skills_backup/$entry_name"
            fi
        done
    fi

    write_success "Backed up to $BACKUP_DIR"
    SUMMARY_BACKED_UP=true
    SUMMARY_BACKUP_DIR="$BACKUP_DIR"
else
    write_info "No existing ~/.copilot/ to back up"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Ensure directories exist
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 2: Ensure directories"

ensure_directory "$COPILOT_HOME"
ensure_directory "$COPILOT_SKILLS_HOME"
write_success "~/.copilot/ and ~/.copilot/skills/ exist"

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Symlink config files
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 3: Symlink config files"

for cfg in "${CONFIG_FILE_LINKS[@]}"; do
    # Support "linkname=sourcefile" syntax for aliased symlinks
    if [[ "$cfg" == *"="* ]]; then
        link_name="${cfg%%=*}"
        source_name="${cfg#*=}"
    else
        link_name="$cfg"
        source_name="$cfg"
    fi

    target_path="$REPO_COPILOT_DIR/$source_name"
    link_path="$COPILOT_HOME/$link_name"

    if [[ ! -f "$target_path" ]]; then
        write_warn "$link_name — source not found in repo, skipping"
        continue
    fi

    display_name="$link_name"
    [[ "$link_name" != "$source_name" ]] && display_name="$link_name → $source_name"

    result=$(create_file_symlink "$link_path" "$target_path" "$display_name")

    case "$result" in
        created)
            write_success "$display_name → linked"
            SUMMARY_CONFIG_FILES_LINKED+=("$link_name")
            ;;
        exists)
            write_info "$display_name — already linked correctly"
            ;;
        skipped)
            write_warn "$display_name — skipped (user declined)"
            SUMMARY_CONFIG_FILES_SKIPPED+=("$link_name")
            ;;
        failed)
            write_err "$display_name — failed to create symlink"
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Patch config.json with portable settings
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 4: Patch config.json"

# Create config.json if it doesn't exist
if [[ ! -f "$CONFIG_JSON_PATH" ]]; then
    echo '{}' > "$CONFIG_JSON_PATH"
fi

if [[ -f "$PORTABLE_JSON_PATH" ]]; then
    if [[ -n "$JSON_TOOL" ]]; then
        json_patch_config "$CONFIG_JSON_PATH" "$PORTABLE_JSON_PATH" "${PORTABLE_ALLOWED_KEYS[@]}"
        write_success "Patched config.json with portable settings"
        SUMMARY_CONFIG_PATCHED=true
    else
        write_warn "No JSON tool available — skipping config patch"
    fi
else
    write_warn "config.portable.json not found in repo — skipping patch"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Add repo path to trusted_folders
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 5: Trusted folders"

RESOLVED_REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

if [[ -n "$JSON_TOOL" ]]; then
    if json_array_contains "$CONFIG_JSON_PATH" "trusted_folders" "$RESOLVED_REPO_ROOT"; then
        write_info "Repo already in trusted_folders"
    else
        json_add_to_array "$CONFIG_JSON_PATH" "trusted_folders" "$RESOLVED_REPO_ROOT"
        write_success "Added $RESOLVED_REPO_ROOT to trusted_folders"
        SUMMARY_TRUSTED_FOLDER_ADDED=true
    fi
else
    write_warn "No JSON tool available — skipping trusted_folders"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: Remove beads marketplace
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 6: Remove beads marketplace"

if [[ -n "$JSON_TOOL" ]]; then
    if json_remove_beads_marketplace "$CONFIG_JSON_PATH"; then
        write_success "Removed beads-marketplace entry"
        SUMMARY_BEADS_REMOVED=true
    else
        write_info "No beads-marketplace found"
    fi
else
    write_warn "No JSON tool available — skipping beads removal"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: Symlink local custom skills
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 7: Symlink local custom skills"

LOCAL_SKILLS=()
while IFS= read -r skill; do
    [[ -n "$skill" ]] && LOCAL_SKILLS+=("$skill")
done < <(get_skill_folders "$REPO_SKILLS_DIR")

if [[ ${#LOCAL_SKILLS[@]} -eq 0 ]]; then
    write_info "No local skills found in $REPO_SKILLS_DIR"
else
    for skill in "${LOCAL_SKILLS[@]}"; do
        link_path="$COPILOT_SKILLS_HOME/$skill"
        skill_path="$REPO_SKILLS_DIR/$skill"
        result=$(create_dir_symlink "$link_path" "$skill_path" "$skill" "true")

        case "$result" in
            created)
                write_success "$skill"
                SUMMARY_SKILLS_CREATED+=("$skill")
                ;;
            exists)
                write_info "$skill — already linked"
                SUMMARY_SKILLS_EXISTED+=("$skill")
                ;;
            skipped)
                write_warn "$skill — skipped (real dir, user declined)"
                SUMMARY_SKILLS_SKIPPED+=("$skill")
                ;;
            failed)
                write_err "$skill — symlink failed"
                SUMMARY_SKILLS_FAILED+=("$skill")
                ;;
        esac
    done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 8: Clone/pull external skill repos and symlink
# ─────────────────────────────────────────────────────────────────────────────
write_step "Step 8: External skill repositories"

# Track all skills for conflict detection: associative arrays
# ALL_SKILL_SOURCES[skill_name] = "source1 source2 ..."
# SKILL_PATH[source:skill_name] = full path
declare -A ALL_SKILL_SOURCES
declare -A SKILL_PATH

# Register local skills first (local wins by default)
for skill in "${LOCAL_SKILLS[@]}"; do
    ALL_SKILL_SOURCES[$skill]="local"
    SKILL_PATH["local:$skill"]="$REPO_SKILLS_DIR/$skill"
done

for i in "${!EXTERNAL_NAMES[@]}"; do
    ext_name="${EXTERNAL_NAMES[$i]}"
    ext_display="${EXTERNAL_DISPLAY[$i]}"
    ext_repo="${EXTERNAL_REPOS[$i]}"
    clone_path="$EXTERNAL_DIR/${EXTERNAL_CLONE_DIRS[$i]}"
    skills_path="$clone_path/${EXTERNAL_SKILLS_SUBDIRS[$i]}"

    clone_result=$(clone_or_pull_repo "$ext_repo" "$clone_path" "$ext_display")

    case "$clone_result" in
        cloned)
            write_success "$ext_display — cloned"
            SUMMARY_EXTERNAL_CLONED+=("$ext_display")
            ;;
        pulled)
            write_success "$ext_display — updated"
            SUMMARY_EXTERNAL_PULLED+=("$ext_display")
            ;;
        *failed*)
            write_err "$ext_display — $clone_result"
            SUMMARY_EXTERNAL_FAILED+=("$ext_display")
            continue
            ;;
    esac

    ext_skills=()
    while IFS= read -r skill; do
        [[ -n "$skill" ]] && ext_skills+=("$skill")
    done < <(get_skill_folders "$skills_path")

    write_info "$ext_display: ${#ext_skills[@]} skills found"

    for skill in "${ext_skills[@]}"; do
        if [[ -z "${ALL_SKILL_SOURCES[$skill]+x}" ]]; then
            ALL_SKILL_SOURCES[$skill]="$ext_name"
        else
            ALL_SKILL_SOURCES[$skill]="${ALL_SKILL_SOURCES[$skill]} $ext_name"
        fi
        SKILL_PATH["$ext_name:$skill"]="$skills_path/$skill"
    done
done

# Detect conflicts and resolve — local wins by default
echo ""
declare -A EXTERNAL_TO_LINK  # skill_name -> source to link

for skill_name in $(echo "${!ALL_SKILL_SOURCES[@]}" | tr ' ' '\n' | sort -u); do
    sources_str="${ALL_SKILL_SOURCES[$skill_name]}"
    read -ra sources_arr <<< "$sources_str"

    # Separate local and external sources
    local_source=""
    external_sources=()
    for src in "${sources_arr[@]}"; do
        if [[ "$src" == "local" ]]; then
            local_source="local"
        else
            external_sources+=("$src")
        fi
    done

    if [[ -n "$local_source" && ${#external_sources[@]} -gt 0 ]]; then
        # Conflict: local wins
        ext_names=""
        for es in "${external_sources[@]}"; do
            # Find display name for this external source
            for idx in "${!EXTERNAL_NAMES[@]}"; do
                if [[ "${EXTERNAL_NAMES[$idx]}" == "$es" ]]; then
                    [[ -n "$ext_names" ]] && ext_names="$ext_names, "
                    ext_names="$ext_names${EXTERNAL_DISPLAY[$idx]}"
                fi
            done
        done
        write_warn "$skill_name — conflict with $ext_names (local wins)"
        SUMMARY_CONFLICTS_RESOLVED+=("$skill_name (local wins over $ext_names)")
        continue
    fi

    if [[ ${#external_sources[@]} -gt 1 ]]; then
        # Conflict between external sources — pick first
        winner="${external_sources[0]}"
        winner_display=""
        other_names=""
        for idx in "${!EXTERNAL_NAMES[@]}"; do
            if [[ "${EXTERNAL_NAMES[$idx]}" == "$winner" ]]; then
                winner_display="${EXTERNAL_DISPLAY[$idx]}"
            fi
        done
        for es in "${external_sources[@]:1}"; do
            for idx in "${!EXTERNAL_NAMES[@]}"; do
                if [[ "${EXTERNAL_NAMES[$idx]}" == "$es" ]]; then
                    [[ -n "$other_names" ]] && other_names="$other_names, "
                    other_names="$other_names${EXTERNAL_DISPLAY[$idx]}"
                fi
            done
        done
        write_warn "$skill_name — conflict between externals, using $winner_display"
        EXTERNAL_TO_LINK[$skill_name]="$winner"
        SUMMARY_CONFLICTS_RESOLVED+=("$skill_name ($winner_display wins over $other_names)")
        continue
    fi

    if [[ ${#external_sources[@]} -eq 1 && -z "$local_source" ]]; then
        EXTERNAL_TO_LINK[$skill_name]="${external_sources[0]}"
    fi
done

# Link external skills
for skill_name in $(echo "${!EXTERNAL_TO_LINK[@]}" | tr ' ' '\n' | sort); do
    source="${EXTERNAL_TO_LINK[$skill_name]}"
    skill_full_path="${SKILL_PATH[$source:$skill_name]}"

    # Find display name
    source_display=""
    for idx in "${!EXTERNAL_NAMES[@]}"; do
        if [[ "${EXTERNAL_NAMES[$idx]}" == "$source" ]]; then
            source_display="${EXTERNAL_DISPLAY[$idx]}"
        fi
    done

    link_path="$COPILOT_SKILLS_HOME/$skill_name"
    result=$(create_dir_symlink "$link_path" "$skill_full_path" "$skill_name ($source_display)" "true")

    case "$result" in
        created)
            write_success "$skill_name ($source_display)"
            SUMMARY_SKILLS_CREATED+=("$skill_name")
            ;;
        exists)
            write_info "$skill_name — already linked"
            SUMMARY_SKILLS_EXISTED+=("$skill_name")
            ;;
        skipped)
            write_warn "$skill_name — skipped"
            SUMMARY_SKILLS_SKIPPED+=("$skill_name")
            ;;
        failed)
            write_err "$skill_name — symlink failed"
            SUMMARY_SKILLS_FAILED+=("$skill_name")
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Step 9: Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}═══════════════════════════════════${NC}"
echo -e "${GREEN}  ✨ Setup Complete${NC}"
echo -e "${CYAN}═══════════════════════════════════${NC}"
echo ""

if $SUMMARY_BACKED_UP; then
    echo -e "  Backup:           ~/.copilot-backup-$TIMESTAMP/"
fi

linked_count=${#SUMMARY_CONFIG_FILES_LINKED[@]}
skipped_cfg=${#SUMMARY_CONFIG_FILES_SKIPPED[@]}
if [[ $linked_count -gt 0 || $skipped_cfg -gt 0 ]]; then
    echo -e "  Config symlinks:  $linked_count linked, $skipped_cfg skipped"
fi

if $SUMMARY_CONFIG_PATCHED; then
    allowed_keys_str=$(IFS=', '; echo "${PORTABLE_ALLOWED_KEYS[*]}")
    echo -e "  Config patched:   $allowed_keys_str"
fi

if $SUMMARY_TRUSTED_FOLDER_ADDED; then
    echo -e "  Trusted folder:   $RESOLVED_REPO_ROOT (added)"
fi

if $SUMMARY_BEADS_REMOVED; then
    echo -e "  Marketplace:      beads-marketplace removed"
fi

created_count=${#SUMMARY_SKILLS_CREATED[@]}
existed_count=${#SUMMARY_SKILLS_EXISTED[@]}
skipped_count=${#SUMMARY_SKILLS_SKIPPED[@]}
failed_count=${#SUMMARY_SKILLS_FAILED[@]}

echo ""
echo -e "  ${CYAN}Skills:${NC}"
if [[ $created_count -gt 0 ]]; then echo -e "    ${GREEN}Created:        $created_count${NC}"; fi
if [[ $existed_count -gt 0 ]]; then echo -e "    ${CYAN}Already linked: $existed_count${NC}"; fi
if [[ $skipped_count -gt 0 ]]; then echo -e "    ${YELLOW}Skipped:        $skipped_count${NC}"; fi
if [[ $failed_count -gt 0 ]];  then echo -e "    ${RED}Failed:         $failed_count${NC}"; fi
if [[ $created_count -eq 0 && $existed_count -eq 0 && $skipped_count -eq 0 && $failed_count -eq 0 ]]; then
    echo -e "    ${GRAY}(none)${NC}"
fi

ext_cloned=${#SUMMARY_EXTERNAL_CLONED[@]}
ext_pulled=${#SUMMARY_EXTERNAL_PULLED[@]}
ext_failed=${#SUMMARY_EXTERNAL_FAILED[@]}
if [[ $ext_cloned -gt 0 || $ext_pulled -gt 0 || $ext_failed -gt 0 ]]; then
    echo ""
    echo -e "  ${CYAN}External repos:${NC}"
    if [[ $ext_cloned -gt 0 ]]; then echo -e "    ${GREEN}Cloned:         $ext_cloned${NC}"; fi
    if [[ $ext_pulled -gt 0 ]]; then echo -e "    ${CYAN}Updated:        $ext_pulled${NC}"; fi
    if [[ $ext_failed -gt 0 ]]; then echo -e "    ${RED}Failed:         $ext_failed${NC}"; fi
fi

if [[ ${#SUMMARY_CONFLICTS_RESOLVED[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${YELLOW}Conflicts resolved:${NC}"
    for c in "${SUMMARY_CONFLICTS_RESOLVED[@]}"; do
        echo -e "    ${YELLOW}• $c${NC}"
    done
fi

echo ""
