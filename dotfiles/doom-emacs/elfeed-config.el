;;; elfeed-config.el -*- lexical-binding: t; -*-
;;; RSS feeds and Org capture from Elfeed.

(use-package! elfeed
  :config
  (map! "C-x w" #'elfeed)
  (map! :map elfeed-show-mode-map "v" #'elfeed-show-quick-url-note)

  (setq elfeed-feeds
        '(
          ;; Technology, politics, and events
          ("http://nullprogram.com/feed/" programming)
          ("https://hnrss.org/frontpage" hn maybe)
          ("https://netzpolitik.org/ticker/feed" maybe)
          ("https://netzpolitik.org/feed/" blog)
          ("https://fragdenstaat.de/artikel/feed/" blog)
          ("https://events.ccc.de/feed/" events security)
          ("https://www.ccc.de/rss/updates.rdf" security)

          ;; Blogs
          ("https://www.benkuhn.net/index.xml" blog)
          ("https://metaredux.com/feed.xml" blog interesting)
          ("https://github.blog/feed/atom" blog)
          ("https://blog.appliedcomputing.io/feed" blog)
          ("https://blog.openstreetmap.org/feed/" blog interesting)
          ("http://feeds.feedburner.com/martinkl" blog)
          ("https://den.dev/index.xml" blog)
          ("https://industrydecarbonization.com/rss.xml" blog interesting)
          ("https://www.bloodinthemachine.com/feed" blog)
          ("https://climatedrift.substack.com/feed" blog)
          ("https://craphound.com/feed" blog)
          ("https://pagedout.institute/rss.xml" blog)
          ("https://hannahritchie.substack.com/feed" blog)
          ("https://ourworldindata.org/atom-data-insights.xml" blog)
          ("https://ourworldindata.org/atom.xml" blog)
          ("https://michael.stapelberg.ch/feed.xml" blog)
          ("https://gregorygundersen.com/feed.xml" blog)
          ("https://www.natesilver.net/feed" blog)
          ("https://frogandtoadai.substack.com/feed" blob)

          ;; Economics and other reading
          ("https://www.lesswrong.com/feed.xml?view=curated-rss" blog)
          ("https://feedpress.me/TheTechnium" blog)
          ("https://www.construction-physics.com/feed" blog)
          ("https://www.optimallyirrational.com/feed" blog)
          ("https://www.statsignificant.com/feed" blog)

          ;; Emacs
          ("https://asylum.madhouse-project.org/blog/atom.xml" emacs blog)
          ("http://www.masteringemacs.org/feed/" emacs blog)
          ("https://pragmaticemacs.wordpress.com/feed" emacs blog)
          ("https://emacsredux.com/atom.xml" emacs blog)

          ;; Entertainment and bikes
          ("https://www.xkcd.com/rss.xml" comic)
          ("https://inrng.com/feed/" bikes)
          ("https://bikepacking.com/feed/" bikes interesting)
          ("https://fahrradzukunft.de/feed/" bikes)
          ("https://www.iamtedking.com/blog?format=rss" bikes interesting)
          ("https://www.renehersecycles.com/feed/" bikes interesting)

          ;; Data and work
          ("https://roundup.getdbt.com/feed" data blog)
          ("https://www.ssp.sh/index.xml" data blog)
          ("https://www.dataengineeringweekly.com/feed" blog)
          ("https://stkbailey.substack.com/feed" blog)
          ("https://seattledataguy.substack.com/feed" blog)
          ("https://martinfowler.com/feed.atom" blog)
          ("http://jpkoning.blogspot.com/feeds/posts/default?alt=rss" blog)
          ("https://motherduck.com/rss.xml" blog)
          ("https://dataengineeringcentral.substack.com/feed" blog)
          ("https://astral.sh/blog/rss.xml" blog)
          ("https://docs.getdbt.com/blog/rss.xml" data blog)))

  (defface interesting-elfeed-entry
    '((t :foreground "#f77"))
    "Interesting Elfeed entry.")
  (defface maybe-elfeed-entry
    '((t :foreground "grey"))
    "Maybe interesting Elfeed entry.")
  (push '(interesting interesting-elfeed-entry) elfeed-search-face-alist)
  (push '(maybe maybe-elfeed-entry) elfeed-search-face-alist)
  (setq-default elfeed-search-filter "@2-weeks-ago +unread ")

  (defun elfeed-show-quick-url-note ()
    "Capture the current Elfeed entry in the Org reading list."
    (interactive)
    (elfeed-link-title elfeed-show-entry)
    (org-capture nil "r")
    (yank)
    (org-capture-finalize)))

(after! elfeed
  (define-advice elfeed-search--header (:around (oldfun &rest args))
    (if elfeed-db
        (apply oldfun args)
      "No database loaded yet")))

(defun elfeed-link-title (entry)
  "Copy ENTRY's title and URL as an Org link to the clipboard."
  (interactive)
  (let* ((link (elfeed-entry-link entry))
         (title (elfeed-entry-title entry))
         (titlelink (concat "[[" link "][" title "]]")))
    (when titlelink
      (kill-new titlelink)
      (x-set-selection 'PRIMARY titlelink)
      (message "Yanked: %s" titlelink))))

(defun elfeed-show-link-title ()
  "Copy the current entry's title and URL as an Org link to the clipboard."
  (interactive)
  (elfeed-link-title elfeed-show-entry))
