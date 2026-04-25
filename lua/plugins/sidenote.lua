return {
  dir = vim.fn.stdpath("config") .. "/lua/sidenote",
  name = "sidenote",
  dev = true,
  ft = "markdown",
  keys = {
    {
      "<leader>cnc",
      function()
        require("sidenote").create_or_edit_visual()
      end,
      mode = "x",
      desc = "sidenote: create from selection",
    },
    {
      "<leader>cnc",
      function()
        require("sidenote").create_or_edit_cursor()
      end,
      mode = "n",
      desc = "sidenote: edit at cursor",
    },
    {
      "<leader>cnk",
      function()
        require("sidenote").quicklook()
      end,
      mode = "n",
      desc = "sidenote: quicklook",
    },
    {
      "<leader>cnl",
      function()
        require("sidenote").browse()
      end,
      mode = "n",
      desc = "sidenote: browse all",
    },
    {
      "<leader>cnd",
      function()
        require("sidenote").delete_at_cursor()
      end,
      mode = "n",
      desc = "sidenote: delete at cursor",
    },
    {
      "<leader>cnr",
      function()
        require("sidenote").toggle_show_resolved()
      end,
      mode = "n",
      desc = "sidenote: toggle show resolved",
    },
    {
      "<leader>cnR",
      function()
        require("sidenote").toggle_resolved_at_cursor()
      end,
      mode = "n",
      desc = "sidenote: mark resolved at cursor",
    },
    {
      "]n",
      function()
        require("sidenote").goto_next()
      end,
      mode = "n",
      desc = "sidenote: next note",
    },
    {
      "[n",
      function()
        require("sidenote").goto_prev()
      end,
      mode = "n",
      desc = "sidenote: prev note",
    },
  },
  config = function()
    require("sidenote").setup()
  end,
}
