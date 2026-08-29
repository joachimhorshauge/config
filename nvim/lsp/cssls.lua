-- VS Code's CSS server, from the same vscode-langservers-extracted package as
-- the html one.
--
-- All three of css/scss/less must appear under `settings` even though only css
-- is used here. The server reads them unconditionally at startup and throws on
-- the first missing one, taking the whole session's diagnostics with it.
return {
  cmd = { 'vscode-css-language-server', '--stdio' },
  filetypes = { 'css', 'scss', 'less' },
  root_markers = { 'go.mod', 'package.json', '.git' },

  -- prettier formats CSS; see the html config for why the server's own
  -- formatter is refused rather than left as a fallback.
  init_options = { provideFormatter = false },

  settings = {
    css = {
      validate = true,
      lint = {
        -- The server's at-rule list is fixed and already behind the spec, so
        -- @container, @layer and @property all read as errors. Nothing else in
        -- its lint set has that problem.
        unknownAtRules = 'ignore',
      },
    },
    scss = { validate = true, lint = { unknownAtRules = 'ignore' } },
    less = { validate = true, lint = { unknownAtRules = 'ignore' } },
  },
}
