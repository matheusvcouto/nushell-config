$env.config.show_banner = false
$env.config.buffer_editor = "nvim"

alias ll = ls -l
alias n = nvim

# Configuração de completions externas para bun run (scripts + arquivos)
use modules/completions [external_completer]

$env.config.completions.external = {
    enable: true
    max_results: 100
    completer: {|spans| external_completer $spans }
}

source ~/.zoxide.nu

# Mise (ativação oficial para Nushell sem sobrescrever o comando externo `mise`)
source ($nu.default-config-dir | path join "mise.nu")


# experimental

# Define comandos inteligentes baseados no OS
let clipboard_command = (
    if ($nu.os-info.name == "windows") { 
        { copy: "clip.exe", paste: "powershell -command Get-Clipboard" }
    } else if ($nu.os-info.name == "macos") { 
        { copy: "pbcopy", paste: "pbpaste" }
    } else { 
        { copy: "xclip -sel clip", paste: "xclip -sel clip -o" }
    }
)

# Cria os aliases usando a definição acima
alias copy = ^$clipboard_command.copy
alias paste = ^$clipboard_command.paste

def --env vim-toggle [] {
  if $env.config.edit_mode == 'vi' {
    $env.config.edit_mode = 'emacs'
    print 'edit_mode: emacs'
  } else {
    $env.config.edit_mode = 'vi'
    print 'edit_mode: vi'
  }
}
alias vt = vim-toggle
$env.config.cursor_shape = {
  emacs: block
  vi_insert: line
  vi_normal: block
}

def crc32-py [
  text?: string
] {
  let value = if $text != null {
    $text
  } else {
    $in | into string | str trim
  }

  uv run python -c "import sys, zlib; print(zlib.crc32(sys.argv[1].encode('utf-8')))" $value
}

def crc32-bun [
  text?: string
] {
  let value = if $text != null {
    $text
  } else {
    $in | into string | str trim
  }

  bun -e "
    const s = process.argv[1];
    let c = -1;
    for (let i = 0; i < s.length; i++) {
      c ^= s.charCodeAt(i);
      for (let j = 0; j < 8; j++) {
        c = (c >>> 1) ^ (0xEDB88320 & -(c & 1));
      }
    }
    console.log((c ^ -1) >>> 0);
  " $value
}

def verify-password [
  prompt: string = "Digite"
  confirm_prompt: string = "Confirme"
] {
  let s1 = (input --suppress-output $"($prompt): ")
  let s2 = (input --suppress-output $"($confirm_prompt): ")

  if $s1 == $s2 {
    print "✓ senhas iguais"
    $s1
  } else {
    error make {msg: "senhas diferentes"}
  }
}


# Installed by:
# version = "0.110.0"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# Nushell sets "sensible defaults" for most configuration settings, 
# so your `config.nu` only needs to override these defaults if desired.
#
# You can open this file in your default editor using:
#     config nu
#
# You can also pretty-print and page through the documentation for configuration
# options using:
#     config nu --doc | nu-highlight | less -R
