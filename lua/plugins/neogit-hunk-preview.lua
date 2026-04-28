return {
  dir = vim.fn.stdpath("config") .. "/lua/neogit-hunk-preview",
  name = "neogit-hunk-preview",
  dev = true,
  dependencies = { "NeogitOrg/neogit" },
  event = "FileType NeogitStatus",
  config = function()
    require("neogit-hunk-preview").setup()
  end,
}
