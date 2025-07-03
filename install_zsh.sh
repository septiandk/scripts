#!/bin/bash
set -e

echo "[*] Installing dependencies..."
apt update
apt install -y zsh git curl wget neovim

# ----------- STEP 1: Prepare Oh My Zsh and Plugins -----------

TEMP_OHMYZSH="/tmp/oh-my-zsh"
ZSH_CUSTOM="$TEMP_OHMYZSH/custom"

if [ ! -d "$TEMP_OHMYZSH" ]; then
  echo "[*] Cloning Oh My Zsh..."
  git clone https://github.com/ohmyzsh/ohmyzsh.git "$TEMP_OHMYZSH"
fi

# Clone plugins if not already present
mkdir -p "$ZSH_CUSTOM/plugins"

[[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] &&
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

[[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] &&
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

[[ ! -d "$ZSH_CUSTOM/plugins/zsh-completions" ]] &&
  git clone https://github.com/zsh-users/zsh-completions "$ZSH_CUSTOM/plugins/zsh-completions"

# ----------- STEP 2: Define .zshrc Template -----------

ZSHRC_CONTENT='
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

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

export EDITOR="nvim"
export VISUAL="nvim"

alias vim="nvim"
alias zshconfig="nvim ~/.zshrc"
alias ohmyzsh="nvim ~/.oh-my-zsh"

autoload -Uz colors && colors

PROMPT="%{\$fg[blue]%}[%*]%{\$reset_color%} %{\$fg[green]%}%n@%m%{\$reset_color%} %{\$fg[yellow]%}%~%{\$reset_color%}\$(git_branch) \$ "

ENABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"
HIST_STAMPS="yyyy-mm-dd"
function git_branch() {
  git rev-parse --is-inside-work-tree &>/dev/null || return
  ref=$(git symbolic-ref --quiet HEAD 2>/dev/null)
  echo " %{$fg[magenta]%}( ${ref#refs/heads/})%{$reset_color%}"
}

'

# ----------- STEP 3: Apply to /etc/skel (for future users) -----------

echo "[*] Setting up /etc/skel for new users..."

cp -r "$TEMP_OHMYZSH" /etc/skel/.oh-my-zsh
echo "$ZSHRC_CONTENT" > /etc/skel/.zshrc

# ----------- STEP 4: Apply to existing users -----------

echo "[*] Applying to existing users..."

for user in $(awk -F: '{ if ($3 >= 1000 && $1 != "nobody") print $1 }' /etc/passwd); do
  HOME_DIR=$(eval echo "~$user")

  echo "  -> Configuring user: $user"

  # Copy .oh-my-zsh if needed
  if [ ! -d "$HOME_DIR/.oh-my-zsh" ]; then
    cp -r "$TEMP_OHMYZSH" "$HOME_DIR/.oh-my-zsh"
    chown -R "$user:$user" "$HOME_DIR/.oh-my-zsh"
  fi

  # Write .zshrc
  echo "$ZSHRC_CONTENT" > "$HOME_DIR/.zshrc"
  chown "$user:$user" "$HOME_DIR/.zshrc"

  # Change shell to zsh
  chsh -s "$(which zsh)" "$user"
done

# ----------- STEP 5: Set default shell globally (optional) -----------

echo "[*] Setting Zsh as default shell for new users (via /etc/default/useradd)..."
sed -i 's|^SHELL=.*|SHELL=/usr/bin/zsh|' /etc/default/useradd

echo "[✔] Zsh environment applied to all users (existing and future)."
echo "[ℹ️ ] You may need to re-login or run 'zsh' manually to see the changes."
