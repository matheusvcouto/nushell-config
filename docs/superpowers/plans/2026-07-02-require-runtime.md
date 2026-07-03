# Require Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Do not commit during implementation; the user will decide if and when commits are allowed.

**Goal:** Add a reusable `require-runtime` guard so any Nushell function can declare supported operating systems and dependencies, then stop before executing unsafe or unsupported code.

**Architecture:** `modules/platform/mod.nu` owns runtime/platform checks because the existing cross-platform plan already centralizes reusable OS and command checks there. `check-runtime` returns structured diagnostics without throwing, `runtime-ok` returns a boolean for fallback paths such as completions, and `require-runtime` throws a clear `error make` before the guarded function runs anything dangerous. Guards are never called at startup top level; they are called inside functions or completers only.

**Tech Stack:** Nushell 0.110.0, existing `.nu` modules, command-line verification with `nu --no-config-file`.

---

## File Structure

- **Create/Modify:** `modules/platform/mod.nu`
  - Owns `command-exists`, `missing-commands`, `check-runtime`, `runtime-ok`, `require-runtime`, `require-command`, and clipboard wrappers.
  - This replaces the narrower platform module planned in `docs/plans/cross-platform-nushell-compat.md`.
- **Modify:** `config.nu`
  - Imports clipboard wrappers from `modules/platform`.
  - Does not call `require-runtime` directly at startup.
- **Modify:** `modules/completions/mod.nu`
  - Uses `runtime-ok` for optional `carapace` fallback.
- **Modify:** `modules/completions/nvim.nu`
  - Uses `runtime-ok` for optional `git` usage.
- **Modify:** `modules/completions/mise.nu`
  - Uses `runtime-ok` for optional `mise` usage.
- **Modify:** `modules/ai_profiles/mod.nu`
  - Uses `require-runtime` only in `run-tool-profile` and `acp-tool-profile`, before `run-external` or `exec`.
- **Modify:** `docs/plans/cross-platform-nushell-compat.md`
  - Updates the implementation plan to describe runtime guards as the standard pattern for future OS/dependency checks.

---

### Task 1: Runtime Guard API in `modules/platform`

**Files:**
- Create: `modules/platform/mod.nu`

- [x] **Step 1: Create `modules/platform/mod.nu` with the full runtime API**

