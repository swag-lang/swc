#pragma once

#ifdef __linux__
SWC_BEGIN_NAMESPACE();

namespace Os
{
    struct LinuxException
    {
        uint32_t signal = 0;
        int32_t signalCode = 0;
        uintptr_t instructionAddress = 0;
        uintptr_t faultAddress = 0;
        // x86-64 DWARF register order, followed by RIP at index 16.
        std::array<uint64_t, 17> registers{};
        std::array<uintptr_t, 64> frames{};
        uint32_t frameCount = 0;
    };

    // Signal-safe lookup. The caller must still keep executing JIT memory alive.
    bool isRegisteredJitCode(uintptr_t address);

    // Recover synchronous faults originating in registered generated code. Native
    // C++ cleanup is unwound before returning false; ordinary C++ exceptions propagate.
    // Foreign noexcept/catch-all boundaries must permit unwinding, as for cancellation.
    bool executeWithHostFaultHandler(LinuxException& outException, void (*function)(void*), void* argument);
}

SWC_END_NAMESPACE();
#endif
