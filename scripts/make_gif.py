"""Turns the frames recorded by `SpaceMap --record <folder>` into the README animation.

All frames share one palette, so flat areas don't shimmer from frame to frame, and repeated frames
are merged into one that stays on screen longer.

    python3 scripts/make_gif.py <frames folder> docs/screenshots/en/demo.gif
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops


def main() -> None:
    folder, output = Path(sys.argv[1]), Path(sys.argv[2])
    frames: list[Image.Image] = []
    durations: list[int] = []
    for line in (folder / "frames.txt").read_text().splitlines():
        name, duration = line.split()
        path = folder / name
        if not path.exists():
            continue
        frame = Image.open(path).convert("RGB")
        if frames and frame.size == frames[-1].size and not ImageChops.difference(frame, frames[-1]).getbbox():
            durations[-1] += int(duration)
            continue
        frames.append(frame)
        durations.append(int(duration))
    if not frames:
        sys.exit(f"no frames in {folder}")

    # The palette comes from a strip of evenly spaced frames, so it covers every view of the walk.
    samples = frames[:: max(1, len(frames) // 8)]
    width, height = frames[0].size
    strip = Image.new("RGB", (width, height * len(samples)))
    for index, sample in enumerate(samples):
        strip.paste(sample.resize((width, height)), (0, height * index))
    palette = strip.quantize(colors=255, method=Image.Quantize.MEDIANCUT)

    indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    output.parent.mkdir(parents=True, exist_ok=True)
    indexed[0].save(output, save_all=True, append_images=indexed[1:], duration=durations, loop=0,
                    optimize=False, disposal=1)
    print(f"{output}: {len(indexed)} frames, {sum(durations) / 1000:.1f} s, "
          f"{output.stat().st_size / 1_000_000:.1f} MB")


if __name__ == "__main__":
    main()
