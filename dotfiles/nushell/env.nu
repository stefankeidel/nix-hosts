use std "path add"

let user = ($env.USER? | default $env.USERNAME?)
if $user == null {
  error make { msg: "Missing USER/USERNAME env var for per-user profile path." }
}

path add $"/etc/profiles/per-user/($user)/bin/"
path add /run/current-system/sw/bin/

# some other random stuff we also have set in zsh
$env.EDITOR = 'vim'
$env.PYTHONBREAKPOINT = 'pudb.set_trace'
$env.LSP_USE_PLISTS = "true"
$env.AIRFLOW_UID = 502
$env.AIRFLOW_GID = 0
$env.AIRFLOW_PLATFORM = "linux/arm64"

# init carapace
# $env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense' # optional
mkdir $"($nu.cache-dir)"
carapace _carapace nushell | save --force $"($nu.cache-dir)/carapace.nu"

# init zoxide https://github.com/ajeetdsouza/zoxide
# 
zoxide init nushell | save -f ~/.zoxide.nu
