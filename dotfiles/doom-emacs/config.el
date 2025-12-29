;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
(setq doom-font (font-spec :family "Hack Nerd Font" :size 19 :weight 'semi-light)
      doom-variable-pitch-font (font-spec :family "Hack Nerd Font" :size 19))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-one)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type nil)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")


;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `after!' block, otherwise Doom's defaults may override your settings. E.g.
;;
;;   (after! PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look up their documentation).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.


; magit
(map! "s-m m" #'magit-status
      "s-m j" #'magit-dispatch
      "s-m k" #'magit-file-dispatch
      "s-m l" #'magit-log-buffer-file
      "s-m b" #'magit-blame)

(setq git-commit-summary-max-length 80)

; random functions for dbt navigation enhancements
(defun kill-buffer-basename ()
   "Kill buffer basename"
   (interactive)
   (kill-new (file-name-base (buffer-file-name))))

(use-package! rg)

(defun lichtblick-dbt-search-model ()
  "Search for model name, as defined by basename of current file"
  (interactive)

  (projectile-ripgrep (file-name-base (buffer-file-name))))

; global stuff
(map! "s-w"   #'next-multiframe-window
      "s-e"   #'consult-buffer
      "C-c r" #'consult-ripgrep
      "C-s"   #'consult-line
      "s-z"   #'avy-goto-char
      "s-l"   #'gptel-menu
      "s-i k" #'kill-buffer-basename
      "s-i s" #'lichtblick-dbt-search-model
      "s-i a" #'org-agenda
      "s-i c" #'org-capture
      "M-y"   #'browse-kill-ring
      "<f2>"  #'gptel-complete
      "<f3>"  #'gptel-accept-completion)

; kill ring navigation
(use-package! browse-kill-ring
  :defer
  :config
  (map! "M-y" #'browse-kill-ring))

; configure a nicer undo version
(use-package! undo-tree
  :diminish
  :config
  (setq undo-tree-auto-save-history t)
  (setq undo-tree-history-directory-alist
    `((".*" . ,temporary-file-directory))))

(global-undo-tree-mode 1)

