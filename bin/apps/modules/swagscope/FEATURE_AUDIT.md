# Swag Scope viewer feature audit

This audit compares all 24 plugins registered by `createViewerPluginRegistry` with published
features of dedicated readers. It is a feature inventory for local, read-only opening, reading,
navigation and inspection; the referenced product may also edit, synchronize or use cloud services.
`Today` describes the Swag Scope reader, not all decoders or alternative viewers offered for a file.
The market documentation was checked on 2026-11-14. The [shared viewer backlog](../../../../backlog/app.scope.viewers.md)
defines the reading-first order and the quality gate. Current implementation details are in the
[application README](README.md).

The product gate applies to every row: one offline executable; all shipped decoders and viewers
implemented in Swag; no separately installed codec, renderer, helper binary or service; bounded
opening and scrolling; visible unsupported-content diagnostics. `app.scope.viewers.009` calls for
cold-open, first-content, adjacent-file and memory measurements on real licensed fixtures alongside
the named reference. `app.scope.viewers.014` covers clean-machine single-executable delivery.

| Registered viewer | Category reference | Today | Largest reading/inspection gaps | Backlog |
| --- | --- | --- | --- | --- |
| HTML | [Firefox Reader View](https://support.mozilla.org/en-US/kb/firefox-reader-view-clutter-free-web-pages) | Offline safe-subset render plus Code and text alternatives | Reader mode, encoding override, resource diagnostics, DOM/source mapping, broader layout fidelity | `app.scope.html.001–006`, `std.gui.html` |
| Code | [VS Code editor](https://code.visualstudio.com/docs/editing/codebasics) | Streamed colored source | Outline, folding, minimap, exact full-file selection, language/encoding diagnostics | `app.scope.code.001–006`, `app.scope.text.005` |
| Markdown | [Typora](https://support.typora.io/Markdown-Reference/) | Rendered document, source alternative and heading outline | Nested blocks, cross-window references, exact search, fragment/footnote navigation, source sync, optional diagrams | `std.gui.markdown.002–012`, `app.scope.markdown.001–004` |
| Subtitles | [Subtitle Edit](https://github.com/SubtitleEdit/subtitleedit/blob/main/docs/features/audio-visualizer.md) | Timed cue transcript | Styled/source modes, cue timeline, media synchronization, waveform context, cue-aware interchange | `app.scope.subtitle.001–004` |
| Image | [XnView MP](https://www.xnview.com/en/image-viewer/) and [Gwenview](https://docs.kde.org/trunk_kf6/en/gwenview/gwenview/introduction.html) | Raster/SVG view, transform, zoom and metadata | Probe/histogram, profiles and HDR, frame/layer navigation, compare, huge-image behavior | `app.scope.image.001–015`, `std.pixel.image` |
| Video | [VLC](https://docs.videolan.me/vlc-user/desktop/3.0/en/basic/settings/adjustmentsandeffects.html) and [mpv](https://mpv.io/manual/stable/) | Native decoded playback with timeline and subtitles for supported codecs | Exact frame/time address, A/B, chapters, track details, sync, transforms, color/HDR, performance path | `app.scope.video.001–013`, `app.scope.video.015–016`, `std.video` |
| PDF | [Okular](https://docs.kde.org/stable_kf6/en/okular/okular/index.html) and [Acrobat Reader](https://helpx.adobe.com/uk/acrobat/using/reading-pdfs-reflow-accessibility-features.html) | Pages, text search/selection and bookmarks | Partial-page robustness, thumbnails/facing, forms/annotations/security, reflow, accessible order, region/table selection | `app.scope.pdf.001–009`, `app.scope.viewers.019`, `std.gui.pdf` |
| Sound | [VLC](https://docs.videolan.me/vlc-user/desktop/3.0/en/basic/playback.html) | Native decoded playback and waveform | Zoom/loop, chapters, channel/frequency/loudness probes, tags and ReplayGain, output diagnostics | `app.scope.audio.001–011`, `std.audio` |
| Font | [FontForge metrics view](https://fontforge.org/docs/ui/mainviews/metricsview.html) | First-face TrueType specimen and character map | Collection faces, CFF, glyph search/detail, shaping, kerning, variable/color fonts | `app.scope.font.001–013`, `std.truetype` |
| MIDI | [Synthesia](https://www.synthesiagame.com/support/guide/displaySheetMusic) | Static zoomable piano roll | Playback, exact event and musical-time navigation, automation lanes, optional interpreted score | `app.scope.midi.001–014` |
| Table | [Modern CSV](https://www.moderncsv.com/documentation/basics/) | Virtualized CSV/TSV grid up to 32 MiB | Streamed huge files, dialect corrections, sort/filter/freeze, formatting, selection/export | `app.scope.table.001–007` |
| RTF | [Word Read Mode](https://support.microsoft.com/en-gb/word/read-documents-in-word) | Formatted prose and simple tables | Fonts/colors, pagination, images, complex tables, encoded text | `app.scope.rtf.001` |
| DOCX | [Word Read Mode](https://support.microsoft.com/en-gb/word/read-documents-in-word) | Ordered prose, simple tables and images | Authored page/section geometry, styles, headers/footnotes/comments, search and restore | `app.scope.docx.001` |
| OpenDocument Presentation | [LibreOffice Impress Guide](https://books.libreoffice.org/en/IG75/IG75-ImpressGuide.pdf) | Ordered slide text and pictures | Master/theme fidelity, authored geometry, notes, overview and animation | `app.scope.odp.001` |
| OpenDocument Spreadsheet | [LibreOffice Calc Guide](https://books.libreoffice.org/en/CG75/CG75-CalcGuide.pdf) | Sheets and displayed cell values | Number styles, charts, annotations, advanced geometry and exact font metrics | `app.scope.ods.001` |
| OpenDocument Text | [LibreOffice Writer Guide](https://books.libreoffice.org/en/WG75/WG75-WriterGuide.pdf) | Paragraphs, lists, simple tables and pictures | Physical pages, headers/footers, notes, comments and complex drawings | `app.scope.odt.001` |
| XLSX | [Excel](https://support.microsoft.com/en-gb/excel/get-started/freeze-panes-to-lock-rows-and-columns) | Sheets and values in bounded grid | Authored widths/merges/styles/number formats, freeze/filter, large-sheet navigation | `app.scope.xlsx.001` |
| PPTX | [PowerPoint Reading View](https://support.microsoft.com/en-us/powerpoint/how-certain-features-behave-in-web-based-powerpoint) | Ordered slide text and pictures | Object geometry, masters/themes, notes, slide overview and presentation | `app.scope.pptx.001` |
| EPUB | [calibre viewer](https://manual.calibre-ebook.com/viewer.html) | Ordered XHTML spine chapters | NCX/nav TOC, book search/bookmarks/history, lazy extraction, paged/flow reading, stable location | `app.scope.epub.001–002`, `app.scope.viewers.018–019` |
| Comic book | [OpenComic](https://github.com/ollm/OpenComic) | Natural-order single CBZ pages | Spread, manga direction, continuous scroll, thumbnails, ComicInfo and position restore | `app.scope.comic.001` |
| Archive | [7-Zip](https://www.7-zip.org/) | ZIP/ZIP64 tree and bounded stored/Deflate entry preview | ZIP variant/integrity contract, nested provenance, encrypted-entry policy; other families later | `app.scope.archive.001–002`, `app.scope.viewers.020` |
| Plain text | [VS Code editor](https://code.visualstudio.com/docs/editing/codebasics) | Streamed text and encoding detection | Exact Go To, whole-file search/result navigation, bookmarks, invisible characters, non-resident copy | `app.scope.text.002–005`, `app.scope.text.027–030`, `app.scope.viewers.016` |
| Binary | [010 Editor templates](https://www.sweetscape.com/010editor/templates.html) | Known-structure report with raw-byte alternative | Semantic filter/compare, provenance, container previews, damage/security findings | `app.scope.binary.001–007`, `app.scope.binary.009`, `app.scope.binary.011–014`, `app.scope.viewers.020` |
| Hexadecimal | [010 Editor](https://www.sweetscape.com/010editor/manual/Compare.htm) | Mapped byte grid, inspector, search and entropy | Precise compare, structures, history/landmarks, checksum, large-file responsiveness, accessibility | `app.scope.hexa.001–022` |

The order for implementation is reader fidelity and common navigation on already registered
formats, then advanced inspection. New format selectors remain after those quality gates. The
reference products are feature evidence, not code or runtime dependencies.
