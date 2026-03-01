Param()

# Windows installer for Fuzzy Macro (windowsTest branch)
# Downloads the `windowsTest` branch zip from GitHub, extracts to Downloads, and runs install_dependencies.bat

Write-Host "Fuzzy Macro Windows installer (windowsTest branch)"

try {
    $AppDir = Join-Path -Path $env:USERPROFILE -ChildPath "Downloads\Fuzzy Macro"
    if (Test-Path $AppDir) {
        Write-Host "Removing existing folder: $AppDir"
        Remove-Item -Recurse -Force -LiteralPath $AppDir
    }
    New-Item -ItemType Directory -Path $AppDir | Out-Null

    # Directly download the branch zip for windowsTest
    $branch = 'windowsTest'
    $zipUrl = "https://github.com/Fuzzy-Team/Fuzzy-Macro/archive/refs/heads/$branch.zip"

    Write-Host "Downloading $zipUrl"
    $tmpZip = Join-Path -Path $env:TEMP -ChildPath "fuzzy_macro_windowsTest.zip"
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

    # Check for Python 3 installation; download and install if missing
    Write-Host "Checking for Python 3 installation..."
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
    }
    if ($pythonCmd) {
        try {
            $verOutput = & $pythonCmd.Source --version 2>&1
        } catch {
            $verOutput = ""
        }
    } else {
        $verOutput = ""
    }
    if ($verOutput -and $verOutput -match 'Python\s+([0-9]+)\.') {
        $major = [int]$matches[1]
    } else {
        $major = 0
    }
    if ($major -ge 3) {
        Write-Host "Python $verOutput detected; skipping installation."
    } else {
        Write-Host "Python 3 not found. Downloading and installing Python 3.9.8..."
        $pythonUrl = 'https://www.python.org/ftp/python/3.9.8/python-3.9.8-amd64.exe'
        $tmpPython = Join-Path -Path $env:TEMP -ChildPath 'python-3.9.8-amd64.exe'
        try {
            Invoke-WebRequest -Uri $pythonUrl -OutFile $tmpPython -UseBasicParsing
            Write-Host "Downloaded Python installer to $tmpPython"
            $arguments = '/quiet','InstallAllUsers=1','PrependPath=1'
            Write-Host "Running Python installer (may prompt for elevation)..."
            Start-Process -FilePath $tmpPython -ArgumentList $arguments -Wait -Verb runAs
            Remove-Item $tmpPython -Force
            Write-Host "Python installation step complete."
        } catch {
            Write-Host "Failed to download or install Python: $_"
            Write-Host "You may need to install Python manually from $pythonUrl"
        }
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
        $desktopLnk = Join-Path -Path $env:USERPROFILE -ChildPath 'Desktop\Fuzzy Macro (windowsTest).lnk'
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

    Write-Host "Installation (windowsTest) complete. Open the Desktop shortcut or run run_macro.bat to launch the macro."
    exit 0
}
catch {
    Write-Error "Installer failed: $_"
    exit 1
}
