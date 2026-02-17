#include "pch.h"
#ifdef _WIN32
#include "Main/CommandLine.h"
#include "Main/ExitCodes.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"

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

    void panicBox(const char* expr)
    {
        std::println(stderr, "panic: {}", expr ? expr : "<null>");
        (void) std::fflush(stderr);

        if (!CommandLine::dbgDevMode)
            exit(ExitCode::PanicBox);

        char msg[2048];
        SWC_ASSERT(std::strlen(expr) < 1024);

        (void) snprintf(msg, sizeof(msg),
                        "%s\n\n"
                        "Press 'Cancel' to exit\n"
                        "Press 'Retry' to break\n",
                        expr);

        const auto result = MessageBoxA(nullptr, msg, "Swc meditation!", MB_CANCELTRYCONTINUE | MB_ICONERROR);
        switch (result)
        {
            case IDCANCEL:
                exit(ExitCode::PanicBox);
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

        // Try English (US) if requested
        constexpr DWORD enUs = MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US);
        DWORD           len  = FormatMessageW(flags, nullptr, id, enUs, reinterpret_cast<LPWSTR>(&buf), 0, nullptr);

        // Fallback to "let the system pick"
        if (len == 0)
            len = FormatMessageW(flags, nullptr, id, 0, reinterpret_cast<LPWSTR>(&buf), 0, nullptr);
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

    fs::path getTemporaryPath()
    {
        char buffer[_MAX_PATH];
        if (GetTempPathA(_MAX_PATH, buffer))
            return buffer;
        return "";
    }

    fs::path getExeFullName()
    {
        char az[_MAX_PATH];
        GetModuleFileNameA(nullptr, az, _MAX_PATH);
        return az;
    }

    bool isDebuggerAttached()
    {
        return IsDebuggerPresent() ? true : false;
    }

    uint32_t memoryPageSize()
    {
        SYSTEM_INFO info;
        GetSystemInfo(&info);
        return info.dwPageSize;
    }

    void* allocExecutableMemory(uint32_t size)
    {
        return VirtualAlloc(nullptr, size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    }

    bool makeWritableExecutableMemory(void* ptr, uint32_t size)
    {
        DWORD oldProtect = 0;
        return VirtualProtect(ptr, size, PAGE_EXECUTE_READWRITE, &oldProtect) ? true : false;
    }

    bool makeExecutableMemory(void* ptr, uint32_t size)
    {
        DWORD oldProtect = 0;
        if (!VirtualProtect(ptr, size, PAGE_EXECUTE_READ, &oldProtect))
            return false;

        return FlushInstructionCache(GetCurrentProcess(), ptr, size) ? true : false;
    }

    void freeExecutableMemory(void* ptr)
    {
        if (!ptr)
            return;
        (void) VirtualFree(ptr, 0, MEM_RELEASE);
    }

    bool loadExternalModule(void*& outModuleHandle, std::string_view moduleName)
    {
        outModuleHandle = nullptr;
        if (moduleName.empty())
            return false;

        const Utf8 moduleNameUtf8{moduleName};
        fs::path   modulePath{moduleNameUtf8.c_str()};
        if (!modulePath.has_extension())
            modulePath += ".dll";

        const Utf8 moduleFileName = modulePath.string();
        auto*      moduleHandle   = LoadLibraryA(moduleFileName.c_str());
        if (!moduleHandle)
            return false;

        outModuleHandle = moduleHandle;
        return true;
    }

    bool getExternalSymbolAddress(void*& outFunctionAddress, void* moduleHandle, std::string_view functionName)
    {
        outFunctionAddress = nullptr;
        if (!moduleHandle || functionName.empty())
            return false;

        const Utf8 functionNameUtf8{functionName};
        auto*      func = GetProcAddress(static_cast<HMODULE>(moduleHandle), functionNameUtf8.c_str());
        if (!func)
            return false;

        outFunctionAddress = reinterpret_cast<void*>(func);
        return true;
    }

    void exit(ExitCode code)
    {
        ExitProcess(static_cast<int>(code));
    }
}

SWC_END_NAMESPACE();

#endif // _WIN32
