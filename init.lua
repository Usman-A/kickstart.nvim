--[[

=====================================================================
==================== READ THIS BEFORE CONTINUING ====================
=====================================================================
========                                    .-----.          ========
========         .----------------------.   | === |          ========
========         |.-""""""""""""""""""-.|   |-----|          ========
========         ||                    ||   | === |          ========
========         ||   KICKSTART.NVIM   ||   |-----|          ========
========         ||                    ||   | === |          ========
========         ||                    ||   |-----|          ========
========         ||:Tutor              ||   |:::::|          ========
========         |'-..................-'|   |____o|          ========
========         `"")----------------(""`   ___________      ========
========        /::::::::::|  |::::::::::\  \ no mouse \     ========
========       /:::========|  |==hjkl==:::\  \ required \    ========
========      '""""""""""""'  '""""""""""""'  '""""""""""'   ========
========                                                     ========
=====================================================================
=====================================================================

What is Kickstart?

  Kickstart.nvim is *not* a distribution.

  Kickstart.nvim is a starting point for your own configuration.
    The goal is that you can read every line of code, top-to-bottom, understand
    what your configuration is doing, and modify it to suit your needs.

    Once you've done that, you can start exploring, configuring and tinkering to
    make Neovim your own! That might mean leaving Kickstart just the way it is for a while
    or immediately breaking it into modular pieces. It's up to you!

    If you don't know anything about Lua, I recommend taking some time to read through
    a guide. One possible example which will only take 10-15 minutes:
      - https://learnxinyminutes.com/docs/lua/

    After understanding a bit more about Lua, you can use `:help lua-guide` as a
    reference for how Neovim integrates Lua.
    - :help lua-guide
    - (or HTML version): https://neovim.io/doc/user/lua-guide.html

Kickstart Guide:

  TODO: The very first thing you should do is to run the command `:Tutor` in Neovim.

    If you don't know what this means, type the following:
      - <escape key>
      - :
      - Tutor
      - <enter key>

    (If you already know the Neovim basics, you can skip this step.)

  Once you've completed that, you can continue working through **AND READING** the rest
  of the kickstart init.lua.

  Next, run AND READ `:help`.
    This will open up a help window with some basic information
    about reading, navigating and searching the builtin help documentation.

    This should be the first place you go to look when you're stuck or confused
    with something. It's one of my favorite Neovim features.

    MOST IMPORTANTLY, we provide a keymap "<space>sh" to [s]earch the [h]elp documentation,
    which is very useful when you're not exactly sure of what you're looking for.

  I have left several `:help X` comments throughout the init.lua
    These are hints about where to find more information about the relevant settings,
    plugins or Neovim features used in Kickstart.

   NOTE: Look for lines like this

    Throughout the file. These are for you, the reader, to help you understand what is happening.
    Feel free to delete them once you know what you're doing, but they should serve as a guide
    for when you are first encountering a few different constructs in your Neovim config.

If you experience any errors while trying to install kickstart, run `:checkhealth` for more info.

I hope you enjoy your Neovim journey,
- TJ

P.S. You can delete this when you're done too. It's your config now! :)
--]]

-- ============================================================
-- SECTION 0: PLATFORM DETECTION
-- This config is dual-target: it runs on Linux/macOS and on native Windows.
-- Anything OS-specific below branches on these flags rather than assuming *nix.
-- Run machine-setup.sh (Linux/macOS) or machine-setup.ps1 (Windows) for system deps.
-- ============================================================
-- Captured as early as possible so the dashboard can report startup time
-- without lazy.nvim's stats module. See the dashboard section in SECTION 4.
local startup_ns = vim.uv.hrtime()

local is_win = vim.fn.has 'win32' == 1
local is_mac = vim.fn.has 'mac' == 1
local is_wsl = not is_win and (vim.fn.has 'wsl' == 1 or (vim.uv.os_uname().release or ''):lower():find 'microsoft' ~= nil)

-- The tree-sitter CLI shells out to `cc` (or MSVC `cl`) to compile parsers.
-- MinGW/WinLibs ships `gcc` only, so parser builds fail with a bare
-- "Error: program not found". Point CC at gcc for Neovim's child processes
-- rather than setting a machine-wide variable or requiring a multi-GB
-- Visual Studio Build Tools install. Only applies when nothing else is found.
if is_win and vim.fn.executable 'cc' == 0 and vim.fn.executable 'cl' == 0 and vim.fn.executable 'gcc' == 1 then
  vim.env.CC = 'gcc'
end

-- ============================================================
-- SECTION 1: OPTIONS
-- Core Neovim settings, leaders, options
-- ============================================================
do
  -- Enable faster startup by caching compiled Lua modules
  vim.loader.enable()

  -- Set <space> as the leader key
  -- See `:help mapleader`
  --  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
  vim.g.mapleader = ' '
  vim.g.maplocalleader = ' '

  -- Set to true if you have a Nerd Font installed and selected in the terminal
  vim.g.have_nerd_font = false

  -- [[ Setting options ]]
  --  See `:help vim.o`
  -- NOTE: You can change these options as you wish!
  --  For more options, you can see `:help option-list`

  -- Make line numbers default
  vim.o.number = true
  -- You can also add relative line numbers, to help with jumping.
  --  Experiment for yourself to see if you like it!
  -- vim.o.relativenumber = true

  -- Enable mouse mode, can be useful for resizing splits for example!
  vim.o.mouse = 'a'

  -- Don't show the mode, since it's already in the status line
  vim.o.showmode = false

  -- Sync clipboard between OS and Neovim.
  --  Schedule the setting after `UiEnter` because it can increase startup-time.
  --  Remove this option if you want your OS clipboard to remain independent.
  --  See `:help 'clipboard'`
  vim.schedule(function() vim.o.clipboard = 'unnamedplus' end)

  -- Under WSL there is no X/Wayland clipboard, so `unnamedplus` silently does
  -- nothing unless we bridge to the Windows clipboard. Prefer win32yank (fast,
  -- and handles paste); otherwise fall back to clip.exe + powershell, which is
  -- always available but cannot round-trip as cleanly.
  -- Native Windows and desktop Linux/macOS need none of this.
  if is_wsl then
    if vim.fn.executable 'win32yank.exe' == 1 then
      vim.g.clipboard = {
        name = 'win32yank-wsl',
        copy = { ['+'] = { 'win32yank.exe', '-i', '--crlf' }, ['*'] = { 'win32yank.exe', '-i', '--crlf' } },
        paste = { ['+'] = { 'win32yank.exe', '-o', '--lf' }, ['*'] = { 'win32yank.exe', '-o', '--lf' } },
        cache_enabled = false,
      }
    elseif vim.fn.executable 'clip.exe' == 1 then
      vim.g.clipboard = {
        name = 'wsl-clip.exe',
        copy = { ['+'] = { 'clip.exe' }, ['*'] = { 'clip.exe' } },
        paste = {
          ['+'] = { 'powershell.exe', '-NoLogo', '-NoProfile', '-Command', '[Console]::Out.Write($(Get-Clipboard -Raw))' },
          ['*'] = { 'powershell.exe', '-NoLogo', '-NoProfile', '-Command', '[Console]::Out.Write($(Get-Clipboard -Raw))' },
        },
        cache_enabled = true,
      }
    end
  end

  -- Enable break indent
  vim.o.breakindent = true

  -- Enable undo/redo changes even after closing and reopening a file
  vim.o.undofile = true

  -- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
  vim.o.ignorecase = true
  vim.o.smartcase = true

  -- Keep signcolumn on by default
  vim.o.signcolumn = 'yes'

  -- Decrease update time
  vim.o.updatetime = 250

  -- Decrease mapped sequence wait time
  vim.o.timeoutlen = 300

  -- Configure how new splits should be opened
  vim.o.splitright = true
  vim.o.splitbelow = true

  -- Sets how neovim will display certain whitespace characters in the editor.
  --  See `:help 'list'`
  --  and `:help 'listchars'`
  --
  --  Notice listchars is set using `vim.opt` instead of `vim.o`.
  --  It is very similar to `vim.o` but offers an interface for conveniently interacting with tables.
  --   See `:help lua-options`
  --   and `:help lua-guide-options`
  vim.o.list = true
  vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

  -- Preview substitutions live, as you type!
  vim.o.inccommand = 'split'

  -- Show which line your cursor is on
  vim.o.cursorline = true

  -- Minimal number of screen lines to keep above and below the cursor.
  vim.o.scrolloff = 10

  -- if performing an operation that would fail due to unsaved changes in the buffer (like `:q`),
  -- instead raise a dialog asking if you wish to save the current file(s)
  -- See `:help 'confirm'`
  vim.o.confirm = true
