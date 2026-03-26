# modules/completions.nu

use ./bun.nu  [bun_completer]
use ./mise.nu [mise_completer]

# Registo de completers modulares
export def external_completer [spans: list<string>] {
    # Registo de completers modulares
    let completers = [
        {|spans| mise_completer $spans }
        {|spans| bun_completer $spans }
        # Adicione novos completers aqui no futuro
    ]

    let expanded_alias = (scope aliases 
        | where name == $spans.0 
        | get --optional 0 
        | get --optional expansion)
        
    let real_cmd = (if $expanded_alias != null {
        $expanded_alias | split row " " | take 1
    } else {
        $spans.0
    })

    # Tenta encontrar um completer registrado que retorne um valor não-nulo
    mut result = null
    for completer in $completers {
        let res = (do $completer $spans)
        if ($res != null) and not ($res | is-empty) {
            $result = $res
            break
        }
    }
    
    # Se encontrou, retorna. Se não, fallback para carapace w/ leniency
    if $result != null {
        $result
    } else {
        CARAPACE_LENIENT=1 carapace $real_cmd nushell ...$spans | from json
    }
}
