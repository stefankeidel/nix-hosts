use std "path add"

path add /etc/profiles/per-user/stefan.keidel@lichtblick.de/bin/

# init carapace
# $env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense' # optional
mkdir $"($nu.cache-dir)"
carapace _carapace nushell | save --force $"($nu.cache-dir)/carapace.nu"

# init zoxide https://github.com/ajeetdsouza/zoxide
# 
zoxide init nushell | save -f ~/.zoxide.nu
