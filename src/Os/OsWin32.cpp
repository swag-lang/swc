#include "pch.h"

#include "Os/Os.h"

SWC_BEGIN_NAMESPACE();

#ifdef _WIN32
#include <windows.h>

namespace Os
{
    void initialize()
    {
        SetConsoleOutputCP(65001);
        const HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
        DWORD        mode = 0;
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
                exit(-1); // NOLINT(concurrency-mt-unsafe)
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

    double timerToSeconds(uint64_t timer)
    {
        LARGE_INTEGER freq;
        QueryPerformanceFrequency(&freq);
        return static_cast<double>(timer) / static_cast<double>(freq.QuadPart);
    }

    Utf8 systemError()
    {
        // Get the error message, if any.
        const DWORD errorMessageId = GetLastError();
        if (errorMessageId == 0)
            return Utf8{};

        DWORD langId = 0;
        GetLocaleInfoEx(LOCALE_NAME_SYSTEM_DEFAULT, LOCALE_ILANGUAGE | LOCALE_RETURN_NUMBER, reinterpret_cast<LPWSTR>(&langId), sizeof(langId) / sizeof(wchar_t));

        LPSTR messageBuffer = nullptr;

        const size_t size = FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                                           nullptr,
                                           errorMessageId,
                                           langId,
                                           reinterpret_cast<LPSTR>(&messageBuffer),
                                           0,
                                           nullptr);
        if (!size)
            return Utf8{};

        // Remove unwanted characters
        const auto pz = messageBuffer;
        for (uint32_t i = 0; i < size; i++)
        {
            const uint8_t c = static_cast<uint8_t>(pz[i]);
            if (c < 32)
                pz[i] = 32;
        }

        Utf8 message(std::string_view{messageBuffer, static_cast<uint32_t>(size)});
        message.trim();
        if (!message.empty() && message.back() == '.')
            message.pop_back();

        // Free the buffer.
        LocalFree(messageBuffer);
        return message;
    }    
}

#endif // _WIN32

SWC_END_NAMESPACE();
