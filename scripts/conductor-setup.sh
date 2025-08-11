echo "=== Monorepo Worktree Setup ==="
echo "Workspace: $CONDUCTOR_WORKSPACE_NAME"
echo "Path: $CONDUCTOR_WORKSPACE_PATH"
echo ""

# Change to workspace directory
cd "$CONDUCTOR_WORKSPACE_PATH"

# Function to recursively copy files matching a pattern
copy_files_recursively() {
    local pattern="$1"
    local description="$2"
    
    echo "=== Copying $description ==="
    
    # Find all files matching the pattern in the source repo, excluding .conductor and .worktree* directories
    find "$CONDUCTOR_ROOT_PATH" -path "*/.conductor" -prune -o -path "*/.worktree*" -prune -o -name "$pattern" -type f -print | while read -r source_file; do
        # Get the relative path from the root
        relative_path="${source_file#$CONDUCTOR_ROOT_PATH/}"
        target_file="$CONDUCTOR_WORKSPACE_PATH/$relative_path"
        
        # Create the target directory if it doesn't exist
        target_dir=$(dirname "$target_file")
        mkdir -p "$target_dir"
        
        # Copy the file
        cp "$source_file" "$target_file"
        echo "✓ Copied $relative_path"
    done
}

# Copy gitignored files
copy_files_recursively ".env*" "environment files"
copy_files_recursively "CLAUDE.local.md" "local Claude configuration files"

echo ""

# Install dependencies
echo "=== Installing dependencies ==="
# examples:
# bun install
# bun --cwd apps/server db:generate
echo "✓ Dependencies installed"

echo ""
echo "=== Worktree ready! ==="

cd apps/