param(
    [string]$Version = "1.0.0",
    [string]$Iscc = (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
)

# Expects flutter and git on PATH (see AGENTS.local.md for this machine's setup).
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    # Dandanplay credentials are build-time defines, exactly like the release
    # workflow: they are read from the environment, base64 encoded, and never
    # written into the repository or the build log.
    $defines = @("--dart-define=APP_VERSION=$Version")
    $dandanAppId = $env:PRAXINO_DANDAN_APP_ID
    $dandanSecret = $env:PRAXINO_DANDAN_APP_SECRET
    if (-not [string]::IsNullOrWhiteSpace($dandanAppId) -and
        -not [string]::IsNullOrWhiteSpace($dandanSecret)) {
        $appIdB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($dandanAppId))
        $secretB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($dandanSecret))
        $defines += "--dart-define=DANDANPLAY_APP_ID_B64=$appIdB64"
        $defines += "--dart-define=DANDANPLAY_APP_SECRET_B64=$secretB64"
        Write-Output "dandanplay_credentials=embedded"
    } else {
        Write-Warning 'PRAXINO_DANDAN_APP_ID / PRAXINO_DANDAN_APP_SECRET not set; the installer will ask for credentials in settings.'
    }

    flutter build windows --release @defines
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }

    if (-not (Test-Path $Iscc)) {
        throw "ISCC not found at $Iscc"
    }
    & $Iscc "/DAppVersion=$Version" "installer\praxino.iss"
    if ($LASTEXITCODE -ne 0) { throw "installer compile failed" }

    $installer = Get-ChildItem "dist\Praxino-Setup-$Version.exe" -ErrorAction Stop
    $hash = (Get-FileHash $installer.FullName -Algorithm SHA256).Hash.ToLower()
    $hashFile = "$($installer.FullName).sha256"
    "$hash  $($installer.Name)" | Set-Content $hashFile -Encoding ascii

    $check = (Get-Content $hashFile -Raw).Split(' ')[0]
    if ($check -ne $hash) { throw "sha256 verification failed" }
    Write-Output "release_local_ok installer=$($installer.FullName) sha256=$hash"
} finally {
    Pop-Location
}
