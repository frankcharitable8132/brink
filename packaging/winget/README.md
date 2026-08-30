# winget manifest

Manifests for [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs), package id `SemihTali.Brink`.
winget accepts unsigned `zip`/`portable` installers, so this works before the exe is code-signed.

Submit / update from Windows:

```powershell
winget install wingetcreate
wingetcreate update SemihTali.Brink -u https://github.com/semihtalii/brink/releases/download/v<VERSION>/Brink-Windows-x64.zip -v <VERSION> --submit
```

or copy the `manifests/` tree into a fork of winget-pkgs and open a PR. Validate first with `winget validate --manifest manifests/s/SemihTali/Brink/<VERSION>`.
Once merged: `winget install SemihTali.Brink`.
