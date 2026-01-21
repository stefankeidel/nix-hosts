use std "path add"

let user = ($env.USER? | default $env.USERNAME?)
if $user == null {
  error make { msg: "Missing USER/USERNAME env var for per-user profile path." }
}

path add $"/etc/profiles/per-user/($user)/bin/"

# init carapace
# $env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense' # optional
mkdir $"($nu.cache-dir)"
carapace _carapace nushell | save --force $"($nu.cache-dir)/carapace.nu"

# init zoxide https://github.com/ajeetdsouza/zoxide
# 
zoxide init nushell | save -f ~/.zoxide.nu
