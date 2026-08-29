require("vim._core.ui2").enable({})
require("options")
-- Before "lsp": both register a FileType autocmd on html, and the one here sets
-- the b:go_template that the one there reads. Autocmds run in the order they
-- were created.
require("filetypes")
require("keymaps")
require("pack")
require("lsp")
