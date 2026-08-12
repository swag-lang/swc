#pragma once
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

enum class ExitCode;
class JITMemory;
class TaskContext;

namespace Os
{
    struct ResolvedAddress
    {
        Utf8 moduleName;
        Utf8 symbolName;
        Utf8 sourceLocation;
    };

    enum class ProcessRunResult : uint8_t
    {
        Ok,
        StartFailed,
        WaitFailed,
        ExitCodeFailed,
        TimedOut,
    };

    enum class WindowsToolchainDiscoveryResult : uint8_t
    {
        Ok,
        MissingMsvcToolchain,
        MissingWindowsSdk,
    };

    struct WindowsToolchainPaths
    {
        fs::path vcLibPath;
        fs::path sdkUmLibPath;
        fs::path sdkUcrtLibPath;
    };

    struct ProcessRunOptions
    {
        std::string*              capturedOutput = nullptr;
        bool                      forwardOutput  = true;
        const TaskContext*        logCtx         = nullptr;
        std::span<const fs::path> additionalPathDirectories;
        void (*outputLineCallback)(void* userData, std::string_view line) = nullptr;
        void* outputLineUserData                                          = nullptr;

        // Lines starting with this prefix are captured but not forwarded (used for
        // machine-readable marker lines like the native test tally).
        std::string_view suppressForwardLinePrefix;

        // Kills the process and reports TimedOut after this many milliseconds; zero waits
        // forever. A run that is supposed to end on its own has to be given a deadline, or a
        // program that stops making progress hangs the whole suite instead of failing it.
        uint32_t timeoutMs = 0;
    };

    struct FileLockOwner
    {
        Utf8     processName;
        uint32_t processId = 0;
    };

    void     initialize();
    bool     stdoutSupportsAnsi();
    bool     stderrSupportsAnsi();
    bool     stdoutSupportsAnimation();
    uint32_t stdoutColumnCount();
    void     setStdoutCursorVisible(bool visible);

    void panicBox(std::string_view expr);
    Utf8 systemError();

    [[noreturn]]
    void exit(ExitCode code);
    [[noreturn]]
    void terminate();

    fs::path                        getTemporaryPath();
    fs::path                        getExeFullName();
    std::optional<Utf8>             readEnvironmentVariable(std::string_view name);
    Utf8                            formatProcessExitCode(uint32_t exitCode);
    Utf8                            formatProcessCommandLine(const fs::path& exePath, std::span<const Utf8> args);
    ProcessRunResult                runProcess(uint32_t& outExitCode, const fs::path& exePath, std::span<const Utf8> args, const fs::path& workingDirectory, const ProcessRunOptions* options = nullptr);
    WindowsToolchainDiscoveryResult discoverWindowsToolchainPaths(WindowsToolchainPaths& outToolchain);

    // Names the processes that hold a file open, mapped, or running — the answer behind an
    // access-denied on a shared library or an executable. Best effort: an empty result means
    // nobody was found, not that nobody holds the file.
    void queryFileLockOwners(std::vector<FileLockOwner>& outOwners, const fs::path& path);

    bool isDebuggerAttached();

    uint32_t memoryPageSize();
    void*    allocExecutableMemory(uint32_t size);
    bool     makeWritableExecutableMemory(void* ptr, uint32_t size);
    bool     makeExecutableMemory(void* ptr, uint32_t size);
    void     freeExecutableMemory(void* ptr);

    // The proximity arena: one reserved region that both JIT code and the
    // compile-time global data segments carve from, so a RIP-relative
    // displacement in JIT-executed code always reaches the segment payload.
    // Page-aligned, committed on demand, read-write; executable carves are
    // reprotected by makeExecutableMemory. Returns null when the region is
    // exhausted - callers fall back to ordinary allocation and RIP-relative
    // patching range-checks the distance it can no longer guarantee.
    void*    allocProximityMemory(uint32_t size);
    bool     isProximityMemory(const void* ptr);
    bool     addHostJitFunctionTable(JITMemory& executableMemory);
    void     removeHostJitFunctionTable(JITMemory& executableMemory);
    void     registerExternalModuleSearchPath(const fs::path& path);
    bool     loadExternalModule(void*& outModuleHandle, std::string_view moduleName);
    bool     getExternalSymbolAddress(void*& outFunctionAddress, void* moduleHandle, std::string_view functionName);
    uint64_t tlsAlloc();
    void     tlsSetValue(uint64_t id, void* value);
    void*    tlsGetValue(uint64_t id);

    const char* hostOsName();
    const char* hostCpuName();
    const char* hostExceptionBackendName();
    bool        isFatalHostException(uint32_t exceptionCode);
    uint32_t    currentProcessId();
    uint32_t    currentThreadId();
    uint32_t    captureCallStack(std::span<uintptr_t> outFrames, uint32_t skipFrames = 0);
    bool        resolveAddress(ResolvedAddress& outAddress, uintptr_t address, const TaskContext* ctx = nullptr);
    size_t      peakProcessMemoryUsage();
    void        decodeHostException(uint32_t& outExceptionCode, const void*& outExceptionAddress, const void* platformExceptionPointers);
    void        appendHostExceptionSummary(const TaskContext* ctx, Utf8& outMsg, const void* platformExceptionPointers);
    void        appendHostCpuContext(Utf8& outMsg, const void* platformExceptionPointers);
    void        appendHostHandlerStack(Utf8& outMsg, const void* platformExceptionPointers, const TaskContext* ctx = nullptr);
}

#ifdef _WIN32
#define SWC_TRY                          __try
#define SWC_EXCEPT                       __except
#define SWC_EXCEPTION_EXECUTE_HANDLER    EXCEPTION_EXECUTE_HANDLER
#define SWC_EXCEPTION_CONTINUE_EXECUTION EXCEPTION_CONTINUE_EXECUTION
#define SWC_EXCEPTION_CONTINUE_SEARCH    EXCEPTION_CONTINUE_SEARCH
#define SWC_LP_EXCEPTION_POINTERS        LPEXCEPTION_POINTERS
#define SWC_GET_EXCEPTION_INFOS()        GetExceptionInformation()
#endif

SWC_END_NAMESPACE();
