#!/usr/bin/env bash
# machine-setup.sh
# Run once on a new machine after cloning your Neovim config.
# Installs all system-level dependencies that Mason/vim.pack can't manage.
#
# Usage:
#   ./machine-setup.sh              # install everything
#   ./machine-setup.sh --skip-latex # skip the large LaTeX install
#   ./machine-setup.sh --skip-java
#   ./machine-setup.sh --skip-dotnet
#
# Not handled here (intentional):
#   - Obsidian vault path: add `export OBSIDIAN_VAULT=~/path/to/vault` to your shell
#   - LSP servers / linters / formatters: Mason handles those inside Neovim

set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Flags
# ─────────────────────────────────────────────────────────────
SKIP_LATEX=false
SKIP_JAVA=false
SKIP_DOTNET=false
SKIP_GO=false

for arg in "$@"; do
  case "$arg" in
    --skip-latex)  SKIP_LATEX=true ;;
    --skip-java)   SKIP_JAVA=true ;;
    --skip-dotnet) SKIP_DOTNET=true ;;
    --skip-go)     SKIP_GO=true ;;
    *) echo "Unknown flag: $arg. Valid flags: --skip-latex --skip-java --skip-dotnet --skip-go" && exit 1 ;;
  esac
done

# ─────────────────────────────────────────────────────────────
# Colours & logging
# ─────────────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log()         { echo -e "${GREEN}✓${NC}  $*"; }
log_section() { echo -e "\n${BLUE}${BOLD}▶  $*${NC}"; }
log_skip()    { echo -e "${YELLOW}→${NC}  skipping $* (already installed)"; }
log_warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
die()         { echo -e "${RED}✗  $*${NC}" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────
# OS + package manager detection
# ─────────────────────────────────────────────────────────────
OS=""
PM=""

detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="macos" ;;
    *)      die "Unsupported OS: $(uname -s)" ;;
  esac
}

detect_pm() {
  if   command -v brew    &>/dev/null; then PM="brew"
  elif command -v paru    &>/dev/null; then PM="paru"
  elif command -v yay     &>/dev/null; then PM="yay"
  elif command -v pacman  &>/dev/null; then PM="pacman"
  elif command -v apt-get &>/dev/null; then PM="apt"
  else die "No supported package manager found (brew / apt / pacman / paru / yay)"; fi
  log "OS: $OS  |  Package manager: $PM"
}

# Install one package, with per-PM name overrides.
# Usage: install_pkg <apt> [brew] [pacman]
install_pkg() {
  local apt_name="$1"
  local brew_name="${2:-$1}"
  local pac_name="${3:-$1}"
  case "$PM" in
    apt)    sudo apt-get install -y "$apt_name" ;;
    brew)   brew install "$brew_name" ;;
    paru)   paru  -S --noconfirm "$pac_name" ;;
    yay)    yay   -S --noconfirm "$pac_name" ;;
    pacman) sudo pacman -S --noconfirm "$pac_name" ;;
  esac
}

# ─────────────────────────────────────────────────────────────
# Base build tools
# ─────────────────────────────────────────────────────────────
install_base_tools() {
  log_section "Base build tools (git, curl, make, gcc, unzip)"

  case "$PM" in
    apt)
      sudo apt-get update -qq
      sudo apt-get install -y git curl wget make unzip build-essential
      ;;
    brew)
      # Xcode CLT provides make/gcc; brew provides the rest
      xcode-select --install 2>/dev/null || true
      brew install git curl wget unzip
      ;;
    paru|yay|pacman)
      install_pkg base-devel base-devel base-devel
      install_pkg git
      install_pkg curl
      install_pkg unzip
      ;;
  esac
  log "Base tools ready"
}