end

-- ============================================================
-- SECTION 2: KEYMAPS & AUTOCMDS
-- basic keymaps, basic autocmds
-- ============================================================
do
  -- [[ Basic Keymaps ]]
  --  See `:help vim.keymap.set()`

  -- Clear highlights on search when pressing <Esc> in normal mode
  --  See `:help hlsearch`
  vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

  -- Diagnostic Config & Keymaps
  --  See `:help vim.diagnostic.Opts`
  vim.diagnostic.config {
    update_in_insert = false,
    severity_sort = true,
    float = { border = 'rounded', source = 'if_many' },
    underline = { severity = { min = vim.diagnostic.severity.WARN } },

    -- Can switch between these as you prefer
    virtual_text = true, -- Text shows up at the end of the line
    virtual_lines = false, -- Text shows up underneath the line, with virtual lines

    -- Auto open the float, so you can easily read the errors when jumping with `[d` and `]d`
    jump = {
      on_jump = function(_, bufnr)
        vim.diagnostic.open_float {
          bufnr = bufnr,
          scope = 'cursor',
          focus = false,
        }
      end,
    },
  }

  vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

  -- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
  -- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
  -- is not what someone will guess without a bit more experience.
  --
  -- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
  -- or just use <C-\><C-n> to exit terminal mode
  vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

  -- TIP: Disable arrow keys in normal mode
  -- vim.keymap.set('n', '<left>', '<cmd>echo "Use h to move!!"<CR>')
  -- vim.keymap.set('n', '<right>', '<cmd>echo "Use l to move!!"<CR>')
  -- vim.keymap.set('n', '<up>', '<cmd>echo "Use k to move!!"<CR>')
  -- vim.keymap.set('n', '<down>', '<cmd>echo "Use j to move!!"<CR>')

  -- Keybinds to make split navigation easier.
  --  Use CTRL+<hjkl> to switch between windows
  --
  --  See `:help wincmd` for a list of all window commands
  vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
  vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
  vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
  vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

  -- NOTE: Some terminals have colliding keymaps or are not able to send distinct keycodes
  -- vim.keymap.set("n", "<C-S-h>", "<C-w>H", { desc = "Move window to the left" })
  -- vim.keymap.set("n", "<C-S-l>", "<C-w>L", { desc = "Move window to the right" })
  -- vim.keymap.set("n", "<C-S-j>", "<C-w>J", { desc = "Move window to the lower" })
  -- vim.keymap.set("n", "<C-S-k>", "<C-w>K", { desc = "Move window to the upper" })

  -- [[ Basic Autocommands ]]
  --  See `:help lua-guide-autocommands`

  -- Highlight when yanking (copying) text
  --  Try it with `yap` in normal mode
  --  See `:help vim.hl.on_yank()`
  vim.api.nvim_create_autocmd('TextYankPost', {
    desc = 'Highlight when yanking (copying) text',
    group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
    callback = function() vim.hl.on_yank() end,
  })
end

-- ============================================================
-- SECTION 3: PLUGIN MANAGER INTRO
-- vim.pack intro, build hooks
-- ============================================================
do
  -- [[ Intro to `vim.pack` ]]
  -- `vim.pack` is a new plugin manager built into Neovim,
  --  which provides a Lua interface for installing and managing plugins.
  --
  --  See `:help vim.pack`, `:help vim.pack-examples` or the
  --  excellent blog post from the creator of vim.pack and mini.nvim:
  --  https://echasnovski.com/blog/2026-03-13-a-guide-to-vim-pack
  --
  --  To inspect plugin state and pending updates, run
  --    :lua vim.pack.update(nil, { offline = true })
  --
  --  To update plugins, run
  --    :lua vim.pack.update()
  --
  --
  --  Throughout the rest of the config there will be examples
  --  of how to install and configure plugins using `vim.pack`.
  --
  --  In this section we set up some autocommands to run build
  --  steps for certain plugins after they are installed or updated.

  local function run_build(name, cmd, cwd)
    local result = vim.system(cmd, { cwd = cwd }):wait()
    if result.code ~= 0 then
      local stderr = result.stderr or ''
      local stdout = result.stdout or ''
      local output = stderr ~= '' and stderr or stdout
      if output == '' then output = 'No output from build command.' end
      vim.notify(('Build failed for %s:\n%s'):format(name, output), vim.log.levels.ERROR)
    end
  end

  -- This autocommand runs after a plugin is installed or updated and
  --  runs the appropriate build command for that plugin if necessary.
  --
  -- See `:help vim.pack-events`
  vim.api.nvim_create_autocmd('PackChanged', {
    callback = function(ev)
      local name = ev.data.spec.name
      local kind = ev.data.kind
      if kind ~= 'install' and kind ~= 'update' then return end

      -- Prefer `make` (present on *nix, and on Windows via choco mingw/make).
      -- Fall back to CMake, which is the supported Windows/MSVC build path.
      if name == 'telescope-fzf-native.nvim' then
        if vim.fn.executable 'make' == 1 then
          run_build(name, { 'make' }, ev.data.path)
        elseif vim.fn.executable 'cmake' == 1 then
          run_build(name, { 'cmake', '-S.', '-Bbuild', '-DCMAKE_BUILD_TYPE=Release' }, ev.data.path)
          run_build(name, { 'cmake', '--build', 'build', '--config', 'Release', '--target', 'install' }, ev.data.path)
        end
        return
      end

      if name == 'LuaSnip' then
        if vim.fn.has 'win32' ~= 1 and vim.fn.executable 'make' == 1 then run_build(name, { 'make', 'install_jsregexp' }, ev.data.path) end
        return
      end

      if name == 'nvim-treesitter' then
        if not ev.data.active then vim.cmd.packadd 'nvim-treesitter' end
        vim.cmd 'TSUpdate'
        return
      end
    end,
  })
end

---Because most plugins are hosted on GitHub, you can use the helper
---function to have less repetition in the following sections.
---@param repo string
---@return string
local function gh(repo) return 'https://github.com/' .. repo end

