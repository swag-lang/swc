# Swag Scope EPUB Viewer Backlog

EPUB book navigation, layout, and reading position.

### app.scope.epub.001 — EPUB chapter reading needs complete navigation

- Evidence: EPUB 2 NCX and EPUB 3 contents now expose authored titles, hierarchy and chapter
  fragments in the shared filterable outline. Internal spine links keep the chapter counter in
  sync. Zoom and column choices preserve the visible text passage; bounded Back/Forward history
  returns to that passage across chapter and fragment visits, through the lens or Alt+arrows.
  The information sheet counts the chapters and gives the title, authors, language, publisher
  and date of the package's Dublin Core metadata. Book-wide search now covers source text in each
  spine chapter, one chapter per incremental callback, and search results navigate to and highlight
  their chapter. A localized `chapter:`/`chapitre:` prefix limits results to the chapter currently
  displayed; `book:`/`livre:` returns to book-wide search. The shared case, whole-word and regular
  expression choices apply to either scope. Search jumps within the current chapter now add the
  passage left behind to Back/Forward history, just as cross-chapter jumps do. Chapters larger
  than 32 MiB or unreadable chapters are skipped with an explanation.
  Landmarks, non-spine footnotes, persistent position restore and
  bookmarks remain absent. Extraction still prepares every package member before the first chapter is shown.
  [File Viewer Plus 7](https://fileviewerplus.com/open/epub) opens EPUB in a document editor and
  exports it to other formats. Chapter-only search scope and exact chapter position are the
  next gaps to close in Scope's chapter-based reading workflow.
- Next: add landmarks, footnote navigation, and bookmark creation/removal; load chapter resources
  on demand so later package members do not delay the first chapter.
- Done when: TOC, landmarks, previous/next, internal links, footnotes, bookmarks, Back/Forward history, and
  book-wide and chapter-scoped search work across a representative EPUB 2/3 corpus, with the first
  chapter available without extracting the whole package.
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
