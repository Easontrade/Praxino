param(
    [string]$Dll = "$env:APPDATA\Praxino\enhance-pack\libmpv-2.dll"
)

if (-not (Test-Path $Dll)) {
    Write-Output "vs_pack_missing $Dll"
    exit 1
}

$bytes = [System.IO.File]::ReadAllBytes($Dll)
$text = [System.Text.Encoding]::ASCII.GetString($bytes)
$hasVs = $text.Contains('vapoursynth') -or $text.Contains('VapourSynth')
Write-Output "vs_pack dll=$Dll size=$($bytes.Length) vapoursynth=$hasVs"
if (-not $hasVs) { exit 2 }
exit 0
