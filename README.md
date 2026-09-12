# Nushell config

Este repositório contém minhas configurações pessoais para o **Nushell**.

Para garantir que as completações de comando funcionem corretamente, é **essencial** ter o `carapace-bin` instalado.

Você pode encontrar o `carapace-bin` e mais informações sobre ele aqui:
[https://github.com/carapace-sh/carapace-bin](https://github.com/carapace-sh/carapace-bin)

## Comandos de perfis e snapshots

Os comandos desta configuração Nushell usam o prefixo `nu-`:

```nu
nu-ai-profile <tool> list
nu-repo-zip .
```

Os equivalentes em Go agora são distribuídos pelo repositório
`matheusvcouto/cli-tools`. Para instalá-los globalmente com Mise, use:

```nu
mise use -g github:matheusvcouto/cli-tools
```

O prefixo evita conflito entre os comandos Nushell e as versões em Go.
