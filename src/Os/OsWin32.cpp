#include "pch.h"
#ifdef _WIN32
#include "Main/FileSystem.h"
#include "Os/Os.h"
#include "Report/ExitCodes.h"

SWC_BEGIN_NAMESPACE()

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
            std::exit(static_cast<int>(ExitCode::PanicBox)); // NOLINT(concurrency-mt-unsafe)
        case IDTRYAGAIN:
            DebugBreak();
            break;
        case IDCONTINUE:
            break;
        default:
            break;
        }
    }

    void panicBox(const char* title, const char* expr)
    {
        if (MessageBoxA(nullptr, expr, title, MB_OKCANCEL | MB_ICONERROR) == IDCANCEL)
            std::exit(static_cast<int>(ExitCode::PanicBox)); // NOLINT(concurrency-mt-unsafe)
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

    fs::path getTemporaryFolder()
    {
        char buffer[_MAX_PATH];
        if (GetTempPathA(_MAX_PATH, buffer))
            return buffer;
        return "";
    }

    bool isDebuggerAttached()
    {
        return IsDebuggerPresent() ? true : false;
    }
}

SWC_END_NAMESPACE()

#endif // _WIN32
