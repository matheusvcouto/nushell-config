# Compatibilidade Cross-Platform do Config Nushell — Plano de Implementação

> **Para quem for executar (humano ou agente):** este arquivo É a
> documentação-de-análise-primeiro pedida. A seção "Análise" registra o que
> foi **VISTO** no código (não deduzido) antes de qualquer mudança. As tasks
> usam checkbox (`- [ ]`) e trazem o código completo + comandos de
> verificação. Feito para ser executado task por task, commitando ao fim de
> cada uma.

**Objetivo:** fazer o config abrir sem erro no Linux e no Windows, sem mudar
o fluxo que já funciona no macOS — corrigindo só os pontos frágeis.

**Arquitetura:** um módulo central minúsculo (`modules/platform`) só para o
que é reutilizado (checar binário no PATH) ou não-trivial (clipboard por OS).
Tudo que é uso único (paths de Android, Homebrew, geração de `zoxide.nu`/
`mise.nu`) fica inline em `env.nu`. O resto são correções cirúrgicas em
arquivos existentes.

**Modo de falha escolhido:** o shell **abre normalmente** em qualquer OS.
Features que dependem de binário externo ausente falham com **erro claro só
quando chamadas** (nunca no startup). `source` de arquivos gerados nunca
quebra porque `env.nu` sempre garante o arquivo (stub vazio se o binário não
existir).

## Constraints globais (valem para todas as tasks)

- Repositório **PÚBLICO**. Nada de segredos nem PII neste doc nem no código:
  sem tokens, sem e-mail real, sem caminho pessoal absoluto. Usar `~`,
  `$nu.home-dir`, placeholders. (Ver `CLAUDE.md`.)
- Código em **nushell** (`.nu`); comentários e mensagens em **PT-BR**,
  combinando com o estilo já existente de cada arquivo.
- **Mudança cirúrgica** (`rules.md` §3): tocar só no necessário; não
  "melhorar" código adjacente; não refatorar o que não está quebrado.
- **Simplicidade** (`rules.md` §2): nenhuma abstração para código de uso
  único; nenhuma flexibilidade não pedida.
- Nushell alvo: **0.110.0** (versão registrada em `config.nu`).
- Windows é suportado para **startup, paths e clipboard básico**. CLIs
  externas (mise, zoxide, carapace, git, bun, deno) continuam dependendo de
  instalação no PATH — quando faltam, a feature falha com erro claro, o
  startup não.
- Commitar **só o que a task pede**. Rodar a varredura de segredos do
  `CLAUDE.md` antes de qualquer commit. Mensagem termina com
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## Análise (o que foi VISTO no código, antes de mudar nada)

Cada item abaixo foi lido diretamente do arquivo citado. Onde o plano
original divergia da realidade, está anotado.

### `config.nu`
- **Clipboard já tem seleção por OS** (linhas 26–38), mas está **quebrado
  fora do macOS**: `alias copy = ^$clipboard_command.copy` com
  `copy: "xclip -sel clip"` faz o nu tratar a string inteira (com espaços)
  como um único nome de comando externo → falha no Linux. Windows tem o
  mesmo problema com `"powershell -command Get-Clipboard"`. **Correção real:
  passar comando + args como lista**, não "adicionar detecção de OS" (ela já
  existe).
- **Linha 17:** `source ~/.zoxide.nu` — aponta pra `~`, arquivo que
  **`env.nu` nunca gera** (ver abaixo). Em máquina nova sem esse arquivo, o
  startup quebra no parse.
- **Linha 20:** `source ($nu.default-config-dir | path join "mise.nu")` — já
  é path portável. Mantém. Depende de `env.nu` garantir que `mise.nu`
  exista.

### `env.nu`
- Usa **`$env.HOME`** em ANDROID_HOME, BUN_INSTALL, PGT_LOG_PATH e nos
  prepends/appends de PATH (linhas 35–58). **`$env.HOME` não existe no
  Windows** → trocar por `$nu.home-dir`.
- **Prepend de `/opt/homebrew/*`** (linhas 46–51) é macOS-only; inofensivo
  em outros OS porque há filtro `where path exists` no fim, mas o correto é
  só adicionar no macOS.
