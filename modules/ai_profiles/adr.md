# ADR: isolamento de perfis e por que o rename não move a pasta

## Contexto

O módulo `ai_profiles` cria contas isoladas de CLIs de IA (`claude-as`,
`codex-as`) apontando `CLAUDE_CONFIG_DIR`/`CODEX_HOME` para um diretório por
perfil (ex: `~/.claude-mae`). Isso permite múltiplas contas (ex: plano Pro
pessoal vs. de um familiar) sem conflito de sessão.

## Problema

`claude-profile rename mae monica` originalmente fazia `mv ~/.claude-mae
~/.claude-monica`. Depois do rename, o Claude Code parava de reconhecer o
plano Pro da conta logada.

Causa raiz: o Claude Code guarda a credencial OAuth no Keychain do macOS,
indexada por um hash do **caminho absoluto** do `CLAUDE_CONFIG_DIR` ativo.
Mudar o nome da pasta muda o caminho, muda o hash, e a entrada de Keychain
antiga fica órfã — a sessão perde a credencial mesmo com todos os arquivos de
config preservados. Esse comportamento não é exclusivo do Claude: qualquer
CLI que cacheie algo por caminho absoluto (lockfiles, cache de path, etc.)
teria o mesmo problema.

## Decisão (revisão 2)

Primeira versão: desacoplar o **alias** do diretório físico, mas manter o
diretório nomeado igual ao alias original (`~/.claude-mae`). Funcionava
(rename não move mais a pasta), mas trouxe um problema de UX apontado pelo
usuário: depois de renomear `mae` → `monica`, um `ls ~/.claude*` continuava
mostrando `.claude-mae`, um nome "errado"/desatualizado e confuso de
inspecionar.

Revisão: todos os perfis passam a viver dentro de uma única pasta
controlada, `~/.ai-profiles/`, cada um com um **ID opaco** gerado uma vez
(`random chars --length 10`) que nunca é exibido como nome de perfil em
nenhum outro lugar (ex: `~/.ai-profiles/claude-a1izmccy2u`).

- `~/.ai-profiles/index.nuon` guarda `{tool, alias, dir, created_at}`. Sem
  segredos — índice texto simples, alias → caminho + data de criação (pra
  rastreabilidade: quando aquele perfil foi criado).
- `claude-profile new <alias>` gera um ID novo, cria o diretório dentro de
  `~/.ai-profiles/`, e registra a entrada no índice.
- `claude-profile rename <old> <new>` só edita o campo `alias` da entrada
  existente (preserva `dir` e `created_at`). O diretório/ID nunca muda.
- `claude-profile delete <alias>` apaga o diretório e remove a entrada do
  índice. (Revisão posterior: trocado de "mover pra `~/.Trash`" para
  exclusão permanente direta — usuário relatou perfis apagados ficando
  perdidos na lixeira do macOS, que não se limpa sozinha. `rm --recursive
  --permanent` em vez de `mv` pra `~/.Trash`.)

Por que isso resolve o problema de UX sem reabrir a questão de segurança:
como o ID nunca aparece como "nome do perfil" em lugar nenhum (você nunca
vê nem digita o ID — só o alias), não existe expectativa de que `ls
~/.ai-profiles` deva bater com o alias atual. Não há mais "nome desatualizado
saltando aos olhos" porque não há mais nome ali, só um identificador interno.

## Decisão (revisão 3): ID por timestamp + array de CLIs suportadas

Dois ajustes adicionais pedidos pelo usuário:

1. **ID opaco trocado de `random chars --length 10` para
   `<timestamp>-<4 chars aleatórios>`** (ex:
   `claude-20260621164706-0i2x`). Um UUID/ULID de verdade seria mais robusto,
   mas implementar a codificação base32 Crockford do ULID à mão no Nushell
   é mais código sem ganho prático aqui. O formato timestamp+sufixo dá a
   mesma propriedade que se queria do ULID (ordenável, rastreável só pelo
   nome) com poucas linhas, e a chance de colisão (mesma CLI, mesmo
   segundo, mesmo sufixo de 4 chars) é desprezível pra esse uso.

