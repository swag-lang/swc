# Swag Scope MIDI Viewer Backlog

The MIDI viewer already parses Standard MIDI Files into notes, tracks, tempo/time/key signatures,
duration, and a zoomable/filterable piano roll. It deliberately has no synthesis today. This
backlog owns professional sequence inspection and optional audition; structured chunk/event bytes
remain available in the Binary viewer.

## Playback and timeline

### app.scope.midi.001 — MIDI has no playback or synthesis

- Evidence: the viewer is a static piano roll with no play, pause, stop, seek clock, playhead,
  instrument rendering, MIDI output, or explicit silent-playback policy. The application README
  states that no MIDI synthesis is performed.
- Next: decide and document one bounded first path: internal General MIDI-compatible synthesis,
  system/user-selected MIDI output, or both, including sound-bank licensing and device latency.
- Complete when: the decision records ownership and safety; the chosen path plays tempo changes,
  channels, programs, controllers, percussion, sustain, and note-off timing; transport stays in
  sync with the playhead; and inspection remains fully usable without an output.

### app.scope.midi.002 — MIDI transport has no loop, metronome, count-in, or playback rate

- Evidence: because there is no clocked transport, the reader also cannot loop a tick/time/measure
  range, hear or see a metronome, start with count-in, or audition at a temporary tempo percentage.
- Next: add a tempo-map-aware transport-range model after app.scope.midi.001, with musical and absolute time
  endpoints.
- Complete when: loop boundaries can snap to event/beat/bar or remain exact, metronome follows time
  signature and tempo changes, rate leaves source tempo events unchanged, and all timing displays
  agree.
- Related: app.scope.midi.001

### app.scope.midi.003 — The piano roll has no playhead, overview, or direct musical-time address

- Evidence: zoom changes horizontal scale and Fit shows the complete score, but there is no
  scrollbar overview, current tick/time/bar:beat:ticks readout, Go To, selection range, or navigation
  history.
- Next: define one reversible map among SMF ticks, tempo-aware seconds, and bars/beats before adding
  address entry, playhead, range selection, and overview ruler.
- Complete when: every coordinate form can be entered and copied, meter/tempo changes are handled,
  SMPTE division is not forced through PPQN arithmetic, overview drag is bounded, and history
  restores track plus time range.

## Musical and event inspection

### app.scope.midi.004 — Notes have no selection or detail inspector

- Evidence: notes paint by track and can be counted, but pointer/keyboard cannot select one and show
  pitch/name, start/end/duration, tick/time/bar position, channel, velocity, release velocity,
  instrument, or overlapping note relationships.
- Next: add note hit testing, single/range selection, and an inspector backed by exact parsed events.
- Complete when: selected notes expose all available source and derived timing/value fields, chords
  and overlaps can be traversed, velocity is visually explainable, and Open in Binary selects the
  originating event bytes.
- Related: app.scope.hexa.002

### app.scope.midi.005 — Non-note MIDI events cannot be viewed on an event list

- Evidence: parsing uses tempo, time signature, key signature, track name, and notes, but program
  changes, controllers, pitch bend, pressure, SysEx, lyrics, markers, cue points, ports, channel
  prefixes, sequence numbers, text, and unknown meta events disappear from the dedicated view.
- Next: retain every event with tick, track, channel, decoded fields, and source byte range, then add
  a virtual filterable event list synchronized with the piano roll.
- Complete when: event type/channel/track/time filters work, running status and malformed lengths are
  diagnosable, unknown payloads remain inspectable, list and roll select each other, and large event
  streams stay bounded.

### app.scope.midi.006 — Tempo, meter, key, marker, and lyric changes are reduced to first-value summary

- Evidence: summary helpers report only the first tempo, time signature, and key signature. Later
  changes do affect duration calculation but are not drawn; lyrics, markers, and cue points are not
  parsed into visible lanes.
- Next: add ruler lanes for tempo, meter, key, markers/cues, and lyrics over the exact event timeline.
- Complete when: every change is positioned and selectable, ramps versus steps are not confused,
  bar numbering follows meter changes, lyrics preserve syllable/order metadata, and lane visibility
  can be configured.

