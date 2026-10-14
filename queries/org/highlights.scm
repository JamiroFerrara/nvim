; Deliberately empty.
;
; org.nvim paints .org buffers with its own generated vim syntax (headlines,
; keywords, src blocks, ...). This file exists only so nvim-treesitter's
; `highlight` module considers the `org` parser supported: with it the
; treesitter highlighter runs on org buffers, which is what makes the markdown
; injected into `#+begin_src markdown` blocks (queries/org/injections.scm) get
; the same highlighting a .md file gets. No captures here on purpose -- a
; capture would override org.nvim's syntax.
