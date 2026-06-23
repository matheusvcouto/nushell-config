# Investigação: dialog de Keychain ao usar `ai-profile agy run`

## STATUS: RESOLVIDO — `agy` removido do módulo

Decisão final (2026-06-23): tirar o `agy` do array `TOOLS` em `mod.nu`
(Opção C, descrita abaixo). O `agy` passou a ser usado direto (`agy ...`),
sem isolamento por perfil — `$HOME` real, keychain de login real, conta
única. Motivo: entre "multi-conta robusta" e "zero risco/zero hack de
keychain", a segunda venceu. O restante deste arquivo é a investigação
histórica que levou a essa decisão; mantido como registro.

## Sintoma

Ao rodar `ai-profile run agy matheusestudos` (ordem antiga; hoje seria
`ai-profile agy run matheusestudos`), apareceu um dialog do macOS:

> **Chaves Não Encontradas**
> Não foi possível encontrar as chaves para armazenar "antigravity".
> [Cancelar] [Reajustar Para Padrões]

⚠️ **Se esse dialog aparecer: clique em "Cancelar". Nunca em "Reajustar
Para Padrões"** — esse botão reseta configuração de keychain e não vale o
risco de afetar o keychain real do sistema na dúvida.

(Sintoma secundário, não relacionado: `ai-profile list` sem `<tool>` dava
erro "CLI desconhecida: list" porque `list` estava sendo lido como valor de
`tool`. Esperado dado o desenho atual do comando — `tool` é sempre o
primeiro argumento.)

## Causa raiz (confirmada empiricamente, não é teoria)

O `agy` é a única das três CLIs isoladas por este módulo que **não tem
nenhuma env var de config-dir**. Procurado no binário (`strings $(which
agy)`) por padrões `AGY_*`, `ANTIGRAVITY_*`, `XDG_*`: não existe nenhuma
variável equivalente a `CLAUDE_CONFIG_DIR`/`CODEX_HOME`. Por isso o
`TOOLS` usa `config_env: "HOME"` pra isolar o `agy` — é a única opção
disponível.

No macOS, o keychain de login do usuário fica em
`$HOME/Library/Keychains/login.keychain-db`. Quando o `with-env` troca o
`$HOME` pra apontar pra pasta do perfil (que não tem
`Library/Keychains/`), qualquer chamada do sistema que dependa do keychain
de login falha em achar um keychain padrão. Confirmado direto:

```
HOME=/tmp/fake security default-keychain
# → "A default keychain could not be found." (exit 1)

HOME=/Users/matheus security default-keychain
# → "/Users/matheus/Library/Keychains/login.keychain-db" (exit 0)
```

O `agy` usa esse mecanismo (visto no `security dump-keychain` da máquina
real, fora do perfil isolado) pra guardar uma entrada chamada "Antigravity
Safe Storage" — o mesmo padrão que Chrome/Electron usam pra ter uma chave
de criptografia auxiliar. Com `$HOME` apontando pra um lugar sem keychain,
essa chamada falha e o macOS mostra o dialog.

## Por que isso NÃO significa que o login falhou

Achado o token salvo, em texto puro, dentro da pasta isolada do perfil:

```
~/.ai-profiles/agy-<id>/.gemini/antigravity-cli/antigravity-oauth-token
{"token":{"access_token":"ya29.<REDIGIDO>","refresh_token":"<REDIGIDO>",...}}
```

Ou seja: o `agy` persiste a credencial real num **arquivo** (que está
isolado corretamente dentro do perfil, igual qualquer outro arquivo de
config). O keychain "Antigravity Safe Storage" é só uma camada extra
(provavelmente usada por outras partes do produto, ex: a IDE desktop) —
não é necessária pro CLI autenticar, já que o token já está em texto
puro no arquivo.

**Conclusão prática: o perfil `matheusestudos` está com login válido.**
Não precisa apagar e recriar.

## O que não foi verificado

Se o dialog volta a aparecer em **todo** uso do `agy` dentro de um perfil
isolado (chato, mas inofensivo) ou se em algum cenário ele trava esperando
resposta na UI. Não testado porque exigiria rodar o `agy` de forma
interativa repetidas vezes e observar — decidido não fazer isso sem
combinar antes, já que pode abrir o dialog na tela do usuário.

## Opções consideradas

### A) Symlink de `Library/Keychains` (e possivelmente `Library/Caches`) do home falso pro real

Testado e funciona — com o symlink, `security default-keychain` dentro do
`$HOME` falso volta a achar o keychain de login real:

