# Maintaining SendToImageResizer

## Project structure

- `SendToImageResizer.ps1` contains the menu, preset editor and image-processing logic.
- `presets.json` contains the user-facing defaults; `presets.default.json` is the reset source.
- `Install.ps1` and `Uninstall.ps1` manage the per-user installation and shortcuts.
- `Test-Project.ps1` validates the source tree and configuration.
- `Test-Integration.ps1` runs the end-to-end image tests.
- `Build-Release.ps1` creates and verifies `SendToImageResizer.zip`.
- `ImageMagick/` contains the pinned portable runtime and its license and configuration files.

## Validation

The **Validate** GitHub Actions workflow runs automatically for pull requests and pushes to `main`. It validates the project, tests image processing, builds the release ZIP and tests installation and uninstallation on Windows.

The same main checks can be started locally on Windows:

```powershell
.\Test-Project.ps1 -RequireImageMagick
.\Test-Integration.ps1
.\Build-Release.ps1 -OutputDirectory "$env:TEMP\SendToImageResizer-release"
```

## Creating a release

1. Merge the intended release state into `main` and ensure the **Validate** workflow passes.
2. Open **Actions → Create Release → Run workflow**.
3. Enter the new semantic version without a leading `v`, for example `1.0.2`.

The entered version is used for the Git tag and release title. The workflow publishes these fixed asset names:

- `SendToImageResizer.zip`
- `Install-Latest.cmd`

`Install-Latest.cmd` depends on the fixed ZIP name to download the newest release.

## Updating ImageMagick

The bundled runtime is intentionally pinned and must be updated manually.

1. Replace the contents of `ImageMagick/` with the intended portable Q8 x64 build.
2. Keep `magick.exe`, its configuration resources, `LICENSE.txt` and `NOTICE.txt`.
3. Do not bundle the separate legacy utility executables; all operations use `magick.exe`.
4. Update `ImageMagick/VERSION.txt` and `THIRD_PARTY_NOTICES.md`.
5. Run the full validation workflow before creating a release.

## Installation behavior

The release package installs into `%LOCALAPPDATA%\SendToImageResizer` without administrator rights. Existing `presets.json` changes are retained during updates; updated factory defaults are copied separately and only applied when the user resets the presets.
