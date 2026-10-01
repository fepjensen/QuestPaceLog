# Links the game's AddOns\QuestPaceLog to this repo's QuestPaceLog folder with a
# directory junction, so edits here show up in game after /reload. Safe to rerun.
# An old copied folder there is moved aside first, never deleted.
$dest = 'F:\World of Warcraft\_classic_beta_\Interface\AddOns\QuestPaceLog'
$src = Join-Path $PSScriptRoot 'QuestPaceLog'
$item = Get-Item $dest -ErrorAction SilentlyContinue
if ($item -and $item.LinkType -eq 'Junction') { Write-Host "Already linked to $($item.Target)"; return }
if ($item) {
    $backup = "$dest-old-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Move-Item $dest (Join-Path $env:TEMP (Split-Path $backup -Leaf))
    Write-Host "Moved the old copy to $env:TEMP\$(Split-Path $backup -Leaf)"
}
New-Item -ItemType Junction -Path $dest -Target $src | Out-Null
Write-Host "Linked $dest to $src"
# To undo, remove only the link, never its contents. (Get-Item $dest).Delete()
