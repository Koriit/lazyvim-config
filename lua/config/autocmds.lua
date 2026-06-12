-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

--vim.g.autoformat = false

-- Purge a buffer's diagnostics the moment it's wiped. Neovim 0.12's
-- workspace/pull diagnostics can linger against a dead bufnr after wipeout,
-- which makes the snacks explorer crash in its diagnostics refresh
-- (`nvim_buf_get_name` -> "Invalid buffer id"). Clearing on BufWipeout
-- removes the stale entries before anything can read them.
vim.api.nvim_create_autocmd("BufWipeout", {
  group = vim.api.nvim_create_augroup("clear_stale_diagnostics", { clear = true }),
  callback = function(ev)
    vim.diagnostic.reset(nil, ev.buf)
  end,
})
