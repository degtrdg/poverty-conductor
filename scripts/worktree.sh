#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# World cities for random branch names (conductor style)
CITIES=(
    "alexandria" "algiers" "apia" "auckland" "belgrade" "berlin" "bilbao" 
    "bismarck" "cahokia" "cancun" "chicago" "dalat" "dar" "delhi" "douala" 
    "guangzhou" "guatemala" "harare" "hartford" "indianapolis" "islamabad" 
    "los-angeles" "macau" "miami" "monaco" "nagoya" "palenque" "providence" 
    "quebec" "richmond" "sacramento" "salem" "singapore" "tel-aviv" "tokyo"
    "melbourne" "sydney" "cairo" "athens" "rome" "paris" "london" "madrid"
    "vienna" "prague" "budapest" "warsaw" "stockholm" "helsinki" "oslo"
    "copenhagen" "amsterdam" "brussels" "zurich" "geneva" "dublin" "edinburgh"
    "lisbon" "barcelona" "valencia" "florence" "venice" "naples" "palermo"
    "istanbul" "ankara" "tehran" "baghdad" "riyadh" "dubai" "muscat" "doha"
    "kuwait" "manama" "abu-dhabi" "casablanca" "tunis" "rabat" "algiers"
    "tripoli" "khartoum" "addis-ababa" "nairobi" "kampala" "dar-es-salaam"
    "lusaka" "harare" "gaborone" "windhoek" "cape-town" "johannesburg"
    "durban" "pretoria" "maputo" "antananarivo" "port-louis" "victoria"
)

# Configuration file for remembering settings
CONFIG_FILE=".worktree-config"

# Function to get a random city
get_random_city() {
    local city_count=${#CITIES[@]}
    local random_index=$((RANDOM % city_count))
    echo "${CITIES[$random_index]}"
}

# Function to get a unique branch name
get_unique_branch_name() {
    local attempt=0
    local max_attempts=20
    
    while [ $attempt -lt $max_attempts ]; do
        local city=$(get_random_city)
        local branch_name="conductor/$city"
        
        # Check if branch already exists
        if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
            echo "$branch_name"
            return 0
        fi
        
        attempt=$((attempt + 1))
    done
    
    # Fallback: add timestamp if we can't find a unique city
    local timestamp=$(date +%s)
    local city=$(get_random_city)
    echo "conductor/$city-$timestamp"
}

# Function to get the current branch
get_current_branch() {
    git branch --show-current
}

# Function to get the default branch (main or master)
get_default_branch() {
    if git show-ref --verify --quiet refs/heads/main; then
        echo "main"
    elif git show-ref --verify --quiet refs/heads/master; then
        echo "master"
    else
        echo "main"  # fallback
    fi
}

# Function to load last used settings
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# Function to save current settings
save_config() {
    local parent_branch="$1"
    cat > "$CONFIG_FILE" << EOF
LAST_PARENT_BRANCH="$parent_branch"
EOF
}

# Function to check if we're in a git repo
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not in a git repository${NC}"
        exit 1
    fi
}

