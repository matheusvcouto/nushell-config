# Isolated account profiles for AI CLIs.

const CLAUDE_PROFILES = ["mae"]
const CODEX_PROFILES = []

def nu-complete-claude-profiles [] {
    $CLAUDE_PROFILES
}

def nu-complete-codex-profiles [] {
    $CODEX_PROFILES
}

def profile-dir [
    tool: string
    profile: string
    profiles: list<string>
] {
    if $profile not-in $profiles {
        error make {
            msg: $"Perfil ($tool) inválido: ($profile). Disponíveis: ($profiles | str join ', ')"
        }
    }

    let dir = ($"~/.($tool)-($profile)" | path expand)
    mkdir $dir
    $dir
}

export def --wrapped claude-as [
    profile: string@nu-complete-claude-profiles
    ...args
] {
    let dir = (profile-dir "claude" $profile $CLAUDE_PROFILES)

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

export def --wrapped codex-as [
    profile: string@nu-complete-codex-profiles
    ...args
] {
    let dir = (profile-dir "codex" $profile $CODEX_PROFILES)

    with-env {
        CODEX_HOME: $dir
        OPENAI_API_KEY: null
    } {
        ^codex ...$args
    }
}
