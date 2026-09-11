# Auditoria do projeto — 2026-07-13

## Escopo e método

Auditoria estática de todos os arquivos-fonte Nushell (`.nu`), configuração
de ambiente, módulos e documentação relacionada. Foram feitas verificações
isoladas, sem criar, editar ou apagar perfis reais de IA nem outro estado do
usuário fora de diretórios temporários.

Classificação usada:

- **Alta**: pode impedir o uso normal ou comprometer a integridade dos dados.
- **Média**: causa erro funcional previsível, degrada a experiência ou reduz
  portabilidade.
- **Baixa**: melhoria de robustez, desempenho, documentação ou manutenção.

## Resumo executivo

Não foi encontrado vazamento de memória comprovável. O repositório é uma
configuração de shell, sem serviço próprio de longa duração; os principais
riscos encontrados são de inicialização, completion, compatibilidade entre
sistemas e integridade do índice de perfis de IA.

Todos os módulos passaram pela checagem sintática do Nushell. Os problemas
abaixo foram separados entre reproduzidos, confirmados por inspeção e riscos
já documentados pelo projeto.

## Problemas reproduzidos

### Alta — inicialização quebra se `~/.zoxide.nu` não existir

- **Local:** `config.nu:17`
- **Evidência:** executar a configuração com um `$HOME` temporário que não
  contém `.zoxide.nu` falha com `nu::parser::sourced_file_not_found` nessa
  linha.
- **Causa:** `source ~/.zoxide.nu` é incondicional, mas `env.nu` não gera
  esse arquivo nem há guarda para a ausência de `zoxide`.
- **Impacto:** uma instalação nova, uma máquina sem zoxide ou uma configuração
  parcialmente instalada não abre o shell.
- **Recomendação:** gerar o módulo com `zoxide init nushell`, salvar no
  diretório padrão do Nushell e só fazer `source` quando o binário e o arquivo
  existirem. A pendência já consta em `tasks.md`.

### Média — `external_completer` falha para lista de spans vazia

- **Local:** `modules/completions/mod.nu:20-28`
- **Evidência:** `external_completer []` produz
  `nu::shell::access_beyond_end` ao acessar `$spans.0`.
- **Impacto:** se o motor de completion invocar o completer sem token atual,
  a completion inteira falha em vez de retornar uma lista vazia.
- **Recomendação:** retornar `[]` no início quando `$spans` estiver vazia e
  usar `get --optional 0` para o primeiro elemento.

### Média — completion de `nvim` usa sempre o primeiro argumento

- **Local:** `modules/completions/nvim.nu:122`
- **Evidência:** a chamada
  `nvim_completer ["nvim" "config.nu" ""]` retornou somente `config.nu`.
- **Causa:** o código usa `get --optional 1` em vez do token que está sendo
  completado.
- **Impacto:** `nvim primeiro-arquivo <TAB>` não sugere corretamente um
  segundo arquivo; flags após o primeiro argumento também recebem sugestões
  inadequadas.
- **Recomendação:** usar o último span/cursor atual e definir o tratamento de
  flags e de múltiplos arquivos.

### Média — bootstrap do `mise` pode falhar sem o diretório padrão

- **Local:** `env.nu:65-67`
- **Evidência:** com `$HOME` temporário vazio e `mise` disponível, o `save`
  falhou com `nu::shell::io::directory_not_found` porque o diretório-pai de
  `$mise_path` não existia.
- **Impacto:** instalação por configuração alternativa, ambiente limpo ou
  bootstrap incompleto pode impedir a inicialização antes de carregar o
  restante da configuração.
- **Recomendação:** criar `($mise_path | path dirname)` antes de salvar e
  tratar a geração como opcional.

## Problemas confirmados por inspeção

### Média — `safe-remove` não é portável para Windows

- **Local:** `modules/utils/mod.nu:18`
- **Causa:** a checagem de containment constrói o separador `"/"` manualmente
  com `str starts-with $"($root)/"`.
- **Impacto:** caminhos Windows podem ser recusados indevidamente; o comando
  de delete de `ai-profile` fica inutilizável nesse sistema.
- **Recomendação:** usar `path relative-to` e rejeitar apenas resultados que
  escapem por `..`.
- **Estado:** já registrado como Task 2 em `tasks.md`.

### Média — `env.nu` contém premissas específicas de macOS

- **Local:** `env.nu:35-60`
- **Causa:** usa `$env.HOME`, layout `~/Library/Android/sdk` e caminhos
  `/opt/homebrew/*` incondicionalmente.
- **Impacto:** Windows não expõe necessariamente `HOME`; Linux e Windows
  recebem caminhos irrelevantes e o Android SDK pode ser apontado
  incorretamente.
- **Recomendação:** derivar home de `$nu.home-path`, condicionar caminhos por
  `$nu.os-info.name` e permitir configuração explícita do SDK.
- **Estado:** já registrado como Task 3 em `tasks.md`.

### Alta — `index.nuon` dos perfis é ponto único de falha

- **Locais:** `modules/ai_profiles/mod.nu:169-180`, `:248-338`
- **Causa:** operações de criar, renomear e apagar fazem leitura-modificação-
  escrita direta, sem escrita atômica, backup nem lock.
