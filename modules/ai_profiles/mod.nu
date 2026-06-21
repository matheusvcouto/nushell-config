# Isolated account profiles for AI CLIs.
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
#
# Para adicionar uma CLI nova:
#   1. Adicione uma entrada em TOOLS com:
#      - name: nome curto usado nos comandos (ex: "claude" -> claude-as)
#      - bin: binário a executar
#      - config_env: env var que a CLI usa pra apontar seu diretório de
#                     config (se a CLI não tiver uma var dedicada, "HOME"
#                     funciona, mas isola só o processo filho, não afeta
#                     o shell)
#      - clear_env: env vars de auth/API key a remover antes de rodar, pra
#                    não vazar credencial do perfil ativo do shell principal
#   2. Copie o bloco "<tool>-profile" de outra CLI (list/new/rename/delete)
#      trocando o nome — isso fica explícito porque o Nushell exige nomes de
#      def estáticos para subcomandos, então não dá pra gerar a partir do
#      array.
#   3. Adicione uma linha `export alias <tool>-as = ai-as <tool>` no fim do
#      arquivo. `ai-as` já é genérico (lê TOOLS), o alias só fixa o primeiro
#      argumento.
#   4. Importe os novos nomes em config.nu (lista do `use modules/ai_profiles`).

const PROFILE_NAME_PATTERN = '^[A-Za-z0-9_-]+$'
const PROFILES_ROOT = "~/.ai-profiles"
const PROFILES_FILE = "~/.ai-profiles/index.nuon"

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
        name: "antigravity"
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

def nu-complete-claude-profiles [] {
    profile-list "claude"
}

def nu-complete-codex-profiles [] {
    profile-list "codex"
}

def nu-complete-antigravity-profiles [] {
    profile-list "antigravity"
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

# Núcleo genérico de execução: monta o env isolado a partir da entrada em
# TOOLS e roda o binário. Toda CLI nova passa por aqui — só muda o `tool`.
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

# Completer do segundo argumento de `ai-as`/`<tool>-as`. Para descobrir qual
# CLI já foi escolhida, primeiro olha os tokens já digitados (chamada direta
# "ai-as claude ..."); se não achar, resolve o alias do primeiro token (ex:
# "claude-as" -> "ai-as claude") do jeito que `nvim_completer` já faz neste
# repositório, já que aliases não vêm expandidos no contexto do completer.
def nu-complete-profile-for-as [context: string] {
    let tools = ($TOOLS | get name)
    let tokens = ($context | split row " ")

    let direct = ($tokens | where {|t| $t in $tools} | get --optional 0)
    if $direct != null {
        return (profile-list $direct)
    }

    let first = ($tokens | get --optional 0)
    let expansion = (scope aliases | where name == $first | get --optional 0.expansion)
    if $expansion != null {
        let via_alias = ($expansion | split row " " | where {|t| $t in $tools} | get --optional 0)
        if $via_alias != null {
            return (profile-list $via_alias)
        }
    }

    []
}

export def --wrapped ai-as [
    tool: string@nu-complete-tools
    profile: string@nu-complete-profile-for-as
    ...args
] {
    run-tool-profile $tool $profile $args
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

export def antigravity-profile [] {
    profile-list "antigravity"
}

export def "antigravity-profile list" [] {
    profile-list "antigravity"
}

export def "antigravity-profile new" [
    profile: string
] {
    create-profile "antigravity" $profile
}

export def "antigravity-profile rename" [
    old: string@nu-complete-antigravity-profiles
    new: string
] {
    rename-profile "antigravity" $old $new
}

export def "antigravity-profile delete" [
    profile: string@nu-complete-antigravity-profiles
] {
    delete-profile "antigravity" $profile
}

# Atalhos "<tool>-as" de cada CLI: cada um é só um alias de ai-as com o
# primeiro argumento (tool) já preenchido. Adicionar uma CLI nova = uma
# entrada em TOOLS + uma linha de alias aqui (e o bloco de subcomandos
# "<tool>-profile" acima, que precisa ficar explícito porque o Nushell exige
# nomes de def estáticos para subcomandos).
export alias claude-as = ai-as claude
export alias codex-as = ai-as codex
export alias antigravity-as = ai-as antigravity
