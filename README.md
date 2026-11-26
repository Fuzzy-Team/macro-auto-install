# How to install Fuzzy Macro

## **WAIT**, before proceeding please note that this is not how to install the macro, please refer to the documentation below:
[https://www.fuzzymacro.com/docs](https://www.fuzzymacro.com/docs)

This installer works with:

- Intel Macs on macOS 10.12 or later
- Apple Silicon Macs (M1 and newer) on macOS 13 or later

The installer downloads the newest [GitHub release](https://github.com/Fuzzy-Team/Fuzzy-Macro/releases/latest), installs Python and the libraries with that release's own `install_dependencies.command`, and adds a shortcut to your Desktop. Running it again reinstalls the macro and keeps your profiles, patterns and data. The old folder goes to the Trash.

## Scripts

| Script | What it does |
| --- | --- |
| `fuzzy_installer.command` | Fresh install, or reinstall of the latest release |
| `migrate_from_existance.command` | Move an Existance Macro folder to the latest release, or reinstall over an existing Fuzzy Macro folder, keeping profiles, patterns and data |
| `update_from_commit.command` | Update or roll back to a specific commit or tester ID, keeping profiles, patterns and data |

## Test builds (macOS)

Latest beta (the newest release, including pre-releases):

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Fuzzy-Team/macro-auto-install/refs/heads/main/fuzzy_installer.command)" _ beta
```

Latest commit on `main`:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Fuzzy-Team/macro-auto-install/refs/heads/main/fuzzy_installer.command)" _ main
```

The migrate script takes the same argument, so a test build over an Existance or Fuzzy Macro folder is:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Fuzzy-Team/macro-auto-install/refs/heads/main/migrate_from_existance.command)" _ main
```

Installer Source Code: https://github.com/Fuzzy-Team/macro-auto-install/

Macro Source Code: https://github.com/Fuzzy-Team/Fuzzy-Macro/tree/main
