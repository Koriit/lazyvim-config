-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>ai", function()
  require("claude").claude_enhance({ is_visual = false })
end, { desc = "Enhance with Claude" })

vim.keymap.set("x", "<leader>ai", function()
  require("claude").claude_enhance({ is_visual = true })
end, { desc = "Enhance with Claude" })

-- Copy absolute path to system clipboard with <C-y>P
vim.keymap.set("n", "<C-y>P", function()
  local path = vim.fn.expand("%:p")
  vim.fn.setreg("+", path)
  vim.notify('Copied "' .. path .. '" to the clipboard!')
end, { desc = "Copy absolute file path" })

-- Copy relative path to system clipboard with <C-y>p
vim.keymap.set("n", "<C-y>p", function()
  local path = vim.fn.expand("%:.")
  vim.fn.setreg("+", path)
  vim.notify('Copied "' .. path .. '" to the clipboard!')
end, { desc = "Copy relative file path" })

-- Copy filename to system clipboard with <C-y>f
vim.keymap.set("n", "<C-y>f", function()
  local path = vim.fn.expand("%:t")
  vim.fn.setreg("+", path)
  vim.notify('Copied "' .. path .. '" to the clipboard!')
end, { desc = "Copy filename" })
