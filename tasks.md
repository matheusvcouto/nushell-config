# Tasks pendentes deste repo

> Checklist vivo. Atualizar (marcar `[x]`, remover, ou adicionar) sempre que
> uma pendência for concluída ou uma nova surgir — não deixar ficar
> desatualizado. Ver `CLAUDE.md` para a regra de sempre checar este arquivo.

## Compat cross-platform (`docs/plans/cross-platform-nushell-compat.md`)

Estado verificado em 2026-07-04 (lido direto do código, não suposto):

- [x] Task 1 — módulo `modules/platform/mod.nu` (feito e mais completo que o
      plano original: `require-runtime`/`check-runtime`/`runtime-ok` além de
      `command-exists` e clipboard por OS).
- [ ] Task 2 — `safe-remove` (`modules/utils/mod.nu:18`) ainda usa
      `str starts-with $"($root)/"` — quebra containment com separador `\`
      no Windows. Trocar por `path relative-to`.
- [ ] Task 3 — `env.nu` ainda usa `$env.HOME` (não existe no Windows),
      `ANDROID_HOME` hardcoded pro layout macOS, prepend de `/opt/homebrew`
      incondicional, e não gera/stub `zoxide.nu` (mise já tem geração mas
      sem stub quando o binário falta).
- [ ] Task 4 (parcial) — clipboard via `modules/platform` **já feito**
      (`config.nu:25-27`). Falta: `config.nu:17` ainda tem
      `source ~/.zoxide.nu` (arquivo nunca gerado por `env.nu` hoje) em vez
      de `source ($nu.default-config-dir | path join "zoxide.nu")`.
- [ ] Task 5 — guardas nos completers: `modules/completions/mod.nu` **já
      feito** (usa `runtime-ok` pro fallback carapace). Falta:
      `modules/completions/nvim.nu` (`git-files` ainda chama `^git
      rev-parse` sem checar se `git` existe) e `modules/completions/mise.nu`
      (sem guarda de `command-exists mise`).
- [ ] Task 6 — `modules/ai_profiles/mod.nu`, função `new-profile-dir`:
      ainda monta o path com interpolação de string (`/` manual) em vez de
      `path join`.

## Suporte a Linux no `ai-profile` (`docs/plans/ai-profile-linux-support.md`)

- [ ] Task A — aplicar as Tasks 2 e 6 acima (pré-requisito).
- [ ] Task B — verificar empiricamente (máquina Linux real) se a credencial
      do `claude` isola por `CLAUDE_CONFIG_DIR` (arquivo) ou cai num Secret
      Service global (quebraria isolamento, cenário agy). Nunca testar via
      `ai-profile claude new` — só `with-env` com pasta temp (regra do
      `CLAUDE.md`: não gravar estado real do usuário).
- [ ] Task C — mesma verificação para `codex` (`CODEX_HOME`/`auth.json`).
- [ ] Task D — só depois de B/C confirmados: virar
      `support.<tool>.run.linux` / `.acp.linux` em
      `modules/ai_profiles/mod.nu` de `untested` pra `supported`/`partial`
      (nunca tocar no record `macos`).
- [ ] Task E — validar ACP (`claude-agent-acp`/`codex-acp`) no Linux antes
      de virar `support.acp.linux`.
- [ ] Task F — documentar no `adr.md` a revisão "Suporte a Linux"; avisar
      que o script `~/.claude/statusline-command.sh` (repo separado, usa
      Keychain/`security` do macOS) fica fora do escopo deste módulo.
