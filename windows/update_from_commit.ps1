Param(
    [Parameter(Mandatory = $false)]
    [string]$CommitHash
)

$ErrorActionPreference = 'Stop'

function Write-Status {
    param([string]$Message)
    Write-Host "[update-from-commit] $Message"
}

if ([string]::IsNullOrWhiteSpace($CommitHash)) {
    $CommitHash = Read-Host 'Enter commit hash to install'
}

if ([string]::IsNullOrWhiteSpace($CommitHash)) {
    Write-Error 'No commit hash provided. Update aborted.'
    exit 1
}

# Match update.py behavior: cwd.replace('/src', '')
$cwd = (Get-Location).Path
if ($cwd -match '[\\/]src$') {
    $destination = Split-Path -Path $cwd -Parent
} else {
    $destination = $cwd
}

if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
    Write-Error "Invalid install directory: $destination"
    exit 1
}

$protectedFolders = @(
    'src/data/user',
    'settings/profiles',
    'settings/patterns'
)

$backupPath = Join-Path -Path $destination -ChildPath 'backup_macro.zip'
$markerPath = Join-Path -Path $destination -ChildPath '.backup_pending'
$remoteZip = "https://github.com/Fuzzy-Team/Fuzzy-Macro/archive/$CommitHash.zip"

Write-Status "Updating to commit $CommitHash"

# Create backup in a staging folder, excluding protected folders and .git.
$backupStage = Join-Path -Path $env:TEMP -ChildPath ("fuzzy_backup_stage_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backupStage | Out-Null

try {
    $protectedFull = @()
    foreach ($p in $protectedFolders) {
        $protectedFull += [IO.Path]::GetFullPath((Join-Path $destination $p))
    }

    Get-ChildItem -LiteralPath $destination -Force | ForEach-Object {
        if ($_.Name -eq '.git') {
            return
        }
        if ($_.FullName -eq $backupPath) {
            return
        }

        $itemFull = [IO.Path]::GetFullPath($_.FullName)
        foreach ($pf in $protectedFull) {
            if ($itemFull.Equals($pf, [System.StringComparison]::OrdinalIgnoreCase)) {
                return
            }
        }

        $target = Join-Path -Path $backupStage -ChildPath $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $backupPath) {
        Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
    }
    Compress-Archive -Path (Join-Path $backupStage '*') -DestinationPath $backupPath -Force -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $markerPath -Value '1' -Encoding ascii -ErrorAction SilentlyContinue
}
finally {
    if (Test-Path -LiteralPath $backupStage) {
        Remove-Item -LiteralPath $backupStage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Download and extract commit zip.
$tmpRoot = Join-Path -Path $env:TEMP -ChildPath ("fuzzy_update_commit_" + [guid]::NewGuid().ToString('N'))
$tmpZip = Join-Path -Path $tmpRoot -ChildPath 'update.zip'
$tmpExtract = Join-Path -Path $tmpRoot -ChildPath 'extract'
New-Item -ItemType Directory -Path $tmpExtract -Force | Out-Null

try {
    Invoke-WebRequest -Uri $remoteZip -OutFile $tmpZip -UseBasicParsing
    Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpExtract -Force

    $extracted = Get-ChildItem -LiteralPath $tmpExtract -Directory | Where-Object { $_.Name -like 'Fuzzy-Macro*' } | Select-Object -First 1
    if (-not $extracted) {
        $extracted = Get-ChildItem -LiteralPath $tmpExtract -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'src') } | Select-Object -First 1
    }
    if (-not $extracted) {
        throw 'Could not locate extracted update folder.'
    }

    # Merge main content while excluding protected folders.
    $excludeDirs = @('/XD')
    foreach ($p in $protectedFolders) {
        $excludeDirs += (Join-Path $extracted.FullName $p)
    }

    $rcArgs = @(
        $extracted.FullName,
        $destination,
        '/E',
        '/R:1',
        '/W:1',
        '/NFL',
        '/NDL',
        '/NJH',
        '/NJS',
        '/NP',
        '/XF', '.git'
    ) + $excludeDirs

    & robocopy @rcArgs | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ge 8) {
        throw "Error while applying update files (robocopy exit code $rc)."
    }

    # Merge patterns without overwriting existing files.
    $srcPatterns = Join-Path $extracted.FullName 'settings/patterns'
    $dstPatterns = Join-Path $destination 'settings/patterns'
    if (Test-Path -LiteralPath $srcPatterns) {
        Get-ChildItem -LiteralPath $srcPatterns -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($srcPatterns.Length).TrimStart('\\', '/')
            $dstFile = Join-Path $dstPatterns $relative
            $dstDir = Split-Path -Path $dstFile -Parent
            if (-not (Test-Path -LiteralPath $dstDir)) {
                New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
            }

            if (-not (Test-Path -LiteralPath $dstFile)) {
                Copy-Item -LiteralPath $_.FullName -Destination $dstFile -Force -ErrorAction SilentlyContinue
            }
            else {
                $nameWithoutExt = [IO.Path]::GetFileNameWithoutExtension($dstFile)
                $ext = [IO.Path]::GetExtension($dstFile)
                $i = 1
                while ($true) {
                    $newName = "$nameWithoutExt.new$i$ext"
                    $newPath = Join-Path $dstDir $newName
                    if (-not (Test-Path -LiteralPath $newPath)) {
                        Copy-Item -LiteralPath $_.FullName -Destination $newPath -Force -ErrorAction SilentlyContinue
                        break
                    }
                    $i++
                }
            }
        }

        # Cleanup .newN files, matching update.py behavior.
        Get-ChildItem -LiteralPath $dstPatterns -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^(?<base>.+?)\.new\d+(?<ext>\..+)?$' } |
            ForEach-Object {
                $base = $Matches['base']
                $ext = $Matches['ext']
                if (-not $ext) { $ext = '' }
                $targetName = "$base$ext"
                $target = Join-Path $_.DirectoryName $targetName
                if (Test-Path -LiteralPath $target) {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                }
                else {
                    Move-Item -LiteralPath $_.FullName -Destination $target -Force -ErrorAction SilentlyContinue
                }
            }
    }

    $runMacroBat = Join-Path $destination 'run_macro.bat'
    if (Test-Path -LiteralPath $runMacroBat) {
        # No chmod needed on Windows, but touch file to verify presence.
        Write-Status "Found run_macro.bat"
    }

    $commitMarker = Join-Path $destination 'src/webapp/updated_commit.txt'
    $commitMarkerDir = Split-Path -Path $commitMarker -Parent
    if (-not (Test-Path -LiteralPath $commitMarkerDir)) {
        New-Item -ItemType Directory -Path $commitMarkerDir -Force | Out-Null
    }
    Set-Content -LiteralPath $commitMarker -Value $CommitHash.Substring(0, [Math]::Min(7, $CommitHash.Length)) -NoNewline -Encoding ascii

    # Attempt to run install dependencies script (non-blocking).
    $installScript = Join-Path $destination 'install_dependencies.bat'
    if (Test-Path -LiteralPath $installScript) {
        Start-Process -FilePath $installScript -WorkingDirectory $destination -WindowStyle Hidden
    }

    Write-Status "Update complete. You can now relaunch the macro."
    exit 0
}
catch {
    Write-Error "Update failed: $_"
    exit 1
}
finally {
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
