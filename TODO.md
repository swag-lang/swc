# Swag Investigation Backlog

This file records compiler, standard-library, tooling, and language-design issues discovered while
working on otherwise unrelated tasks. An entry is a lead worth preserving, not a commitment to
implement it.

Fix a finding immediately when it is sufficiently understood, relevant to the current task, and
safe to validate. Add it here when it needs separate investigation, broader design work, or stronger
evidence. Search before adding an entry, enrich existing entries instead of duplicating them, and
remove or update entries when later work resolves or disproves them.

## Open Investigations

<!--
Use this compact format. Keep observations factual and make the next step actionable.

### Short descriptive title

- Area: compiler | bin/std | language | tooling | documentation
- Found while: task, test, or file that exposed the issue
- Observation: awkward behavior, suspected defect, or optimization opportunity
- Evidence: reproduction, relevant paths, measurements, or diagnostics
- Next step: smallest useful investigation
- Related: issue, pull request, or TODO entry if applicable
-->

### A reference to a nullable slot escapes the whole nullability system

- Area: compiler
- Found while: checking whether the postfix `!` leaks `readonly` (it does not — `readonly`
  deliberately "restricts writing through the field's name; it does not freeze the whole value",
  [002_009_visibility_and_exports.swg:107-109](bin/reference/modules/language/src/002_009_visibility_and_exports.swg#L107-L109))
- Observation: `&#null *T` — a reference bound to a nullable slot, which is exactly what
  `Array.opIndex` hands back — is not seen as nullable anywhere. `isNullable()` is asked of the
  reference, and a reference is never nullable, so: the use-site rules let a member access through
  it compile with no proof at all, and the postfix `!` is a silent no-op on it. The nullability
  system simply does not apply to values reached through a reference.
- Evidence: with `mtd const at()->const &(#null *Item)`, `bound.value` compiles unguarded and
  `#typeof(bound.value)` reports `#null *Item` rather than the field type — member resolution
  peels one pointer-or-reference layer and then stops, so it never reaches the struct.
  `#typeof(bound!)` is unchanged by the assertion.
- Next step: this needs three coordinated changes, which is why an attempt was reverted rather
  than half-shipped. (1) The use-site check must look through the reference
  (`SemaHelpers::unwrapAliasRefType` in `resolveMemberAccess`). (2) `notNullUnwrappedTypeRef` must
  strip `Nullable` INSIDE the reference — rebuilding `&(#null *T)` as `&*T` rather than dropping
  the reference, so the payload convention is untouched. (3) Member resolution must peel every
  reference layer and then exactly one pointer (`**T` must still stop after one), and codegen must
  do the matching double indirection — step 3 is where the reverted attempt failed: it compiled
  but read the wrong address at run time. Start with a runtime test for `bound!.value`, since that
  is what catches the codegen half.
- Related: `bin/unittests/jit/operators/notnull_access.swg`

### Golden snapshots cannot be recorded under the test sandbox

- Area: compiler | bin/std
- Found while: regenerating the gui widget goldens after the theme-atlas format change
- Observation: `swc test` always arms the sandbox, and the sandbox refuses every write outside
  its root. The golden store's documented flows — create a missing golden on first run, write
  `<name>.actual.txt`/`.png` next to a mismatching golden for `tools/accept-test-goldens.bat` —
  both write into the module source tree, so they silently stopped working when the sandbox
  landed: a failing golden reports `[golden] cannot write ...` and leaves nothing to accept.
- Evidence: the 13 gui golden mismatches printed `cannot write` for every actual; recording them
  required launching the tests with an explicit repo-rooted sandbox
  (`--run-arg "swag.sandbox=<repo root>"`), which redirects the special directories into the
  repository and allows the corpus writes.
- Next step: decide where golden actuals should land under a sandbox. Candidates: the launcher
  grants the corpus root explicitly (a `swag.sandbox.corpus=<dir>` run argument the golden store
  consults), or the golden store mirrors actuals under the sandbox root at a deterministic path
  and `accept-test-goldens.bat` harvests them. Writing straight to the source tree from a
  sandboxed test contradicts the sandbox guarantee, so the escape must stay launcher-owned.

### Constant branches survive until the sanitizer after inlining

- Area: compiler
- Found while: `notnull_access.swg` release-mode sanity false positive (fixed in the sanitizer)
- Observation: inlining `redundant(null)` folds the null test to `%2 = 1; %3 = %2;
  cmp %3, 0; je`, yet no pass folds the constant compare-and-branch before sanity runs, so the
  dead dereference block survives the whole pre-RA pipeline. The sanitizer now prunes the
  infeasible edge itself, but the optimizer keeps emitting the dead block.
- Evidence: `#[Swag.PrintMicro("pre-sanity")]` on a `#test` calling `redundant(null)` shows the
  folded guard and the unreachable dereference block still present at the sanity stage.
- Next step: teach branch-simplify (or const-fold) to evaluate a conditional jump whose flags
  come from a compare against an immediate on a register holding a known constant, then let DCE
  drop the unreachable block; measure code-size impact on the release suites.

### Appending a `String` rvalue with `+=` corrupts the heap

- Area: bin/std | compiler
- Found while: accumulating traced SVG fragments into one `String` in a script
- Observation: `someString += Format.toString(...)` — appending a temporary `String` value —
  corrupts the heap. The damage surfaces later, as access violations inside unrelated
  allocations, so the crash site points far away from the append. Appending a `string` view
  (`+= s.toString()`) and `String.appendFormat` are sound. Appending a `String` lvalue was
  replaced in the same experiment and has not been exonerated separately.
- Evidence: scripted loop calling `Svg.trace` over 16 icon cells: with `outSvg +=
  Format.toString(...)` in the loop, iteration 3 dies with 0xC0000005 inside `pixel.dll`; the
  identical run with `appendFormat` plus `+= body.toString()` completes all 16 cells. The same
  loop with no appends at all also completes, and the failure point moves with unrelated
  allocation changes — classic layout-sensitive out-of-bounds or use-after-free behavior.
- Next step: build a minimal repro without `pixel` (a loop appending `String` rvalues to a
  growing `String`), then inspect which `opAssign`/append overload a `String` rvalue selects and
  the drop ordering of the temporary around `+=` — the append may be reading the operand's
  buffer after the temporary was dropped, or routing through a byte-slice overload whose length
  is read from freed storage.

### `Image.load` hands back the magenta placeholder for PNGs that decode correctly

- Area: bin/std
- Found while: regenerating the `texteffect.zoom` golden and comparing theme-atlas fidelity in
  standalone scripts
- Observation: `Image.load(path)` returned the magenta "missing image" placeholder for valid
  theme PNGs, while `File.readAllBytes` + `Image.decode(".png", bytes)` decodes the same files
  correctly. The placeholder makes the failure silent: a comparison harness happily measured
  differences against solid magenta.
- Evidence: the gui theme PNG atlases during the DPI/theme work; switching the scripts to
  read-then-decode was the entire fix at first. Later in the same work, `Image.decode(".png",
  bytes)` itself returned the placeholder for the same files when executed as a JIT-run script,
  while the identical call decodes correctly compiled into a native module — so the failure is
  context-dependent (JIT execution), not a parsing defect.
- Next step: run one PNG decode under the JIT with the decoder instrumented, find which stage
  fails only there (the placeholder swallows it), and make the failure loud (return the decode
  failure) instead of returning placeholder pixels.

### Data-driven UI resource for `std/gui`

- Area: bin/std
- Found while: simplifying the sCrypt vault cards after `FormCtrl` was judged too heavy
- Observation: a UI described by a data string is only worth it when the caller never needs the
  controls back. The removed `FormCtrl` proved the opposite case: every consumer built an
  `Array'FormFieldDefinition`, then immediately recovered typed pointers by string identifier
  (`notnull (notnull form.findField("create.size")).accessoryChoice`), so the data layer added a
  stringly-typed boundary without removing a single control pointer. A full markup would extend
  that boundary from four fields to the whole window unless the resource is resolved at compile
  time into typed members.
- Evidence: commits 3b382e68a and 8009467a0 removed `FormCtrl`, `FormFieldDefinition`,
  `FormFieldKind`, `FormChoice`, and `FormField` (177 lines) and replaced three consumers with
  `FormLayoutCtrl` builders that return the concrete control. sCrypt's two cards lost their two
  field-description functions and every `findField` lookup. `Core.File.TweakFile` already parses a
  text format onto struct fields through reflection, and `ThemeStyle.addStyleSheetColors` shows the
  existing string-resource precedent in `std/gui`.
- Next step: prototype the compile-time half first, since it is what decides the design. Parse a
  small UI resource in a `#run` block with `TweakFile` as the model, and check whether the parsed
  tree can emit typed member declarations for a window struct through `#code`/generated source. If
  typed accessors cannot be generated at compile time, a UI resource reintroduces exactly the
  lookup boundary the builders just removed, and a resource editor would ship that cost to every
  window. Only then evaluate the editor.

### `#[Swag.Tls]` is accepted and then ignored

- Area: compiler
- Found while: attributing the sCrypt/WinFsp integration working-set growth to the runtime
  allocator rather than to sCrypt or WinFsp
- Observation: the attribute is parsed into `RtAttributeFlagsE::Tls`
  ([AttributeList.h:37](src/Compiler/Sema/Core/AttributeList.h#L37), assigned at
  [Sema.Attributes.cpp:181](src/Compiler/Sema/Ast/Sema.Attributes.cpp#L181)) and never read again;
  no backend emits a thread-local segment. A `#[Swag.Tls]` global is an ordinary shared global, so
  every "one copy per thread" design built on it is silently one shared copy. The language
  reference documents the feature as working
  ([003_005_variables.swg:128-131](bin/reference/modules/language/src/003_005_variables.swg#L128-L131)).
- Evidence: a native program writes `0xAAAA` into a `#[Swag.Tls] var u64` on the main thread; a raw
  `CreateThread` worker reads back `0xAAAA` (a real slot reads 0), writes `0xBBBB`, and the main
  thread then reads `0xBBBB`. The three users in `bin/` are the allocator's per-thread heap
  ([allocator.swg:66](bin/runtime/allocator.swg#L66)), `Random.shared()`
  ([random.swg:3](bin/std/modules/core/src/rand/random.swg#L3)), and the Mersenne Twister plus
  counter behind `Guid64`/`Guid128`
  ([guid64.swg:6](bin/std/modules/core/src/system/guid64.swg#L6),
  [guid128.swg:6](bin/std/modules/core/src/system/guid128.swg#L6)), so identifier and random
  streams are raced on and can repeat across threads.
- Next step: decide between implementing the attribute (a `.tls` section and an
  `IMAGE_TLS_DIRECTORY` in the PE writer and the integrated linker, plus an equivalent under the
  JIT) and rejecting it with a diagnostic. Either way the three `bin/` users need a mechanism that
  exists today: an explicit slot through `__tlsAlloc`/`__tlsGetPtr`, which is already how the
  runtime context reaches per-thread storage
  ([os_windows.swg:298](bin/runtime/os_windows.swg#L298)).
- Related: the allocator entry below, whose severity comes from this one.

### The runtime allocator spends a page per block and strands blocks across threads

- Area: bin/std | compiler
- Found while: reproducing an sCrypt WinFsp mount in the privileged integration test, which
  reached about 760 MiB in release and about 835 MiB in fast-debug for a 64 MiB container
- Observation: three compounding costs, none of them specific to sCrypt. `osAlloc` takes one
  `VirtualAlloc(MEM_RESERVE | MEM_COMMIT)` per block
  ([allocator.swg:246](bin/runtime/allocator.swg#L246)), so any block below about 3.7 KiB costs a
  full committed page and a 64 KiB address-space reservation. `trimThreadHeap` measures its 8 MiB
  budget in user class bytes ([allocator.swg:493](bin/runtime/allocator.swg#L493)), which
  understates the committed cost by the same factor, so the trim almost never fires. And because
  the per-thread heap pointer is not actually thread-local, `threadHeap` keeps meeting a heap owned
  by another thread, builds a replacement, and abandons the previous one without retiring it
  ([allocator.swg:318-336](bin/runtime/allocator.swg#L318-L336)) while `freeBlock` parks blocks on
  the remote free list of a heap nobody will ever drain
  ([allocator.swg:927-940](bin/runtime/allocator.swg#L927-L940)).
- Evidence: measured with a native probe reading `PROCESS_MEMORY_COUNTERS` and the allocator
  counters. One thread holding 40 000 live 32-byte blocks (1.25 MiB of payload) takes the working
  set from 4 MiB to 160 MiB; freeing all of them changes nothing while `sizeCached` reports
  1250 KiB against an 8 MiB budget; `releaseAllocatorThreadCache()` returns it to 4 MiB. Four
  concurrent raw OS threads that each allocate and free 10 000 blocks leave 64 207 regions
  outstanding at 254 MiB, and repeating the identical round reaches 504 MiB then 752 MiB. At
  1000 blocks per thread the same four threads issue 6304 raw allocations for 4004 requested
  blocks with an empty retired-heap list, which is `threadHeap` rebuilding heaps it then drops.
  sCrypt runs every filesystem callback on WinFsp's own dispatcher threads
  ([winfspmount.win32.swg:86](bin/apps/modules/sCrypt/src/winfsp/winfspmount.win32.swg#L86)), and
  each callback allocates, which is why the integration run lands where it does.
- Next step: three separable decisions. Carve small blocks out of larger OS reservations instead
  of one `VirtualAlloc` per block; account the trim budget in committed bytes rather than user
  class bytes; and, once a real thread-local exists, make `threadHeap` retire the heap it replaces
  and give an orphaned heap's remote free list an owner. The first alone removes most of the
  factor of 128 measured above.
- Related: the `#[Swag.Tls]` entry above.

### Remaining DPI work: icon sources and the in-place capture editor

- Area: bin/std
- Found while: making `std/gui` and `Env.Window` per-monitor DPI aware (surfaces are physical
  windows, the window tree stays logical, the renderer maps painter streams through
  `Painter.contentScale`, and theme tiles sample with sharp bilinear at fractional scales)
- Observation: the 24/64-pixel icon atlases are still 1x raster sources, so at 150% an icon is a
  sharpened upscale rather than a re-rasterization; SVG sources rendered per scale would make
  them native. Separately, sCapture's in-place capture editor mixes desktop-physical and logical
  spaces in its editing overlay; the grab flow, bars, and 1:1 capture display were adapted, but
  the gizmo/form editing interactions inside the in-place overlay have not been visually
  verified on a scaled or mixed-DPI multi-monitor setup.
- Evidence: gui2 and the dark default theme at 150% show crisp text, hairlines, and tile
  borders. The theme widgets atlas, the theme icon set, and sCapture's application icon set
  are now vector sources (`gui/src/theme/widgets.svg`, `gui/src/theme/icons.svg`,
  `sCapture/datas/icons.svg` — the two icon sets from Fluent UI System Icons) rasterized per
  size and scale through `Gui.IconSet`, so the only remaining raster source is the spinner
  strip (`theme/spin.png`). sCapture compiles and the main grab path converts spaces
  explicitly (`capturerectwnd.swg`, `screenshot.swg`, `inplaceeditwnd.swg`).
- Next step: fold the spinner into a vector or procedural form, then run a capture and
  in-place edit session on a 150% display and on mixed-DPI monitors, and fix the remaining
  space mismatches the session exposes.