-- ============================================================
-- SECTION 4: UI / CORE UX PLUGINS
-- guess-indent, gitsigns, which-key, colorscheme, todo-comments, mini modules
-- ============================================================
do
  -- [[ Installing and Configuring Plugins ]]
  --
  -- To install a plugin simply call `vim.pack.add` with its git url.
  -- This will download the default branch of the plugin, which will usually be `main` or `master`
  -- You can also have more advanced specs, which we will talk about later.
  --
  -- For most plugins its not enough to install them, you also need to call their `.setup()` to start them.
  --
  -- For example, lets say we want to install `guess-indent.nvim` - a plugin for
  -- automatically detecting and setting the indentation.
  --
  -- We first install it from https://github.com/NMAC427/guess-indent.nvim
  -- and then call its `setup()` function to start it with default settings.
  vim.pack.add { gh 'NMAC427/guess-indent.nvim' }
  require('guess-indent').setup {}

  -- Here is a more advanced configuration example that passes options to `gitsigns.nvim`
  --
  -- See `:help gitsigns` to understand what each configuration key does.
  -- Adds git related signs to the gutter, as well as utilities for managing changes
  vim.pack.add { gh 'lewis6991/gitsigns.nvim' }
  local gitsigns = require 'gitsigns'
  gitsigns.setup {
    signs = {
      add = { text = '+' }, ---@diagnostic disable-line: missing-fields
      change = { text = '~' }, ---@diagnostic disable-line: missing-fields
      delete = { text = '_' }, ---@diagnostic disable-line: missing-fields
      topdelete = { text = '‾' }, ---@diagnostic disable-line: missing-fields
      changedelete = { text = '~' }, ---@diagnostic disable-line: missing-fields
    },
    -- gitsigns.nvim's recommended keymaps:
    on_attach = function(bufnr)
      -- Navigation
      vim.keymap.set('n', ']c', function()
        if vim.wo.diff then
          vim.cmd.normal { ']c', bang = true }
        else
          gitsigns.nav_hunk 'next'
        end
      end, { desc = 'Jump to next git [c]hange', buf = bufnr })

      vim.keymap.set('n', '[c', function()
        if vim.wo.diff then
          vim.cmd.normal { '[c', bang = true }
        else
          gitsigns.nav_hunk 'prev'
        end
      end, { desc = 'Jump to previous git [c]hange', buf = bufnr })

      -- Visual mode actions
      vim.keymap.set('v', '<leader>hs', function() gitsigns.stage_hunk { vim.fn.line '.', vim.fn.line 'v' } end, { desc = 'git [s]tage hunk', buf = bufnr })
      vim.keymap.set('v', '<leader>hr', function() gitsigns.reset_hunk { vim.fn.line '.', vim.fn.line 'v' } end, { desc = 'git [r]eset hunk', buf = bufnr })
      -- Normal mode actions
      vim.keymap.set('n', '<leader>hs', gitsigns.stage_hunk, { desc = 'git [s]tage hunk', buf = bufnr })
      vim.keymap.set('n', '<leader>hr', gitsigns.reset_hunk, { desc = 'git [r]eset hunk', buf = bufnr })
      vim.keymap.set('n', '<leader>hS', gitsigns.stage_buffer, { desc = 'git [S]tage buffer', buf = bufnr })
      vim.keymap.set('n', '<leader>hR', gitsigns.reset_buffer, { desc = 'git [R]eset buffer', buf = bufnr })
      vim.keymap.set('n', '<leader>hp', gitsigns.preview_hunk, { desc = 'git [p]review hunk', buf = bufnr })
      vim.keymap.set('n', '<leader>hi', gitsigns.preview_hunk_inline, { desc = 'git preview hunk [i]nline', buf = bufnr })
      vim.keymap.set('n', '<leader>hb', function() gitsigns.blame_line { full = true } end, { desc = 'git [b]lame line', buf = bufnr })
      vim.keymap.set('n', '<leader>hd', gitsigns.diffthis, { desc = 'git [d]iff against index', buf = bufnr })
      vim.keymap.set('n', '<leader>hD', function() gitsigns.diffthis '~' end, { desc = 'git [D]iff against last commit', buf = bufnr })
      vim.keymap.set('n', '<leader>hQ', function() gitsigns.setqflist 'all' end, { desc = 'git hunk [Q]uickfix list (all files in repo)', buf = bufnr })
      vim.keymap.set('n', '<leader>hq', gitsigns.setqflist, { desc = 'git hunk [q]uickfix list (all changes in this file)', buf = bufnr })
      -- Toggles
      vim.keymap.set('n', '<leader>tb', gitsigns.toggle_current_line_blame, { desc = '[T]oggle git show [b]lame line', buf = bufnr })
      vim.keymap.set('n', '<leader>tw', gitsigns.toggle_word_diff, { desc = '[T]oggle git intra-line [w]ord diff', buf = bufnr })
      -- Text object
      vim.keymap.set({ 'o', 'x' }, 'ih', gitsigns.select_hunk, { desc = 'text object [i]nside [h]unk', buf = bufnr })
    end,
  }

  -- Useful plugin to show you pending keybinds.
  vim.pack.add { gh 'folke/which-key.nvim' }
  require('which-key').setup {
    -- Delay between pressing a key and opening which-key (milliseconds)
    delay = 0,
    icons = { mappings = vim.g.have_nerd_font },
    -- Document existing key chains
    spec = {
      { '<leader>s', group = '[S]earch', mode = { 'n', 'v' } },
      { '<leader>t', group = '[T]oggle' },
      { '<leader>u', group = '[U]I' },
      { '<leader>l', group = '[L]ive preview' },
      { '<leader>d', group = '[D]atabase', mode = { 'n', 'v' } },
      { '<leader>w', group = '[W]orkspace / session' },
      { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } }, -- Enable gitsigns recommended keymaps first
      { 'gr', group = 'LSP Actions', mode = { 'n' } },
    },
  }

  -- [[ Colorscheme ]]
  -- You can easily change to a different colorscheme.
  -- Change the name of the colorscheme plugin below, and then
  -- change the command under that to load whatever the name of that colorscheme is.
  --
  -- If you want to see what colorschemes are already installed, you can use `:Telescope colorscheme`.
  vim.pack.add { gh 'folke/tokyonight.nvim' }  -- kept installed, easy to switch back
  vim.pack.add { gh 'EdenEast/nightfox.nvim' }

  -- Load the colorscheme. Other nightfox variants: nightfox, nordfox, duskfox, dawnfox, dayfox, terafox
  vim.cmd.colorscheme 'carbonfox'

  -- Highlight todo, notes, etc in comments
  vim.pack.add { gh 'folke/todo-comments.nvim' }
  require('todo-comments').setup { signs = false }

  -- [[ mini.nvim ]]
  --  A collection of various small independent plugins/modules
  vim.pack.add { gh 'nvim-mini/mini.nvim' }

  -- If a nerd font is available, load the icons module for pretty icons in various plugins.
  if vim.g.have_nerd_font then
    require('mini.icons').setup()
    -- Used for backwards compatibility with plugins that require `nvim-web-devicons` (e.g. telescope.nvim)
    MiniIcons.mock_nvim_web_devicons()
  end

  -- Better Around/Inside textobjects
  --
  -- Examples:
  --  - va)  - [V]isually select [A]round [)]paren
  --  - yiiq - [Y]ank [I]nside [I]+1 [Q]uote
  --  - ci'  - [C]hange [I]nside [']quote
  require('mini.ai').setup {
    -- NOTE: Avoid conflicts with the built-in incremental selection mappings on Neovim>=0.12 (see `:help treesitter-incremental-selection`)
    mappings = {
      around_next = 'aa',
      inside_next = 'ii',
    },
    n_lines = 500,
  }

  -- Add/delete/replace surroundings (brackets, quotes, etc.)
  --
  -- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
  -- - sd'   - [S]urround [D]elete [']quotes
  -- - sr)'  - [S]urround [R]eplace [)] [']
  require('mini.surround').setup()

  -- Simple and easy statusline.
  --  You could remove this setup call if you don't like it,
  --  and try some other statusline plugin
  local statusline = require 'mini.statusline'
  -- Set `use_icons` to true if you have a Nerd Font
  statusline.setup { use_icons = vim.g.have_nerd_font }

  -- You can configure sections in the statusline by overriding their
  -- default behavior. For example, here we set the section for
  -- cursor location to LINE:COLUMN
  ---@diagnostic disable-next-line: duplicate-set-field
  statusline.section_location = function() return '%2l:%-2v' end

  -- ... and there is more!
  --  Check out: https://github.com/nvim-mini/mini.nvim

  -- [[ snacks.nvim ]]
  -- A collection of small, focused QoL improvements by folke.
  vim.pack.add { gh 'folke/snacks.nvim' }
  require('snacks').setup {
    bigfile = { enabled = true },            -- disable heavy features for very large files
    -- Sections are spelled out because the DEFAULT set is incompatible with
    -- vim.pack. snacks' built-in `startup` section calls
    -- require('lazy.stats') unconditionally, so on any non-lazy.nvim config
    -- it throws "module 'lazy.stats' not found" from a UIEnter autocommand
    -- every time the dashboard opens. The replacement below reports the same
    -- numbers from vim.pack.get().
    --
    -- Also note `section = 'session'` is pointless here: snacks gates it on
    -- M.have_plugin, which is `package.loaded.lazy and ...`, so it silently
    -- renders nothing without lazy. Use <leader>wl to restore a session.
    dashboard = {
      enabled = true,
      sections = {
        { section = 'header' },
        { section = 'keys', gap = 1, padding = 1 },
        function()
          local plugins = vim.pack.get()
          local active = 0
          for _, p in ipairs(plugins) do
            if p.active then active = active + 1 end
          end
          -- hrtime is nanoseconds; render one decimal place of milliseconds.
          local ms = math.floor((vim.uv.hrtime() - startup_ns) / 1e5 + 0.5) / 10
          return {
            align = 'center',
            text = {
              { (vim.g.have_nerd_font and '󰒲 ' or '') .. 'Neovim loaded ', hl = 'footer' },
              { active .. '/' .. #plugins, hl = 'special' },
              { ' plugins in ', hl = 'footer' },
              { ms .. 'ms', hl = 'special' },
            },
          }
        end,
      },
    },
    notifier = { enabled = true, timeout = 3000 }, -- replaces vim.notify with a styled popup
    quickfile = { enabled = true },          -- open files faster
    scroll = { enabled = true },             -- smooth scrolling
    terminal = { enabled = true },           -- floating terminal
    -- Enabled only for Snacks.picker.projects() (<leader>wp in SECTION 9.7).
    -- ui_select MUST stay false: it defaults to true when the picker is
    -- enabled and would take over vim.ui.select, silently replacing the
    -- telescope-ui-select extension configured in SECTION 5.
    picker = { enabled = true, ui_select = false },
  }

  -- Toggle a floating terminal (quick one-off commands)
  vim.keymap.set({ 'n', 't' }, '<leader>tt', function() Snacks.terminal() end, { desc = '[T]oggle [T]erminal' })
  -- Open a persistent right-side split terminal — run `claude` or any CLI here
  -- Each unique id keeps its own session, so you can have one for claude and one for shell
  vim.keymap.set({ 'n', 't' }, '<leader>ta', function()
    Snacks.terminal(nil, { id = 'ai', win = { position = 'right', width = 0.4 } })
  end, { desc = '[T]erminal: [A]I / side panel' })
  vim.keymap.set({ 'n', 't' }, '<leader>ts', function()
    Snacks.terminal(nil, { id = 'shell', win = { position = 'bottom', height = 0.3 } })
  end, { desc = '[T]erminal: [S]hell (bottom)' })
  -- Dismiss all visible notifications
  vim.keymap.set('n', '<leader>un', function() Snacks.notifier.hide() end, { desc = '[U]I: dismiss [N]otifications' })

  -- [[ vim-be-good ]]
  -- A game for practising Vim motions. Run :VimBeGood to start.
  vim.pack.add { gh 'ThePrimeagen/vim-be-good' }
end

-- ============================================================
-- SECTION 5: SEARCH & NAVIGATION
-- Telescope setup, keymaps, LSP picker mappings
-- ============================================================
do
  -- [[ Fuzzy Finder (files, lsp, etc) ]]
  --
  -- Telescope is a fuzzy finder that comes with a lot of different things that
  -- it can fuzzy find! It's more than just a "file finder", it can search
  -- many different aspects of Neovim, your workspace, LSP, and more!
  --
  -- There are lots of other alternative pickers (like snacks.picker, or fzf-lua)
  -- so feel free to experiment and see what you like!
  --
  -- The easiest way to use Telescope, is to start by doing something like:
  --  :Telescope help_tags
  --
  -- After running this command, a window will open up and you're able to
  -- type in the prompt window. You'll see a list of `help_tags` options and
  -- a corresponding preview of the help.
  --
  -- Two important keymaps to use while in Telescope are:
  --  - Insert mode: <c-/>
  --  - Normal mode: ?
  --
  -- This opens a window that shows you all of the keymaps for the current
  -- Telescope picker. This is really useful to discover what Telescope can
  -- do as well as how to actually do it!

  ---@type (string|vim.pack.Spec)[]
  local telescope_plugins = {
    gh 'nvim-lua/plenary.nvim',
    gh 'nvim-telescope/telescope.nvim',
    gh 'nvim-telescope/telescope-ui-select.nvim',
  }
  -- fzf-native is a compiled extension: include it only if we can actually build it.
  -- `make` on *nix / choco-mingw, or `cmake` on Windows with MSVC.
  if vim.fn.executable 'make' == 1 or vim.fn.executable 'cmake' == 1 then
    table.insert(telescope_plugins, gh 'nvim-telescope/telescope-fzf-native.nvim')
  end

  -- NOTE: You can install multiple plugins at once
  vim.pack.add(telescope_plugins)

  -- See `:help telescope` and `:help telescope.setup()`
  require('telescope').setup {
    -- You can put your default mappings / updates / etc. in here
    --  All the info you're looking for is in `:help telescope.setup()`
    --
    -- defaults = {
    --   mappings = {
    --     i = { ['<c-enter>'] = 'to_fuzzy_refine' },
    --   },
    -- },
    -- pickers = {}
    extensions = {
      ['ui-select'] = { require('telescope.themes').get_dropdown() },
    },
  }

  -- Enable Telescope extensions if they are installed
  pcall(require('telescope').load_extension, 'fzf')
  pcall(require('telescope').load_extension, 'ui-select')

  -- See `:help telescope.builtin`
  local builtin = require 'telescope.builtin'
  vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
  vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
  vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
  vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
  vim.keymap.set({ 'n', 'v' }, '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
  vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
  vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
  vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
  vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
  vim.keymap.set('n', '<leader>sc', builtin.commands, { desc = '[S]earch [C]ommands' })
  vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })

  -- Add Telescope-based LSP pickers when an LSP attaches to a buffer.
  -- If you later switch picker plugins, this is where to update these mappings.
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('telescope-lsp-attach', { clear = true }),
    callback = function(event)
      local buf = event.buf

      -- Find references for the word under your cursor.
      vim.keymap.set('n', 'grr', builtin.lsp_references, { buffer = buf, desc = '[G]oto [R]eferences' })

      -- Jump to the implementation of the word under your cursor.
      -- Useful when your language has ways of declaring types without an actual implementation.
      vim.keymap.set('n', 'gri', builtin.lsp_implementations, { buffer = buf, desc = '[G]oto [I]mplementation' })

      -- Jump to the definition of the word under your cursor.
      -- This is where a variable was first declared, or where a function is defined, etc.
      -- To jump back, press <C-t>.
      vim.keymap.set('n', 'grd', builtin.lsp_definitions, { buffer = buf, desc = '[G]oto [D]efinition' })

      -- Fuzzy find all the symbols in your current document.
      -- Symbols are things like variables, functions, types, etc.
      vim.keymap.set('n', 'gO', builtin.lsp_document_symbols, { buffer = buf, desc = 'Open Document Symbols' })

      -- Fuzzy find all the symbols in your current workspace.
      -- Similar to document symbols, except searches over your entire project.
      vim.keymap.set('n', 'gW', builtin.lsp_dynamic_workspace_symbols, { buffer = buf, desc = 'Open Workspace Symbols' })

      -- Jump to the type of the word under your cursor.
      -- Useful when you're not sure what type a variable is and you want to see
      -- the definition of its *type*, not where it was *defined*.
      vim.keymap.set('n', 'grt', builtin.lsp_type_definitions, { buffer = buf, desc = '[G]oto [T]ype Definition' })
    end,
  })

  -- Override default behavior and theme when searching
  vim.keymap.set('n', '<leader>/', function()
    -- You can pass additional configuration to Telescope to change the theme, layout, etc.
    builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
      winblend = 10,
      previewer = false,
    })
  end, { desc = '[/] Fuzzily search in current buffer' })

  -- It's also possible to pass additional configuration options.
  --  See `:help telescope.builtin.live_grep()` for information about particular keys
  vim.keymap.set(
    'n',
    '<leader>s/',
    function()
      builtin.live_grep {
        grep_open_files = true,
        prompt_title = 'Live Grep in Open Files',
      }
    end,
    { desc = '[S]earch [/] in Open Files' }
  )

  -- Shortcut for searching your Neovim configuration files
  vim.keymap.set('n', '<leader>sn', function() builtin.find_files { cwd = vim.fn.stdpath 'config', follow = true } end, { desc = '[S]earch [N]eovim files' })
