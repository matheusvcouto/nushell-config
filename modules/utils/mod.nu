# Utilitários genéricos, reutilizáveis por qualquer módulo.

# Apaga um caminho permanentemente, só se ele estiver de fato dentro de
# `allowed_root`. Defesa em profundidade: protege contra apagar a coisa
# errada se `path` algum dia vier vazio, relativo, ou apontando pra fora do
# diretório esperado por causa de um bug em quem chama.
export def safe-remove [
    path: string
    allowed_root: string
] {
    if ($path | is-empty) {
        error make { msg: "safe-remove: caminho vazio, recusando apagar" }
    }

    let resolved = ($path | path expand)
    let root = ($allowed_root | path expand)

    if not ($resolved | str starts-with $"($root)/") {
        error make {
            msg: $"safe-remove: ($resolved) não está dentro de ($root), recusando apagar"
        }
    }

    if not ($resolved | path exists) {
        error make { msg: $"safe-remove: ($resolved) não existe" }
    }

    rm --recursive --permanent $resolved
}
