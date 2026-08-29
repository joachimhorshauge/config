-- Haskell's language server.
--
-- One package covers all three jobs, because the Arch build compiles the
-- plugins in rather than shelling out to separate tools:
--
--   hls-ormolu-plugin   answers textDocument/formatting, which is why haskell
--                       is absent from conform's formatters_by_ft
--   hls-hlint-plugin    publishes the hlint warnings, each with an "Apply
--                       hint" code action the standalone binary cannot offer
--   hls-cabal-plugin    does the same for the .cabal file itself
--
-- So: pacman -S haskell-language-server, and nothing else.
--
-- That package links against the system GHC (/usr/bin/ghc) and its libraries,
-- so it only loads projects built with that same compiler. A ghcup-managed GHC
-- needs ghcup's own HLS instead — the two builds do not mix, and the failure
-- shows up as "GHC version mismatch" in :LspLog rather than as a crash.
return {
  cmd = { 'haskell-language-server-wrapper', '--lsp' },

  -- 'cabal' is the .cabal file, handled by hls-cabal-plugin. 'cabalproject'
  -- (cabal.project) is left out: no plugin reads it, so a server would attach
  -- and answer nothing.
  filetypes = { 'haskell', 'lhaskell', 'cabal' },

  -- root_markers cannot express this one. The marker that matters most is
  -- '*.cabal' — a glob, and root_markers takes base names only (:h
  -- lsp-root_markers) — so the search runs through vim.fs.root, which does
  -- take a predicate.
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    if fname == '' then
      return -- not calling on_dir is how a config declines the buffer
    end

    -- Priority is hie-bios's own. hie.yaml is alone at the top because it is
    -- the file that tells hie-bios how to load the project; where it sits is
    -- the root by definition. The middle group is "whatever names the build"
    -- and its members are equal — a stack project has both stack.yaml and a
    -- .cabal, and either one found first is the same directory.
    local root = vim.fs.root(bufnr, {
      'hie.yaml',
      -- One predicate rather than the nested list the equal-priority group
      -- would normally be written as, because vim.fs.root hands each element
      -- straight to vim.fs.find, and find takes a list of names or a function
      -- but not a table holding both — mixing them crashes in joinpath. A
      -- single function covers all four names and keeps the grouping.
      function(name)
        return name == 'cabal.project'
          or name == 'stack.yaml'
          or name == 'package.yaml'
          or name:match('%.cabal$') ~= nil
      end,
      '.git',
    })

    -- No marker anywhere is the loose-script case, and it still has to get an
    -- answer: on_dir left uncalled means no server at all. Its own directory
    -- is the honest one — hie-bios falls back to loading the file with default
    -- flags, which carries a single self-contained module.
    on_dir(root or vim.fs.dirname(fname))
  end,

  settings = {
    haskell = {
      -- Also the default, but worth pinning: this is the answer to "what
      -- formats Haskell here", and conform defers to it rather than
      -- duplicating it. 'fourmolu', 'stylish-haskell' and 'floskell' are
      -- compiled in too, so switching is this string and nothing else.
      formattingProvider = 'ormolu',

      -- The .cabal counterpart, and the one gap in "install one package":
      -- hls-cabal-fmt-plugin runs the external cabal-fmt binary, which is not
      -- in the Arch repos. Until `cabal install cabal-fmt`, formatting a
      -- .cabal file is a no-op that logs to :LspLog.
      cabalFormattingProvider = 'cabal-fmt',

      plugin = {
        -- Stated on purpose: this is the linter, and lua/plugins/lint.lua
        -- stands down for any buffer this server is attached to. Turning it
        -- off here is what hands linting back to the standalone hlint.
        hlint = { globalOn = true },
      },
    },
  },
}
