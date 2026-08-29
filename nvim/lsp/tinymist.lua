-- Typst's language server. tinymist embeds its own copy of the compiler, so
-- the `typst` binary on PATH is not what answers hover, completion or
-- diagnostics here — the two only need to agree on a Typst version.
return {
  cmd = { 'tinymist', 'lsp' },
  filetypes = { 'typst' },

  -- typst.toml only exists for packages. A loose .typ file is the common case,
  -- so '.git' carries the root most of the time, and the server falls back to
  -- the file's own directory when neither is found.
  root_markers = { 'typst.toml', '.git' },

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
