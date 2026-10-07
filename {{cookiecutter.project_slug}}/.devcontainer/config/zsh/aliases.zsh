# Zsh Aliases

# ===================
# Claude
# ===================
# Auto mode: Claude Code's built-in classifier decides which tool calls are
# safe to run without a prompt (permissions.defaultMode is "auto" in the
# bundled settings.json too — these aliases just make it explicit).
alias cca="claude --permission-mode auto"
alias ccac="claude --permission-mode auto --continue"
alias ccar="claude --permission-mode auto --resume"
# Install the latest Claude Code release now. The image pins a version and
# DISABLE_AUTOUPDATER=1 keeps it there, so this is the deliberate way to get
# ahead of the pin; a rebuild puts the pinned version back.
alias cu="curl -fsSL https://claude.ai/install.sh | bash"

# ===================
# GitHub Copilot CLI
# ===================
alias caat="copilot --allow-all-tools --banner"

# ===================
# Azure CLI
# ===================
# Who am I logged in as, and against which subscription/tenant?
alias azw='az account show --query "{user:user.name, subscription:name, tenant:tenantId}" -o table'
alias azl="az login"

# ===================
# GitHub CLI
# ===================
alias ghw="gh auth status"
alias ghl="gh auth login"

# ===================
# Git
# ===================
alias gs="git status --short --untracked-files=no"

# ===================
# Devcontainer
# ===================
alias dce="devcontainer exec --workspace-folder . zsh"
alias dcu="devcontainer up --workspace-folder ."
alias dcur="devcontainer up --workspace-folder . --remove-existing-container"

# ===================
# Meta
# ===================
# List the aliases in this file, grouped by section: als
als() {
    awk '
        /^# =+$/ && p2 ~ /^# =+$/ && p1 ~ /^# / { printf "\n\033[1;33m%s\033[0m\n", substr(p1, 3) }
        /^alias / {
            line = substr($0, 7); n = index(line, "=")
            cmd = substr(line, n + 1); gsub(/^["\047]|["\047]$/, "", cmd)
            printf "  \033[1;32m%-6s\033[0m %s\n", substr(line, 1, n - 1), cmd
        }
        { p2 = p1; p1 = $0 }
    ' "$HOME/.config/zsh/aliases.zsh"
    printf "  \033[1;32m%-6s\033[0m %s\n" "als" "this list"
}
