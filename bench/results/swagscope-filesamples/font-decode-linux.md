# Expanded font decoder comparison on Linux

Swag is ahead of Pillow in 81 of 103 pathname cases, including all seven
WOFF1 cases. The report includes the 22 remaining CJK cases and timings
with native FreeType under three input acquisition modes.
[Final verification](#final-corpus-verification) · [Native CJK comparison](#native-cjk-pathname-snapshot-and-retained-source-comparison)

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

## CJK file ownership and CFF parsing

Pillow passes filename inputs to `FT_New_Face`. On this Linux build, FreeType maps
the file with `mmap(PROT_READ, MAP_PRIVATE)` and closes the descriptor. Its CFF loader
initializes the CharStrings INDEX with `load = 0`. It reads the terminal offset to size
the index and leaves the charstrings in the stream until glyph loading requests them.
[Pillow pathname loading](https://github.com/python-pillow/Pillow/blob/12.3.0/src/_imagingft.c#L191-L214) · [FreeType mapping](https://github.com/freetype/freetype/blob/VER-2-14-3/builds/unix/ftsystem.c#L247-L338) · [FreeType CFF index loading](https://github.com/freetype/freetype/blob/VER-2-14-3/src/cff/cffload.c#L234-L310) · [FreeType CharStrings call](https://github.com/freetype/freetype/blob/VER-2-14-3/src/cff/cffload.c#L2383-L2390)

A syscall trace of the Japanese Sans OTF confirmed a file mapping and zero `read`
or `pread64` calls against the font descriptor. A separate FreeType stream callback
counted 1.50–1.54 MB requested during open and 69–166 additional bytes for the first
rendered glyph. These are logical byte requests, with repeated requests included.
Replacing a 55-byte charstring in place on a fixture copy changed the output of the
already-open FreeType face on this host.

Swag holds an independent copy, as required by `Face.loadFile`. It acquires
16.39–16.47 MB for the selected Sans TTC members, 16.47 MB for the Sans OTF, and
24.57 MB for the Serif OTF. Charstrings are interpreted on demand from that copy.
Acquisition represents about 90–93% of the profiled opening time after the changes below.
[Swag file loading](../../../bin/std/modules/truetype/src/fontfile.swg) · [Face ownership contract](../../../bin/std/modules/truetype/src/face.swg#L354)

The native FreeType snapshot column includes `pread` of the entire file into
a reusable buffer, then `FT_New_Memory_Face`, size setup, and one rendered glyph.
The file descriptor and buffer are acquired before timing. The OTF rows copy the
same file on both sides. Swag takes 1.81 and 2.93 ms against FreeType snapshot totals
of 2.61 and 3.66 ms. Swag copies just one member on the TTC rows.

The six scenarios use a warm cache, a single Intel Xeon Platinum 8573C CPU, 20 px,
and 11 interleaved batches of 21 fresh faces after five warmups. The Swag baseline
is `685df90fe2`. The Pillow 12.3.0 and native probes use the same FreeType 2.14.3
library. The two Swag builds agree on glyph indices, advances, dimensions, and CRC-64.
A separate sweep checked 2,935 glyphs from the 10 TTC members and the two OTF files,
sampling the first, middle, and last mapped glyph of each FDSelect range.
[Raw timings and phase samples](font-decode-linux-cjk.json) · [Native probe instructions](../../workloads/fontdecode/README.md#cjk-ownership-comparison)

| Fixture | Face | Swag before (µs) | Swag after (µs) | Pillow (µs) | FreeType file (µs) | FreeType snapshot (µs) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 0 | 1745.95 | 1719.71 | 860.58 | 765.23 | 2828.29 |
| `NotoSansCJK-Regular.ttc` | 1 | 1803.25 | 1656.37 | 917.25 | 805.88 | 2776.02 |
| `NotoSansCJK-Regular.ttc` | 2 | 1828.86 | 1761.69 | 877.56 | 793.78 | 2759.99 |
| `NotoSansCJK-Regular.ttc` | 7 | 1739.59 | 1739.02 | 880.85 | 743.40 | 2651.52 |
| `NotoSansCJKjp-Regular.otf` | 0 | 1888.89 | 1806.60 | 878.91 | 927.47 | 2609.75 |
| `NotoSerifCJKjp-Regular.otf` | 0 | 3051.54 | 2933.38 | 955.57 | 876.42 | 3664.34 |

FreeType retains packed FDSelect ranges and caches its last range lookup. Swag used
to allocate and fill one byte per glyph, even for 65,535-glyph faces with only 118
or 221 ranges. The updated parser validates the packed table once. Rendering looks
up format 0 directly and binary-searches format 3. DICT operands also go directly
into their final pool.
[FreeType FDSelect](https://github.com/freetype/freetype/blob/VER-2-14-3/src/cff/cffload.c#L704-L817)

The parser phases below are medians of nine dedicated batches of 11 opens in
instrumented builds. The existing validity checks still cover the entire FDSelect
table at open, including dictionary indices and the final glyph sentinel.

| Fixture | Face | Swag after input acquisition (µs) | SFNT before → after (µs) | FDSelect before → after (µs) |
| --- | ---: | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 0 | 1489.38 | 212.59 → 174.18 | 40.61 → 0.48 |
| `NotoSansCJK-Regular.ttc` | 1 | 1494.49 | 200.08 → 165.68 | 33.56 → 0.48 |
| `NotoSansCJK-Regular.ttc` | 2 | 1608.87 | 202.81 → 180.36 | 36.35 → 0.50 |
| `NotoSansCJK-Regular.ttc` | 7 | 1525.74 | 208.98 → 163.95 | 35.23 → 0.48 |
| `NotoSansCJKjp-Regular.otf` | 0 | 1581.79 | 226.72 → 176.34 | 37.25 → 0.47 |
| `NotoSerifCJKjp-Regular.otf` | 0 | 2868.31 | 266.73 → 207.34 | 45.67 → 0.77 |

## Shared font source

An immutable `FontSource` snapshots a file once. Each loaded face retains the source,
and its size, glyph slot, and rendering workspace remain independent. Scope shares
one source between its collection probe, specimen view, and Pixel typeface cache.
[FontSource implementation](../../../bin/std/modules/truetype/src/fontsource.swg)

Both memory inputs are available before timing starts. The earlier Swag path calls
`Face.loadAt` on the byte buffer, the shared path opens a new face from `FontSource`,
and FreeType 2.14.3 calls `FT_New_Memory_Face`. All variants set 20 px and render one
glyph. The table gives medians of 11 interleaved batches of 21 fresh faces with five
warmups, pinned to a single Intel Xeon Platinum 8573C CPU. The regular Swag file loads
are in the raw samples as a control. The baseline revision is `7447dae0a7`.
[Raw samples](font-decode-linux-source.json) · [Probe modes](../../workloads/fontdecode/README.md#shared-source-comparison)

| Fixture | Face | Swag copying (µs) | Swag shared (µs) | FreeType memory (µs) |
| --- | ---: | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 0 | 1684.14 | 140.28 | 709.42 |
| `NotoSansCJK-Regular.ttc` | 1 | 1668.06 | 132.61 | 708.46 |
| `NotoSansCJK-Regular.ttc` | 2 | 1612.95 | 123.34 | 710.13 |
| `NotoSansCJK-Regular.ttc` | 7 | 1588.57 | 120.73 | 706.37 |
| `NotoSansCJKjp-Regular.otf` | 0 | 1553.45 | 125.22 | 871.36 |
| `NotoSerifCJKjp-Regular.otf` | 0 | 2279.41 | 145.56 | 792.12 |

A separate collection pass includes reading the file, counting all ten TTC members,
opening each, setting 20 px, rendering U+65E5, and destroying each face. It takes
25.63 ms with per-face copies and 12.07 ms with a shared source. Each median uses
11 interleaved batches of 11 complete passes after five warmups. The two Swag modes
match glyph indices, advances, bitmap dimensions, and CRC-64 in both workloads.

## Reusing a parsed CFF program

All ten Noto Sans CJK TTC faces reference one CFF table. The five members of
Noto Serif CJK do the same. A retained source now caches the validated CFF program
by byte range, so the next face can reuse the indexes, dictionaries, and glyph
selection data. The SFNT metrics, character maps, and rendering workspace stay
per face. The corpus adds the serif collection and a variable TrueType CJK control.

The source is already in memory and the parser cache is warm before the timed
opens. Timings include setting 20 px and rendering one glyph. Each result is the
median of 11 interleaved batches of 101 fresh faces after five warmups on one CPU.
The baseline is `ef3a48a55d`. FreeType 2.14.3 uses `FT_New_Memory_Face`.
The Swag builds agree on glyph indices, advances, bitmap dimensions, and CRC-64.
[Raw samples and fixture hashes](font-decode-linux-cff-cache.json)

| Fixture | Face | Glyph | Swag before (µs) | Swag cached (µs) | FreeType memory (µs) |
| --- | ---: | --- | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 0 | `U+65E5` | 148.34 | 63.31 | 745.04 |
| `NotoSansCJK-Regular.ttc` | 1 | `U+D55C` | 143.06 | 75.21 | 747.58 |
| `NotoSansCJK-Regular.ttc` | 2 | `U+4E2D` | 127.95 | 63.47 | 733.87 |
| `NotoSansCJK-Regular.ttc` | 7 | `U+FF21` | 131.99 | 64.31 | 705.97 |
| `NotoSansCJKjp-Regular.otf` | 0 | `U+65E5` | 138.09 | 66.23 | 909.93 |
| `NotoSerifCJK-Regular.ttc` | 0 | `U+65E5` | 150.38 | 66.93 | 793.23 |
| `NotoSerifCJK-Regular.ttc` | 1 | `U+D55C` | 168.89 | 88.37 | 825.53 |
| `NotoSerifCJK-Regular.ttc` | 2 | `U+4E2D` | 152.44 | 67.78 | 788.46 |
| `NotoSerifCJK-Regular.ttc` | 3 | `U+9F8D` | 176.26 | 97.42 | 838.45 |
| `NotoSerifCJK-Regular.ttc` | 4 | `U+2000B` | 150.66 | 75.56 | 781.38 |
| `NotoSansSC-Variable.ttf` | 0 | `U+9F8D` | 57.29 | 54.92 | 1664.71 |
| `NotoSerifCJKjp-Regular.otf` | 0 | `U+672C` | 150.23 | 73.36 | 808.39 |

The collection passes below start with a fresh source and an empty parse cache each time.
The input snapshot is made before timing. Each pass opens every member, renders U+65E5
at 20 px, and destroys each face. The medians use 11 interleaved batches of 11 complete
passes and matching glyph fingerprints between Swag builds.

| Collection | Members | Swag before (µs) | Swag cached (µs) |
| --- | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 10 | 1425.25 | 780.76 |
| `NotoSerifCJK-Regular.ttc` | 5 | 774.06 | 468.94 |

## Default-instance TrueType snapshots

The standalone load keeps the default glyph outlines in `glyf`. When a large
`gvar` table describes other instances, the owned snapshot checks the original
range and omits the variation payload. A selected collection member can omit the
same unused data. Both file and copied-memory loads use the compact representation.

The comparison adds Noto Sans JP and Noto Sans TC variable TrueType to the
existing SC fixture. Swag leads Pillow in 41 of the 52 expanded file scenarios.
The other eleven are CJK CFF file loads. All Swag glyph indices, advances, bitmap
dimensions, and CRC-64 match the baseline `ccd4c58548`.

The file comparison uses Pillow 12.3.0 with FreeType 2.14.3 in Basic mode. Each
result is the median of 11 interleaved batches on one CPU with a warm file cache.
The probe opens 101 fresh faces per batch, or 21 for files of at least 10 MB.
A separate syscall trace counts bytes returned by reads of the font file.
[All 52 scenarios and raw timings](font-decode-linux-variations.json)

| Fixture | Bytes read before | Bytes read after | Swag before (µs) | Swag after (µs) | Pillow (µs) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `NotoSansJP-Variable.ttf` | 9589912 | 5840191 | 942.65 | 622.67 | 2443.57 |
| `NotoSansTC-Variable.ttf` | 11941980 | 7223529 | 1119.88 | 748.68 | 2189.34 |
| `NotoSansSC-Variable.ttf` | 17772312 | 10690532 | 1662.16 | 1067.02 | 2301.50 |

## SIMD validation of Unicode groups

The format-12 and format-13 validators load four packed groups at a time.
Vector checks cover range order, Unicode bounds, and glyph counts. A bounded
scalar pass handles the tail, and the first group can still start at U+0000.

The 14 CJK scenarios use an existing in-memory source with its parsed CFF data
already available where applicable. Each result is the median of 11 interleaved
batches of 251 fresh faces at 20 px after five warmups. The baseline is
`d47643249d`. Glyph indices, advances, bitmap dimensions, and CRC-64 match.
The last column uses seven separate instrumented batches of 506 opens.
[Raw phase and end-to-end timings](font-decode-linux-cmap.json)

| Fixture | Face | Open and render before (µs) | After (µs) | CMap parse before → after (µs) |
| --- | ---: | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 0 | 63.89 | 50.08 | 38.15 → 27.59 |
| `NotoSansCJK-Regular.ttc` | 1 | 75.66 | 62.06 | 40.09 → 25.22 |
| `NotoSansCJK-Regular.ttc` | 2 | 66.12 | 50.96 | 39.70 → 24.76 |
| `NotoSansCJK-Regular.ttc` | 7 | 62.36 | 51.03 | 39.38 → 25.15 |
| `NotoSansCJKjp-Regular.otf` | 0 | 64.27 | 49.00 | 37.53 → 26.38 |
| `NotoSerifCJK-Regular.ttc` | 0 | 66.38 | 52.85 | 38.78 → 24.83 |
| `NotoSerifCJK-Regular.ttc` | 1 | 92.22 | 77.56 | 38.28 → 25.97 |
| `NotoSerifCJK-Regular.ttc` | 2 | 69.16 | 52.20 | 38.35 → 23.80 |
| `NotoSerifCJK-Regular.ttc` | 3 | 93.55 | 79.33 | 40.22 → 23.97 |
| `NotoSerifCJK-Regular.ttc` | 4 | 72.49 | 59.24 | 36.57 → 23.36 |
| `NotoSansJP-Variable.ttf` | 0 | 52.37 | 48.73 | 16.43 → 11.36 |
| `NotoSansTC-Variable.ttf` | 0 | 70.16 | 58.07 | 13.97 → 10.05 |
| `NotoSansSC-Variable.ttf` | 0 | 57.69 | 54.05 | 4.21 → 3.25 |
| `NotoSerifCJKjp-Regular.otf` | 0 | 74.38 | 62.01 | 39.96 → 25.20 |

## Parallel reads for large Linux snapshots

On Linux, a read of at least 8 MiB can use up to four positional reads on the
same descriptor. The reads fill disjoint parts of the owned buffer. Completion
returns the contiguous prefix in file order, and a failed positional read falls
back to the ordinary stream path. The parallel path uses the existing worker budget.

The runs pin to one or four logical CPUs. With four CPUs, the automatic runtime
starts three pool workers and the submitting thread also participates.
The table reports medians of 11 interleaved batches of 21 fresh file opens and
one rendered glyph at 20 px. The warm-cache baseline is `d8325e8d9e`.
Glyph indices, advances, bitmap dimensions, and CRC-64 agree across all four runs.
Separate one-worker repeats on the three variable controls ranged from a 3.3%
gain to a 0.4% slowdown. [Raw timings and controls](font-decode-linux-parallel-read.json)

| Fixture | Face | Before, 1 worker (µs) | After, 1 worker (µs) | Before, 4 CPUs (µs) | After, 4 CPUs (µs) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 0 | 1891.21 | 1854.06 | 1897.67 | 1344.06 |
| `NotoSansCJK-Regular.ttc` | 1 | 1859.76 | 1851.97 | 1867.81 | 1339.43 |
| `NotoSansCJK-Regular.ttc` | 2 | 1862.02 | 1847.06 | 1829.87 | 1358.68 |
| `NotoSansCJK-Regular.ttc` | 7 | 1758.30 | 1806.98 | 1932.74 | 1378.64 |
| `NotoSansCJKjp-Regular.otf` | 0 | 2347.30 | 2435.86 | 2334.61 | 1387.47 |
| `NotoSerifCJK-Regular.ttc` | 0 | 2906.34 | 2812.75 | 2876.17 | 1815.55 |
| `NotoSerifCJK-Regular.ttc` | 1 | 2826.45 | 2883.94 | 2916.28 | 1828.94 |
| `NotoSerifCJK-Regular.ttc` | 2 | 2866.84 | 2849.03 | 2807.05 | 1892.63 |
| `NotoSerifCJK-Regular.ttc` | 3 | 2993.83 | 2877.82 | 2952.54 | 1920.72 |
| `NotoSerifCJK-Regular.ttc` | 4 | 2755.14 | 2810.16 | 2869.38 | 1785.00 |
| `NotoSansJP-Variable.ttf` | 0 | 678.24 | 726.53 | 709.40 | 671.06 |
| `NotoSansTC-Variable.ttf` | 0 | 797.36 | 822.75 | 782.59 | 772.96 |
| `NotoSansSC-Variable.ttf` | 0 | 1165.01 | 1196.82 | 1208.67 | 862.64 |
| `NotoSerifCJKjp-Regular.otf` | 0 | 3282.91 | 3318.16 | 3364.66 | 2027.74 |

Each collection pass includes the initial read into `FontSource`, opening every
member, rendering U+65E5 at 20 px, and destroying each face. The medians below
use 11 interleaved batches of 11 passes.

| Collection | Members | Before, 4 CPUs (ms) | After, 4 CPUs (ms) |
| --- | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 10 | 13.74 | 5.89 |
| `NotoSerifCJK-Regular.ttc` | 5 | 15.42 | 6.90 |

## Cold CFF dictionary decoding

CFF font and private dictionaries reuse their operator and operand buffers while
the FDArray is decoded. Each parsed private dictionary stores its local subroutines
and width defaults together in one reserved array.

The probe creates a fresh source from bytes already in memory before each measured
open. It times opening, setting 20 px, and rendering one glyph. The FDArray phase
is measured inside the parser. Medians use 11 interleaved batches of 31 fresh
opens after five warmups on one CPU. The baseline is `d8325e8d9e`. The Swag builds
agree on glyph indices, advances, dimensions, and CRC-64. [Raw samples](font-decode-linux-cff-dicts.json)

| Fixture | Face | Open and render before (µs) | After (µs) | FDArray before → after (µs) |
| --- | ---: | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 0 | 141.97 | 130.34 | 41.54 → 28.78 |
| `NotoSansCJK-Regular.ttc` | 7 | 141.88 | 142.42 | 44.61 → 27.55 |
| `NotoSansCJKjp-Regular.otf` | 0 | 149.02 | 134.89 | 45.30 → 26.30 |
| `NotoSerifCJK-Regular.ttc` | 0 | 163.91 | 149.08 | 47.00 → 31.43 |
| `NotoSerifCJK-Regular.ttc` | 4 | 174.16 | 160.59 | 48.42 → 35.37 |
| `NotoSerifCJKjp-Regular.otf` | 0 | 190.26 | 154.93 | 47.75 → 29.36 |

## Shared WOFF1 reconstruction

A `FontSource` keeps its original WOFF1 snapshot and reconstructs the sfnt on
the first metadata or face request. Swag Scope uses that reconstruction for both
metadata and rendering. Later faces borrow the same sfnt and keep their own glyph
and size state. Both byte buffers remain allocated until the last owner releases
the source.

The corpus adds generated WOFF1 forms of the pinned Noto Sans CJK JP OTF and Noto
Sans SC variable TTF. It now covers 54 scenarios on 47 files, including the 12
supplied fonts. The table compares open and render at 20 px on one CPU, using the
median of 11 interleaved batches of 5 fresh faces after 5 warmups. The source
columns omit the initial load. The file columns include independently opening the
file, reading it, and reconstructing its tables on every iteration. FreeType
2.14.3 opens the input from existing memory and reconstructs it for each face.
Swag's glyph indices, advances, bitmap dimensions, and CRC-64 agree with the
baseline `b50a786180`. FreeType selects the same glyph indices.
[Raw timings](font-decode-linux-woff-source.json)

| Fixture | Source before (ms) | Source after (ms) | File before (ms) | File after (ms) | FreeType memory (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `DejaVuSans.woff` | 4.926 | 0.064 | 4.816 | 5.029 | 5.828 |
| `Inter-Variable.woff` | 6.544 | 0.037 | 6.045 | 5.891 | 9.701 |
| `SourceSans3-Regular.woff` | 2.396 | 0.020 | 2.435 | 2.467 | 2.933 |
| `NotoSansCJKjp-Regular.woff` | 140.022 | 0.068 | 144.358 | 142.367 | 153.263 |
| `NotoSansSC-Variable.woff` | 137.758 | 0.077 | 142.215 | 139.633 | 157.508 |

## Parallel WOFF1 reconstruction

A WOFF1 file with at least two independently compressed tables of 1 MiB or more
can reconstruct its tables on the existing worker pool. Directory validation
assigns each table a disjoint sfnt range. A worker verifies the zlib stream and
copies its decoded bytes and alignment padding into that range. The decoder
returns errors in directory order. Concurrent tables use temporary output
buffers in addition to the final sfnt. One-worker runs and files below the
threshold decode serially.

The corpus adds WOFF1 variants of Noto Sans JP and TC variable TrueType, for 56
scenarios on 49 files. The baseline is `29663c04fe`. Each row measures a fresh
pathname open and one rendered glyph at 20 px with a warm filesystem cache.
Results are medians of 11 interleaved batches of seven opens after five warmups.
The four-CPU run uses the automatic pool of three workers.
The Swag builds return identical glyph indices, advances, bitmap dimensions,
and CRC-64. FreeType 2.14.3 agrees on the glyph indices.
[Raw samples](font-decode-linux-woff-parallel.json)

| Fixture | Before, 1 worker (ms) | After, 1 worker (ms) | Before, 4 CPUs (ms) | After, 4 CPUs (ms) | FreeType file (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `DejaVuSans.woff` | 4.014 | 4.104 | 4.091 | 3.880 | 5.001 |
| `Inter-Variable.woff` | 4.810 | 4.770 | 4.771 | 4.869 | 7.615 |
| `SourceSans3-Regular.woff` | 1.945 | 2.008 | 2.016 | 2.015 | 2.599 |
| `NotoSansCJKjp-Regular.woff` | 116.844 | 117.216 | 111.422 | 116.097 | 133.345 |
| `NotoSansSC-Variable.woff` | 112.930 | 112.537 | 109.453 | 82.094 | 133.829 |
| `NotoSansJP-Variable.woff` | 56.865 | 58.157 | 57.344 | 34.873 | 70.728 |
| `NotoSansTC-Variable.woff` | 77.360 | 75.758 | 76.828 | 51.539 | 88.707 |

## Shared character map selection

Faces borrowed from one immutable source keep the validated base map and variation
map selection for each table range and glyph count. A later open of that range
can use the selection without rescanning its groups. Collection members can
share a selection when both bounds agree.

The corpus adds three public static TrueType fonts, for 59 scenarios on 52
files. Timings use one CPU, a 20 px glyph, and 11 interleaved batches after five
warmups. The baseline is `36223c728c`. Each source batch opens 251 fresh faces
from the same source after its first parse. File controls use 21 independent
pathname opens per batch. FreeType 2.14.3 uses a memory face for the source run
and a pathname face for the file run. The Swag builds produce matching glyph
indices, advances, dimensions, and CRC-64. FreeType selects the same glyph
indices. [Raw timings and a repeat on eight controls](font-decode-linux-cmap-source.json)

| Fixture | Face | Source before (µs) | Source after (µs) | FreeType memory (µs) |
| --- | ---: | ---: | ---: | ---: |
| `DejaVuSans.ttf` | 0 | 58.44 | 56.95 | 91.81 |
| `Inter-Variable.ttf` | 0 | 33.93 | 30.74 | 1633.30 |
| `NimbusSans-Regular.otf` | 0 | 14.08 | 13.18 | 51.26 |
| `NotoSansCJK-Regular.ttc` | 0 | 53.84 | 24.41 | 793.59 |
| `NotoSansCJK-Regular.ttc` | 1 | 63.30 | 34.83 | 811.87 |
| `NotoSansCJK-Regular.ttc` | 2 | 55.60 | 29.11 | 776.44 |
| `NotoSansCJK-Regular.ttc` | 7 | 51.01 | 27.38 | 783.83 |
| `NotoSansCJKjp-Regular.otf` | 0 | 51.72 | 25.17 | 972.10 |
| `NotoSerifCJK-Regular.ttc` | 0 | 54.72 | 30.51 | 873.99 |
| `NotoSerifCJK-Regular.ttc` | 1 | 82.77 | 56.13 | 873.95 |
| `NotoSerifCJK-Regular.ttc` | 2 | 57.04 | 31.20 | 853.90 |
| `NotoSerifCJK-Regular.ttc` | 3 | 97.05 | 75.96 | 864.13 |
| `NotoSerifCJK-Regular.ttc` | 4 | 63.80 | 39.85 | 952.80 |
| `ZenKakuGothicNew-Regular.ttf` | 0 | 74.80 | 78.72 | 820.66 |
| `MaShanZheng-Regular.ttf` | 0 | 92.88 | 102.14 | 1067.52 |
| `GowunBatang-Regular.ttf` | 0 | 130.72 | 131.75 | 696.43 |
| `NotoSansJP-Variable.ttf` | 0 | 51.73 | 38.55 | 1781.86 |
| `NotoSansTC-Variable.ttf` | 0 | 64.26 | 52.71 | 1860.31 |
| `NotoSansSC-Variable.ttf` | 0 | 60.61 | 54.36 | 1832.17 |
| `NotoSerifCJKjp-Regular.otf` | 0 | 65.29 | 35.90 | 974.25 |

Static CJK source medians were within 3.6% in the quieter control repeat. The
pathname comparison still shows the independent-copy cost, including 3.76 ms
for Noto Serif CJK JP versus 0.89 ms in FreeType and 1.21 ms for Gowun Batang
versus 0.71 ms in FreeType. For Noto Serif CJK JP, the two independent pathname
repeats were 5–9% slower than the Swag baseline. The source speedup applies to
retained snapshots.

## Scope character index

Scope builds its page starts and its first Unicode scalar per glyph by
visiting the selected character map in order. For grouped maps, iteration
seeks to the first group it needs and walks the mapped ranges. Glyph-zero
mappings and surrogate code points are skipped. One visit builds each index
when the viewer opens a face or switches to another collection member.

The probe isolates the viewer's index construction with the face already
loaded. It starts at U+0020 and uses 192 characters per page. The baseline is
`154239b013`. Medians use seven interleaved batches of three indexes on one
CPU, after one warmup. All 59 fixture faces have the same page count and
CRC-64 of the page starts and glyph-to-character arrays before and after.
[Raw timings and checksums](font-index-linux.json)

| Fixture | Face | Before (ms) | After (ms) |
| --- | ---: | ---: | ---: |
| `DejaVuSans.ttf` | 0 | 104.888 | 0.029 |
| `NotoSansCJKjp-Regular.otf` | 0 | 131.549 | 0.419 |
| `NotoSerifCJK-Regular.ttc` | 0 | 130.425 | 0.382 |
| `ZenKakuGothicNew-Regular.ttf` | 0 | 73.638 | 6.268 |
| `MaShanZheng-Regular.ttf` | 0 | 76.504 | 6.301 |
| `GowunBatang-Regular.ttf` | 0 | 110.338 | 0.059 |
| `NotoSansJP-Variable.ttf` | 0 | 129.159 | 0.157 |
| `NotoSansSC-Variable.ttf` | 0 | 115.414 | 0.184 |

## Format-4 character index

Scope's index can visit the ordered segments of a format-4 map directly.
The visitor uses the same glyph array and delta rules as a single-character
lookup. With an unordered set of end codes, the visitor uses the existing
lookup results for each code. Ordered overlapping segments retain the first
matching segment.

The probe repeats the index workload on all 59 fixture faces, starting at
U+0020 with 192 characters per page. The baseline is `8296a9151e`. Medians
use seven interleaved batches of three indexes and one warmup on one CPU.
Every page count and both CRC-64 values match the baseline.
[Raw timings and checksums](font-index-linux-cmap4.json)

| Fixture | Before (ms) | After (ms) |
| --- | ---: | ---: |
| `NotoSansCJKjp-Regular.otf` | 0.4477 | 0.4223 |
| `ZenKakuGothicNew-Regular.ttf` | 6.5499 | 0.1092 |
| `MaShanZheng-Regular.ttf` | 6.0487 | 0.1250 |
| `fontawesome-webfont.ttf` | 5.7881 | 0.0044 |
| `OpenSans-Regular.otf` | 5.2105 | 0.0057 |
| `SourceCodePro-Regular.ttf` | 5.2968 | 0.0043 |

## Packed SFNT scans

The metrics parser converts eight short vertical records together, interleaving
their bearings with the last advance height. Legacy kerning validates four
ordered records at a time before using the packed pair table. The glyph-name
parser groups Pascal strings when the remaining bytes cover four maximum-size
records and checks the rest individually.

The probe compares nine cases with `2fe9e5e5b8`. Each measurement uses one
CPU and a glyph at 20 px, with medians from 11 interleaved batches after five
warmups. The source mode opens 251 faces per batch from a retained snapshot.
The file mode uses 21 independent pathname opens and includes the bytes read.
Glyph indices, advances, dimensions, and CRC-64 agree across Swag builds.
FreeType 2.14.3 selects the same glyphs.
[Raw timings and phase measurements](font-decode-linux-sfnt-scans.json)

| Fixture | Source before (µs) | Source after (µs) | File before (µs) | File after (µs) |
| --- | ---: | ---: | ---: | ---: |
| `DejaVuSans.ttf` | 58.01 | 37.95 | 135.45 | 122.88 |
| `DejaVuSerif.ttf` | 49.84 | 41.14 | 85.26 | 72.65 |
| `Inter-Variable.ttf` | 30.80 | 28.26 | 123.08 | 137.80 |
| `NimbusSans-Regular.otf` | 13.12 | 12.81 | 45.07 | 43.62 |
| `ZenKakuGothicNew-Regular.ttf` | 79.25 | 55.53 | 409.17 | 433.34 |
| `MaShanZheng-Regular.ttf` | 102.77 | 89.74 | 814.81 | 858.67 |
| `GowunBatang-Regular.ttf` | 137.35 | 106.11 | 1297.48 | 1271.88 |
| `NotoSansSC-Variable.ttf` | 53.82 | 55.98 | 1478.27 | 1389.73 |
| `NotoSerifCJKjp-Regular.otf` | 34.02 | 35.82 | 4063.82 | 3968.45 |

In the separate phase probe, median kerning validation for DejaVu Sans moves
from 13.87 to 3.21 µs. Gowun Batang's metrics move from 31.03 to 2.47 µs and its
glyph-name parse from 40.64 to 28.34 µs. Each phase measurement uses 21 opens
from a retained source after five warmups.

A full pathname repeat before this pass uses Pillow 12.3.0 Basic layout with
FreeType 2.14.3. Swag wins 46 of 59 cases across 52 files on one CPU. The
remaining cases include eleven CJK CFF faces, Gowun Batang, and DejaVu Sans.
[Full corpus repeat](font-decode-linux-59-cases.json)

## Deflate table widths

Deflate uses an 11-bit literal lookup for dynamic streams at least 16 KiB and
a 9-bit lookup for smaller streams. Its distance and code-length tables use
eight and seven bits. Dynamic lookup storage belongs to the dynamic block
decoder. The baseline `65bb993978` includes the fixed tables already
precomputed by `59b58035db`.

The table uses 11 interleaved batches of seven fresh pathname opens with one
worker after five warmups. Each open renders one glyph at 20 px. The Swag
builds return the same glyph indices, advances, dimensions, and CRC-64.
FreeType 2.14.3 selects the same glyph indices.
[Raw timings, an earlier run, and zlib controls](font-decode-linux-deflate.json)

| Fixture | Before (ms) | After (ms) | FreeType file (ms) |
| --- | ---: | ---: | ---: |
| `DejaVuSans.woff` | 3.881 | 3.651 | 4.978 |
| `Inter-Variable.woff` | 4.773 | 4.283 | 7.567 |
| `SourceSans3-Regular.woff` | 1.881 | 1.948 | 2.564 |
| `NotoSansCJKjp-Regular.woff` | 114.465 | 104.958 | 132.816 |
| `NotoSansSC-Variable.woff` | 112.823 | 100.501 | 132.070 |
| `NotoSansJP-Variable.woff` | 56.432 | 50.088 | 68.359 |
| `NotoSansTC-Variable.woff` | 75.505 | 64.921 | 87.658 |

The WOFF1 CJK opens improve by 8–14%. Source Sans 3 takes 0.067 ms longer in
this repeat. Four PNG IDAT streams, fixed and stored streams, and repetitive
dynamic data were also decoded directly. The decoded lengths and CRC-64
match in every control. The stored 256 KiB stream takes 21.09 µs versus
20.81 µs. The PNG streams gain 4–10%.

## CFF glyph outlines

Type 2 decoding consumes consecutive one-byte operands with a local stack
cursor. Cubic curves reserve their three points and three tags together.

The probe measures a glyph in a loaded face at 24 px and 64 px. Each program
warms the glyph set once and measures five passes through the same set.
The medians use nine interleaved batches on one CPU. Up to 513 code points
are sampled per face from its CJK, Hangul, and supplementary CJK coverage,
with Latin and neighboring blocks for the controls. The seed is 5973 plus
the member index. The two builds match point counts and CRC-64 of contour
ends, points, tags, and rendered bitmap bytes.
[Raw timings and fixture fingerprints](font-glyph-linux-cff-batch.json)

| Fixture | Face | Pixels | Outline before (µs/glyph) | After | Bitmap before (µs/glyph) | After |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `GowunBatang-Regular.ttf` | 0 | 24 | 12.517 | 11.688 | 75.999 | 74.806 |
| `GowunBatang-Regular.ttf` | 0 | 64 | 12.293 | 12.464 | 182.789 | 186.396 |
| `NimbusSans-Regular.otf` | 0 | 24 | 2.008 | 1.651 | 11.484 | 10.742 |
| `NimbusSans-Regular.otf` | 0 | 64 | 1.915 | 1.589 | 24.291 | 23.349 |
| `NotoSansCJK-Regular.ttc` | 1 | 24 | 6.101 | 4.694 | 29.332 | 27.916 |
| `NotoSansCJK-Regular.ttc` | 1 | 64 | 6.010 | 4.668 | 59.923 | 58.153 |
| `NotoSansCJKjp-Regular.otf` | 0 | 24 | 6.359 | 4.559 | 28.238 | 27.496 |
| `NotoSansCJKjp-Regular.otf` | 0 | 64 | 6.106 | 4.436 | 58.061 | 57.604 |
| `NotoSerifCJK-Regular.ttc` | 4 | 24 | 13.235 | 9.262 | 49.825 | 45.470 |
| `NotoSerifCJK-Regular.ttc` | 4 | 64 | 11.870 | 9.655 | 96.679 | 96.802 |
| `NotoSerifCJKjp-Regular.otf` | 0 | 24 | 12.526 | 8.915 | 50.001 | 46.381 |
| `NotoSerifCJKjp-Regular.otf` | 0 | 64 | 11.423 | 8.945 | 97.159 | 94.230 |
| `SourceSans3-Regular.otf` | 0 | 24 | 2.490 | 1.858 | 12.164 | 11.845 |
| `SourceSans3-Regular.otf` | 0 | 64 | 2.589 | 2.047 | 26.386 | 24.730 |

The 64 px TrueType control and the large Serif CJK bitmap case show small
timing increases. The CFF outline phase improves at both sizes on all six
CFF faces.

## TrueType glyph output buffers

Simple TrueType glyphs expand their flags into the reusable tag buffer and
decode coordinates directly into the reusable point buffer. Coordinate
lengths are checked while expanding flag runs. Contour ends remain in the
font bytes until final append. A failed load rolls back the appended points
and tags. Composite glyphs use the same simple-glyph decoder for their parts.

The probe uses the glyph workload at 24 px and 64 px on nine TrueType files,
including two of the supplied fonts. It compares with `65bb993978` and uses
nine interleaved batches of five passes after one warmup. The table gives
the median time per glyph. Both builds match point counts and CRC-64 for
points, tags, contour ends, and rendered bitmap bytes.
[Raw timings and the control repeat](font-glyph-linux-glyf-output.json)

| Fixture | Pixels | Outline before (µs/glyph) | After | Bitmap before (µs/glyph) | After |
| --- | ---: | ---: | ---: | ---: | ---: |
| `DejaVuSans.ttf` | 24 | 5.176 | 2.825 | 10.751 | 9.114 |
| `DejaVuSans.ttf` | 64 | 4.972 | 3.290 | 19.020 | 18.253 |
| `GowunBatang-Regular.ttf` | 24 | 11.928 | 8.753 | 73.112 | 72.749 |
| `GowunBatang-Regular.ttf` | 64 | 12.612 | 9.372 | 179.808 | 176.497 |
| `Lato-Regular.ttf` | 24 | 2.821 | 2.188 | 14.281 | 13.597 |
| `Lato-Regular.ttf` | 64 | 2.942 | 1.856 | 31.378 | 30.801 |
| `MaShanZheng-Regular.ttf` | 24 | 13.806 | 10.282 | 101.881 | 100.752 |
| `MaShanZheng-Regular.ttf` | 64 | 13.616 | 9.948 | 268.862 | 265.235 |
| `NotoSansJP-Variable.ttf` | 24 | 6.437 | 4.584 | 35.697 | 35.217 |
| `NotoSansJP-Variable.ttf` | 64 | 6.659 | 4.737 | 83.918 | 78.398 |
| `NotoSansSC-Variable.ttf` | 24 | 5.950 | 4.600 | 37.871 | 36.265 |
| `NotoSansSC-Variable.ttf` | 64 | 6.845 | 4.925 | 83.778 | 81.983 |
| `NotoSansTC-Variable.ttf` | 24 | 7.358 | 4.834 | 44.744 | 35.438 |
| `NotoSansTC-Variable.ttf` | 64 | 6.932 | 5.133 | 82.338 | 81.927 |
| `OpenSans-Regular.ttf` | 24 | 2.946 | 1.802 | 16.213 | 15.668 |
| `OpenSans-Regular.ttf` | 64 | 2.894 | 1.927 | 36.945 | 37.090 |
| `ZenKakuGothicNew-Regular.ttf` | 24 | 6.032 | 4.575 | 34.856 | 33.126 |
| `ZenKakuGothicNew-Regular.ttf` | 64 | 6.261 | 4.748 | 77.721 | 76.109 |

In the 11-batch repeat on three files, Open Sans at 64 px moves from 2.632
to 2.001 µs per outline. Gowun Batang moves from 11.954 to 8.624 µs and
Noto Sans SC from 6.895 to 4.822 µs at the same size.

## First positional font read

Large Linux reads submit their independent ranges before reading the first
range on the caller. Each task writes its own part of the same buffer. The
join preserves the contiguous prefix and the file stream's position.

Each timed run opens and renders one face in a fresh process from a warmed
filesystem cache. The Swag probes request four workers and are pinned to
four logical CPUs. Both build variants use the same worker setup. One
series includes lazy pool startup and the other prestarts it. The medians
use 21 interleaved cases per face. FreeType 2.14.3 also opens one face in
a fresh process. The baseline is `08cc42d7d8`.
[Raw timings, WOFF controls, and one-worker repeat](font-decode-linux-first-read.json)

| Fixture | First before (ms) | First after (ms) | Prestarted before (ms) | Prestarted after (ms) | FreeType first (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 9.856 | 6.205 | 7.532 | 5.067 | 1.532 |
| `NotoSansCJKjp-Regular.otf` | 9.197 | 5.981 | 7.442 | 5.756 | 1.549 |
| `NotoSerifCJK-Regular.ttc` | 13.259 | 10.428 | 10.887 | 7.387 | 1.702 |
| `GowunBatang-Regular.ttf` | 4.122 | 3.300 | 3.996 | 2.488 | 1.237 |
| `NotoSerifCJKjp-Regular.otf` | 11.930 | 8.287 | 11.186 | 7.872 | 1.739 |

The first opens above improve by 20–37%, and the prestarted runs by 23–38%.
The WOFF controls include a 12% increase on Noto Sans SC with lazy worker
startup and a 0.5% increase with the prestarted pool. Glyph indices,
advances, dimensions, and CRC-64 agree across the two Swag builds for
every run. FreeType selects the same glyph indices.

## TrueType outline point scaling

Simple glyphs compute a reciprocal once and reuse it for both axes. The
fast calculation corrects the quotient before applying the sign. Large
intermediate values use integer division with the same rounding rule.

The comparison with `08cc42d7d8` uses nine interleaved batches of five
passes on one CPU. The point, tag, contour, and bitmap fingerprints match
at both pixel sizes. The six CJK fixtures take 27–42% less time to load
their outlines. Bitmap results also include the unchanged raster stage.
[Raw timings and fingerprints](font-glyph-linux-point-scale.json)

| Fixture | Pixels | Outline before (µs/glyph) | After | Bitmap before (µs/glyph) | After |
| --- | ---: | ---: | ---: | ---: | ---: |
| `DejaVuSans.ttf` | 24 | 3.090 | 3.111 | 9.832 | 8.031 |
| `DejaVuSans.ttf` | 64 | 3.138 | 2.984 | 17.174 | 15.569 |
| `GowunBatang-Regular.ttf` | 24 | 8.534 | 5.835 | 68.820 | 65.254 |
| `GowunBatang-Regular.ttf` | 64 | 7.988 | 5.835 | 172.318 | 167.222 |
| `Lato-Regular.ttf` | 24 | 1.905 | 1.538 | 13.594 | 13.493 |
| `Lato-Regular.ttf` | 64 | 1.814 | 1.394 | 30.272 | 29.511 |
| `MaShanZheng-Regular.ttf` | 24 | 10.484 | 7.287 | 92.065 | 90.235 |
| `MaShanZheng-Regular.ttf` | 64 | 10.168 | 7.145 | 248.289 | 251.704 |
| `NotoSansJP-Variable.ttf` | 24 | 4.515 | 2.978 | 33.384 | 31.170 |
| `NotoSansJP-Variable.ttf` | 64 | 4.301 | 3.093 | 75.311 | 76.817 |
| `NotoSansSC-Variable.ttf` | 24 | 4.490 | 3.296 | 35.503 | 33.639 |
| `NotoSansSC-Variable.ttf` | 64 | 4.680 | 3.344 | 82.134 | 78.215 |
| `NotoSansTC-Variable.ttf` | 24 | 4.800 | 3.492 | 35.133 | 33.267 |
| `NotoSansTC-Variable.ttf` | 64 | 4.523 | 3.217 | 81.547 | 80.546 |
| `OpenSans-Regular.ttf` | 24 | 1.899 | 1.317 | 15.616 | 14.758 |
| `OpenSans-Regular.ttf` | 64 | 1.987 | 1.382 | 35.607 | 36.250 |
| `ZenKakuGothicNew-Regular.ttf` | 24 | 4.419 | 3.164 | 33.681 | 31.201 |
| `ZenKakuGothicNew-Regular.ttf` | 64 | 5.474 | 3.186 | 74.013 | 70.635 |

DejaVu Sans is within 5% at both sizes for outline loading. The 64 px
bitmap timings rise by 1–2% on Ma Shan Zheng, Noto Sans JP, and Open Sans.

## Vertical metrics shared by a retained font source

Faces from the same source reuse expanded vertical metrics when they
reference the same table range and have the same glyph and long-record
counts. The face keeps the source alive for the duration of any
vertical-metrics borrow. Standalone loads expand into face-owned storage.

The comparison with `8e3e1dea33` uses 11 interleaved batches on one
CPU. Each batch measures 251 reopens of a retained source at 20 px.
The loading phase takes 36–55% less time across the 11 CJK CFF cases.
Opening and rendering together takes 23–46% less time. Swag glyph
indices, advances, dimensions, and bitmap fingerprints match in every
case. FreeType 2.14.3 opens the same face from a retained memory buffer.
[Raw timings including pathname controls](font-decode-linux-vertical-metrics.json)

| Fixture | Face | Open before (µs) | After | Open and render before (µs) | After | FreeType (µs) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 0 | 20.84 | 9.32 | 28.25 | 15.66 | 820.17 |
| `NotoSansCJK-Regular.ttc` | 1 | 19.34 | 9.38 | 34.80 | 22.87 | 783.95 |
| `NotoSansCJK-Regular.ttc` | 2 | 19.94 | 9.41 | 27.60 | 16.35 | 782.04 |
| `NotoSansCJK-Regular.ttc` | 7 | 19.78 | 8.94 | 26.04 | 14.76 | 784.38 |
| `NotoSansCJKjp-Regular.otf` | 0 | 20.32 | 9.88 | 28.77 | 15.65 | 990.85 |
| `NotoSerifCJK-Regular.ttc` | 0 | 19.99 | 9.84 | 28.81 | 16.57 | 853.98 |
| `NotoSerifCJK-Regular.ttc` | 1 | 19.34 | 11.45 | 56.17 | 40.08 | 882.69 |
| `NotoSerifCJK-Regular.ttc` | 2 | 20.16 | 10.69 | 29.97 | 19.63 | 886.56 |
| `NotoSerifCJK-Regular.ttc` | 3 | 21.00 | 11.73 | 60.01 | 43.78 | 934.95 |
| `NotoSerifCJK-Regular.ttc` | 4 | 19.80 | 12.66 | 38.65 | 29.70 | 883.52 |
| `NotoSerifCJKjp-Regular.otf` | 0 | 21.61 | 10.74 | 37.71 | 23.73 | 872.79 |

Pathname controls for these CFF faces vary between 5% faster and 7% slower.
That path performs its own file read and expands the metrics per call.

## Expanded Chinese, Japanese and Korean fixtures

The corpus has 71 cases across 58 files, including the 12 supplied
fonts. Six pinned Google Fonts add Hong Kong Chinese, Korean and
Japanese variable TrueType faces and two Traditional Chinese static
faces. Cases cover kana, Hangul, Han characters and an Extension B
code point. All new cases select a nonzero glyph.

With one worker and one CPU, Swag opens and renders faster than Pillow
12.3.0 with FreeType 2.14.3 in 60 of 71 cases. All 12 new cases and all
seven WOFF1 cases are ahead. The 11 slower cases use large Noto Sans
or Serif CJK CFF outlines. The workload uses 20 px, five warmups, and
nine interleaved batches of 31 opens or seven for files at least 10 MB.
Swag output fingerprints match the previous build across the corpus.
[Raw timings and all fixtures](font-decode-linux-71-cases.json)

| New fixture | Character | Swag open and render (µs) | Pillow (µs) |
| --- | ---: | ---: | ---: |
| `NotoSansKR-Variable.ttf` | U+AC01 | 686.0 | 3086.0 |
| `NotoSansKR-Variable.ttf` | U+97D3 | 780.5 | 3150.0 |
| `NotoSansHK-Variable.ttf` | U+20021 | 894.9 | 3028.9 |
| `NotoSansHK-Variable.ttf` | U+9AA8 | 843.9 | 2675.7 |
| `NotoSerifJP-Variable.ttf` | U+3042 | 941.6 | 3160.8 |
| `NotoSerifJP-Variable.ttf` | U+9AD8 | 938.0 | 3144.8 |
| `NotoSerifKR-Variable.ttf` | U+D55C | 1722.1 | 3239.2 |
| `NotoSerifKR-Variable.ttf` | U+91D1 | 1716.5 | 2701.2 |
| `LXGWWenKaiTC-Regular.ttf` | U+570B | 1590.8 | 2683.6 |
| `LXGWWenKaiTC-Regular.ttf` | U+9F8D | 1642.1 | 3619.6 |
| `Iansui-Regular.ttf` | U+81FA | 1239.7 | 2852.6 |
| `Iansui-Regular.ttf` | U+9F9C | 1168.4 | 3185.3 |

## Scope font selection digest

Loading a single-face font skips the persisted collection selection lookup
and its full-file SHA-256. Collections reuse the same digest as the Pixel
typeface cache identity and avoid a second full-file checksum pass. The
selected face reuses the metadata read while building the face picker.

The native Scope Release builds compare with `0cacd90c1f` using the same
SHA-accelerated Core. Each of 11 interleaved batches starts a fresh process
and times the background content load with one worker and a warm filesystem
cache. Face, glyph, page, and named-glyph counts match. Twelve native viewer
tests pass, including selection persistence and invalid TTC members.
[Raw timings](font-scope-linux-selection-digest.json)

| Fixture | Scope load before (ms) | After |
| --- | ---: | ---: |
| `NotoSansCJKjp-Regular.otf` | 43.541 | 23.145 |
| `NotoSerifCJKjp-Regular.otf` | 71.980 | 32.641 |
| `NotoSansCJK-Regular.ttc` | 71.059 | 48.680 |
| `NotoSerifCJK-Regular.ttc` | 78.798 | 73.211 |
| `NotoSansSC-Variable.ttf` | 63.023 | 19.904 |
| `NotoSansKR-Variable.ttf` | 27.749 | 11.239 |
| `GowunBatang-Regular.ttf` | 58.338 | 49.972 |
| `LXGWWenKaiTC-Regular.ttf` | 107.040 | 89.891 |
| `Lato-Regular.ttf` | 0.972 | 0.698 |
| `SourceCodePro-Regular.otf` | 1.780 | 1.183 |

## Glyph names shared by a retained font source

TrueType faces that share a validated `post` range and glyph count reuse
the forward glyph names and their lazily built reverse index. Both indexes
stay with the source until its last face closes.

The comparison with `0cacd90c1f` uses nine interleaved batches of 251
source reopens on one CPU at 20 px. Loading falls by 65–79% on the five
static CJK fonts with large custom name tables. Faces without custom
names serve as controls. Source reloads preserve the glyph indices,
advances, dimensions and bitmap fingerprints in all measured cases.
[Raw timings and pathname controls](font-decode-linux-post-names.json)

| Fixture | Character | Open before (µs) | After | Open and render before (µs) | After |
| --- | ---: | ---: | ---: | ---: | ---: |
| `DejaVuSans.ttf` | U+0041 | 33.55 | 15.97 | 37.92 | 19.81 |
| `ZenKakuGothicNew-Regular.ttf` | U+6C38 | 34.97 | 11.67 | 56.19 | 32.22 |
| `MaShanZheng-Regular.ttf` | U+9F99 | 33.11 | 11.75 | 83.71 | 63.59 |
| `GowunBatang-Regular.ttf` | U+D55C | 49.73 | 14.41 | 94.75 | 59.95 |
| `LXGWWenKaiTC-Regular.ttf` | U+570B | 86.55 | 18.28 | 130.96 | 73.61 |
| `LXGWWenKaiTC-Regular.ttf` | U+9F8D | 85.41 | 19.44 | 148.02 | 76.68 |
| `Iansui-Regular.ttf` | U+81FA | 65.87 | 16.27 | 122.61 | 67.88 |
| `Iansui-Regular.ttf` | U+9F9C | 60.62 | 17.58 | 119.98 | 80.42 |

## Packed outline offset validation

The `loca` and CFF INDEX validators unpack one SIMD block at a time.
Each comparison brings forward the last offset of the previous block.
The vector and scalar paths reject descending pairs in the same order,
including pairs that cross a block boundary.

The kernel comparison with `0cacd90c1f` uses 21 interleaved batches of
501 validations. Across the three widths, scans of 60,000 pairs take
11–18% less time. The real-font workload also compares pathnames and
retained-source loads, and matches Swag glyph fingerprints in every case.
[Raw kernel and font timings](font-decode-linux-packed-offsets.json)

| Bytes per offset | Offset pairs | Before (µs) | After |
| ---: | ---: | ---: | ---: |
| 2 | 255 | 0.085 | 0.075 |
| 2 | 4096 | 0.854 | 0.626 |
| 2 | 16384 | 2.992 | 2.413 |
| 2 | 60000 | 11.253 | 9.172 |
| 3 | 255 | 0.104 | 0.106 |
| 3 | 4096 | 1.340 | 1.258 |
| 3 | 16384 | 5.225 | 4.745 |
| 3 | 60000 | 20.391 | 17.609 |
| 4 | 255 | 0.110 | 0.104 |
| 4 | 4096 | 1.426 | 1.201 |
| 4 | 16384 | 5.789 | 5.041 |
| 4 | 60000 | 20.075 | 17.799 |

## Raster scanline bands

The grayscale rasterizer filters edges once for each eight-row band
of a tall glyph. Scanlines preserve contour order and the original
coverage arithmetic. Small bitmaps use one band with the full edge list.

The comparison with `0cacd90c1f` uses nine interleaved batches of three
passes. Both builds match the outline and bitmap fingerprints on 15
fonts at both pixel sizes, including supplied TrueType and public CFF
fonts. The 64 px cases improve by 12–50%. A 15-batch repeat confirms
the gain on the large cases. Zen Kaku Gothic New at 24 px moves from
an 11% increase in the broad run to an 18% improvement in the repeat.
[Raw timings, repeat, and golden results](font-glyph-linux-raster-bands.json)

| Fixture | Face | Pixels | Load and render before (µs/glyph) | After |
| --- | ---: | ---: | ---: | ---: |
| `DejaVuSans.ttf` | 0 | 24 | 7.838 | 7.963 |
| `DejaVuSans.ttf` | 0 | 64 | 17.362 | 12.696 |
| `GowunBatang-Regular.ttf` | 0 | 24 | 76.062 | 55.677 |
| `GowunBatang-Regular.ttf` | 0 | 64 | 179.821 | 97.373 |
| `Lato-Regular.ttf` | 0 | 24 | 12.214 | 12.166 |
| `Lato-Regular.ttf` | 0 | 64 | 30.633 | 21.311 |
| `MaShanZheng-Regular.ttf` | 0 | 24 | 106.344 | 80.685 |
| `MaShanZheng-Regular.ttf` | 0 | 64 | 255.675 | 128.972 |
| `NotoSansJP-Variable.ttf` | 0 | 24 | 32.326 | 25.894 |
| `NotoSansJP-Variable.ttf` | 0 | 64 | 73.583 | 49.693 |
| `NotoSansSC-Variable.ttf` | 0 | 24 | 33.342 | 28.595 |
| `NotoSansSC-Variable.ttf` | 0 | 64 | 78.646 | 54.570 |
| `NotoSansTC-Variable.ttf` | 0 | 24 | 33.727 | 28.055 |
| `NotoSansTC-Variable.ttf` | 0 | 64 | 81.421 | 54.478 |
| `OpenSans-Regular.ttf` | 0 | 24 | 14.700 | 13.989 |
| `OpenSans-Regular.ttf` | 0 | 64 | 35.666 | 25.514 |
| `ZenKakuGothicNew-Regular.ttf` | 0 | 24 | 30.163 | 33.556 |
| `ZenKakuGothicNew-Regular.ttf` | 0 | 64 | 71.458 | 48.368 |
| `NimbusSans-Regular.otf` | 0 | 24 | 10.126 | 9.988 |
| `NimbusSans-Regular.otf` | 0 | 64 | 21.852 | 17.986 |
| `NotoSansCJK-Regular.ttc` | 1 | 24 | 26.800 | 24.149 |
| `NotoSansCJK-Regular.ttc` | 1 | 64 | 56.111 | 41.408 |
| `NotoSansCJKjp-Regular.otf` | 0 | 24 | 27.730 | 21.861 |
| `NotoSansCJKjp-Regular.otf` | 0 | 64 | 58.230 | 40.983 |
| `NotoSerifCJK-Regular.ttc` | 4 | 24 | 46.982 | 39.596 |
| `NotoSerifCJK-Regular.ttc` | 4 | 64 | 90.723 | 65.551 |
| `NotoSerifCJKjp-Regular.otf` | 0 | 24 | 53.335 | 38.601 |
| `NotoSerifCJKjp-Regular.otf` | 0 | 64 | 97.899 | 64.526 |
| `SourceSans3-Regular.otf` | 0 | 24 | 11.418 | 11.327 |
| `SourceSans3-Regular.otf` | 0 | 64 | 23.972 | 21.086 |

Native TrueType tests and the GUI, Pixel, and Swag Vault golden suites
pass. The baseline and candidate both report the same Swag Capture
borrow-check diagnostic and the same six Swag Scope golden failures.
All seven Scope PNGs produced by those failures are byte-identical
between the two builds.

## Scope glyph-name index

The picker borrows glyph-name strings from the displayed face. It
keeps the same name comparison and sorted lookup. Changing collection
members rebuilds the name index before releasing the old face.

The comparison with `72139801f6` uses 11 fresh-process loads per variant
with one worker. The two large named TrueType controls improve by 20%
and 30%. Face, glyph, page and name counts match in all ten cases. The
sorted name and glyph ID CRC-64 also matches in every case.
[Raw timings and fingerprints](font-scope-linux-borrowed-names.json)

| Fixture | Scope load before (ms) | After |
| --- | ---: | ---: |
| `NotoSansCJKjp-Regular.otf` | 13.778 | 13.870 |
| `NotoSerifCJKjp-Regular.otf` | 18.476 | 18.787 |
| `NotoSansCJK-Regular.ttc` | 27.917 | 29.796 |
| `NotoSerifCJK-Regular.ttc` | 40.237 | 38.724 |
| `NotoSansSC-Variable.ttf` | 14.423 | 13.712 |
| `NotoSansKR-Variable.ttf` | 6.963 | 7.300 |
| `GowunBatang-Regular.ttf` | 24.510 | 19.720 |
| `LXGWWenKaiTC-Regular.ttf` | 53.915 | 37.711 |
| `Lato-Regular.ttf` | 0.633 | 0.704 |
| `SourceCodePro-Regular.otf` | 1.133 | 0.837 |

## Direct WOFF1 table output

Parallel WOFF1 tasks inflate into their assigned ranges in the final
sfnt buffer. The fixed-output zlib entry point shares checksum and
limit validation with the growable decoder. The final match uses a
bounded copy when the target has less than one vector of slack.

The comparison with `0cacd90c1f` uses two requested workers on two
logical CPUs, three warmups and nine interleaved batches of five
opens. Three CJK variable WOFF1 fixtures take 15–20% less time. Seven
fresh-process samples measure peak RSS with the same worker count.
Glyph indices, advances, bitmap dimensions and checksums agree across
all seven WOFF1 cases.
[Raw timings, one-worker controls, and peak RSS](font-decode-linux-woff-direct.json)

| Fixture | Open and render before (ms) | After | Peak RSS before (MiB) | After |
| --- | ---: | ---: | ---: | ---: |
| `DejaVuSans.woff` | 3.546 | 3.472 | — | — |
| `Inter-Variable.woff` | 4.360 | 3.995 | — | — |
| `SourceSans3-Regular.woff` | 1.775 | 1.723 | — | — |
| `NotoSansCJKjp-Regular.woff` | 100.607 | 99.702 | 46.2 | 30.5 |
| `NotoSansSC-Variable.woff` | 74.373 | 63.452 | 46.3 | 29.5 |
| `NotoSansJP-Variable.woff` | 37.035 | 31.008 | 25.6 | 16.5 |
| `NotoSansTC-Variable.woff` | 55.140 | 44.278 | 31.7 | 20.3 |

The native compression cases pass in Release and Release Safe.
The TrueType and selected Pixel PNG and collection cases pass.

## Compact CFF CID maps

Regional CFF subsets can assign many glyphs to nonconsecutive CIDs.
Dense-enough CID ranges use 16-bit glyph indices in a direct lookup
table. The identity fast path and the sparse hash lookup cover the
other distributions. Duplicate CIDs retain the last glyph.

Four pinned Noto regional subsets add eight cases, for 79 cases across
62 files. The comparison with `0cacd90c1f` uses 11 interleaved batches on
one CPU. Opening a fresh source after the font bytes have been acquired
improves by 60–75%. Opening from the pathname improves by 39–55%, with
FreeType 2.14.3 ahead on all eight pathname cases. Direct CID lookups
run in 4.7–5.9 ns compared with 18.1–23.8 ns before. The mapping
fingerprints cover all 65,536 CID values in each file. Rendered glyph
indices, advances, dimensions and bitmap checksums match across builds.
[Raw opening and lookup timings](font-decode-linux-cff-cid-map.json)

| New fixture | Character | Pathname before (ms) | After | FreeType (ms) | Fresh source before (ms) | After |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `NotoSansJP-Regular.otf` | U+3042 | 2.163 | 0.975 | 0.518 | 2.068 | 0.636 |
| `NotoSansJP-Regular.otf` | U+65E5 | 2.041 | 1.032 | 0.491 | 1.690 | 0.628 |
| `NotoSansHK-Regular.otf` | U+9AA8 | 2.374 | 1.451 | 0.502 | 2.171 | 0.669 |
| `NotoSansHK-Regular.otf` | U+9F8D | 2.378 | 1.357 | 0.500 | 1.959 | 0.743 |
| `NotoSerifKR-Regular.otf` | U+D55C | 2.457 | 1.261 | 0.628 | 1.877 | 0.469 |
| `NotoSerifKR-Regular.otf` | U+570B | 2.977 | 1.425 | 0.587 | 1.662 | 0.509 |
| `NotoSerifSC-Regular.otf` | U+4E2D | 3.377 | 2.009 | 0.551 | 1.919 | 0.773 |
| `NotoSerifSC-Regular.otf` | U+6587 | 3.266 | 1.971 | 0.566 | 2.278 | 0.745 |

## Packed CFF charset ranges

Formats 1 and 2 check each whole record once and read its already
bounded bytes directly. The glyph-count check and the identity
shortcut still apply. Functional tests cover truncated records in
both formats.

The four regional subset fixtures compare with `74eda41449` in
11 interleaved batches on one CPU. Fresh-source opening takes 58–72%
less time. Pathname opening improves by 24–46%. Noto Sans JP takes
575–590 µs from a pathname, compared with 469–487 µs in FreeType
2.14.3. All eight glyph fingerprints match across the Swag builds.
[Raw timings](font-decode-linux-cff-charset-ranges.json)

| Fixture | Character | Open before (µs) | After | FreeType | Fresh source before (µs) | After |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `NotoSansJP-Regular.otf` | U+3042 | 1070.4 | 575.0 | 486.5 | 658.0 | 187.6 |
| `NotoSansJP-Regular.otf` | U+65E5 | 1079.2 | 589.9 | 468.7 | 653.7 | 180.3 |
| `NotoSansHK-Regular.otf` | U+9AA8 | 1386.5 | 786.2 | 507.7 | 725.0 | 214.4 |
| `NotoSansHK-Regular.otf` | U+9F8D | 1261.6 | 800.2 | 540.0 | 754.6 | 210.1 |
| `NotoSerifKR-Regular.otf` | U+D55C | 1231.1 | 880.3 | 634.8 | 502.0 | 192.5 |
| `NotoSerifKR-Regular.otf` | U+570B | 1221.8 | 928.3 | 612.4 | 489.8 | 205.9 |
| `NotoSerifSC-Regular.otf` | U+4E2D | 1993.7 | 1355.2 | 552.0 | 848.0 | 277.7 |
| `NotoSerifSC-Regular.otf` | U+6587 | 1857.7 | 1345.7 | 556.9 | 851.4 | 262.2 |

## Scope character block coverage

Scope counts the mapped characters in its five displayed Unicode
blocks directly from the character map. Both opening a font and
switching members use this path.

The comparison with `22ce80bf08` uses 11 interleaved fresh-process
opens with one worker. A second timed loop repeats coverage counting
101 times on the loaded face. Counting takes 1.9–12.7 µs, down from
272.5–413.1 µs. Every block count matches in all ten cases. The
native font viewer tests and the Scope Release build pass.
[Raw timings and complete block counts](font-scope-linux-character-coverage.json)

| Fixture | Coverage before (µs) | After | Scope open before (ms) | After |
| --- | ---: | ---: | ---: | ---: |
| `NotoSansCJKjp-Regular.otf` | 395.12 | 4.76 | 14.712 | 15.018 |
| `NotoSerifCJKjp-Regular.otf` | 397.60 | 5.19 | 21.369 | 21.599 |
| `NotoSansCJK-Regular.ttc` | 387.05 | 5.45 | 31.769 | 31.168 |
| `NotoSerifCJK-Regular.ttc` | 383.89 | 4.67 | 42.101 | 40.789 |
| `NotoSansSC-Variable.ttf` | 347.21 | 5.21 | 14.883 | 14.748 |
| `NotoSansKR-Variable.ttf` | 364.98 | 4.82 | 8.693 | 8.592 |
| `GowunBatang-Regular.ttf` | 363.64 | 4.41 | 21.267 | 20.879 |
| `LXGWWenKaiTC-Regular.ttf` | 413.10 | 12.66 | 40.579 | 39.104 |
| `Lato-Regular.ttf` | 273.40 | 1.94 | 0.725 | 0.361 |
| `SourceCodePro-Regular.otf` | 272.51 | 2.56 | 0.950 | 0.606 |

## Signed-distance field row bounds

Each SDF row keeps the edges that can affect the encoded distance.
Edges farther away vertically than the spread plus one pixel can
only produce a saturated byte. Every crossing edge remains available
for the winding test.

The comparison with `636be06fdf` uses seven interleaved batches of
three passes. Loading and SDF rendering at 64 px with spread 8 takes
64–74% less time across seven fonts. The two spread-64 controls take
16–18% less time. Outline and SDF byte fingerprints match for all
16 cases. The native scalar reference test also matches every pixel.
[Raw timings and fingerprints](font-glyph-linux-sdf-rows.json)

| Fixture | Pixels | Spread | Load and render before (µs/glyph) | After |
| --- | ---: | ---: | ---: | ---: |
| `Lato-Regular.ttf` | 24 | 8 | 262.35 | 173.61 |
| `Lato-Regular.ttf` | 64 | 8 | 1279.63 | 455.43 |
| `Lato-Regular.ttf` | 24 | 64 | 5530.44 | 4634.59 |
| `OpenSans-Regular.ttf` | 24 | 8 | 296.63 | 147.87 |
| `OpenSans-Regular.ttf` | 64 | 8 | 1355.46 | 419.76 |
| `GowunBatang-Regular.ttf` | 24 | 8 | 1831.09 | 890.42 |
| `GowunBatang-Regular.ttf` | 64 | 8 | 10725.92 | 2805.03 |
| `MaShanZheng-Regular.ttf` | 24 | 8 | 2778.31 | 1395.63 |
| `MaShanZheng-Regular.ttf` | 64 | 8 | 16792.95 | 4350.61 |
| `NotoSansJP-Variable.ttf` | 24 | 8 | 746.79 | 421.23 |
| `NotoSansJP-Variable.ttf` | 64 | 8 | 3848.19 | 1117.88 |
| `NotoSansCJKjp-Regular.otf` | 24 | 8 | 567.23 | 294.18 |
| `NotoSansCJKjp-Regular.otf` | 64 | 8 | 2774.57 | 800.30 |
| `NotoSansCJKjp-Regular.otf` | 24 | 64 | 8413.82 | 6869.89 |
| `NotoSerifCJKjp-Regular.otf` | 24 | 8 | 759.92 | 404.07 |
| `NotoSerifCJKjp-Regular.otf` | 64 | 8 | 3956.62 | 1124.58 |

## Medium Linux font reads

The minimum size for parallel positional reads moves from 8 MiB to
4 MiB. The threshold applies to each read, including compacted ranges
of a collection member or a default variable instance.

The table uses 33 interleaved batches of first opens from warm
filesystem caches with four requested workers on four logical CPUs.
The six newly parallelized cases take 26–41% less time with lazy
worker startup and 42–47% less time with prestarted workers, with
small and already-parallel cases included as controls. Glyph
indices, advances, dimensions and checksums match across builds.
[Raw timings, initial run, and targeted repeat](font-decode-linux-medium-reads.json)

| Fixture | Lazy before (ms) | After | Prestarted before (ms) | After | FreeType first (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `NotoSansCJKjp-Regular.otf` | 4.908 | 5.870 | 4.997 | 4.605 | 1.475 |
| `MaShanZheng-Regular.ttf` | 3.988 | 2.418 | 3.842 | 2.131 | 1.506 |
| `GowunBatang-Regular.ttf` | 3.199 | 2.803 | 2.874 | 2.721 | 1.129 |
| `NotoSansJP-Variable.ttf` | 4.146 | 2.676 | 3.982 | 2.275 | 2.266 |
| `NotoSansSC-Variable.ttf` | 3.959 | 4.154 | 3.752 | 4.223 | 2.429 |
| `NotoSansHK-Variable.ttf` | 4.235 | 2.771 | 4.340 | 2.533 | 2.088 |
| `NotoSansJP-Regular.otf` | 3.055 | 2.196 | 3.146 | 1.761 | 0.864 |
| `NotoSansHK-Regular.otf` | 3.706 | 2.734 | 3.847 | 2.210 | 0.926 |
| `NotoSerifKR-Regular.otf` | 4.921 | 2.891 | 4.977 | 2.614 | 1.259 |
| `NotoSerifSC-Regular.otf` | 3.796 | 3.978 | 3.604 | 3.312 | 1.104 |
| `OpenSans-Regular.ttf` | 0.158 | 0.157 | 0.202 | 0.208 | 0.190 |

The 51-batch targeted repeat measures Noto Sans CJK JP at 4.864 ms
before and 4.721 ms after for lazy startup. The corresponding
prestarted results are 5.027 and 5.461 ms. That control already
qualified for parallel reads at 8 MiB.

## Signed-distance field row winding

A crossing contributes winding up to the first pixel center it
excludes. The rasterizer accumulates those changes while visiting
the row. Each crossing is evaluated once per row.

Seven interleaved batches compare with `94962d20e1` on the same
seven fonts. At 64 px and spread 8, loading and rendering takes
8–22% less time. The spread-64 controls improve by 11–14%. Every
sample has the same outline and bitmap fingerprint as the baseline.
The native tests also compare the complete SDF with scalar winding.
[Raw timings and fingerprints](font-glyph-linux-sdf-winding.json)

| Fixture | Pixels | Spread | Load and render before (µs/glyph) | After |
| --- | ---: | ---: | ---: | ---: |
| `Lato-Regular.ttf` | 24 | 8 | 164.89 | 135.45 |
| `Lato-Regular.ttf` | 64 | 8 | 511.51 | 398.01 |
| `Lato-Regular.ttf` | 24 | 64 | 4643.11 | 4149.07 |
| `OpenSans-Regular.ttf` | 24 | 8 | 155.78 | 131.05 |
| `OpenSans-Regular.ttf` | 64 | 8 | 427.59 | 354.04 |
| `GowunBatang-Regular.ttf` | 24 | 8 | 906.32 | 742.67 |
| `GowunBatang-Regular.ttf` | 64 | 8 | 2684.02 | 2213.27 |
| `MaShanZheng-Regular.ttf` | 24 | 8 | 1417.40 | 1192.63 |
| `MaShanZheng-Regular.ttf` | 64 | 8 | 4261.30 | 3522.97 |
| `NotoSansJP-Variable.ttf` | 24 | 8 | 403.45 | 336.36 |
| `NotoSansJP-Variable.ttf` | 64 | 8 | 1119.48 | 930.20 |
| `NotoSansCJKjp-Regular.otf` | 24 | 8 | 274.56 | 254.22 |
| `NotoSansCJKjp-Regular.otf` | 64 | 8 | 812.19 | 748.31 |
| `NotoSansCJKjp-Regular.otf` | 24 | 64 | 6737.09 | 5819.02 |
| `NotoSerifCJKjp-Regular.otf` | 24 | 8 | 399.34 | 352.41 |
| `NotoSerifCJKjp-Regular.otf` | 64 | 8 | 1105.43 | 929.19 |

## Glyph locations shared by a retained font source

A retained source caches the validation and final offset of each
packed glyph location range. Each face still verifies that the final
offset fits its own outline table. Standalone opens validate their
independent bytes as before.

The comparison with `9a7d0f5cdc` uses seven interleaved batches of 251
reopens on one CPU. Opening the CJK TrueType fixtures falls by 19–56%.
Both builds select the same glyphs and preserve the advance, bitmap
dimensions and CRC-64 in every case. The native tests include two
faces that share offsets and declare different outline lengths.
[Raw timings and pathname controls](font-decode-linux-shared-loca.json)

| Fixture | Character | Open before (µs) | After | Open and render before (µs) | After |
| --- | ---: | ---: | ---: | ---: | ---: |
| `DejaVuSans.ttf` | U+0041 | 21.23 | 17.81 | 26.60 | 23.31 |
| `Inter-Variable.ttf` | U+0057 | 12.89 | 12.95 | 25.24 | 23.77 |
| `ZenKakuGothicNew-Regular.ttf` | U+6C38 | 16.67 | 11.24 | 40.41 | 36.77 |
| `MaShanZheng-Regular.ttf` | U+9F99 | 15.14 | 12.26 | 80.42 | 79.89 |
| `GowunBatang-Regular.ttf` | U+D55C | 18.26 | 12.19 | 67.08 | 63.19 |
| `NotoSansJP-Variable.ttf` | U+2000B | 24.78 | 13.82 | 48.04 | 35.84 |
| `NotoSansTC-Variable.ttf` | U+9F8D | 26.03 | 14.30 | 57.53 | 48.96 |
| `NotoSansSC-Variable.ttf` | U+9F8D | 32.27 | 14.49 | 62.84 | 40.86 |
| `NotoSansKR-Variable.ttf` | U+AC01 | 30.32 | 14.43 | 45.59 | 28.26 |
| `NotoSansKR-Variable.ttf` | U+97D3 | 29.45 | 14.00 | 46.13 | 30.08 |
| `NotoSansHK-Variable.ttf` | U+20021 | 25.30 | 14.79 | 49.30 | 38.34 |
| `NotoSansHK-Variable.ttf` | U+9AA8 | 25.39 | 14.53 | 40.66 | 27.45 |
| `NotoSerifJP-Variable.ttf` | U+3042 | 28.14 | 15.34 | 75.01 | 61.51 |
| `NotoSerifJP-Variable.ttf` | U+9AD8 | 24.91 | 15.52 | 49.42 | 38.76 |
| `NotoSerifKR-Variable.ttf` | U+D55C | 29.61 | 17.56 | 74.46 | 64.72 |
| `NotoSerifKR-Variable.ttf` | U+91D1 | 31.33 | 15.45 | 57.64 | 40.08 |
| `LXGWWenKaiTC-Regular.ttf` | U+570B | 23.98 | 11.37 | 80.06 | 66.47 |
| `LXGWWenKaiTC-Regular.ttf` | U+9F8D | 25.05 | 11.07 | 92.10 | 76.61 |
| `Iansui-Regular.ttf` | U+81FA | 23.87 | 14.64 | 81.90 | 78.43 |
| `Iansui-Regular.ttf` | U+9F9C | 22.41 | 13.49 | 87.10 | 78.93 |
| `Lato-Regular.ttf` | U+0041 | 14.88 | 15.47 | 22.43 | 23.41 |
| `OpenSans-Regular.ttf` | U+0041 | 12.71 | 11.87 | 18.72 | 19.73 |

## PostScript Type 1 decoding

Type 1 decrypts directly into its output buffer, uses the byte
substring search for dictionary markers, and moves each decoded
charstring into the font. Bare programs can borrow their input while
parsing. The common leading `hsbw` sequence supplies the advance
directly. Computed widths and other operators use the interpreter.

Three pinned URW Type 1 files add six cases, for 85 cases on 65 files.
All six take 22–28% less time to open and render than `9a7d0f5cdc`,
and all six are ahead of Pillow 12.3.0 with FreeType 2.14.3. The test
uses 13 interleaved batches of 41 opens on one CPU. The Swag builds
match glyph IDs, advances, dimensions and bitmap checksums. Both
engines select the same PostScript glyph names.
[Raw timings and glyph names](font-decode-linux-type1.json)

| Fixture | Character | Before (µs) | Buffer and scan changes | With width fast path | Pillow |
| --- | ---: | ---: | ---: | ---: | ---: |
| `NimbusSans-Regular.t1` | U+0041 | 1348.6 | 1020.2 | 975.6 | 1250.8 |
| `NimbusSans-Regular.t1` | U+0067 | 1293.1 | 1030.4 | 998.0 | 1295.4 |
| `NimbusMonoPS-Regular.t1` | U+0057 | 1642.3 | 1288.1 | 1245.8 | 1427.1 |
| `NimbusMonoPS-Regular.t1` | U+0069 | 1599.4 | 1267.6 | 1238.4 | 1456.6 |
| `P052-Roman.t1` | U+0067 | 1814.4 | 1429.1 | 1382.8 | 1667.2 |
| `P052-Roman.t1` | U+0045 | 1876.3 | 1441.8 | 1398.0 | 1582.2 |

The timing set uses Latin Type 1 glyphs. The Standard Symbols PS
trial for U+03A9 has no Unicode glyph in Swag and is excluded from
the timing set.

## Type 1 programs shared by a retained font source

Retained Type 1 faces borrow the same immutable decrypted program.
Opening from a pathname still creates an independent program.

Eleven interleaved batches on one CPU show 93–95% less reopen time
than `e56d492497` for the three URW fonts. Face opening includes size
setup. Glyph indices, advances, dimensions and CRC-64 agree in all
six cases. A native test opens two faces, destroys the source and the
first face, and reads the advance and name from the surviving face.
[Raw timings and pathname controls](font-decode-linux-type1-source.json)

| Fixture | Character | Open before (µs) | After |
| --- | ---: | ---: | ---: |
| `NimbusSans-Regular.t1` | U+0041 | 1282.08 | 91.82 |
| `NimbusSans-Regular.t1` | U+0067 | 1309.35 | 90.90 |
| `NimbusMonoPS-Regular.t1` | U+0057 | 1561.89 | 102.96 |
| `NimbusMonoPS-Regular.t1` | U+0069 | 1641.66 | 98.80 |
| `P052-Roman.t1` | U+0067 | 1717.55 | 95.16 |
| `P052-Roman.t1` | U+0045 | 1734.97 | 101.73 |

## Shared advances and Unicode maps for bare PostScript programs

A retained source builds charstring advances and its synthetic Unicode
map once for bare CFF and Type 1. The cached tables follow the source
allocator and stay alive as long as either face retains them.

Three CFF programs extracted from pinned public OTFs add six cases.
The corpus now has 91 cases on 68 files with the original attachments.
The comparison with `8fcc21a3bb` uses eleven interleaved batches of 251
reopens on one CPU. Retained openings take 1.1–1.4 µs across all
twelve cases. Each result keeps its glyph index, advance, bitmap
dimensions and CRC-64. The pathname runs include 31 opens per batch.
[Raw timings and pathname controls](font-decode-linux-program-tables.json)

| Fixture | Character | Open before (µs) | After |
| --- | ---: | ---: | ---: |
| `NimbusSans-Regular.t1` | U+0041 | 75.60 | 1.13 |
| `NimbusSans-Regular.t1` | U+0067 | 73.56 | 1.42 |
| `NimbusMonoPS-Regular.t1` | U+0057 | 73.71 | 1.31 |
| `NimbusMonoPS-Regular.t1` | U+0069 | 76.40 | 1.29 |
| `P052-Roman.t1` | U+0067 | 81.03 | 1.22 |
| `P052-Roman.t1` | U+0045 | 74.95 | 1.07 |
| `NimbusSans-Regular.cff` | U+0041 | 238.81 | 1.19 |
| `NimbusSans-Regular.cff` | U+0067 | 244.10 | 1.20 |
| `NimbusMonoPS-Regular.cff` | U+0057 | 287.59 | 1.35 |
| `NimbusMonoPS-Regular.cff` | U+0069 | 285.56 | 1.20 |
| `SourceSans3-Regular.cff` | U+0043 | 894.74 | 1.28 |
| `SourceSans3-Regular.cff` | U+0045 | 798.63 | 1.15 |

## CFF advances set in subroutines

Width-only execution now stops across the call chain when a subroutine
sets the glyph advance. Outline execution still visits the remaining
commands. The native test puts the move that sets the width two calls
deep and checks that outline decoding still detects a truncated operand.

Across 13 interleaved batches of 61 pathname opens on one CPU, the
six bare CFF cases take 12–26% less time than `8fcc21a3bb`. The four
Nimbus cases are ahead of Pillow. Source Sans 3 is within 17% of the
reference. All glyph indices, advances, dimensions and CRC-64 match
between the Swag builds.
[Raw timings and fingerprints](font-decode-linux-cff-width.json)

| Fixture | Character | Open and render before (µs) | After | Pillow |
| --- | ---: | ---: | ---: | ---: |
| `NimbusSans-Regular.cff` | U+0041 | 257.28 | 219.97 | 279.45 |
| `NimbusSans-Regular.cff` | U+0067 | 268.56 | 229.82 | 302.21 |
| `NimbusMonoPS-Regular.cff` | U+0057 | 288.77 | 218.75 | 307.48 |
| `NimbusMonoPS-Regular.cff` | U+0069 | 292.37 | 217.50 | 301.88 |
| `SourceSans3-Regular.cff` | U+0043 | 812.75 | 708.20 | 616.29 |
| `SourceSans3-Regular.cff` | U+0045 | 805.35 | 704.66 | 605.52 |

## Signed-distance field geometry shared by a scanline

The row pass prepares each edge's direction, squared length, and
vertical dot product while collecting winding changes. Every sample
on the row reuses that geometry, with the same projection and
distance arithmetic as the previous renderer.

Seven interleaved batches compare with `6b8fa57dc1` on one CPU.
The seven 64 px cases take 14–20% less time to load and render.
The two spread-64 controls improve by about 20%. Every outline and
bitmap fingerprint agrees, including the odd-width tails. The
native test compares the bitmap with a scalar reference.
[Raw timings and fingerprints](font-glyph-linux-sdf-geometry.json)

| Fixture | Pixels | Spread | Load and render before (µs/glyph) | After |
| --- | ---: | ---: | ---: | ---: |
| `Lato-Regular.ttf` | 24 | 8 | 126.68 | 119.53 |
| `Lato-Regular.ttf` | 64 | 8 | 364.70 | 311.81 |
| `Lato-Regular.ttf` | 24 | 64 | 3707.11 | 2951.22 |
| `OpenSans-Regular.ttf` | 24 | 8 | 119.72 | 102.27 |
| `OpenSans-Regular.ttf` | 64 | 8 | 328.63 | 284.08 |
| `GowunBatang-Regular.ttf` | 24 | 8 | 680.04 | 568.25 |
| `GowunBatang-Regular.ttf` | 64 | 8 | 2076.16 | 1658.43 |
| `MaShanZheng-Regular.ttf` | 24 | 8 | 1095.27 | 909.13 |
| `MaShanZheng-Regular.ttf` | 64 | 8 | 3183.13 | 2596.29 |
| `NotoSansJP-Variable.ttf` | 24 | 8 | 298.04 | 251.75 |
| `NotoSansJP-Variable.ttf` | 64 | 8 | 850.09 | 696.10 |
| `NotoSansCJKjp-Regular.otf` | 24 | 8 | 230.67 | 202.60 |
| `NotoSansCJKjp-Regular.otf` | 64 | 8 | 651.07 | 552.09 |
| `NotoSansCJKjp-Regular.otf` | 24 | 64 | 5294.61 | 4211.53 |
| `NotoSerifCJKjp-Regular.otf` | 24 | 8 | 322.44 | 263.40 |
| `NotoSerifCJKjp-Regular.otf` | 64 | 8 | 873.40 | 715.67 |

## Packed Type 1 charstrings and borrowed glyph names

Glyph names refer to the font's decrypted dictionary. Charstrings and
local subroutines share one byte buffer, addressed by offsets. The
buffer grows independently of the offsets, and faces still own the
decrypted data through their program.

Eleven interleaved batches of 31 opens on one CPU compare with
`9734ba70c4`. Pathname open times fall by 21–27% across the six URW
cases. Retained-source times remain around 1 µs. Glyph IDs, advances,
dimensions and CRC-64 agree, and the native allocator test checks
that the last face releases the program.
[Raw timings and retained-source controls](font-decode-linux-type1-storage.json)

| Fixture | Character | Pathname open before (µs) | After |
| --- | ---: | ---: | ---: |
| `NimbusSans-Regular.t1` | U+0041 | 1072.93 | 783.53 |
| `NimbusSans-Regular.t1` | U+0067 | 1046.37 | 791.16 |
| `NimbusMonoPS-Regular.t1` | U+0057 | 1277.48 | 1011.67 |
| `NimbusMonoPS-Regular.t1` | U+0069 | 1315.26 | 964.01 |
| `P052-Roman.t1` | U+0067 | 1401.91 | 1100.58 |
| `P052-Roman.t1` | U+0045 | 1501.79 | 1089.82 |

## Literal width prefixes in bare CFF

The width reader handles literal operands and local or global subroutine
calls up to the operator that sets the advance. Arithmetic and other
commands use the full interpreter. Glyph drawing uses the existing
outline interpreter.

Thirteen interleaved batches with 61 pathname opens on one CPU compare
with `191b224582`. The six cases take 16–19% less time to open and
render, and all six are ahead of Pillow in this run. The Swag builds
agree on every reported glyph fingerprint and on all 4,188 advances
in the three programs. The native tests cover nested calls, signed
literals, fixed point, default widths and arithmetic fallback.
[Raw timings, fingerprints and advance checksums](font-decode-linux-cff-width-prefix.json)

| Fixture | Character | Open and render before (µs) | After | Pillow |
| --- | ---: | ---: | ---: | ---: |
| `NimbusSans-Regular.cff` | U+0041 | 225.61 | 181.97 | 276.49 |
| `NimbusSans-Regular.cff` | U+0067 | 227.61 | 191.14 | 309.80 |
| `NimbusMonoPS-Regular.cff` | U+0057 | 217.29 | 177.87 | 317.16 |
| `NimbusMonoPS-Regular.cff` | U+0069 | 223.63 | 182.28 | 290.46 |
| `SourceSans3-Regular.cff` | U+0043 | 723.97 | 594.05 | 618.90 |
| `SourceSans3-Regular.cff` | U+0045 | 709.19 | 592.83 | 613.85 |

## Additional Japanese and Korean TrueType fixtures

Klee One, Sawarabi Gothic, Shippori Mincho and Gothic A1 add eight
cases on four pinned public fonts. The corpus now covers 99 cases on
72 files. The added glyphs include kana, Hangul and ideographs.

The timings are medians of nine interleaved batches of 31 pathname
opens on one CPU. Both Swag builds report identical glyph indices,
advances, dimensions and CRC-64. Six cases are ahead of Pillow.
Gothic A1 takes longer to open, and its 2.3 MB input copy accounts
for a median 216 µs in the phase probe before table validation.
[Raw timings and fixture hashes](font-decode-linux-cjk-static-extra.json)

| Fixture | Character | Swag before (µs) | Swag candidate | Pillow |
| --- | ---: | ---: | ---: | ---: |
| `KleeOne-Regular.ttf` | U+6C38 | 2085.41 | 1728.55 | 4705.11 |
| `KleeOne-Regular.ttf` | U+3042 | 2186.15 | 1947.57 | 4422.03 |
| `SawarabiGothic-Regular.ttf` | U+672C | 321.63 | 311.96 | 1715.63 |
| `SawarabiGothic-Regular.ttf` | U+9AA8 | 301.78 | 320.55 | 2188.69 |
| `ShipporiMincho-Regular.ttf` | U+5B57 | 2002.75 | 1461.16 | 3535.57 |
| `ShipporiMincho-Regular.ttf` | U+6F22 | 2105.92 | 1907.31 | 3998.37 |
| `GothicA1-Regular.ttf` | U+D55C | 377.89 | 408.10 | 272.04 |
| `GothicA1-Regular.ttf` | U+AC01 | 413.31 | 430.23 | 218.79 |

## Distinct previous winners for MSDF searches

Several distance channels can share the same winning edge. The next
sample measures each distinct previous winner once and skips those
edges in the remaining search. The existing tie order remains intact.

Five interleaved batches on one CPU give 4–21% lower load and render
times on the seven 64 px cases. Both spread-64 controls also improve.
Every outline and bitmap fingerprint agrees with `06343223ad`.
[Raw timings and fingerprints](font-glyph-linux-msdf-seeds.json)

| Fixture | Pixels | Spread | Load and render before (µs/glyph) | After |
| --- | ---: | ---: | ---: | ---: |
| `Lato-Regular.ttf` | 24 | 8 | 822.00 | 633.80 |
| `Lato-Regular.ttf` | 64 | 8 | 2991.70 | 2558.61 |
| `Lato-Regular.ttf` | 24 | 64 | 18268.46 | 14098.32 |
| `OpenSans-Regular.ttf` | 24 | 8 | 804.25 | 631.38 |
| `OpenSans-Regular.ttf` | 64 | 8 | 2978.39 | 2696.97 |
| `GowunBatang-Regular.ttf` | 24 | 8 | 3730.52 | 3678.98 |
| `GowunBatang-Regular.ttf` | 64 | 8 | 20668.80 | 18034.15 |
| `MaShanZheng-Regular.ttf` | 24 | 8 | 5988.22 | 5565.79 |
| `MaShanZheng-Regular.ttf` | 64 | 8 | 33492.69 | 26411.14 |
| `NotoSansJP-Variable.ttf` | 24 | 8 | 2336.34 | 2044.02 |
| `NotoSansJP-Variable.ttf` | 64 | 8 | 8436.86 | 8081.46 |
| `NotoSansCJKjp-Regular.otf` | 24 | 8 | 1435.45 | 1131.71 |
| `NotoSansCJKjp-Regular.otf` | 64 | 8 | 6405.66 | 5532.52 |
| `NotoSansCJKjp-Regular.otf` | 24 | 64 | 17282.39 | 15295.24 |
| `NotoSerifCJKjp-Regular.otf` | 24 | 8 | 1826.12 | 1623.72 |
| `NotoSerifCJKjp-Regular.otf` | 64 | 8 | 8633.64 | 7316.69 |

## Horizontal distance bounds for wide SDF glyphs

Wide glyphs measure distances in 16-pixel spans. A span keeps only
the row edges whose horizontal bounds can affect its quantized
distance. All row crossings still contribute to winding.

Seven interleaved batches compare with `06343223ad`. The five
64 px CJK cases take 29–48% less time, and the Latin cases at
64 px take 6–10% less time. Narrow cases and spread-64 controls
show smaller changes in both directions. The complete outline
and bitmap fingerprints agree in all cases.
[Raw timings and fingerprints](font-glyph-linux-sdf-tiles.json)

| Fixture | Pixels | Spread | Load and render before (µs/glyph) | After |
| --- | ---: | ---: | ---: | ---: |
| `Lato-Regular.ttf` | 24 | 8 | 117.04 | 110.12 |
| `Lato-Regular.ttf` | 64 | 8 | 305.88 | 275.68 |
| `Lato-Regular.ttf` | 24 | 64 | 3802.13 | 3711.24 |
| `OpenSans-Regular.ttf` | 24 | 8 | 106.16 | 109.10 |
| `OpenSans-Regular.ttf` | 64 | 8 | 293.42 | 275.01 |
| `GowunBatang-Regular.ttf` | 24 | 8 | 871.46 | 866.04 |
| `GowunBatang-Regular.ttf` | 64 | 8 | 1927.91 | 1374.41 |
| `MaShanZheng-Regular.ttf` | 24 | 8 | 1140.53 | 1201.12 |
| `MaShanZheng-Regular.ttf` | 64 | 8 | 3231.94 | 2259.91 |
| `NotoSansJP-Variable.ttf` | 24 | 8 | 260.63 | 256.80 |
| `NotoSansJP-Variable.ttf` | 64 | 8 | 951.14 | 490.79 |
| `NotoSansCJKjp-Regular.otf` | 24 | 8 | 236.99 | 198.30 |
| `NotoSansCJKjp-Regular.otf` | 64 | 8 | 812.88 | 420.09 |
| `NotoSansCJKjp-Regular.otf` | 24 | 64 | 5293.96 | 5265.24 |
| `NotoSerifCJKjp-Regular.otf` | 24 | 8 | 265.25 | 283.11 |
| `NotoSerifCJKjp-Regular.otf` | 64 | 8 | 724.13 | 499.34 |

## Hexadecimal Type 1 input

The PFA reader looks up hexadecimal digits and writes the decoded
bytes directly into reserved storage. The cipher keeps a wrapping
state, since bits above its low 16 never affect the output.

A pinned URW program converted to PFA adds two hexadecimal cases,
and a second converted to PFB adds two binary-container cases. The
corpus now has 103 cases on 74 files. Eleven interleaved batches
with 51 pathname opens on one CPU give 52–60% faster PFA opens.
The binary controls are included, with one Type 1 median rising
7%. Glyph indices, advances, dimensions and CRC-64 match on all
ten cases.
[Raw timings and format controls](font-decode-linux-type1-eexec.json)

| Fixture | Character | Pathname open before (µs) | After |
| --- | ---: | ---: | ---: |
| `NimbusSans-Regular.t1` | U+0041 | 723.31 | 705.02 |
| `NimbusSans-Regular.t1` | U+0067 | 1021.71 | 688.73 |
| `NimbusMonoPS-Regular.t1` | U+0057 | 1168.01 | 980.64 |
| `NimbusMonoPS-Regular.t1` | U+0069 | 994.81 | 935.17 |
| `P052-Roman.t1` | U+0067 | 1051.12 | 985.73 |
| `P052-Roman.t1` | U+0045 | 1057.97 | 1135.48 |
| `NimbusSans-Regular.pfa` | U+0041 | 3881.13 | 1873.20 |
| `NimbusSans-Regular.pfa` | U+0067 | 4175.67 | 1671.51 |
| `P052-Roman.pfb` | U+0067 | 1081.91 | 1279.26 |
| `P052-Roman.pfb` | U+0045 | 1063.15 | 1007.79 |

## Vertical metrics decoded when needed

Font opening validates and retains the packed vertical metrics table.
Loading a glyph reads its pair directly. A caller that asks for a
borrowed metric pointer materializes the entries once. The entries
retain their address for the lifetime of the face, and retained faces
share them when they use the same table.

Nine interleaved batches compare with `06343223ad`. Opening the full
Noto CJK faces from a newly created source takes 8–20% less time,
with acquisition outside the timed region. Pathname opens still
include the input copy. All 21 glyph fingerprints agree. Native
tests cover both long and short records, deferred materialization,
stable addresses and retained-source lifetimes.
[Raw timings and pathname controls](font-decode-linux-vertical-packed.json)

| Fixture | Face | Character | Fresh source open before (µs) | After |
| --- | ---: | ---: | ---: | ---: |
| `DejaVuSans.ttf` | 0 | U+0041 | 30.23 | 32.74 |
| `NotoSansCJK-Regular.ttc` | 0 | U+65E5 | 107.01 | 94.60 |
| `NotoSansCJK-Regular.ttc` | 1 | U+D55C | 105.94 | 91.98 |
| `NotoSansCJK-Regular.ttc` | 2 | U+4E2D | 105.71 | 93.71 |
| `NotoSansCJK-Regular.ttc` | 7 | U+FF21 | 110.27 | 91.80 |
| `NotoSansCJKjp-Regular.otf` | 0 | U+65E5 | 108.64 | 94.03 |
| `NotoSerifCJK-Regular.ttc` | 0 | U+65E5 | 120.50 | 100.52 |
| `NotoSerifCJK-Regular.ttc` | 1 | U+D55C | 119.02 | 109.91 |
| `NotoSerifCJK-Regular.ttc` | 2 | U+4E2D | 120.58 | 107.28 |
| `NotoSerifCJK-Regular.ttc` | 3 | U+9F8D | 123.54 | 99.27 |
| `NotoSerifCJK-Regular.ttc` | 4 | U+2000B | 116.08 | 100.60 |
| `NotoSansSC-Variable.ttf` | 0 | U+9F8D | 39.73 | 31.80 |
| `NotoSerifCJKjp-Regular.otf` | 0 | U+672C | 122.27 | 104.56 |
| `NotoSansJP-Regular.otf` | 0 | U+3042 | 147.76 | 147.41 |
| `NotoSansJP-Regular.otf` | 0 | U+65E5 | 149.25 | 145.45 |
| `NotoSansHK-Regular.otf` | 0 | U+9AA8 | 183.42 | 174.71 |
| `NotoSansHK-Regular.otf` | 0 | U+9F8D | 183.29 | 173.16 |
| `NotoSerifKR-Regular.otf` | 0 | U+D55C | 152.56 | 164.43 |
| `NotoSerifKR-Regular.otf` | 0 | U+570B | 157.71 | 151.56 |
| `NotoSerifSC-Regular.otf` | 0 | U+4E2D | 240.32 | 228.10 |
| `NotoSerifSC-Regular.otf` | 0 | U+6587 | 232.61 | 224.19 |

## Direct decryption of hexadecimal Type 1 input

The PFA reader validates hexadecimal input while decrypting its bytes.
It uses the binary reader when it encounters non-hexadecimal content
before the trailer. A hexadecimal-looking binary prefix remains covered
by the native tests.

Eleven interleaved batches with 51 opens on one CPU compare with
`bb5f1c72c8`. The PFA cases improve by 19–26%. Binary control
medians vary in both directions. All ten glyph fingerprints agree.
[Raw timings and binary controls](font-decode-linux-type1-hex-direct.json)

| Fixture | Character | Pathname open before (µs) | After |
| --- | ---: | ---: | ---: |
| `NimbusSans-Regular.t1` | U+0041 | 757.32 | 740.85 |
| `NimbusSans-Regular.t1` | U+0067 | 792.05 | 745.34 |
| `NimbusMonoPS-Regular.t1` | U+0057 | 926.13 | 919.00 |
| `NimbusMonoPS-Regular.t1` | U+0069 | 891.71 | 991.40 |
| `P052-Roman.t1` | U+0067 | 1061.74 | 1041.48 |
| `P052-Roman.t1` | U+0045 | 1059.55 | 1041.74 |
| `NimbusSans-Regular.pfa` | U+0041 | 1678.68 | 1365.81 |
| `NimbusSans-Regular.pfa` | U+0067 | 1756.99 | 1300.74 |
| `P052-Roman.pfb` | U+0067 | 1079.31 | 1039.14 |
| `P052-Roman.pfb` | U+0045 | 1063.17 | 1058.47 |

## Complete 103-case comparison

The 74-file corpus includes 12 supplied files, public fonts and
fixtures derived from pinned inputs. It covers TrueType, OpenType
CFF, collections, WOFF1, bare CFF, and binary and hexadecimal Type 1.

The Swag probes build against `9a7d0f5cdc` and `bdf45200be`.
The candidate build selects five Core crypto files from `06343223ad`
for compiler compatibility. The CRC-64 check runs after the timed
spans. Each entry is the median of nine interleaved batches with
five warmups, one requested Swag worker, a warm file cache, and
20 px glyphs. Batches open 31 fresh faces, or seven when the file
is at least 10 MB.

Swag is ahead of Pillow 12.3.0 with FreeType 2.14.3 in 81 cases.
Every Swag glyph index, advance, bitmap dimension, and CRC-64
matches the baseline. All seven WOFF1, ten Type 1, and six bare
CFF cases are ahead. The table shows the 22 remaining pathname
cases.
[Raw batches, fingerprints and fixture hashes](font-decode-linux-full-corpus.json)

| Fixture | Face | Character | Baseline Swag (µs) | Candidate | Pillow |
| --- | ---: | ---: | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 0 | U+65E5 | 1644.76 | 1681.06 | 792.94 |
| `NotoSansCJK-Regular.ttc` | 1 | U+D55C | 1816.80 | 1631.79 | 914.20 |
| `NotoSansCJK-Regular.ttc` | 2 | U+4E2D | 1780.22 | 1647.10 | 792.71 |
| `NotoSansCJK-Regular.ttc` | 7 | U+FF21 | 1680.29 | 1667.82 | 761.90 |
| `NotoSansCJKjp-Regular.otf` | 0 | U+65E5 | 2226.97 | 2131.31 | 801.53 |
| `NotoSerifCJK-Regular.ttc` | 0 | U+65E5 | 2888.40 | 2840.64 | 826.51 |
| `NotoSerifCJK-Regular.ttc` | 1 | U+D55C | 2847.73 | 2624.04 | 989.82 |
| `NotoSerifCJK-Regular.ttc` | 2 | U+4E2D | 2759.93 | 2839.28 | 904.09 |
| `NotoSerifCJK-Regular.ttc` | 3 | U+9F8D | 2838.34 | 2715.67 | 991.62 |
| `NotoSerifCJK-Regular.ttc` | 4 | U+2000B | 2798.93 | 2715.28 | 864.25 |
| `GowunBatang-Regular.ttf` | 0 | U+D55C | 1058.17 | 1076.09 | 839.77 |
| `NotoSerifCJKjp-Regular.otf` | 0 | U+672C | 3074.54 | 3054.16 | 955.65 |
| `NotoSansJP-Regular.otf` | 0 | U+3042 | 713.07 | 695.48 | 604.15 |
| `NotoSansJP-Regular.otf` | 0 | U+65E5 | 710.89 | 681.50 | 511.27 |
| `NotoSansHK-Regular.otf` | 0 | U+9AA8 | 769.54 | 750.33 | 555.26 |
| `NotoSansHK-Regular.otf` | 0 | U+9F8D | 779.95 | 741.86 | 585.16 |
| `NotoSerifKR-Regular.otf` | 0 | U+D55C | 1046.83 | 1053.81 | 715.67 |
| `NotoSerifKR-Regular.otf` | 0 | U+570B | 1015.45 | 1078.78 | 710.69 |
| `NotoSerifSC-Regular.otf` | 0 | U+4E2D | 1481.33 | 1411.20 | 559.96 |
| `NotoSerifSC-Regular.otf` | 0 | U+6587 | 1458.97 | 1486.64 | 596.87 |
| `GothicA1-Regular.ttf` | 0 | U+D55C | 243.20 | 243.47 | 139.32 |
| `GothicA1-Regular.ttf` | 0 | U+AC01 | 243.47 | 247.43 | 109.66 |

## Native CJK pathname, snapshot and retained-source comparison

The same Swag build and native FreeType 2.14.3 each set 20 px and
render one glyph. The medians use seven interleaved batches on
one CPU with five warmups. Both engines choose the same glyph
index throughout this comparison.

The FreeType pathname opens map the original file and acquire
glyph data as needed. Swag copies an independent snapshot of
the selected face. The FreeType snapshot column includes a full
`pread` into a reusable buffer. The descriptor and buffer are
prepared before timing. Swag copies one member for collection
rows, and both engines copy the same input for standalone
rows. Swag is ahead of FreeType's snapshot in 21 of these 22
cases.

The retained-source and FreeType memory columns acquire input
before timing. The timed Swag opens reuse previously validated
tables from that source. FreeType creates a fresh memory face
from the same buffer each time. Across the 11 full Noto CJK
faces, Swag takes 12–35 µs and FreeType takes 668–816 µs.
[Raw native timings and fingerprints](font-decode-linux-cjk-native-final.json)

| Fixture | Face | Character | Swag file (µs) | FreeType file | FreeType snapshot | Swag retained | FreeType memory |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 0 | U+65E5 | 1617.70 | 742.02 | 2820.33 | 12.61 | 711.40 |
| `NotoSansCJK-Regular.ttc` | 1 | U+D55C | 1670.01 | 686.90 | 2895.68 | 20.16 | 678.97 |
| `NotoSansCJK-Regular.ttc` | 2 | U+4E2D | 1669.26 | 730.30 | 2790.77 | 15.41 | 667.68 |
| `NotoSansCJK-Regular.ttc` | 7 | U+FF21 | 1623.89 | 702.53 | 2832.25 | 12.32 | 689.81 |
| `NotoSansCJKjp-Regular.otf` | 0 | U+65E5 | 2049.34 | 924.91 | 2819.53 | 13.09 | 815.96 |
| `NotoSerifCJK-Regular.ttc` | 0 | U+65E5 | 2702.00 | 775.98 | 3635.22 | 15.56 | 765.32 |
| `NotoSerifCJK-Regular.ttc` | 1 | U+D55C | 2860.92 | 818.32 | 3677.80 | 30.48 | 757.97 |
| `NotoSerifCJK-Regular.ttc` | 2 | U+4E2D | 2742.83 | 779.00 | 3582.06 | 17.32 | 721.40 |
| `NotoSerifCJK-Regular.ttc` | 3 | U+9F8D | 2704.92 | 821.51 | 3658.26 | 35.36 | 776.17 |
| `NotoSerifCJK-Regular.ttc` | 4 | U+2000B | 2822.35 | 771.97 | 3643.20 | 21.77 | 743.98 |
| `GowunBatang-Regular.ttf` | 0 | U+D55C | 1064.38 | 588.30 | 1552.56 | 36.48 | 567.01 |
| `NotoSerifCJKjp-Regular.otf` | 0 | U+672C | 2880.41 | 808.01 | 3626.07 | 19.73 | 730.51 |
| `NotoSansJP-Regular.otf` | 0 | U+3042 | 697.71 | 479.39 | 952.28 | 23.40 | 445.03 |
| `NotoSansJP-Regular.otf` | 0 | U+65E5 | 662.99 | 430.93 | 926.00 | 12.16 | 418.86 |
| `NotoSansHK-Regular.otf` | 0 | U+9AA8 | 747.72 | 471.26 | 1034.16 | 17.05 | 476.85 |
| `NotoSansHK-Regular.otf` | 0 | U+9F8D | 813.73 | 529.67 | 1051.57 | 23.45 | 464.94 |
| `NotoSerifKR-Regular.otf` | 0 | U+D55C | 1076.57 | 584.54 | 1431.25 | 30.57 | 562.66 |
| `NotoSerifKR-Regular.otf` | 0 | U+570B | 974.67 | 590.28 | 1401.91 | 26.75 | 555.04 |
| `NotoSerifSC-Regular.otf` | 0 | U+4E2D | 1503.24 | 537.38 | 1785.32 | 16.63 | 523.14 |
| `NotoSerifSC-Regular.otf` | 0 | U+6587 | 1469.74 | 515.48 | 1757.77 | 20.88 | 527.71 |
| `GothicA1-Regular.ttf` | 0 | U+D55C | 252.41 | 63.75 | 273.14 | 22.44 | 49.54 |
| `GothicA1-Regular.ttf` | 0 | U+AC01 | 243.53 | 61.74 | 241.65 | 15.46 | 49.49 |

## Vector decoding of adjacent Type 1 hexadecimal digits

A vector validates sixteen adjacent hexadecimal digits and packs
them into eight cipher bytes. The scalar path covers whitespace
and partial groups. The same cipher recurrence decrypts both
paths. The native test checks lowercase and uppercase PFA spelling.

Eleven interleaved batches with 51 opens on one CPU compare with
`bdf45200be`. PFA opening falls by 30–32% to 855–869 µs. Binary
controls and exact glyph fingerprints are included.
[Raw timings and fingerprints](font-decode-linux-type1-hex-simd.json)

| Fixture | Character | Pathname open before (µs) | After |
| --- | ---: | ---: | ---: |
| `NimbusSans-Regular.t1` | U+0041 | 688.57 | 693.19 |
| `NimbusSans-Regular.t1` | U+0067 | 699.12 | 670.38 |
| `NimbusMonoPS-Regular.t1` | U+0057 | 863.08 | 850.95 |
| `NimbusMonoPS-Regular.t1` | U+0069 | 880.95 | 852.79 |
| `P052-Roman.t1` | U+0067 | 981.26 | 1022.42 |
| `P052-Roman.t1` | U+0045 | 975.57 | 977.71 |
| `NimbusSans-Regular.pfa` | U+0041 | 1264.07 | 854.98 |
| `NimbusSans-Regular.pfa` | U+0067 | 1241.80 | 868.47 |
| `P052-Roman.pfb` | U+0067 | 978.99 | 1010.52 |
| `P052-Roman.pfb` | U+0045 | 1025.47 | 987.93 |

## Final corpus verification

The complete standard library at `903c822263` is built with the
Release compiler from `d643cd7688`. The baseline is `9a7d0f5cdc`.
Seven interleaved batches on one CPU warm the filesystem cache and
open fresh faces at 20 px. The candidate leads Pillow 12.3.0 with
FreeType 2.14.3 in 81 of 103 cases. All glyph indices, advances,
bitmap dimensions, and CRC-64 checksums agree across the two Swag
versions. The 22 remaining pathname cases are CJK.
[Raw batches, fingerprints and fixture hashes](font-decode-linux-full-corpus-verified.json)

| Input | Swag ahead | Cases |
| --- | ---: | ---: |
| TTF | 48 | 51 |
| OTF | 10 | 20 |
| TTC | 0 | 9 |
| WOFF1 | 7 | 7 |
| Bare CFF | 6 | 6 |
| Type 1 | 6 | 6 |
| PFA | 2 | 2 |
| PFB | 2 | 2 |

| Example | Character | Baseline Swag (µs) | Candidate | Pillow |
| --- | ---: | ---: | ---: | ---: |
| `NimbusSans-Regular.pfa` | U+0041 | 4419.99 | 838.11 | 1880.84 |
| `NimbusSans-Regular.pfa` | U+0067 | 4334.44 | 876.46 | 2046.00 |

### CJK with the verified build

The native comparison repeats the pathname, snapshot, and retained
source workloads above. Swag is ahead of FreeType in 11 of the 13
standalone cases that copy the same complete file. Both Gothic A1
glyphs favor FreeType in this run. Including collections, Swag is
ahead of FreeType's snapshot in 20 of 22 cases. Collection rows
copy a selected member in Swag and the entire collection in
FreeType. The 11 full Noto faces take 12–37 µs to reopen and render
from Swag's retained source. FreeType takes 658–821 µs from a
buffer acquired before timing.
[Raw native timings and fingerprints](font-decode-linux-cjk-native-verified.json)

The parallel comparison requests one or four workers on the same
four CPUs and starts the workers before timing. The 16 cases that
qualify for parallel reads take 19–43% less time with four workers,
with a median reduction of 37%. Gowun Batang, Noto Sans JP, and
Noto Serif KR pass Pillow in this set. Gothic A1 is below the
parallel read threshold and serves as a control. Glyph outputs
agree across worker counts.
[Raw worker timings and fingerprints](font-decode-linux-cjk-workers-verified.json)

| Fixture | Face | Character | One worker (µs) | Four workers | Pillow |
| --- | ---: | ---: | ---: | ---: | ---: |
| `NotoSansCJK-Regular.ttc` | 0 | U+65E5 | 1792.46 | 1270.00 | 918.23 |
| `NotoSansCJK-Regular.ttc` | 1 | U+D55C | 1922.80 | 1327.38 | 902.10 |
| `NotoSansCJK-Regular.ttc` | 2 | U+4E2D | 1923.91 | 1286.70 | 922.00 |
| `NotoSansCJK-Regular.ttc` | 7 | U+FF21 | 1867.30 | 1217.56 | 860.75 |
| `NotoSansCJKjp-Regular.otf` | 0 | U+65E5 | 2316.63 | 1326.06 | 840.89 |
| `NotoSerifCJK-Regular.ttc` | 0 | U+65E5 | 3031.51 | 1832.46 | 989.20 |
| `NotoSerifCJK-Regular.ttc` | 1 | U+D55C | 3140.51 | 1916.19 | 1148.10 |
| `NotoSerifCJK-Regular.ttc` | 2 | U+4E2D | 3289.72 | 1927.70 | 921.93 |
| `NotoSerifCJK-Regular.ttc` | 3 | U+9F8D | 3069.75 | 2011.58 | 1063.25 |
| `NotoSerifCJK-Regular.ttc` | 4 | U+2000B | 3134.77 | 1891.21 | 866.10 |
| `GowunBatang-Regular.ttf` | 0 | U+D55C | 1229.09 | 734.40 | 871.04 |
| `NotoSerifCJKjp-Regular.otf` | 0 | U+672C | 3348.83 | 1959.35 | 990.95 |
| `NotoSansJP-Regular.otf` | 0 | U+3042 | 780.04 | 562.77 | 654.45 |
| `NotoSansHK-Regular.otf` | 0 | U+9AA8 | 839.57 | 683.87 | 590.99 |
| `NotoSerifKR-Regular.otf` | 0 | U+D55C | 1153.62 | 790.17 | 889.86 |
| `NotoSerifSC-Regular.otf` | 0 | U+4E2D | 1748.23 | 1043.26 | 637.30 |
| `GothicA1-Regular.ttf` | 0 | U+D55C | 278.82 | 259.80 | 132.82 |

The verified build passes 210 native TrueType tests in Release and
108 selected tests in Release Safe. The 46 Core compression tests
pass in both configurations. The 12 Scope font tests pass and the
Scope Release application builds. The three Pixel collection tests
and 18 GUI PDF font and text tests pass in Release. TrueType and
Pixel documentation builds also pass.
