# CLAUDE.md — regras deste repositório

> **Sempre leia e siga `rules.md` antes de agir** (diretrizes de trabalho:
> pensar antes de codar, simplicidade, mudanças cirúrgicas, e — importante —
> separar o que você VIU do que DEDUZIU antes de afirmar). Este arquivo
> (`CLAUDE.md`) cobre as regras específicas deste repo; `rules.md` cobre o
> comportamento geral. Em conflito, o pedido explícito do usuário vence.

Config do nushell (dotfiles). **Repositório PÚBLICO** em
github.com/matheusvcouto/nushell-config — tudo que entra aqui é visível pra
qualquer pessoa.

## Segurança: NUNCA commitar credenciais (regra inegociável)

Já houve um vazamento (fragmento de OAuth token num doc). Para impedir que
se repita:

1. **Nunca** escreva valores de segredo em arquivo nenhum do repo — nem em
   código, nem em `.md`, nem em exemplo. Isso inclui: tokens (`ya29.`,
   `sk-`, `sk-ant-`, `ghp_`/`gho_`/`ghs_`/`github_pat_`, `AIza`, `AKIA`,
   `xox*`, JWTs `eyJ...`), `access_token`/`refresh_token`/`id_token`/
   `client_secret`/`password` com VALOR, chaves privadas
   (`BEGIN ... PRIVATE KEY`), conteúdo de `.env`, cookies, sessões.
2. Ao documentar formato de credencial, use **sempre placeholders**
   (`<REDIGIDO>`, `ya29.<...>`, `sk-...`) — nunca cole a saída real de um
   arquivo de token, keychain, `auth.json`, `oauth_creds.json`,
   `antigravity-oauth-token`, etc. Se precisar mostrar estrutura, invente
   valores fake óbvios.
3. **Antes de QUALQUER `git add`/`commit`/`push`**, rodar esta varredura no
   que vai entrar (sintaxe do ripgrep — testada; não usar `-E`, que no `rg`
   é `--encoding`):
   ```
   git diff --cached | rg -n 'ya29\.[A-Za-z0-9]|sk-(ant-)?[A-Za-z0-9]{12}|gh[pousr]_|github_pat_|AIza[0-9A-Za-z_-]{20}|AKIA[0-9A-Z]{16}|xox[baprs]-|eyJ[A-Za-z0-9_-]+\.eyJ|BEGIN .*PRIVATE KEY|(access|refresh|id)_token"\s*:\s*"[A-Za-z0-9]'
   ```
   Saída vazia = ok. Qualquer match que seja VALOR real (não nome de env
   var, não prosa, não placeholder `<...>`) → **parar e redigir antes de
   commitar**. (Validado: pega `"access_token":"ya29.real..."`, ignora
   `ANTHROPIC_API_KEY`, `ya29.<REDIGIDO>` e a palavra em prosa.)
4. **Nunca commitar arquivos sensíveis**: `.env`, `.env.*` (exceto
   `.env.example` só com comentários/placeholders), `*.pem`, `*.key`,
   `id_rsa`, `id_ed25519`, `*.p12`, `auth.json`, `credentials*.json`,
   `*oauth*token*`, `.npmrc`, `.netrc`, `.aws/credentials`, dumps de
   keychain. Manter o `.gitignore` cobrindo esses.
5. Distinguir o que NÃO é segredo (pode aparecer): **nomes** de env vars
   (`ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`) sem valor; a palavra
   `access_token` em prosa/documentação; placeholders.
6. Se um segredo VAZAR mesmo assim: redigir no working tree, commitar a
   correção, avisar o usuário que o valor continua no histórico (e no
   remoto, se já foi pushado) e que só some com reescrita de histórico
   (`git filter-repo` + force-push) — decisão do usuário. Recomendar
   rotacionar/revogar o segredo de qualquer forma.

## Commits e push

- Commitar ou pushar **só quando o usuário pedir**.
- Mensagens de commit terminam com:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Rodar a varredura da seção de segurança antes de cada push.

## Estilo / convenções do repo

- Código em **nushell** (`.nu`); módulos em `modules/<nome>/mod.nu`.
- Combinar com o estilo existente do arquivo (nomes, comentários, idioma —
  comentários e mensagens em PT-BR como no resto do repo).
- Decisões de arquitetura ficam documentadas em `.md` ao lado do módulo
  (ex: `modules/ai_profiles/adr.md`, `known-issues.md`, `future-ideas.md`).