end

-- ============================================================
-- SECTION 6: LSP
-- LSP keymaps, server configuration, Mason tools installations
-- ============================================================
do
  -- [[ LSP Configuration ]]
  -- Brief aside: **What is LSP?**
  --
  -- LSP is an initialism you've probably heard, but might not understand what it is.
  --
  -- LSP stands for Language Server Protocol. It's a protocol that helps editors
  -- and language tooling communicate in a standardized fashion.
  --
  -- In general, you have a "server" which is some tool built to understand a particular
  -- language (such as `gopls`, `lua_ls`, `rust_analyzer`, etc.). These Language Servers
  -- (sometimes called LSP servers, but that's kind of like ATM Machine) are standalone
  -- processes that communicate with some "client" - in this case, Neovim!
  --
  -- LSP provides Neovim with features like:
  --  - Go to definition
  --  - Find references
  --  - Autocompletion
  --  - Symbol Search
  --  - and more!
  --
  -- Thus, Language Servers are external tools that must be installed separately from
  -- Neovim. This is where `mason` and related plugins come into play.
  --
  -- If you're wondering about lsp vs treesitter, you can check out the wonderfully
  -- and elegantly composed help section, `:help lsp-vs-treesitter`

  -- Useful status updates for LSP.
  vim.pack.add { gh 'j-hui/fidget.nvim' }
  require('fidget').setup {}

  --  This function gets run when an LSP attaches to a particular buffer.
  --    That is to say, every time a new file is opened that is associated with
  --    an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
  --    function will be executed to configure the current buffer
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
    callback = function(event)
      -- NOTE: Remember that Lua is a real programming language, and as such it is possible
      -- to define small helper and utility functions so you don't have to repeat yourself.
      --
      -- In this case, we create a function that lets us more easily define mappings specific
      -- for LSP related items. It sets the mode, buffer and description for us each time.
      local map = function(keys, func, desc, mode)
        mode = mode or 'n'
        vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
      end

      -- Rename the variable under your cursor.
      --  Most Language Servers support renaming across files, etc.
      map('grn', vim.lsp.buf.rename, '[R]e[n]ame')

      -- Execute a code action, usually your cursor needs to be on top of an error
      -- or a suggestion from your LSP for this to activate.
      map('gra', vim.lsp.buf.code_action, '[G]oto Code [A]ction', { 'n', 'x' })

      -- WARN: This is not Goto Definition, this is Goto Declaration.
      --  For example, in C this would take you to the header.
      map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

      -- The following two autocommands are used to highlight references of the
      -- word under your cursor when your cursor rests there for a little while.
      --    See `:help CursorHold` for information about when this is executed
      --
      -- When you move your cursor, the highlights will be cleared (the second autocommand).
      local client = vim.lsp.get_client_by_id(event.data.client_id)
      if client and client:supports_method('textDocument/documentHighlight', event.buf) then
        local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
          buffer = event.buf,
          group = highlight_augroup,
          callback = vim.lsp.buf.document_highlight,
        })

        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
          buffer = event.buf,
          group = highlight_augroup,
          callback = vim.lsp.buf.clear_references,
        })

        vim.api.nvim_create_autocmd('LspDetach', {
          group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
          callback = function(event2)
            vim.lsp.buf.clear_references()
            vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
          end,
        })
      end

      -- The following code creates a keymap to toggle inlay hints in your
      -- code, if the language server you are using supports them
      --
      -- This may be unwanted, since they displace some of your code
      if client and client:supports_method('textDocument/inlayHint', event.buf) then
        map('<leader>th', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf }) end, '[T]oggle Inlay [H]ints')
      end
    end,
  })

  -- Enable the following language servers
  --  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
  --  See `:help lsp-config` for information about keys and how to configure
  ---@type table<string, vim.lsp.Config>
  local servers = {
    clangd = {}, -- C and C++

    gopls = {}, -- Go

    rust_analyzer = {}, -- Rust (binary provided by rustup; Mason installs a fallback)

    omnisharp = {}, -- C# (requires .NET SDK on the machine)

    jdtls = {}, -- Java (requires JDK on the machine)

    marksman = {}, -- Markdown

    dockerls = {}, -- Dockerfile

    docker_compose_language_service = {}, -- docker-compose.yml

    html = {},   -- HTML LSP
    cssls = {},  -- CSS LSP

    texlab = {}, -- LaTeX LSP

    -- Some languages (like typescript) have entire language plugins that can be useful:
    --    https://github.com/pmizio/typescript-tools.nvim
    --
    -- But for many setups, the LSP (`ts_ls`) will work just fine
    -- ts_ls = {},

    pyright = {
      settings = {
        pyright = {
          disableOrganizeImports = true, -- ruff handles imports
        },
      },
    },

    ruff = {}, -- formatting + import sorting LSP (lint handled by pylint)

    stylua = {}, -- Used to format Lua code

    -- Special Lua Config, as recommended by neovim help docs
    lua_ls = {
      on_init = function(client)
        client.server_capabilities.documentFormattingProvider = false -- Disable formatting (formatting is done by stylua)

        if client.workspace_folders then
          local path = client.workspace_folders[1].name
          if path ~= vim.fn.stdpath 'config' and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc')) then return end
        end

        local current_settings = client.config.settings --[[@as lspconfig.settings.lua_ls]]
        client.config.settings.Lua = vim.tbl_deep_extend('force', current_settings.Lua, {
          runtime = {
            version = 'LuaJIT',
            path = { 'lua/?.lua', 'lua/?/init.lua' },
          },
          workspace = {
            checkThirdParty = false,
            -- NOTE: this is a lot slower and will cause issues when working on your own configuration.
            --  See https://github.com/neovim/nvim-lspconfig/issues/3189
            -- Deliberate divergence from upstream: bd53f28 dropped the '${3rd}'
            -- paths outright, on the grounds that luv/busted "are not really
            -- relevant for neovim configs". This config leans on vim.uv (see
            -- SECTION 0 and the on_init above), so the luv definitions earn
            -- their keep -- they are what makes vim.uv complete and type-check.
            -- NOTE: list_extend, NOT tbl_extend. `vim.tbl_extend` merges by KEY,
            -- so on two list-like tables it overwrites indices 1..n of the
            -- runtime-file list with the '${3rd}' entries, silently dropping two
            -- real runtime paths. That was the bug bd53f28 fixed.
            library = vim.list_extend(vim.api.nvim_get_runtime_file('', true), {
              '${3rd}/luv/library',
              '${3rd}/busted/library',
            }),
          },
        })
      end,
      ---@type lspconfig.settings.lua_ls
      settings = {
        Lua = {
          format = { enable = false }, -- Disable formatting (formatting is done by stylua)
        },
      },
    },
  }

  vim.pack.add {
    gh 'neovim/nvim-lspconfig',
    gh 'mason-org/mason.nvim',
    gh 'mason-org/mason-lspconfig.nvim',
    gh 'WhoIsSethDaniel/mason-tool-installer.nvim',
  }

  -- Automatically install LSPs and related tools to stdpath for Neovim
  require('mason').setup {}

  -- Translates between nvim-lspconfig server names and mason.nvim package names (e.g. lua_ls <-> lua-language-server)
  require('mason-lspconfig').setup {
    automatic_enable = false, -- Change this to true if you want to automatically enable servers that are installed manually (e.g. via :Mason / :MasonInstall)
  }

  -- Ensure the servers and tools above are installed
  --
  -- To check the current status of installed tools and/or manually install
  -- other tools, you can run
  --    :Mason
  --
  -- You can press `g?` for help in this menu.
  local ensure_installed = vim.tbl_keys(servers or {})
  vim.list_extend(ensure_installed, {
    'tree-sitter-cli', -- needed by nvim-treesitter to compile parsers
    'pylint', -- Python linter (reads project .pylintrc automatically)
    'goimports', -- Go: organizes imports + formats (replaces gofmt for imports)
    'gofumpt', -- Go: stricter formatter on top of gofmt
    'clang-format', -- C / C++ formatter
    'prettier', -- Markdown formatter
    'csharpier', -- C# formatter
    'latexindent', -- LaTeX formatter
    'sqlfluff', -- Oracle SQL formatter/linter (config: sqlfluff.cfg)
  })

  require('mason-tool-installer').setup { ensure_installed = ensure_installed }

  for name, server in pairs(servers) do
    vim.lsp.config(name, server)
    vim.lsp.enable(name)
  end
