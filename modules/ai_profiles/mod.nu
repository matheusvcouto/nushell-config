# Isolated account profiles for AI CLIs.
#
# Um único comando genérico (lê TOOLS, nenhum código duplicado por CLI):
#
#   ai-profile <tool> list
#   ai-profile <tool> new <nome>
#   ai-profile <tool> rename <antigo> <novo>
#   ai-profile <tool> delete <nome>
#   ai-profile <tool> run <perfil> ...args     -- roda a CLI isolada
#
# Pra adicionar uma CLI nova, só uma entrada em TOOLS (ver abaixo) — nenhum
# comando novo precisa ser escrito.
#
# Todos os perfis vivem dentro de PROFILES_ROOT, cada um numa pasta com ID
# opaco (ex: ~/.ai-profiles/claude-20260621163245-x7k2). O "nome" que você
# usa nos comandos (alias, ex: "mae") é só um rótulo guardado em
# PROFILES_FILE, nunca o nome real da pasta.
#
# Por quê: muitas CLIs (Claude Code incluso) amarram credenciais ao caminho
# absoluto do config dir (ex: Keychain do macOS é indexado por hash do
# path). Se o "nome" do perfil fosse o nome da pasta, renomear o perfil
# exigiria mover a pasta e invalidaria a credencial. Com o ID fixo e nunca
# reaproveitado para nada visível, renomear um alias nunca precisa mover ou
# tocar a pasta — e como o ID nunca aparece em mais nenhum lugar, um
# `ls ~/.ai-profiles` não fica com nomes "errados" depois de um rename.

use ../utils [safe-remove]

const PROFILE_NAME_PATTERN = '^[A-Za-z0-9_-]+$'
const PROFILES_ROOT = "~/.ai-profiles"
const PROFILES_FILE = "~/.ai-profiles/index.nuon"

# Cada entrada:
#   - name: valor que você digita como <tool> (ex: "claude")
#   - bin: binário a executar
#   - config_env: env var que a CLI usa pra apontar seu diretório de config
#                 (se a CLI não tiver uma var dedicada, "HOME" funciona, mas
#                 isola só o processo filho rodado pelo with-env, não afeta
#                 o resto do shell)
#   - clear_env: env vars de auth/API key a remover antes de rodar, pra não
#                vazar credencial do perfil ativo do shell principal
const TOOLS = [
    {
        name: "claude"
        bin: "claude"
        config_env: "CLAUDE_CONFIG_DIR"
        clear_env: [
            "CLAUDE_CODE_USE_BEDROCK"
            "CLAUDE_CODE_USE_VERTEX"
            "CLAUDE_CODE_USE_FOUNDRY"
            "ANTHROPIC_API_KEY"
            "ANTHROPIC_AUTH_TOKEN"
            "CLAUDE_CODE_OAUTH_TOKEN"
            "ANTHROPIC_BASE_URL"
        ]
    }
    {
        name: "codex"
        bin: "codex"
        config_env: "CODEX_HOME"
        clear_env: ["OPENAI_API_KEY"]
    }
    {
        # "agy" é o binário da CLI do produto Antigravity (Google). Usamos
        # o nome do binário, não do produto, porque é isso que você digita
        # pra rodar a CLI sozinha.
        name: "agy"
        bin: "agy"
        # agy não tem uma env var dedicada de config dir (usa $HOME
        # diretamente). Sobrescrever HOME aqui só afeta o processo do agy
        # rodado dentro do with-env, não o shell.
        config_env: "HOME"
        clear_env: ["ANTIGRAVITY_API_KEY"]
    }
]

def tool-spec [
    tool: string
] {
    let spec = ($TOOLS | where name == $tool | get --optional 0)
    if $spec == null {
        let names = ($TOOLS | get name | str join ', ')
        error make {
            msg: $"CLI desconhecida: ($tool). Disponíveis: ($names)"
        }
    }
    $spec
}

def nu-complete-tools [] {
    $TOOLS | get name
}

def nu-complete-actions [] {
    ["list" "new" "rename" "delete" "run"]
}

# Completer usado pra qualquer argumento que represente um nome de perfil
# (no "run" e no "rename"/"delete" do ai-profile). Acha a CLI já digitada
# olhando os tokens da linha — nesses comandos o tool é sempre um argumento
# literal (não escondido atrás de alias), então não tem ambiguidade.
def nu-complete-profile-arg [context: string] {
    let tools = ($TOOLS | get name)
    let tool = ($context | split row " " | where {|t| $t in $tools} | get --optional 0)
    if $tool == null {
        []
    } else {
        profile-list $tool
    }
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
# Formato timestamp+sufixo: ordenável por data de criação só olhando o
# nome, e a chance de colisão (mesma CLI, mesmo segundo, mesmo sufixo de 4
# chars) é desprezível sem precisar implementar ULID/UUID.
def new-profile-dir [
    tool: string
] {
    let stamp = (date now | format date "%Y%m%d%H%M%S")
    let suffix = (random chars --length 4 | str downcase)
    $"(profiles-root-path)/($tool)-($stamp)-($suffix)"
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
    tool-spec $tool | ignore

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
    print $"Isso vai apagar permanentemente: ($dir)"

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

    safe-remove $dir (profiles-root-path)

    let entries = (
        read-profile-map
        | where {|e| not ($e.tool == $tool and $e.alias == $profile)}
    )
    write-profile-map $entries

    $dir
}

# Núcleo genérico de execução: monta o env isolado a partir da entrada em
# TOOLS e roda o binário. Toda CLI passa por aqui — só muda o `tool`.
def run-tool-profile [
    tool: string
    profile: string
    args: list<string>
] {
    let spec = (tool-spec $tool)
    let dir = (existing-profile-dir $tool $profile)

    let overrides = (
        $spec.clear_env
        | reduce --fold {($spec.config_env): $dir} {|env_name, acc|
            $acc | insert $env_name null
        }
    )

    with-env $overrides {
        run-external $spec.bin ...$args
    }
}

# --wrapped é necessário pro "run" poder repassar flags soltas (ex: --print
# "oi") direto pra CLI de verdade, sem o Nushell tentar interpretá-las como
# flags do próprio ai-profile. tool/action continuam posicionais tipados com
# completer normal — --wrapped só afeta como os tokens finais (...rest) são
# tratados, não os primeiros argumentos.
export def --wrapped "ai-profile" [
    tool: string@nu-complete-tools
    action: string@nu-complete-actions = "list"
    ...rest: string@nu-complete-profile-arg
] {
    tool-spec $tool | ignore

    match $action {
        "list" => (profile-list $tool)
        "new" => {
            let name = ($rest | get --optional 0)
            if $name == null {
                error make { msg: "uso: ai-profile <tool> new <nome>" }
            }
            create-profile $tool $name
        }
        "rename" => {
            let old = ($rest | get --optional 0)
            let new = ($rest | get --optional 1)
            if $old == null or $new == null {
                error make { msg: "uso: ai-profile <tool> rename <antigo> <novo>" }
            }
            rename-profile $tool $old $new
        }
        "delete" => {
            let name = ($rest | get --optional 0)
            if $name == null {
                error make { msg: "uso: ai-profile <tool> delete <nome>" }
            }
            delete-profile $tool $name
        }
        "run" => {
            let profile = ($rest | get --optional 0)
            if $profile == null {
                error make { msg: "uso: ai-profile <tool> run <perfil> [...args]" }
            }
            run-tool-profile $tool $profile ($rest | skip 1)
        }
        _ => {
            error make {
                msg: $"Ação desconhecida: ($action). Use list, new, rename, delete ou run."
            }
        }
    }
}
