<div align="center">
  <img src="Resources/Rowvi.png" alt="Rowvi app icon" width="128">
  <h1>Rowvi</h1>
  <p><strong>Desktop and window layout profiles for macOS</strong></p>
  <p>Create layouts for work, study, or personal projects and switch between profiles from the menu bar.</p>
  <p>
    <a href="#installation">Installation</a> ·
    <a href="#quick-start">Quick Start</a> ·
    <a href="#building-from-source">Build</a> ·
    <a href="LICENSE">MIT</a>
  </p>
  <img src="docs/images/rowvi-window.png" alt="Translucent Rowvi window with desktop tiles over a nighttime cityscape" width="900">
</div>

## Features

- **Profiles.** Give each profile its own set of desktops, apps, and window modes. You can create, duplicate, rename, and delete profiles.
- **Desktops.** Add desktops and drag their tiles to reorder them.
- **Window modes.** Keep a window at its normal size or expand it to fill the desktop. When a desktop contains a single window, that window can use a dedicated full-screen Space.
- **Menu bar and launch options.** Switch profiles from the menu bar, hide the Dock icon, and choose which profile Rowvi applies at launch.

## Installation

**Requires macOS 27 or later.**

1. Download `Rowvi-v*.dmg` from the latest release if available, or download `Rowvi-v*.zip`. You can also [build from source](#building-from-source). [GitHub Releases](https://github.com/ditarget/rowvi/releases)
2. Open the DMG and drag `Rowvi.app` into Applications. If you downloaded the ZIP, extract it and move `Rowvi.app` to `/Applications`.
3. Open Rowvi from Applications. In Rowvi, go to **Settings (Настройки) → Permissions (Разрешения)** and grant **Accessibility (Универсальный доступ)** access so Rowvi can move and resize windows.

Builds from GitHub Releases support automatic updates through Sparkle. To check manually, choose **Check for Updates… (Проверить обновления…)** from the Rowvi menu or under **Settings → App (Приложение)**.

Rowvi uses a self-signed certificate. If macOS blocks the downloaded app on first launch, try opening it, then go to **System Settings → Privacy & Security → Open Anyway**. Download the installer from the official repository. [Apple instructions](https://support.apple.com/en-us/102445)

## Quick Start

1. Open **Manage Profiles (Управление профилями)** next to the profile picker and create a profile.
2. Click **+** to add a desktop tile. Click the tile to choose its apps and window modes.
3. Drag the tiles into the order you want and click **Apply (Применить)**.

Selecting a profile in the Rowvi window or menu bar applies its layout immediately. Click **-** to remove a tile from the layout.

In **Manage Profiles**, you can enable **Remove extra desktops and apps (Убирать лишние рабочие столы и приложения)** for the selected profile. Cleanup is off by default. After applying the layout successfully, Rowvi quits apps outside the profile if all their windows are on desktops scheduled for removal. Rowvi then removes extra regular desktops from the primary display, leaving at least one. macOS moves any remaining open windows to another desktop. To use cleanup with multiple displays, enable **Displays have separate Spaces** in Mission Control settings.

Under **Settings → App**, you can configure Rowvi to launch when you log in to macOS. If macOS requires approval, Rowvi prompts you to open Login Items settings. The **Profile at Rowvi launch (Профиль при запуске Rowvi)** setting applies whether you open Rowvi manually or it starts at login. By default, Rowvi leaves windows where they are.

> [!TIP]
> Rowvi applies Space layouts on the primary display. To preserve the desktop order, disable **Automatically rearrange Spaces based on most recent use** in Mission Control settings.

## Building from Source

You need the Xcode tools and the macOS 27 SDK or later. On the first build, the Makefile downloads Sparkle and verifies the archive checksum.

```sh
git clone https://github.com/ditarget/rowvi.git
cd rowvi
make check
make open
```

`make check` verifies layout logic and `Info.plist`. `make open` builds and opens `.build/Rowvi.app`. For consistent code signing across local builds, install [rcodesign](https://github.com/indygreg/apple-platform-rs/releases/tag/apple-codesign%2F0.29.0) and run `make signing-key` once. Subsequent builds will use the same certificate. If the signing identity changes, macOS may ask you to grant Accessibility access again.

`make release` configures the Sparkle update URL and packages the files for GitHub Releases. [Release instructions](docs/releasing.md)

## Profiles and Mission Control

Rowvi stores profiles and the last selection in `~/Library/Application Support/WindowLayout/profiles.json`. When upgrading, Rowvi migrates the existing layout from `layout.json` into the **Main (Основной)** profile.

Rowvi manages Spaces through Mission Control's accessibility interface and undocumented macOS interfaces. After moving a window, Rowvi verifies its actual position and reports an error if macOS does not confirm the move.

## License

Rowvi is released under the [MIT license](LICENSE). Sparkle, the update framework, is distributed under its own license. [Sparkle license](https://github.com/sparkle-project/Sparkle/blob/2.10.1/LICENSE)
