# modules/completions/deno.nu

# Lê o campo "tasks" de deno.json/deno.jsonc, aceitando valor string ou
# objeto {command, description} (formato novo do Deno)
def parse_deno_tasks [] {
    let config_path = (if ("deno.json" | path exists) {
        "deno.json"
    } else if ("deno.jsonc" | path exists) {
        "deno.jsonc"
    } else {
        null
    })

    if $config_path == null {
        []
    } else {
        let raw = (open --raw $config_path)
        # Remoção simples de comentários de linha (best-effort, não é um parser JSONC completo)
        let cleaned = ($raw | lines | each {|line| $line | str replace -r '(?<!:)//.*$' '' } | str join "\n")

        try {
            $cleaned
                | from json
                | get tasks?
                | default {}
                | items {|k, v|
                    let description = (if ($v | describe) == "string" {
                        $v
                    } else {
                        $v.description? | default ($v.command? | default "")
                    })
                    {value: $k, description: $description}
                }
        } catch {
            []
        }
    }
}

# Completer específico para `deno`
export def deno_completer [spans: list<string>] {
    let expanded_alias = (scope aliases
        | where name == $spans.0
        | get --optional 0
        | get --optional expansion)

    let real_cmd = (if $expanded_alias != null {
        $expanded_alias | split row " " | take 1
    } else {
        $spans.0
    })

    if $real_cmd != "deno" {
        return null
    }

    let full_spans = (if $expanded_alias != null {
        $spans | skip 1 | prepend ($expanded_alias | split row " ")
    } else {
        $spans
    })

    let subcommand = ($full_spans.1? | default "")
    let partial = ($full_spans | get --optional 2 | default "")

    if $subcommand == "task" {
        let candidates = parse_deno_tasks

        if ($partial | is-empty) {
            $candidates | sort-by value
        } else {
            let search_term = ($partial | str downcase)
            $candidates
                | where {|opt| ($opt.value | str downcase) | str contains $search_term}
                | sort-by value
        }
    } else if $subcommand == "run" {
        # Arquivos executáveis diretamente: .ts/.tsx/.js/.jsx sempre ESM,
        # .mjs sempre ESM, .cjs sempre CommonJS, .mts/.cts equivalentes TS
        let raw_files = (glob "**/*.{ts,tsx,js,jsx,mjs,cjs,mts,cts}" --depth 4)

        let filtered_files = ($raw_files | each {|file|
            let relative = ($file | path relative-to $env.PWD | str replace --all "\\" "/")

            let parts = ($relative | split row "/")
            let should_exclude = ($parts | any {|part|
                if $part in ["node_modules" ".git" "dist" "build" "coverage"] {
                    true
                } else if ($part | str starts-with ".") {
                    true
                } else {
                    false
                }
            })

            if $should_exclude {
                null
            } else {
                {value: $relative, description: "Script File"}
            }
        } | compact)

        let candidates = if ($partial | is-empty) {
            $filtered_files
        } else {
            let search_term = ($partial | str downcase)
            $filtered_files
                | where {|opt| ($opt.value | str downcase) | str contains $search_term}
        }

        $candidates | sort-by {|opt|
            {depth: ($opt.value | split row "/" | length), name: $opt.value}
        }
    } else {
        null
    }
}
