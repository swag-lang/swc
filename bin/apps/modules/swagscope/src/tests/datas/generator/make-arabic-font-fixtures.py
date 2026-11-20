#!/usr/bin/env python3
"""Rebuild the Swag Scope Arabic TTF and two-face TTC from Noto Sans Arabic."""

from pathlib import Path
import argparse
import shutil
import tempfile

from fontTools import subset
from fontTools.ttLib import TTCollection, TTFont


def subset_font(source: Path, style: str, output: Path) -> None:
    font = TTFont(source)
    font.recalcTimestamp = False
    options = subset.Options()
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
                        16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28,
                        29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40]
    options.name_legacy = True
    options.name_languages = [0x409]
    options.layout_features = ["*"]
    options.glyph_names = True
    sub = subset.Subsetter(options=options)
    # The fixture text's Arabic characters plus the full basic Arabic block let the map
    # show realistic language coverage while retaining all shaping glyph closure.
    chars = set("Swag Scope plain-text verification fixture ASCII punctuation UTF-8 text "
                "café naïve Ελληνικά 日本語 한국어 العربية and Tabs first second third "
                "A deliberately long logical line follows: 0123456789abcdefghijklmnopqrstuvwxyz"
                "ABCDEFGHIJKLMNOPQRSTUVWXYZ The plain-text verification marker is searchable.")
    codepoints = {ord(char) for char in chars} | set(range(0x0600, 0x0700))
    sub.populate(unicodes=codepoints)
    sub.subset(font)

    family = "Swag Scope Arabic Fixture"
    names = font["name"]
    for record in list(names.names):
        if record.nameID in (1, 16):
            value = family
        elif record.nameID in (2, 17):
            value = style
        elif record.nameID == 4:
            value = f"{family} {style}"
        elif record.nameID == 6:
            value = f"SwagScopeArabicFixture-{style}"
        elif record.nameID == 3:
            value = f"SwagScopeFixtureArabic-{style}-1"
        else:
            continue
        names.setName(value, record.nameID, record.platformID, record.platEncID,
                      record.langID)
    font["head"].created = 0
    font["head"].modified = 0
    font.save(output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--regular", type=Path, required=True,
                        help="path to licensed NotoSansArabic-Regular.ttf")
    parser.add_argument("--bold", type=Path, required=True,
                        help="path to licensed NotoSansArabic-Bold.ttf")
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="swagscope-arabic-") as temporary:
        temp = Path(temporary)
        regular_path = temp / "regular.ttf"
        bold_path = temp / "bold.ttf"
        subset_font(args.regular, "Regular", regular_path)
        subset_font(args.bold, "Bold", bold_path)
        shutil.copyfile(regular_path, args.output_dir / "viewer.arabic.ttf")

        collection = TTCollection()
        collection.fonts = [TTFont(regular_path, recalcTimestamp=False),
                            TTFont(bold_path, recalcTimestamp=False)]
        collection.save(args.output_dir / "viewer.arabic.ttc")


if __name__ == "__main__":
    main()
