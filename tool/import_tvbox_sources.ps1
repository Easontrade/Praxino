param(
    [string]$List = "$env:APPDATA\Praxino\tvbox\import-list.txt",
    [string]$OutDir = "$env:APPDATA\Praxino\tvbox",
    [int]$TimeoutSec = 8,
    [int]$Throttle = 12
)

$lines = Get-Content $List -Encoding utf8 | Where-Object { $_ -match '\|' }
$seen = @{}
$entries = @()
foreach ($line in $lines) {
    $name, $url = $line.Split('|', 2)
    $url = $url.Trim()
    try {
        $uri = [Uri]$url
        $normalized = "$($uri.Scheme.ToLower())://$($uri.Host.ToLower()):$($uri.Port)$($uri.AbsolutePath.TrimEnd('/'))$($uri.Query)"
    } catch { continue }
    if ($seen.ContainsKey($normalized)) { continue }
    $seen[$normalized] = $true
    $entries += [pscustomobject]@{ Name = $name.Trim(); Url = $url }
}

$results = $entries | ForEach-Object -Parallel {
    $name = $_.Name
    $url = $_.Url
    $out = $using:OutDir
    $timeout = $using:TimeoutSec
    $hash = [BitConverter]::ToString(
        [Security.Cryptography.SHA256]::Create().ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($url)
        )
    ).Replace('-', '').Substring(0, 12).ToLower()
    $target = Join-Path $out "bulk-$hash.json"
    try {
        Invoke-WebRequest -Uri $url -OutFile $target -TimeoutSec $timeout `
            -UseBasicParsing -Headers @{ 'User-Agent' = 'okhttp/3.12.11' } | Out-Null
        $json = Get-Content $target -Raw -Encoding utf8 | ConvertFrom-Json
        return "OK $name sites=$($json.sites.Count) urls=$($json.urls.Count) $url"
    } catch {
        Remove-Item $target -Force -ErrorAction SilentlyContinue
        return "FAIL $name $url :: $($_.Exception.Message)"
    }
} -ThrottleLimit $Throttle

$results | Set-Content (Join-Path $OutDir 'import-results.txt') -Encoding utf8
$ok = ($results | Where-Object { $_ -like 'OK *' }).Count
$fail = $results.Count - $ok
Write-Output "unique=$($entries.Count) ok=$ok fail=$fail"
$results | Where-Object { $_ -like 'OK *' } | Select-Object -First 30
