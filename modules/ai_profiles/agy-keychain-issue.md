# Investigação: dialog de Keychain ao usar `ai-profile agy run`

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
{"token":{"access_token":"ya29.a0AT3oNZ88Nlsn_0rJmJYohNZoLH50-6R4v1G3sKsX...
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

**Decisão final: pendente — aguardando o usuário escolher entre A/B/C.**