2. **`const TOOLS` array** como única fonte de verdade sobre quais CLIs o
   módulo isola, cada entrada com `name`, `bin`, `config_env` (env var que a
   CLI usa pra apontar o config dir) e `clear_env` (env vars de auth a
   remover antes de rodar). Um `run-tool-profile` genérico monta o
   `with-env` a partir dessa entrada e roda o binário — toda a lógica de
   criar/listar/renomear/apagar perfil (`profile-list`, `create-profile`,
   etc.) já era parametrizada por `tool: string`, então não precisou
   duplicar nada além disso.
   Adicionado `antigravity` (CLI `agy`) como prova: a CLI não tem uma env
   var dedicada de config dir (usa `$HOME` direto), então `config_env` foi
   setado como `"HOME"` — o override fica restrito ao processo filho dentro
   do `with-env`, não vaza pro shell.
   Limitação aceita: o Nushell exige nomes de `def` estáticos, então ainda é
   preciso escrever os `export def antigravity-as` / `antigravity-profile
   ...` à mão (cerca de 25 linhas, copiadas do bloco do `codex`) — o array
   elimina a duplicação de *lógica*, não a necessidade de declarar os
   comandos exportados em si.

## Decisão (revisão 4): `ai-as` genérico + alias por CLI

Os 3 blocos `export def --wrapped <tool>-as` eram idênticos exceto pelo nome
da CLI (6 linhas cada, só repassando pra `run-tool-profile`). Substituídos
por um único `ai-as [tool, profile, ...args]` genérico, e cada
`<tool>-as` virou só `export alias <tool>-as = ai-as <tool>`. Adicionar uma
CLI nova agora exige: 1 entrada em TOOLS + 1 linha de alias (pra `-as`) + o
bloco de subcomandos `<tool>-profile` (não eliminável — ver limitação
abaixo) + import em `config.nu`.

O autocomplete do segundo argumento de `ai-as` (`profile`) precisa saber
qual `tool` já foi digitado. Quando chamado direto (`ai-as claude <tab>`) é
trivial. Quando chamado via alias (`claude-as <tab>`), não há garantia de
que o Nushell exponha ao completer o contexto já expandido (`ai-as claude
`) em vez do texto literal digitado (`claude-as `) — não há como confirmar
isso sem dirigir um Tab real numa sessão interativa, o que não é possível
no ambiente onde essa decisão foi tomada. Por isso o completer
(`nu-complete-profile-for-as`) trata os dois casos: primeiro tenta achar um
nome de CLI conhecido nos tokens já digitados; se não achar, resolve o
alias do primeiro token via `scope aliases` (a mesma técnica que
`modules/completions/nvim.nu` já usa pra resolver `n` -> `nvim`) e tenta de
novo a partir da expansão. Testado isoladamente chamando a função do
completer com os dois formatos de contexto possíveis — ambos retornam a
lista de perfis certa. **Não testado**: o Tab de verdade numa sessão
interativa real, que é a única forma de confirmar 100% qual dos dois
formatos o Nushell entrega.

## Decisão (revisão 5, final): `ai-profile` único, tool como argumento, não como nome de comando

A revisão 4 concluiu (errado) que dava pra genericizar `ai-as` mas não os
subcomandos `<tool>-profile`, porque "tool no meio do nome do subcomando"
não dá pra expressar via alias. Isso é verdade, mas a saída não era abrir
mão da genericidade — era parar de colocar `tool` dentro do *nome* do
comando.

Solução: `tool` é só o **primeiro argumento posicional**, nunca parte do
nome do comando exportado. Dois comandos no total, cobrindo qualquer CLI
presente em TOOLS sem nenhum código extra por CLI:

- `ai-profile run <tool> <profile> ...args` — roda a CLI isolada.
- `ai-profile <tool> [list|new|rename|delete] ...` — gerencia perfis
  (`list` é o padrão se a ação for omitida).

Truque que faz isso funcionar: `ai-profile run` é um nome de subcomando
**estático** (sempre literalmente "run"), então o Nushell o reconhece e
prioriza sobre o `ai-profile` genérico quando o segundo token digitado é
exatamente "run" — testado diretamente (`ai-profile run claude mae --foo`
cai no comando certo, `ai-profile claude list` cai no outro). Isso resolve
de uma vez a limitação registrada na revisão 4: não precisa mais de NENHUM
bloco de comando por CLI. Adicionar uma CLI nova agora é **só uma entrada
em TOOLS** — nada mais.

Tradeoff aceito: a ação (`list`/`new`/`rename`/`delete`) não é mais um
subcomando nativo do Nushell, é uma string normal com completer próprio
(`nu-complete-actions`). Funciona igual no Tab, só que via completer
custom em vez de descoberta nativa de subcomando — sem diferença prática
percebida ao digitar.

O completer de nome de perfil (`nu-complete-profile-arg`) ficou mais
simples que na revisão 4: como `tool` agora é sempre um argumento literal
explícito (nunca escondido atrás de alias), não precisa mais da lógica
dupla de "tenta direto, senão resolve alias" — só procura, nos tokens já
digitados, qual deles é um nome de CLI conhecido.

