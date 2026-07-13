;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el

;; To install a package with Doom you must declare them here and run 'doom sync'
;; on the command line, then restart Emacs for the changes to take effect -- or


;; To install SOME-PACKAGE from MELPA, ELPA or emacsmirror:
;; (package! some-package)

;; To install a package directly from a remote git repo, you must specify a
;; `:recipe'. You'll find documentation on what `:recipe' accepts here:
;; https://github.com/radian-software/straight.el#the-recipe-format
;; (package! another-package
;;   :recipe (:host github :repo "username/repo"))

;; If the package you are trying to install does not contain a PACKAGENAME.el
;; file, or is located in a subdirectory of the repo, you'll need to specify
;; `:files' in the `:recipe':
;; (package! this-package
;;   :recipe (:host github :repo "username/repo"
;;            :files ("some-file.el" "src/lisp/*.el")))

;; If you'd like to disable a package included with Doom, you can do so here
;; with the `:disable' property:
;; (package! builtin-package :disable t)

;; You can override the recipe of a built in package without having to specify
;; all the properties for `:recipe'. These will inherit the rest of its recipe
;; from Doom or MELPA/ELPA/Emacsmirror:
;; (package! builtin-package :recipe (:nonrecursive t))
;; (package! builtin-package-2 :recipe (:repo "myfork/package"))

;; Specify a `:branch' to install a package from a particular branch or tag.
;; This is required for some packages whose default branch isn't 'master' (which
;; our package manager can't deal with; see radian-software/straight.el#279)
;; (package! builtin-package :recipe (:branch "develop"))

;; Use `:pin' to specify a particular commit to install.
;; (package! builtin-package :pin "1a2b3c4d5e")


;; Doom's packages are pinned to a specific commit and updated from release to
;; release. The `unpin!' macro allows you to unpin single packages...
;; (unpin! pinned-package)
;; ...or multiple packages
;; (unpin! pinned-package another-pinned-package)
;; ...Or *all* packages (NOT RECOMMENDED; will likely break things)
;; (unpin! t)

(package! browse-kill-ring)
(package! german-holidays)
(package! undo-tree)
(package! visual-regexp)
(package! visual-regexp-steroids)
(package! crux)
(package! ob-http)
;(package! org-roam)
(package! multiple-cursors)
(package! ob-sql-mode)
(package! undo-fu :disable t)
(package! elfeed)
;(package! copilot)
;; (package! org-ql
;;   :recipe (:host github :repo "alphapapa/org-ql" :files ("*.el")))
;; (package! org-roam-ql)
(package! rg)
(package! easy-kill)
(package! yasnippet)
(package! mise)
;; (package! center-content-mode :pin "6527a1c8148c69b730d8d5517ee48fede5720f21"
;;   :recipe (:host nil :type git :repo "https://git.larstvei.no/larstvei/center-content-mode.git"))
;; (package! macher :pin "d447e262a336498b64e49afc04b76263955bbee7"
;;   :recipe (:host github :repo "kmontag/macher" :files ("*.el")))
(package! gptel-autocomplete :pin "8ace326a6e7b8a3a4df7a6e80272b472e7fbd167"
  :recipe (:host github :repo "JDNdeveloper/gptel-autocomplete" :files ("*.el")))
(package! org-modern)
(package! org-present)
(package! shell-maker)
(package! acp)
(package! agent-shell)

(package! buffer-guardian
  :recipe
  (:host github :repo "jamescherti/buffer-guardian.el"))
