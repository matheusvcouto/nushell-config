# modules/completions/nvim.nu

def normalize-path [path: string] {
    $path | str replace --all "\\" "/"
}

def is-excluded-dir [relative: string] {
    let excluded_dirs = [
        ".git"
        "node_modules"
        ".next"
        ".expo"
        "dist"
        "build"
        "coverage"
        "target"
        ".cache"
    ]

    let parts = ($relative | split row "/")
    $parts | any {|part| $part in $excluded_dirs}
}

def is-binary-like [relative: string] {
    let lowered = ($relative | str downcase)
    let blocked_exts = [
        ".png" ".jpg" ".jpeg" ".gif" ".webp" ".ico" ".svg"
        ".mp4" ".mov" ".avi" ".mkv" ".webm"
        ".mp3" ".wav" ".ogg" ".flac"
        ".zip" ".tar" ".gz" ".bz2" ".xz" ".7z" ".rar"
        ".pdf" ".dmg" ".exe" ".dll" ".so" ".a" ".o" ".class" ".jar" ".bin"
    ]

    $blocked_exts | any {|ext| $lowered | str ends-with $ext}
}

def should-keep [relative: string] {
    if ($relative | is-empty) {
        false
    } else if (is-excluded-dir $relative) {
        false
    } else if (is-binary-like $relative) {
        false
    } else {
        true
    }
}

def git-files [] {
    let check = (^git rev-parse --is-inside-work-tree | complete)
    if $check.exit_code != 0 {
        return []
    }

    ^git ls-files --cached --others --exclude-standard
    | lines
    | each {|line| normalize-path $line}
}

def glob-files [depth: int] {
    let raw = (glob "**/*" --depth $depth)
    $raw
    | where {|p| ($p | path type) == "file"}
    | each {|file|
        let relative = ($file | path relative-to $env.PWD)
        normalize-path $relative
    }
}

def env-files [depth: int] {
    let root_env = (glob ".env*")
    let nested_env = (glob "**/.env*" --depth $depth)

    [$root_env $nested_env]
    | flatten
    | where {|p| ($p | path type) == "file"}
    | each {|file|
        let relative = ($file | path relative-to $env.PWD)
        normalize-path $relative
    }
}

def match-paths [paths: list<string>, needle: string] {
    if ($needle | is-empty) {
        $paths | first 120
    } else {
        $paths
        | where {|path| ($path | str downcase) | str contains $needle}
        | first 120
    }
}

# Completer específico para `nvim` e alias como `n`
export def nvim_completer [spans: list<string>] {
    let expanded_alias = (scope aliases
        | where name == $spans.0
        | get --optional 0
        | get --optional expansion)

    let real_cmd = (if $expanded_alias != null {
        $expanded_alias | split row " " | take 1
    } else {
        $spans.0
    })

    if not ($real_cmd in ["nvim" "n"]) {
        return null
    }

    let full_spans = (if $expanded_alias != null {
        $spans | skip 1 | prepend ($expanded_alias | split row " ")
    } else {
        $spans
    })

    let partial = ($full_spans | get --optional 1 | default "")
    let depth = if ($partial | str contains "/") { 8 } else { 4 }
    let needle = ($partial | str downcase)

    let git_paths = (git-files)
    let discovered_paths = (if ($git_paths | is-empty) {
        glob-files $depth
    } else {
        env-files $depth
    })

    let git_matches = (match-paths $git_paths $needle)
    let discovered_matches = (match-paths $discovered_paths $needle)

    let candidates = (
        [$discovered_matches $git_matches]
        | flatten
        | uniq
        | where {|path| should-keep $path}
        | first 100
    )

    $candidates
    | each {|path| {value: $path, description: "Workspace file"}}
}
