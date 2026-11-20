# Swag Scope Subtitle Viewer Backlog

This backlog covers standalone subtitle files: timed transcript navigation, source and
styled views, timing checks, and clipboard interchange. Playback and in-player subtitle
presentation live in [app.scope.video.md](app.scope.video.md).

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