Os comandos `claude-as`/`codex-as`/`claude-profile`/etc da revisão 4 foram
removidos. Tudo passa por `ai-profile` e `ai-profile run`.

## Decisão (revisão 6): `run` dentro do mesmo `ai-profile`, ordem `<tool> run <perfil>`

A revisão 5 deixou `run` como um comando separado (`ai-profile run <tool>
<perfil>`) só pra poder ser `--wrapped` (repassar flags soltas como
`--print "oi"` direto pra CLI de verdade, sem o Nushell tentar interpretá
-las como flags do `ai-profile`). Isso deixava a ordem inconsistente:
`ai-profile run claude mae` mas `ai-profile claude rename ...` (tool em
posições diferentes dependendo do comando).

Usuário preferiu ordem consistente (`ai-profile <tool> run <perfil>
...args`, tool sempre em primeiro) mesmo sabendo do tradeoff. Testado e
confirmado: dá pra ter os dois ao mesmo tempo. `--wrapped` no `ai-profile`
inteiro não rouba o completer dos primeiros posicionais (`tool`, `action`
continuam com `string@completer` funcionando normalmente) — só evita que
tokens finais com `--` sejam interpretados como flags do próprio
`ai-profile`. Confirmado com teste direto (`ai-profile claude run mae
--print "oi" --foo` chega em `rest` intacto, sem erro de "unknown flag").

`run` virou só mais um caso do `match $action` (junto com
list/new/rename/delete), usando `$rest | get 0` como nome do perfil e
`$rest | skip 1` como args da CLI. Removido o comando separado
`"ai-profile run"`.

## Decisão (revisão 7): `apply-statusline` pra propagar a statusLine aos perfis isolados

**Problema**: `CLAUDE_CONFIG_DIR`/`CODEX_HOME` apontam cada perfil pro seu
próprio `settings.json`, isolado do `~/.claude/settings.json` global por
design (é o que garante que `model`/`enabledPlugins`/`theme` de um perfil
não vazam pra outro). Efeito colateral notado pelo usuário: a chave
`statusLine` do `settings.json` global também não chega aos perfis — rodar
`ai-profile claude run monica` não mostrava a status bar, porque o
`settings.json` daquele perfil simplesmente não tinha a chave.

**Alternativas consideradas**:
- *Symlink do `settings.json` do perfil pro global*: descartada — reabriria
  o problema que o isolamento existe pra evitar (mudar config num perfil
  afetaria todos).
- *Escrever `statusLine` automaticamente em `create-profile`*: descartada a
  pedido do usuário — ele queria controle manual, por perfil, não algo que
  todo perfil novo já vem com de cara.
- *Copiar/mesclar o JSON na mão*: simples, mas arriscado (mesclar errado
  apaga outras chaves do `settings.json` do perfil) e repetitivo.

**Decisão**: novo comando `ai-profile <tool> apply-statusline <perfil>
[template]`. Lê um template em `statusline-templates/<template>.json`
(`default` se omitido) — um arquivo contendo só o valor da chave
`statusLine` — e faz `upsert statusLine` no `settings.json` do perfil,
preservando todas as outras chaves. Roda só quando chamado explicitamente;
nunca em `new`/`run`/`acp`. Pasta de templates resolvida via `path self`
(const, parse-time) a partir do próprio `mod.nu`, não do diretório onde o
`nu` foi iniciado.

Motivo de usar **template em arquivo** em vez de hardcodar a `statusLine`
global dentro do comando: o usuário quer poder ter statuslines diferentes
por perfil (ex: uma mais simples num perfil, mais detalhada em outro) —
basta adicionar um `.json` novo em `statusline-templates/` e passar o nome
como segundo argumento.

## Decisão (revisão 8): bug do nome de conta na statusLine com perfis isolados

**Sintoma**: ao rodar `ai-profile claude run monica`, a status bar do Claude
Code (script fora deste repo, em `~/.claude/statusline-command.sh`) mostrava
o nome da conta principal (`Matheus`) em vez do nome da conta isolada
(`Mônica`), mesmo a sessão estando autenticada corretamente como Mônica.

**Causa raiz (confirmada empiricamente)**: o script lia o nome direto de
`$HOME/.claude.json` (hardcoded), ignorando que o `run-tool-profile` (acima)
isola via `with-env { CLAUDE_CONFIG_DIR: $dir }`. O processo `claude` da
sessão isolada — e a statusLine, como processo filho dele — herda
`CLAUDE_CONFIG_DIR` no ambiente, mas o script não usava essa variável.
Confirmado inspecionando os dois arquivos: `~/.claude.json` tem
`oauthAccount.displayName = "Matheus"`; o `.claude.json` dentro da pasta do
perfil monica (`~/.ai-profiles/claude-...-hilw/.claude.json`) tem
`oauthAccount.displayName = "Mônica"` (conta secundária da família).

