# Expanded font decoder comparison on Linux

The expanded corpus has 41 files and 44 scenarios. It includes the 12 supplied files,
26 public fonts, and three WOFF1 files generated from the public inputs. Four scenarios
select different faces from the same CJK collection. The workload, source revisions, and
fixture hashes are available in the [benchmark directory](../../workloads/fontdecode/README.md).

Both Swag builds use `Face.loadFile` and render one glyph at 20 px. The baseline is
`bbb9380105`. Pillow 12.3.0 uses FreeType 2.14.3 and Basic layout for the one-character
workload. The results are medians of 11 interleaved batches on one Intel Xeon Platinum
8573C CPU with a warm file cache. Each batch opens 251 fresh faces per case, or 21 for
files at least 10 MB. The timed spans include opening, setting the size, and rendering.
[Raw batch timings and fixture hashes](font-decode-linux.json)

The published Swag build rejected all three WOFF1 files because their directory entries
are in tag order and their data blocks follow the source font order. The updated reader
checks padding and overlap in file order, then inflates each table directly into the
reconstructed SFNT buffer. It renders all three files faster than Pillow in this run.
[WOFF1 table directory and data order](https://www.w3.org/TR/WOFF/#DataFormat)

Swag is ahead in 36 of 44 scenarios. All eight remaining cases have lower medians than
published Swag. The six CJK scenarios remain 2.9 to 3.9 times as slow as Pillow. Their
16–25 MB files dominate the open phase. On the DejaVu fonts, ordered legacy kerning
stays packed and `post` names are read from validated spans. DejaVu Sans drops from
1.13 ms to 0.23 ms and DejaVu Serif from 0.55 ms to 0.14 ms, against 0.13 and 0.14 ms
in Pillow. Noto Sans Math and Noto Sans Symbols 2 move ahead of the reference.

Glyph indices, advances, bitmap dimensions, and CRC-64 matched on all 41 scenarios
accepted by both Swag builds. They also matched on the three WOFF1 files against the
published decoder with only the directory-order fix applied. In that separate
nine-batch check, the updated decoder saved 11% to 26% on the WOFF1 cases.

| Fixture | Face | Glyph | Published Swag (µs) | Updated Swag (µs) | Pillow (µs) |
| --- | ---: | --- | ---: | ---: | ---: |
| `Amiri-Regular.ttf` | 0 | `U+0639` | 234.82 | 99.30 | 1628.26 |
| `AtkinsonHyperlegibleNext.ttf` | 0 | `U+0051` | 68.92 | 50.76 | 510.97 |
| `DejaVuSans.ttf` | 0 | `U+0041` | 1126.32 | 233.75 | 133.57 |
| `DejaVuSerif.ttf` | 0 | `U+0067` | 547.88 | 139.28 | 137.43 |
| `Inter-Variable.ttf` | 0 | `U+0057` | 348.55 | 187.45 | 1979.58 |
| `Lato-Public.ttf` | 0 | `U+0041` | 153.72 | 88.78 | 277.81 |
| `NimbusMonoPS-Regular.otf` | 0 | `U+0057` | 56.23 | 59.68 | 118.11 |
| `NimbusSans-Regular.otf` | 0 | `U+0041` | 54.84 | 53.34 | 149.61 |
| `NotoEmoji.ttf` | 0 | `U+1F642` | 436.61 | 330.72 | 463.62 |
| `NotoSans-Regular.ttf` | 0 | `U+0041` | 278.98 | 103.48 | 1389.28 |
| `NotoSansArabic.ttf` | 0 | `U+0639` | 269.74 | 153.12 | 892.10 |
| `NotoSansArmenian.ttf` | 0 | `U+0531` | 66.80 | 56.32 | 637.70 |
| `NotoSansCJK-Regular.ttc` | 0 | `U+65E5` | 2982.07 | 2836.00 | 910.87 |
| `NotoSansCJK-Regular.ttc` | 1 | `U+D55C` | 2986.09 | 2887.37 | 972.91 |
| `NotoSansCJK-Regular.ttc` | 2 | `U+4E2D` | 3103.61 | 3087.92 | 904.50 |
| `NotoSansCJK-Regular.ttc` | 7 | `U+FF21` | 3251.97 | 2933.77 | 963.02 |
| `NotoSansCJKjp-Regular.otf` | 0 | `U+65E5` | 3008.08 | 2667.95 | 918.00 |
| `NotoSansDevanagari.ttf` | 0 | `U+0915` | 170.32 | 109.13 | 29201.42 |
| `NotoSansEthiopic.ttf` | 0 | `U+1200` | 221.09 | 190.75 | 1066.08 |
| `NotoSansHebrew.ttf` | 0 | `U+05D0` | 63.91 | 48.51 | 457.53 |
| `NotoSansMath.ttf` | 0 | `U+222B` | 588.43 | 256.92 | 360.36 |
| `NotoSansSymbols2.ttf` | 0 | `U+2606` | 405.66 | 249.72 | 300.56 |
| `NotoSerifCJKjp-Regular.otf` | 0 | `U+672C` | 3946.36 | 3802.75 | 973.06 |
| `NotoSerifThai.ttf` | 0 | `U+0E01` | 72.85 | 57.84 | 505.13 |
| `NotoSerifTibetan.ttf` | 0 | `U+0F40` | 452.43 | 331.70 | 1665.03 |
| `OpenSans-Public.ttf` | 0 | `U+0041` | 132.32 | 83.77 | 206.09 |
| `Roboto-Variable.ttf` | 0 | `U+0067` | 102.54 | 80.00 | 218.73 |
| `SourceSans3-Regular.otf` | 0 | `U+0041` | 145.13 | 151.59 | 175.15 |
| `SourceSerif4-Regular.otf` | 0 | `U+0067` | 110.50 | 111.81 | 196.07 |
| `DejaVuSans.woff` | 0 | `U+0041` | Rejected | 4331.98 | 5399.47 |
| `fontawesome-webfont.otf` | 0 | `U+F000` | 74.60 | 74.91 | 105.40 |
| `fontawesome-webfont.ttf` | 0 | `U+F000` | 85.09 | 48.29 | 214.60 |
| `Inter-Variable.woff` | 0 | `U+0057` | Rejected | 5267.90 | 8102.07 |
| `Lato-Regular.otf` | 0 | `U+0041` | 45.10 | 43.97 | 85.92 |
| `Lato-Regular.ttf` | 0 | `U+0041` | 42.74 | 36.67 | 184.62 |
| `NotoSansShavian-Regular.otf` | 0 | `U+10450` | 30.04 | 28.46 | 63.54 |
| `NotoSansShavian-Regular.ttf` | 0 | `U+10450` | 29.59 | 27.53 | 217.25 |
| `OpenSans-Regular.otf` | 0 | `U+0041` | 77.25 | 74.96 | 142.38 |
| `OpenSans-Regular.ttf` | 0 | `U+0041` | 85.23 | 45.15 | 96.63 |
| `slick.otf` | 0 | `U+0061` | 37.33 | 35.24 | 113.54 |
| `slick.ttf` | 0 | `U+0061` | 28.93 | 29.73 | 152.72 |
| `SourceCodePro-Regular.otf` | 0 | `U+0041` | 46.09 | 46.37 | 95.85 |
| `SourceCodePro-Regular.ttf` | 0 | `U+0041` | 59.28 | 37.15 | 66.67 |
| `SourceSans3-Regular.woff` | 0 | `U+0041` | Rejected | 2250.43 | 2809.58 |

## Packed glyph tables

This round uses the same 44 scenarios and repeats the Linux Release comparison against
`eab46cd563`. Glyph indices, advances, bitmap dimensions, and CRC-64 match across both Swag
builds on all 44 scenarios. The timings use Pillow 12.3.0 in Basic layout mode with FreeType
2.14.3 and the same warm-cache, 20 px workload described above. [Raw results](font-decode-linux-packed.json)

Swag leads in 38 of 44 scenarios. It keeps validated `loca` entries and format-2 `post` name
indices in the owned font buffer. It compares adjacent offsets in SIMD groups, including those
in CFF indexes, and reads `name` records from bounded spans.

The six CJK cases save 10% to 16% against the previous Swag build and take 2.2 to 2.8 times
Pillow's time. An isolated `File.readAllBytes` probe takes 1.55 to 2.28 ms on the three distinct
CJK files. The last two columns below come from seven separate instrumented batches of 11
opens. They measure file acquisition and SFNT parsing inside `Face.loadFile`.

| Fixture | Face | Swag before (µs) | Swag after (µs) | Pillow (µs) | Swag file read (µs) | SFNT parse before → after (µs) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `DejaVuSans.ttf` | 0 | 221.59 | 97.76 | 129.01 | 38.78 | 145.91 → 49.39 |
| `DejaVuSerif.ttf` | 0 | 126.72 | 67.25 | 118.43 | 16.53 | 79.96 → 30.45 |
| `NotoSansCJK-Regular.ttc` | 0 | 2459.49 | 2146.01 | 886.69 | 1821.61 | 622.06 → 292.98 |
| `NotoSansCJK-Regular.ttc` | 1 | 2480.27 | 2202.11 | 871.59 | 1813.64 | 629.63 → 276.35 |
| `NotoSansCJK-Regular.ttc` | 2 | 2427.12 | 2174.79 | 811.10 | 1756.02 | 573.22 → 292.34 |
| `NotoSansCJK-Regular.ttc` | 7 | 2419.21 | 2133.10 | 864.25 | 1929.62 | 573.06 → 281.07 |
| `NotoSansCJKjp-Regular.otf` | 0 | 2113.72 | 1871.14 | 839.10 | 1578.20 | 607.93 → 285.79 |
| `NotoSerifCJKjp-Regular.otf` | 0 | 3107.69 | 2619.43 | 932.10 | 2316.68 | 645.73 → 296.45 |

## Compact collection members

Large TTC opens copy the selected face's tables into its owned SFNT buffer. On
Noto Sans CJK, the four tested members read 16.39–16.47 MB of the 19.48 MB file.
The format-12 and format-13 Unicode map validators read the packed group fields directly.

The same 44 scenarios use Linux Release, Swag baseline `740046dbe4`, and Pillow
12.3.0 with FreeType 2.14.3 in Basic mode. Timings use 11 interleaved
batches on the same CPU and a warm file cache. Swag glyph indices, advances, bitmap
dimensions, and CRC-64 match across the two builds in all 44 scenarios.
[Raw file and memory timings](font-decode-linux-collections.json)

The four TTC file cases save 16% to 24% against the Swag baseline. The two CJK OTF
cases save 5% to 7%. Swag leads Pillow in 38 of 44 scenarios. The six CJK
cases take 1.90 to 2.58 times Pillow's elapsed time.

| Fixture | Face | Glyph | Swag before (µs) | Swag after (µs) | Pillow (µs) |
| --- | ---: | --- | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 0 | `U+65E5` | 2209.56 | 1757.23 | 896.04 |
| `NotoSansCJK-Regular.ttc` | 1 | `U+D55C` | 2295.38 | 1923.93 | 968.63 |
| `NotoSansCJK-Regular.ttc` | 2 | `U+4E2D` | 2335.10 | 1770.14 | 930.16 |
| `NotoSansCJK-Regular.ttc` | 7 | `U+FF21` | 2267.90 | 1749.15 | 899.24 |
| `NotoSansCJKjp-Regular.otf` | 0 | `U+65E5` | 1996.81 | 1895.05 | 978.07 |
| `NotoSerifCJKjp-Regular.otf` | 0 | `U+672C` | 2850.41 | 2662.64 | 1032.79 |

The `--collection-memory` run opens the TTC members with `Face.loadAt` after the input
buffer is available. The four cases save 11% to 20% against the Swag baseline.
Their glyph measurements and CRC-64 also match the file run.

| Noto Sans CJK face | Swag before (µs) | Swag after (µs) |
| ---: | ---: | ---: |
| 0 | 2051.76 | 1769.73 |
| 1 | 2200.66 | 1751.38 |
| 2 | 2012.76 | 1781.62 |
| 7 | 2117.45 | 1786.22 |
