# SendToImageResizer

A lightweight Windows tool for resizing and compressing images from the **Send to** context menu.

No administrator rights, background service or shell extension required. ImageMagick is bundled, so the tool also works offline after installation.

## Installation

Download and run **Install-Latest.cmd** from the [latest release](https://github.com/Hypano/SendToImageResizer/releases/latest).

Alternatively, download and extract `SendToImageResizer.zip`, then run `Install.cmd`.

The application is installed for the current user in `%LOCALAPPDATA%\SendToImageResizer`. Existing custom presets are kept when updating.

## Usage

1. Select one or more image files, or one folder containing images.
2. Right-click the selection. If needed, choose **Show more options**.
3. Choose **Send to → Image Resizer**.
4. Select a preset.

When files are selected, only those files are processed. When a folder is selected, all supported images in that folder are processed. Subfolders can be included through the preset settings.

You can also start **Image Resizer** from the Start menu and select a folder there.

### Large file selections

Windows limits the complete command line to 32,767 characters. The practical number of individually selectable files therefore depends on the combined length of their paths.

If Windows displays **The filename or extension is too long**, select the common parent folder instead.

## Presets

Press **C - Configure presets** in the application to create, edit, delete or reset presets.

Presets support:

- Compression without changing the resolution
- Resizing by percentage or maximum edge length
- Creating a copy or replacing the original
- Optional subfolder processing, automatic orientation and timestamp preservation
- JPG, JPEG, PNG and WebP files

When using a `replace` preset, the new image is created and validated first. The original file is then moved to the Windows Recycle Bin as a recoverable backup.

## Command-line use

The menu can be skipped by passing an exact preset name from PowerShell.

Process a folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SendToImageResizer.ps1 `
  -PresetName "Resize to 1920 px" `
  -MainFolder "C:\Images"
```

Process only specific files:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SendToImageResizer.ps1 `
  -PresetName "Resize to 1920 px" `
  "C:\Images\First image.jpg" `
  "C:\Images\Second image.png"
```

A replace preset runs immediately without confirmation in this mode.

## Uninstall

Use **Start menu → SendToImageResizer → Uninstall Image Resizer**, or run `Uninstall.cmd` from the installation directory.

## Maintainer information

Development, validation and release instructions are documented in [MAINTAINING.md](https://github.com/Hypano/SendToImageResizer/blob/main/MAINTAINING.md).

## License

SendToImageResizer is licensed under the MIT License. Bundled third-party components retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