```nu
# modules/platform/mod.nu
# Guards reutilizáveis para runtime/plataforma. Não chame estes guards no
# topo de config.nu/env.nu: startup deve continuar abrindo em qualquer OS.

export def command-exists [name: string]: nothing -> bool {
    which $name | is-not-empty
}

export def missing-commands [names: list<string>]: nothing -> list<string> {
    $names | where {|name| not (command-exists $name)}
}

def record-like [value] {
    $value | describe | str starts-with "record"
}

def normalize-support-rule [rule] {
    if (record-like $rule) {
        $rule
    } else {
        { status: $rule }
    }
}

def runtime-support-rule [spec: record] {
    let support = ($spec.support? | default { default: "unsupported" })
    let raw = (
        $support
        | get --optional $nu.os-info.name
        | default ($support | get --optional default | default "unsupported")
    )

    normalize-support-rule $raw
}

def dependency-target [dep: record] {
    let kind = ($dep.kind? | default "command")
    if $kind == "path" {
        $dep.path? | default ""
    } else {
        $dep.name? | default ""
    }
}

def check-dependency [dep: record] {
    let kind = ($dep.kind? | default "command")
    let target = (dependency-target $dep)
    let hint = ($dep.hint? | default null)

    if ($target | is-empty) {
        return {
            ok: false
            kind: $kind
            target: "sem nome"
            reason: $"dependência do tipo ($kind) sem campo obrigatório"
            hint: $hint
        }
    }

    match $kind {
        "command" => {
            if (command-exists $target) {
                { ok: true }
            } else {
                {
                    ok: false
                    kind: $kind
                    target: $target
                    reason: "comando ausente no PATH"
                    hint: $hint
                }
            }
        }
        "path" => {
            let expanded = ($target | path expand)
            if ($expanded | path exists) {
                { ok: true }
            } else {
                {
                    ok: false
                    kind: $kind
                    target: $target
                    reason: $"caminho não existe: ($expanded)"
                    hint: $hint
                }
            }
        }
        "env" => {
            let value = ($env | get --optional $target)
            let present = if $value == null {
                false
            } else if (($value | describe) == "string") {
                not ($value | is-empty)
            } else {
                true
            }

            if $present {
                { ok: true }
            } else {
                {
                    ok: false
                    kind: $kind
                    target: $target
                    reason: "variável de ambiente ausente ou vazia"
                    hint: $hint
                }
            }
        }
        _ => {
            {
                ok: false
                kind: $kind
                target: $target
                reason: "tipo de dependência desconhecido"
                hint: "use command, path ou env"
            }
        }
    }
}

# Retorna diagnóstico estruturado. Não joga erro.
export def check-runtime [spec: record] {
    let feature = ($spec.name? | default "feature")
    let os = $nu.os-info.name
    let support = (runtime-support-rule $spec)
    let status = ($support.status? | default "unsupported")
    mut failures = []

    if $status == "unsupported" {
        let reason = ($support.reason? | default "não suportado neste sistema")
        $failures = ($failures | append {
            kind: "os"
            os: $os
            status: $status
            reason: $reason
            hint: ($support.hint? | default null)
        })
    } else if $status == "untested" {
        let reason = ($support.reason? | default "ainda não testado neste sistema")
        $failures = ($failures | append {
            kind: "os"
            os: $os
            status: $status
            reason: $reason
            hint: ($support.hint? | default null)
        })
    } else if not ($status in ["supported" "partial"]) {
        $failures = ($failures | append {
            kind: "os"
            os: $os
            status: $status
            reason: "status de suporte inválido"
            hint: "use supported, partial, untested ou unsupported"
        })
    }

    let requires = [
        ($spec.requires? | default [])
        ($support.requires? | default [])
    ] | flatten

    let dep_failures = (
        $requires
        | each {|dep| check-dependency $dep}
        | where ok == false
        | each {|failure| $failure | reject ok}
    )
    $failures = ($failures | append $dep_failures)

    {
        ok: ($failures | is-empty)
        feature: $feature
        os: $os
        status: $status
        failures: $failures
    }
}

export def runtime-ok [spec: record]: nothing -> bool {
    let result = (check-runtime $spec)
    $result.ok
}

def format-runtime-failure [failure: record] {
    let kind = ($failure.kind? | default "runtime")
    let target = ($failure.target? | default "")
    let reason = ($failure.reason? | default "falha sem detalhe")
    let hint = ($failure.hint? | default null)
    let hint_text = if $hint == null { "" } else { $" — ($hint)" }

    if $kind == "os" {
        let os = ($failure.os? | default $nu.os-info.name)
        let status = ($failure.status? | default "unsupported")
        $"OS ($os) está ($status): ($reason)($hint_text)"
    } else {
        $"($kind) ($target): ($reason)($hint_text)"
    }
}

# Aborta com erro claro se o runtime não satisfaz a política declarada.
# Em caso de sucesso, não imprime nada. Isso é essencial para comandos ACP.
export def require-runtime [spec: record] {
    let result = (check-runtime $spec)
    if not $result.ok {
        let details = (
            $result.failures
            | each {|failure| format-runtime-failure $failure}
            | str join "\n- "
        )
        error make {
            msg: $"($result.feature) não pode executar em ($result.os)\n- ($details)"
        }
    }
}

export def require-command [name: string, hint?: string] {
    require-runtime {
        name: $"comando ($name)"
        support: { default: "supported" }
        requires: [
            { kind: "command", name: $name, hint: $hint }
        ]
    }
}

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
        {
            copy:  { cmd: "xclip", args: ["-selection" "clipboard"] }
            paste: { cmd: "xclip", args: ["-selection" "clipboard" "-o"] }
        }
    }
}

export def clip-copy [] {
    let spec = (clipboard-spec $nu.os-info.name).copy
    require-runtime {
        name: "clipboard copy"
        support: { default: "supported" }
        requires: [
            { kind: "command", name: $spec.cmd }
        ]
    }
    $in | ^$spec.cmd ...$spec.args
}

export def clip-paste [] {
    let spec = (clipboard-spec $nu.os-info.name).paste
    require-runtime {
        name: "clipboard paste"
        support: { default: "supported" }
        requires: [
            { kind: "command", name: $spec.cmd }
        ]
    }
    ^$spec.cmd ...$spec.args
}
```

- [x] **Step 2: Verify the module loads and `runtime-ok` succeeds**

Run:

```bash
nu --no-config-file -c 'use modules/platform *; runtime-ok { name: "teste ok", support: { default: "supported" }, requires: [{ kind: "command", name: "nu" }] }'
```

