;;; org-config.el -*- lexical-binding: t; -*-
;;; Agenda, capture, Babel, and presentations.
;; `org-directory' must be set in config.el before Org loads.

;; SQL Babel blocks do not prompt; other languages retain confirmation.
(setq org-confirm-babel-evaluate
      (lambda (lang _body)
        (not (string= lang "sql"))))

(after! org
  (use-package! german-holidays)
  (use-package! ob-http)

  (defun stefan/org-files-under (&rest directories)
    "Return Org files below DIRECTORIES, relative to `org-directory'."
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
          (stefan/org-files-under "personal" "work" "knowledge" "presentations")))
        org-agenda-files
        (seq-filter
         #'file-exists-p
         (append stefan/org-task-files
                 (list (expand-file-name "reading.org" org-directory)))))

  (setq org-clock-persist 'history)
  (org-clock-persistence-insinuate)

  (setq org-todo-keywords
        '((sequence "TODO(t)" "NEXT(n)" "PROGRESS(p!)" "WIP(w!)" "|" "DONE(d!)")
          (sequence "QUEUE(q)" "STARTED(s!)" "SAVED(v)" "|" "FINISHED(f!)")
          (sequence "HOLD(h@/!)" "|" "CANCELLED(c@/!)" "CANCELED(x@/!)")))

  (setq org-tag-alist '((:startgroup)
                        ("@home" . ?h)
                        ("@work" . ?w)
                        (:endgroup)
                        ("@personal" . ?p)
                        ("@habit" . ?b)))

  (setq org-todo-keyword-faces
        '(("TODO" :foreground "indian red" :weight bold)
          ("PROGRESS" :foreground "sky blue" :weight bold)
          ("DONE" :foreground "forest green" :weight bold)
          ("HOLD" :foreground "orange" :weight bold)
          ("NEXT" :foreground "LightSalmon1" :weight bold)
          ("CANCELLED" :foreground "forest green" :weight bold)
          ("CANCELED" :foreground "forest green" :weight bold)
          ("MEETING" :foreground "forest green" :weight bold)
          ("QUEUE" :foreground "LightSalmon1" :weight bold)
          ("STARTED" :foreground "PeachPuff2" :weight bold)
          ("SAVED" :foreground "sky blue" :weight bold)
          ("FINISHED" :foreground "forest green" :weight bold)
          ("WIP" :foreground "sky blue" :weight bold)))

  (setq org-refile-targets
        `((,(expand-file-name "tasks.org" org-directory) :regexp . "\\(?:Home\\|Work\\)")))

  ;; File-specific #+ARCHIVE rules still override this default.
  (setq org-archive-location '"archive/org-mode/archive.org::"
        org-agenda-skip-deadline-if-done t
        org-agenda-skip-scheduled-if-done t
        org-agenda-skip-scheduled-if-deadline-is-shown t
        diary-file (expand-file-name "diary" org-directory)
        org-agenda-include-diary (file-exists-p diary-file))

  (org-babel-do-load-languages
   'org-babel-load-languages
   '((sql . t) (python . t) (http . t) (shell . t)))
  (add-to-list 'org-modules 'org-habit t)

  (setq org-agenda-custom-commands
        `(("a" "Agenda and tasks"
           ((agenda "" ((org-agenda-span 'week)
                         (org-deadline-warning-days 4)))
            (alltodo "" ((org-agenda-files ',stefan/org-task-files)
                         (org-agenda-overriding-header "Tasks")))))
          ("r" "Reading list"
           ((todo "STARTED") (todo "QUEUE") (todo "SAVED"))
           ((org-agenda-files ',(list (expand-file-name "reading.org" org-directory)))))))

  (setq org-capture-templates
        '(("i" "Task" entry
           (file+headline "tasks.org" "Tasks")
           "** TODO %?\n/Entered on/ %U")
          ("r" "Reading List" entry
           (file+headline "reading.org" "from template")
           "** QUEUE %?")))

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
