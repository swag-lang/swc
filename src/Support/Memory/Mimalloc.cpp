#if SWC_DEV_MODE
#define MI_SECURE 3
#define MI_DEBUG  3
#endif

// Every worker thread owns one heap, and each heap holds a 64 KiB page per size class it
// touches. Committing those pages whole charged the process about 3.5 MiB per worker that
// no block ever reached, so a small program compiled on a many-core host paid three times
// what one worker needs. Small pages now commit as their free list grows, one step at a time.
#define MI_PAGE_MIN_COMMIT_SIZE (16 * 1024)

// Every configuration defines NDEBUG, including DevMode, which deliberately turns mimalloc's
// internal checks back on. mimalloc warns about that combination; the pairing is the intent here.
#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable : 5295)
#endif

// ReSharper disable once CppUnusedIncludeDirective
#include "Support/Memory/mimalloc/src/static.c" // NOLINT(bugprone-suspicious-include)

#ifdef _MSC_VER
#pragma warning(pop)
#endif
