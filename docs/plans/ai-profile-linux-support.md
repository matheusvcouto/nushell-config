# Plano: suporte a Linux no `ai-profile` (sem bug, sem tocar no macOS)

> Este arquivo é o plano de análise-primeiro para dar suporte a Linux ao
> módulo `modules/ai_profiles/mod.nu`, seguindo `rules.md` (separar VISTO de
> DEDUZIDO) e o `CLAUDE.md` deste repo (nunca testar de um jeito que grave
> estado real do usuário). Nada foi implementado ainda — isto é plano, não
> execução.

## 1. O achado central (o que muda de fato entre Mac e Linux)

O caminho de execução do módulo **já é OS-agnóstico**. `run-tool-profile`/
`acp-tool-profile` só fazem: resolver a pasta do perfil → montar
`with-env {config_env: dir, ...clear_env: null}` → rodar o binário. Isso
funciona igual em qualquer OS. **Não há código macOS-específico no fluxo** —
nem `security`, nem `pbcopy`, nem path com layout de macOS.

O que separa o módulo do Linux hoje são **duas coisas, e só duas**:

1. **Um portão deliberado**: os records `support.<tool>.run.linux` e
   `.acp.linux` estão marcados `untested` (`mod.nu:72,78,95,102`).
   `require-runtime` aborta com "isolamento de credenciais ainda não
   validado no Linux". Isso é proposital — não é bug, é a trava de
   segurança.
2. **A pergunta empírica que o portão protege**: *no Linux, a credencial
   realmente fica isolada por perfil?* Isso depende de **onde cada CLI
   guarda o token no Linux**, que é diferente do macOS e **nunca foi
   verificado** (`known-issues.md` só tem evidência de macOS).

Ou seja: "dar suporte a Linux corretamente" é **80% verificação + virar o
portão**, não escrever fluxo novo. Escrever um monte de código
Linux-específico seria o erro — o fluxo genérico já é o "jeito nativo".

## 2. VISTO × A VERIFICAR (regra do repo: separar)

**VISTO (no código/docs deste repo):**
- macOS `claude`: credencial no Keychain indexada por hash do path do
  config dir → isolamento por perfil confirmado.
- macOS `codex`: token em `<CODEX_HOME>/auth.json` (arquivo) → isolamento
  por arquivo.
- O fluxo `run`/`acp` não tem nada macOS-específico.

**A VERIFICAR numa máquina Linux real (não dá pra afirmar do Mac):**
- No Linux o `claude` guarda o token em **arquivo dentro do
  `CLAUDE_CONFIG_DIR`** (ex: `.credentials.json`) ou no **Secret Service**
  (libsecret/gnome-keyring)?
  - Se **arquivo** → isolamento é automático (igual codex). Caso bom,
    provável em servidor/headless.
  - Se **Secret Service** → é preciso saber se o item é indexado por path
    (como macOS, isola) ou é **um item global único** (como o agy,
    **quebra** o isolamento).
- No Linux o `codex` mantém o token em `auth.json` (quase certo que sim) e
  não depende de um "Safe Storage" keychain macOS-only.

**Nunca assumir.** O plano abaixo determina isso empiricamente.

## 3. Princípio de design (o "sem interferir no Mac")

Espelhar o padrão que o módulo `platform` já usa (`clipboard-spec` por
`$nu.os-info.name`, `support.<os>` em `check-runtime`):

- Toda decisão nova fica **atrás de `$nu.os-info.name`** ou dentro do
  record `support.linux`. O branch/record `macos` **não é tocado** —
  permanece byte-a-byte igual.
- Nenhum `require-runtime` novo no startup (regra do compat plan): só
  dentro das funções.
- Refatores de separador (`path join`, `path relative-to`) produzem
  resultado **idêntico** no macOS → seguros.

## 4. Tasks

### Task A — Fundação cross-platform (pré-requisito, ainda não aplicado)
As Tasks 2 e 6 do `docs/plans/cross-platform-nushell-compat.md` **estão
documentadas mas não executadas** (confirmado: `modules/utils/mod.nu:18`
ainda tem `str starts-with "($root)/"`; `modules/ai_profiles/mod.nu` ainda
tem interpolação `.../...` em `new-profile-dir`). Sem elas, `delete` e a
criação de pasta ficam frágeis fora do macOS. Aplicar as duas:
- `safe-remove`: containment via `path relative-to` (separador-agnóstico).
  Chamado no `delete-profile`.