Expected output:

```text
true
```

- [x] **Step 3: Verify missing dependencies are reported without throwing in `check-runtime`**

Run:

```bash
nu --no-config-file -c 'use modules/platform *; check-runtime { name: "teste dep", support: { default: "supported" }, requires: [{ kind: "command", name: "comando-inexistente-xyz" }] } | select ok failures'
```

Expected: `ok` is `false`, and `failures` contains `target: comando-inexistente-xyz` with `reason: comando ausente no PATH`.

- [x] **Step 4: Verify unsupported OS aborts before the function body**

Run on macOS:

```bash
nu --no-config-file -c 'use modules/platform *; require-runtime { name: "teste linux-only", support: { linux: "supported" } }; print "nao deveria imprimir"'
```

Expected: command exits non-zero with error containing:

```text
teste linux-only não pode executar em macos
```

It must not print `nao deveria imprimir`.

- [x] **Step 5: Verify success is silent**

Run:

```bash
nu --no-config-file -c 'use modules/platform *; require-runtime { name: "teste silencioso", support: { default: "supported" }, requires: [{ kind: "command", name: "nu" }] }; print "ok"'
```

Expected output:

```text
ok
```

- [x] **Step 6: Review checkpoint, no commit**

```bash
git diff -- modules/platform/mod.nu .tmp/require_runtime_tests.nu
```

---

### Task 2: Use Runtime Guards for Clipboard Without Startup Breakage

**Files:**
- Modify: `config.nu`

- [x] **Step 1: Replace the current clipboard command string aliases**

Replace the block that builds `clipboard_command` and aliases `copy`/`paste` with:

```nu
# Clipboard por OS. A checagem de runtime acontece só quando copy/paste são
# chamados; startup continua abrindo mesmo sem xclip/pbcopy/clip.exe.
use modules/platform [clip-copy clip-paste]
alias copy = clip-copy
alias paste = clip-paste
```

- [x] **Step 2: Verify startup does not execute clipboard checks**

Run:

```bash
nu --env-config env.nu --config config.nu -c '"startup ok"'
```

Expected output:

```text
startup ok
```

- [x] **Step 3: Verify clipboard works on macOS**

Run:

```bash
nu --env-config env.nu --config config.nu -c '"runtime-clipboard-ok" | copy; paste'
```

Expected output:

```text
runtime-clipboard-ok
```

- [x] **Step 4: Verify clipboard missing dependency error without changing PATH globally**

Run:

```bash
nu --no-config-file -c 'use modules/platform *; with-env { PATH: [] } { "x" | clip-copy }'
```

Expected: command exits non-zero with an error containing `clipboard copy não pode executar` and `comando ausente no PATH`.

- [x] **Step 5: Review checkpoint, no commit**

```bash
git diff -- config.nu
```

---

### Task 3: Use Non-Throwing Runtime Checks in Completers

**Files:**
- Modify: `modules/completions/mod.nu`
- Modify: `modules/completions/nvim.nu`
- Modify: `modules/completions/mise.nu`

- [x] **Step 1: Update `modules/completions/mod.nu` to guard `carapace`**

Add after the existing `use ./...` imports:

```nu
use ../platform [runtime-ok]
```

Replace the final fallback block with:

```nu
    if $result != null {
        $result
    } else if (runtime-ok {
        name: "completion carapace"
        support: { default: "supported" }
        requires: [{ kind: "command", name: "carapace" }]
    }) {
        CARAPACE_LENIENT=1 carapace $real_cmd nushell ...$spans | from json
    } else {
        []
    }
```

- [x] **Step 2: Update `modules/completions/nvim.nu` to guard `git`**

Add after the header comment:

```nu
use ../platform [runtime-ok]
```

Replace `git-files` with:

```nu
def git-files [] {
    if not (runtime-ok {
        name: "completion nvim git-files"
        support: { default: "supported" }
        requires: [{ kind: "command", name: "git" }]
    }) {
        return []
    }

    let check = (^git rev-parse --is-inside-work-tree | complete)
    if $check.exit_code != 0 {
        return []
    }

    ^git ls-files --cached --others --exclude-standard
    | lines
    | each {|line| normalize-path $line}
}
```

- [x] **Step 3: Update `modules/completions/mise.nu` to guard `mise`**

Add after the header comment:

```nu
use ../platform [runtime-ok]
```

