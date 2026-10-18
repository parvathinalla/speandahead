param([switch]$SkipBuild, [int]$Port = 8080)

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Push-Location $projectRoot
try {
    if (-not $SkipBuild) {
        & flutter build web --profile --no-pub --no-wasm-dry-run --dart-define-from-file=backend/private/flutter.public.json --output=build/web-profile
        if ($LASTEXITCODE -ne 0) { throw 'Flutter profile build failed.' }
    }
    if (-not (Test-Path -LiteralPath 'build/web-profile/main.dart.js')) {
        throw 'Build the web profile before using -SkipBuild.'
    }
    & .\.venv\Scripts\python.exe -m http.server $Port --directory build/web-profile --bind 127.0.0.1
} finally {
    Pop-Location
}
