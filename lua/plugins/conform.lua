return {
  "stevearc/conform.nvim",
  opts = {
    formatters_by_ft = {
      markdown = { "rumdl" },
    },
    formatters = {
      rumdl = {
        -- Path to executable
        command = "rumdl",
        -- Force rumdl to read from stdin and output formatted code directly
        -- Using 'fmt' subcommand tells rumdl to behave as a text formatter
        args = {
          "fmt",
          -- Stdin formatting gains nothing from the on-disk cache, and the
          -- cache litters a .rumdl_cache/ dir into every project root (which
          -- the explorer then walks, tripping a snacks/Neovim 0.12 diagnostics bug).
          "--no-cache",
          -- Force the output stream to remain pure, formatted text
          "--silent",
          "-",
        },
        stdin = true,
      },
    },
  },
}
