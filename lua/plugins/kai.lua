return {
  dir = vim.fn.stdpath("config"),
  name = "kai",
  lazy = true,
  keys = {
    {
      "<leader>ai",
      function()
        require("kai").kai_enhance()
      end,
      mode = { "n", "v" },
      desc = "Enhance with Kai",
    },
  },
}
