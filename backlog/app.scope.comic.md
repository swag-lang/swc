# Swag Scope Comic Book Viewer Backlog

CBZ reading and navigation.

### app.scope.comic.001 — CBZ has page turns but no complete comic reading modes

- Evidence: `Viewers.Comic` lists image members in natural filename order and opens one page through
  `EmbeddedViewer`. Previous and next controls are available, and a lens option maps left/right
  keys to manga reading order. A clickable page counter accepts a one-based page number. A
  `ComicInfo.xml` at the root of the book, read through the DTD-free package scanner, gives the
  information sheet its title, writer, series, number, volume, penciller, publisher and year, and a
  `Manga` value of `YesAndRightToLeft` starts the book in right-to-left order. There is still no
  thumbnail index or multi-page reading layout. A dedicated reader such as
  [OpenComic](https://github.com/ollm/OpenComic) offers right-to-left manga, double-page spreads,
  continuous webtoon scroll, bookmarks and reading-position restore.
- Next: add a bounded page index with thumbnails and stable positions, then single/spread/continuous
  layouts, right-to-left spreads, cover alignment and per-page fit/zoom.
- Done when: natural order, nested folders, spreads, manga direction, tall pages and damaged
  members remain readable and navigable across real CBZ books; page changes never require
  extracting all images first, and unsupported image pages are named in place.
- Related: app.scope.image.005, app.scope.viewers.003
