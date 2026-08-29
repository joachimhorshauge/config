-- Emmet abbreviations: `div.card>ul>li*3` expands to the nested markup, `m10`
-- to `margin: 10px`. It is a second server on the same buffer as html/cssls,
-- which LSP allows and blink merges the results of.
--
-- Worth having next to the html server rather than instead of it: the html
-- server completes what exists (tags, attributes, hx-* from the custom data),
-- emmet writes structure that does not exist yet.
return {
  cmd = { 'emmet-language-server', '--stdio' },

  -- css is in here for the property abbreviations, which work in a .css file
  -- as well as in a <style> block.
  filetypes = { 'html', 'css', 'scss', 'less' },
  root_markers = { 'go.mod', 'package.json', '.git' },

  init_options = {
    ---@type table<string, string>
    variables = {},
    ---@type string[]
    excludeLanguages = {},
    showExpandedAbbreviation = 'always',

    -- Off: with it on, every partial word in the buffer is offered as an
    -- abbreviation, so the completion list fills with expansions of prose.
    showAbbreviationSuggestions = false,

    -- Emmet's own `!` boilerplate and `>` nesting are enough; the suggested
    -- filters mostly duplicate what the html server already completes.
    showSuggestionsAsSnippets = false,
  },
}
