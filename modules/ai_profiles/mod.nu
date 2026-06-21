# Isolated account profiles for AI CLIs.
#
# Todos os perfis vivem dentro de PROFILES_ROOT, cada um numa pasta com ID
# opaco (ex: ~/.ai-profiles/claude-x7k2p9qa1z). O "nome" que você usa nos
# comandos (alias, ex: "mae") é só um rótulo guardado em PROFILES_FILE,
# nunca o nome real da pasta.
#
# Por quê: muitas CLIs (Claude Code incluso) amarram credenciais ao caminho
# absoluto do config dir (ex: Keychain do macOS é indexado por hash do
# path). Se o "nome" do perfil fosse o nome da pasta, renomear o perfil
# exigiria mover a pasta e invalidaria a credencial. Com o ID fixo e nunca
# reaproveitado para nada visível, renomear um alias nunca precisa mover ou
# tocar a pasta — e como o ID nunca aparece em mais nenhum lugar, um
# `ls ~/.ai-profiles` não fica com nomes "errados" depois de um rename.

const PROFILE_NAME_PATTERN = '^[A-Za-z0-9_-]+$'
const PROFILES_ROOT = "~/.ai-profiles"
const PROFILES_FILE = "~/.ai-profiles/index.nuon"

def nu-complete-claude-profiles [] {
    profile-list "claude"
}

def nu-complete-codex-profiles [] {
    profile-list "codex"
}

def profiles-root-path [] {
    $PROFILES_ROOT | path expand
}

def profiles-file-path [] {
    $PROFILES_FILE | path expand
}

def read-profile-map [] {
    let path = (profiles-file-path)
    if ($path | path exists) {
        open $path
    } else {
        []
    }
}

def write-profile-map [entries: list] {
    mkdir (profiles-root-path)
    $entries | save --force (profiles-file-path)
}

# Caminho usado apenas para criar um perfil novo (primeira vez). O ID é
# opaco e definitivo: nunca é regenerado nem reaproveitado para o alias.
def new-profile-dir [
    tool: string
] {
    let id = (random chars --length 10 | str downcase)
    $"(profiles-root-path)/($tool)-($id)"
}

def profile-path [
    tool: string
    profile: string
] {
    read-profile-map
    | where {|e| $e.tool == $tool and $e.alias == $profile}
    | get --optional 0
    | get dir
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
    read-profile-map | where tool == $tool | get alias | sort
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

    let existing = (profile-list $tool)
    if $profile in $existing {
        error make {
            msg: $"Perfil ($tool) já existe: ($profile)"
        }
    }

    let dir = (new-profile-dir $tool)
    mkdir $dir

    let entries = (read-profile-map)
    write-profile-map ($entries | append {
        tool: $tool
        alias: $profile
        dir: $dir
        created_at: (date now | format date "%Y-%m-%dT%H:%M:%S")
    })

    $dir
}

# Renomeia apenas o alias no PROFILES_FILE. O diretório físico (e portanto
# qualquer credencial de keychain/cache amarrada a ele) nunca é tocado, então
# o login da CLI continua valendo depois do rename.
def rename-profile [
    tool: string
    old: string
    new: string
] {
    existing-profile-dir $tool $old | ignore
    assert-valid-profile-name $new

    let existing = (profile-list $tool)
    if $new in $existing {
        error make {
            msg: $"Perfil ($tool) já existe: ($new)"
        }
    }

    let entries = (
        read-profile-map
        | each {|e|
            if $e.tool == $tool and $e.alias == $old {
                $e | update alias $new
            } else {
                $e
            }
        }
    )
    write-profile-map $entries

    profile-path $tool $new
}

def delete-profile [
    tool: string
    profile: string
] {
    let dir = (existing-profile-dir $tool $profile)
    print $"Isso vai mover para a lixeira: ($dir)"

    let typed_profile = (input $"Digite o nome do perfil para confirmar: ")
    if $typed_profile != $profile {
        error make {
            msg: $"Confirmação inválida. Esperado: ($profile)"
        }
    }

    let answer = (input "Confirmar exclusão? [y/N]: " | str downcase)
    if $answer not-in ["y", "yes"] {
        error make {
            msg: "Exclusão cancelada"
        }
    }

    let trash_dir = ("~/.Trash" | path expand)
    mkdir $trash_dir

    let deleted_at = (date now | format date "%Y%m%d-%H%M%S")
    let trash_name = $"($dir | path basename)-($deleted_at)"
    let trash_path = ($trash_dir | path join $trash_name)

    mv $dir $trash_path

    let entries = (
        read-profile-map
        | where {|e| not ($e.tool == $tool and $e.alias == $profile)}
    )
    write-profile-map $entries

    $trash_path
}

export def --wrapped claude-as [
    profile: string@nu-complete-claude-profiles
    ...args
] {
    let dir = (existing-profile-dir "claude" $profile)

    with-env {
        CLAUDE_CONFIG_DIR: $dir
        CLAUDE_CODE_USE_BEDROCK: null
        CLAUDE_CODE_USE_VERTEX: null
        CLAUDE_CODE_USE_FOUNDRY: null
        ANTHROPIC_API_KEY: null
        ANTHROPIC_AUTH_TOKEN: null
        CLAUDE_CODE_OAUTH_TOKEN: null
        ANTHROPIC_BASE_URL: null
    } {
        ^claude ...$args
    }
}

export def claude-profile [] {
    profile-list "claude"
}

export def "claude-profile list" [] {
    profile-list "claude"
}

export def "claude-profile new" [
    profile: string
] {
    create-profile "claude" $profile
}

export def "claude-profile rename" [
    old: string@nu-complete-claude-profiles
    new: string
] {
    rename-profile "claude" $old $new
}

export def "claude-profile delete" [
    profile: string@nu-complete-claude-profiles
] {
    delete-profile "claude" $profile
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

export def codex-profile [] {
    profile-list "codex"
}

export def "codex-profile list" [] {
    profile-list "codex"
}

export def "codex-profile new" [
    profile: string
] {
    create-profile "codex" $profile
}

export def "codex-profile rename" [
    old: string@nu-complete-codex-profiles
    new: string
] {
    rename-profile "codex" $old $new
}

export def "codex-profile delete" [
    profile: string@nu-complete-codex-profiles
] {
    delete-profile "codex" $profile
}
