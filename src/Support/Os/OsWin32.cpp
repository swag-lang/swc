#include "pch.h"
#ifdef _WIN32
#include "Backend/JIT/JITMemory.h"
#include "Main/CompilerInstance.h"
#include "Main/ExitCodes.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include <dbghelp.h>
#include <psapi.h>

#pragma comment(lib, "Dbghelp.lib")
#pragma comment(lib, "Psapi.lib")

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
        SymbolEngineState&     state = symbolEngineState();
        const std::scoped_lock lock(state.mutex);

        if (!state.attempted)
        {
            state.attempted      = true;
            const HANDLE process = GetCurrentProcess();
            SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES);
            state.initialized = SymInitialize(process, nullptr, TRUE) == TRUE;
        }

        return state.initialized;
    }

    std::wstring toWide(const std::string_view value)
    {
        if (value.empty())
            return {};

        const int wideCount = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
        if (wideCount <= 0)
            return {};

        std::wstring result;
        result.resize(static_cast<size_t>(wideCount));
        MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), wideCount);
        return result;
    }

    void appendQuotedCommandArg(std::wstring& out, const std::wstring_view arg)
    {
        const bool needsQuotes = arg.empty() || arg.find_first_of(L" \t\"") != std::wstring_view::npos;
        if (!needsQuotes)
        {
            out.append(arg);
            return;
        }

        out.push_back(L'"');
        size_t pendingSlashes = 0;
        for (const wchar_t c : arg)
        {
            if (c == L'\\')
            {
                pendingSlashes++;
                continue;
            }

            if (c == L'"')
            {
                out.append(pendingSlashes * 2 + 1, L'\\');
                out.push_back(L'"');
                pendingSlashes = 0;
                continue;
            }

            if (pendingSlashes)
            {
                out.append(pendingSlashes, L'\\');
                pendingSlashes = 0;
            }

            out.push_back(c);
        }

        if (pendingSlashes)
            out.append(pendingSlashes * 2, L'\\');
        out.push_back(L'"');
    }

    std::optional<Utf8> readEnvUtf8(const char* name)
    {
        char*  value  = nullptr;
        size_t length = 0;
        if (_dupenv_s(&value, &length, name) != 0 || !value || !*value)
        {
            if (value)
                std::free(value);
            return std::nullopt;
        }

        Utf8 result(value);
        std::free(value);
        return result;
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

        SymbolEngineState&     state = symbolEngineState();
        const std::scoped_lock lock(state.mutex);
        bool                   hasInfo = false;

        const HANDLE                                            process = GetCurrentProcess();
        std::array<uint8_t, sizeof(SYMBOL_INFO) + MAX_SYM_NAME> symbolBuffer{};

        auto* symbol         = reinterpret_cast<SYMBOL_INFO*>(symbolBuffer.data());
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

        const auto modBase = reinterpret_cast<uintptr_t>(mbi.AllocationBase);
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

    void appendWindowsStackFrame(Utf8& outMsg, const TaskContext* ctx, const uint32_t index, const uintptr_t address)
    {
        outMsg += std::format("[{:02}] 0x{:016X}", index, address);

        MEMORY_BASIC_INFORMATION mbi{};
        if (VirtualQuery(reinterpret_cast<LPCVOID>(address), &mbi, sizeof(mbi)))
        {
            const auto modBase = reinterpret_cast<uintptr_t>(mbi.AllocationBase);
            if (modBase)
            {
                char        modulePath[MAX_PATH + 1]{};
                const DWORD len = GetModuleFileNameA(reinterpret_cast<HMODULE>(modBase), modulePath, MAX_PATH);
                if (len)
                {
                    modulePath[len]       = 0;
                    const Utf8 moduleName = FileSystem::formatFileName(ctx, fs::path(modulePath));
                    outMsg += std::format("  {} + 0x{:X}", moduleName, address - modBase);
                }
            }
        }

        outMsg += "\n";
        if (!appendWindowsAddressSymbol(outMsg, ctx, address, 4))
            appendOsField(outMsg, "symbol", "<unresolved>", 4);
    }

    bool appendWindowsStackFromException(Utf8& outMsg, const void* platformExceptionPointers, const TaskContext* ctx)
    {
#ifdef _M_X64
        const auto* args    = static_cast<const EXCEPTION_POINTERS*>(platformExceptionPointers);
        const auto* context = args ? args->ContextRecord : nullptr;
        if (!context)
            return false;

        (void) ensureSymbolEngineInitialized();

        CONTEXT      walkContext = *context;
        STACKFRAME64 frame{};
        frame.AddrPC.Offset    = walkContext.Rip;
        frame.AddrPC.Mode      = AddrModeFlat;
        frame.AddrFrame.Offset = walkContext.Rbp;
        frame.AddrFrame.Mode   = AddrModeFlat;
        frame.AddrStack.Offset = walkContext.Rsp;
        frame.AddrStack.Mode   = AddrModeFlat;

        uint32_t     numFrames = 0;
        const HANDLE process   = GetCurrentProcess();
        const HANDLE thread    = GetCurrentThread();

        while (numFrames < 64)
        {
            const DWORD64 address = frame.AddrPC.Offset;
            if (!address)
                break;

            appendWindowsStackFrame(outMsg, ctx, numFrames, address);
            ++numFrames;

            const BOOL hasNext = StackWalk64(IMAGE_FILE_MACHINE_AMD64,
                                             process,
                                             thread,
                                             &frame,
                                             &walkContext,
                                             nullptr,
                                             SymFunctionTableAccess64,
                                             SymGetModuleBase64,
                                             nullptr);
            if (!hasNext)
                break;

            if (frame.AddrPC.Offset == address)
                break;
        }

        return numFrames != 0;
#else
        (void) outMsg;
        (void) platformExceptionPointers;
        (void) ctx;
        return false;
#endif
    }

    void appendWindowsStackFromHandler(Utf8& outMsg, const TaskContext* ctx)
    {
        void*        frames[64]{};
        const USHORT numFrames = ::CaptureStackBackTrace(0, std::size(frames), frames, nullptr);
        for (uint32_t i = 0; i < numFrames; ++i)
            appendWindowsStackFrame(outMsg, ctx, i, reinterpret_cast<uintptr_t>(frames[i]));
    }

    bool tryLoadExternalModulePath(void*& outModuleHandle, const fs::path& modulePath)
    {
        const Utf8    moduleFileName = modulePath.string();
        const HMODULE moduleHandle   = LoadLibraryA(moduleFileName.c_str());
        if (!moduleHandle)
            return false;

        outModuleHandle = moduleHandle;
        return true;
    }

    bool tryLoadExternalModuleAlias(void*& outModuleHandle, const fs::path& requestedPath, const char* aliasStem)
    {
        fs::path aliasPath = requestedPath.parent_path() / aliasStem;
        aliasPath.replace_extension(".dll");
        return tryLoadExternalModulePath(outModuleHandle, aliasPath);
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

    size_t peakProcessMemoryUsage()
    {
        PROCESS_MEMORY_COUNTERS memoryCounters = {};
        memoryCounters.cb                      = sizeof(memoryCounters);
        if (!GetProcessMemoryInfo(GetCurrentProcess(), &memoryCounters, sizeof(memoryCounters)))
            return 0;
        return memoryCounters.PeakWorkingSetSize;
    }

    void decodeHostException(uint32_t& outExceptionCode, const void*& outExceptionAddress, const void* platformExceptionPointers)
    {
        outExceptionCode    = 0;
        outExceptionAddress = nullptr;
        const auto* args    = static_cast<const EXCEPTION_POINTERS*>(platformExceptionPointers);
        const auto* record  = args ? args->ExceptionRecord : nullptr;
        if (!record)
            return;

        outExceptionCode    = record->ExceptionCode;
        outExceptionAddress = record->ExceptionAddress;
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

        if (!CompilerInstance::dbgDevMode)
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

    ProcessRunResult runProcess(uint32_t& outExitCode, const fs::path& exePath, const std::span<const Utf8> args, const fs::path& workingDirectory)
    {
        outExitCode = 0;

        std::wstring commandLine;
        appendQuotedCommandArg(commandLine, exePath.wstring());
        for (const Utf8& arg : args)
        {
            commandLine.push_back(L' ');
            appendQuotedCommandArg(commandLine, toWide(arg));
        }

        STARTUPINFOW        startupInfo{};
        PROCESS_INFORMATION processInfo{};
        startupInfo.cb = sizeof(startupInfo);

        std::wstring       mutableCommandLine = commandLine;
        const std::wstring workingDirW        = workingDirectory.empty() ? std::wstring() : workingDirectory.wstring();
        if (!CreateProcessW(exePath.wstring().c_str(),
                            mutableCommandLine.data(),
                            nullptr,
                            nullptr,
                            FALSE,
                            0,
                            nullptr,
                            workingDirW.empty() ? nullptr : workingDirW.c_str(),
                            &startupInfo,
                            &processInfo))
        {
            return ProcessRunResult::StartFailed;
        }

        const DWORD waitResult = WaitForSingleObject(processInfo.hProcess, INFINITE);
        if (waitResult != WAIT_OBJECT_0)
        {
            CloseHandle(processInfo.hThread);
            CloseHandle(processInfo.hProcess);
            return ProcessRunResult::WaitFailed;
        }

        DWORD exitCode = 0;
        if (!GetExitCodeProcess(processInfo.hProcess, &exitCode))
        {
            CloseHandle(processInfo.hThread);
            CloseHandle(processInfo.hProcess);
            return ProcessRunResult::ExitCodeFailed;
        }

        CloseHandle(processInfo.hThread);
        CloseHandle(processInfo.hProcess);
        outExitCode = exitCode;
        return ProcessRunResult::Ok;
    }

    WindowsToolchainDiscoveryResult discoverWindowsToolchainPaths(WindowsToolchainPaths& outToolchain)
    {
        outToolchain = {};

        std::vector<fs::path> candidates;
        if (const auto vctools = readEnvUtf8("VCToolsInstallDir"))
            candidates.emplace_back(std::string(*vctools));

        const auto appendRoots = [&](const fs::path& basePath) {
            std::error_code ec;
            if (!fs::exists(basePath, ec))
                return;

            std::vector<fs::path> versionRoots;
            for (fs::directory_iterator it(basePath, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
            {
                if (ec)
                {
                    ec.clear();
                    continue;
                }

                if (!it->is_directory(ec))
                {
                    ec.clear();
                    continue;
                }

                for (fs::directory_iterator skuIt(it->path(), fs::directory_options::skip_permission_denied, ec), skuEnd; skuIt != skuEnd; skuIt.increment(ec))
                {
                    if (ec)
                    {
                        ec.clear();
                        continue;
                    }

                    if (!skuIt->is_directory(ec))
                    {
                        ec.clear();
                        continue;
                    }

                    const fs::path toolsDir = skuIt->path() / "VC" / "Tools" / "MSVC";
                    if (!fs::exists(toolsDir, ec))
                        continue;

                    for (fs::directory_iterator toolIt(toolsDir, fs::directory_options::skip_permission_denied, ec), toolEnd; toolIt != toolEnd; toolIt.increment(ec))
                    {
                        if (ec)
                        {
                            ec.clear();
                            continue;
                        }

                        if (toolIt->is_directory(ec))
                            versionRoots.push_back(toolIt->path());
                    }
                }
            }

            std::ranges::sort(versionRoots, std::greater{}, [](const fs::path& path) {
                return path.filename().generic_string();
            });
            for (const auto& root : versionRoots)
                candidates.push_back(root);
        };

        appendRoots("C:\\Program Files\\Microsoft Visual Studio");
        appendRoots("C:\\Program Files (x86)\\Microsoft Visual Studio");

        for (const auto& root : candidates)
        {
            std::error_code ec;
            const fs::path  linkExe = root / "bin" / "Hostx64" / "x64" / "link.exe";
            const fs::path  libExe  = root / "bin" / "Hostx64" / "x64" / "lib.exe";
            const fs::path  vcLib   = root / "lib" / "x64";
            if (!fs::exists(linkExe, ec) || !fs::exists(libExe, ec))
                continue;

            outToolchain.linkExe   = linkExe;
            outToolchain.libExe    = libExe;
            outToolchain.vcLibPath = vcLib;
            break;
        }

        if (outToolchain.linkExe.empty() || outToolchain.libExe.empty())
            return WindowsToolchainDiscoveryResult::MissingMsvcToolchain;

        candidates.clear();
        if (const auto sdkDir = readEnvUtf8("WindowsSdkDir"))
        {
            const fs::path libRoot = fs::path(std::string(*sdkDir)) / "Lib";
            if (const auto sdkVersion = readEnvUtf8("WindowsSDKVersion"))
                candidates.emplace_back(libRoot / std::string(*sdkVersion));
        }

        std::error_code ec;
        const fs::path  sdkRoot = R"(C:\Program Files (x86)\Windows Kits\10\Lib)";
        if (fs::exists(sdkRoot, ec))
        {
            std::vector<fs::path> versions;
            for (fs::directory_iterator it(sdkRoot, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
            {
                if (ec)
                {
                    ec.clear();
                    continue;
                }

                if (it->is_directory(ec))
                    versions.push_back(it->path());
            }

            std::ranges::sort(versions, std::greater{}, [](const fs::path& path) {
                return path.filename().generic_string();
            });
            for (const auto& version : versions)
                candidates.push_back(version);
        }

        for (const auto& root : candidates)
        {
            const fs::path umLib   = root / "um" / "x64";
            const fs::path ucrtLib = root / "ucrt" / "x64";
            if (!fs::exists(umLib, ec) || !fs::exists(ucrtLib, ec))
                continue;

            outToolchain.sdkUmLibPath   = umLib;
            outToolchain.sdkUcrtLibPath = ucrtLib;
            return WindowsToolchainDiscoveryResult::Ok;
        }

        return WindowsToolchainDiscoveryResult::MissingWindowsSdk;
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

    bool addHostJitFunctionTable(JITMemory& executableMemory)
    {
        if (!executableMemory.ptr_ || !executableMemory.size_)
            return false;

        SWC_ASSERT(executableMemory.hostRuntimeFunction_ == nullptr);
        auto* const runtimeFunction = new RUNTIME_FUNCTION{};

        runtimeFunction->BeginAddress = 0;
        runtimeFunction->EndAddress   = executableMemory.size_;
        runtimeFunction->UnwindData   = executableMemory.unwindInfoOffset_;

        const DWORD64 baseAddress = reinterpret_cast<DWORD64>(executableMemory.ptr_);
        if (!RtlAddFunctionTable(runtimeFunction, 1, baseAddress))
        {
            delete runtimeFunction;
            return false;
        }

        executableMemory.hostRuntimeFunction_ = runtimeFunction;
        return true;
    }

    bool loadExternalModule(void*& outModuleHandle, std::string_view moduleName)
    {
        outModuleHandle = nullptr;
        if (moduleName.empty())
            return false;

        const Utf8     moduleNameUtf8{moduleName};
        const fs::path requestedPath{moduleNameUtf8.c_str()};
        if (requestedPath.has_extension())
            return tryLoadExternalModulePath(outModuleHandle, requestedPath);

        fs::path dllPath = requestedPath;
        dllPath.replace_extension(".dll");
        if (tryLoadExternalModulePath(outModuleHandle, dllPath))
            return true;

        // Some Windows import library names differ from the actual DLL name used by LoadLibrary.
        Utf8 requestedStem = requestedPath.filename().string();
        requestedStem.make_lower();
        if (requestedStem == "ucrt")
            return tryLoadExternalModuleAlias(outModuleHandle, requestedPath, "ucrtbase");
        if (requestedStem == "vcruntime")
            return tryLoadExternalModuleAlias(outModuleHandle, requestedPath, "vcruntime140") ||
                   tryLoadExternalModuleAlias(outModuleHandle, requestedPath, "vcruntime140_1");
        if (requestedStem == "xinput")
            return tryLoadExternalModuleAlias(outModuleHandle, requestedPath, "xinput1_4") ||
                   tryLoadExternalModuleAlias(outModuleHandle, requestedPath, "xinput9_1_0") ||
                   tryLoadExternalModuleAlias(outModuleHandle, requestedPath, "xinput1_3");

        return false;
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

    uint64_t tlsAlloc()
    {
        const DWORD tlsId = TlsAlloc();
        SWC_ASSERT(tlsId != TLS_OUT_OF_INDEXES);
        return tlsId;
    }

    void tlsSetValue(uint64_t id, void* value)
    {
        SWC_ASSERT(id <= std::numeric_limits<DWORD>::max());
        (void) TlsSetValue(static_cast<DWORD>(id), value);
    }

    void* tlsGetValue(uint64_t id)
    {
        SWC_ASSERT(id <= std::numeric_limits<DWORD>::max());
        return TlsGetValue(static_cast<DWORD>(id));
    }

    void appendHostExceptionSummary(const TaskContext* ctx, Utf8& outMsg, const void* platformExceptionPointers)
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
        appendWindowsAddress(addressMsg, ctx, reinterpret_cast<uintptr_t>(record->ExceptionAddress));
        while (!addressMsg.empty() && addressMsg.back() == '\n')
            addressMsg.pop_back();
        appendOsField(outMsg, "address", addressMsg);

        if (record->NumberParameters)
            appendOsField(outMsg, "parameters", std::format("{}", record->NumberParameters));

        if ((record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION || record->ExceptionCode == EXCEPTION_IN_PAGE_ERROR) && record->NumberParameters >= 2)
        {
            Utf8 accessMsg;
            accessMsg += std::format("{} at ", windowsAccessViolationOpName(record->ExceptionInformation[0]));
            appendWindowsAddress(accessMsg, ctx, record->ExceptionInformation[1]);
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

    void appendHostHandlerStack(Utf8& outMsg, const void* platformExceptionPointers, const TaskContext* ctx)
    {
        if (appendWindowsStackFromException(outMsg, platformExceptionPointers, ctx))
            return;

        appendWindowsStackFromHandler(outMsg, ctx);
    }

    void exit(ExitCode code)
    {
        ExitProcess(static_cast<int>(code));
    }

    void terminate()
    {
        TerminateProcess(GetCurrentProcess(), 0);
        SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();

#endif // _WIN32
