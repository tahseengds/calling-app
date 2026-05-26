# Sanitize a raw Claude Code session JSONL before committing.
#
# Usage:
#   .\sanitize.ps1 <src.jsonl> <dst.jsonl>
#
# Example:
#   .\sanitize.ps1 `
#     "$env:USERPROFILE\.claude\projects\D--calling-app\<uuid>.jsonl" `
#     "2026-06-12-session-c-topic.jsonl"
#
# After running, grep the output for any AIzaSy / eyJ / +1xxxxxxxxxx etc.
# to confirm nothing leaked, then `git add` it.

param(
  [Parameter(Mandatory)][string]$Src,
  [Parameter(Mandatory)][string]$Dst
)

if (-not (Test-Path $Src)) {
  Write-Error "Source file not found: $Src"
  exit 1
}

# Patterns must stay in sync with the README table and the .gitignore note.
$replacements = @(
  @('AIzaSy[A-Za-z0-9_-]{33}',                                          '[REDACTED_FIREBASE_API_KEY]'),
  @('eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}', '[REDACTED_JWT]'),
  @('\+92\d{10}',                                                       '[REDACTED_PHONE_PK]'),
  @('\+1\d{10}',                                                        '[REDACTED_PHONE_US]'),
  @('Bearer\s+[A-Za-z0-9_.-]{30,}',                                     'Bearer [REDACTED]'),
  @('TURN_SECRET=[A-Za-z0-9]{16,}',                                     'TURN_SECRET=[REDACTED]'),
  @('165\.227\.146\.247',                                               '[REDACTED_VPS_IP]')
)

$content = [System.IO.File]::ReadAllText($Src)
Write-Host "── Sanitizing $Src ──"

foreach ($rep in $replacements) {
  $count = ([regex]::Matches($content, $rep[0])).Count
  if ($count -gt 0) {
    Write-Host ("  redacted {0,4} × {1}" -f $count, $rep[0])
    $content = [regex]::Replace($content, $rep[0], $rep[1])
  }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Dst, $content, $utf8NoBom)
$sizeMb = [math]::Round((Get-Item $Dst).Length / 1MB, 2)
Write-Host "  wrote $Dst ($sizeMb MB)"

# Verification pass — re-grep the output, complain if any pattern still matches.
Write-Host ""
Write-Host "── Verifying no secrets remain ──"
$leak = $false
$sanitized = [System.IO.File]::ReadAllText($Dst)
foreach ($rep in $replacements) {
  $count = ([regex]::Matches($sanitized, $rep[0])).Count
  if ($count -gt 0) {
    Write-Host "  LEAK: $count × $($rep[0]) still in output" -ForegroundColor Red
    $leak = $true
  }
}
if (-not $leak) {
  Write-Host "  Clean — safe to commit." -ForegroundColor Green
} else {
  Write-Host ""
  Write-Error "Sanitization incomplete — do NOT commit. Investigate the patterns above."
  exit 2
}
