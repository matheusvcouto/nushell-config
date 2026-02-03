# Load .env file if it exists (OS-agnostic, works on Windows/Linux/macOS)
const env_file = $nu.env-path | path dirname | path join '.env'

if ($env_file | path exists) {
    open $env_file
    | lines
    | where ($it | str length) > 0
    | where ($it | str starts-with '#') == false
    | parse -r '(?P<key>[^=]+)=(?P<value>.*)'
    | reduce --fold {} {|row, acc|
        $acc | insert ($row | get key) ($row.value | str trim -c '"')
    }
    | load-env
}

# Test environment variable
$env.TESTE_NUSH = "valor_teste"