- `new-profile-dir`: trocar `$"(root)/(...)"` por `path join`.

Verificação segura (não mexe em estado real): os próprios passos das Tasks
2/6 do compat plan, que usam `/tmp` e `list` (leitura pura).

### Task B — Verificar isolamento de `claude` no Linux (o coração)
Numa máquina Linux com `claude` instalado e **duas contas de teste** (ou a
mesma conta duas vezes, só pra provar separação de credencial):
1. Descobrir o backend: com `CLAUDE_CONFIG_DIR` apontando pra uma pasta
   temporária, logar, e inspecionar **se surgiu um arquivo de credencial
   dentro da pasta** (`ls -a $dir`) ou se foi pro keyring (`secret-tool
   search` / `ls ~/.local/share/keyrings`). Registrar o achado em
   `known-issues.md` (seção "claude — Linux").
2. Provar isolamento: dois `CLAUDE_CONFIG_DIR` distintos → duas sessões →
   cada uma enxerga sua própria conta, sem cruzar.
3. **Regra de teste do CLAUDE.md**: fazer isso com `with-env
   {CLAUDE_CONFIG_DIR: <pasta temp em /tmp>}` — **nunca** via `ai-profile
   claude new`, que grava em `~/.ai-profiles/index.nuon` (estado real do
   usuário). Testar o *mecanismo do claude*, não o comando do módulo.
4. Se o backend for "item global único no Secret Service" (cenário agy):
   **não virar para supported**; marcar `partial` com `reason` explicando,
   ou investigar flag pra forçar credencial em arquivo. Documentar como o
   agy.

### Task C — Verificar isolamento de `codex` no Linux
Mesmo método: `with-env {CODEX_HOME: <temp>}`, confirmar que `auth.json`
nasce dentro da pasta e que dois `CODEX_HOME` não cruzam. Registrar
evidência.

### Task D — Virar o portão `support.linux` (só depois de B e C passarem)
Para cada resultado confirmado, trocar em `mod.nu` o record daquele
tool/canal:
- Isolamento provado → `linux: { status: "supported", requires: [{ kind:
  "command", name: "<bin>" }] }` (espelhando o macos).
- Isolamento parcial/frágil → `partial` com `reason`.
- **Não confirmado** → deixar `untested`. O portão existe justamente pra
  isso.

O `windows` continua `untested` (fora do escopo deste pedido). O branch
`macos` **não é editado**.

### Task E — ACP no Linux (opcional, mesmo padrão)
`acp-tool-profile` usa `exec` + `with-env` — cross-platform por
construção. Só precisa: os binários `claude-agent-acp`/`codex-acp`
existirem no Linux (o `requires` já cobre) e confirmar que `exec`/stdio se
comportam. Virar `support.acp.linux` só após teste real de um handshake
JSON-RPC.

### Task F — Documentação e limite de escopo
- Atualizar `adr.md` com uma revisão "Suporte a Linux": o que foi
  verificado, qual backend de credencial, e por que o portão foi virado.
- **Fora do escopo deste módulo (avisar o usuário):** o script
  `~/.claude/statusline-command.sh` (repo separado) usa `security`/Keychain
  do macOS e o path `~/.claude`. No Linux ele não roda como está.
  `ai-profile apply-statusline` (que só escreve JSON) funciona; o *script
  consumidor* precisaria de um branch Linux próprio, **em outro repo**.

## 5. O que NÃO fazer
- Não criar um `run-tool-profile` "versão Linux" nem duplicar lógica por
  OS — o fluxo já é genérico; duplicar é o anti-padrão.
- Não virar `support.linux` "no escuro" pra destravar rápido: sem a
  evidência de isolamento, isso reintroduz exatamente o risco do agy.
- Não trocar `PROFILES_ROOT` por caminho XDG: `~/.ai-profiles` é decisão
  de design (pasta única inspecionável) e expande igual no Linux.
- Não rodar `ai-profile <tool> new/delete` como "teste" — grava estado
  real fora do repo (proibido pelo CLAUDE.md).

---

**Resumo de uma linha:** o módulo já chama "a função nativa" em qualquer
OS — o trabalho real é **provar empiricamente no Linux que a credencial
isola por perfil** (Tasks B/C), aplicar os dois fixes de path pendentes
(Task A) e só então **virar o record `support.linux`** (Task D), sem
encostar no branch macOS.
