require("blink.cmp").setup({
  keymap = { preset = "default" },

  appearance = {
    nerd_font_variant = "mono",
  },

  completion = {
    documentation = { auto_show = true, auto_show_delay_ms = 200 },

    -- The html server's hx-* entries carry real documentation, and emmet's
    -- entries carry the markup they expand to. Neither is readable from the
    -- label alone, so the menu shows what kind of thing each item is.
    menu = {
      draw = {
        columns = {
          { "label", "label_description", gap = 1 },
          { "kind_icon", "kind", gap = 1 },
          { "source_name" },
        },
      },
    },

    -- Emmet abbreviations are built by typing `>`, `+` and `*`, which are not
    -- word characters — accepting on one of them would expand `div` before the
    -- abbreviation was finished.
    list = { selection = { preselect = true, auto_insert = false } },
  },

  snippets = {
    -- friendly_snippets defaults to true and finds the plugin by scanning
    -- 'runtimepath', so it needs nothing here beyond the entry in pack.lua.
    --
    -- search_paths is what needs stating: setting it replaces the default
    -- rather than adding to it, and the default is exactly this directory.
    -- snippets/<filetype>.json in there is merged with friendly-snippets'
    -- file of the same name, not shadowed by it.
    --
    -- Two things about writing those files, neither of which JSON lets you
    -- record in the file itself:
    --
    --   * Every top-level key is read as a snippet, and each one is required
    --     to have both `prefix` and `body`. A "//" key used as a comment is
    --     not skipped — it becomes a snippet with a nil body, and the source
    --     throws "bad argument #1 to 'concat'" the moment the menu draws.
    --
    --   * A literal $ has to be written \$, because a bare one is a tabstop.
    --     `{{ $v := . }}` without the escape silently becomes a placeholder
    --     named v.
    search_paths = { vim.fn.stdpath("config") .. "/snippets" },
  },

  sources = {
    default = { "lsp", "path", "snippets", "buffer" },

    providers = {
      -- Buffer completion is the noisy one in a template: every attribute
      -- value and every word of copy in the file is a candidate, and it drowns
      -- the hx-* entries the html server offers. Ranking it below the rest
      -- keeps it as the fallback it is meant to be.
      buffer = { score_offset = -3 },

      -- Emmet returns one item per abbreviation typed so far, which is useful
      -- but should never outrank a real tag or attribute from the html server.
      lsp = { score_offset = 1 },
    },
  },

  fuzzy = { implementation = "prefer_rust_with_warning" },
})