; projectile bindings
(map! :map projectile-mode-map
      "s-p" #'projectile-command-map
      "s-f" #'projectile-ripgrep)

; some imports
(use-package! visual-regexp)
(use-package! visual-regexp-steroids)
(use-package! crux)

(use-package! multiple-cursors
    :config
    (map! "s-d" #'mc/mark-all-like-this)
    (map! "s-." #'mc/mark-next-like-this))

; sql stuff, mostly postgres
(use-package! ob-sql-mode)

; .pgpass parser
(defun read-file (file)
  "Returns file as list of lines."
  (with-temp-buffer
    (insert-file-contents file)
    (split-string (buffer-string) "\n" t)))

(defun pgpass-to-sql-connection (config)
  "Returns a suitable list for sql-connection-alist from a pgpass file."
  (append sql-connection-alist
          (let* ((make-connection (lambda (host port db user _pass)
                                   (list
                                    (concat db)
                                    (list 'sql-product ''postgres)
                                    (list 'sql-server host)
                                    (list 'sql-user user)
                                    (list 'sql-port (string-to-number port))
                                    (list 'sql-database db)))))
            (mapcar (lambda (line)
                      (apply make-connection (split-string line ":" t)))
                    config))))

;;; Actually populating sql-connection-alist
(setq sql-connection-alist (pgpass-to-sql-connection (read-file "~/.pgpass")))

(add-hook 'sql-interactive-mode-hook
          (lambda ()
            (toggle-truncate-lines t)))

(setq org-confirm-babel-evaluate
      (lambda (lang body)
        (not (string= lang "sql"))))

;; AI stuff
(after! gptel
  (gptel-make-gh-copilot "Copilot")
  (setq gptel-model 'gpt-5-mini
        gptel-backend (gptel-make-gh-copilot "Copilot"))

  (use-package! macher
      :custom
      ;; The org UI has structured navigation and nice content folding.
      (macher-action-buffer-ui 'org)
    )

  (use-package! gptel-autocomplete
    :config
    (setq gptel-autocomplete-before-context-lines 100)
    (setq gptel-autocomplete-after-context-lines 20)
    (setq gptel-autocomplete-temperature 0.1)
    (setq gptel-autocomplete-use-context t)
    )

  (use-package! gptel
      :config
      (macher-install))

  ;; (gptel-make-preset 'gpt5coding                       ;preset name, a symbol
  ;;     :description "A preset optimized for coding tasks" ;for your reference
  ;;     :backend "Copilot"
  ;;     :model 'gpt-5-mini
  ;;     :system "You are an expert coding assistant. Your role is to provide high-quality code solutions, refactorings, and explanations."
  ;;     :tools '("view_buffer" "edit_buffer")) ;gptel tools or tool names
  ;;
)

;; accept completion from copilot and fallback to company
;; (use-package! copilot
;;   :hook (prog-mode . copilot-mode)
;;   :config
;;   (map! :map copilot-completion-map "<f2>" #'copilot-accept-completion)
;;   (add-to-list 'copilot-indentation-alist '(prog-mode 2))
;;   (add-to-list 'copilot-indentation-alist '(org-mode 2))
;;   (add-to-list 'copilot-indentation-alist '(text-mode 2))
;;   (add-to-list 'copilot-indentation-alist '(closure-mode 2))
;;   (add-to-list 'copilot-indentation-alist '(emacs-lisp-mode 2))
;; )

; my legacy org mode clusterfuck of a configuration
; should be at the very bottom and refactored at some point
(after! org
  (use-package! german-holidays)
  (use-package! ob-http)
  (setq org-agenda-files (list "~/org/stefan.org"
                             "~/org/reading.org"
                             "~/org/lichtblick.org"))

  (setq org-todo-keywords
        (quote ((sequence "TODO(t)" "SOMEDAY(s)" "PROGRESS(p!)" "|" "DONE(d!)")
                (sequence "WAITING(w@/!)" "HOLD(h@/!)" "|" "CANCELLED(c@/!)" "MEETING(m)"))))

  (setq org-todo-keyword-faces
        (quote (("TODO" :foreground "indian red" :weight bold)
                  ("SOMEDAY" :foreground "LightSalmon1" :weight bold)a
                  ("PROGRESS" :foreground "sky blue" :weight bold)
                  ("DONE" :foreground "forest green" :weight bold)
                  ("WAITING" :foreground "orange" :weight bold)
                  ("HOLD" :foreground "magenta" :weight bold)
                  ("CANCELLED" :foreground "forest green" :weight bold)
                  ("MEETING" :foreground "forest green" :weight bold)
                  ;; For my reading list
                  ("QUEUE" :foreground "LightSalmon1" :weight bold)
                  ("STARTED" :foreground "PeachPuff2" :weight bold)
                  ("SAVED" :foreground "sky blue" :weight bold)
                  )))

    (setq org-tag-alist (quote ((:startgroup)
                                ("@errand" . ?e)
                                ("@work" . ?w)
                                ("@move" . ?m)
                                ("@home" . ?h)
                                ("@routine" . ?t)
                                ("@bike" . ?b)
                                ("@reading" . ?r)
                                (:endgroup)
                                )))

    (setq org-refile-targets '(("~/org/stefan.org" :maxlevel . 2)
                             ("~/org/reading.org" :maxlevel . 1)
                             ("~/org/lichtblick.org" :maxlevel . 2)
                             ))

  ;; one big archive for everything [file-specific rules still apply and override]
  (setq org-archive-location '"archive.org::")

  (setq org-agenda-skip-scheduled-if-deadline-is-shown t)
  (setq org-agenda-skip-deadline-if-done t)
  (setq org-agenda-include-diary t)

  (org-babel-do-load-languages
   'org-babel-load-languages
   '((sql . t) (python . t) (http . t) (shell . t)))

  (add-to-list 'org-modules 'org-habit t)

  (setq org-agenda-custom-commands
        '(
          ("a" "Agenda and tasks"
           ((agenda "" ((org-agenda-span 7)))
            (tags-todo "@work")
            (tags-todo "@home")
            ;(tags-todo "@reading")
            ))
          ("r" "Reading list"
           (
            (todo "STARTED")
            (todo "QUEUE")
            (todo "SAVED")
            ))
          ))

  (setq org-capture-templates '(
   ("t" "Todo Lichtblick" entry
    (file+headline "~/org/lichtblick.org" "Tasks")
    "* TODO %i%?")
   ("s" "Todo Stefan" entry
    (file+headline "~/org/stefan.org" "tasks")
    "* TODO %i%?")
   ;; ("c" "Calendar" entry
   ;;  (file+headline "~/org/stefan.org" "calendar")
   ;;  "* %i%? \n   %t")
   ;; ;; ("s" "Standup" entry
   ;; ;;  (file+headline "~/org/idagio.org" "standups")
   ;; ;;  "** Standup %t\n*** yesterday\n-%?\n*** today\n-\n")
   ("r" "Reading List" entry
    (file+headline "~/org/reading.org" "from template")
    "** QUEUE %?")
   ))

  (use-package! org-roam
    :custom
    (org-roam-directory (file-truename "~/org-roam/"))
    (org-roam-capture-templates
     '(
     ("d" "default" plain
        "%?"
        :if-new (file+head "%<%Y-%m-%d--%H-%M-%S>-${slug}.org" "#+title: ${title}\n#+filetags:")
        :unnarrowed t)
     ("t" "ticket" plain
      "* https://lichtblick.atlassian.net/browse/${title}\n\n%?\n"
      :if-new (file+head "lichtblick-tickets/%<%Y-%m-%d--%H-%M-%S>-${slug}.org"
                         "#+title: ${title}\n#+FILETAGS: ticket:lichtblick"
                         )
      :unnarrowed t)
      )
     )
    :config
    (setq org-roam-node-display-template (concat "${title:*} " (propertize "${tags:60}" 'face 'org-tag)))
    (setq org-roam-completion-everywhere t)
    (org-roam-db-autosync-mode)
    (map! "s-b f" #'org-roam-node-find)
    (map! "s-b g" #'org-roam-graph)
    (map! "s-b i" #'org-roam-node-insert)
    (map! "s-b c" #'org-roam-capture)
    )

  (use-package! org-present
  :config
  ;; Hooks
  (add-hook! 'org-present-mode-hook
    (defun +org-present-setup ()
      ;; (jinx-mode -1)
      ;(org-modern-mode -1)
      ;(set (make-local-variable 'org-modern-hide-stars) t)
      ;(org-modern-mode 1)
      (org-present-big)
      (org-display-inline-images)
      ;; (focus-mode 1)
      (center-content-mode 1)))

  (add-hook! 'org-present-mode-quit-hook
    (defun +org-present-teardown ()
      ;; (jinx-mode 1)
      ;(org-modern-mode -1)
      ;(setq org-modern-hide-stars (default-value 'org-modern-hide-stars))
      ;(org-modern-mode 1)
      ;; (focus-mode -1)qq
      (center-content-mode -1)))

  ;; Custom functions
  (defun org-present-next-item ()
    (interactive)
    (unless (re-search-forward "^+" nil t)
      (org-present-next)))

  (defun org-present-prev-item ()
    (interactive)
    (unless (re-search-backward "^+" nil t)
      (org-present-prev)))

  ;; Key bindings
  ;; (map! :map org-present-mode-keymap
  ;;       "<next>"     #'org-present-next-item
  ;;       "C-<right>"  #'org-present-next-item
  ;;       "<prior>"    #'org-present-prev-item
  ;;       "C-<left>"   #'org-present-prev-item)
  )
)

;; elixir config
(with-eval-after-load 'eglot
  (setq eglot-ignored-server-capabilities '(:inlayHintProvider))

  (add-to-list 'eglot-server-programs
               '(elixir-mode "elixir-ls")))

;; newsreader
(use-package! elfeed
  :config
  (map! "C-x w" #'elfeed)
  (map! :map elfeed-show-mode-map "v" #'elfeed-show-quick-url-note)
  (setq elfeed-feeds
      '(
        ; useful geek stuff
        ("http://nullprogram.com/feed/" programming)
        ("https://hnrss.org/frontpage" hn maybe) ; spammy custom tag for Hacker News
        ("https://netzpolitik.org/ticker/feed" maybe)
        ("https://netzpolitik.org/feed/" blog)
        ("https://fragdenstaat.de/artikel/feed/" blog)

        ("https://events.ccc.de/feed/" events security)
        ("https://www.ccc.de/rss/updates.rdf" security)

        ("https://www.benkuhn.net/index.xml" blog)
        ("https://metaredux.com/feed.xml" blog interesting)
        ("https://github.blog/feed/atom" blog)
        ("https://blog.appliedcomputing.io/feed" blog)
        ("https://blog.openstreetmap.org/feed/" blog interesting)
        ("http://feeds.feedburner.com/martinkl" blog)
        ("https://den.dev/index.xml" blog)
        ("https://industrydecarbonization.com/rss.xml" blog interesting)
        ("https://www.bloodinthemachine.com/feed" blog)
        ("https://climatedrift.substack.com/feed" blog)
        ("https://craphound.com/feed" blog) ; his long form blog
        ("https://pagedout.institute/rss.xml" blog)

        ; econ and random stuff
        ("https://www.lesswrong.com/feed.xml?view=curated-rss" blog)
        ("https://feedpress.me/TheTechnium" blog)
        ("https://www.construction-physics.com/feed" blog)
        ("https://www.optimallyirrational.com/feed" blog)
        ("https://www.ribbonfarm.com/feed" blog)

        ; emacs
        ("https://asylum.madhouse-project.org/blog/atom.xml" emacs blog)
        ("http://www.masteringemacs.org/feed/" emacs blog)
        ("https://pragmaticemacs.wordpress.com/feed" emacs blog)
        ("https://emacsredux.com/atom.xml" emacs blog)

        ; entertainment
        ("https://www.xkcd.com/rss.xml" comic)

        ; bikes
        ("https://inrng.com/feed/" bikes)
        ("http://feeds.feedburner.com/redkiteprayer/krin" bikes)
        ("https://bikepacking.com/feed/" bikes interesting)
        ("https://fahrradzukunft.de/feed/" bikes)
        ("https://www.iamtedking.com/blog?format=rss" bikes interesting)
        ("https://www.renehersecycles.com/feed/" bikes interesting)

        ; trying to keep taps on work stuff
        ; ("https://meltano.com/blog/feed/" data blog) -- meltano feed is kaputt
        ("https://roundup.getdbt.com/feed" data blog)
        ("https://www.ssp.sh/index.xml" data blog)
        ("https://more-than-numbers.count.co/feed" blog)
        ("https://www.dataengineeringweekly.com/feed" blog)
        ("https://stkbailey.substack.com/feed" blog)
        ("https://seattledataguy.substack.com/feed" blog)
        ("https://martinfowler.com/feed.atom" blog)
        ("http://jpkoning.blogspot.com/feeds/posts/default?alt=rss" blog)
        ("https://motherduck.com/rss.xml" blog)
        ("https://dataengineeringcentral.substack.com/feed" blog)
        ))
  :config
  (defface interesting-elfeed-entry
    '((t :foreground "#f77"))
    "interesting elfeed entry")
  (defface maybe-elfeed-entry
    '((t :foreground "grey"))
    "maybe elfeed entry")
  (push '(interesting interesting-elfeed-entry)
        elfeed-search-face-alist)

  (push '(maybe maybe-elfeed-entry)
        elfeed-search-face-alist)
  (setq-default elfeed-search-filter "@2-weeks-ago +unread ")
  (defun elfeed-show-quick-url-note ()
      "Fastest way to capture entry link to org agenda from elfeed show mode"
      (interactive)
      (elfeed-link-title elfeed-show-entry)
      (org-capture nil "r")
      (yank)
      (org-capture-finalize))
  )

(after! elfeed
  (define-advice elfeed-search--header (:around (oldfun &rest args))
  (if elfeed-db
      (apply oldfun args)
    "No database loaded yet"))
)

(defun elfeed-link-title (entry)
  "Copy the entry title and URL as org link to the clipboard."
  (interactive)
  (let* ((link (elfeed-entry-link entry))
         (title (elfeed-entry-title entry))
         (titlelink (concat "[[" link "][" title "]]")))
    (when titlelink
      (kill-new titlelink)
      (x-set-selection 'PRIMARY titlelink)
      (message "Yanked: %s" titlelink))))

(defun elfeed-show-link-title ()
"Copy the current entry title and URL as org link to the clipboard."
(interactive)
(elfeed-link-title elfeed-show-entry))


;; (define-key elfeed-show-mode-map "l"
;;   (lambda ()
;;     (interactive)
;;     (elfeed-link-title elfeed-show-entry)))


;; (setq-default elfeed-search-filter "@2-weeks-ago +unread ")

;; (defface interesting-elfeed-entry
;;   '((t :foreground "#f77"))
;;   "interesting elfeed entry")

;; (defface maybe-elfeed-entry
;;   '((t :foreground "grey"))
;;   "maybe elfeed entry")

;; (push '(interesting interesting-elfeed-entry)
;;       elfeed-search-face-alist)

;; (push '(maybe maybe-elfeed-entry)
;;       elfeed-search-face-alist)

;; (define-key elfeed-show-mode-map "l"
;;   (lambda ()
;;     (interactive)
;;     (elfeed-link-title elfeed-show-entry)))

; disable confirmation on exit
(setq confirm-kill-emacs nil)

(use-package! easy-kill
  :config
  (map! "M-w" #'easy-kill)
  (map! "s-," #'easy-mark))

(use-package! yasnippet
  :init
  (add-to-list 'yas-snippet-dirs (f-expand "~/.config/doom/snippets"))
  :config
  (yas-global-mode 1))

(use-package mise :demand t)

(after! python
  (global-mise-mode t))
