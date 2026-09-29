;;; navigation.el -*- lexical-binding: t; -*-
;;; Project navigation, terminal commands, and keybindings.

(setq git-commit-summary-max-length 80)

;; Watches for every cached project can exhaust the macOS file-descriptor limit
;; when a large virtual environment is replaced. Manual cache updates still work.
(after! projectile
  (setq projectile-auto-update-cache-with-watches nil)
  (dolist (directory '(".venv" "venv" ".direnv"))
    (add-to-list 'projectile-globally-ignored-directories directory)))

(defun kill-buffer-basename ()
  "Copy the basename of the current buffer's file."
  (interactive)
  (kill-new (file-name-base (buffer-file-name))))

(use-package! rg)

(defun lichtblick-dbt-search-model ()
  "Search the current project for the current file's basename."
  (interactive)
  (projectile-ripgrep (file-name-base (buffer-file-name))))

(defun stefan--projectile-run-ghostel-buffer (label &optional where command)
  "Open or switch to a permanent ghostel buffer for the current project.

The buffer is named `**LABEL parent/project**', where parent/project is
the last two path segments of the project root. WHERE controls placement:
nil for the current window, `window' for another window, or `frame' for
another frame. When COMMAND is given, send it to a new buffer."
  ;; Load ghostel before dynamically binding its special variable; otherwise
  ;; the binding would be lexical and ghostel would ignore our buffer name.
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
  "Define project ghostel commands for NAME and LABEL, optionally sending COMMAND."
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
(stefan--def-projectile-ghostel-commands "pi" "pi" "pi")

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

;; Global shortcuts.
(map! "s-m m" #'magit-status
      "s-m j" #'magit-dispatch
      "s-m k" #'magit-file-dispatch
      "s-m l" #'magit-log-buffer-file
      "s-m b" #'magit-blame
      "s-w"   #'next-multiframe-window
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
      "s-i o" #'stefan/open-current-gitlab-project
      "s-i m" #'lab-list-branch-merge-requests
      "s-i p" #'lab-list-project-pipelines
      "M-y"   #'browse-kill-ring)

(bind-key "s-l" lab-map)

(map! :map projectile-mode-map
      "s-p" #'projectile-command-map
      "s-f" #'projectile-ripgrep)

(map! :map projectile-command-map
      "v"   #'stefan-projectile-run-ghostel
      "c"   #'stefan-projectile-run-copilot
      "x"   #'stefan-projectile-run-pi
      "4 v" #'stefan-projectile-run-ghostel-other-window
      "4 c" #'stefan-projectile-run-copilot-other-window
      "4 x" #'stefan-projectile-run-pi-other-window
      "5 v" #'stefan-projectile-run-ghostel-other-frame
      "5 c" #'stefan-projectile-run-copilot-other-frame
      "5 x" #'stefan-projectile-run-pi-other-frame)

(put 'projectile-ripgrep 'disabled nil)
