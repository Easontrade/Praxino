param(
    [Parameter(Mandatory)][string]$Python,
    [Parameter(Mandatory)][string]$VsSite,
    [string]$Mpv = "mpv",
    [Parameter(Mandatory)][string]$Script,
    [Parameter(Mandatory)][string]$Video
)

$env:Path = "$Python;$VsSite;$env:Path"
$env:PYTHONPATH = Split-Path $VsSite -Parent
$env:VAPOURSYNTH_PLUGIN_PATH = Join-Path $VsSite 'plugins'

$work = Split-Path $Script -Parent
Push-Location $work
try {
    $output = & $Mpv --no-config --vo=null --ao=null `
        "--vf=vapoursynth=file=$(Split-Path $Script -Leaf)" --frames=5 $Video 2>&1
    $errors = $output | Select-String -Pattern 'Unsupported output|Failed to initialize|could not init VS|Filter error'
    if ($errors) {
        $errors | ForEach-Object { Write-Output $_.Line }
        exit 1
    }
    Write-Output "vs_e2e_ok script=$Script"
} finally {
    Pop-Location
}