### app.scope.midi.007 — Tracks and channels cannot be muted, soloed, regrouped, or understood

- Evidence: the selector shows All Tracks or one track by note count. It cannot display track and
  channel concurrently, mute/solo, rename session labels, color consistently, show ports/programs/
  drum channels, or explain format 0 channel mixtures.
- Next: introduce a track/channel matrix with stable colors and diagnostic mute/solo state independent
  of source events.
- Complete when: track and channel filters compose, mute/solo affect display and app.scope.midi.001 playback,
  program/bank/percussion/port facts are visible over time, format 0/1/2 semantics are explicit, and
  reset restores an unfiltered score.

### app.scope.midi.008 — Controller, pitch, velocity, aftertouch, and program automation have no lanes

- Evidence: the piano roll encodes note rectangles only. Continuous and discrete performance data
  cannot be graphed, probed, correlated with notes, or checked for dense/redundant events.
- Next: add one selectable automation lane with step/linear presentation appropriate to each MIDI
  message type, then support stacked lanes under a strict drawing budget.
- Complete when: CC, pitch bend, channel/poly pressure, program/bank, sustain, and velocity can be
  shown and probed; 7/14-bit values state resolution; channel scope is explicit; and dense lanes
  aggregate without losing exact event access.

### app.scope.midi.009 — The piano roll cannot zoom vertically or adapt its keyboard and note labels

- Evidence: horizontal zoom exists, while pitch rows, visible range, keyboard width, note-name
  convention, octave numbering, drum names, scale highlighting, and black/white-key contrast are
  fixed.
- Next: add vertical zoom/pan and configurable pitch labelling before scale/drum overlays.
- Complete when: vertical fit and zoom preserve selected notes, MIDI key number and chosen note name
  are visible, octave convention is declared, channel-10 drum maps can replace pitch names, and
  key-signature/scale highlighting is optional and accessible.

## Integrity, scale, and interchange

### app.scope.midi.010 — SMF timing and structural edge cases have no explicit support matrix

- Evidence: the parser caps input at 32 MiB and one million notes, calculates PPQN duration from a
  tempo map, and parses core chunks. Support for SMPTE division, format 2 independent sequences,
  multiple End-of-Track cases, running status boundaries, RIFF RMID, karaoke conventions, huge delta
  times, and conflicting tempo tracks is not presented as a tested contract.
- Next: document current semantics and add focused fixtures for every SMF format/division plus
  malformed chunk/event recovery before expanding formats.
- Complete when: format 0/1/2 and PPQN/SMPTE behavior are declared and tested, caps report resource
  limits rather than corruption, partial tracks survive safe damage, RMID stance is explicit, and
  the viewer summary names timing mode.

### app.scope.midi.011 — Large MIDI files are fully materialized and hard-capped

- Evidence: the entire file, tracks, and up to one million note objects remain resident before the
  view is useful. Event-dense captures can hit the 32 MiB or note cap despite needing only a small
  visible time range.
- Next: split a bounded chunk/event index from lazily decoded visible events and publish metadata as
  soon as the header and track directory are known.
- Complete when: opening and scrolling memory are explicitly bounded, note/event limits can page
  rather than fail, visible ranges decode first, analysis cancels, and exact counts distinguish
  known from still-indexing values.
- Related: app.scope.viewers.004

### app.scope.midi.012 — MIDI events and views cannot be exported with an explicit loss policy

- Evidence: the viewer has no copy-note/event, CSV/JSON event export, tempo-map export, piano-roll
  image, or selected-range MIDI extraction. Rewriting SMF safely is outside the current reader.
- Next: export selected/all decoded events and tempo maps to stable JSON/CSV plus a rendered image;
  treat SMF range extraction as a separate, explicitly normalized writer outcome.
- Complete when: tabular exports preserve track/channel/tick/time/source offset and raw unknown data,
  images name scale and range, normalized SMF export states event ordering/running-status/timing
  changes, and the original file is never modified.