**Não é um problema de autenticação/isolamento real** — o `claude` em si
sempre leu o config dir e o Keychain certos (isolamento por
`CLAUDE_CONFIG_DIR` + hash do path, ver seção "Isolamento funciona?" em
`known-issues.md`). O bug era puramente cosmético, isolado a um script
separado fora deste módulo.

**Correção**: trocar `"$HOME/.claude.json"` por
`"${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"` no script da statusLine — usa
o config dir do perfil ativo quando setado, cai no `$HOME` normal quando
não (conta principal). Testado nos três casos (conta principal, perfil
monica, `CLAUDE_CONFIG_DIR` apontando pra pasta inexistente — falha
graciosa, segmento só desaparece, sem erro). Não afeta nenhuma credencial
nem o Keychain: o campo lido é só texto decorativo dentro do `.claude.json`.

## Decisão (revisão 9): rate-limit da statusLine — "recência-por-sessão" no lugar de "maior % vence"

**Contexto**: o mesmo script (`~/.claude/statusline-command.sh`) mantém um cache
compartilhado de rate-limit por conta em `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/rate-limit-cache.json`
(o `CLAUDE_CONFIG_DIR` de cada perfil isola o cache — contas nunca cruzam). O objetivo
do cache é que terminais diferentes da MESMA conta convirjam para o valor real, já que
cada sessão do Claude Code só enxerga o snapshot de rate-limit que ela mesma recebeu.

**Bug (o erro a NÃO repetir)**: a primeira versão do cache guardava o **maior**
`used_percentage` por janela (`resets_at`), assumindo *"uso só cresce até resetar"*.
Essa premissa é falsa. `used_percentage` = uso ÷ **limite**; quando a Anthropic
**aumenta o limite no meio da janela**, o mesmo uso vira um % **menor**, na MESMA
janela → o max-clamp trava no valor velho e a **baseline nunca desce**. Sintoma real
observado (2026-07-02): cache preso em 5% enquanto o uso real era 1–2%.

