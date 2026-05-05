# Plano Implementado: Completer `nvim`/`n` com Busca Híbrida

## Resumo
Implementação de um novo módulo de completion para `nvim` e alias `n`, com estratégia híbrida (`git ls-files` + `glob`) para manter performance e ampliar cobertura, incluindo arquivos ignorados pelo git como `.env*`.

O comportamento é semi-recursivo:
- profundidade moderada por padrão
- profundidade maior quando o usuário digita caminho parcial com `/`

## Mudanças de Implementação
- Criação de `modules/completions/nvim.nu` com `nvim_completer`.
- Registro do novo completer em `modules/completions/mod.nu`.
- Detecção de comando real via resolução de alias (cobrindo `n -> nvim`).
- Estratégia de candidatos:
  1. Base tracked via `git ls-files`.
  2. Base de descoberta via `glob "**/*"` com profundidade dinâmica.
  3. Merge e deduplicação por caminho relativo normalizado.
- Recursão dinâmica:
  - sem `/` no termo parcial: depth `4`
  - com `/` no termo parcial: depth `8`
- Filtros:
  - exclusão de diretórios pesados/ruído (`.git`, `node_modules`, `.next`, `.expo`, `dist`, `build`, `coverage`, `target`, `.cache`)
  - exclusão de extensões binárias/mídia comuns para reduzir poluição
  - `.env*` permanece visível
- Ordenação de resultados:
  - prioridade por fonte (tracked antes de discovered)
  - depois profundidade
  - depois nome

## Interfaces e Comportamento
- Cobertura de completion:
  - `nvim <TAB>`
  - `n <TAB>`
- Formato retornado:
  - `{ value, description, priority }`
- Integração com fallback existente:
  - quando não aplicável, segue fluxo do `external_completer` com `carapace`

## Validação Executada
- Carregamento do módulo principal:
  - `nu -c 'use modules/completions/mod.nu [external_completer]; "ok"'`
- Execução direta do completer:
  - `nu -c 'use modules/completions/nvim.nu [nvim_completer]; nvim_completer ["nvim" ""] | first 3 | to json -r'`
- Resultado observado incluiu `.env`, confirmando cobertura de arquivo ignorado pelo git.

## Assumptions e Defaults
- Fonte híbrida adotada: `git + glob`.
- `.env*` não deve ser ocultado mesmo quando ignorado pelo git.
- Defaults de profundidade definidos inicialmente como `4` e `8`.
