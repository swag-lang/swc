#if SWC_DEV_MODE
#define MI_SECURE 3
#define MI_DEBUG  3
#endif

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
