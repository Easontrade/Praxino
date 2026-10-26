param(
    [Parameter(Mandatory)][string]$Video,
    [int]$Seconds = 2,
    [string]$Ffmpeg = "ffmpeg",
    [string]$Esrgan = "realesrgan-ncnn-vulkan",
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "praxino-offline")
)

$frames = Join-Path $Work 'frames'
$upscaled = Join-Path $Work 'upscaled'
$output = Join-Path $Work 'enhanced.mp4'
Remove-Item $frames, $upscaled -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $frames, $upscaled -Force | Out-Null

& $Ffmpeg -y -i $Video -t $Seconds -vf fps=1 -qscale:v 1 (Join-Path $frames '%08d.png') 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg frame extraction failed' }

& $Esrgan -i $frames -o $upscaled -n realesr-animevideov3 -s 2 -f png 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Real-ESRGAN failed' }

& $Ffmpeg -y -framerate 1 -i (Join-Path $upscaled '%08d.png') -i $Video -map 0:v:0 -map 1:a? `
    -t $Seconds -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a copy $output 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg encode failed' }

$info = & $Ffmpeg -hide_banner -i $output 2>&1 | Select-String -Pattern 'Video:' | Select-Object -First 1
Write-Output "offline_e2e_ok output=$output"
Write-Output $info.Line.Trim()
