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

# Editor
$env.EDITOR = "code"

# Android SDK
$env.ANDROID_HOME = $"($env.HOME)/Library/Android/sdk"
$env.PATH = ($env.PATH | split row (char esep) | append [$"($env.ANDROID_HOME)/emulator", $"($env.ANDROID_HOME)/platform-tools"] | str join (char esep))

# Bun
$env.BUN_INSTALL = $"($env.HOME)/.bun"
$env.PATH = ($env.PATH | split row (char esep) | append $"($env.BUN_INSTALL)/bin" | str join (char esep))

# Tools
$env.PGT_LOG_PATH = $"($env.HOME)/.cache/postgrestools-pg-log"