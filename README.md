# kickstart.nvim

## Introduction

A starting point for Neovim that is:

* Small
* Single-file
* Completely Documented

**NOT** a Neovim distribution, but instead a starting point for your configuration.

## Installation

### Machine setup scripts (recommended)

This config is **dual-target**: it runs on Linux/macOS and on native Windows.
`init.lua` detects the platform and branches where it has to, so the same clone
works on any of them. Rather than installing the system dependencies by hand,
run the setup script for your OS:

| OS | Script | Package sources |
| :- | :----- | :-------------- |
| Linux, macOS | `./machine-setup.sh` | apt / brew / pacman / paru / yay, cargo, nvm, rustup |
| Windows | `.\machine-setup.ps1` | winget, npm |

Both scripts are idempotent — they skip anything already installed — and both
accept the same skip flags for the heavy optional dependencies:

```sh
# Linux / macOS
./machine-setup.sh --skip-latex --skip-java --skip-dotnet --skip-go
```

```powershell
# Windows - run as yourself, NOT elevated
.\machine-setup.ps1 -SkipLatex -SkipJava -SkipDotnet -SkipGo -SkipRust
```

> [!IMPORTANT]
> **`machine-setup.ps1` needs no administrator rights.** This is deliberate:
> on a managed corporate machine you may only have policy-scoped elevation
> (e.g. Microsoft Intune Endpoint Privilege Management, "Run with elevated
> access") rather than real UAC admin. Everything installs into your own
> profile — `winget --scope user` into
> `%LOCALAPPDATA%\Microsoft\WinGet\Packages`, portable zips into
> `%LOCALAPPDATA%\Programs`, npm globals into `%APPDATA%\npm`. The machine
> `PATH` is never modified.
>
> Node, Go and the JDK publish MSIs that insist on installing machine-wide
> (they fail with exit `1602` when UAC is declined), so the script installs
> those three from their official **ZIP** distributions instead and adds them
> to your user `PATH`. Same binaries, no elevation.
>
> The **.NET SDK** is the sole exception — its installer genuinely requires
> admin. It is usually already present on a corporate image, so the script
> checks and reports rather than failing. Only `omnisharp` (C#) needs it; drop
> `omnisharp` from the `servers` table in `init.lua` if you would rather Mason
> stopped retrying it.

> [!WARNING]
> Do not run `machine-setup.ps1` from a shell elevated as a *different*
> account. The user-scope installs would land in that account's profile, so
> `tree-sitter`, the npm globals and the winget packages would not be on
> **your** `PATH` — and treesitter would fail with exactly the same error you
> were trying to fix. Run it as yourself, unelevated.

After the script finishes, **open a new shell** so the updated user `PATH` is
visible, then run `nvim` and let `vim.pack` and Mason do the rest. Confirm with
`:checkhealth`.

Treesitter parsers compile asynchronously, so they are not ready the instant
Neovim opens. The config only requests the parsers actually missing and
reports progress, so on first launch you get a notification naming them and a
second one when the compile finishes — no guessing whether highlighting is
broken or merely still building. To check by hand:

```vim
:lua print(#require('nvim-treesitter').get_installed('parsers'))
```

If the compile *fails*, the notification says so. On Windows the usual cause
is the tree-sitter CLI not finding a C compiler — see the `CC` note below.

#### What differs per platform

Most of the config is platform-agnostic. These are the places it branches:

| Concern | Linux | macOS | Windows |
| :------ | :---- | :---- | :------ |
| vimtex PDF viewer | `zathura` | `skim` | `sumatrapdf` |
| LaTeX distribution | texlive + latexmk | mactex-no-gui | MiKTeX (ships latexmk) |
| C compiler for treesitter | gcc (build-essential) | Xcode CLT | gcc (WinLibs) |
| `telescope-fzf-native` build | `make` | `make` | `make`, else CMake fallback |
| tree-sitter CLI | `cargo install tree-sitter-cli` | same | `npm install -g tree-sitter-cli` (prebuilt, no Rust needed) |
| `CC` for the tree-sitter CLI | unset (finds `cc`) | unset | `vim.env.CC = 'gcc'` — see below |
| Clipboard | native X/Wayland | native | native; **WSL** bridges via `win32yank` |
| Rust toolchain | default | default | `stable-gnu`, to avoid needing VS Build Tools |
| Node / Go / JDK | pkg manager, nvm | brew | portable **zips** into `%LOCALAPPDATA%\Programs` (the MSIs need admin) |

The `CC` row is worth calling out, because the failure is opaque. The
tree-sitter CLI shells out to `cc` (or MSVC `cl`) to compile a parser. MinGW
and WinLibs ship `gcc` but no `cc`, so every parser build dies with a bare:

```
Error during "tree-sitter build": Error: Failed to compile parser
Caused by: Error: program not found
```

`init.lua` fixes this by setting `vim.env.CC = 'gcc'` on Windows when neither
`cc` nor `cl` is present. That is scoped to Neovim's child processes, so it
needs no machine-wide environment variable and no multi-GB Visual Studio
Build Tools install.

Anything the config cannot find, it degrades around rather than erroring:
`telescope-fzf-native` is only loaded if it can be built, and `yazi.nvim` is
only wired up if the `yazi` binary exists — otherwise `open_for_directories`
would hijack `nvim .` and leave you without a working file explorer.

#### Machine-local configuration

Anything tied to a single machine or employer belongs in **`lua/machine.lua`**,
which is gitignored and loaded with `pcall` at the end of SECTION 9.6. A fresh
clone has no such file and everything still works — that is what keeps this
repo portable and free of internal details.

It is the right home for:

- extra file-type associations for in-house SQL extensions (many Oracle shops
  use their own set for package bodies, views, table DDL and so on)
- house indentation rules
- a sqlfluff override: set `vim.g.sqlfluff_config` to a config path and
  conform uses it instead of the generic `sqlfluff.cfg` committed here
- database connections and any private tooling that wraps them

```lua
-- lua/machine.lua (gitignored)
vim.filetype.add { extension = { xyz = 'plsql' } }
vim.g.sqlfluff_config = vim.fs.joinpath(vim.fn.stdpath 'config', 'sqlfluff.local.cfg')
vim.g.dbs = { mydb = vim.env.MYDB_URL }  -- never hardcode credentials
```

> [!NOTE]
> `vim-dadbod` cannot do Oracle **wallet** authentication. Its
> `db#adapter#oracle#interactive()` always builds `user/password@host` and
> falls back to `system/oracle`; nothing emits the `/@ALIAS` form a wallet
> needs. If your site authenticates via a wallet, drive `sqlplus` directly
> from `lua/machine.lua` rather than through dadbod.

#### SQL formatting

`sqlfluff` is wired to the `sql` filetype only, **not** `plsql`. It parses
PL/SQL package bodies cleanly, but `sqlfluff format` always runs its own
reindent/reflow pass — not rule-driven, and not switchable off via
`exclude_rules` or a `rules` allowlist — which hoists `exception` out to the
wrong nesting level. There is no configuration that makes it safe for
procedural code, so `<leader>f` on a PL/SQL buffer tells you no formatter is
configured instead of quietly mangling it. Oracle's SQLcl (`format buffer`)
is the upgrade path if you ever install it.

Two timing details, both measured rather than guessed:

- sqlfluff needs **~1s** just to start (Python interpreter startup, roughly
  independent of input size). conform's default `timeout_ms` is 1000, so
  synchronous formatting sat right on the boundary and failed intermittently.
  `format_on_save` here uses 3000ms.
- `timeout_ms` has **no effect when `async = true`**, which is how `<leader>f`
  runs — so interactive formatting was never affected by this.

### Install Neovim

Kickstart.nvim targets *only* the latest
['stable'](https://github.com/neovim/neovim/releases/tag/stable) and latest
['nightly'](https://github.com/neovim/neovim/releases/tag/nightly) of Neovim.
If you are experiencing issues, please make sure you have at least the latest
stable version. Most likely, you want to install neovim via a [package
manager](https://github.com/neovim/neovim/blob/master/INSTALL.md#install-from-package).
To check your neovim version, run `nvim --version` and make sure it is not
below the latest
['stable'](https://github.com/neovim/neovim/releases/tag/stable) version. If
your chosen install method only gives you an outdated version of neovim, find
alternative [installation methods below](#alternative-neovim-installation-methods).

### Install External Dependencies

External Requirements:
- Basic utils: `git`, `make`, `unzip`, C Compiler (`gcc`)
- [ripgrep](https://github.com/BurntSushi/ripgrep#installation),
  [fd-find](https://github.com/sharkdp/fd#installation)
- [tree-sitter CLI](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md#installation)
- Clipboard tool (xclip/xsel/win32yank or other depending on the platform)
- A [Nerd Font](https://www.nerdfonts.com/): optional, provides various icons
  - if you have it set `vim.g.have_nerd_font` in `init.lua` to true
- Emoji fonts (Ubuntu only, and only if you want emoji!) `sudo apt install fonts-noto-color-emoji`
- Language Setup:
  - If you want to write Typescript, you need `npm`
  - If you want to write Golang, you will need `go`
  - etc.

> [!NOTE]
> See [Install Recipes](#Install-Recipes) for additional Windows and Linux specific notes
> and quick install snippets

### Install Kickstart

> [!NOTE]
> [Backup](#FAQ) your previous configuration (if any exists)

Neovim's configurations are located under the following paths, depending on your OS:

| OS | PATH |
| :- | :--- |
| Linux, MacOS | `$XDG_CONFIG_HOME/nvim`, `~/.config/nvim` |
| Windows (cmd)| `%localappdata%\nvim\` |
| Windows (powershell)| `$env:LOCALAPPDATA\nvim\` |

#### Recommended Step

Create your own copy of this repo using GitHub's
["Use this template"](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template)
button so that you have your own copy that you can modify, then install by
cloning your new repo to your machine using one of the commands below,
depending on your OS.

Alternatively, you can [fork](https://docs.github.com/en/get-started/quickstart/fork-a-repo)
this repo if you prefer an easy upstream sync path (e.g., keeping your config
on a separate branch and fast-forwarding `master` from upstream). See the
[discussion in #1740](https://github.com/nvim-lua/kickstart.nvim/issues/1740)
for the tradeoffs between the two approaches.

> [!NOTE]
> Your repo's URL will be something like this:
> `https://github.com/<your_github_username>/kickstart.nvim.git`

You likely want to remove `nvim-pack-lock.json` from your repo's `.gitignore`
file too - it's ignored in the kickstart repo to make maintenance easier, but
it's recommended to track it in version control (see `:help vim.pack-lockfile`).

#### Clone kickstart.nvim

> [!NOTE]
> If following the recommended step above (i.e., creating your own repo from
> the template or fork), replace `nvim-lua` with `<your_github_username>`
> in the commands below

<details><summary> Linux and Mac </summary>

```sh
git clone https://github.com/usman-a/kickstart.nvim.git "${XDG_CONFIG_HOME:-$HOME/.config}"/nvim
```

</details>

<details><summary> Windows </summary>

If you're using `cmd.exe`:

```
git clone https://github.com/usman-a/kickstart.nvim.git "%localappdata%\nvim"
```

If you're using `powershell.exe`

```
git clone https://github.com/usman-a/kickstart.nvim.git "${env:LOCALAPPDATA}\nvim"
```

</details>

### Post Installation

Start Neovim

```sh
nvim
```

That's it! `vim.pack` will install all the plugins from your config. Use
`:lua vim.pack.update(nil, { offline = true })` to inspect plugin state and
`:lua vim.pack.update()` to fetch updates (`:write` applies updates, `:quit`
cancels them).

#### Read The Friendly Documentation

Read through the `init.lua` file in your configuration folder for more
information about extending and exploring Neovim. That also includes
examples of adding popularly requested plugins.

> [!NOTE]
> For more information about a particular plugin check its repository's documentation.


### Getting Started

[The Only Video You Need to Get Started with Neovim](https://youtu.be/m8C0Cq9Uv9o)

### FAQ

* What should I do if I already have a pre-existing Neovim configuration?
  * You should back it up and then delete all associated files.
  * This includes your existing init.lua and the Neovim files in `~/.local`
    which can be deleted with `rm -rf ~/.local/share/nvim/`
* Can I keep my existing configuration in parallel to kickstart?
  * Yes! You can use [NVIM_APPNAME](https://neovim.io/doc/user/starting.html#%24NVIM_APPNAME)`=nvim-NAME`
    to maintain multiple configurations. For example, you can install the kickstart
    configuration in `~/.config/nvim-kickstart` and create an alias:
    ```
    alias nvim-kickstart='NVIM_APPNAME="nvim-kickstart" nvim'
    ```
    When you run Neovim using `nvim-kickstart` alias it will use the alternative
    config directory and the matching local directory
    `~/.local/share/nvim-kickstart`. You can apply this approach to any Neovim
    distribution that you would like to try out.
* What if I want to "uninstall" this configuration:
  * Remove your config directory and local data directory (for example,
    `~/.config/nvim` and `~/.local/share/nvim`).
* Why is the kickstart `init.lua` a single file? Wouldn't it make sense to split it into multiple files?
  * The main purpose of kickstart is to serve as a teaching tool and a reference
    configuration that someone can easily use to `git clone` as a basis for their own.
    As you progress in learning Neovim and Lua, you might consider splitting `init.lua`
    into smaller parts. A fork of kickstart that does this while maintaining the
    same functionality is available here:
    * [kickstart-modular.nvim](https://github.com/dam9000/kickstart-modular.nvim)
  * Discussions on this topic can be found here:
    * [Restructure the configuration](https://github.com/nvim-lua/kickstart.nvim/issues/218)
    * [Reorganize init.lua into a multi-file setup](https://github.com/nvim-lua/kickstart.nvim/pull/473)

### Install Recipes

Below you can find OS specific install instructions for Neovim and dependencies.

After installing all the dependencies continue with the [Install Kickstart](#install-kickstart) step.

#### Windows Installation

<details><summary>Windows with Microsoft C++ Build Tools and CMake</summary>
Kickstart's default config is make-only for `telescope-fzf-native.nvim`.
If `make` is unavailable, the plugin is skipped.

Recommended: install `make` (see the chocolatey section below).

If you want a CMake-only setup, customize `init.lua` in two places:

1. Include `telescope-fzf-native.nvim` when `cmake` is available:

```lua
if vim.fn.executable 'make' == 1 or vim.fn.executable 'cmake' == 1 then
  table.insert(plugins, gh 'nvim-telescope/telescope-fzf-native.nvim')
end
```

2. In the `PackChanged` hook, use CMake when `make` is unavailable:

```lua
if name == 'telescope-fzf-native.nvim' then
  if vim.fn.executable 'make' == 1 then
    run_build(name, { 'make' }, ev.data.path)
  elseif vim.fn.executable 'cmake' == 1 then
    run_build(name, { 'cmake', '-S.', '-Bbuild', '-DCMAKE_BUILD_TYPE=Release' }, ev.data.path)
    run_build(name, { 'cmake', '--build', 'build', '--config', 'Release', '--target', 'install' }, ev.data.path)
  end
  return
end
```

See `telescope-fzf-native` documentation for [build details](https://github.com/nvim-telescope/telescope-fzf-native.nvim#installation).
</details>
<details><summary>Windows with gcc/make using chocolatey</summary>
Alternatively, one can install gcc and make which don't require changing the config,
the easiest way is to use choco:

1. install [chocolatey](https://chocolatey.org/install)
either follow the instructions on the page or use winget,
run in cmd as **admin**:
```
winget install --accept-source-agreements chocolatey.chocolatey
```

2. install all requirements using choco, exit the previous cmd and
open a new one so that choco path is set, and run in cmd as **admin**:
```
choco install -y neovim git ripgrep wget fd unzip gzip mingw make tree-sitter
```
</details>
<details><summary>WSL (Windows Subsystem for Linux)</summary>

```
wsl --install
wsl
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt install make gcc ripgrep fd-find tree-sitter-cli unzip git xclip neovim
```
</details>

#### Linux Install
<details><summary>Ubuntu Install Steps</summary>

```
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt install make gcc ripgrep fd-find tree-sitter-cli unzip git xclip neovim
```
</details>
<details><summary>Debian Install Steps</summary>

```
sudo apt update
sudo apt install make gcc ripgrep fd-find tree-sitter-cli unzip git xclip curl

# Now we install nvim
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
sudo rm -rf /opt/nvim-linux-x86_64
sudo mkdir -p /opt/nvim-linux-x86_64
sudo chmod a+rX /opt/nvim-linux-x86_64
sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz

# make it available in /usr/local/bin, distro installs to /usr/bin
sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/
```
</details>
<details><summary>Fedora Install Steps</summary>

```
sudo dnf install -y gcc make git ripgrep fd-find tree-sitter-cli unzip neovim
```
</details>

<details><summary>Arch Install Steps</summary>

```
sudo pacman -S --noconfirm --needed gcc make git ripgrep fd tree-sitter-cli unzip neovim
```
</details>

<details><summary>Alpine Install Steps</summary>

> [!CAUTION]
> Neovim works fine on Alpine, but some tooling appears incompatible with musl
> (lua-language-server, etc., check `:Mason` or `:MasonLog`).
> Quickfix Lua-LSP-Support: `:%s/lua_ls/emmylua_ls`

```shell
sudo apk add gcc make git fd ripgrep tree-sitter-cli unzip bash gzip curl musl-dev neovim-doc neovim
```

</details>

### Alternative neovim installation methods

For some systems it is not unexpected that the [package manager installation
method](https://github.com/neovim/neovim/blob/master/INSTALL.md#install-from-package)
recommended by neovim is significantly behind. If that is the case for you,
pick one of the following methods that are known to deliver fresh neovim versions very quickly.
They have been picked for their popularity and because they make installing and updating
neovim to the latest versions easy. You can also find more detail about the
available methods being discussed
[here](https://github.com/nvim-lua/kickstart.nvim/issues/1583).


<details><summary>Bob</summary>

[Bob](https://github.com/MordechaiHadad/bob) is a Neovim version manager for
all platforms. Simply install
[rustup](https://rust-lang.github.io/rustup/installation/other.html),
and run the following commands:

```bash
rustup default stable
rustup update stable
cargo install bob-nvim
bob use stable
```

</details>

<details><summary>Homebrew</summary>

[Homebrew](https://brew.sh) is a package manager popular on Mac and Linux.
Simply install using [`brew install`](https://formulae.brew.sh/formula/neovim).

</details>

<details><summary>Flatpak</summary>

Flatpak is a package manager for applications that allows developers to package their applications
just once to make it available on all Linux systems. Simply [install flatpak](https://flatpak.org/setup/)
and setup [flathub](https://flathub.org/setup) to [install neovim](https://flathub.org/apps/io.neovim.nvim).

</details>

<details><summary>asdf and mise-en-place</summary>

[asdf](https://asdf-vm.com/) and [mise](https://mise.jdx.dev/) are tool version managers,
mostly aimed towards project-specific tool versioning. However both support managing tools
globally in the user-space as well:

<details><summary>mise</summary>

[Install mise](https://mise.jdx.dev/getting-started.html), then run:

```bash
mise plugins install neovim
mise use neovim@stable
```

</details>

<details><summary>asdf</summary>

[Install asdf](https://asdf-vm.com/guide/getting-started.html), then run:

```bash
asdf plugin add neovim
asdf install neovim stable
asdf set neovim stable --home
asdf reshim neovim
```

</details>

</details>
