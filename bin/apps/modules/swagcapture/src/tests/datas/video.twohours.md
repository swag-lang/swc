# Two-hour video workspace

Open `video.twohours.scc` in Swag Capture with its sibling `video.twohours.mp4` present.
The SCC is the editable capture document; the MP4 is its original media, as for ordinary captures.

The deterministic synthetic recording contains 216,000 H.264 pictures at 160 × 96, 30 fps,
and 345,600,000 audible mono AAC sample frames at 48 kHz: exactly 7,200 seconds. The MP4
is 49,229,264 bytes. A small picture keeps this duration/indexing fixture practical in Git.

Seven binary marks across the top encode the minute (0–119). Six marks across the bottom
encode the picture within its two-second closed GOP (0–59); a vertical bar moves across the
middle. The soundtrack is a continuous 750 Hz tone. Completed fragments and a final key-frame
index are present. The generator encodes one GOP per minute and repeats its compressed packets;
this exercises real packet counts and timestamps, but does not simulate acquisition throughput,
realistic browser compression, continuous audio-clock drift, or a two-hour recording soak.

Run the native editor/tooling scenario from the repository root:

```powershell
python tools/capture-video.py
```

It opens the SCC through the library, seeks and plays near two hours, changes and saves trim
points, exercises undo/redo, adds timed annotations, and exports unchanged, trimmed, annotated,
and resized media. It checks output picture/sample counts, decodability, compressed packet
identity, and preservation of the original. Screenshots, exports, timings and logs remain in the
printed external evidence directory. `--output` selects a new directory outside the checkout.
The runner performs machine-load admission before each test command.

To deliberately replace both maintained fixture files with the current native encoders:

```powershell
python tools/capture-video.py --regenerate
```

Generator: `cases/integration/longvideo.fixture.swg`. Native scenarios:
`cases/stress/longvideo.workspace.swg`. Regeneration requires the explicit
`capture.fixture.generate=true` argument so routine test selections cannot overwrite fixtures.

SHA-256 of this fixture revision:

```text
7d8d0b441ec6e07733553793f6bd4e2a1dfc3c6ade060184c06761c57b63bc24  video.twohours.mp4
184559b6ebc49851b97dfe1a68d4cbb675e22fc006c395b0b0e8a555437c6b22  video.twohours.scc
```
