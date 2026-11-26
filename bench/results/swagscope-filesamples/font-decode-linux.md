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

Four-worker runs use four logical CPUs, and one-worker runs pin to one CPU.
The table reports medians of 11 interleaved batches of 21 fresh file opens and
one rendered glyph at 20 px. The warm-cache baseline is `d8325e8d9e`.
Glyph indices, advances, bitmap dimensions, and CRC-64 agree across all four runs.
Separate one-worker repeats on the three variable controls ranged from a 3.3%
gain to a 0.4% slowdown. [Raw timings and controls](font-decode-linux-parallel-read.json)

| Fixture | Face | Before, 1 worker (µs) | After, 1 worker (µs) | Before, 4 workers (µs) | After, 4 workers (µs) |
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

| Collection | Members | Before, 4 workers (ms) | After, 4 workers (ms) |
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
The Swag builds return identical glyph indices, advances, bitmap dimensions,
and CRC-64. FreeType 2.14.3 agrees on the glyph indices.
[Raw samples](font-decode-linux-woff-parallel.json)

| Fixture | Before, 1 worker (ms) | After, 1 worker (ms) | Before, 4 workers (ms) | After, 4 workers (ms) | FreeType file (ms) |
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