Add after `if $real_cmd != "mise" { return null }`:

```nu
    if not (runtime-ok {
        name: "completion mise"
        support: { default: "supported" }
        requires: [{ kind: "command", name: "mise" }]
    }) {
        return null
    }
```

- [x] **Step 4: Verify completers never throw when external commands are absent**

Run:

```bash
nu --no-config-file -c '
use modules/completions *
with-env { PATH: [] } {
    print (external_completer [git status])
    print (external_completer [mise use])
    print (external_completer [nvim src])
}
'
```

Expected: no command-not-found errors. Each print returns a list, commonly `[]`.

- [x] **Step 5: Review checkpoint, no commit**

```bash
git diff -- modules/completions/mod.nu modules/completions/nvim.nu modules/completions/mise.nu
```

---

### Task 4: Add Runtime Policies to External AI Profile Execution

**Files:**
- Modify: `modules/ai_profiles/mod.nu`

- [x] **Step 1: Import `require-runtime`**

Replace:

```nu
use ../utils [safe-remove]
```

with:

```nu
use ../platform [require-runtime]
use ../utils [safe-remove]
```

- [x] **Step 2: Add support policy to the `claude` tool entry**

In the `claude` object inside `TOOLS`, after the `acp` field, add:

```nu
        support: {
            run: {
                macos: { status: "supported", requires: [{ kind: "command", name: "claude" }] }
                linux: { status: "untested", reason: "isolamento de credenciais ainda não validado no Linux" }
                windows: { status: "untested", reason: "isolamento de credenciais ainda não validado no Windows" }
                default: { status: "unsupported", reason: "sistema não reconhecido pelo config" }
            }
            acp: {
                macos: { status: "supported", requires: [{ kind: "command", name: "claude-agent-acp" }] }
                linux: { status: "untested", reason: "stdio/exec do ACP ainda não validado no Linux" }
                windows: { status: "untested", reason: "stdio/exec do ACP ainda não validado no Windows" }
                default: { status: "unsupported", reason: "sistema não reconhecido pelo config" }
            }
        }
```

- [x] **Step 3: Add support policy to the `codex` tool entry**

In the `codex` object inside `TOOLS`, after the `acp` field, add:

```nu
        support: {
            run: {
                macos: { status: "supported", requires: [{ kind: "command", name: "codex" }] }
                linux: { status: "untested", reason: "isolamento de credenciais ainda não validado no Linux" }
                windows: { status: "untested", reason: "isolamento de credenciais ainda não validado no Windows" }
                default: { status: "unsupported", reason: "sistema não reconhecido pelo config" }
            }
            acp: {
                macos: { status: "supported", requires: [{ kind: "command", name: "codex-acp" }] }
                linux: { status: "untested", reason: "stdio/exec do ACP ainda não validado no Linux" }
                windows: { status: "untested", reason: "stdio/exec do ACP ainda não validado no Windows" }
                default: { status: "unsupported", reason: "sistema não reconhecido pelo config" }
            }
        }
```

- [x] **Step 4: Guard `run-tool-profile` before profile lookup and process execution**

Change the start of `run-tool-profile` to:

```nu
def run-tool-profile [
    tool: string
    profile: string
    args: list<string>
] {
    let spec = (tool-spec $tool)
    require-runtime {
        name: $"ai-profile ($tool) run"
        support: $spec.support.run
    }

    let dir = (existing-profile-dir $tool $profile)
```

Keep the rest of the function unchanged.

- [x] **Step 5: Guard `acp-tool-profile` before profile lookup, stderr logging, and `exec`**

Change the start of `acp-tool-profile` to:

```nu
def acp-tool-profile [
    tool: string
    profile: string
    args: list<string>
] {
    let spec = (tool-spec $tool)
    if ($spec.acp? | is-empty) {
        error make {
            msg: $"($tool) não tem ACP configurado — falta o campo acp em TOOLS"
        }
    }
    require-runtime {
        name: $"ai-profile ($tool) acp"
        support: $spec.support.acp
    }

    let dir = (existing-profile-dir $tool $profile)
```

Keep the rest of the function unchanged.

- [x] **Step 6: Verify list/new-style actions still load without external CLIs**

Run:

```bash
nu --no-config-file -c 'use modules/ai_profiles *; with-env { PATH: [] } { ai-profile claude list; ai-profile codex list }'
```

