# How to install Fuzzy Macro

## **WAIT**, before proceeding please note that this is not how to install the macro, please refer to the documentation below:
[https://www.fuzzymacro.com/docs](https://www.fuzzymacro.com/docs)

This installer works with:

- Macos 10.12+
- All M1-4 chips
- All Macs with an intel chip and Macos 10.12+


## Test builds (macOS)

Latest beta:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Fuzzy-Team/macro-auto-install/refs/heads/main/fuzzy_installer.command)" _ beta
```

Latest commit on `main`:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Fuzzy-Team/macro-auto-install/refs/heads/main/fuzzy_installer.command)" _ main
```

Installer Source Code: https://github.com/Fuzzy-Team/macro-auto-install/
 - Installer then runs `install_dependencies.command` from the downloaded release, so the dependencies always match the installed version

Macro Source Code: https://github.com/Fuzzy-Team/Fuzzy-Macro/tree/main
