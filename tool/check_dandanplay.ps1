# Smoke-tests the dandanplay AppId/AppSecret pair against the open danmaku API,
# so an approved credential can be checked without starting the player.
#
# Signature scheme (same as lib/core/danmaku/dandanplay_provider.dart):
#   base64(sha256(appId + timestamp + path + appSecret)), timestamp in seconds,
#   path is the API path without the query string.
param(
    [string]$AppId = $env:PRAXINO_DANDAN_APP_ID,
    [string]$AppSecret = $env:PRAXINO_DANDAN_APP_SECRET,
    [string]$Anime = '孤独摇滚',
    [string]$BaseUrl = 'https://api.dandanplay.net'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($AppId) -or [string]::IsNullOrWhiteSpace($AppSecret)) {
    throw 'Pass -AppId/-AppSecret or set PRAXINO_DANDAN_APP_ID / PRAXINO_DANDAN_APP_SECRET.'
}

function New-SignatureHeaders([string]$Path) {
    $timestamp = [string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $raw = "$AppId$timestamp$Path$AppSecret"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw))
    } finally {
        $sha.Dispose()
    }
    return @{
        'X-AppId'     = $AppId
        'X-Timestamp' = $timestamp
        'X-Signature' = [Convert]::ToBase64String($hash)
        'Accept'      = 'application/json'
    }
}

function Invoke-Dandanplay([string]$Path, [hashtable]$Query) {
    $queryString = ($Query.GetEnumerator() | ForEach-Object {
        [uri]::EscapeDataString($_.Key) + '=' + [uri]::EscapeDataString([string]$_.Value)
    }) -join '&'
    $uri = "$BaseUrl$Path" + $(if ($queryString) { "?$queryString" } else { '' })
    try {
        $response = Invoke-WebRequest -Uri $uri -Headers (New-SignatureHeaders $Path) -Method Get
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        $body = $_.ErrorDetails.Message
        # 403 means the signature/AppId pair was rejected. An empty body is the
        # usual answer for a credential the open platform has not approved yet.
        $hint = if ([string]::IsNullOrWhiteSpace($body)) {
            '(no body: AppId/AppSecret rejected, or the application is not approved yet)'
        } else {
            $body
        }
        throw "HTTP $status from $Path : $hint"
    }
    return $response.Content | ConvertFrom-Json
}

Write-Output "checking $BaseUrl as appId=$AppId"
$result = Invoke-Dandanplay -Path '/api/v2/search/episodes' -Query @{ anime = $Anime }
if ($result.success -ne $true) {
    throw "request rejected: $($result.errorMessage) (code=$($result.errorCode))"
}

# The live API groups results per anime: {animes:[{animeTitle, episodes:[...]}]}.
# Loop variables must not shadow the $Anime parameter (PowerShell is
# case-insensitive), otherwise the title would be read as a string.
$episodes = @(
    foreach ($animeEntry in @($result.animes)) {
        foreach ($episodeEntry in @($animeEntry.episodes)) {
            [pscustomobject]@{
                episodeId    = $episodeEntry.episodeId
                animeTitle   = $animeEntry.animeTitle
                episodeTitle = $episodeEntry.episodeTitle
            }
        }
    }
)
Write-Output "ok episodes=$($episodes.Count)"
foreach ($row in $episodes | Select-Object -First 5) {
    Write-Output "  [$($row.episodeId)] $($row.animeTitle) / $($row.episodeTitle)"
}
if ($episodes.Count -gt 0) {
    $first = $episodes[0].episodeId
    $comments = Invoke-Dandanplay -Path "/api/v2/comment/$first" -Query @{ withRelated = 'true'; chConvert = '1' }
    Write-Output "ok comments=$(@($comments.comments).Count) episode=$first"
}
Write-Output 'dandanplay_ok'