Expected: no command-not-found error for `claude`, `codex`, `claude-agent-acp`, or `codex-acp`. The command may print existing profile lists or empty lists.

- [x] **Step 7: Verify run blocks before external execution when dependency is absent**

Run:

```bash
nu --no-config-file -c 'use modules/ai_profiles *; with-env { PATH: [] } { ai-profile claude run perfil-inexistente }'
```

Expected: error contains `ai-profile claude run não pode executar` and `comando ausente no PATH`. It must not fail first with `Perfil claude inválido`; the runtime guard should run before profile lookup.

- [x] **Step 8: Review checkpoint, no commit**

```bash
git diff -- modules/ai_profiles/mod.nu
```

---

### Task 5: Document the Runtime Guard Pattern in the Cross-Platform Plan

**Files:**
- Modify: `docs/plans/cross-platform-nushell-compat.md`

- [x] **Step 1: Update the architecture paragraph**

Replace the current architecture paragraph with:

```md
**Arquitetura:** um módulo central (`modules/platform`) para runtime/plataforma:
checagem de binário no PATH, guards declarativos (`check-runtime`,
`runtime-ok`, `require-runtime`) e clipboard por OS. Tudo que é uso único
(paths de Android, Homebrew, geração de `zoxide.nu`/`mise.nu`) fica inline em
`env.nu`. O resto são correções cirúrgicas em arquivos existentes.
```

- [x] **Step 2: Add runtime guard rule after the failure-mode paragraph**

Add:

```md
**Regra para guards:** nunca chamar `require-runtime` no topo de `config.nu`,
`env.nu` ou de um módulo importado no startup. Use `require-runtime` no início
da função que executa a feature; use `runtime-ok` quando a feature puder cair
para fallback silencioso (ex: completions). `check-runtime` é para diagnóstico
e testes, porque retorna `{ok, failures}` sem jogar erro.
```

- [x] **Step 3: Update Task 1 interface list**

Make sure Task 1 lists these interfaces:

```md
- `command-exists [name: string] -> bool`
- `missing-commands [names: list<string>] -> list<string>`
- `check-runtime [spec: record] -> record`
- `runtime-ok [spec: record] -> bool`
- `require-runtime [spec: record]` — erra se OS/dependências não satisfazem a política
- `require-command [name: string, hint?: string]`
- `clip-copy []`
- `clip-paste []`
```

- [x] **Step 4: Review checkpoint, no commit**

```bash
git diff -- docs/plans/cross-platform-nushell-compat.md
```

---

## Final Verification

- [x] **Run the platform guard checks**

```bash
nu --no-config-file -c 'use modules/platform *; runtime-ok { name: "ok", support: { default: "supported" }, requires: [{ kind: "command", name: "nu" }] }'
```

Expected: `true`.

- [x] **Run the startup check**

```bash
nu --env-config env.nu --config config.nu -c '"startup ok"'
```

Expected: `startup ok`.

- [x] **Run the missing dependency check**

```bash
nu --no-config-file -c 'use modules/platform *; require-runtime { name: "dep ausente", support: { default: "supported" }, requires: [{ kind: "command", name: "comando-inexistente-xyz" }] }'
```

Expected: non-zero error containing `dep ausente não pode executar` and `comando ausente no PATH`.

- [x] **Run the completer fallback check**

```bash
nu --no-config-file -c '
use modules/completions *
with-env { PATH: [] } {
    print (external_completer [git status])
    print (external_completer [mise use])
    print (external_completer [nvim src])
}
'
```

Expected: no command-not-found errors.

- [x] **Run the AI profile guard check**

```bash
nu --no-config-file -c 'use modules/ai_profiles *; with-env { PATH: [] } { ai-profile claude run perfil-inexistente }'
```

Expected: non-zero error from `require-runtime` about missing `claude`, before any profile validation error.

---

## Self-Review

- Spec coverage: The plan implements a generic guard, non-throwing diagnostics, boolean fallback checks, dependency checks for commands/paths/env vars, OS support states, and safe consumer rollout.
- Startup safety: No task calls `require-runtime` at import/startup top level. `config.nu` imports aliases only; clipboard guards run when `copy`/`paste` are called.
- ACP safety: `require-runtime` is silent on success and throws before `print -e`/`exec` on failure.
- Placeholder scan: no placeholder markers remain.
- Type consistency: The plan uses `support`, `requires`, `status`, `reason`, `hint`, `kind`, `name`, and `path` consistently across all snippets.
