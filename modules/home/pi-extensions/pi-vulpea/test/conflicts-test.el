;;; conflicts-test.el --- Conflict and boundary regressions -*- lexical-binding: t; -*-
(load (expand-file-name "bridge-test.el" (file-name-directory load-file-name)) nil t)

(ert-deftest pi-vulpea-external-change-does-not-prompt-or-revert ()
  (pi-vulpea-test-vault
   (let* ((revision (pi-vulpea-test-revision area-id))
          (path (vulpea-note-path (pi-vulpea--note area-id)))
          (buffer (pi-vulpea--buffer path)))
     (with-temp-buffer
       (insert-file-contents path)
       (goto-char (point-max))
       (insert "\nExternal edit.\n")
       (write-region (point-min) (point-max) path nil 'silent))
     (set-file-times path (time-add (current-time) 10))
     (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) (ert-fail "Must not prompt in Emacs")))
               ((symbol-function 'y-or-n-p) (lambda (&rest _) (ert-fail "Must not prompt in Emacs"))))
       (should-error (pi-vulpea-test-call "update" :id area-id :revision revision
                                          :action "append" :text "must not overwrite"))
       (should-error (pi-vulpea-test-call "read" :id area-id)))
     (with-current-buffer buffer
       (should-not (string-match-p "External edit" (buffer-string)))))))

(ert-deftest pi-vulpea-symlink-escape-and-failed-child-rollback ()
  (pi-vulpea-test-vault
   (let ((outside (expand-file-name "outside.org" temp))
         (link (expand-file-name "escape.org" org-directory)))
     (with-temp-file outside (insert "Outside the vault."))
     (make-symbolic-link outside link)
     (should-error (pi-vulpea--path link))
     (should (= 0 (length (alist-get 'items (pi-vulpea-test-call "search" :query "Outside the vault."))))))
   (let ((before (alist-get 'content (pi-vulpea-test-call "read" :id area-id))))
     (should-error (pi-vulpea-test-call "create" :kind "project" :title "Invalid subtree"
					:parentId area-id :revision (pi-vulpea-test-revision area-id)
					:body "* Escapes parent"))
     (should (equal before (alist-get 'content (pi-vulpea-test-call "read" :id area-id)))))))

(ert-deftest pi-vulpea-index-existing-section-and-edit-it ()
  (pi-vulpea-test-vault
   (let* ((indexed (pi-vulpea-test-call "update" :id area-id :revision (pi-vulpea-test-revision area-id)
                                        :action "index" :outline '("Notes")))
          (notes-id (pi-vulpea-test-id indexed)))
     (should (= 1 (vulpea-note-level (pi-vulpea--note notes-id))))
     (pi-vulpea-test-call "update" :id notes-id :revision (pi-vulpea-test-revision notes-id)
                          :action "append" :text "** dbt triage\nOriginal reproduction steps.")
     (let* ((child (pi-vulpea-test-call "update" :id notes-id :revision (pi-vulpea-test-revision notes-id)
					:action "index" :outline '("dbt triage")))
            (child-id (pi-vulpea-test-id child)))
       (pi-vulpea-test-call "update" :id child-id :revision (pi-vulpea-test-revision child-id)
                            :action "replace" :oldText "Original reproduction steps." :text "Verified reproduction steps.")
       (should (string-match-p "Verified reproduction steps" (alist-get 'content (pi-vulpea-test-call "read" :id child-id)))))
     (should-error (pi-vulpea-test-call "update" :id area-id :revision (pi-vulpea-test-revision area-id)
					:action "index" :outline '("Missing")))
     (should-error (pi-vulpea-test-call "update" :id area-id :revision (pi-vulpea-test-revision area-id)
					:action "index" :outline '("Archive"))))))

(ert-deftest pi-vulpea-tagged-container-and-pagination ()
  (pi-vulpea-test-vault
   (with-current-buffer (pi-vulpea--buffer (vulpea-note-path (pi-vulpea--note area-id)))
     (goto-char (point-min))
     (re-search-forward "^\\* Tasks$")
     (org-set-tags '("work"))
     (pi-vulpea--save))
   (pi-vulpea-test-call "create" :kind "project" :title "Project A"
			:parentId area-id :revision (pi-vulpea-test-revision area-id))
   (pi-vulpea-test-call "create" :kind "project" :title "Project B"
			:parentId area-id :revision (pi-vulpea-test-revision area-id))
   (let* ((first (pi-vulpea-test-call "list" :kind "project" :limit 1))
          (second (pi-vulpea-test-call "list" :kind "project" :limit 1 :offset (alist-get 'nextOffset first))))
     (should (equal "Project A" (alist-get 'title (aref (alist-get 'items first) 0))))
     (should (equal "Project B" (alist-get 'title (aref (alist-get 'items second) 0))))
     (should-not (alist-get 'nextOffset second)))
   (let ((text (alist-get 'content (pi-vulpea-test-call "read" :id area-id))))
     (should (= 1 (with-temp-buffer (insert text) (goto-char (point-min))
                                    (let ((count 0)) (while (re-search-forward "^\\* Tasks" nil t)
                                                       (setq count (1+ count))) count)))))))
