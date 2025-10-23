#include "pch.h"

#include "Os/Os.h"

#ifdef _WIN32
#include <windows.h>

namespace Os
{
    void initialize()
    {
        SetConsoleOutputCP(65001);
        const HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
        DWORD  mode = 0;
        if (GetConsoleMode(hOut, &mode))
        {
            mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
            SetConsoleMode(hOut, mode);
        }        
    }

    void assertBox(const char* expr, const char* file, int line)
    {
        char msg[2048];

        (void) snprintf(msg, sizeof(msg),
                        "Assertion failed\n\n"
                        "File: %s\n"
                        "Line: %d\n"
                        "Expression: %s\n",
                        file, line, expr);

        const auto result = MessageBoxA(nullptr, msg, "Swag meditation !", MB_CANCELTRYCONTINUE | MB_ICONERROR);
        switch (result)
        {
            case IDCANCEL:
                exit(-1);  // NOLINT(concurrency-mt-unsafe)
            case IDTRYAGAIN:
                DebugBreak();
                break;
            case IDCONTINUE:
                break;
            default:
                break;
        }
    }

    uint64_t timerNow()
    {
        LARGE_INTEGER res;
        QueryPerformanceCounter(&res);
        return res.QuadPart;
    }    
}

#endif // _WIN32
