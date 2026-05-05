# modules/completions/bun.nu

# Completer específico para `bun run`
export def bun_completer [spans: list<string>] {
    let expanded_alias = (scope aliases 
        | where name == $spans.0 
        | get --optional 0 
        | get --optional expansion)
        
    let real_cmd = (if $expanded_alias != null {
        $expanded_alias | split row " " | take 1
    } else {
        $spans.0
    })
    
    let full_spans = (if $expanded_alias != null {
        $spans | skip 1 | prepend ($expanded_alias | split row " ")
    } else {
        $spans
    })
    
    # Verifica se é "bun run"
    if ($real_cmd == "bun" and ($full_spans.1? == "run")) {
        let partial = ($full_spans | get --optional 2 | default "")
        
        # 1. Scripts do package.json
        let scripts = (if ("package.json" | path exists) {
            open "package.json"
                | get scripts? 
                | default {} 
                | items {|k, v| {value: $k, description: $v, priority: 0}}
        } else {
            []
        })
        
        # 2. Arquivos (TS/JS/TSX/MD) com exclusão robusta
        # Glob patterns para buscar arquivos relevantes
        let raw_files = (glob "**/*.{ts,js,tsx,md}" --depth 4)
        
        let filtered_files = ($raw_files | each {|file|
            let relative = ($file | path relative-to $env.PWD | str replace --all "\\" "/")
            
            # Lógica de Exclusão
            let parts = ($relative | split row "/")
            let should_exclude = ($parts | any {|part|
                # Regra 1: Pastas explicitamente proibidas
                if $part in ["node_modules" ".expo" ".next" "dist" "build" "coverage"] {
                    true
                } else if ($part | str starts-with ".") {
                    # Regra 2: Pastas ocultas (exceto whitelist)
                    if $part == ".-no-ignore" {
                        false # Permitido!
                    } else {
                        true # Bloqueado (outras pastas ocultas)
                    }
                } else {
                    false
                }
            })
            
            if $should_exclude {
                null # Filtra fora
            } else {
                {value: $relative, description: "Script File", priority: 1}
            }
        } | compact) # Remove os nulls
        
        let all_options = [$scripts $filtered_files] | flatten
        
        # 3. Busca e Ordenação
        let candidates = if ($partial | is-empty) {
            $all_options
        } else {
            let search_term = ($partial | str downcase)
            $all_options 
                | where {|opt| ($opt.value | str downcase) | str contains $search_term}
        }
        
        # Ordenação: Prioridade (Scripts) -> Profundidade (Arquivos próximos) -> Nome
        $candidates | sort-by {|opt| 
            let depth = ($opt.value | split row "/" | length)
            {
                priority: ($opt.priority? | default 1), 
                depth: $depth, 
                name: $opt.value
            }
        }
    } else {
        null # Retorna null se não for responsabilidade deste completer
    }
}
