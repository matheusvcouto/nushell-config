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
- `claude-profile delete <alias>` move o diretório pra `~/.Trash` e remove a
  entrada do índice.

Por que isso resolve o problema de UX sem reabrir a questão de segurança:
como o ID nunca aparece como "nome do perfil" em lugar nenhum (você nunca
vê nem digita o ID — só o alias), não existe expectativa de que `ls
~/.ai-profiles` deva bater com o alias atual. Não há mais "nome desatualizado
saltando aos olhos" porque não há mais nome ali, só um identificador interno.

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