# ─────────────────────────────────────────────────────────────
# Neovim (latest stable from GitHub releases on apt; pkg manager elsewhere)
# ─────────────────────────────────────────────────────────────
install_neovim() {
  log_section "Neovim"

  if command -v nvim &>/dev/null; then
    log_skip "neovim ($(nvim --version | head -1))"
    return
  fi

  case "$PM" in
    apt)
      # Ubuntu's repo is often outdated — install from GitHub releases
      local arch; arch=$(uname -m)
      local nvim_arch
      case "$arch" in
        x86_64)  nvim_arch="linux-x86_64" ;;
        aarch64) nvim_arch="linux-arm64" ;;
        *)       die "Unsupported arch for Neovim download: $arch" ;;
      esac
      local tmp; tmp=$(mktemp -d)
      curl -sL "https://github.com/neovim/neovim/releases/latest/download/nvim-${nvim_arch}.tar.gz" \
        -o "$tmp/nvim.tar.gz"
      sudo tar -C /usr/local --strip-components=1 -xzf "$tmp/nvim.tar.gz"
      rm -rf "$tmp"
      ;;
    brew)   brew install neovim ;;
    paru)   paru  -S --noconfirm neovim ;;
    yay)    yay   -S --noconfirm neovim ;;
    pacman) sudo pacman -S --noconfirm neovim ;;
  esac
  log "Neovim $(nvim --version | head -1)"
}

# ─────────────────────────────────────────────────────────────
# ripgrep (Telescope live_grep + obsidian.nvim search)
# ─────────────────────────────────────────────────────────────
install_ripgrep() {
  log_section "ripgrep"

  if command -v rg &>/dev/null; then
    log_skip "ripgrep ($(rg --version | head -1))"
    return
  fi

  install_pkg ripgrep ripgrep ripgrep
  log "ripgrep $(rg --version | head -1)"
}

# ─────────────────────────────────────────────────────────────
# Rust + cargo packages
# (tree-sitter-cli: nvim-treesitter parser compilation)
# (yazi-fm / yazi-cli: the Yazi file manager)
# ─────────────────────────────────────────────────────────────
install_rust() {
  log_section "Rust (rustup)"

  if command -v cargo &>/dev/null; then
    log_skip "cargo ($(cargo --version))"
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    log "Rust installed"
  fi

  # Make cargo available for the rest of this script
  source "${CARGO_HOME:-$HOME/.cargo}/env" 2>/dev/null || \
    export PATH="$HOME/.cargo/bin:$PATH"
}

install_cargo_packages() {
  log_section "Cargo packages"

  # ┌────────────────────┬────────────┬─────────────────────────────────────┐
  # │ Crate              │ Binary     │ Purpose                             │
  # ├────────────────────┼────────────┼─────────────────────────────────────┤
  # │ tree-sitter-cli    │ tree-sitter│ nvim-treesitter parser compilation  │
  # │ yazi-fm            │ yazi       │ Yazi file manager                   │
  # │ yazi-cli           │ ya         │ Yazi helper CLI                     │
  # └────────────────────┴────────────┴─────────────────────────────────────┘
  local -a crates=(tree-sitter-cli yazi-fm yazi-cli)
  local -a bins=(tree-sitter yazi ya)

  for i in "${!crates[@]}"; do
    local crate="${crates[$i]}"
    local bin="${bins[$i]}"
    if command -v "$bin" &>/dev/null; then
      log_skip "$crate ($("$bin" --version 2>/dev/null | head -1 || echo installed))"
    else
      cargo install "$crate"
      log "$crate → $bin installed"
    fi
  done
}

# ─────────────────────────────────────────────────────────────
# Node.js via nvm
# ─────────────────────────────────────────────────────────────
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

install_nvm() {
  log_section "nvm"

  if [ -s "$NVM_DIR/nvm.sh" ]; then
    log_skip "nvm"
  else
    curl -sL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    log "nvm installed"
  fi

  # Load nvm as a shell function for the rest of this script
  export NVM_DIR
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh" || true
}

install_node() {
  log_section "Node.js (latest LTS)"

  # nvm is a shell function, not a binary — use `type` not `command -v`
  if ! type nvm &>/dev/null 2>&1; then
    log_warn "nvm not loaded — skipping Node. Restart your shell and re-run."
    return
  fi

  nvm install --lts
  nvm use --lts
  log "Node $(node --version) / npm $(npm --version)"
}

