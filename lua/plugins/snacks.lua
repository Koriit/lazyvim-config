return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      hidden = true, -- show dotfiles in all pickers
      ignored = false, -- show .gitignore'd files in all pickers
      sources = {
        explorer = {
          hidden = true,
          ignored = true,
        },
        -- The files picker overrides the top-level default,
        -- so it must be set explicitly.
        files = {
          hidden = true,
          ignored = false,
        },
        grep = {
          hidden = true,
          ignored = false,
        },
      },
    },
  },
}
