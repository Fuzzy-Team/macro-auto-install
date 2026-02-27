Param()

# Windows installer for Fuzzy Macro
# Downloads latest release zip from GitHub, extracts to Downloads, and runs install_dependencies.bat

Write-Host "Fuzzy Macro Windows installer"

try {
    $AppDir = Join-Path -Path $env:USERPROFILE -ChildPath "Downloads\Fuzzy Macro"
    if (Test-Path $AppDir) {
        Write-Host "Removing existing folder: $AppDir"
        Remove-Item -Recurse -Force -LiteralPath $AppDir
    }
    New-Item -ItemType Directory -Path $AppDir | Out-Null

    Write-Host "Querying GitHub for latest release..."
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Fuzzy-Team/Fuzzy-Macro/releases/latest' -UseBasicParsing -ErrorAction SilentlyContinue
    if ($null -eq $release -or $release.tag_name -eq $null) {
        Write-Host "Falling back to tags API"
        $tags = Invoke-RestMethod -Uri 'https://api.github.com/repos/Fuzzy-Team/Fuzzy-Macro/tags?per_page=100' -UseBasicParsing
        if ($tags -and $tags[0].name) { $tag = $tags[0].name } else { $tag = 'main' }
        $zipUrl = "https://github.com/Fuzzy-Team/Fuzzy-Macro/archive/refs/tags/$tag.zip"
    } else {
        $zipUrl = $release.zipball_url
        $tag = $release.tag_name
    }

    Write-Host "Downloading $zipUrl"
    $tmpZip = Join-Path -Path $env:TEMP -ChildPath "fuzzy_macro.zip"
    Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing

    Write-Host "Extracting to $AppDir"
    Expand-Archive -LiteralPath $tmpZip -DestinationPath $AppDir -Force
    Remove-Item $tmpZip -Force

    # Move inner folder contents up if necessary
    $inner = Get-ChildItem -LiteralPath $AppDir -Directory | Where-Object { $_.Name -like 'Fuzzy-Macro*' } | Select-Object -First 1
    if ($inner) {
        Get-ChildItem -LiteralPath $inner.FullName | ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination $AppDir -Force
        }
        Remove-Item -Recurse -Force -LiteralPath $inner.FullName
    }

    # Run the bundled Windows dependency installer if present
    $installScript = Join-Path -Path $AppDir -ChildPath 'install_dependencies.bat'
    if (Test-Path $installScript) {
        Write-Host "Running dependency installer: $installScript"
        Start-Process -FilePath $installScript -WorkingDirectory $AppDir -Verb runAs
    } else {
        Write-Host "Warning: install_dependencies.bat not found in $AppDir. You may need to install dependencies manually."
    }

    # Create Desktop shortcut to run_macro.bat
    $runMacro = Join-Path -Path $AppDir -ChildPath 'run_macro.bat'
    if (Test-Path $runMacro) {
        $desktopLnk = Join-Path -Path $env:USERPROFILE -ChildPath 'Desktop\Fuzzy Macro.lnk'
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($desktopLnk)
        $Shortcut.TargetPath = $runMacro
        $Shortcut.WorkingDirectory = $AppDir
        $Shortcut.WindowStyle = 1
        $Shortcut.Save()
        Write-Host "Created Desktop shortcut at $desktopLnk"
    } else {
        Write-Host "run_macro.bat not found; skipping shortcut creation."
    }

    Write-Host "Installation complete. Open the Desktop shortcut or run run_macro.bat to launch the macro."
    exit 0
}
catch {
    Write-Error "Installer failed: $_"
    exit 1
}
