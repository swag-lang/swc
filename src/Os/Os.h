#pragma once
SWC_BEGIN_NAMESPACE()

namespace Os
{
    void initialize();

    void assertBox(const char* expr, const char* file, int line);
    void panicBox(const char* title, const char* expr);
    Utf8 systemError();

    bool isDebuggerAttached();
}

#ifdef _WIN32
#define SWC_TRY                          __try
#define SWC_EXCEPT                       __except
#define SWC_EXCEPTION_EXECUTE_HANDLER    EXCEPTION_EXECUTE_HANDLER
#define SWC_EXCEPTION_CONTINUE_EXECUTION EXCEPTION_CONTINUE_EXECUTION
#define SWC_LPEXCEPTION_POINTERS         LPEXCEPTION_POINTERS
#define SWC_GET_EXCEPTION_INFOS()        GetExceptionInformation()
#endif

SWC_END_NAMESPACE()