```
ln -s ~/Library/Keychains /tmp/fakehome/Library/Keychains
HOME=/tmp/fakehome security default-keychain
# → acha o keychain real, exit 0
```

- ✅ Resolve o dialog de verdade no macOS.
- ⚠️ **Específico de macOS.** Contraria o objetivo de uma solução que
  funcione independente do sistema — no Linux esse mecanismo de
  credenciais é outro (libsecret/D-Bus, não relativo a `$HOME`), então o
  comportamento lá seria diferente de qualquer forma.
  Encontrado também `Library/Caches/ms-playwright-go` sendo recriado
  dentro da pasta do perfil — duplicação de cache por perfil. Resolveria
  symlinkando também, mas cada symlink novo fura mais o isolamento de
  `$HOME` que era o propósito original do override.

### B) Deixar como está, documentar a limitação

Usuário clica "Cancelar" no dialog (se aparecer) e segue usando — o
login funciona porque o token está em arquivo, não no keychain.

- ✅ Zero código novo. `agy` já funciona hoje (confirmado: `--help`,
  `--version` e a TUI abrem normalmente dentro do perfil isolado).
- ⚠️ Dialog pode ser inconveniente se aparecer em todo uso (não
  verificado quão frequente).

### C) Tirar o `agy` do array `TOOLS`

Suportar só CLIs com env var de config-dir dedicada (`claude`, `codex`),
que isolam sem tocar em `$HOME`. `agy` seria usado sem isolamento
(uma conta só, como antes deste módulo existir).

- ✅ Mais robusto e sem hacks específicos de plataforma.
- ⚠️ Perde multi-conta no `agy`.

## Recomendação (na hora, ainda sem decisão do usuário)

A opção **B** foi recomendada como ponto de partida: custo zero, o `agy`
já funciona, e o dialog (se voltar a aparecer) é só ruído visual, não
bloqueio. A opção A foi desencorajada apesar de funcionar, porque
introduz dependência de macOS e fragiliza o isolamento de `$HOME` que é a
única ferramenta de isolamento disponível pra essa CLI especificamente.

---

## ATUALIZAÇÃO (investigação aprofundada — corrige o entendimento acima)

Uma investigação posterior (subagente, sem completar nenhum login real)
mudou o entendimento da seção "Por que isso NÃO significa que o login
falhou". O resumo "o token está em arquivo, keychain é só auxiliar" estava
**incompleto/errado pro caso normal**. Achados:

### A credencial real do agy é um item ÚNICO e GLOBAL do Keychain
Quando o `agy` roda com `$HOME` real, ele autentica a partir do Keychain
de login via **um único item generic-password**:

> `service="gemini", account="antigravity"` — exatamente UM item, **sem
> discriminador por conta**.

Provas:
- Com `$HOME` falso + symlink válido de `Library/Keychains` + **nenhum
  arquivo de credencial** → autenticou (retornou a lista de modelos),
  lendo do keychain.
- Um `~/.gemini/oauth_creds.json` deliberadamente inválido foi **ignorado**
  enquanto o item do keychain existia. **Keychain vence o arquivo.**

Consequência: relocar config via `$HOME` (ou via a flag escondida
`--gemini_dir=<path>`, que existe e isola config/estado/cache/conversas)
**não isola a autenticação** — todos os perfis dividiriam o mesmo token do
keychain global. Por isso o `$HOME` override sozinho não dá multi-conta
"de verdade".

### Existe a flag `--gemini_dir=<path>` (e `--app_data_dir`)
Relocam tudo de config/estado/cache pra outro diretório — **menos a auth**.
Não há env var (`XDG_*`, `AGY_*`, `ANTIGRAVITY_*`, `GEMINI_*`) que reloque
config/token. `XDG_CONFIG_HOME` é ignorado.

### Multi-conta concorrente DE VERDADE exige um Keychain por perfil
Como a credencial é o Keychain de login (derivado de `$HOME`) e a chave é
fixa, o único jeito de dois processos concorrentes terem tokens
diferentes é **cada um com seu próprio `login.keychain-db`** — ou seja,
`$HOME` falso por perfil com um keychain **real e próprio** (criado via
`security create-keychain`), NÃO symlinkado pro compartilhado. Provado o
mecanismo (keychain vazio → "sign in"; keychain populado → autentica),
mas **não verificado ponta-a-ponta com 2 logins reais**.

Layout que daria multi-conta concorrente (Tipo C, avançado/frágil):
`Library/Keychains/` real por perfil + `.gemini/` real por perfil +
symlinks de `.gitconfig`, `.ssh`, `Library/Caches` (Playwright fica em
`Library/Caches/ms-playwright-go`). `~/.config/antigravity` é não-problema
— neste build o agy nem usa.

