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

; remove frame decoration
(add-to-list 'default-frame-alist '(undecorated . t))

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
(setq org-directory (file-name-as-directory (expand-file-name "~/Proton/orgmode/")))


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
(setq projectile-auto-update-cache-with-watches t)

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
      "s-r"   #'+vertico/switch-workspace-buffer
      "s-e"   #'consult-buffer
      "s-i e" #'+workspace/switch-to
      "C-c r" #'consult-ripgrep
      "C-s"   #'consult-line
      "s-z"   #'avy-goto-char
      "s-i k" #'kill-buffer-basename
      "s-i s" #'lichtblick-dbt-search-model
      "s-i a" #'org-agenda
      "s-i c" #'org-capture
      "s-i l" #'agent-shell
      "s-i o" #'stefan/open-current-gitlab-project
      "M-y"   #'browse-kill-ring)

(bind-key "s-l" lab-map)

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

(defun stefan--projectile-run-ghostel-buffer (label &optional where command)
  "Open or switch to a permanent ghostel buffer for the current project.

The buffer is named \"**LABEL parent/project**\", where parent/project is
the last two path segments of the project root (e.g. \"data/infrastructure\"
for ~/code/lichtblick/data/infrastructure), and its `default-directory' is
the project root, similar to `projectile-run-eshell'/`projectile-run-term'
(cf. https://github.com/bbatsov/projectile/pull/1474).  WHERE controls
placement: nil for the current window, `window' for another window, or
`frame' for another frame.  When COMMAND is given, it is sent to the
freshly created ghostel buffer followed by a return, so callers can
launch e.g. \"copilot\" straight away."
  ;; Force ghostel.el to load now, before we dynamically rebind
  ;; `ghostel-buffer-name' below.  On a fresh Emacs (package not yet
  ;; loaded), that variable isn't declared special yet, so `let*'
  ;; would only create a throwaway lexical binding that the real
  ;; `ghostel' function - defined in a separately compiled file -
  ;; never sees, silently ignoring our buffer name override.
  (require 'ghostel)
  (let* ((root (directory-file-name (projectile-project-root)))
         (parent (file-name-nondirectory (directory-file-name (file-name-directory root))))
         (project (file-name-nondirectory root))
         (default-directory (projectile-project-root))
         (buffer-name (format "**%s %s/%s**" label parent project))
         (existing (get-buffer buffer-name)))
    (if existing
        (pcase where
          ('window (switch-to-buffer-other-window existing))
          ('frame (switch-to-buffer-other-frame existing))
          (_ (switch-to-buffer existing)))
      ;; `ghostel-buffer-name' drives both the buffer's name and the
      ;; identity `ghostel' uses to find/reuse it on subsequent calls,
      ;; mirroring `ghostel-project's own let-binding trick.
      (let* ((ghostel-buffer-name buffer-name)
             (display-buffer-overriding-action
              (pcase where
                ('window '(display-buffer-pop-up-window))
                ('frame '(display-buffer-pop-up-frame))
                (_ display-buffer-overriding-action)))
             (buf (ghostel)))
        (when command
          (with-current-buffer buf
            (ghostel-send-string command)
            (ghostel-send-string "\r")))))))

