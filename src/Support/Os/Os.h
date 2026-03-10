#pragma once
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif

SWC_BEGIN_NAMESPACE();

enum class ExitCode;
class JITMemory;
class TaskContext;

namespace Os
{
    enum class ProcessRunResult : uint8_t
    {
        Ok,
        StartFailed,
        WaitFailed,
        ExitCodeFailed,
    };

    enum class WindowsToolchainDiscoveryResult : uint8_t
    {
        Ok,
        MissingMsvcToolchain,
        MissingWindowsSdk,
    };

    struct WindowsToolchainPaths
    {
        fs::path linkExe;
        fs::path libExe;
        fs::path vcLibPath;
        fs::path sdkUmLibPath;
        fs::path sdkUcrtLibPath;
    };

    void initialize();

    void panicBox(const char* expr);
    Utf8 systemError();

    [[noreturn]]
    void exit(ExitCode code);
    [[noreturn]]
    void terminate();

    fs::path                        getTemporaryPath();
    fs::path                        getExeFullName();
    ProcessRunResult                runProcess(uint32_t& outExitCode, const fs::path& exePath, std::span<const Utf8> args, const fs::path& workingDirectory);
    WindowsToolchainDiscoveryResult discoverWindowsToolchainPaths(WindowsToolchainPaths& outToolchain);

    bool isDebuggerAttached();

    uint32_t memoryPageSize();
    void*    allocExecutableMemory(uint32_t size);
    bool     makeWritableExecutableMemory(void* ptr, uint32_t size);
    bool     makeExecutableMemory(void* ptr, uint32_t size);
    void     freeExecutableMemory(void* ptr);
    bool     addHostJitFunctionTable(JITMemory& executableMemory);
    void     removeHostJitFunctionTable(JITMemory& executableMemory);
    bool     loadJitSymbolFile(JITMemory& executableMemory, const fs::path& imagePath, std::string_view moduleName, uint64_t imageBase, uint32_t imageSize);
    void     unloadJitSymbolFile(JITMemory& executableMemory);
    bool     loadExternalModule(void*& outModuleHandle, std::string_view moduleName);
    bool     getExternalSymbolAddress(void*& outFunctionAddress, void* moduleHandle, std::string_view functionName);
    uint64_t tlsAlloc();
    void     tlsSetValue(uint64_t id, void* value);
    void*    tlsGetValue(uint64_t id);

    const char* hostOsName();
    const char* hostCpuName();
    const char* hostExceptionBackendName();
    uint32_t    currentProcessId();
    uint32_t    currentThreadId();
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
#define SWC_LP_EXCEPTION_POINTERS        LPEXCEPTION_POINTERS
#define SWC_GET_EXCEPTION_INFOS()        GetExceptionInformation()
#endif

SWC_END_NAMESPACE();
