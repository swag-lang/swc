#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>

#include "Main/ExitCodes.h"

namespace
{
    constexpr char missingAvx2Message[] =
        "fatal error: swc needs a CPU with AVX2 (x86-64-v3)\n"
        "note: swc emits x86-64-v3 code and executes it in its own JIT, so the host CPU needs it too\n";

    void NTAPI verifyHostCpu(PVOID, const DWORD reason, PVOID)
    {
        if (reason != DLL_PROCESS_ATTACH || IsProcessorFeaturePresent(PF_AVX2_INSTRUCTIONS_AVAILABLE))
            return;

        const HANDLE stderrHandle = GetStdHandle(STD_ERROR_HANDLE);
        if (stderrHandle && stderrHandle != INVALID_HANDLE_VALUE)
        {
            DWORD written;
            (void) WriteFile(stderrHandle, missingAvx2Message, static_cast<DWORD>(sizeof(missingAvx2Message) - 1), &written, nullptr);
        }

        (void) TerminateProcess(GetCurrentProcess(), static_cast<UINT>(swc::ExitCode::ErrorCommand));
        for (;;)
            Sleep(INFINITE);
    }
}

// The loader walks TLS callbacks before the CRT and C++ initializers. XLAA sorts immediately
// after the CRT's XLA sentinel and before mimalloc's XLB callback and the CRT's XLC callback.
#pragma section(".CRT$XLAA", long, read)
extern "C" __declspec(allocate(".CRT$XLAA")) PIMAGE_TLS_CALLBACK const swcHostCpuGuard = verifyHostCpu;

#pragma comment(linker, "/include:_tls_used")
#pragma comment(linker, "/include:swcHostCpuGuard")