(defmacro stefan--def-projectile-ghostel-commands (name label &optional command)
  "Define interactive commands stefan-projectile-run-NAME[-other-{window,frame}]
that open a ghostel buffer LABEL, optionally sending COMMAND."
  (let ((base (intern (format "stefan-projectile-run-%s" name)))
        (win (intern (format "stefan-projectile-run-%s-other-window" name)))
        (frame (intern (format "stefan-projectile-run-%s-other-frame" name))))
    `(progn
       (defun ,base ()
         ,(format "Open a permanent ghostel buffer in the current project's root%s."
                  (if command (format " and start %s in it" command) ""))
         (interactive)
         (stefan--projectile-run-ghostel-buffer ,label nil ,command))
       (defun ,win ()
         ,(format "Like `%s', but displayed in another window." base)
         (interactive)
         (stefan--projectile-run-ghostel-buffer ,label 'window ,command))
       (defun ,frame ()
         ,(format "Like `%s', but displayed in another frame." base)
         (interactive)
         (stefan--projectile-run-ghostel-buffer ,label 'frame ,command)))))

(stefan--def-projectile-ghostel-commands "ghostel" "term")
(stefan--def-projectile-ghostel-commands "copilot" "copilot" "copilot")
(stefan--def-projectile-ghostel-commands "vibe" "vibe" "vibe")

(defun stefan/open-current-gitlab-project ()
  "Open the current Projectile project in the GitLab browser."
  (interactive)
  (unless (fboundp 'projectile-project-root)
    (require 'projectile))
  (let* ((project-root (or (and (fboundp 'projectile-project-root)
                                (projectile-project-root))
                           default-directory))
         (project-name (file-name-nondirectory (directory-file-name project-root)))
         (remote-url (string-trim
                      (shell-command-to-string
                       (format "git -C %s remote get-url origin"
                               (shell-quote-argument project-root)))))
         (repo-path
          (or
           (let ((url (string-trim remote-url)))
             (cond
              ((string-prefix-p "ssh://" url)
               (let* ((rest (substring url (length "ssh://")))
                      (at-pos (string-match "@" rest))
                      (without-user (if at-pos
                                        (substring rest (1+ at-pos))
                                      rest))
                      (slash-pos (string-match "/" without-user)))
                 (if slash-pos
                     (substring without-user (1+ slash-pos))
                   nil)))
              ((or (string-prefix-p "https://" url)
                   (string-prefix-p "http://" url)
                   (string-prefix-p "git://" url))
               (let* ((prefix (cond ((string-prefix-p "https://" url) "https://")
                                    ((string-prefix-p "http://" url) "http://")
                                    ((string-prefix-p "git://" url) "git://")
                                    (t "")))
                      (rest (substring url (length prefix)))
                      (slash-pos (string-match "/" rest)))
                 (if slash-pos
                     (substring rest (1+ slash-pos))
                   nil)))
              ((string-match-p ":" url)
               (let* ((colon-pos (string-match ":" url))
                      (path (substring url (1+ colon-pos))))
                 (if (and path (not (string-prefix-p "/" path)))
                     path
                   nil)))
              (t nil)))
           project-name))
         (normalized-path (replace-regexp-in-string "\\.git$" "" repo-path))
         (url (format "https://gitlab.lichtblick.app/%s" normalized-path)))
    (browse-url url)))

; projectile bindings
(map! :map projectile-mode-map
      "s-p" #'projectile-command-map
      "s-f" #'projectile-search-review);#'+default/search-project-for-symbol-at-point)

(map! :map projectile-command-map
      "v"   #'stefan-projectile-run-ghostel
      "c"   #'stefan-projectile-run-copilot
      "x"   #'stefan-projectile-run-vibe
      "4 v" #'stefan-projectile-run-ghostel-other-window
      "4 c" #'stefan-projectile-run-copilot-other-window
      "4 x" #'stefan-projectile-run-vibe-other-window
      "5 v" #'stefan-projectile-run-ghostel-other-frame
      "5 c" #'stefan-projectile-run-copilot-other-frame
      "5 x" #'stefan-projectile-run-vibe-other-frame)

; it's disabled by default
(put 'projectile-ripgrep 'disabled nil)

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

;; ACP / agent-shell
(use-package! acp
  :after shell-maker)

(use-package! agent-shell
  :after acp
  :bind (:map agent-shell-mode-map
              ("RET" . newline)
              ("C-c C-c" . shell-maker-submit)
              ("C-c C-k" . agent-shell-interrupt))
  :config
  (setq agent-shell-openai-authentication (agent-shell-github-make-copilot-config :login t)
        agent-shell-prefer-viewport-interaction t))


;; GPT.el
;; (after! gptel
;;   (gptel-make-gh-copilot "Copilot" :host "api.enterprise.githubcopilot.com")
;;   (use-package! gptel)
;; )

;; accept completion from copilot and fallback to company
;; (use-package! copilot
;;   :hook (prog-mode . copilot-mode)
;;   :bind (:map copilot-completion-map
;;               ("<tab>" . 'copilot-accept-completion)
;;               ("TAB" . 'copilot-accept-completion)
;;               ("C-TAB" . 'copilot-accept-completion-by-word)
;;               ("C-<tab>" . 'copilot-accept-completion-by-word))
;;   :config
;;   (add-to-list 'copilot-indentation-alist '(prog-mode 2))
;;   (add-to-list 'copilot-indentation-alist '(org-mode 2))
;;   (add-to-list 'copilot-indentation-alist '(text-mode 2))
;;   (add-to-list 'copilot-indentation-alist '(clojure-mode 2))
;;   (add-to-list 'copilot-indentation-alist '(emacs-lisp-mode 2)))

;; (after! copilot
;;   (setopt copilot-lsp-settings '(:github-enterprise (:uri "https://lichtblick-se.ghe.com")))
;;   (setopt copilot-chat-use-agent-mode t)

;;   (setopt copilot-mcp-servers
;;         '(:fetch (:command "uvx" :args ["mcp-server-fetch"])
;;           :gitlab-cicd-catalog (
;;                 :command "/Users/stefan.keidel@lichtblick.de/code/lichtblick/agent-tools/gitlab-cicd-catalog-mcp/serve.sh"
;;                          :args []
;;                          :env (:SSL_VERIFY "false" :GITLAB_TOKEN "glpat-lkK4kCC3HrDel0X4J_Yn1W86MQp1OjE1Mwk.01.0z1ygcn4y"))))
;; )

; my legacy org mode clusterfuck of a configuration
; should be at the very bottom and refactored at some point
(after! org
  (use-package! german-holidays)
  (use-package! ob-http)

  (defun stefan/org-files-under (&rest directories)
    "Return org files below DIRECTORIES, relative to `org-directory'."
    (mapcan (lambda (directory)
              (let ((path (expand-file-name directory org-directory)))
                (when (file-directory-p path)
                  (directory-files-recursively path "\\.org\\'"))))
            directories))

  (defvar stefan/org-task-files nil
    "Org files that should contribute regular tasks to the agenda.")

  (setq stefan/org-task-files
        (seq-filter
         #'file-exists-p
         (append
          (list (expand-file-name "tasks.org" org-directory))
          (stefan/org-files-under
           "personal"
           "work"
           "knowledge"
           "presentations")))
        org-agenda-files
        (seq-filter
         #'file-exists-p
         (append
          stefan/org-task-files
          (list (expand-file-name "reading.org" org-directory)))))

  (setq org-clock-persist 'history)
  (org-clock-persistence-insinuate)

  (setq org-todo-keywords
        (quote ((sequence "TODO(t)" "NEXT(n)" "PROGRESS(p!)" "WIP(w!)" "|" "DONE(d!)")
                (sequence "QUEUE(q)" "STARTED(s!)" "SAVED(v)" "|" "FINISHED(f!)")
                (sequence "HOLD(h@/!)" "|" "CANCELLED(c@/!)" "CANCELED(x@/!)"))))

  (setq org-tag-alist '((:startgroup)
                        ("@home" . ?h)
                        ("@work" . ?w)
                        (:endgroup)
                        ("@personal" . ?p)
                        ("@habit" . ?b)))

  (setq org-todo-keyword-faces
        (quote (("TODO" :foreground "indian red" :weight bold)
                  ("PROGRESS" :foreground "sky blue" :weight bold)
                  ("DONE" :foreground "forest green" :weight bold)
                  ("HOLD" :foreground "orange" :weight bold)
                  ("NEXT" :foreground "LightSalmon1" :weight bold)
                  ("CANCELLED" :foreground "forest green" :weight bold)
                  ("CANCELED" :foreground "forest green" :weight bold)
                  ("MEETING" :foreground "forest green" :weight bold)
                  ;; For my reading list
                  ("QUEUE" :foreground "LightSalmon1" :weight bold)
                  ("STARTED" :foreground "PeachPuff2" :weight bold)
                  ("SAVED" :foreground "sky blue" :weight bold)
                  ("FINISHED" :foreground "forest green" :weight bold)
                  ("WIP" :foreground "sky blue" :weight bold)
                  )))

    (setq org-refile-targets
          `((,(expand-file-name "tasks.org" org-directory) :regexp . "\\(?:Home\\|Work\\)")))

  ;; Default archive target; file-specific #+ARCHIVE rules still override this.
  (setq org-archive-location '"archive/org-mode/archive.org::")

  (setq org-agenda-skip-deadline-if-done t)
  (setq org-agenda-skip-scheduled-if-done t)
  (setq org-agenda-skip-scheduled-if-deadline-is-shown t)
  (setq diary-file (expand-file-name "diary" org-directory)
        org-agenda-include-diary (file-exists-p diary-file))

  (org-babel-do-load-languages
   'org-babel-load-languages
   '((sql . t) (python . t) (http . t) (shell . t)))

  (add-to-list 'org-modules 'org-habit t)

  (setq org-agenda-custom-commands
        `(
          ("a" "Agenda and tasks"
           ((agenda "" (
                        (org-agenda-span 'week)
                        (org-deadline-warning-days 4)
                        ))
            (alltodo ""
                     ((org-agenda-files ',stefan/org-task-files)
                      (org-agenda-overriding-header "Tasks")))
            ))
          ("r" "Reading list"
           (
            (todo "STARTED")
            (todo "QUEUE")
            (todo "SAVED")
            )
          ((org-agenda-files ',(list (expand-file-name "reading.org" org-directory)))))
          ))

  (setq org-capture-templates '(
   ("i" "Task" entry
    (file+headline "tasks.org" "Tasks")
          "** TODO %?\n/Entered on/ %U")
   ("r" "Reading List" entry
    (file+headline "reading.org" "from template")
    "** QUEUE %?")
   ))

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
      ;; (center-content-mode 1)
      ))

  (add-hook! 'org-present-mode-quit-hook
    (defun +org-present-teardown ()
      ;; (jinx-mode 1)
      ;(org-modern-mode -1)
      ;(setq org-modern-hide-stars (default-value 'org-modern-hide-stars))
      ;(org-modern-mode 1)
      ;; (focus-mode -1)
      ;; (center-content-mode -1)
      ))

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

  (defun my-project-find-python-project (dir)
    (when-let ((root (locate-dominating-file dir "pyproject.toml")))
      (cons 'python-project root)))

  (with-eval-after-load "project"
    (cl-defmethod project-root ((project (head python-project)))
      (cdr project))

    (add-hook 'project-find-functions #'my-project-find-python-project))

  (add-to-list 'eglot-server-programs
               '(elixir-mode "elixir-ls"))

  (add-to-list 'eglot-server-programs
               '((python-ts-mode python-mode)
                 . ("ty" "server")))
  (add-hook 'python-ts-mode-hook #'eglot-ensure)
  (add-to-list 'major-mode-remap-alist '(python-mode . python-ts-mode))
)

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
        ("https://hannahritchie.substack.com/feed" blog)
        ("https://ourworldindata.org/atom-data-insights.xml" blog)
        ("https://ourworldindata.org/atom.xml" blog)
        ("https://michael.stapelberg.ch/feed.xml" blog)

        ; econ and random stuff
        ("https://www.lesswrong.com/feed.xml?view=curated-rss" blog)
        ("https://feedpress.me/TheTechnium" blog)
        ("https://www.construction-physics.com/feed" blog)
        ("https://www.optimallyirrational.com/feed" blog)
        ("https://www.statsignificant.com/feed" blog)

        ; emacs
        ("https://asylum.madhouse-project.org/blog/atom.xml" emacs blog)
        ("http://www.masteringemacs.org/feed/" emacs blog)
        ("https://pragmaticemacs.wordpress.com/feed" emacs blog)
        ("https://emacsredux.com/atom.xml" emacs blog)

        ; entertainment
        ("https://www.xkcd.com/rss.xml" comic)

        ; bikes
        ("https://inrng.com/feed/" bikes)
        ("https://bikepacking.com/feed/" bikes interesting)
        ("https://fahrradzukunft.de/feed/" bikes)
        ("https://www.iamtedking.com/blog?format=rss" bikes interesting)
        ("https://www.renehersecycles.com/feed/" bikes interesting)

        ; trying to keep taps on work stuff
        ; ("https://meltano.com/blog/feed/" data blog) -- meltano feed is kaputt
        ("https://roundup.getdbt.com/feed" data blog)
        ("https://www.ssp.sh/index.xml" data blog)
        ("https://www.dataengineeringweekly.com/feed" blog)
        ("https://stkbailey.substack.com/feed" blog)
        ("https://seattledataguy.substack.com/feed" blog)
        ("https://martinfowler.com/feed.atom" blog)
        ("http://jpkoning.blogspot.com/feeds/posts/default?alt=rss" blog)
        ("https://motherduck.com/rss.xml" blog)
        ("https://dataengineeringcentral.substack.com/feed" blog)
        ("https://astral.sh/blog/rss.xml" blog)
        ("https://docs.getdbt.com/blog/rss.xml" data blog)
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
  (add-to-list 'yas-snippet-dirs (expand-file-name "~/.config/doom/snippets"))
  :config
  (yas-global-mode 1))

(use-package mise :demand t)

(after! python
  (global-mise-mode t)
)

(after! buffer-guardian
  ;; Save the buffer even if the window change results in the same buffer
  (setq buffer-guardian-save-on-same-buffer-window-change t)

  ;; Non-nil to enable verbose mode to log when a buffer is automatically saved
  (setq buffer-guardian-verbose nil)

  ;; Save all buffers after N seconds of user idle time. (Disabled by default)
  ;; (setq buffer-guardian-save-all-buffers-idle 30)

  (buffer-guardian-mode 1))

;; GitLab token is never committed here; it's decrypted by agenix to
;; ~/.config/gitlab-token (see hosts/*/darwin-configuration.nix and
;; secrets/gitlab-token.age) and read at startup instead.
;;
;; `lab-config' is a plain variable, so it can be set here directly without
;; forcing the `lab' package to load early (use-package!'s lazy loading was
;; preventing this from taking effect until the buffer was eval'd by hand).
(after! lab
  (let ((gitlab-token-file (expand-file-name "~/.config/gitlab-token")))
    (setq lab-config
          `((:host "https://gitlab.lichtblick.app/"
             :token ,(when (file-exists-p gitlab-token-file)
                       (with-temp-buffer
                         (insert-file-contents gitlab-token-file)
                         (string-trim (buffer-string))))
             :group "lichtblick"))))
)

(use-package! embark
  :ensure t
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)
         ("C-h B" . embark-bindings))
  :init
  (setq prefix-help-command #'embark-prefix-help-command))
