return {
  "NeogitOrg/neogit",
  lazy = true,
  dependencies = {
    "nvim-lua/plenary.nvim", -- required

    -- Only one of these is needed.
    "sindrets/diffview.nvim", -- optional
    "esmuellert/codediff.nvim", -- optional

    -- For a custom log pager
    "m00qek/baleia.nvim", -- optional

    -- Only one of these is needed.
    "nvim-telescope/telescope.nvim", -- optional
    "ibhagwan/fzf-lua", -- optional
    "nvim-mini/mini.pick", -- optional
    "folke/snacks.nvim", -- optional
  },
  cmd = "Neogit",
  keys = {
    { "<leader>gg", "<cmd>Neogit<cr>", desc = "Show Neogit UI" },
  },
  opts = {
    signs = {
      hunk = { "▶", "▼" },
    },
  },
  config = function(_, opts)
    require("neogit").setup(opts)

    -- Make hunk @@ lines pop as clear boundary markers.
    -- Uses the theme's Search highlight bg as a reference — it's deliberately
    -- eye-catching — while keeping a distinct colour from the purple active-hunk
    -- highlight (NeogitHunkHeaderHighlight). Hooked to ColorScheme so it
    -- survives theme reloads.
    local function patch_hunk_header_hl()
      local search = vim.api.nvim_get_hl(0, { name = "Search", link = false })
      local header = vim.api.nvim_get_hl(0, { name = "NeogitHunkHeader", link = false })
      vim.api.nvim_set_hl(0, "NeogitHunkHeader", vim.tbl_extend("force", header, {
        bg = search.bg,
        fg = search.fg or header.fg,
        bold = true,
      }))
    end

    patch_hunk_header_hl()
    vim.api.nvim_create_autocmd("ColorScheme", { callback = patch_hunk_header_hl })
  end,
}
