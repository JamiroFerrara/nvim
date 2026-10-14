; Parse a `#+begin_src markdown` block as markdown, so its body is highlighted
; (and rendered, via render-markdown) exactly like a .md file.
;
; `(expr) @_lang` is anchored to the parameter right after the block name, so
; only the language is compared: `#+begin_src markdown :tangle a.md` is still
; markdown, `#+begin_src python :tangle markdown` is not.
(block
  name: (expr) @_name
  . (expr) @_lang
  contents: (contents) @injection.content
  (#eq? @_name "src")
  (#eq? @_lang "markdown")
  (#set! injection.language "markdown")
  (#set! injection.include-children))
