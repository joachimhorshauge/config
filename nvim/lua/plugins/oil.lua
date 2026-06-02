require("oil").setup({
  default_file_explorer = true,  -- replaces netrw
  view_options = {
    show_hidden = true,
  },
  keymaps = {
    ["<CR>"]   = "actions.select",
    ["<C-h>"]  = "actions.parent",
    ["<C-l>"]  = "actions.refresh",
    ["q"]      = "actions.close",
    ["gd"]     = {
      desc = "Toggle file detail view",
      callback = function()
        local oil = require("oil")
        local config = require("oil.config")
        if #config.columns == 1 then
          oil.set_columns({ "icon", "permissions", "size", "mtime" })
        else
          oil.set_columns({ "icon" })
        end
      end,
    },
  },
})
