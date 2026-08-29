return {
  cmd = { 'lua-language-server' },
  filetypes = { 'lua' },
  -- '.git' is the fallback: without it a config directory that has no
  -- .luarc.json gets no root, and the server attaches wherever nvim was opened.
  root_markers = { '.luarc.json', '.luarc.jsonc', '.git' },

  settings = {
    Lua = {
      runtime = { version = 'LuaJIT' },
      -- Without this every line of this config is flagged "Undefined global
      -- vim". Pointing the server at the Neovim runtime also buys completion
      -- and signatures for the whole vim.* API, not just silence.
      workspace = {
        library = vim.api.nvim_get_runtime_file('lua', true),
        checkThirdParty = false,
      },
      telemetry = { enable = false },
    },
  },
}
