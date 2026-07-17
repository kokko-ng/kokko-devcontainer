# Zsh Aliases

# ===================
# Claude
# ===================
alias ccc="claude --permission-mode bypassPermissions"
alias cccc="claude --permission-mode bypassPermissions --continue"
# Update Claude Code (native installer)
alias cu="curl -fsSL https://claude.ai/install.sh | bash"

# ===================
# GitHub Copilot CLI
# ===================
alias caat="copilot --allow-all-tools --banner"

# ===================
# Git safety (see GIT-SAFETY.md)
# ===================
# Working-tree snapshots: `snaps` (list) / show / diff / restore <ref>.
# Note that `ccc` above runs with bypassPermissions, which skips permission
# rules entirely -- PreToolUse hooks are what still block a destructive git
# command there, which is why the safety net is built out of hooks.
alias gs="git status --short --untracked-files=no"
alias snapl="snaps list"

# ===================
# Devcontainer
# ===================
alias dce="devcontainer exec --workspace-folder . zsh"
alias dcu="devcontainer up --workspace-folder ."
alias dcur="devcontainer up --workspace-folder . --remove-existing-container"
