-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>ai", function()
  require("claude").claude_enhance({ is_visual = false })
end, { desc = "Enhance with Claude" })

vim.keymap.set("x", "<leader>ai", function()
  require("claude").claude_enhance({ is_visual = true })
end, { desc = "Enhance with Claude" })
