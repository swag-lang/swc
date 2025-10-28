#include "pch.h"
#ifdef _WIN32

#include "Main/FileSystem.h"
#include "Os/Os.h"
#include <windows.h>

SWC_BEGIN_NAMESPACE();

namespace Os
{
    void initialize()
    {
        SetConsoleCP(CP_UTF8);
        SetConsoleOutputCP(CP_UTF8);
        const HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
        if (hOut != INVALID_HANDLE_VALUE)
        {
            DWORD mode = 0;
            if (GetConsoleMode(hOut, &mode))
            {
                mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
                SetConsoleMode(hOut, mode);
            }
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

    Utf8 systemError()
    {
        const DWORD id = GetLastError();
        if (id == 0)
            return {};

        LPWSTR          buf   = nullptr;
        constexpr DWORD flags = FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS | FORMAT_MESSAGE_MAX_WIDTH_MASK;

        auto formatWithLang = [&](DWORD lang) -> DWORD {
            return FormatMessageW(flags, nullptr, id, lang,
                                  reinterpret_cast<LPWSTR>(&buf),
                                  0, nullptr);
        };

        // 1) Try English (US) if requested
        constexpr DWORD enUs = MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US);
        DWORD           len  = formatWithLang(enUs);

        // 2) Fallback to "let the system pick"
        if (len == 0)
            len = formatWithLang(0);
        if (len == 0 || !buf)
            return {};

        // Convert to UTF-8
        const int lenBytes = WideCharToMultiByte(CP_UTF8, 0, buf, static_cast<int>(len), nullptr, 0, nullptr, nullptr);
        Utf8      msg;
        if (lenBytes > 0)
        {
            msg.resize(lenBytes);
            WideCharToMultiByte(CP_UTF8, 0, buf, static_cast<int>(len), msg.data(), lenBytes, nullptr, nullptr);
        }
        LocalFree(buf);

        return FileSystem::normalizeSystemMessage(msg);
    }
}

SWC_END_NAMESPACE();

#endif // _WIN32
