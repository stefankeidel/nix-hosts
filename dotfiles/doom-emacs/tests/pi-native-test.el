;;; pi-native-test.el -*- lexical-binding: t; -*-
(require 'ert)
(load (expand-file-name "../pi-native.el" (file-name-directory load-file-name)) nil t)

(defmacro stefan-pi-test--session (&rest body)
  `(let ((source (generate-new-buffer "pi-test-source"))
         (terminal (generate-new-buffer "pi-test-terminal"))
         (stefan-pi--sessions (make-hash-table :test #'equal)))
     (unwind-protect
         (progn
           (puthash "test" terminal stefan-pi--sessions)
           (with-current-buffer terminal (setq stefan-pi--source source))
           ,@body)
       (kill-buffer source)
       (kill-buffer terminal))))

(defun stefan-pi-test--request (request)
  (json-parse-string
   (decode-coding-string
    (base64-decode-string
     (stefan-pi-request
      (base64-encode-string (encode-coding-string (json-serialize request) 'utf-8) t)))
    'utf-8)
   :object-type 'alist :false-object nil :null-object nil))

(ert-deftest stefan-pi-context-unsaved-source ()
  (stefan-pi-test--session
   (with-current-buffer source
     (insert "unsaved buffer text")
     (goto-char 5))
   (with-current-buffer terminal (setq stefan-pi--selection "selected text"))
   (let ((context (stefan-pi--context "test")))
     (should (equal (alist-get 'excerpt context) "unsaved buffer text"))
     (should (equal (alist-get 'selection context) "selected text"))
     (should (= (alist-get 'point context) 5))
     (should (eq (alist-get 'modified context) t)))))

(ert-deftest stefan-pi-eval-mutates-source-not-current-buffer ()
  (stefan-pi-test--session
   (with-current-buffer terminal
     (let ((result (stefan-pi--eval "test" "(insert \"hello\") (princ \"output\") (+ 20 22)" nil)))
       (should (equal (alist-get 'value result) "42"))
       (should (equal (alist-get 'output result) "output"))))
   (should (equal (with-current-buffer source (buffer-string)) "hello"))
   (should (equal (with-current-buffer terminal (buffer-string)) ""))))

(ert-deftest stefan-pi-eval-explicit-buffer ()
  (stefan-pi-test--session
   (stefan-pi--eval "test" "(insert \"target\")" (buffer-name terminal))
   (should (equal (with-current-buffer terminal (buffer-string)) "target"))
   (should-error (stefan-pi--eval "test" "nil" "missing-pi-test-buffer"))))

(ert-deftest stefan-pi-eval-multiple-forms-and-lexical-binding ()
  (stefan-pi-test--session
   (should (equal (alist-get 'value (stefan-pi--eval
                                    "test" ";; comment\n(setq-local pi-test-value 7)\n(let ((x 3)) (funcall (lambda () (+ x pi-test-value))))" nil))
                  "10"))))

(ert-deftest stefan-pi-dead-source-does-not-fall-back ()
  (stefan-pi-test--session
   (kill-buffer source)
   (should-error (stefan-pi--context "test"))
   (should-error (stefan-pi--eval "test" "(+ 1 2)" nil))))

(ert-deftest stefan-pi-unknown-session-rejected ()
  (let ((response (stefan-pi-test--request '((session . "missing") (operation . "context")))))
    (should-not (alist-get 'ok response))
    (should (string-match-p "no longer attached" (alist-get 'error response)))))

(ert-deftest stefan-pi-protocol-unicode-and-errors ()
  (stefan-pi-test--session
   (let* ((text (concat "quotes \" slash \\ newline\n" (string #x3bb #x1f600)))
          (response (stefan-pi-test--request
                     `((session . "test") (operation . "eval") (code . ,(prin1-to-string text))))))
     (should (alist-get 'ok response))
     (should (equal (alist-get 'value (alist-get 'result response)) (prin1-to-string text))))
   (let ((response (stefan-pi-test--request
                    '((session . "test") (operation . "eval") (code . "(error \"test failure\")")))))
     (should-not (alist-get 'ok response))
     (should (equal (alist-get 'error response) "test failure")))))

(ert-deftest stefan-pi-bounded-context-and-result ()
  (stefan-pi-test--session
   (with-current-buffer source (insert (make-string 20000 ?x)) (goto-char 10000))
   (should (= (length (alist-get 'excerpt (stefan-pi--context "test"))) 4000))
   (should (string-suffix-p "[truncated]"
                            (alist-get 'value (stefan-pi--eval "test" "(make-string 20000 ?x)" nil))))))

(ert-deftest stefan-pi-launch-reuse-retarget-and-restart ()
  (let* ((original-require (symbol-function 'require))
         (stefan-pi--sessions (make-hash-table :test #'equal))
         (source (generate-new-buffer "pi-launch-source"))
         (other (generate-new-buffer "pi-launch-other"))
         (server-process (make-pipe-process :name "pi-test-server" :noquery t))
         (server-use-tcp nil)
         (server-name "pi-test-exact")
         (server-socket-dir temporary-file-directory)
         (root default-directory)
         (starts 0)
         terminal child first-session env)
    (unwind-protect
        (save-window-excursion
          (cl-letf (((symbol-function 'require)
                     (lambda (feature &rest args)
                       (if (memq feature '(ghostel projectile)) t
                         (apply original-require feature args))))
                    ((symbol-function 'projectile-project-root) (lambda () root))
                    ((symbol-function 'executable-find) (lambda (name) (concat "/test/" name)))
                    ((symbol-function 'ghostel-exec)
                     (lambda (buffer _program)
                       (cl-incf starts)
                       (setq env (list (getenv "PI_EMACS_SOCKET") (getenv "PI_EMACS_SESSION")))
                       (setq child (make-pipe-process :name "pi-test-child" :buffer buffer :noquery t)))))
            (switch-to-buffer source)
            (setq terminal (stefan-pi-open))
            (setq first-session (buffer-local-value 'stefan-pi--session terminal))
            (should (equal (car env) (expand-file-name server-name server-socket-dir)))
            (should (equal (cadr env) first-session))
            (should (eq source (stefan-pi--source-buffer first-session)))
            (switch-to-buffer other)
            (should (eq terminal (stefan-pi-open)))
            (should (= starts 1))
            (should (eq other (stefan-pi--source-buffer first-session)))
            (should (eq terminal (stefan-pi-open)))
            (should (eq other (stefan-pi--source-buffer first-session)))
            (delete-process child)
            (stefan-pi-open)
            (should (= starts 2))
            (should-not (gethash first-session stefan-pi--sessions))
            (should (eq other (stefan-pi--source-buffer
                               (buffer-local-value 'stefan-pi--session terminal))))))
      (when (process-live-p child) (delete-process child))
      (delete-process server-process)
      (when (buffer-live-p terminal) (kill-buffer terminal))
      (kill-buffer source)
      (kill-buffer other))))

(ert-deftest stefan-pi-session-cleanup ()
  (stefan-pi-test--session
   (with-current-buffer terminal
     (setq stefan-pi--session "test")
     (stefan-pi--forget-session))
   (should-error (stefan-pi--terminal "test"))))
