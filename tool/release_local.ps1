param(
    [string]$Version = "1.0.0",
    [string]$Iscc = (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
)

# Expects flutter and git on PATH (see AGENTS.local.md for this machine's setup).
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    flutter build windows --release
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
