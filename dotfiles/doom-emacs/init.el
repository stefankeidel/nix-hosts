;;; $DOOMDIR/init.el -*- lexical-binding: t; -*-
;; Doom modules and their load order. Run `doom sync' after changing this file.

(doom! :input

       :completion
       (corfu +orderless)
       vertico

       :ui
       doom
       dashboard
       hl-todo
       modeline
       ophints
       (popup +defaults)
       (vc-gutter +pretty)
       vi-tilde-fringe
       workspaces

       :editor
       file-templates
       fold
       snippets
       (whitespace +guess +trim)

       :emacs
       dired
       electric
       tramp
       undo
       vc

       :term
       ghostel

       :checkers
       syntax

       :tools
       docker
       (eval +overlay)
       lookup
       (lsp +eglot)
       magit
       (terraform +lsp)
       tree-sitter

       :os
       (:if (featurep :system 'macos) macos)

       :lang
       (elixir +lsp +tree-sitter)
       emacs-lisp
       json
       javascript
       latex
       markdown
       (nix +lsp +tree-sitter)
       org
       (python +lsp +tree-sitter)
       sh
       yaml

       :email

       :app

       :config
       (default +bindings +smartparens))
