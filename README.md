# Neovim config

Personal Neovim configuration based on [LazyVim](https://github.com/LazyVim/LazyVim),
extended with locally-developed plugins (`lua/sidenote/`, `lua/mdtable/`, ...).

## Markdown toolchain

### Prerequisites

- **Rust + cargo** — required to build `rumdl` from crates.io (see Lua toolchain section below).

### Install

```bash
cargo install rumdl
```

### Why these choices

| Tool | Role | Notes |
|---|---|---|
| `rumdl` | formatter | Rust-based Markdown formatter; used by conform.nvim for `markdown` files. |

### Verify

```bash
rumdl --version
```

---

## Lua toolchain

The plugins in this repo are authored, formatted, linted, and tested with the
standard Lua / Neovim toolchain. All tools below should resolve on `PATH`.

### Prerequisites

- **Rust + cargo** — required to build `stylua` and `selene` from crates.io.
  Install via [rustup](https://rustup.rs/) (`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`).

### Install

```bash
# 1. Lua runtime + package manager (apt)
sudo apt install luajit lua5.1 liblua5.1-dev luarocks

# 2. Formatter + linter (cargo)
cargo install stylua selene

# 3. Test framework (user-local luarocks tree)
luarocks install --local busted

# 4. LSP — grab the latest release tarball for your platform from
#    https://github.com/LuaLS/lua-language-server/releases
#    (file: lua-language-server-<ver>-linux-x64.tar.gz), then:
mkdir -p ~/.local/share/lua-language-server ~/.local/bin
tar -xzf lua-language-server-*-linux-x64.tar.gz -C ~/.local/share/lua-language-server
ln -sf ~/.local/share/lua-language-server/bin/lua-language-server ~/.local/bin/lua-language-server
```

### Shell setup

Add to `~/.zshrc` / `~/.bashrc`:

```bash
# Lua package paths + ~/.luarocks/bin on PATH
eval "$(luarocks path)"
```

`luarocks path` (≥ 3.8) exports `LUA_PATH`, `LUA_CPATH`, and prepends
`~/.luarocks/bin` to `PATH` — covering the test framework's binary and
any rocks the Lua interpreter needs to `require`.

Also ensure these are on `PATH` (usually already handled by your distro / rustup):

- `~/.cargo/bin` — `stylua`, `selene` (added by rustup)
- `~/.local/bin` — `lua-language-server` (added by Ubuntu's `~/.profile`)

Reload your shell (`exec zsh`) after editing rc files.

### Why these choices

| Tool | Role | Notes |
|---|---|---|
| `luajit` / `lua5.1` | runtime | Neovim embeds LuaJIT (5.1 ABI); plugin tests run against the same runtime. |
| `luarocks` | package manager | Standard way to install Lua libraries (e.g. `busted`). |
| `stylua` | formatter | De-facto standard formatter for Neovim plugins; config in `stylua.toml`. |
| `selene` | linter | Single static Rust binary; modern replacement for `luacheck`. |
| `busted` | test framework | BDD-style runner used by most Neovim plugins. |
| `lua-language-server` | LSP | Type-aware completion, diagnostics, navigation. |

### Verify

```bash
stylua --version
selene --version
busted --version
lua-language-server --version
luajit -v
luarocks --version
```