- **ANDROID_HOME** é hardcoded pra `~/Library/Android/sdk` (layout macOS).
- **Gera `mise.nu`** com guarda `which mise` (linhas 63–68), **mas não faz
  stub** quando mise falta → `config.nu:20` quebra se `mise.nu` nunca foi
  gerado.
- **Não gera `zoxide.nu`** em lugar nenhum. (Confirmado: única referência a
  zoxide fora de `history.txt` é o comentário na linha 45 e o `source` do
  `config.nu`.)

### `modules/completions/mod.nu`
- `external_completer` cai em **`carapace` incondicionalmente** (linha 44).
  Se carapace faltar → erro no completion.

### `modules/completions/nvim.nu`
- `git-files` (linhas 49–58) já checa "não é repo git" via
  `^git rev-parse | complete` + exit code. **Mas isso ainda estoura se o
  binário `git` não existir** (comando-não-encontrado não vira exit code no
  nu, vira erro). Então a guarda ainda é necessária — por um motivo
  diferente do que o plano original dizia. Quando git falta, cair pro glob.

### `modules/completions/mise.nu`
- `mise_completer` roda `^mise --help` quando você digita `mise ` (linhas
  6/11). Guarda defensiva `command-exists mise` alinha com o modo de falha
  escolhido.

### `modules/completions/{bun,deno}.nu`
- Só usam `glob` e `open` de arquivos locais (portável, sem binário externo
  em tempo de completion). **Não precisam mudar.** `str replace --all "\\"
  "/"` já normaliza separador do Windows.

### `modules/utils/mod.nu`
- `safe-remove` (linha 18) usa `str starts-with $"($root)/"` — **`/`
  hardcoded**. No Windows `path expand` devolve `\`, então a checagem de
  containment quebra. Trocar por containment via `path relative-to`
  (independente de separador). É chamado em `ai_profiles/mod.nu:301`.

### `modules/ai_profiles/mod.nu`
- Único ponto de `/` manual é `new-profile-dir` (linha 164):
  `$"(profiles-root-path)/($tool)-($stamp)-($suffix)"`. Trocar por
  `path join`. **Não há outra comparação de string com `/`** neste arquivo
  (o resto já usa `path join`/`path expand`). Não reescrever o módulo — só
  esse ponto.

### `.gitignore`
- Cobre `.env`, `history.txt`, `mise.nu`. **`zoxide.nu` não está lá** — ao
  passar a gerá-lo no config dir, adicionar.

---

## Estrutura de arquivos

- **Criar** `modules/platform/mod.nu` — helpers de plataforma reutilizados:
  `command-exists`, `require-command`, `clip-copy`, `clip-paste` (+ helper
  privado `clipboard-spec`). Responsabilidade única: abstrair diferenças de
  SO que aparecem em mais de um lugar.
- **Modificar** `modules/utils/mod.nu` — containment cross-platform em
  `safe-remove`.
- **Modificar** `env.nu` — `$nu.home-dir`, paths por OS, Homebrew só no
  macOS, gerar+stub de `zoxide.nu` e `mise.nu`.
- **Modificar** `config.nu` — `source` do `zoxide.nu` do config dir; trocar
  bloco de clipboard pelos defs do módulo.
- **Modificar** `modules/completions/mod.nu` — guarda de `carapace`.
- **Modificar** `modules/completions/nvim.nu` — guarda de `git`.
- **Modificar** `modules/completions/mise.nu` — guarda de `mise`.
- **Modificar** `modules/ai_profiles/mod.nu` — `path join` em `new-profile-dir`.
- **Modificar** `.gitignore` — adicionar `zoxide.nu`.

> **Nota sobre "testes":** este repo **não tem framework de teste** nem pasta
> `tests/`. Então cada task verifica com **comandos `nu` reais + saída
> esperada** (estilo `rules.md` §6: evidência antes de "pronto"), não com
> unit tests. Onde dá, os comandos rodam com `--no-config-file` pra isolar.

---

### Task 1: Módulo `platform` (command-exists + clipboard por OS)

**Arquivos:**
- Criar: `modules/platform/mod.nu`

**Interfaces produzidas** (usadas por tasks 4 e 5):
- `command-exists [name: string] -> bool`
- `require-command [name: string, hint?: string]` — erra se ausente
- `clip-copy []` — lê stdin, copia pro clipboard do OS
- `clip-paste []` — imprime o clipboard do OS

- [ ] **Passo 1: Criar `modules/platform/mod.nu` com este conteúdo exato**

```nu
# modules/platform/mod.nu
# Abstrai diferenças de SO que aparecem em mais de um ponto do config.
# O que é uso único (paths de Android, Homebrew) fica inline no env.nu.

