#!/bin/bash
set -e

# ---------- Step 1: Install Zsh & dependencies ----------
echo "[*] Installing Zsh and dependencies..."
sudo apt update
sudo apt install -y zsh git curl wget neovim

# ---------- Step 2: Install Oh My Zsh ----------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "[*] Installing Oh My Zsh..."
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "[*] Oh My Zsh already installed."
fi

# ---------- Step 3: Install Plugins ----------
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
echo "[*] Installing Zsh plugins..."

# Autosuggestions
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

# Syntax Highlighting
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# Completions
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-completions" ]; then
  git clone https://github.com/zsh-users/zsh-completions "$ZSH_CUSTOM/plugins/zsh-completions"
fi

# ---------- Step 4: Configure .zshrc ----------
echo "[*] Applying custom .zshrc..."
cat > ~/.zshrc << 'EOF'
# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

# Plugins
plugins=(
  git 
  z 
  extract 
  history   
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-completions
)

source $ZSH/oh-my-zsh.sh

# Preferred editor
export EDITOR='nvim'
export VISUAL='nvim'

# Aliases
alias vim='nvim'
alias zshconfig="nvim ~/.zshrc"
alias ohmyzsh="nvim ~/.oh-my-zsh"

# Enable colors for prompt
autoload -Uz colors && colors

# Custom colorful prompt
PROMPT='%{$fg[blue]%}[%*]%{$reset_color%} %{$fg[green]%}%n@%m%{$reset_color%} %{$fg[yellow]%}%~%{$reset_color%}$(git_branch) $ '

ENABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"
HIST_STAMPS="yyyy-mm-dd"
EOF

# ---------- Step 5: Set Zsh as default shell ----------
echo "[*] Setting Zsh as default shell..."
chsh -s "$(which zsh)"

echo "[✔] Done. Please logout or run 'zsh' to start using Zsh."
