<div align="center">

<img src="Resources/AppIcon.png" width="128" alt="">

# SpaceMap

**See what's eating your Mac's disk, as one big zoomable map.**

[![Build](https://github.com/renkagod/spacemap/actions/workflows/build.yml/badge.svg)](https://github.com/renkagod/spacemap/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/renkagod/spacemap)](https://github.com/renkagod/spacemap/releases/latest)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[**Download**](https://github.com/renkagod/spacemap/releases/latest/download/SpaceMap-macOS.zip) · Apple Silicon & Intel · 1 MB

**English** · [Русский](#русский)

</div>

<img src="docs/screenshots/map.png" alt="Treemap of a home folder: movies, virtual machines, photos and downloads as large blocks">

The bigger the rectangle, the more space a file or folder takes. Folders nest inside each other
with their names and sizes, and color tells the file type. The map fills in live while the scan
runs, so there's no waiting for it to finish.

> The interface is in Russian for now.

## Features

- Folders are framed boxes and files are tiles; entries too small to draw are merged into an
  "N more" block.
- The scan runs on all cores (`readdir` + `lstat`). Sizes match `du`: allocated blocks, hard links
  counted once, symlinks and other volumes skipped.
- Double-click or pinch to zoom into a folder; Esc, ⌘↑, the mouse back button or a swipe goes back
  up, with an animated transition.
- The sidebar lists the current folder's contents, its largest files and a breakdown by file type.
- Click "Video" in the legend or the Types tab and everything else on the map dims.
- Right-click to open a file, reveal it in Finder, copy its path, rescan a folder or move it to the
  Trash.
- Sizes can be shown as space used on disk or as the sum of file lengths, the way Finder counts.
- Apps, the Photos library, Logic projects and other packages show as single blocks, like in Finder.
- Drop a folder onto the window or the Dock icon to scan it.

<table>
  <tr>
    <td><img src="docs/screenshots/types.png" alt="Types tab with videos highlighted on the map"></td>
    <td><img src="docs/screenshots/largest.png" alt="Largest files in the folder"></td>
  </tr>
  <tr>
    <td align="center">Breakdown by type, videos highlighted</td>
    <td align="center">Largest files</td>
  </tr>
</table>

## Install

1. Download [`SpaceMap-macOS.zip`](https://github.com/renkagod/spacemap/releases/latest/download/SpaceMap-macOS.zip)
   from [Releases](https://github.com/renkagod/spacemap/releases), unzip it and drag `SpaceMap.app`
   into Applications.
2. The app is not signed with an Apple Developer certificate, so macOS blocks the first launch.
   Open System Settings → Privacy & Security and click "Open Anyway". Or run in Terminal:

   ```bash
   xattr -cr /Applications/SpaceMap.app
   ```

3. To see the whole disk, including Mail, Messages and system folders, give SpaceMap Full Disk
   Access in the same settings pane. Without it the app still works and marks those folders as
   inaccessible.

Requires macOS 13 Ventura or later.

## Build from source

You need Swift 5.9+: Xcode or the Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/renkagod/spacemap.git
cd spacemap
bash scripts/build-app.sh
open build/SpaceMap.app
```

With full Xcode you get a universal arm64 + x86_64 binary; with the Command Line Tools alone, a
build for your Mac. `build/SpaceMap-macOS.zip`, the same archive as in the release, appears next
to it.

Tests: `swift test`.

## How it works

| Where | What |
|---|---|
| [`Sources/SpaceMapCore/DiskScanner.swift`](Sources/SpaceMapCore/DiskScanner.swift) | Multithreaded walk; the tree grows under a single lock and the UI reads it live |
| [`Sources/SpaceMapCore/Treemap.swift`](Sources/SpaceMapCore/Treemap.swift) | Squarified treemap (Bruls, Huizing, van Wijk) with nested folders and merging of small entries |
| [`Sources/SpaceMap/TreemapRenderer.swift`](Sources/SpaceMap/TreemapRenderer.swift) | Draws into a bitmap with Core Graphics and Core Text on a background thread |
| [`Sources/SpaceMap/TreemapView.swift`](Sources/SpaceMap/TreemapView.swift) | NSView: hover, clicks, menus, gestures and the zoom animation |
| [`Sources/SpaceMap/*View.swift`](Sources/SpaceMap) | SwiftUI interface |

No dependencies, only system frameworks.

A release is `git tag v1.2.3 && git push origin v1.2.3`: CI runs the tests, builds the app and
attaches the zip to the release.

## Contributing

Bugs and ideas go to [issues](https://github.com/renkagod/spacemap/issues). Pull requests are
welcome; make sure `swift test` and `bash scripts/build-app.sh` pass first.

## License

[MIT](LICENSE)

---

## Русский

**Посмотри, что съело место на диске Mac: одна большая карта, по которой можно ходить.**

[**Скачать**](https://github.com/renkagod/spacemap/releases/latest/download/SpaceMap-macOS.zip) · Apple Silicon и Intel · 1 МБ

Чем больше прямоугольник, тем больше места занимает файл или папка. Папки вложены друг в друга
с заголовками и размерами, цвет показывает тип файлов. Карта строится прямо во время
сканирования, ждать конца не нужно.

### Возможности

- Папки нарисованы рамками, файлы плитками, а то, что слишком мелко для карты, собрано в блок «ещё N».
- Сканирование идёт на всех ядрах (`readdir` + `lstat`). Размеры считаются как у `du`: занятые
  блоки, жёсткие ссылки один раз, симлинки и другие диски не учитываются.
- Двойной клик или щипок открывает папку; Esc, ⌘↑, боковая кнопка мыши или свайп возвращают
  наверх, с анимацией.
- В боковой панели содержимое текущей папки, самые крупные файлы в ней и разбивка по типам.
- Клик по «Видео» в легенде или во вкладке «Типы» гасит на карте всё остальное.
- По правому клику можно открыть файл, показать в Finder, скопировать путь, пересканировать
  папку или переместить в Корзину.
- Размер считается либо как занятое на диске место, либо как сумма длин файлов, как в Finder.
- Приложения, медиатека «Фото», проекты Logic и другие пакеты показаны одним блоком, как в Finder.
- Папку можно перетащить в окно или на иконку в Dock.

### Установка

1. Скачай [`SpaceMap-macOS.zip`](https://github.com/renkagod/spacemap/releases/latest/download/SpaceMap-macOS.zip)
   со страницы [релизов](https://github.com/renkagod/spacemap/releases), распакуй и перетащи
   `SpaceMap.app` в «Программы».
2. Приложение не подписано сертификатом Apple, поэтому при первом запуске macOS его заблокирует.
   Открой Системные настройки → Конфиденциальность и безопасность и нажми «Всё равно открыть».
   Или выполни в Терминале:

   ```bash
   xattr -cr /Applications/SpaceMap.app
   ```

3. Чтобы видеть весь диск, включая почту, «Сообщения» и системные папки, дай SpaceMap
   «Полный доступ к диску» в тех же настройках. Без него приложение тоже работает, просто
   покажет такие папки недоступными.

Нужна macOS 13 Ventura или новее.

### Сборка из исходников

Нужен Swift 5.9+: Xcode или Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/renkagod/spacemap.git
cd spacemap
bash scripts/build-app.sh
open build/SpaceMap.app
```

С полным Xcode получится универсальный бинарник arm64 + x86_64, с одними Command Line Tools
сборка будет только под твой Mac. Рядом появится `build/SpaceMap-macOS.zip`, такой же, как в релизе.

Тесты: `swift test`. Устройство кода описано в [английской части](#how-it-works).

### Участие

Баги и идеи пиши в [issues](https://github.com/renkagod/spacemap/issues). Пулл-реквесты
приветствуются: перед отправкой проверь, что проходят `swift test` и `bash scripts/build-app.sh`.

### Лицензия

[MIT](LICENSE)
