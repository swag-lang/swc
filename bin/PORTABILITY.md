# Portability boundary

Code under `bin/` belongs to one of three dependency layers. Dependencies point down this list;
they never point back up it.

1. **Platform-neutral Swag** owns policy, orchestration, parsing, normalization, data conversion,
   and public contracts. This is every runtime, standard-module, and shipped-application source
   not assigned below. Neutral sources may call portable operations whose implementation is
   supplied by a host leaf, but they do not import a native module, branch on `#os`, name a native
   type or constant, or call a native API.
2. **Host primitives** own the irreducible operating-system mechanisms behind those contracts.
   The Windows runtime leaf, the named Core/GUI/Pixel/Audio Windows leaves, sCapture's capture
   leaf, and sCrypt's `winfsp/` directory belong here. Module setup files may select these leaves
   and their raw dependencies. A host leaf may depend on optional native interoperability, but its
   portable API uses neutral values or opaque native storage.
3. **Optional native interoperability** owns raw ABI declarations and deliberately native
   adapters. The `win32`, `gdi32`, `gdiplus`, `xinput`, and `xaudio2` modules belong here, as do
   explicit adapters such as `Image.from(HBITMAP)`. Interoperability modules may depend only on
   other interoperability modules. Portable code never needs them merely to use Core, GUI, Pixel,
   Audio, or a shipped application.

OpenGL is outside this boundary: the portability roadmap deliberately excludes it. Tests that
exercise a native integration point remain in the host layer and must be selected explicitly.

`swc tools/portability.swgs` checks this contract. Its exact path and declaration approvals live
in `tools/src/portability.swg`; a platform-looking suffix is not an approval. Add a path only when
it owns a narrow host mechanism or optional adapter, and keep transitional public exceptions tied
to their backlog entry. Every repository test campaign runs the same audit before compiling.