**Causa raiz conceitual**: staleness (terminal ocioso mostra valor velho/**baixo**) e
aumento-de-limite (valor real **caiu**) são o MESMO problema com sinais opostos. "Maior
vence" resolve o primeiro e quebra o segundo. O sinal correto para desempatar não é
"qual % é maior", é **"qual reporte é o mais recente"** (= qual sessão falou com o
servidor por último).

**Correção — recência-por-sessão**: o cache passa a guardar, por janela, um mapa
`sessions[<session_id>] = {pct, at}`, onde `at` é o epoch da última vez que aquele pct
**mudou** para aquela sessão (`session_id` é campo estável do stdin da statusLine;
fallback bucket único `"_"`). A cada tick: se o pct do stdin difere do guardado para a
sessão → grava e carimba `at=agora`; se é igual → mantém o `at` antigo (o terminal
ocioso "envelhece" e nunca ganha). O valor **exibido** é o pct da sessão com o `at` mais
recente. Rollover (novo `resets_at`) zera o mapa; poda por TTL (6h) descarta terminais
fechados. Resultado: sobe quando você usa, e **desce quando o limite aumenta** — sempre
o valor mais fresco.

Junto foram corrigidos, no mesmo edit: cache corrompido agora se auto-repara (antes o
bloco de escrita era pulado e o cache ficava morto até deleção manual); janela expirada
não mostra mais % fantasma; `resets_at` em formato inesperado (ex.: ISO-8601) degrada
sem derrubar o script.

**Invariante que qualquer edição futura deve preservar**: o caminho do cache e o do
`.claude.json` continuam ancorados em `CLAUDE_CONFIG_DIR` — é isso que dá o isolamento
por conta. NÃO hardcode `~/.claude`. E **não reverta para "maior % vence"** por parecer
mais simples: aquilo trava a baseline (ver bug acima). Backup do script pré-correção:
`~/.claude/statusline/backups/statusline-command.sh.bak-20260702-114738`.

**Post-mortem (mesmo dia, 2026-07-02 à tarde)** — a primeira implementação da revisão 9
introduziu dois defeitos novos, corrigidos numa segunda passada (restaurou-se o backup e
reaplicou-se a correção). Lições para NÃO repetir:

1. **Nunca ler campos tab-separados com `IFS=$'\t' read` quando algum campo pode ser
   vazio.** Tab é "IFS whitespace" no bash: campos vazios à esquerda COLAPSAM e todos os
   valores deslizam de posição. Sintoma real: a janela 5h expirou, foi omitida (campos
   vazios na frente do @tsv), e o pct/reset da janela SEMANAL apareceu dentro do
   segmento 5h ("5h 7% (6h49m restantes)" — impossível para uma janela de 5 horas — e o
   7d sumiu). Correção: um valor por LINHA (`read` por linha preserva vazios), nunca
   `@tsv` + IFS-tab quando há campos opcionais.
2. **Não omitir janela expirada da exibição.** O usuário QUER ver o contador descer até
   "0m restantes" e ficar lá — é assim que ele sabe que o limite reiniciou. Janela
   expirada continua exibida com o último pct até chegar reporte da janela nova
   (rollover). Omitir era regressão de UX além de ter disparado o bug 1.
3. **Poda por TTL deve usar "última vez VISTO" (`seen`), não "última MUDANÇA" (`at`).**
   `at` fica propositalmente velho quando o pct não muda; podar por `at` removeria
   sessões ATIVAS de pct estável (a janela semanal muda devagar). O schema tem os dois
   campos: `at` decide quem é exibido, `seen` decide quem é podado.

Snapshot da versão defeituosa (referência): `~/.claude/statusline/backups/statusline-command.sh.bak-broken-20260702-151800`.
Harness de teste (23 cenários, incluindo os de regressão acima): reconstruível a partir
deste post-mortem; rodar cada cenário com `CLAUDE_CONFIG_DIR` temporário e stdin sintético.

## Revisão 10 — statusLine: dados frescos via API OAuth + refreshInterval por perfil (2026-07-02)

A barra de rate-limit mostrava 33% com uso real de 88%: o stdin da statusLine só
atualiza quando a própria sessão fala com o modelo — sessão ociosa nunca fica sabendo do
uso feito em outros dispositivos da conta. Correção na statusline global
(`~/.claude/statusline-command.sh`): fetch em background da mesma API que o painel
`/usage` usa (`https://api.anthropic.com/api/oauth/usage`), TTL 60s, cache
`usage-api-cache.json` **por conta** (ancorado em `CLAUDE_CONFIG_DIR`, como o resto).

Pontos que tocam o ai-profile:

1. **Credencial por perfil no Keychain**: com `CLAUDE_CONFIG_DIR` setado, o Claude Code
   guarda o token OAuth no item `Claude Code-credentials-<sha256(config_dir)[0:8]>`
   (verificado: `c274f3fc` = sha256 de `~/.ai-profiles/claude-20260621175425-hilw`).
   O fetcher da statusline deriva o sufixo do env e **nunca** cai para o item da conta
   principal — fallback cruzado mostraria o uso de outra conta na barra do perfil.
   Nunca imprimir nem renovar o token (renovar por fora pode invalidar a sessão do CLI).
2. **`statusLine.refreshInterval` precisa existir no `settings.json` DO PERFIL** (o
   global `~/.claude/settings.json` não vale para perfis isolados — `CLAUDE_CONFIG_DIR`
   substitui o diretório inteiro). Sem ele a linha só re-renderiza em evento: countdown
   congelado e fetch nunca disparado em sessão ociosa. Adicionado `refreshInterval: 3`
   ao perfil existente; **perfis novos de claude devem incluir o campo** se quiserem o
   relógio correndo.

Docs completas da revisão (fetch, lock, pseudo-sessão `__api__`, indicador `↻`):
`~/.claude/statusline/` (repo git próprio da statusline — ver ADR.md lá, revisões 10 e 11).

## Alternativas consideradas

- **Diretório nomeado igual ao alias original** (revisão 1, descrita
  acima): funcional, mas com o problema de UX que motivou a revisão 2.
- **Pasta opaca, mas ainda solta na raiz do `$HOME`** (ex:
  `~/.claude-<uuid>`): descartada a favor de agrupar tudo em
  `~/.ai-profiles/` — mais fácil inspecionar/fazer backup/limpar um único
  diretório do que vários dotfiles espalhados na raiz do home.
- **Sem rename, só criar/apagar** (renomear = apagar + criar + logar de
  novo): alternativa mais simples, considerada por reduzir a superfície de
  manutenção. Com a revisão 2 (ID opaco + pasta única), a complexidade
  restante do rename é pequena (só edita uma linha de um índice), então essa
  troca deixou de parecer necessária — mas é uma simplificação possível se o
  índice ainda incomodar no futuro.
