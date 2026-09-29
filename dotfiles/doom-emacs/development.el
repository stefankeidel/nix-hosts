;;; development.el -*- lexical-binding: t; -*-
;;; SQL, language servers, and development helpers.

(use-package! ob-sql-mode)

(defun read-file (file)
  "Return the lines in FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (split-string (buffer-string) "\n" t)))

(defun pgpass-to-sql-connection (config)
  "Turn lines from a pgpass file into `sql-connection-alist' entries."
  (append sql-connection-alist
          (let ((make-connection (lambda (host port db user _pass)
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

;; Keep this at startup: SQL connections are populated from the local pgpass.
(setq sql-connection-alist (pgpass-to-sql-connection (read-file "~/.pgpass")))

(add-hook 'sql-interactive-mode-hook
          (lambda ()
            (toggle-truncate-lines t)))

(with-eval-after-load 'eglot
  (setq eglot-ignored-server-capabilities '(:inlayHintProvider))

  (defun my-project-find-python-project (dir)
    (when-let ((root (locate-dominating-file dir "pyproject.toml")))
      (cons 'python-project root)))

  (with-eval-after-load "project"
    (cl-defmethod project-root ((project (head python-project)))
      (cdr project))
    (add-hook 'project-find-functions #'my-project-find-python-project))

  (add-to-list 'eglot-server-programs '(elixir-mode "elixir-ls"))
  (add-to-list 'eglot-server-programs
               '((python-ts-mode python-mode) . ("ty" "server")))
  (add-hook 'python-ts-mode-hook #'eglot-ensure)
  (add-to-list 'major-mode-remap-alist '(python-mode . python-ts-mode)))

(use-package mise :demand t)

(after! python
  (global-mise-mode t))

(after! buffer-guardian
  (setq buffer-guardian-save-on-same-buffer-window-change t
        buffer-guardian-verbose nil)
  (buffer-guardian-mode 1))
