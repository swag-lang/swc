#pragma once
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif

SWC_BEGIN_NAMESPACE()

namespace Os
{
    void initialize();

    void assertBox(const char* expr, const char* file, int line);
    void panicBox(const char* expr);
    Utf8 systemError();

    fs::path getTemporaryFolder();

    bool isDebuggerAttached();
}

#ifdef _WIN32
#define SWC_TRY                          __try
#define SWC_EXCEPT                       __except
#define SWC_EXCEPTION_EXECUTE_HANDLER    EXCEPTION_EXECUTE_HANDLER
#define SWC_EXCEPTION_CONTINUE_EXECUTION EXCEPTION_CONTINUE_EXECUTION
#define SWC_LP_EXCEPTION_POINTERS        LPEXCEPTION_POINTERS
#define SWC_GET_EXCEPTION_INFOS()        GetExceptionInformation()
#endif

SWC_END_NAMESPACE()
