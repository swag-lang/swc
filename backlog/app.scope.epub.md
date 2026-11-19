# Swag Scope EPUB Viewer Backlog

EPUB book navigation, layout, and reading position.

### app.scope.epub.001 — EPUB chapter reading needs complete navigation

- Evidence: EPUB 2 NCX and EPUB 3 contents now expose authored titles, hierarchy and chapter
  fragments in the shared filterable outline. Internal spine links keep the chapter counter in
  sync. Zoom and column choices preserve the visible text passage; bounded Back/Forward history
  returns to that passage across chapter and fragment visits, through the lens or Alt+arrows.
  The information sheet counts the chapters and gives the title, authors, language, publisher
  and date of the package's Dublin Core metadata. Book-wide search, landmarks, non-spine footnotes, persistent position restore and bookmarks
  remain absent. Extraction still prepares every package member before the first chapter is shown.
  [File Viewer Plus 7](https://fileviewerplus.com/open/epub) opens EPUB in a document editor and
  exports it to other formats. Book-wide search and exact chapter position are the first gaps
  to close in Scope's chapter-based reading workflow.
- Next: add book-wide search with chapter/all-book scope and stable chapter positions, then
  bookmarks, persistent reading positions and lazy extraction of the visible chapter's resources.
- Done when: TOC, previous/next, links, footnotes, search, bookmarks, history and position restore work across a
  representative EPUB 2/3 corpus without delaying first content for the whole package.
- Related: app.scope.archive.001

### app.scope.epub.002 — EPUB needs paged layout and persistent logical reading positions

- Evidence: the chapter reader offers compact, comfortable and wide default reading measures,
  plus zoom. A logical text location preserves the visible passage through those changes, while
  authored CSS keeps priority. There is no book-level paged/continuous-flow choice, line-spacing
  control or persistent position restore, and ordinary viewport reflow still keeps pixel scroll.
- Next: build book-owned paged and continuous modes over the HTML layout, retain a logical
  location across viewport changes, and connect it to navigation, search and safe position restore.
- Done when: readers can choose fit-to-width flow or pages, adjust typography without corrupting
  authored content, and reopen at the same logical passage across window and theme changes.
- Related: app.scope.epub.001, app.scope.viewers.003
