;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el
;; Package declarations only; run `doom sync' after changing these.

;; Editing and navigation
(package! browse-kill-ring)
(package! undo-tree)
(package! undo-fu :disable t)
(package! visual-regexp)
(package! visual-regexp-steroids)
(package! crux)
(package! multiple-cursors)
(package! rg)
(package! easy-kill)
(package! yasnippet)

;; Org and feeds
(package! german-holidays)
(package! ob-http)
(package! ob-sql-mode)
(package! org-modern)
(package! org-present)
(package! elfeed)

;; Development and GitLab
(package! mise)
(package! buffer-guardian
  :recipe (:host github :repo "jamescherti/buffer-guardian.el"))
(package! lab
  :recipe (:host github :repo "isamert/lab.el"))
(package! jj-mode
  :recipe (:host github :repo "bolivier/jj-mode.el")
  :pin "7e299b60e536d61e694f75fb7a2d1b922f09a5a5")