install_npm_packages() {
  log_section "npm global packages"

  if ! command -v npm &>/dev/null; then
    log_warn "npm not found — skipping npm packages"
    return
  fi

  # ┌──────────────┬──────────────────────────────────────────┐
  # │ Package      │ Purpose                                  │
  # ├──────────────┼──────────────────────────────────────────┤
  # │ live-server  │ HTML live preview (live-server.nvim)     │
  # └──────────────┴──────────────────────────────────────────┘
  local -a packages=(live-server)

  for p in "${packages[@]}"; do
    if npm list -g --depth=0 2>/dev/null | grep -q "$p"; then
      log_skip "$p (npm global)"
    else
      npm install -g "$p"
      log "$p installed globally"
    fi
  done
}

# ─────────────────────────────────────────────────────────────
# Python + uv
# ─────────────────────────────────────────────────────────────
install_python() {
  log_section "Python + uv"

  if command -v python3 &>/dev/null; then
    log_skip "python3 ($(python3 --version))"
  else
    case "$PM" in
      apt)    sudo apt-get install -y python3 python3-pip ;;
      brew)   brew install python ;;
      paru)   paru  -S --noconfirm python ;;
      yay)    yay   -S --noconfirm python ;;
      pacman) sudo pacman -S --noconfirm python python-pip ;;
    esac
    log "python3 installed"
  fi

  if command -v uv &>/dev/null; then
    log_skip "uv ($(uv --version))"
  else
    curl -LsSf https://astral.sh/uv/install.sh | sh
    log "uv installed"
  fi
}

# ─────────────────────────────────────────────────────────────
# Go
# ─────────────────────────────────────────────────────────────
install_go() {
  log_section "Go"

  if $SKIP_GO; then
    log_warn "Skipping Go (--skip-go)"
    return
  fi

  if command -v go &>/dev/null; then
    log_skip "go ($(go version))"
    return
  fi

  case "$PM" in
    apt)
      # Fetch the latest release tag and download the official tarball
      local ver
      ver=$(curl -s "https://go.dev/dl/?mode=json" \
        | grep -o '"version":"go[^"]*"' | head -1 | grep -o 'go[0-9.]*')
      local arch; arch=$(uname -m)
      local go_arch; [ "$arch" = "aarch64" ] && go_arch="arm64" || go_arch="amd64"
      local tmp; tmp=$(mktemp -d)
      curl -sL "https://go.dev/dl/${ver}.linux-${go_arch}.tar.gz" -o "$tmp/go.tar.gz"
      sudo rm -rf /usr/local/go
      sudo tar -C /usr/local -xzf "$tmp/go.tar.gz"
      rm -rf "$tmp"
      # Persist in profile
      grep -qxF 'export PATH="$PATH:/usr/local/go/bin"' "$HOME/.profile" 2>/dev/null \
        || echo 'export PATH="$PATH:/usr/local/go/bin"' >> "$HOME/.profile"
      export PATH="$PATH:/usr/local/go/bin"
      ;;
    brew)   brew install go ;;
    paru)   paru  -S --noconfirm go ;;
    yay)    yay   -S --noconfirm go ;;
    pacman) sudo pacman -S --noconfirm go ;;
  esac
  log "Go $(go version)"
}

# ─────────────────────────────────────────────────────────────
# Java (JDK) — needed for jdtls (Java LSP in Mason)
# ─────────────────────────────────────────────────────────────
install_java() {
  log_section "Java (JDK)"

  if $SKIP_JAVA; then
    log_warn "Skipping Java (--skip-java)"
    return
  fi

  if command -v java &>/dev/null; then
    log_skip "java ($(java -version 2>&1 | head -1))"
    return
  fi

  case "$PM" in
    apt)    sudo apt-get install -y default-jdk ;;
    brew)
      brew install openjdk
      # Symlink so system Java wrappers find it
      sudo ln -sfn "$(brew --prefix openjdk)/libexec/openjdk.jdk" \
        /Library/Java/JavaVirtualMachines/openjdk.jdk 2>/dev/null || true
      ;;
    paru)   paru  -S --noconfirm jdk-openjdk ;;
    yay)    yay   -S --noconfirm jdk-openjdk ;;
    pacman) sudo pacman -S --noconfirm jdk-openjdk ;;
  esac
  log "Java installed"
}

