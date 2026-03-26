# modules/completions/mise.nu

def parse_mise_commands [] {
    ^mise --help
    | lines
    | parse -r '^\s{2}(?P<value>[a-z][a-z0-9-]*)\s{2,}(?P<description>.+)$'
}

def parse_mise_flags [] {
    ^mise --help
    | lines
    | parse -r '^\s{2}(?P<short>-[A-Za-z]),\s(?P<value>--[a-z0-9-]+)(?:\s.+)?$'
    | each {|row|
        {value: $row.value, description: $"($row.short), ($row.value)"}
    }
}

# Completer específico para `mise`
export def mise_completer [spans: list<string>] {
    let expanded_alias = (scope aliases
        | where name == $spans.0
        | get --optional 0
        | get --optional expansion)

    let real_cmd = (if $expanded_alias != null {
        $expanded_alias | split row " " | take 1
    } else {
        $spans.0
    })

    if $real_cmd != "mise" {
        return null
    }

    let full_spans = (if $expanded_alias != null {
        $spans | skip 1 | prepend ($expanded_alias | split row " ")
    } else {
        $spans
    })

    let partial = ($full_spans | last | default "")
    let only_command_or_first_arg = (($full_spans | length) <= 2)
    let is_flag_context = ($partial | str starts-with "-")

    if ($only_command_or_first_arg or $is_flag_context) {
        let command_candidates = (if $only_command_or_first_arg { parse_mise_commands } else { [] })
        let flag_candidates = (if ($only_command_or_first_arg or $is_flag_context) { parse_mise_flags } else { [] })
        let all_candidates = [$command_candidates $flag_candidates] | flatten

        if ($partial | is-empty) {
            $all_candidates
        } else {
            let needle = ($partial | str downcase)
            $all_candidates | where {|opt| ($opt.value | str downcase) | str starts-with $needle}
        }
    } else {
        null
    }
}
