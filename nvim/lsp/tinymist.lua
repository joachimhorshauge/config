-- Typst's language server. tinymist embeds its own copy of the compiler, so
-- the `typst` binary on PATH is not what answers hover, completion or
-- diagnostics here — the two only need to agree on a Typst version.
return {
  cmd = { 'tinymist', 'lsp' },
  filetypes = { 'typst' },

  -- The root decides what a leading '/' in an #import means, so it has to be
  -- the same root the file is really compiled with — otherwise the server
  -- reports an error on an import that builds perfectly well.
  --
  -- Inside the zk notebook that root is the notebook. notes-site compiles every
  -- .typ in it with `typst compile --root <notebook>`, so
  -- `#import "/templates/exercise.typ"` resolves there; rooting an exercise at
  -- its own directory instead looks for exercises/IPSRP/templates/ and finds
  -- nothing. The notebook has no typst.toml and is not a git repo, so no marker
  -- would ever have found it.
  --
  -- Everywhere else the markers apply as before: typst.toml only exists for
  -- packages, a loose .typ is the common case, and '.git' carries the root most
  -- of the time. on_dir is called either way — with nil when nothing is found,
  -- which leaves the server treating the file's own directory as the root.
  root_dir = function(bufnr, on_dir)
    local notebook = vim.fs.normalize(vim.env.ZK_NOTEBOOK_DIR or vim.fn.expand('~/notes'))
    local file = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))

    if vim.fs.relpath(notebook, file) then
      on_dir(notebook)
      return
    end
    on_dir(vim.fs.root(bufnr, { 'typst.toml', '.git' }))
  end,

  settings = {
    -- typstyle is compiled into tinymist, so formatting needs nothing else
    -- installed. This has to be set: with no mode the server answers
    -- textDocument/formatting with "unsupported" and conform's lsp fallback
    -- silently does nothing.
    formatterMode = 'typstyle',
    formatterPrintWidth = 80,

    -- Prose stays on whatever lines it was written on. Reflowing it would
    -- rewrite paragraphs wholesale on every save and bury real edits in diffs.
    formatterProseWrap = false,

    -- No PDF unless asked for, via :TypstPdf. 'onType' writes one on every
    -- keystroke, and the live preview already covers seeing the result.
    exportPdf = 'never',

    -- A multi-file document is compiled from whichever file :TypstPin names;
    -- until then each .typ is its own root, which is what a single-file note
    -- wants anyway.
    projectResolution = 'singleFile',
  },
}
