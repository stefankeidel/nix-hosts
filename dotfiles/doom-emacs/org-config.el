;;; org-config.el -*- lexical-binding: t; -*-
;;; Fresh PARA notes using Vulpea's stock workflow.
;; `org-directory' is set in config.el; old notes outside it stay untouched.

(map! (:prefix ("s-o" . "notes")
       :desc "Find note" "f" #'vulpea-find
       :desc "Insert note link" "i" #'vulpea-insert
       ;; vulpea-find creates a note when given a new title; vulpea-create is not a command.
       :desc "Find or create note" "n" #'vulpea-find
       :desc "Toggle sidebar" "s" #'vulpea-ui-sidebar-toggle
       :desc "Find area" "a" #'vulpea-para-find-area
       :desc "Find project" "p" #'vulpea-para-find-project
       :desc "Find resource" "r" #'vulpea-para-find-resource
       :desc "Capture area" "A" #'vulpea-para-capture-area
       :desc "Capture project" "P" #'vulpea-para-capture-project
       :desc "Capture" "c" #'org-capture
       :desc "Daily agenda" "g" #'vulpea-para-agenda-main
       :desc "Agenda dispatcher" "G" #'org-agenda
       :desc "Area agenda" "v" #'vulpea-para-agenda-area
       :desc "Archive project" "x" #'vulpea-para-archive-project
       :desc "Check notes setup" "d" #'vulpea-doctor
       :desc "Check PARA setup" "D" #'vulpea-para-doctor))
;; s-i a (agenda dispatcher) and s-i c (capture) remain in navigation.el.

(use-package! vulpea-ui
  :commands (vulpea-ui-sidebar-toggle))

;; SQL Babel blocks do not prompt; other languages retain confirmation.
(setq org-confirm-babel-evaluate
      (lambda (lang _body) (not (string= lang "sql"))))

(after! org
  (use-package! german-holidays)
  (use-package! ob-http)

  ;; The stock agenda uses FOCUS / WAITING / HOLD tags, not extra TODO states.
  (setq org-todo-keywords '((sequence "TODO(t)" "|" "DONE(d!)" "CANCELLED(c@/!)"))
        org-tag-alist '(("FOCUS" . ?f) ("WAITING" . ?w) ("HOLD" . ?h) ("REFILE" . ?r))
        org-agenda-files nil
        org-default-notes-file (expand-file-name "inbox.org" org-directory)
        org-archive-location "::* Archive"
        org-agenda-skip-deadline-if-done t
        org-agenda-skip-scheduled-if-done t
        org-agenda-skip-scheduled-if-deadline-is-shown t
        org-agenda-include-diary nil)

  (use-package! vulpea
    :demand t
    :init
    (make-directory org-directory t)
    (setq vulpea-db-sync-directories (list org-directory)
          vulpea-default-notes-directory org-directory
          ;; A fresh index prevents old notes appearing in the new views.
          vulpea-db-location (expand-file-name "vulpea-para.db" doom-cache-dir))
    :config
    (vulpea-db-autosync-mode +1))

  (use-package! vulpea-para
    :demand t
    :config
    ;; IDs make these containers available to database-backed refiling.
    (setq vulpea-para-capture-area-body
          (concat "* Notes
:PROPERTIES:
:ID: %(org-id-new)
:END:

"
                  "* Tasks
:PROPERTIES:
:ID: %(org-id-new)
:END:

"
                  "* Archive :ARCHIVE:
")
          org-capture-templates
          '(("i" "Inbox task" entry
             (file+headline "inbox.org" "Tasks")
             "* TODO %? :REFILE:
:PROPERTIES:
:ID: %(org-id-new)
:END:
%U
")
            ;; Keep Elfeed's existing capture key, without a separate reading state machine.
            ("r" "Read later" entry
             (file+headline "inbox.org" "Tasks")
             "* TODO Read %? :REFILE:
:PROPERTIES:
:ID: %(org-id-new)
:END:
%U
")))
    (vulpea-para-setup-defaults))

  (org-babel-do-load-languages
   'org-babel-load-languages
   '((sql . t) (python . t) (http . t) (shell . t)))
  (add-to-list 'org-modules 'org-habit t)

  (use-package! org-present
    :config
    (add-hook! 'org-present-mode-hook
      (defun +org-present-setup ()
        (org-present-big)
        (org-display-inline-images)))
    (add-hook! 'org-present-mode-quit-hook
      (defun +org-present-teardown ()
        nil))

    (defun org-present-next-item ()
      (interactive)
      (unless (re-search-forward "^+" nil t)
        (org-present-next)))

    (defun org-present-prev-item ()
      (interactive)
      (unless (re-search-backward "^+" nil t)
        (org-present-prev)))))

;;; Previous task setup (disabled; no migration of existing notes)
;;   (defun stefan/org-files-under (&rest directories)
;;     "Return Org files below DIRECTORIES, relative to `org-directory'."
;;     (mapcan (lambda (directory)
;;               (let ((path (expand-file-name directory org-directory)))
;;                 (when (file-directory-p path)
;;                   (directory-files-recursively path "\\.org\\'"))))
;;             directories))
;;
;;   (defvar stefan/org-task-files nil
;;     "Org files that should contribute regular tasks to the agenda.")
;;
;;   (setq stefan/org-task-files
;;         (seq-filter
;;          #'file-exists-p
;;          (append
;;           (list (expand-file-name "tasks.org" org-directory))
;;           (stefan/org-files-under "personal" "work" "knowledge" "presentations")))
;;         org-agenda-files
;;         (seq-filter
;;          #'file-exists-p
;;          (append stefan/org-task-files
;;                  (list (expand-file-name "reading.org" org-directory)))))
;;
;;   (setq org-todo-keywords
;;         '((sequence "TODO(t)" "NEXT(n)" "PROGRESS(p!)" "WIP(w!)" "|" "DONE(d!)")
;;           (sequence "QUEUE(q)" "STARTED(s!)" "SAVED(v)" "|" "FINISHED(f!)")
;;           (sequence "HOLD(h@/!)" "|" "CANCELLED(c@/!)" "CANCELED(x@/!)")))
;;
;;   (setq org-tag-alist '((:startgroup)
;;                         ("@home" . ?h)
;;                         ("@work" . ?w)
;;                         (:endgroup)
;;                         ("@personal" . ?p)
;;                         ("@habit" . ?b)))
;;
;;   (setq org-todo-keyword-faces
;;         '(("TODO" :foreground "indian red" :weight bold)
;;           ("PROGRESS" :foreground "sky blue" :weight bold)
;;           ("DONE" :foreground "forest green" :weight bold)
;;           ("HOLD" :foreground "orange" :weight bold)
;;           ("NEXT" :foreground "LightSalmon1" :weight bold)
;;           ("CANCELLED" :foreground "forest green" :weight bold)
;;           ("CANCELED" :foreground "forest green" :weight bold)
;;           ("MEETING" :foreground "forest green" :weight bold)
;;           ("QUEUE" :foreground "LightSalmon1" :weight bold)
;;           ("STARTED" :foreground "PeachPuff2" :weight bold)
;;           ("SAVED" :foreground "sky blue" :weight bold)
;;           ("FINISHED" :foreground "forest green" :weight bold)
;;           ("WIP" :foreground "sky blue" :weight bold)))
;;
;;   (setq org-refile-targets
;;         `((,(expand-file-name "tasks.org" org-directory) :regexp . "\\(?:Home\\|Work\\)")))
;;
;;   ;; File-specific #+ARCHIVE rules still override this default.
;;   (setq org-archive-location '"archive/org-mode/archive.org::"
;;         org-agenda-skip-deadline-if-done t
;;         org-agenda-skip-scheduled-if-done t
;;         org-agenda-skip-scheduled-if-deadline-is-shown t
;;         diary-file (expand-file-name "diary" org-directory)
;;         org-agenda-include-diary (file-exists-p diary-file))
;;
;;   (org-babel-do-load-languages
;;    'org-babel-load-languages
;;    '((sql . t) (python . t) (http . t) (shell . t)))
;;   (add-to-list 'org-modules 'org-habit t)
;;
;;   (setq org-agenda-custom-commands
;;         `(("a" "Agenda and tasks"
;;            ((agenda "" ((org-agenda-span 'week)
;;                          (org-deadline-warning-days 4)))
;;             (alltodo "" ((org-agenda-files ',stefan/org-task-files)
;;                          (org-agenda-overriding-header "Tasks")))))
;;           ("r" "Reading list"
;;            ((todo "STARTED") (todo "QUEUE") (todo "SAVED"))
;;            ((org-agenda-files ',(list (expand-file-name "reading.org" org-directory)))))))
;;
;;   (setq org-capture-templates
;;         '(("i" "Task" entry
;;            (file+headline "tasks.org" "Tasks")
;;            "** TODO %?\n/Entered on/ %U")
;;           ("r" "Reading List" entry
;;            (file+headline "reading.org" "from template")
;;            "** QUEUE %?")))
;;
;;
