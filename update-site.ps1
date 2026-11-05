# Updates the Adventurer's Almanac page in the Lab on fjportfolio.com from your saved data.
# The game writes its saved file when you log out or /reload.
# Reads the WTF folder, never changes it. Asks before publishing, or with -Auto (the daily
# scheduled task) publishes on its own when there's new data and the site still builds.
param([switch]$Auto)
$portfolio = 'F:\Claude Code\portfolio'
$data = 'src/data/lab/questpacelog.json'
$archive = 'src/data/lab/questpacelog-beta.json'
$log = Join-Path $PSScriptRoot 'logs\site-update.log'

function Say($text) {
    Write-Host $text
    if ($Auto) {
        New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
        Add-Content $log "$(Get-Date -Format 'yyyy-MM-dd HH:mm') $text"
    }
}

# The beta summary is the only copy of the beta data left. It lives in its own file, which
# this script never writes, and the page's Beta tab reads it.
if (-not (Test-Path (Join-Path $portfolio $archive))) { Say 'The beta archive is missing from the portfolio, nothing was changed.'; exit 1 }

Push-Location $portfolio
try {
    # Unattended, never publish site work you haven't published yourself.
    if ($Auto -and (git rev-list --count '@{u}..HEAD') -ne '0') { Say 'The portfolio has commits you have not pushed yet, so nothing was published.'; exit 1 }

    python "$PSScriptRoot\tools\export_site.py" --out $data
    if ($LASTEXITCODE) { git checkout -- $data; Say 'The export failed, nothing changed.'; exit 1 }
    # The export stamps today's date, so a change in that line alone isn't new play.
    $changed = git diff -U0 -- $data | Where-Object { $_ -match '^[+-]\s' -and $_ -notmatch '"generatedOn"' }
    if (-not $changed) { git checkout -- $data; Say 'No new play since the last update.'; return }
    git diff --stat -- $data
    Write-Host 'Checking that the site still builds...'
    npm run build | Out-Null
    if ($LASTEXITCODE) { git checkout -- $data; Say 'The site build failed with the new data, nothing was published.'; exit 1 }
    if (-not $Auto -and (Read-Host 'Publish to fjportfolio.com? Type y for yes') -ne 'y') {
        git checkout -- $data
        Write-Host 'Not published.'
        return
    }
    git add -- $data
    git commit -q -m "Lab, Adventurer's Almanac data from $(Get-Date -Format yyyy-MM-dd)" -- $data
    git push -q
    if ($LASTEXITCODE) { Say 'The push failed, the new data is committed locally and goes out with the next push.'; exit 1 }
    Say 'Published. Cloudflare rebuilds the site in a minute or two.'
} finally {
    Pop-Location
}