### Por que `ai-profile agy run` FUNCIONA mesmo assim hoje (fallback)
No setup atual (`$HOME` falso, **sem** keychain nenhum na pasta), o
keychain fica indisponível → o dialog aparece → ao cancelar, o `agy` cai
no **fallback do arquivo de token** (`antigravity-oauth-token`, em texto
puro) dentro do `$HOME` isolado. Foi por isso que o login apareceu como
`[email redigido]` na sessão. Ou seja: **o keychain quebrado é,
por acidente, o que faz o isolamento por arquivo funcionar** — cada perfil
tem seu arquivo e não há keychain compartilhado pra sobrepor.

Implicação prática boa: como cada `$HOME` falso tem seu próprio arquivo e
nenhum keychain, **mesmo uso concorrente provavelmente já funciona hoje
via fallback de arquivo** — com o dialog (cancelar) como único custo
visível. Não verificado com 2 contas reais, e depende do caminho de
fallback (que um update do agy pode mudar). O token fica em texto puro no
arquivo (modo 0600, só dono lê).

#### Detalhamento do fallback (como funciona passo a passo)

Sequência observada com `ai-profile agy run <perfil>`:

1. `with-env` aponta `$HOME` pra `~/.ai-profiles/agy-<id>/`. Essa pasta não
   tem `Library/Keychains/`, então o macOS não acha um keychain padrão.
2. **No login** (`agy` tentando GRAVAR o token no slot
   `gemini`/`antigravity` do keychain): a gravação falha → aparece o dialog
   "Chaves Não Encontradas". Você clica **Cancelar**.
3. O `agy` então grava/lê o token no **arquivo**
   `$HOME/.gemini/antigravity-cli/antigravity-oauth-token` (JSON em texto
   puro: `{"token":{"access_token":"ya29...","refresh_token":...}}`).
4. **Nas execuções seguintes**, o `agy` lê o token desse arquivo. Como já
   está autenticado e não precisa gravar no keychain de novo, **o dialog
   não reaparece** — ele é, na prática, **só no login** (confirmado pelo
   uso real: a mensagem aparece apenas no login).

#### Isolamento por perfil: por que funciona, e por que é frágil

Cada perfil = um `$HOME` falso = um `~/.gemini/antigravity-cli/` próprio =
um arquivo de token próprio. Não há keychain compartilhado pra sobrepor →
cada perfil (inclusive vários ao mesmo tempo, cada processo com seu
`$HOME`) usa seu próprio token. É isso que dá multi-conta concorrente
**de graça** no estado atual.

⚠️ **Ironia importante (não-óbvia):** o dialog/keychain-quebrado é
**load-bearing** pro isolamento. Se a gente "consertasse" o dialog
symlinkando `Library/Keychains` pro keychain real (a antiga Opção A), o
`agy` voltaria a usar o **slot global único** do keychain → **todos os
perfis passariam a compartilhar a mesma conta** e o isolamento
**quebraria**. Ou seja: Opção A (tirar o dialog) e o isolamento por perfil
são **conflitantes**. Pra ter multi-conta sem o keychain global atrapalhar,
ou se mantém o keychain indisponível (estado atual, fallback de arquivo) ou
se dá um keychain **próprio por perfil** (Tipo C). Não dá pra ter
"keychain real compartilhado" + multi-conta.

Resumo: o estado atual (sem keychain no `$HOME` falso → fallback de
arquivo) é, surpreendentemente, o caminho **mais simples** que entrega
multi-conta concorrente — o Tipo C (keychain por perfil) só seria
necessário se um update do agy deixar de cair no fallback de arquivo.

### Tradeoff de fundo (decisão do produto, não nossa)
Pro agy, **"sentir nativo como claude/codex"** e **"multi-conta robusta"**
são mutuamente exclusivos: nativo = usa o keychain global = 1 conta;
multi-conta robusta = keychain por perfil = não-nativo + frágil +
macOS-only. claude/codex não têm esse dilema porque foram feitos pra
relocar a credencial inteira via env var mantendo `$HOME` real.

**Decisão final: pendente.** Caminho atual recomendado = **B** (usar como
está, via fallback de arquivo, cancelando o dialog), documentado aqui. O
**Tipo C** (keychain por perfil) fica como opt-in futuro, só se multi-conta
simultânea robusta virar requisito firme, e só depois de validar com 2
logins reais.