end

-- ============================================================
-- SECTION 7: FORMATTING
-- conform.nvim setup and keymap
-- ============================================================
do
  -- [[ Formatting ]]
  vim.pack.add { gh 'stevearc/conform.nvim' }
  require('conform').setup {
    notify_on_error = false,
    -- conform's default, set explicitly for clarity. Note its scope is
    -- narrower than the name suggests: it fires only when a filetype HAS
    -- formatters configured but none are available. A filetype with no
    -- formatters at all stays silent, which is why the <leader>f keymap
    -- below inspects the callback error itself.
    notify_no_formatters = true,
    format_on_save = function(bufnr)
      -- You can specify filetypes to autoformat on save here:
      local enabled_filetypes = {
        -- lua = true,
        -- python = true,
      }
      if enabled_filetypes[vim.bo[bufnr].filetype] then
        -- 500ms (the kickstart default here) is too tight for interpreted
        -- formatters. Measured on this machine, sqlfluff takes 920-1150ms
        -- just to start -- Python interpreter startup, largely independent
        -- of input size -- so it would time out on literally every save,
        -- and conform reports that only in its log. prettier and latexindent
        -- are in similar territory. 3000ms leaves real headroom while still
        -- bailing out if something hangs.
        return { timeout_ms = 3000 }
      else
        return nil
      end
    end,
    default_format_opts = {
      lsp_format = 'fallback', -- Use external formatters if configured below, otherwise use LSP formatting. Set to `false` to disable LSP formatting entirely.
    },
    -- You can also specify external formatters in here.
    formatters_by_ft = {
      -- rust = { 'rustfmt' },
      -- You can use 'stop_after_first' to run the first available formatter from the list
      -- javascript = { "prettierd", "prettier", stop_after_first = true },
      python = { 'ruff_format' },
      go = { 'goimports', 'gofumpt' },
      rust = { 'rustfmt' }, -- rustfmt ships with rustup, not Mason
      c = { 'clang_format' },
      cpp = { 'clang_format' },
      cs = { 'csharpier' },
      markdown = { 'prettier' },
      tex = { 'latexindent' },

      -- Oracle SQL. Deliberately NOT wired up for `plsql`.
      --
      -- sqlfluff's oracle dialect does parse PL/SQL package bodies cleanly
      -- (zero unparsable sections), but `sqlfluff format` corrupts their
      -- layout: it hoists `exception` out to the wrong nesting level and
      -- breaks `select ... where` across lines. Neither
      --   exclude_rules = layout.indent
      -- nor an allowlist of
      --   rules = layout.spacing
      -- prevents it -- `format` always runs its own reindent/reflow pass,
      -- which is not rule-driven and cannot be switched off. So there is no
      -- configuration that makes it safe here.
      --
      -- Consequence: <leader>f on a PL/SQL buffer reports that no formatter
      -- is configured (see the keymap below) rather than quietly mangling
      -- the code. If a real PL/SQL formatter becomes available -- Oracle's
      -- SQLcl has `format buffer` -- wire that up here instead.
      sql = { 'sqlfluff' },
    },
    formatters = {
      -- Pinned to our own config so behaviour is identical in every repo.
      -- Without --config sqlfluff defaults to the `ansi` dialect, which
      -- cannot parse Oracle at all.
      sqlfluff = {
        command = 'sqlfluff',
        -- `format` (not the built-in's `fix`): we want layout changes only,
        -- not rule auto-fixes rewriting existing SQL.
        -- A function, not a table, so the path is resolved at format time.
        -- A machine-local module (see the end of SECTION 9.6) may set
        -- vim.g.sqlfluff_config to point at house-style overrides; absent
        -- that we use the generic Oracle config committed here, so this file
        -- carries no site-specific style.
        args = function()
          local cfg = vim.g.sqlfluff_config or vim.fs.joinpath(vim.fn.stdpath 'config', 'sqlfluff.cfg')
          return { 'format', '--config', cfg, '-' }
        end,
        stdin = true,
        -- IMPORTANT: conform's built-in sqlfluff sets `require_cwd = true`
        -- with a cwd probe for .sqlfluff / pyproject.toml / setup.cfg /
        -- tox.ini. User config is merged ON TOP of that built-in, so without
        -- this override the formatter reports "Root directory not found" and
        -- silently does nothing in any repo lacking one of those files --
        -- <leader>f appears to succeed but the buffer never changes.
        -- We pass --config explicitly, so no project-root probe is needed.
        require_cwd = false,
      },
    },
  }

  -- Report back instead of failing silently.
  --
  -- Two silent-failure modes are worth closing. conform's own
  -- notify_no_formatters only fires when a filetype HAS formatters
  -- configured but none are available -- for a filetype with none at all
  -- (plsql, here) it just returns "No formatters available for buffer" and
  -- says nothing. And `notify_on_error = false` above suppresses real
  -- failures too. Both leave <leader>f looking like it worked.
  vim.keymap.set({ 'n', 'v' }, '<leader>f', function()
    local ft = vim.bo.filetype
    require('conform').format({ async = true }, function(err)
      if not err then return end
      if tostring(err):match 'No formatters available' then
        vim.notify(("No formatter configured for filetype '%s'"):format(ft), vim.log.levels.WARN)
      else
        vim.notify('Format failed: ' .. tostring(err), vim.log.levels.WARN)
      end
    end)
  end, { desc = '[F]ormat buffer' })
end

-- ============================================================
-- SECTION 7.5: LINTING
-- nvim-lint runs pylint on Python files and surfaces results as diagnostics.
-- pylint automatically searches up the directory tree for .pylintrc, so your
-- company's config is picked up without any extra setup here.
-- ============================================================
do
  vim.pack.add { gh 'mfussenegger/nvim-lint' }
  local lint = require 'lint'

  lint.linters_by_ft = {
    python = { 'pylint' },
  }

  vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost', 'InsertLeave' }, {
    group = vim.api.nvim_create_augroup('kickstart-lint', { clear = true }),
    callback = function()
      lint.try_lint()
    end,
  })