# true se o binário existe no PATH atual.
export def command-exists [name: string]: nothing -> bool {
    which $name | is-not-empty
}

# Erra com mensagem clara se o comando não existir. Usado pelos wrappers que
# dependem de binário externo: o shell abre normal e só a feature falha (com
# explicação) quando chamada.
export def require-command [name: string, hint?: string] {
    if not (command-exists $name) {
        let extra = if $hint != null { $" — ($hint)" } else { "" }
        error make { msg: $"comando '($name)' não encontrado no PATH($extra)" }
    }
}

# Especificação do clipboard por OS. Comando + args como LISTA — nunca uma
# string com espaços (o nu trataria "xclip -selection clipboard" como um
# único nome de comando).
def clipboard-spec [os: string] {
    if $os == "windows" {
        {
            copy:  { cmd: "clip.exe", args: [] }
            paste: { cmd: "powershell", args: ["-NoProfile" "-Command" "Get-Clipboard"] }
        }
    } else if $os == "macos" {
        {
            copy:  { cmd: "pbcopy",  args: [] }
            paste: { cmd: "pbpaste", args: [] }
        }
    } else {
        # Linux/BSD: xclip na seleção clipboard.
        {
            copy:  { cmd: "xclip", args: ["-selection" "clipboard"] }
            paste: { cmd: "xclip", args: ["-selection" "clipboard" "-o"] }
        }
    }
}

# Copia stdin pro clipboard do OS.
export def clip-copy [] {
    let spec = (clipboard-spec $nu.os-info.name).copy
    require-command $spec.cmd
    $in | ^$spec.cmd ...$spec.args
}

# Imprime o clipboard do OS.
export def clip-paste [] {
    let spec = (clipboard-spec $nu.os-info.name).paste
    require-command $spec.cmd
    ^$spec.cmd ...$spec.args
}
```

- [ ] **Passo 2: Verificar que o módulo carrega e `command-exists` funciona**

Rodar (a partir da raiz do repo):
```
nu --no-config-file -c 'use modules/platform *; [(command-exists nu) (command-exists comando-que-nao-existe-xyz)]'
```
Esperado: `[true, false]`

- [ ] **Passo 3: Verificar que `require-command` erra claro quando falta**

Rodar:
```
nu --no-config-file -c 'use modules/platform *; require-command comando-que-nao-existe-xyz'
```
Esperado: erro contendo `comando 'comando-que-nao-existe-xyz' não encontrado no PATH`

- [ ] **Passo 4: (macOS) Verificar clipboard round-trip**

Rodar:
```
nu --no-config-file -c 'use modules/platform *; "ping-123" | clip-copy; clip-paste'
```
Esperado: imprime `ping-123`

- [ ] **Passo 5: Commit**

```
git add modules/platform/mod.nu
git commit -m "Add platform module: command-exists e clipboard por OS

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `safe-remove` cross-platform

**Arquivos:**
- Modificar: `modules/utils/mod.nu:18`

**Interfaces:** `safe-remove [path, allowed_root]` — assinatura inalterada.

- [ ] **Passo 1: Substituir a checagem de containment**

