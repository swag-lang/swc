# Swag Scope Subtitle Viewer Backlog

This backlog covers standalone subtitle files: timed transcript navigation, source and
styled views, timing checks, and clipboard interchange. Playback and in-player subtitle
presentation live in [app.scope.video.md](app.scope.video.md).

### app.scope.subtitle.001 — Subtitle navigation has no current-cue timeline

- Evidence: SubRip and related files become a searchable timestamped transcript. The information
  bar exposes validated Go To Cue and Go To Time dialogs; Ctrl+Page Up/Down navigates adjacent cues,
  Ctrl+Home/End jumps to the first or last cue, `:` and an instant or a cue number go there from
  the lens, and the editor caret, direct jumps, and host search update the highlighted cue and its
  position counter. There is no duration filter or timeline. The
  [File Viewer Plus 7 catalog](https://fileviewerplus.com/file_types) provides no standalone
  cue-reader reference.
- Next: use Scope's timed-transcript fixtures to add a compact time ruler with overlap
  markers and a duration filter.
- Done when: cue and time jumps are keyboard accessible, overlapping cues are grouped, the
  current cue is marked, and search reveal, cue selection, and timeline position remain
  synchronized.
- Related: app.scope.subtitle.002, app.scope.subtitle.003

### app.scope.subtitle.002 — Subtitle syntax, styling, and diagnostics disappear in transcript mode

- Evidence: the dedicated viewer shows normalized cue text and times only. Cue identifiers,
  WebVTT settings, ASS styles, positioning, comments, malformed timing, and unsupported tags cannot
  be inspected or traced back to source.
- Next: add Normalized, Styled Preview, and Source modes sharing exact cue/source ranges.
- Done when: switching modes preserves the cue, parsing warnings point to source text,
  supported styling and placement can be previewed safely, and unsupported constructs remain visible.

### app.scope.subtitle.003 — Subtitle timing cannot be checked against media

- Evidence: the information sheet counts the cues that start before the one before them has ended
  and gives the shortest time a cue stays on screen; the track orders its cues by start, so cues
  written out of order are not reported. The standalone subtitle viewer has no way to associate a
  video or sound file, overlay cues, visualize waveform/frame timing, or apply a temporary delay and
  frame-rate conversion.
- Next: let the reader attach one local media file without modifying either input and reuse the
  existing video subtitle overlay and media clock.
- Done when: cues preview over media, delay and FPS conversion are reversible session settings,
  gaps/overlaps/out-of-order cues are flagged, and no transcoding or source rewrite is implied.

### app.scope.subtitle.004 — Subtitle text has no focused interchange commands

- Evidence: generic selection can copy transcript text; Ctrl+C or the lens copies the current
  cue, and the lens copies the whole dialogue without its times, a blank line between two cues.
  There is no export of a normalized transcript or report of cues omitted because of parser damage.
- Next: add cue-aware copy commands and bounded exports that preserve explicit timing policy.
- Done when: one cue, selected cues, dialogue-only text, and a normalized transcript can be
  copied or exported, and lossy normalization is summarized before writing.
