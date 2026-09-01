# SendToImageResizer

Lightweight Windows image resizing and compression using the **Send to** context menu and a bundled, pinned ImageMagick version.

No background service, no shell extension, no administrator rights and no updater.

## How it works

1. Right-click the main folder that contains your images.
2. Choose **Send to → Image Resizer**.
3. Select a preset from the console menu.

You can also start **Image Resizer** from the Start menu and select a main folder there.

The application processes the folder itself instead of passing hundreds of individual file paths through the Windows command line. This avoids the command-line length limit that can break large selections. Individual files are accepted for convenience, but selecting their common parent folder is recommended.

## Features

- One stable SendTo shortcut
- Interactive console menu
- Presets are loaded fresh before every operation
- Built-in preset editor: create, edit, delete or reset presets
- Resize modes: compression only, percentage, or maximum edge in pixels
- Never upscales images
- Create a copy or safely replace the original
- Optional recursive processing of subfolders
- Optional automatic orientation
- Optional timestamp preservation
- JPG, JPEG, PNG and WebP support by default
- Live progress and a result summary
- Safe replacement workflow with the original moved to the Recycle Bin only after the new file was created successfully

## Installation

Download **Install-Latest.cmd** from the [latest GitHub release](https://github.com/Hypano/SendToImageResizer/releases/latest) and run it.

The download installer retrieves the matching `SendToImageResizer.zip`, extracts it into a randomly named directory below `%TEMP%`, installs the application and removes the ZIP and extracted temporary files afterward. Only the installed application remains in `%LOCALAPPDATA%`.

Alternatively, download and extract `SendToImageResizer.zip` yourself, then run:

```text
Install.cmd
```

The installer copies the application to:

```text
%LOCALAPPDATA%\SendToImageResizer
```

and creates:

- **Send to → Image Resizer**
- **Start menu → SendToImageResizer → Image Resizer**
- **Start menu → SendToImageResizer → Uninstall Image Resizer**

No administrator rights are required.

When reinstalling or updating, locally edited presets are retained. Updated factory defaults are installed separately and are only applied when you explicitly reset the presets.

## Creating a release

Releases are created manually:

1. Update `VERSION.txt` and merge the intended release state into `main`.
2. Open **Actions → Create Release → Run workflow**.
3. Enter the exact version from `VERSION.txt`, for example `1.0.1`.

The workflow validates the version, runs the end-to-end test, builds and verifies `SendToImageResizer.zip`, and publishes it together with `Install-Latest.cmd`. The fixed ZIP filename lets the installer always retrieve the latest published version.

## Presets

Presets are stored in `presets.json`. Use **C - Configure presets** in the application to manage them without editing JSON manually. The editor also offers an option to open the JSON in Notepad.

Example:

```json
{
  "name": "Resize to 1920 px",
  "mode": "fit",
  "value": 1920,
  "quality": 80,
  "autoOrient": false,
  "operation": "copy",
  "copySuffix": "_1920px",
  "overwriteCopy": false,
  "recursive": false,
  "preserveTimestamps": true
}
```

Supported resize modes:

| Mode | Meaning |
|---|---|
| `none` | Keep the dimensions and only recompress the image |
| `percent` | Resize to `value` percent; values are limited to 1–100 |
| `fit` | Fit inside `value × value` pixels while retaining the aspect ratio |

Supported operations:

| Operation | Meaning |
|---|---|
| `copy` | Create a new file next to the original using `copySuffix` |
| `replace` | Replace the original using the safe backup workflow |

Preset values and names are read directly from `presets.json` whenever the menu is displayed. Changes therefore take effect immediately; no shortcut synchronization or reinstallation is needed.

### Optional non-interactive use

The same processing path can be called from scripts by using the exact preset name:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SendToImageResizer.ps1 `
  -PresetName "Resize to 1920 px" `
  -MainFolder "C:\Images"
```

Replace presets run directly because the operation is already explicit in the preset configuration. The safe backup workflow is used in both interactive and non-interactive mode.

## Safe replacement

For a `replace` preset, every image is processed as follows:

1. ImageMagick writes a temporary image next to the source file.
2. The result and exit code are validated.
3. The original is renamed to a temporary backup.
4. The processed image takes the original name.
5. Timestamps are restored when enabled.
6. The backup is moved to the Windows Recycle Bin.

If a step fails, the original is restored whenever possible and the failure is shown in the final summary.

## ImageMagick

The project is designed for the bundled **ImageMagick 7.1.2-21 portable Q8 x64** build. It deliberately does not download or update ImageMagick. This keeps image processing reproducible and allows the tool to work offline.

The complete `ImageMagick` directory must contain at least `magick.exe`, `LICENSE.txt` and `NOTICE.txt`. Installation stops with a clear error if the package is incomplete.

ImageMagick is distributed under the ImageMagick License. See `ImageMagick/LICENSE.txt`, `ImageMagick/NOTICE.txt` and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Uninstall

Use the Start menu uninstall shortcut or run:

```text
Uninstall.cmd
```

Uninstalling removes the SendTo shortcut, Start menu entries, installed application files and locally edited presets.

## Validate a package

Run the built-in validator from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Project.ps1
```

For a release package, require the complete bundled ImageMagick runtime:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Project.ps1 -RequireImageMagick
```

## License

SendToImageResizer is licensed under the MIT License. Bundled third-party components retain their own licenses.