Trocar o bloco (linhas ~18–22):
```nu
    if not ($resolved | str starts-with $"($root)/") {
        error make {
            msg: $"safe-remove: ($resolved) não está dentro de ($root), recusando apagar"
        }
    }
```
por (containment por componente de path, independente de separador `/` vs
`\`; `path relative-to` de um descendente nunca começa com `..` e nunca é
vazio — vazio significaria o próprio root, que também não deve ser apagado):
```nu
    let inside = (try {
        let rel = ($resolved | path relative-to $root)
        ($rel | is-not-empty) and not ($rel | str starts-with "..")
    } catch {
        false
    })
    if not $inside {
        error make {
            msg: $"safe-remove: ($resolved) não está dentro de ($root), recusando apagar"
        }
    }
```

- [ ] **Passo 2: Verificar que recusa caminho fora do root**

Rodar:
```
nu --no-config-file -c 'use modules/utils *; safe-remove /etc /tmp/sr-root'
```
Esperado: erro contendo `não está dentro de`

- [ ] **Passo 3: Verificar que aceita filho real (e recusa o próprio root)**

Rodar:
```
nu --no-config-file -c '
use modules/utils *
mkdir /tmp/sr-root/child
safe-remove /tmp/sr-root/child /tmp/sr-root
print (["child removido?" (not ("/tmp/sr-root/child" | path exists))])
safe-remove /tmp/sr-root /tmp/sr-root
'
```
Esperado: imprime `[child removido?, true]` e depois **erra** ao tentar
apagar o próprio root (`não está dentro de`). Limpar: `rm -rf /tmp/sr-root`.

- [ ] **Passo 4: Commit**

```
git add modules/utils/mod.nu
git commit -m "safe-remove: containment cross-platform via path relative-to

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `env.nu` portável (home-dir, paths por OS, geração+stub)

**Arquivos:**
- Modificar: `env.nu:35-68`
- Modificar: `.gitignore`

- [ ] **Passo 1: Substituir o bloco de env vars + PATH (linhas 34–61)**

Trocar de `# Tools and SDKs` até o fim do bloco `$env.PATH = (...)` por:
```nu
# Tools and SDKs
let home = $nu.home-dir
let os = $nu.os-info.name

# Android SDK: layout difere por OS. Se o caminho não existir, os appends de
# PATH abaixo são filtrados fora de qualquer forma (where path exists).
$env.ANDROID_HOME = (
    if $os == "macos" {
        [$home "Library" "Android" "sdk"] | path join
    } else if $os == "windows" {
        [($env.LOCALAPPDATA? | default ([$home "AppData" "Local"] | path join)) "Android" "Sdk"] | path join
    } else {
        [$home "Android" "Sdk"] | path join
    }
)
$env.ANDROID_EMULATOR_DEFAULT_AVD = "Pixel_9"
$env.BUN_INSTALL = ([$home ".bun"] | path join)
$env.PGT_LOG_PATH = ([$home ".cache" "postgrestools-pg-log"] | path join)

# Path Management (Modular and Clean)
# Adiciona paths, mantém únicos, e garante que existam (where path exists).
mut paths = (
    $env.PATH
    | prepend ([$home ".local" "share" "mise" "shims"] | path join)
    | append [
        ($env.ANDROID_HOME | path join "emulator")
        ($env.ANDROID_HOME | path join "platform-tools")
        ([$home ".flutter" "bin"] | path join)
        ($env.BUN_INSTALL | path join "bin")
    ]
)

# Homebrew só no macOS: quando o nu é lançado direto por um app GUI (ex:
# plugin de terminal do Obsidian), o PATH herdado é o mínimo do launchd
# (/etc/paths), sem /opt/homebrew/*. Sem isso, qualquer hook que dependa de
# bin do brew (zoxide, mise, etc.) falha só nesse cenário.
if $os == "macos" {
    $paths = ($paths | prepend ["/opt/homebrew/bin" "/opt/homebrew/sbin"])
}

$env.PATH = ($paths | uniq | where {|p| $p | path exists})
```

- [ ] **Passo 2: Substituir o bloco de ativação do mise (linhas 63–68) por geração+stub de zoxide E mise**

Trocar de `# Mise Activation` até o fim por:
```nu
# Geração de módulos de ativação. Ambos são sourced pelo config.nu, então
# precisam existir no parse — se o binário faltar, salva um stub vazio pro
# source não quebrar o startup.
let config_dir = $nu.default-config-dir

let zoxide_path = ($config_dir | path join "zoxide.nu")
if (which zoxide | is-not-empty) {
    ^zoxide init nushell | save $zoxide_path --force
} else if not ($zoxide_path | path exists) {
    "" | save $zoxide_path --force
}

let mise_path = ($config_dir | path join "mise.nu")
if (which mise | is-not-empty) {
    ^mise activate nu | save $mise_path --force
} else if not ($mise_path | path exists) {
    "" | save $mise_path --force
}
```

- [ ] **Passo 3: Adicionar `zoxide.nu` ao `.gitignore`**

O `.gitignore` passa a ter (é gerado, como `mise.nu`):
```
.env
history.txt
mise.nu
zoxide.nu
```

- [ ] **Passo 4: Verificar que `env.nu` sozinho não quebra e gera os arquivos**

Rodar (a partir da raiz do repo):
```
nu --env-config env.nu --no-std-lib -c '[($nu.default-config-dir | path join "zoxide.nu" | path exists) ($nu.default-config-dir | path join "mise.nu" | path exists)]'
```
Esperado: `[true, true]` (macOS atual: gerados de verdade). Sem erro no
carregamento do `env.nu`.

- [ ] **Passo 5: Commit**

```
git add env.nu .gitignore
git commit -m "env.nu: paths por OS via home-dir, Homebrew só no macOS, stub de zoxide/mise

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `config.nu` (source do zoxide do config dir + clipboard via módulo)

**Arquivos:**
- Modificar: `config.nu:17` e `config.nu:26-38`

**Interfaces consumidas:** `clip-copy`, `clip-paste` da Task 1.

- [ ] **Passo 1: Trocar o source do zoxide (linha 17)**

De:
```nu
source ~/.zoxide.nu
```
Para (arquivo agora gerado no config dir pela Task 3):
```nu
source ($nu.default-config-dir | path join "zoxide.nu")
```

- [ ] **Passo 2: Substituir o bloco de clipboard (linhas 25–38)**

Trocar de `# Define comandos inteligentes...` até `alias paste = ...` por:
```nu
# Clipboard por OS (comando + args como lista, ver modules/platform).
use modules/platform [clip-copy clip-paste]
alias copy = clip-copy
alias paste = clip-paste
```

- [ ] **Passo 3: Verificar startup completo (env + config) sem erro**

Rodar (a partir da raiz do repo):
```
nu --env-config env.nu --config config.nu -c '"startup ok"'
```
Esperado: imprime `startup ok`, sem nenhum erro/warning de parse ou source.

- [ ] **Passo 4: (macOS) Verificar copy/paste no shell configurado**

Rodar:
```
nu --env-config env.nu --config config.nu -c '"clip-ok-456" | copy; paste'
```
Esperado: imprime `clip-ok-456`

- [ ] **Passo 5: Commit**

```
git add config.nu
git commit -m "config.nu: source zoxide do config dir e clipboard via modules/platform

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Guardas de dependência nos completers

**Arquivos:**
- Modificar: `modules/completions/mod.nu`
- Modificar: `modules/completions/nvim.nu`
- Modificar: `modules/completions/mise.nu`

**Interfaces consumidas:** `command-exists` da Task 1.

- [ ] **Passo 1: `mod.nu` — importar helper e guardar o fallback carapace**

No topo, após os `use ./*.nu`, adicionar:
```nu
use ../platform [command-exists]
```
Trocar o bloco final (linhas ~41–45):
```nu
    if $result != null {
        $result
    } else {
        CARAPACE_LENIENT=1 carapace $real_cmd nushell ...$spans | from json
    }
```
por:
```nu
    if $result != null {
        $result
    } else if (command-exists carapace) {
        CARAPACE_LENIENT=1 carapace $real_cmd nushell ...$spans | from json
    } else {
        []
    }
```

- [ ] **Passo 2: `nvim.nu` — guardar `git-files` contra binário ausente**

No topo (após o comentário do cabeçalho), adicionar:
```nu
use ../platform [command-exists]
```
Trocar o início de `git-files` (linhas ~49–52):
```nu
def git-files [] {
    let check = (^git rev-parse --is-inside-work-tree | complete)
    if $check.exit_code != 0 {
        return []
    }
```
por:
```nu
def git-files [] {
    if not (command-exists "git") {
        return []
    }
    let check = (^git rev-parse --is-inside-work-tree | complete)
    if $check.exit_code != 0 {
        return []
    }
```

- [ ] **Passo 3: `mise.nu` — guardar contra binário ausente**

No topo (após o comentário do cabeçalho), adicionar:
```nu
use ../platform [command-exists]
```
Logo após o `if $real_cmd != "mise" { return null }` (linha ~33), adicionar:
```nu
    if not (command-exists mise) {
        return null
    }
```

- [ ] **Passo 4: Verificar que os completers não estouram sem as dependências**

Rodar (simula PATH vazio — nenhuma das CLIs externas resolve):
```
nu --no-config-file -c '
use modules/completions *
with-env {PATH: []} {
    print (external_completer [git status])
    print (external_completer [mise use])
    print (external_completer [nvim src])
}
'
```
Esperado: cada chamada retorna uma lista (possivelmente `[]`), **sem erro**
de "command not found". (`nvim src` pode retornar `[]` ou paths do glob
conforme o cwd; o que importa é não estourar.)

- [ ] **Passo 5: Commit**

```
git add modules/completions/mod.nu modules/completions/nvim.nu modules/completions/mise.nu
git commit -m "completers: guardar carapace/git/mise ausentes com command-exists

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: `path join` em `ai_profiles`

**Arquivos:**
- Modificar: `modules/ai_profiles/mod.nu:164`

- [ ] **Passo 1: Trocar a interpolação por `path join`**

De:
```nu
    $"(profiles-root-path)/($tool)-($stamp)-($suffix)"
```
Para:
```nu
    (profiles-root-path) | path join $"($tool)-($stamp)-($suffix)"
```

- [ ] **Passo 2: Verificar que os comandos de listagem seguem funcionando**

Rodar (a partir da raiz do repo):
```
nu --no-config-file -c 'use modules/ai_profiles *; ai-profile claude list; ai-profile codex list'
```
Esperado: lista os perfis existentes (ou "nenhum perfil criado"), sem erro.

- [ ] **Passo 3: Commit**

```
git add modules/ai_profiles/mod.nu
git commit -m "ai_profiles: path join em new-profile-dir (cross-platform)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Auto-revisão (cobertura vs. escopo original)

- Startup Linux/Windows sem erro → Tasks 3 (stub zoxide/mise, home-dir) + 4
  (source do config dir). ✔
- Clipboard cross-platform → Task 1 + 4 (corrige o bug de string-com-espaço
  já existente). ✔
- Paths por OS (Android, Homebrew, HOME) → Task 3. ✔
- Completers tolerantes a dependência ausente → Task 5. ✔
- `safe-remove` cross-platform → Task 2. ✔
- `/` manual em ai_profiles → Task 6. ✔
- Segurança de path (safe-remove aceita filho / recusa fora) → Task 2
  passos 2–3. ✔

**Divergências assumidas em relação ao plano original (decididas, não em
silêncio):**
1. **Módulo `platform` enxuto.** Cortei `os-name`, `home-dir`,
   `run-command-spec`, `android-home`, `base-path-prepends`,
   `base-path-appends`: são wrappers de builtin (`$nu.os-info.name`,
   `$nu.home-dir`) ou lógica de uso único. Ficaram inline no `env.nu`
   (`rules.md` §2). Se algum vier a ser reusado, promove-se a helper depois.
2. **Clipboard não era "adicionar detecção de OS"** — a detecção já existe e
   está quebrada. A task corrige o modo de passar args (lista, não string).
3. **`nvim_completer` já tinha guarda parcial** ("não é repo git"); a task
   só cobre o caso do binário `git` ausente, que a guarda atual não pega.
4. **Sem framework de teste no repo** → verificação por comandos `nu` reais
   com saída esperada, não unit tests.
5. **Doc de análise e plano no mesmo arquivo** (`docs/plans/`, seguindo a
   convenção já existente do repo, em vez de `docs/superpowers/plans/`).

**Não verificado (rodar durante a execução, não dá pra afirmar agora):**
- Comportamento real no Windows e Linux — só foi possível ler o código e
  validar no macOS. As mudanças são baseadas em contratos documentados do nu
  (`$nu.home-dir`, `$nu.os-info.name`, `path join`/`path relative-to`
  independentes de separador), mas o startup nesses OS **precisa ser testado
  na máquina alvo** antes de declarar suporte.
- Que `powershell -NoProfile -Command Get-Clipboard` e `clip.exe` são os
  binários certos no Windows alvo (documentado, não testado aqui).
