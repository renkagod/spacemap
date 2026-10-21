"""Builds a believable home folder out of sparse files, for the README screenshots.

Files get their logical size via truncate() and take almost no disk space, so screenshots are taken
in the "Длина файлов" (logical size) mode.

    python3 scripts/make_demo_tree.py ~/SpaceMapDemo
"""
import random
import sys
from pathlib import Path

GB = 1_000_000_000
MB = 1_000_000
KB = 1_000

rng = random.Random(42)


def make(path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as handle:
        handle.truncate(max(1, int(size)))


def spread(low: float, high: float) -> float:
    return rng.uniform(low, high)


def build(root: Path) -> None:
    movies = root / "Фильмы"
    for name, size in [("Дюна. Часть вторая (2024) 2160p.mkv", 58 * GB), ("Интерстеллар 2160p.mkv", 64 * GB),
                       ("Бегущий по лезвию 2049.mkv", 41 * GB), ("Оппенгеймер 1080p.mp4", 14 * GB),
                       ("Мастер и Маргарита.mkv", 22 * GB), ("Брат 2.avi", 1.4 * GB)]:
        make(movies / name, size)
    for season in range(1, 4):
        for episode in range(1, 11):
            make(movies / "Сериалы" / "Чернобыль" / f"Сезон {season}" / f"S0{season}E{episode:02}.mkv",
                 spread(2.1, 3.4) * GB)
    for episode in range(1, 9):
        make(movies / "Сериалы" / "Слово пацана" / f"Серия {episode}.mp4", spread(1.2, 1.9) * GB)

    photos = root / "Изображения"
    library = photos / "Photos Library.photoslibrary"
    for index in range(1800):
        make(library / "originals" / f"{index % 16:X}" / f"IMG_{index:05}.HEIC", spread(1.8, 4.5) * MB)
    for index in range(220):
        make(library / "originals" / f"{index % 16:X}" / f"VID_{index:04}.MOV", spread(40, 600) * MB)
    make(library / "database" / "Photos.sqlite", 1.9 * GB)
    for index in range(260):
        make(photos / "Отпуск в Грузии 2025" / f"DSC{index:05}.ARW", spread(24, 38) * MB)
    for index in range(140):
        make(photos / "Отпуск в Грузии 2025" / "jpeg" / f"DSC{index:05}.jpg", spread(6, 14) * MB)
    for index in range(90):
        make(photos / "Скриншоты" / f"Снимок экрана {index}.png", spread(0.6, 4) * MB)
    make(photos / "Обои" / "wallpaper-6k.heic", 38 * MB)

    music = root / "Музыка"
    for artist, albums in [("Кино", 6), ("Radiohead", 5), ("Hans Zimmer", 4), ("Земфира", 4), ("Daft Punk", 3)]:
        for album in range(albums):
            for track in range(12):
                make(music / "Медиатека" / artist / f"Альбом {album + 1}" / f"{track + 1:02} трек.flac",
                     spread(25, 60) * MB)
    for project in ["Новый трек", "Демо 3", "Ремикс"]:
        project_dir = music / "Logic" / f"{project}.logicx"
        for take in range(30):
            make(project_dir / "Media" / "Audio Files" / f"Take {take}.wav", spread(30, 140) * MB)
    for index in range(40):
        make(music / "Сэмплы" / f"kit_{index}.zip", spread(80, 400) * MB)

    downloads = root / "Загрузки"
    for name, size in [("Xcode_16.4.xip", 3.3 * GB), ("ubuntu-24.04-desktop-amd64.iso", 6.1 * GB),
                       ("Windows11_ARM.iso", 5.4 * GB), ("DaVinci_Resolve_19.dmg", 3.4 * GB),
                       ("Steam.dmg", 0.2 * GB), ("Telegram.dmg", 0.1 * GB), ("Курс по Swift.zip", 9.8 * GB),
                       ("бэкап телефона.zip", 18 * GB), ("Docker.dmg", 1.6 * GB)]:
        make(downloads / name, size)
    for index in range(70):
        make(downloads / f"document ({index}).pdf", spread(0.2, 12) * MB)
    for index in range(25):
        make(downloads / f"IMG_{4000 + index}.jpg", spread(2, 6) * MB)

    documents = root / "Документы"
    for index in range(120):
        make(documents / "Учёба" / f"Лекция {index + 1}.pdf", spread(1, 40) * MB)
    for index in range(30):
        make(documents / "Работа" / f"Отчёт {index + 1}.docx", spread(0.1, 3) * MB)
        make(documents / "Работа" / f"Таблица {index + 1}.xlsx", spread(0.1, 8) * MB)
    for index in range(8):
        make(documents / "Презентации" / f"Питч {index + 1}.key", spread(60, 900) * MB)
    make(documents / "Книги" / "Совершенный код.epub", 18 * MB)
    for index in range(60):
        make(documents / "Книги" / f"книга_{index}.pdf", spread(2, 60) * MB)

    projects = root / "Developer"
    for project in ["spacemap", "telegram-bot", "site", "ml-experiments"]:
        base = projects / project
        for index in range(60):
            make(base / "src" / f"module_{index}.{rng.choice(['swift', 'py', 'ts', 'go'])}", spread(2, 40) * KB)
        for index in range(900):
            make(base / "node_modules" / f"pkg{index % 120}" / f"index_{index}.js", spread(1, 200) * KB)
        make(base / ".git" / "objects" / "pack" / "pack-1.pack", spread(40, 900) * MB)
        for index in range(30):
            make(base / "build" / f"obj_{index}.o", spread(0.5, 30) * MB)
    make(projects / "ml-experiments" / "datasets" / "imagenet-subset.tar", 34 * GB)
    make(projects / "ml-experiments" / "checkpoints" / "model-7b.safetensors", 14 * GB)
    for index in range(4):
        make(projects / "VirtualMachines" / f"Ubuntu {index}.utm" / "Data" / "disk.qcow2", spread(12, 40) * GB)

    library = root / "Library"
    for app in ["com.apple.Safari", "com.google.Chrome", "com.spotify.client", "ru.keepcoder.Telegram",
                "com.microsoft.VSCode", "com.apple.dt.Xcode"]:
        for index in range(150):
            make(library / "Caches" / app / f"cache_{index:04}", spread(0.05, 30) * MB)
    for index in range(400):
        make(library / "Developer" / "Xcode" / "DerivedData" / f"Build-{index % 8}" / f"obj_{index}.o",
             spread(1, 60) * MB)
    for index in range(12):
        make(library / "Developer" / "CoreSimulator" / "Devices" / f"device-{index}" / "data.img",
             spread(1.5, 6) * GB)
    make(library / "Application Support" / "MobileSync" / "Backup" / "iPhone" / "Manifest.db", 0.4 * GB)
    for index in range(600):
        make(library / "Application Support" / "MobileSync" / "Backup" / "iPhone" / f"{index:02x}"[-2:] / f"blob{index}",
             spread(5, 90) * MB)
    for index in range(80):
        make(library / "Logs" / f"diagnostic_{index}.log", spread(0.1, 25) * MB)
    make(library / "Containers" / "com.apple.mail" / "Data" / "Library" / "Mail" / "V10" / "Envelope Index",
         2.3 * GB)


if __name__ == "__main__":
    if sys.platform != "darwin":
        # Only APFS keeps truncate()d files sparse; elsewhere this would write ~500 GB of zeros.
        sys.exit("run this on macOS: other file systems do not create sparse files")
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "SpaceMapDemo").expanduser()
    build(target)
    print(f"demo tree in {target}")
