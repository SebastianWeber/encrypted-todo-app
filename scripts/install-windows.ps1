<#
.SYNOPSIS
  Installiert oder aktualisiert den Windows-Client der verschlüsselten
  ToDo-App aus dem neuesten GitHub-Release.

.DESCRIPTION
  Ohne Parameter: lädt das aktuelle Windows-ZIP, entpackt es nach
  $InstallDir und legt eine Startmenü-Verknüpfung an. Zugangsdaten,
  Schlüssel und lokale Daten bleiben bei Updates erhalten (Windows
  Credential Manager bzw. %APPDATA%\de.sweber\encrypted_todo_app).

  Mit -Owner/-Repo/-Token (optional -Passphrase): hinterlegt zusätzlich
  eine Erstkonfiguration (provision.json), die die App beim ersten Start
  ins Onboarding übernimmt und danach löscht. Nur für die Ersteinrichtung
  nötig — bestehende Installationen brauchen das nicht.

.EXAMPLE
  .\install-windows.ps1
  (reines Update)

.EXAMPLE
  .\install-windows.ps1 -Owner SebastianWeber -Repo encrypted-todo-app-backend -Token github_pat_... -Passphrase "..."
  (Neuinstallation inkl. Erstkonfiguration)
#>
param(
    [string]$InstallDir = "$env:LOCALAPPDATA\EncryptedTodo",
    [string]$Owner,
    [string]$Repo,
    [string]$Branch = "main",
    [string]$Token,
    [string]$Passphrase
)

$ErrorActionPreference = 'Stop'
$releaseApi = 'https://api.github.com/repos/SebastianWeber/encrypted-todo-app/releases/latest'

$release = Invoke-RestMethod $releaseApi
$asset = $release.assets | Where-Object { $_.name -like 'EncryptedTodo-Windows-*.zip' } | Select-Object -First 1
if (-not $asset) { throw 'Kein Windows-ZIP am neuesten Release gefunden.' }

Write-Host "Lade $($asset.name) ($($release.tag_name)) ..."
$zipPath = Join-Path $env:TEMP $asset.name
Invoke-WebRequest $asset.browser_download_url -OutFile $zipPath

if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }
Expand-Archive $zipPath -DestinationPath $InstallDir
Remove-Item $zipPath

# Startmenü-Verknüpfung
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Verschluesselte ToDos.lnk'
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($shortcut)
$link.TargetPath = Join-Path $InstallDir 'encrypted_todo_app.exe'
$link.WorkingDirectory = $InstallDir
$link.Save()

# Optionale Erstkonfiguration
if ($Owner -and $Repo -and $Token) {
    $supportDir = Join-Path $env:APPDATA 'de.sweber\encrypted_todo_app'
    New-Item -ItemType Directory -Force $supportDir | Out-Null
    $provision = [ordered]@{
        owner  = $Owner
        repo   = $Repo
        branch = $Branch
        token  = $Token
    }
    if ($Passphrase) { $provision.passphrase = $Passphrase }
    ($provision | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $supportDir 'provision.json')
    Write-Host 'Erstkonfiguration hinterlegt - die App uebernimmt sie beim naechsten Start ins Onboarding.'
}

Write-Host "Fertig: $($release.tag_name) installiert nach $InstallDir"
Write-Host "Start: $shortcut"
