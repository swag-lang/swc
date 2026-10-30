# mimalloc integration

The `mimalloc/` directory contains Microsoft mimalloc **3.6.0**, from the official
[v3.6.0 tag](https://github.com/microsoft/mimalloc/releases/tag/v3.6.0).
Generated `docs/` output is omitted, as in the previous import. There are no local source patches.

Archive: `https://codeload.github.com/microsoft/mimalloc/tar.gz/refs/tags/v3.6.0`

SHA-256: `c663101ba193b5b823c8541c1b719ab67e3ebf9976e425a02359a5cad5e52990`

`Mimalloc.cpp` includes upstream `src/static.c` without the compiler PCH. DevMode retains
`MI_DEBUG=3` and `MI_SECURE=3`. `Allocator.cpp` routes global C++ allocation and deallocation
through mimalloc and configures page commitment on demand and destruction on exit.

The 3.4.3 integration carried three local changes, retired in this import:

- The configurable minimum page commitment and corrected arena commitment comparison are
  covered by upstream's 16 KiB minimum and byte-based comparison in 3.6.0. The wrapper no
  longer overrides `MI_PAGE_MIN_COMMIT_SIZE`.
- Dynamic loading of the Windows privilege APIs is unnecessary: upstream's desktop random
  fallback now links `advapi32.lib`, which the compiler also already links.

Keep future vendor imports pristine where possible. Validate both compiler executables:
DevMode enables stronger allocator checks, and allocations can outlive their worker thread.