# ─────────────────────────────────────────────────────────────
# .NET SDK — needed for omnisharp (C# LSP in Mason)
# ─────────────────────────────────────────────────────────────
install_dotnet() {
  log_section ".NET SDK"

  if $SKIP_DOTNET; then
    log_warn "Skipping .NET (--skip-dotnet)"
    return
  fi

  if command -v dotnet &>/dev/null; then
    log_skip "dotnet ($(dotnet --version))"
    return
  fi

  case "$PM" in
    apt|pacman|paru|yay)
      # Microsoft's official install script works on all Linux distros
      curl -sL https://dot.net/v1/dotnet-install.sh \
        | bash -s -- --channel LTS --install-dir "$HOME/.dotnet"
      grep -qxF 'export PATH="$PATH:$HOME/.dotnet"' "$HOME/.profile" 2>/dev/null \
        || echo 'export PATH="$PATH:$HOME/.dotnet"' >> "$HOME/.profile"
      export PATH="$PATH:$HOME/.dotnet"
      ;;
    brew)
      brew install dotnet
      ;;
  esac
  log ".NET SDK $(dotnet --version 2>/dev/null || echo installed)"
}

# ─────────────────────────────────────────────────────────────
# LaTeX — needed for vimtex + latexmk compiler
# Also installs the PDF viewer (zathura on Linux, Skim on macOS)
# ─────────────────────────────────────────────────────────────
install_latex() {
  log_section "LaTeX"

  if $SKIP_LATEX; then
    log_warn "Skipping LaTeX (--skip-latex)"
    return
  fi

  if command -v latexmk &>/dev/null; then
    log_skip "LaTeX (latexmk found)"
  else
    log_warn "LaTeX is large (~1-4 GB). Press Ctrl-C within 5s to skip."
    sleep 5

    case "$PM" in
      apt)
        # texlive + extras is a reasonable middle ground (~1GB).
        # Swap for texlive-full (~4GB) if you need every package.
        sudo apt-get install -y texlive texlive-latex-extra texlive-fonts-recommended latexmk
        ;;
      brew)
        # mactex-no-gui skips the GUI apps; still ~3GB
        brew install --cask mactex-no-gui
        ;;
      paru)   paru  -S --noconfirm texlive-most ;;
      yay)    yay   -S --noconfirm texlive-most ;;
      pacman) sudo pacman -S --noconfirm texlive-most ;;
    esac
    log "LaTeX installed"
  fi

  # PDF viewer
  if [[ "$OS" == "linux" ]]; then
    if command -v zathura &>/dev/null; then
      log_skip "zathura"
    else
      install_pkg zathura zathura zathura
      log "zathura installed"
    fi
  elif [[ "$OS" == "macos" ]]; then
    if command -v skim &>/dev/null || [ -d "/Applications/Skim.app" ]; then
      log_skip "Skim"
    else
      brew install --cask skim
      log "Skim installed"
    fi
  fi
}

# ─────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────
print_next_steps() {
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}${BOLD}  Setup complete!${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "  Next steps:"
  echo "  1. Restart your shell (or: source ~/.profile)"
  echo "  2. Open Neovim — Mason will auto-install all LSP servers,"
  echo "     linters, and formatters on first launch."
  echo ""
  echo "  One-time per machine (not in this script):"
  echo "  • Obsidian vault:"
  echo "    Add to ~/.bashrc / ~/.zshrc:"
  echo "    export OBSIDIAN_VAULT=~/path/to/your/vault"
  echo ""
  if [[ "$OS" == "macos" ]]; then
    echo "  • vimtex PDF viewer: Skim (installed)"
    echo "    In your nvim config, vimtex_view_method is set to 'zathura'."
    echo "    Change it to 'skim' on macOS."
  else
    echo "  • vimtex PDF viewer: zathura (installed)"
  fi
  echo ""
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
main() {
  echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║           machine-setup.sh                   ║${NC}"
  echo -e "${BOLD}║   Neovim config — system dependencies        ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"

  detect_os
  detect_pm

  install_base_tools
  install_neovim
  install_ripgrep
  install_rust
  install_cargo_packages
  install_nvm
  install_node
  install_npm_packages
  install_python
  install_go
  install_java
  install_dotnet
  install_latex

  print_next_steps
}

main "$@"
