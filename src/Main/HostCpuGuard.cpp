#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>

#include "Main/ExitCodes.h"

namespace
{
    constexpr char missingAvx2Message[] =
        "fatal error: swc needs a CPU with AVX2 (x86-64-v3)\r\n"
        "note: swc emits x86-64-v3 code and executes it in its own JIT, so the host CPU needs it too\r\n";

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
#elif defined(__linux__) && defined(__x86_64__)
#include "Main/ExitCodes.h"
#include <errno.h>
#include <unistd.h>

namespace
{
    // This translation unit can be built with the compiler's optimized CPU target. Keep the
    // guard at the baseline ISA: it must reject unsupported hosts before any v3 code runs.
    __attribute__((target("arch=x86-64"))) void verifyHostCpu()
    {
        // Preinit runs before GCC's CPU detection constructor. GCC's v3 predicate includes
        // OSXSAVE/XCR0 support for the AVX register state, not just the CPUID AVX2 bit.
        __builtin_cpu_init();
        if (__builtin_cpu_supports("x86-64-v3"))
            return;

        constexpr char message[] =
            "fatal error: swc needs a CPU with AVX2 (x86-64-v3)\n"
            "note: swc emits x86-64-v3 code and executes it in its own JIT, so the host CPU needs it too\n";
        const char* cursor = message;
        size_t remaining = sizeof(message) - 1;
        while (remaining)
        {
            const ssize_t written = write(STDERR_FILENO, cursor, remaining);
            if (written > 0)
            {
                cursor += written;
                remaining -= static_cast<size_t>(written);
            }
            else if (written == 0 || errno != EINTR)
                break;
        }
        _exit(static_cast<int>(swc::ExitCode::ErrorCommand));
    }
}

// ELF preinit precedes executable and shared-library constructors, including the allocator.
__attribute__((section(".preinit_array"), used)) static void (*const swcHostCpuGuard)() = verifyHostCpu;
#else
#error Unsupported compiler host CPU guard
#endif
