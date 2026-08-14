# MediaPrep language resources

MediaPrep 0.11.54 ships 14 interface languages.

`mediaprep.en-US.json` is the authoritative master and fallback for the 0.11.54 release line. Its key set is frozen at schema 1, `LanguageFileVersion` 1.7.5, 739 keys.

All locale files must:

- use UTF-8 with BOM;
- keep exactly the same keys and key order as `en-US`;
- preserve every numbered format placeholder used by the corresponding master string;
- keep `Culture` and `LanguageCode` equal to the culture suffix in the filename;
- contain no empty user-facing translations.

Validate the package on Windows PowerShell 5.1 with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\App\Test-MediaPrepLanguages.ps1"
```

For the beta-11 master, the expected result is:

```text
Language validation OK: 14 language file(s), 739 keys, version 1.7.5.
```

Do not change the 0.11.54 en-US master without deliberately advancing the language-file version and synchronizing every locale.

