#include "pch.h"
#ifdef _WIN32
#include "Main/CommandLine.h"
#include "Main/ExitCodes.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include <dbghelp.h>

#pragma comment(lib, "Dbghelp.lib")

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_OS_FIELD_WIDTH = 24;

    void appendOsField(Utf8& outMsg, const std::string_view label, const std::string_view value, const uint32_t leftPadding = 0)
    {
        for (uint32_t i = 0; i < leftPadding; ++i)
            outMsg += " ";

        outMsg += label;
        outMsg += ":";
        uint32_t used = static_cast<uint32_t>(label.size()) + 1;
        while (used < K_OS_FIELD_WIDTH)
        {
            outMsg += " ";
            ++used;
        }

        outMsg += value;
        outMsg += "\n";
    }

    struct SymbolEngineState
    {
        std::mutex mutex;
        bool       attempted   = false;
        bool       initialized = false;
    };

    SymbolEngineState& symbolEngineState()
    {
        static SymbolEngineState state;
        return state;
    }

    bool ensureSymbolEngineInitialized()
    {
        SymbolEngineState& state = symbolEngineState();
        std::scoped_lock   lock(state.mutex);

        if (!state.attempted)
        {
            state.attempted      = true;
            const HANDLE process = GetCurrentProcess();
            SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES);
            state.initialized = SymInitialize(process, nullptr, TRUE) == TRUE;
        }

        return state.initialized;
    }

    const char* windowsExceptionCodeName(const uint32_t code)
    {
        switch (code)
        {
            case EXCEPTION_ACCESS_VIOLATION:
                return "EXCEPTION_ACCESS_VIOLATION";
            case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:
                return "EXCEPTION_ARRAY_BOUNDS_EXCEEDED";
            case EXCEPTION_BREAKPOINT:
                return "EXCEPTION_BREAKPOINT";
            case EXCEPTION_DATATYPE_MISALIGNMENT:
                return "EXCEPTION_DATATYPE_MISALIGNMENT";
            case EXCEPTION_FLT_DENORMAL_OPERAND:
                return "EXCEPTION_FLT_DENORMAL_OPERAND";
            case EXCEPTION_FLT_DIVIDE_BY_ZERO:
                return "EXCEPTION_FLT_DIVIDE_BY_ZERO";
            case EXCEPTION_FLT_INEXACT_RESULT:
                return "EXCEPTION_FLT_INEXACT_RESULT";
            case EXCEPTION_FLT_INVALID_OPERATION:
                return "EXCEPTION_FLT_INVALID_OPERATION";
            case EXCEPTION_FLT_OVERFLOW:
                return "EXCEPTION_FLT_OVERFLOW";
            case EXCEPTION_FLT_STACK_CHECK:
                return "EXCEPTION_FLT_STACK_CHECK";
            case EXCEPTION_FLT_UNDERFLOW:
                return "EXCEPTION_FLT_UNDERFLOW";
            case EXCEPTION_ILLEGAL_INSTRUCTION:
                return "EXCEPTION_ILLEGAL_INSTRUCTION";
            case EXCEPTION_IN_PAGE_ERROR:
                return "EXCEPTION_IN_PAGE_ERROR";
            case EXCEPTION_INT_DIVIDE_BY_ZERO:
                return "EXCEPTION_INT_DIVIDE_BY_ZERO";
            case EXCEPTION_INT_OVERFLOW:
                return "EXCEPTION_INT_OVERFLOW";
            case EXCEPTION_INVALID_DISPOSITION:
                return "EXCEPTION_INVALID_DISPOSITION";
            case EXCEPTION_NONCONTINUABLE_EXCEPTION:
                return "EXCEPTION_NONCONTINUABLE_EXCEPTION";
            case EXCEPTION_PRIV_INSTRUCTION:
                return "EXCEPTION_PRIV_INSTRUCTION";
            case EXCEPTION_SINGLE_STEP:
                return "EXCEPTION_SINGLE_STEP";
            case EXCEPTION_STACK_OVERFLOW:
                return "EXCEPTION_STACK_OVERFLOW";
            default:
                return "UNKNOWN_EXCEPTION";
        }
    }

    const char* windowsAccessViolationOpName(const ULONG_PTR op)
    {
        switch (op)
        {
            case 0:
                return "read";
            case 1:
                return "write";
            case 8:
                return "execute";
            default:
                return "unknown";
        }
    }

    const char* windowsProtectToString(const DWORD protect)
    {
        switch (protect & 0xFF)
        {
            case PAGE_NOACCESS:
                return "NOACCESS";
            case PAGE_READONLY:
                return "READONLY";
            case PAGE_READWRITE:
                return "READWRITE";
            case PAGE_WRITECOPY:
                return "WRITECOPY";
            case PAGE_EXECUTE:
                return "EXECUTE";
            case PAGE_EXECUTE_READ:
                return "EXECUTE_READ";
            case PAGE_EXECUTE_READWRITE:
                return "EXECUTE_READWRITE";
            case PAGE_EXECUTE_WRITECOPY:
                return "EXECUTE_WRITECOPY";
            default:
                return "UNKNOWN";
        }
    }

    const char* windowsStateToString(const DWORD state)
    {
        switch (state)
        {
            case MEM_COMMIT:
                return "COMMIT";
            case MEM_FREE:
                return "FREE";
            case MEM_RESERVE:
                return "RESERVE";
            default:
                return "UNKNOWN";
        }
    }

    const char* windowsTypeToString(const DWORD type)
    {
        switch (type)
        {
            case MEM_IMAGE:
                return "IMAGE";
            case MEM_MAPPED:
                return "MAPPED";
            case MEM_PRIVATE:
                return "PRIVATE";
            default:
                return "UNKNOWN";
        }
    }

    bool appendWindowsAddressSymbol(Utf8& outMsg, const TaskContext* ctx, const uint64_t address, const uint32_t leftPadding = 0)
    {
        if (!address)
            return false;
        if (!ensureSymbolEngineInitialized())
            return false;

        SymbolEngineState& state = symbolEngineState();
        std::scoped_lock   lock(state.mutex);
        bool               hasInfo = false;

        const HANDLE                                            process = GetCurrentProcess();
        std::array<uint8_t, sizeof(SYMBOL_INFO) + MAX_SYM_NAME> symbolBuffer{};

        const auto symbol    = reinterpret_cast<SYMBOL_INFO*>(symbolBuffer.data());
        symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
        symbol->MaxNameLen   = MAX_SYM_NAME;

        DWORD64 displacement = 0;
        if (SymFromAddr(process, address, &displacement, symbol))
        {
            appendOsField(outMsg, "symbol", std::format("{} + 0x{:X}", symbol->Name, static_cast<uint64_t>(displacement)), leftPadding);
            hasInfo = true;
        }

        IMAGEHLP_LINE64 lineInfo{};
        lineInfo.SizeOfStruct = sizeof(lineInfo);
        DWORD lineDisp        = 0;
        if (SymGetLineFromAddr64(process, address, &lineDisp, &lineInfo))
        {
            const Utf8 fileLoc = FileSystem::formatFileLocation(ctx, fs::path(lineInfo.FileName), lineInfo.LineNumber);
            appendOsField(outMsg, "source", std::format("{} (+{})", fileLoc, lineDisp), leftPadding);
            hasInfo = true;
        }

        return hasInfo;
    }

    void appendWindowsAddress(Utf8& outMsg, const TaskContext* ctx, const uint64_t address)
    {
        outMsg += std::format("0x{:016X}", address);
        if (!address)
            return;

        MEMORY_BASIC_INFORMATION mbi{};
        if (!VirtualQuery(reinterpret_cast<LPCVOID>(static_cast<uintptr_t>(address)), &mbi, sizeof(mbi)))
            return;

        const uintptr_t modBase = reinterpret_cast<uintptr_t>(mbi.AllocationBase);
        if (modBase)
        {
            char        modulePath[MAX_PATH + 1]{};
            const DWORD len = GetModuleFileNameA(reinterpret_cast<HMODULE>(modBase), modulePath, MAX_PATH);
            if (len)
            {
                modulePath[len]       = 0;
                const Utf8 moduleName = FileSystem::formatFileName(ctx, fs::path(modulePath));
                outMsg += std::format(" ({} + 0x{:X})", moduleName, address - modBase);
            }
        }

        outMsg += "\n";
        if (modBase)
        {
            char        modulePath[MAX_PATH + 1]{};
            const DWORD len = GetModuleFileNameA(reinterpret_cast<HMODULE>(modBase), modulePath, MAX_PATH);
            if (len)
            {
                modulePath[len] = 0;
                appendOsField(outMsg, "module path", modulePath);
            }
        }

        appendWindowsAddressSymbol(outMsg, ctx, address);
        appendOsField(outMsg, "memory", std::format("state={}, type={}, protect={}", windowsStateToString(mbi.State), windowsTypeToString(mbi.Type), windowsProtectToString(mbi.Protect)));
    }
}

