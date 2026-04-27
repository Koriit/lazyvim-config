return {
  dir = vim.fn.stdpath("config") .. "/lua/mdtable",
  name = "mdtable",
  dev = true,
  ft = "markdown",
  keys = {
    {
      "<leader>mt",
      function()
        require("mdtable").inspect()
      end,
      mode = "n",
      ft = "markdown",
      desc = "mdtable: inspect row at cursor",
    },
  },
}
