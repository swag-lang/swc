#pragma once
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif

SWC_BEGIN_NAMESPACE();

enum class ExitCode;

namespace Os
{
    void initialize();

    void panicBox(const char* expr);
    Utf8 systemError();

    [[noreturn]]
    void exit(ExitCode code);

    fs::path getTemporaryPath();
    fs::path getExeFullName();

    bool isDebuggerAttached();

    uint32_t memoryPageSize();
    void*    allocExecutableMemory(uint32_t size);
    bool     makeWritableExecutableMemory(void* ptr, uint32_t size);
    bool     makeExecutableMemory(void* ptr, uint32_t size);
    void     freeExecutableMemory(void* ptr);
    bool     loadExternalModule(void*& outModuleHandle, std::string_view moduleName);
    bool     getExternalSymbolAddress(void*& outFunctionAddress, void* moduleHandle, std::string_view functionName);
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