- **Impacto:** interrupção ou concorrência pode deixar diretórios órfãos,
  entradas apontando para diretórios removidos ou perder alteração de outra
  execução. Não há comando de recuperação.
- **Recomendação:** escrita em arquivo temporário seguida de rename atômico,
  backup `.bak`, lock por operação e `ai-profile doctor`/`adopt`.
- **Estado:** risco já reconhecido em `modules/ai_profiles/known-issues.md`.

### Média — `apply-statusline` é aceito para Codex, mas o template padrão é do Claude

- **Locais:** `modules/ai_profiles/mod.nu:511-517` e
  `modules/ai_profiles/statusline-templates/default.json:3`
- **Causa:** o dispatcher não limita a ação por ferramenta e o template
  padrão chama `bash ~/.claude/statusline-command.sh`.
- **Impacto:** `ai-profile codex apply-statusline <perfil>` grava uma chave
  orientada ao Claude no `settings.json` do Codex.
- **Recomendação:** restringir a ação ao Claude ou separar templates e
  capacidades por ferramenta.

### Baixa — guardas ACP não verificam a CLI principal

- **Locais:** `modules/ai_profiles/mod.nu:76-103`
- **Causa:** as regras ACP exigem somente `claude-agent-acp` ou `codex-acp`.
- **Impacto:** se o adapter existir, mas a CLI que ele embrulha não, o erro
  surge tardiamente e é menos claro.
- **Recomendação:** declarar o adapter e a CLI principal em `requires`.

### Baixa — plano e implementação do completer `nvim` divergem

- **Locais:** `docs/plans/completer-nvim-busca-hibrida-git-glob.md:14-35` e
  `modules/completions/nvim.nu:126-145`
- **Causa:** o plano declara merge de `git ls-files` com `glob`, prioridade
  por fonte e ordenação. O código usa `glob` só quando não há resultados Git;
  havendo Git, descobre somente `.env*`.
- **Impacto:** comportamento e documentação deixam de ter uma fonte única de
  verdade; a cobertura de arquivos ignorados é menor que a estratégia
  descrita.
- **Recomendação:** decidir se o comportamento atual é intencional. Se for,
  corrigir o plano; caso contrário, implementar merge, deduplicação e ordem
  documentados.

### Baixa — parser de `.env` é propositalmente simples, mas frágil

- **Local:** `env.nu:16-25`
- **Limitações:** comentários com indentação, `export KEY=...`, aspas simples,
  escapes e valores multilinha não são tratados como em parsers usuais de
  `.env`.
- **Impacto:** um `.env` válido para outras ferramentas pode impedir ou
  alterar silenciosamente a carga de ambiente do Nushell.
- **Recomendação:** documentar o subconjunto aceito ou substituir a lógica por
  um parser confiável.

### Baixa — custo de completion cresce em repositórios grandes

- **Locais:** `modules/completions/mise.nu:5-18`,
  `modules/completions/bun.nu:38` e `modules/completions/deno.nu:80`
- **Causa:** cada Tab pode executar `mise --help` duas vezes e fazer globs
  recursivos.
- **Impacto:** atraso perceptível e uso desnecessário de CPU em projetos
  grandes.
- **Recomendação:** executar `mise --help` uma vez por requisição e usar cache
  curto, invalidado por diretório/tempo, para listas de arquivos.

## Cobertura de testes

- Não há testes versionados detectáveis no repositório.
- Existe `.tmp/require_runtime_tests.nu`, mas `.tmp/` é ignorado pelo Git e
  rodar `nu .tmp/require_runtime_tests.nu` apenas define `main`; não executa
  as asserções. Executar `source ...; main` passou durante a auditoria.
- Recomenda-se mover o harness para `tests/`, chamar o entrypoint de forma
  explícita e documentar um único comando de teste para CI e uso local.

## Segurança e memória

- A varredura dos arquivos versionáveis não encontrou padrões de credenciais
  reais; as ocorrências encontradas são regras de detecção ou placeholders.
- Não há vazamento de memória comprovável. A análise estática não identificou
  processos próprios persistentes, caches sem limite ou hooks que cresçam
  durante a inicialização normal. A maior preocupação operacional é o custo
  dos completers, não retenção de memória.

## Validações executadas

1. `nu --ide-check` em todos os arquivos `.nu`: sem diagnósticos de erro.
2. Carregamento isolado dos módulos `platform`, `utils`, `completions` e
   `ai_profiles`: passou.
3. Carregamento da configuração atual: passou.
4. Harness `require-runtime` executado explicitamente por `main`: passou.
5. Vetor conhecido de CRC32: `crc32-bun abc` retornou `891568578`.
6. Reproduções isoladas dos erros de zoxide, bootstrap de mise e completers:
   confirmadas conforme descrito acima.

## Ordem recomendada de correção

1. Tornar a inicialização resiliente a zoxide/mise ausentes ou não gerados.
2. Corrigir os dois defeitos reproduzidos de completion.
3. Implementar as pendências cross-platform de `safe-remove`, `env.nu` e
   zoxide já listadas em `tasks.md`.
4. Proteger `index.nuon` com escrita atômica, backup e recuperação.
5. Criar testes versionados para os casos reproduzidos e os fluxos seguros de
   `ai-profile`.