# Main function
main() {
    echo -e "${BLUE}=== Git Worktree Manager ===${NC}"
    echo

    # Check if we're in a git repo
    check_git_repo

    # Load previous settings
    load_config

    # Generate unique branch name
    local workspace_name=$(get_unique_branch_name)

    # Get current branch and default branch
    local current_branch=$(get_current_branch)
    local default_branch=$(get_default_branch)
    
    # Determine parent branch (prioritize: last used -> current -> default)
    local suggested_parent="$default_branch"
    if [ -n "$LAST_PARENT_BRANCH" ]; then
        suggested_parent="$LAST_PARENT_BRANCH"
    elif [ -n "$current_branch" ] && [ "$current_branch" != "HEAD" ]; then
        suggested_parent="$current_branch"
    fi

    echo -e "${YELLOW}Auto-generated name:${NC} $workspace_name"
    echo

    # Prompt for parent branch with smart default
    echo -n -e "${YELLOW}Parent branch${NC} [$suggested_parent]: "
    read parent_branch
    if [ -z "$parent_branch" ]; then
        parent_branch="$suggested_parent"
    fi

    # Check if parent branch exists
    if ! git show-ref --verify --quiet refs/heads/"$parent_branch"; then
        echo -e "${RED}Error: Branch '$parent_branch' does not exist${NC}"
        exit 1
    fi

    # Create worktree directory if it doesn't exist
    mkdir -p .worktrees

    local workspace_path=".worktrees/$(echo $workspace_name | sed 's/\//-/g')"
    local full_workspace_path="$(pwd)/$workspace_path"

    echo
    echo -e "${BLUE}Creating worktree...${NC}"
    echo "  Name: $workspace_name"
    echo "  Parent: $parent_branch"
    echo "  Path: $workspace_path"

    # Create the worktree
    if ! git worktree add -b "$workspace_name" "$workspace_path" "$parent_branch"; then
        echo -e "${RED}Failed to create worktree${NC}"
        exit 1
    fi

    # Save settings for next time
    save_config "$parent_branch"

    # Set up environment variables for the setup script (conductor compatibility)
    export CONDUCTOR_WORKSPACE_NAME="$workspace_name"
    export CONDUCTOR_WORKSPACE_PATH="$full_workspace_path"
    # export CONDUCTOR_ROOT_PATH="/Users/danielgeorge/Documents/work/ml/small-stuff/speck/monorepo"
    export CONDUCTOR_ROOT_PATH="FILL_ME_IN"
    export CONDUCTOR_DEFAULT_BRANCH="$default_branch"

    echo
    echo -e "${BLUE}Running setup script...${NC}"

    # Look for setup script (prefer main repo version over worktree version)
    local setup_script=""
    if [ -f "scripts/conductor-setup.sh" ]; then
        setup_script="scripts/conductor-setup.sh"
    elif [ -f "$workspace_path/scripts/conductor-setup.sh" ]; then
        setup_script="$workspace_path/scripts/conductor-setup.sh"
    fi

    if [ -n "$setup_script" ]; then
        # Run the setup script with the environment variables set
        bash "$setup_script"
    else
        echo -e "${YELLOW}No setup script found (scripts/conductor-setup.sh)${NC}"
        echo "Copying files manually..."
        
        # Fallback: basic file copying
        cd "$workspace_path"
        
        # Copy environment files
        find "$CONDUCTOR_ROOT_PATH" -name ".env*" -type f -not -path "*/.worktrees/*" | while read -r source_file; do
            relative_path="${source_file#$CONDUCTOR_ROOT_PATH/}"
            target_file="$CONDUCTOR_WORKSPACE_PATH/$relative_path"
            target_dir=$(dirname "$target_file")
            mkdir -p "$target_dir"
            cp "$source_file" "$target_file"
            echo "✓ Copied $relative_path"
        done
        
        # Copy local Claude configuration files
        find "$CONDUCTOR_ROOT_PATH" -name "CLAUDE.local.md" -type f -not -path "*/.worktrees/*" | while read -r source_file; do
            relative_path="${source_file#$CONDUCTOR_ROOT_PATH/}"
            target_file="$CONDUCTOR_WORKSPACE_PATH/$relative_path"
            target_dir=$(dirname "$target_file")
            mkdir -p "$target_dir"
            cp "$source_file" "$target_file"
            echo "✓ Copied $relative_path"
        done
        
        # Install dependencies
        echo "Installing dependencies..."
        # examples:
        # bun install
        # bun --cwd apps/server db:generate 2>/dev/null || echo "Database generation skipped (not available)"
        
        cd - > /dev/null
    fi

    echo
    echo -e "${GREEN}=== Worktree ready! ===${NC}"
    echo -e "${YELLOW}Opening in Cursor...${NC}"
    
    # Open in Cursor
    cd "$workspace_path"
    if command -v cursor > /dev/null 2>&1; then
        cursor .
        echo "✓ Opened in Cursor"
    else
        echo -e "${YELLOW}Cursor not found, skipping...${NC}"
    fi
    cd - > /dev/null
    
    echo
    echo -e "${YELLOW}To switch to the worktree:${NC}"
    echo "  cd $workspace_path"
    echo
    echo -e "${YELLOW}To remove the worktree later:${NC}"
    echo "  git worktree remove $workspace_path"
}

# Run main function
main "$@"