namespace Os
{
    const char* hostOsName()
    {
        return "windows";
    }

    const char* hostCpuName()
    {
#ifdef _M_X64
        return "x64";
#elifdef _M_IX86
        return "x86";
#else
        return "unknown-cpu";
#endif
    }

    const char* hostExceptionBackendName()
    {
        return "windows seh";
    }

    uint32_t currentProcessId()
    {
        return static_cast<uint32_t>(GetCurrentProcessId());
    }

    uint32_t currentThreadId()
    {
        return static_cast<uint32_t>(GetCurrentThreadId());
    }

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

        const int result = MessageBoxA(nullptr, msg, "Swc meditation!", MB_CANCELTRYCONTINUE | MB_ICONERROR);
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

        const Utf8    moduleFileName = modulePath.string();
        const HMODULE moduleHandle   = LoadLibraryA(moduleFileName.c_str());
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

        const Utf8    functionNameUtf8{functionName};
        const FARPROC func = GetProcAddress(static_cast<HMODULE>(moduleHandle), functionNameUtf8.c_str());
        if (!func)
            return false;

        outFunctionAddress = reinterpret_cast<void*>(func);
        return true;
    }

    void appendHostExceptionSummary(const TaskContext& ctx, Utf8& outMsg, const void* platformExceptionPointers)
    {
        const auto* args   = static_cast<const EXCEPTION_POINTERS*>(platformExceptionPointers);
        const auto* record = args ? args->ExceptionRecord : nullptr;
        if (!record)
        {
            appendOsField(outMsg, "record", "none");
            return;
        }

        appendOsField(outMsg, "code", std::format("0x{:08X} ({})", record->ExceptionCode, windowsExceptionCodeName(record->ExceptionCode)));
        Utf8 addressMsg;
        appendWindowsAddress(addressMsg, &ctx, reinterpret_cast<uintptr_t>(record->ExceptionAddress));
        while (!addressMsg.empty() && addressMsg.back() == '\n')
            addressMsg.pop_back();
        appendOsField(outMsg, "address", addressMsg);

        if (record->NumberParameters)
            appendOsField(outMsg, "parameters", std::format("{}", record->NumberParameters));

        if ((record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION || record->ExceptionCode == EXCEPTION_IN_PAGE_ERROR) && record->NumberParameters >= 2)
        {
            Utf8 accessMsg;
            accessMsg += std::format("{} at ", windowsAccessViolationOpName(record->ExceptionInformation[0]));
            appendWindowsAddress(accessMsg, &ctx, record->ExceptionInformation[1]);
            while (!accessMsg.empty() && accessMsg.back() == '\n')
                accessMsg.pop_back();
            appendOsField(outMsg, "access", accessMsg);
        }
    }

    void appendHostCpuContext(Utf8& outMsg, const void* platformExceptionPointers)
    {
        const auto* args    = static_cast<const EXCEPTION_POINTERS*>(platformExceptionPointers);
        const auto* context = args ? args->ContextRecord : nullptr;
        if (!context)
        {
            outMsg += "<null>\n";
            return;
        }

#ifdef _M_X64
        outMsg += std::format("rip=0x{:016X} rsp=0x{:016X} rbp=0x{:016X}\n", context->Rip, context->Rsp, context->Rbp);
        outMsg += std::format("rax=0x{:016X} rbx=0x{:016X} rcx=0x{:016X} rdx=0x{:016X}\n", context->Rax, context->Rbx, context->Rcx, context->Rdx);
        outMsg += std::format("rsi=0x{:016X} rdi=0x{:016X} r8=0x{:016X} r9=0x{:016X}\n", context->Rsi, context->Rdi, context->R8, context->R9);
        outMsg += std::format("r10=0x{:016X} r11=0x{:016X} r12=0x{:016X} r13=0x{:016X}\n", context->R10, context->R11, context->R12, context->R13);
        outMsg += std::format("r14=0x{:016X} r15=0x{:016X} eflags=0x{:08X}\n", context->R14, context->R15, context->EFlags);
#else
        outMsg += "unsupported architecture\n";
#endif
    }

    void appendHostHandlerStack(const TaskContext& ctx, Utf8& outMsg)
    {
        void*        frames[64]{};
        const USHORT numFrames = ::CaptureStackBackTrace(0, std::size(frames), frames, nullptr);

        for (uint32_t i = 0; i < numFrames; ++i)
        {
            const uintptr_t address = reinterpret_cast<uintptr_t>(frames[i]);
            outMsg += std::format("[{:02}] 0x{:016X}", i, address);

            MEMORY_BASIC_INFORMATION mbi{};
            if (VirtualQuery(reinterpret_cast<LPCVOID>(address), &mbi, sizeof(mbi)))
            {
                const uintptr_t modBase = reinterpret_cast<uintptr_t>(mbi.AllocationBase);
                if (modBase)
                {
                    char        modulePath[MAX_PATH + 1]{};
                    const DWORD len = GetModuleFileNameA(reinterpret_cast<HMODULE>(modBase), modulePath, MAX_PATH);
                    if (len)
                    {
                        modulePath[len]       = 0;
                        const Utf8 moduleName = FileSystem::formatFileName(&ctx, fs::path(modulePath));
                        outMsg += std::format("  {} + 0x{:X}", moduleName, address - modBase);
                    }
                }
            }

            outMsg += "\n";
            if (!appendWindowsAddressSymbol(outMsg, &ctx, address, 4))
                appendOsField(outMsg, "symbol", "<unresolved>", 4);
        }
    }

    void exit(ExitCode code)
    {
        ExitProcess(static_cast<int>(code));
    }
}

SWC_END_NAMESPACE();

#endif // _WIN32
