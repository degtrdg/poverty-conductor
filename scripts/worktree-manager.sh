#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to check if we're in a git repo
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not in a git repository${NC}"
        exit 1
    fi
}

# Function to get worktrees
get_worktrees() {
    if [ ! -d ".worktrees" ]; then
        echo ""
        return
    fi
    
    git worktree list --porcelain | grep -E "^worktree|^branch" | \
    awk '
        /^worktree/ { path = $2; gsub(/.*\/\.worktrees\//, "", path) }
        /^branch/ { 
            branch = $2; 
            gsub(/^refs\/heads\//, "", branch)
            if (path != "") print path ":" branch
        }
    ' | sort
}

# Function to check if fzf is available
has_fzf() {
    command -v fzf > /dev/null 2>&1
}

# Function to format worktree for display
format_worktree() {
    local item="$1"
    local path="${item%%:*}"
    local branch="${item##*:}"
    local full_path=".worktrees/$path"
    
    if [ -d "$full_path" ]; then
        local status="${GREEN}●${NC}"
    else
        local status="${RED}●${NC}"
    fi
    
    printf "%s %-20s %s\n" "$status" "$path" "$branch"
}

# Function to show worktree details for preview
preview_worktree() {
    local item="$1"
    local path="${item%%:*}"
    local branch="${item##*:}"
    local full_path=".worktrees/$path"
    
    echo -e "${CYAN}Worktree Details${NC}"
    echo "Path: $full_path"
    echo "Branch: $branch"
    echo ""
    
    if [ -d "$full_path" ]; then
        echo -e "${GREEN}Status: Active${NC}"
        echo ""
        echo "Recent commits:"
        cd "$full_path" 2>/dev/null && git log --oneline -5 2>/dev/null || echo "No commits found"
    else
        echo -e "${RED}Status: Missing${NC}"
    fi
}

# TUI using fzf
run_fzf_interface() {
    local worktrees=$(get_worktrees)
    
    if [ -z "$worktrees" ]; then
        echo -e "${YELLOW}No worktrees found in .worktrees/${NC}"
        echo "Create one with: ./scripts/worktree.sh"
        return
    fi
    
    echo -e "${BLUE}=== Worktree Manager ===${NC}"
    echo -e "${YELLOW}Controls:${NC}"
    echo "  Enter - Open in Cursor"
    echo "  Ctrl-D - Archive/Remove"
    echo "  Ctrl-N - New worktree"
    echo "  Esc - Quit"
    echo ""
    
    export -f preview_worktree
    export RED GREEN BLUE YELLOW CYAN NC
    
    local selected=$(echo "$worktrees" | fzf \
        --height=80% \
        --layout=reverse \
        --border \
        --prompt="Select worktree > " \
        --preview="bash -c 'preview_worktree {}'" \
        --preview-window=right:50% \
        --bind="ctrl-d:execute(echo 'archive:{}' && exit 0)" \
        --bind="ctrl-n:execute(echo 'new' && exit 0)" \
        --header="Enter: Open | Ctrl-D: Archive | Ctrl-N: New | Esc: Quit" \
        --no-info)
    
    if [ -n "$selected" ]; then
        if [ "$selected" = "new" ]; then
            ./scripts/worktree.sh
        elif [[ "$selected" == archive:* ]]; then
            local item="${selected#archive:}"
            archive_worktree "$item"
        else
            open_worktree "$selected"
        fi
    fi
}

# Fallback bash select interface
run_bash_interface() {
    local worktrees=$(get_worktrees)
    
    if [ -z "$worktrees" ]; then
        echo -e "${YELLOW}No worktrees found in .worktrees/${NC}"
        echo "Create one with: ./scripts/worktree.sh"
        return
    fi
    
    echo -e "${BLUE}=== Worktree Manager ===${NC}"
    echo ""
    
    # Convert worktrees to array for select
    IFS=$'\n' read -d '' -r -a worktree_array <<< "$worktrees" || true
    
    # Add special options
    worktree_array+=("📁 Create New Worktree" "❌ Quit")
    
    echo "Select a worktree:"
    PS3="Your choice: "
    select item in "${worktree_array[@]}"; do
        case $item in
            "📁 Create New Worktree")
                ./scripts/worktree.sh
                break
                ;;
            "❌ Quit")
                break
                ;;
            *)
                if [ -n "$item" ]; then
                    echo ""
                    echo "Selected: $item"
                    echo "1) Open in Cursor"
                    echo "2) Archive/Remove"
                    echo "3) Back to list"
                    
                    read -p "Action: " action
                    case $action in
                        1) open_worktree "$item"; break ;;
                        2) archive_worktree "$item"; break ;;
                        3) run_bash_interface; break ;;
                        *) echo "Invalid choice"; continue ;;
                    esac
                fi
                ;;
        esac
    done
}

# Function to open worktree
open_worktree() {
    local item="$1"
    local path="${item%%:*}"
    local branch="${item##*:}"
    local full_path=".worktrees/$path"
    
    if [ ! -d "$full_path" ]; then
        echo -e "${RED}Error: Worktree directory not found: $full_path${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Opening worktree: $path${NC}"
    echo "Branch: $branch"
    echo "Path: $full_path"
    
    cd "$full_path"
    
    if command -v cursor > /dev/null 2>&1; then
        echo "Opening in Cursor..."
        cursor .
    else
        echo -e "${YELLOW}Cursor not found. You can manually cd to: $full_path${NC}"
    fi
}

# Function to archive/remove worktree
archive_worktree() {
    local item="$1"
    local path="${item%%:*}"
    local branch="${item##*:}"
    local full_path=".worktrees/$path"
    
    echo -e "${YELLOW}Archive worktree: $path${NC}"
    echo "Branch: $branch"
    echo "Path: $full_path"
    echo ""
    
    read -p "Are you sure you want to remove this worktree? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        if [ -d "$full_path" ]; then
            if ! git worktree remove "$full_path" 2>/dev/null; then
                echo -e "${YELLOW}Worktree contains modified or untracked files.${NC}"
                read -p "Force remove? (Y/n): " force_confirm
                force_confirm=${force_confirm:-Y}  # Default to Y if empty
                
                if [[ $force_confirm =~ ^[Yy]$ ]]; then
                    git worktree remove --force "$full_path"
                    echo -e "${GREEN}✓ Worktree force removed: $path${NC}"
                else
                    echo "Cancelled force removal."
                    return
                fi
            else
                echo -e "${GREEN}✓ Worktree removed: $path${NC}"
            fi
        else
            echo -e "${YELLOW}Worktree directory not found, cleaning up branch...${NC}"
        fi
        
        # Clean up branch if it exists
        if git show-ref --verify --quiet "refs/heads/$branch"; then
            read -p "Delete branch '$branch' as well? (y/N): " delete_branch
            if [[ $delete_branch =~ ^[Yy]$ ]]; then
                git branch -D "$branch"
                echo -e "${GREEN}✓ Branch deleted: $branch${NC}"
            fi
        fi
    else
        echo "Cancelled."
    fi
}

# Main function
main() {
    check_git_repo
    
    if has_fzf; then
        run_fzf_interface
    else
        echo -e "${YELLOW}fzf not found, using basic interface${NC}"
        echo -e "${CYAN}Tip: Install fzf for a better experience: brew install fzf${NC}"
        echo ""
        run_bash_interface
    fi
}

# Run main function
main "$@"