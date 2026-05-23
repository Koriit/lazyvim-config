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
          -- Force the output stream to remain pure, formatted text
          "--silent",
          "-",
        },
        stdin = true,
      },
    },
  },
}
