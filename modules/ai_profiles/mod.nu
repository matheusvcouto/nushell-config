# Isolated account profiles for AI CLIs.

const PROFILE_NAME_PATTERN = '^[A-Za-z0-9_-]+$'

def nu-complete-claude-profiles [] {
    profile-list "claude"
}

def nu-complete-codex-profiles [] {
    profile-list "codex"
}

def profile-prefix [
    tool: string
] {
    $".($tool)-"
}

def profile-path [
    tool: string
    profile: string
] {
    $"~/.($tool)-($profile)" | path expand
}

def assert-valid-profile-name [
    profile: string
] {
    if not ($profile =~ $PROFILE_NAME_PATTERN) {
        error make {
            msg: $"Nome de perfil inválido: ($profile). Use apenas letras, números, _ ou -"
        }
    }
}

def profile-list [
    tool: string
] {
    let prefix = (profile-prefix $tool)

    glob $"~/.($tool)-*"
    | where {|path| ($path | path type) == dir }
    | each {|path| $path | path basename | str replace $prefix "" }
    | sort
}

def profile-list-message [
    profiles: list<string>
] {
    if ($profiles | is-empty) {
        "nenhum perfil criado"
    } else {
        $profiles | str join ', '
    }
}

def existing-profile-dir [
    tool: string
    profile: string
] {
    assert-valid-profile-name $profile

    let profiles = (profile-list $tool)
    if $profile not-in $profiles {
        error make {
            msg: $"Perfil ($tool) inválido: ($profile). Disponíveis: (profile-list-message $profiles)"
        }
    }

    profile-path $tool $profile
}

def create-profile [
    tool: string
    profile: string
] {
    assert-valid-profile-name $profile

    let dir = (profile-path $tool $profile)
    if ($dir | path exists) {
        error make {
            msg: $"Perfil ($tool) já existe: ($profile)"
        }
    }

    mkdir $dir
    $dir
}

def rename-profile [
    tool: string
    old: string
    new: string
] {
    let old_dir = (existing-profile-dir $tool $old)
    assert-valid-profile-name $new

    let new_dir = (profile-path $tool $new)
    if ($new_dir | path exists) {
        error make {
            msg: $"Perfil ($tool) já existe: ($new)"
        }
    }

    mv $old_dir $new_dir
    $new_dir
}

export def --wrapped claude-as [
    profile: string@nu-complete-claude-profiles
    ...args
] {
    let dir = (existing-profile-dir "claude" $profile)

    with-env {
        CLAUDE_CONFIG_DIR: $dir
        ANTHROPIC_API_KEY: null
        ANTHROPIC_AUTH_TOKEN: null
        CLAUDE_CODE_OAUTH_TOKEN: null
        ANTHROPIC_BASE_URL: null
    } {
        ^claude ...$args
    }
}

export def claude-profiles [] {
    profile-list "claude"
}

export def claude-profile-new [
    profile: string
] {
    create-profile "claude" $profile
}

export def claude-profile-rename [
    old: string@nu-complete-claude-profiles
    new: string
] {
    rename-profile "claude" $old $new
}

export def --wrapped codex-as [
    profile: string@nu-complete-codex-profiles
    ...args
] {
    let dir = (existing-profile-dir "codex" $profile)

    with-env {
        CODEX_HOME: $dir
        OPENAI_API_KEY: null
    } {
        ^codex ...$args
    }
}

export def codex-profiles [] {
    profile-list "codex"
}

export def codex-profile-new [
    profile: string
] {
    create-profile "codex" $profile
}

export def codex-profile-rename [
    old: string@nu-complete-codex-profiles
    new: string
] {
    rename-profile "codex" $old $new
}
