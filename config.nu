$env.config.show_banner = false
$env.EDITOR = "code"
alias ll = ls -l
alias n = nvim

$env.PGT_LOG_PATH = $"($env.HOME)/.cache/postgrestools-pg-log"
$env.BUN_INSTALL = $"($env.HOME)/.bun"

# Configuração de completions externas para bun run (scripts + arquivos)
use modules/completions [external_completer]

$env.config.completions.external = {
    enable: true
    max_results: 100
    completer: {|spans| external_completer $spans }
}

source ~/.zoxide.nu

#
# Installed by:
# version = "0.110.0"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# Nushell sets "sensible defaults" for most configuration settings, 
# so your `config.nu` only needs to override these defaults if desired.
#
# You can open this file in your default editor using:
#     config nu
#
# You can also pretty-print and page through the documentation for configuration
# options using:
#     config nu --doc | nu-highlight | less -R
