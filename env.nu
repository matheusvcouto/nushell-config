# ENV Conversions
$env.ENV_CONVERSIONS = {
    "PATH": {
        from_string: { |s| $s | split row (char esep) | path expand --no-symlink }
        to_string: { |v| $v | path expand --no-symlink | str join (char esep) }
    }
    "Path": {
        from_string: { |s| $s | split row (char esep) | path expand --no-symlink }
        to_string: { |v| $v | path expand --no-symlink | str join (char esep) }
    }
}

# Load .env file if it exists (OS-agnostic, works on Windows/Linux/macOS)
const env_file = $nu.env-path | path dirname | path join '.env'

if ($env_file | path exists) {
    open $env_file
    | lines
    | where ($it | str length) > 0
    | where ($it | str starts-with '#') == false
    | parse -r '(?P<key>[^=]+)=(?P<value>.*)'
    | reduce --fold {} {|row, acc|
        $acc | insert ($row | get key) ($row.value | str trim -c '"')
    }
    | load-env
}

# Git
$env.GIT_EDITOR = "hx"

# Editor
$env.EDITOR = "code"

# Tools and SDKs
$env.ANDROID_HOME = $"($env.HOME)/Library/Android/sdk"
$env.ANDROID_EMULATOR_DEFAULT_AVD = "Pixel_9"
$env.BUN_INSTALL = $"($env.HOME)/.bun"
$env.PGT_LOG_PATH = $"($env.HOME)/.cache/postgrestools-pg-log"

# Path Management (Modular and Clean)
# Equivalent to fish_add_path: adds paths, keeps them unique, and ensures they exist.
$env.PATH = (
    $env.PATH
    | prepend $"($env.HOME)/.local/share/mise/shims"
    | append [
        $"($env.ANDROID_HOME)/emulator"
        $"($env.ANDROID_HOME)/platform-tools"
        $"($env.HOME)/.flutter/bin"
        $"($env.BUN_INSTALL)/bin"
    ]
    | uniq
    | where { |p| $p | path exists }
)

# Mise Activation
# Gera o módulo de ativação oficial do Nushell.
let mise_path = $nu.default-config-dir | path join "mise.nu"
if (which mise | is-not-empty) {
    ^mise activate nu | save $mise_path --force
}