end

-- ============================================================
-- SECTION 8: AUTOCOMPLETE & SNIPPETS
-- blink.cmp and luasnip setup
-- ============================================================
do
  -- [[ Snippet Engine ]]

  -- NOTE: You can also specify plugin using a version range for its git tag.
  --  See `:help vim.version.range()` for more info
  vim.pack.add { { src = gh 'L3MON4D3/LuaSnip', version = vim.version.range '2.*' } }
  require('luasnip').setup {}

  -- `friendly-snippets` contains a variety of premade snippets.
  --    See the README about individual language/framework/plugin snippets:
  --    https://github.com/rafamadriz/friendly-snippets
  --
  -- vim.pack.add { gh 'rafamadriz/friendly-snippets' }
  -- require('luasnip.loaders.from_vscode').lazy_load()

  -- [[ Autocomplete Engine ]]
  vim.pack.add { { src = gh 'saghen/blink.cmp', version = vim.version.range '1.*' } }
  require('blink.cmp').setup {
    keymap = {
      -- 'default' (recommended) for mappings similar to built-in completions
      --   <c-y> to accept ([y]es) the completion.
      --    This will auto-import if your LSP supports it.
      --    This will expand snippets if the LSP sent a snippet.
      -- 'super-tab' for tab to accept
      -- 'enter' for enter to accept
      -- 'none' for no mappings
      --
      -- For an understanding of why the 'default' preset is recommended,
      -- you will need to read `:help ins-completion`
      --
      -- No, but seriously. Please read `:help ins-completion`, it is really good!
      --
      -- All presets have the following mappings:
      -- <tab>/<s-tab>: move to right/left of your snippet expansion
      -- <c-space>: Open menu or open docs if already open
      -- <c-n>/<c-p> or <up>/<down>: Select next/previous item
      -- <c-e>: Hide menu
      -- <c-k>: Toggle signature help
      --
      -- See `:help blink-cmp-config-keymap` for defining your own keymap
      preset = 'default',

      -- For more advanced Luasnip keymaps (e.g. selecting choice nodes, expansion) see:
      --    https://github.com/L3MON4D3/LuaSnip?tab=readme-ov-file#keymaps
    },

    appearance = {
      -- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
      -- Adjusts spacing to ensure icons are aligned
      nerd_font_variant = 'mono',
    },

    completion = {
      -- By default, you may press `<c-space>` to show the documentation.
      -- Optionally, set `auto_show = true` to show the documentation after a delay.
      documentation = { auto_show = false, auto_show_delay_ms = 500 },
    },

    sources = {
      default = { 'lsp', 'path', 'snippets' },
    },

    snippets = { preset = 'luasnip' },

    -- Blink.cmp includes an optional, recommended rust fuzzy matcher,
    -- which automatically downloads a prebuilt binary when enabled.
    --
    -- By default, we use the Lua implementation instead, but you may enable
    -- the rust implementation via `'prefer_rust_with_warning'`
    --
    -- See `:help blink-cmp-config-fuzzy` for more information
    fuzzy = { implementation = 'lua' },

    -- Shows a signature help window while you type arguments for a function
    signature = { enabled = true },
  }
