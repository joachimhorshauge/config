; extends
;
; Go template actions inside an HTML buffer.
;
; Template files are filetype 'html' (see lua/filetypes.lua), so the html parser
; is what runs — and to it a {{ ... }} action is ordinary text, which means no
; highlighting at all on the half of the file that is actually program.
;
; 'injection.combined' is the part that matters. `{{ if }}` and `{{ end }}` land
; in different (text) nodes with markup between them; parsed one node at a time
; gotmpl sees an unterminated if in the first and a stray end in the second.
; Combined, the regions are concatenated and parsed as one template, which is
; what they are.
;
; Delete this file to go back to plain HTML highlighting; nothing else depends
; on it beyond the "gotmpl" entry in the treesitter parser list.

((text) @injection.content
  (#lua-match? @injection.content "{{")
  (#set! injection.language "gotmpl")
  (#set! injection.combined))

; `<a href="/items/{{ .ID }}">` and `hx-get="{{ .URL }}"`. Not combined: an
; attribute holds a whole action or none, and combining them across the document
; would splice unrelated fragments together.
((attribute_value) @injection.content
  (#lua-match? @injection.content "{{")
  (#set! injection.language "gotmpl"))
