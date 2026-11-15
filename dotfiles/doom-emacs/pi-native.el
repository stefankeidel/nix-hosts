;;; pi-native.el --- Local Pi bridge with Ghostel rendering -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'json)
(require 'server)
(require 'subr-x)

(defvar stefan-pi--sessions (make-hash-table :test #'equal))
(defvar-local stefan-pi--session nil)
(defvar-local stefan-pi--source nil)
(defvar-local stefan-pi--selection nil)

(defun stefan-pi--terminal (session)
  "Return the live terminal registered for SESSION."
  (let ((buffer (gethash session stefan-pi--sessions)))
    (unless (buffer-live-p buffer)
      (error "Pi session is no longer attached; reopen Pi from Emacs"))
    buffer))

(defun stefan-pi--source-buffer (session)
  "Return SESSION's source buffer, failing rather than guessing."
  (let ((source (buffer-local-value 'stefan-pi--source
                                    (stefan-pi--terminal session))))
    (unless (buffer-live-p source)
      (error "Source buffer was killed; reopen Pi from a source buffer"))
    source))

(defun stefan-pi--clip (text)
  "Bound TEXT before sending it to Pi."
  (if (> (length text) 12000)
      (concat (substring text 0 12000) "\n[truncated]")
    text))

(defun stefan-pi--context (session)
  "Describe SESSION's source, including unsaved text near point."
  (let* ((terminal (stefan-pi--terminal session))
         (selection (buffer-local-value 'stefan-pi--selection terminal)))
    (with-current-buffer (stefan-pi--source-buffer session)
      `((buffer . ,(buffer-name))
        (file . ,buffer-file-name)
        (mode . ,(symbol-name major-mode))
        (directory . ,default-directory)
        (modified . ,(if (buffer-modified-p) t :false))
        (point . ,(point))
        (line . ,(line-number-at-pos))
        (selection . ,selection)
        (excerpt_start . ,(max (point-min) (- (point) 2000)))
        (excerpt . ,(buffer-substring-no-properties
                     (max (point-min) (- (point) 2000))
                     (min (point-max) (+ (point) 2000))))))))

(defun stefan-pi--eval (session code buffer-name)
  "Evaluate CODE in SESSION's source or explicit existing BUFFER-NAME.
This is unrestricted Elisp, not a sandbox.  Pi asks before calling it."
  (stefan-pi--terminal session)
  (let ((buffer (if buffer-name
                    (or (get-buffer buffer-name)
                        (error "No such buffer: %s" buffer-name))
                  (stefan-pi--source-buffer session))))
    (with-current-buffer buffer
      (let ((standard-output (get-buffer-create " *pi-eval-output*"))
            (print-length 100)
            (print-level 20)
            (print-circle t))
        (with-current-buffer standard-output (erase-buffer))
        (let ((value (eval (read (concat "(progn\n" code "\n)")) t)))
          `((buffer . ,(buffer-name))
            (value . ,(stefan-pi--clip (prin1-to-string value)))
            (output . ,(with-current-buffer standard-output
                         (stefan-pi--clip (buffer-string))))))))))

(defun stefan-pi-request (encoded)
  "Handle a base64-encoded JSON request from the local Pi extension.
Return base64 JSON so emacsclient's Lisp string escaping is unambiguous."
  (let ((response
         (condition-case err
             (let* ((request (json-parse-string
                              (decode-coding-string (base64-decode-string encoded) 'utf-8)
                              :object-type 'alist :null-object nil))
                    (session (alist-get 'session request))
                    (operation (alist-get 'operation request)))
               `((ok . t)
                 (result . ,(pcase operation
                              ("context" (stefan-pi--context session))
                              ("eval" (stefan-pi--eval session
                                                       (alist-get 'code request)
                                                       (alist-get 'buffer request)))
                              (_ (error "Unknown Pi operation"))))))
           (error `((ok . :false) (error . ,(error-message-string err)))))))
    (base64-encode-string (encode-coding-string (json-serialize response
                                              :false-object :false
                                              :null-object nil) 'utf-8) t)))

(defun stefan-pi-return-to-source ()
  "Return from the Pi terminal to its source buffer."
  (interactive)
  (pop-to-buffer (stefan-pi--source-buffer stefan-pi--session)))

(define-minor-mode stefan-pi-native-mode
  "Pi terminal attached to this Emacs instance.
Use `stefan-pi-return-to-source' to return to the source buffer."
  :lighter " Pi"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "s-i b") #'stefan-pi-return-to-source)
            map))

(defun stefan-pi--forget-session ()
  "Detach this terminal's bridge when it is killed."
  (remhash stefan-pi--session stefan-pi--sessions))

(defun stefan-pi-open (&optional where)
  "Open the project's native Pi terminal, placed according to WHERE.
WHERE is nil, `window', or `frame'.  Calling from a source buffer retargets
context; calling from the Pi terminal preserves the previous source."
  (interactive)
  (require 'ghostel)
  (require 'projectile)
  (let* ((source (if stefan-pi-native-mode stefan-pi--source (current-buffer)))
         (selection (if stefan-pi-native-mode stefan-pi--selection
                      (when (use-region-p)
                        (stefan-pi--clip (buffer-substring-no-properties
                                         (region-beginning) (region-end))))))
         (root (file-name-as-directory (file-truename (projectile-project-root))))
         (name (format "**pi-native %s %s**"
                       (file-name-nondirectory (directory-file-name root))
                       (substring (secure-hash 'sha256 root) 0 8)))
         (buffer (get-buffer name)))
    (when (file-remote-p root)
      (user-error "The native Pi bridge supports local projects only"))
    (unless (executable-find "pi") (user-error "Cannot find pi in exec-path"))
    (when server-use-tcp (user-error "The Pi bridge requires a local Emacs socket"))
    ;; Another GUI Emacs may already own the default socket.  Never attach to it.
    (unless (process-live-p server-process)
      (when (server-running-p)
        (setq server-name (format "pi-%s" (emacs-pid))))
      (server-start))
    (unless buffer
      (setq buffer (get-buffer-create name)))
    (pcase where
      ('window (switch-to-buffer-other-window buffer))
      ('frame (switch-to-buffer-other-frame buffer))
      (_ (switch-to-buffer buffer)))
    (with-current-buffer buffer
      (unless (and stefan-pi-native-mode (get-buffer-process buffer)
                   (process-live-p (get-buffer-process buffer)))
        (let* ((session (secure-hash 'sha256 (format "%s%s%s" (emacs-pid) (float-time) (random))))
               (process-environment (copy-sequence process-environment))
               (default-directory root))
          (setenv "PI_EMACS_SOCKET" (expand-file-name server-name server-socket-dir))
          (setenv "PI_EMACS_SESSION" session)
          (setenv "PI_EMACS_CLIENT" (or (executable-find "emacsclient")
                                        (user-error "Cannot find emacsclient")))
          (ghostel-exec buffer (executable-find "pi"))
          (when stefan-pi--session (remhash stefan-pi--session stefan-pi--sessions))
          (setq-local stefan-pi--session session)
          (puthash session buffer stefan-pi--sessions)
          (stefan-pi-native-mode 1)
          (add-hook 'kill-buffer-hook #'stefan-pi--forget-session nil t)))
      (setq-local stefan-pi--source source
                  stefan-pi--selection selection))
    buffer))

(defun stefan-projectile-run-pi ()
  "Open the project's Emacs-attached Pi terminal."
  (interactive)
  (stefan-pi-open))

(defun stefan-projectile-run-pi-other-window ()
  "Open the project's Emacs-attached Pi in another window."
  (interactive)
  (stefan-pi-open 'window))

(defun stefan-projectile-run-pi-other-frame ()
  "Open the project's Emacs-attached Pi in another frame."
  (interactive)
  (stefan-pi-open 'frame))

(provide 'pi-native)
;;; pi-native.el ends here