end

-- ============================================================
-- SECTION 9: TREESITTER
-- Parser installation, syntax highlighting, folds, indentation
-- ============================================================
do
  -- [[ Configure Treesitter ]]
  --  Used to highlight, edit, and navigate code
  --
  --  See `:help nvim-treesitter-intro`

  -- NOTE: You can also specify a branch or a specific commit
  vim.pack.add { { src = gh 'nvim-treesitter/nvim-treesitter', version = 'main' } }

  -- Ensure basic parsers are installed
  -- NOTE: there is no `plsql` treesitter parser. This `sql` parser handles
  -- plain .sql fine, but chokes on PL/SQL package bodies -- which is why
  -- SECTION 9.6 maps .pks/.pkb/etc to the `plsql` filetype instead, letting
  -- Vim's built-in PL/SQL syntax file handle those.
  local parsers = {
    'bash', 'c', 'c_sharp', 'cpp', 'css', 'diff', 'dockerfile', 'go', 'html',
    'java', 'latex', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'python',
    'query', 'rust', 'sql', 'vim', 'vimdoc',
  }
  -- Parser installation is asynchronous: install() returns immediately and
  -- compiles in the background, so parsers are NOT ready the moment Neovim
  -- opens. On a fresh clone that looks like broken highlighting for the first
  -- minute with nothing explaining why.
  --
  -- So: only ask for the parsers actually missing (avoids needless churn on
  -- every startup), and use the returned Task's :await to report when the
  -- compile finishes -- or why it failed.
  do
    local ts = require 'nvim-treesitter'
    local have = {}
    for _, p in ipairs(ts.get_installed 'parsers') do
      have[p] = true
    end
    local missing = vim.tbl_filter(function(p) return not have[p] end, parsers)

    if #missing > 0 then
      vim.notify(
        ('nvim-treesitter: compiling %d parser%s in the background (%s)')
          :format(#missing, #missing == 1 and '' or 's', table.concat(missing, ', ')),
        vim.log.levels.INFO
      )
      ts.install(missing):await(function(err)
        vim.schedule(function()
          if err then
            -- The usual cause on Windows is no C compiler on PATH: the
            -- tree-sitter CLI shells out to `cc`, which MinGW does not
            -- provide. SECTION 0 sets vim.env.CC = 'gcc' to cover that.
            vim.notify('nvim-treesitter: parser install failed: ' .. tostring(err), vim.log.levels.ERROR)
          else
            vim.notify(('nvim-treesitter: %d parser(s) ready'):format(#missing), vim.log.levels.INFO)
          end
        end)
      end)
    end
  end

  ---@param buf integer
  ---@param language string
  local function treesitter_try_attach(buf, language)
    -- Check if a parser exists and load it
    if not vim.treesitter.language.add(language) then return end
    -- Enable syntax highlighting and other treesitter features
    vim.treesitter.start(buf, language)

    -- Enable treesitter based folds
    -- For more info on folds see `:help folds`
    -- vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    -- vim.wo.foldmethod = 'expr'

    -- Check if treesitter indentation is available for this language, and if so enable it
    -- in case there is no indent query, the indentexpr will fallback to the vim's built in one
    local has_indent_query = vim.treesitter.query.get(language, 'indents') ~= nil

    -- Enable treesitter based indentation
    if has_indent_query then vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()" end
  end

  local available_parsers = require('nvim-treesitter').get_available()
  vim.api.nvim_create_autocmd('FileType', {
    callback = function(args)
      local buf, filetype = args.buf, args.match

      local language = vim.treesitter.language.get_lang(filetype)
      if not language then return end

      local installed_parsers = require('nvim-treesitter').get_installed 'parsers'

      if vim.tbl_contains(installed_parsers, language) then
        -- Enable the parser if it is already installed
        treesitter_try_attach(buf, language)
      elseif vim.tbl_contains(available_parsers, language) then
        -- If a parser is available in `nvim-treesitter`, auto-install it and enable it after the installation is done
        require('nvim-treesitter').install(language):await(function() treesitter_try_attach(buf, language) end)
      else
        -- Try to enable treesitter features in case the parser exists but is not available from `nvim-treesitter`
        treesitter_try_attach(buf, language)
      end
    end,
  })
end

-- ============================================================
-- SECTION 9.5: WRITING, DOCUMENTS & FILE NAVIGATION
-- render-markdown, obsidian.nvim, vimtex, live-server, yazi
-- ============================================================
do
  -- [[ Inline Markdown rendering ]]
  -- Renders markdown headers, bold, italic, code blocks etc. visually inside the buffer.
  -- Works for any .md file, not just Obsidian notes.
  vim.pack.add { gh 'MeanderingProgrammer/render-markdown.nvim' }
  require('render-markdown').setup {}

  -- [[ Obsidian vault integration ]]
  -- Wiki links, tags, backlinks, daily notes, search across your vault.
  -- Set the OBSIDIAN_VAULT env var on each machine, or change the fallback below.
  -- `vim.fs.normalize` keeps the path sane on Windows (forward slashes, ~ expanded),
  -- and we create the directory if missing so obsidian.nvim doesn't error on startup.
  local vault = vim.fs.normalize(vim.env.OBSIDIAN_VAULT or '~/obsidian')
  if vim.fn.isdirectory(vault) == 0 then vim.fn.mkdir(vault, 'p') end

  vim.pack.add { gh 'obsidian-nvim/obsidian.nvim' }
  require('obsidian').setup {
    workspaces = {
      {
        name = 'vault',
        path = vault,
      },
    },
    ui = { enable = false }, -- render-markdown.nvim handles visuals
  }

  -- [[ LaTeX ]]
  -- vimtex provides compilation (\ll), PDF viewer (\lv), and navigation.
  -- Per-machine system deps:
  --   Linux   : texlive + latexmk + zathura   (apt/pacman)
  --   macOS   : mactex-no-gui + Skim          (brew)
  --   Windows : MiKTeX (ships latexmk) + SumatraPDF  (winget)
  -- SumatraPDF is the Windows viewer that supports vimtex forward/inverse search;
  -- zathura has no usable native Windows build.
  vim.pack.add { gh 'lervag/vimtex' }
  vim.g.vimtex_view_method = (is_win and 'sumatrapdf') or (is_mac and 'skim') or 'zathura'
  vim.g.vimtex_compiler_method = 'latexmk'

  -- [[ HTML live preview ]]
  -- Opens current HTML file in the browser with live reload on save.
  -- Per-machine dep: npm install -g live-server
  vim.pack.add { gh 'barrett-ruth/live-server.nvim' }
  require('live-server').setup {}
  vim.keymap.set('n', '<leader>lh', '<cmd>LiveServerStart<cr>', { desc = '[L]ive [H]TML preview start' })
  vim.keymap.set('n', '<leader>lH', '<cmd>LiveServerStop<cr>', { desc = '[L]ive [H]TML preview stop' })

  -- [[ Yazi file manager ]]
  -- Floating file manager with image previews, bulk rename, etc.
  -- Replaces a traditional file tree.
  -- Per-machine dep: install yazi (https://github.com/sxyazi/yazi)
  --   Linux/macOS : cargo install yazi-fm yazi-cli  (or brew/pacman)
  --   Windows     : winget install sxyazi.yazi
  --
  -- Only wire this up if the binary actually exists. Otherwise
  -- `open_for_directories` would hijack `nvim .` and leave you with a broken
  -- explorer and no netrw fallback.
  if vim.fn.executable 'yazi' == 1 then
    vim.pack.add { gh 'mikavilpas/yazi.nvim' }
    require('yazi').setup {
      open_for_directories = true, -- `nvim .` opens yazi instead of netrw
    }
    vim.keymap.set('n', '<leader>e', '<cmd>Yazi<cr>', { desc = 'Open [E]xplorer (Yazi)' })
    vim.keymap.set('n', '<leader>E', '<cmd>Yazi cwd<cr>', { desc = 'Open [E]xplorer at cwd' })
  end
end

-- ============================================================
-- SECTION 9.6: DATABASE / ORACLE SQL
-- vim-dadbod, dadbod-ui, dadbod-completion, PL/SQL filetypes
-- ============================================================
do
  -- [[ Oracle / SQL client ]]
  -- dadbod runs queries from a buffer and renders results in a split. For
  -- Oracle it shells out to `sqlplus`, so that must be on PATH (it ships with
  -- the Oracle client / Instant Client).
  --
  --   <leader>du  toggle the DBUI sidebar (schemas, tables, saved queries)
  --   <leader>df  jump to the DBUI query buffer
  --   <leader>dr  run the query under the cursor, or the visual selection
  --
  -- There is deliberately NO Oracle language server configured. `sqlls` only
  -- understands generic ANSI SQL -- it cannot resolve packages, %ROWTYPE or
  -- schema objects, so it would produce noise rather than useful diagnostics.
  vim.pack.add {
    gh 'tpope/vim-dadbod',
    gh 'kristijanhusak/vim-dadbod-ui',
    gh 'kristijanhusak/vim-dadbod-completion',
  }

  -- Connections are deliberately empty here. Never put a connection string
  -- in this repo -- not even a hostname. Populate it either:
  --   * interactively, with `A` in the DBUI sidebar. Those are saved under
  --     stdpath('data')/db_ui, which is outside this git repo; or
  --   * from the gitignored machine-local module, which can read them from
  --     the environment, e.g.
  --       vim.g.dbs = { mydb = vim.env.MYDB_URL }
  --     with MYDB_URL set to something like
  --       oracle:user/password@host:1521/servicename
  --
  -- NOTE: dadbod's oracle adapter cannot do Oracle wallet auth. Its
  -- db#adapter#oracle#interactive() always builds `user/password@host` and
  -- defaults to `system/oracle`, with no code path emitting the `/@ALIAS`
  -- form a wallet needs. If your site uses a wallet, drive sqlplus directly
  -- from the machine-local module instead of through dadbod.
  vim.g.dbs = {}

  vim.g.db_ui_win_position = 'left'
  vim.g.db_ui_use_nerd_fonts = vim.g.have_nerd_font and 1 or 0
  vim.g.db_ui_show_database_icon = 1
  vim.g.db_ui_save_location = vim.fs.joinpath(vim.fn.stdpath 'data', 'db_ui')

  -- IMPORTANT: dadbod-ui defaults this to 1, which executes the ENTIRE buffer
  -- as a query every time you `:w`. On a shared dev database that is a nasty
  -- surprise, so require an explicit run instead.
  vim.g.db_ui_execute_on_save = 0

  vim.keymap.set('n', '<leader>du', '<cmd>DBUIToggle<cr>', { desc = '[D]atabase: toggle [U]I' })
  vim.keymap.set('n', '<leader>df', '<cmd>DBUIFindBuffer<cr>', { desc = '[D]atabase: [F]ind buffer' })
  vim.keymap.set('n', '<leader>dr', '<Plug>(DBUI_ExecuteQuery)', { desc = '[D]atabase: [R]un query' })
  vim.keymap.set('v', '<leader>dr', '<Plug>(DBUI_ExecuteQuery)', { desc = '[D]atabase: [R]un selection' })

  -- [[ Site-specific SQL conventions ]]
  -- Extra file-extension associations (Oracle shops tend to use their own set
  -- for package bodies, views, table DDL and so on) and house indentation
  -- deliberately do NOT live here -- they are site-specific and would make
  -- this config non-portable. Put them in the machine-local module loaded at
  -- the end of this section. The generic Oracle support above works without.

  -- Table/column completion inside SQL buffers. dadbod-completion ships an
  -- omnifunc, so this works with <C-x><C-o> immediately. Note blink.cmp does
  -- not consume omnifunc sources -- wiring it into blink's popup would need
  -- the extra `saghen/blink.compat` shim. See the README.
  vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'sql', 'plsql', 'mysql' },
    callback = function() vim.bo.omnifunc = 'vim_dadbod_completion#omni' end,
    desc = 'Enable dadbod SQL completion via <C-x><C-o>',
  })

  -- [[ Machine-local configuration (optional, never committed) ]]
  -- `lua/machine.lua` is gitignored. It is the place for anything tied to one
  -- machine or one employer, so that none of it ends up in this repo:
  --   * extra file-type associations for in-house Oracle extensions
  --   * house indentation and a sqlfluff override via vim.g.sqlfluff_config
  --   * private database tooling (wallet-backed wrappers, internal hosts)
  --
  -- pcall keeps it strictly optional: a fresh clone has no such file and
  -- everything above still works, which is what keeps this config portable.
  -- A genuine error inside the module is still reported, rather than being
  -- silently swallowed along with the "not found" case.
  local ok, err = pcall(require, 'machine')
  if not ok and not tostring(err):match "module 'machine' not found" then
    vim.notify('machine.lua failed to load: ' .. tostring(err), vim.log.levels.WARN)
  end
end

-- ============================================================
-- SECTION 9.7: FILE & WORKSPACE NAVIGATION
-- harpoon (pinned files), persistence (sessions), project picker
-- ============================================================
do
  -- [[ Harpoon 2 ]]
  -- Pin the handful of files you are actually working in and jump straight to
  -- them. This replaces VS Code's pinned tabs, and it scales far better than
  -- cycling buffers once a project gets large.
  --   <leader>a    pin the current file
  --   <C-e>        open the pin list (editable like a normal buffer)
  --   <leader>1-5  jump to pin 1-5
  vim.pack.add { { src = gh 'ThePrimeagen/harpoon', version = 'harpoon2' } }
  local harpoon = require 'harpoon'
  harpoon:setup()

  vim.keymap.set('n', '<leader>a', function() harpoon:list():add() end, { desc = 'H[a]rpoon: pin current file' })
  vim.keymap.set('n', '<C-e>', function() harpoon.ui:toggle_quick_menu(harpoon:list()) end, { desc = 'Harpoon: pin list' })
  for i = 1, 5 do
    vim.keymap.set('n', '<leader>' .. i, function() harpoon:list():select(i) end, { desc = 'Harpoon: go to pin ' .. i })
  end

  -- [[ Sessions ]]
  -- Saves a session per directory, so reopening a repo restores your buffers,
  -- splits and folds. This is VS Code's "reopen last workspace".
  vim.pack.add { gh 'folke/persistence.nvim' }
  require('persistence').setup()

  vim.keymap.set('n', '<leader>ws', function() require('persistence').load() end, { desc = '[W]orkspace: restore [S]ession for cwd' })
  vim.keymap.set('n', '<leader>wl', function() require('persistence').load { last = true } end, { desc = '[W]orkspace: restore [L]ast session' })
  vim.keymap.set('n', '<leader>wd', function() require('persistence').stop() end, { desc = "[W]orkspace: [D]on't save this session" })

  -- [[ Project switcher ]]
  -- snacks.nvim is already installed, so its picker gives us a project list
  -- without pulling in another plugin. Projects are detected from git roots
  -- and from recent files.
  vim.keymap.set('n', '<leader>wp', function() Snacks.picker.projects() end, { desc = '[W]orkspace: switch [P]roject' })
end

-- ============================================================
-- SECTION 10: OPTIONAL EXAMPLES / NEXT STEPS
-- kickstart.plugins.* examples
-- ============================================================
do
  -- The following comments only work if you have downloaded the kickstart repo, not just copy pasted the
  -- init.lua. If you want these files, they are in the repository, so you can just download them and
  -- place them in the correct locations.

  -- NOTE: Next step on your Neovim journey: Add/Configure additional plugins for Kickstart
  --
  --  Here are some example plugins that I've included in the Kickstart repository.
  --  Uncomment any of the lines below to enable them (you will need to restart nvim).
  --
  -- require 'kickstart.plugins.debug'
  -- require 'kickstart.plugins.indent_line'
  -- require 'kickstart.plugins.lint'
  -- require 'kickstart.plugins.autopairs'
  -- require 'kickstart.plugins.neo-tree'

  -- NOTE: You can add your own plugins, configuration, etc. in `lua/custom/plugins/*.lua`.
  --
  -- For independent modules, uncomment the convenience loader:
  -- require 'custom.plugins'
  --
  -- `custom.plugins` automatically loads files from that directory, but their
  -- order is unspecified. If plugins depend on each other, keep them in the same
  -- file and put their `vim.pack.add()` and `setup()` calls in the required order.
  --
  -- If separate modules need a specific order, require them explicitly instead:
  -- require 'custom.plugins.colorscheme'
  -- require 'custom.plugins.ui'
  -- require 'custom.plugins.git'
end

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
