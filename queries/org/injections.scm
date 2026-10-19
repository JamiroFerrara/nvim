; Parse every `#+begin_src <lang>` block body as `<lang>`, so its highlighting
; is the same the buffer would get in a file of that language. The parameter
; right after the block name is the language; `(expr) @injection.language`
; is anchored to it, so `:tangle md` on another parameter is not mistaken for
; it, and Neovim resolves the text through its filetype -> language mapping
; (e.g. `sh` -> `bash`, `cs` -> `c_sharp`).
;
; Markdown is the one block rendered as well as highlighted: render-markdown
; installs itself for a markdown language tree, which is what gives a
; `#+begin_src markdown` block the rendering a .md file gets.
(block
  name: (expr) @_name
  . (expr) @injection.language
  contents: (contents) @injection.content
  (#eq? @_name "src")
  (#set! injection.include-children))
