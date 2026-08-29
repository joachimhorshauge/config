-- VS Code's HTML server, shipped by the vscode-langservers-extracted package
-- along with the css, json and eslint ones. It is the only HTML server that
-- knows the full element/attribute set, and the only one that takes custom
-- attribute data — which is what teaches it htmx (see dataPaths below).
--
-- It tolerates Go's {{ }} actions because it does no tag-balance checking: its
-- diagnostics come from the languages embedded in <style> and <script>, not
-- from the markup. That is also why 'validate.scripts' is off below.
local htmx_data = vim.fn.stdpath('config') .. '/html-data/htmx.json'

return {
  cmd = { 'vscode-html-language-server', '--stdio' },
  filetypes = { 'html' },

  -- go.mod first: in this project the templates live under a Go module, and
  -- rooting at the module keeps <a href> path completion resolving against the
  -- same tree the server embeds files from.
  root_markers = { 'go.mod', 'package.json', '.git' },

  init_options = {
    -- conform owns formatting (djlint, which understands {{ }}). Left on, the
    -- server advertises textDocument/formatting and conform's
    -- `lsp_format = "fallback"` would reach for it whenever djlint is absent —
    -- silently reflowing template blocks into broken markup.
    provideFormatter = false,

    -- Completion and hover inside <style>/<script> in a template, handed off
    -- to the same engines cssls uses.
    embeddedLanguages = { 'css', 'javascript' },
    configurationSection = { 'html', 'css', 'javascript' },

    -- VS Code custom-data files. This is what makes hx-* real attributes to
    -- the server: they complete inside a tag, hover with docs, and hx-swap
    -- offers its value set — rather than being snippets you have to remember.
    --
    -- Setting this is only half of it; see the handler below.
    dataPaths = { htmx_data },
  },

  handlers = {
    -- The server does not read the dataPaths it was handed. It sends each one
    -- straight back as an 'html/customDataContent' request and waits for the
    -- editor to return the file's text — VS Code serves them through its own
    -- virtual filesystem, so the server never touches a disk path itself.
    --
    -- Neovim has no handler for that request, and the server's loader swallows
    -- the failure: parseHTMLData catches and returns an empty provider. The
    -- result is dataPaths appearing to work while contributing nothing, which
    -- is exactly what it did before this function existed.
    ['html/customDataContent'] = function(_, params)
      -- The path arrives bare over the wire in some versions and wrapped in
      -- the usual params array in others.
      local path = type(params) == 'table' and params[1] or params
      if type(path) ~= 'string' then
        return ''
      end

      local content = ''
      local ok, lines = pcall(vim.fn.readfile, path)
      if ok then
        content = table.concat(lines, '\n')
      end

      -- Returning '' rather than an error keeps the server's own fallback
      -- path: an empty provider, plain HTML completion, no hx-*.
      return content
    end,
  },

  settings = {
    html = {
      -- Server-side values land in <script> as bare {{ .JSON }}, which is not
      -- valid JavaScript and would light up the whole block. <style> is left
      -- validated: template actions are rare in CSS.
      validate = { scripts = false, styles = true },
      format = { enable = false },
      -- htmx puts long attribute lists on elements; wrapping the tag on hover
      -- makes the docs unreadable.
      hover = { documentation = true, references = true },
    },
  },
}
