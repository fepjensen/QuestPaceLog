# Updates the QuestPaceLog page on fjportfolio.com from your saved data.
# Log out or /reload first, the game only writes its saved file then.
# Reads the WTF folder, never changes it. Publishes only after you type y.
$portfolio = 'F:\Claude Code\portfolio'
$data = 'src/data/lab/questpacelog.json'

python "$PSScriptRoot\tools\export_site.py" --out (Join-Path $portfolio $data)
if ($LASTEXITCODE) { Write-Host 'The export failed, nothing changed.'; exit 1 }

Push-Location $portfolio
try {
    if (-not (git status --porcelain -- $data)) { Write-Host 'No new data since the last update.'; return }
    git diff --stat -- $data
    Write-Host 'Checking that the site still builds...'
    npm run build | Out-Null
    if ($LASTEXITCODE) { git checkout -- $data; Write-Host 'The site build failed with the new data, nothing was published.'; exit 1 }
    if ((Read-Host 'Publish to fjportfolio.com? Type y for yes') -ne 'y') {
        git checkout -- $data
        Write-Host 'Not published.'
        return
    }
    git add -- $data
    git commit -m "Lab, QuestPaceLog data from $(Get-Date -Format yyyy-MM-dd)" -- $data
    git push
    Write-Host 'Published. Cloudflare rebuilds the site in a minute or two.'
} finally {
    Pop-Location
}
