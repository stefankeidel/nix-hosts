# Pi in the running Emacs

This is a hybrid: Ghostel renders Pi's normal TUI, while a small minor mode and
Pi extension connect it to the Emacs instance that launched it. It is not a
separate RPC chat frontend, and keeps Pi's usual commands, extensions, sessions,
and confirmation dialogs.

## Use

After the usual rebuild/switch and an Emacs restart:

- `s-i x` or `s-p x`: open/reuse this project's attached Pi terminal.
- `s-p 4 x` / `s-p 5 x`: open it in another window / frame.
- `s-i b` in the Pi terminal: return to its source buffer.
- Open Pi again from another source buffer to retarget its context.

The terminal runs Pi directly, not a shell with a typed startup command. Its
name includes a hash of the canonical project root, so similarly named projects
do not share a terminal. Exiting Pi and reopening restarts it; killing the
terminal detaches its bridge. Old `**pi ...**` terminals are not reused.

Try: "Use emacs_context to inspect my selection, then use emacs_eval to insert
an Elisp comment in the attached buffer without saving it."

## Tools

`emacs_context` returns the attached buffer's name, file, major mode, directory,
modified flag, point/line, and a bounded excerpt of its live text. The selection
is captured when opening/retargeting Pi; point and excerpt are read live.
It does not automatically send buffer contents with every prompt.

`emacs_eval` evaluates one or more Elisp forms in that source buffer, or in an
explicitly named existing buffer. It returns the printed last value and captured
standard output. Evaluation uses lexical binding. Every call asks for approval
in Pi and fails closed without interactive UI. Source buffers may be unsaved,
non-file buffers. No buffer is saved automatically by the bridge.

Examples:

```elisp
(list (buffer-name) (point) major-mode)
(insert ";; edited by Pi\n")
(with-current-buffer "*scratch*" (buffer-string))
```

## Trust And Limits

This is unrestricted local Elisp, not a sandbox. Approved code can read other
buffers, access credentials, change files, or launch processes. Confirmation is
a workflow safeguard, not a security boundary against an agent that already has
shell access. Buffer text is data and should not be treated as instructions.

The bridge uses Emacs' local Unix socket and per-terminal attachment IDs. No TCP
listener or additional daemon is introduced. If another Emacs owns the default
socket, this instance starts its own named server. Normal Pi shell launches do
not register the Emacs tools. Remote/TRAMP projects and TCP Emacs servers are
not supported.

Elisp runs on Emacs' main thread: do not approve infinite loops, long-running
operations, or forms that wait for input. The client has a 30-second timeout,
but cancelling/timing out emacsclient cannot reliably interrupt running Elisp,
undo edits, or prevent a queued request from later executing. Use Emacs `C-g`
if necessary. Evaluation is sequential within Pi, but does not lock files against
other tools; avoid parallel filesystem and buffer edits to the same file.

After restarting Emacs, launch a fresh terminal through the binding. Session
attachments are deliberately not persisted or silently rebound to another Emacs.

## Tests

```sh
emacs --batch -Q -l dotfiles/doom-emacs/tests/pi-native-test.el \
  -f ert-run-tests-batch-and-exit

# Point NODE_PATH at the lib/node_modules directory of the installed Pi package.
NODE_PATH="$PI_NODE_MODULES" node --test modules/home/pi-extensions/tests/emacs.test.cjs
```

The extension tests optionally exercise a real server when
`PI_EMACS_TEST_SOCKET` names an isolated Emacs socket with a `smoke` attachment.
The graphical Ghostel rendering and Doom keymaps still need an interactive check.
