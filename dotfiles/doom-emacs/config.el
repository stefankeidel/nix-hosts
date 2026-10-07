;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-
;;; Personal settings and entry points for the topic-specific configuration.
;; Keep settings that must be in place before packages load above the load! calls.

(setq doom-font (font-spec :family "Hack Nerd Font" :size 19 :weight 'semi-light)
      doom-variable-pitch-font (font-spec :family "Hack Nerd Font" :size 19)
      doom-theme 'doom-one
      display-line-numbers-type nil
      org-directory (file-name-as-directory (expand-file-name "~/Proton/orgmode/")))

(load! "navigation")
(load! "development")
(load! "org-config")
(load! "elfeed-config")

;;; Editing and session behavior
(setq confirm-kill-emacs nil)

;; Start maximized, not in a macOS native-fullscreen Space, so external
;; window managers can still move and resize the frame.
(add-to-list 'default-frame-alist '(fullscreen . maximized))
(add-to-list 'default-frame-alist '(undecorated . t))

(use-package! browse-kill-ring
  :defer
  :config
  (map! "M-y" #'browse-kill-ring))

(use-package! undo-tree
  :diminish
  :config
  (setq undo-tree-auto-save-history t
        undo-tree-history-directory-alist
        `((".*" . ,temporary-file-directory))))
(global-undo-tree-mode 1)

(use-package! visual-regexp)
(use-package! visual-regexp-steroids)
(use-package! crux)

(use-package! multiple-cursors
  :config
  (map! "s-d" #'mc/mark-all-like-this
        "s-." #'mc/mark-next-like-this))

(use-package! easy-kill
  :config
  (map! "M-w" #'easy-kill
        "s-," #'easy-mark))

(use-package! yasnippet
  :init
  (add-to-list 'yas-snippet-dirs (expand-file-name "~/.config/doom/snippets"))
  :config
  (yas-global-mode 1))

(use-package! embark
  :ensure t
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)
         ("C-h B" . embark-bindings))
  :init
  (setq prefix-help-command #'embark-prefix-help-command))

;;; GitLab integration
;; The token is decrypted by agenix to ~/.config/gitlab-token; never put it
;; directly in this repository. lab-config is set when lab loads.
(after! lab
  (let ((gitlab-token-file (expand-file-name "~/.config/gitlab-token")))
    (setq lab-config
          `((:host "https://gitlab.lichtblick.app/"
             :token ,(when (file-exists-p gitlab-token-file)
                       (with-temp-buffer
                         (insert-file-contents gitlab-token-file)
                         (string-trim (buffer-string))))
             :group "lichtblick")))))
