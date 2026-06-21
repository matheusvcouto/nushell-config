# ai-profile

Contas isoladas (Pro pessoal vs. de um familiar, por exemplo) para CLIs de
IA, sem conflito de sessão. Um único comando cobre qualquer CLI configurada
em `TOOLS` dentro de `mod.nu` (hoje: `claude`, `codex`, `agy`).

## Uso

```
ai-profile <tool> list
ai-profile <tool> new <nome>
ai-profile <tool> rename <nome-antigo> <nome-novo>
ai-profile <tool> delete <nome>
ai-profile <tool> run <nome> ...args
```

`list` é o padrão se você omitir a ação (`ai-profile claude` == `ai-profile
claude list`).

## Exemplos

```
ai-profile claude new mae
ai-profile claude run mae
ai-profile agy new mae
ai-profile agy run mae --print "oi"
ai-profile claude rename mae monica
```

Na primeira vez que você roda `ai-profile <tool> run <nome>`, a CLI não tem
login ainda — faça o login normal dela dentro dessa sessão (ex: `/login`
no Claude) escolhendo a conta certa. Fica salvo isolado daquele perfil.

## O que não fazer

- Não mova/renomeie a pasta de um perfil manualmente (`~/.ai-profiles/...`).
  Use `ai-profile <tool> rename`, que só troca o rótulo sem tocar na pasta
  — é assim que o login não se perde (detalhes em `adr.md`).
- `ai-profile <tool> delete <nome>` apaga a pasta **permanentemente** (não
  vai pra lixeira). Confirme o nome antes de aceitar.

## Adicionar uma CLI nova

Uma entrada em `const TOOLS` (em `mod.nu`) é suficiente — nenhum comando
novo precisa ser escrito. Veja o comentário acima do array pra cada campo.
