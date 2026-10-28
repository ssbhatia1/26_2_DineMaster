$ErrorActionPreference = "Stop"

$envFile = Join-Path $PSScriptRoot ".env"
if (-not (Test-Path $envFile)) {
    throw ".env file not found in backend folder."
}

Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $parts = $line -split "=", 2
        $name = $parts[0].Trim()
        $value = $parts[1].Trim()

        if ($value.Length -ge 2 -and
            (($value.StartsWith('"') -and $value.EndsWith('"')) -or
             ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

if (-not $env:DB_USERNAME -or -not $env:DB_PASSWORD) {
    throw "DB_USERNAME or DB_PASSWORD is missing from .env."
}
if (-not $env:JWT_SECRET) {
    throw "JWT_SECRET is missing from .env."
}

& (Join-Path $PSScriptRoot "mvnw.cmd") spring-boot:run
exit $LASTEXITCODE
