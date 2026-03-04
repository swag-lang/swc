#include "pch.h"
#ifdef _WIN32
#include "Main/CommandLine.h"
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

#ifdef _M_X64
    constexpr uint8_t K_UWOP_PUSH_NONVOL = 0;
    constexpr uint8_t K_UWOP_ALLOC_LARGE = 1;
    constexpr uint8_t K_UWOP_ALLOC_SMALL = 2;
    constexpr uint8_t K_UWOP_SET_FPREG   = 3;

    enum class JitUnwindOpKind : uint8_t
    {
        PushNonVol,
        SetFramePointer,
        AllocateStack,
    };

    struct JitUnwindOp
    {
        JitUnwindOpKind kind       = JitUnwindOpKind::PushNonVol;
        uint8_t         codeOffset = 0;
        uint8_t         reg        = 0;
        uint32_t        stackSize  = 0;
    };

    struct JitFunctionTableEntry
    {
        RUNTIME_FUNCTION runtimeFunction{};
    };

    struct JitFunctionTableState
    {
        std::mutex                                                              mutex;
        std::unordered_map<const void*, std::unique_ptr<JitFunctionTableEntry>> entries;
    };

    JitFunctionTableState& jitFunctionTableState()
    {
        static JitFunctionTableState state;
        return state;
    }

    bool isWindowsX64NonVolatileReg(const uint8_t reg)
    {
        switch (reg)
        {
            case 3:
            case 5:
            case 6:
            case 7:
            case 12:
            case 13:
            case 14:
            case 15:
                return true;
            default:
                return false;
        }
    }

    bool parsePushNonVol(const ByteSpan functionCode, const size_t codeOffset, uint8_t& outReg, uint8_t& outLength)
    {
        outReg    = 0;
        outLength = 0;
        if (codeOffset >= functionCode.size())
            return false;

        const auto* bytes  = reinterpret_cast<const uint8_t*>(functionCode.data());
        size_t      cursor = codeOffset;
        uint8_t     rex    = 0;
        if (bytes[cursor] >= 0x40 && bytes[cursor] <= 0x4F)
        {
            rex = bytes[cursor];
            ++cursor;
            if (cursor >= functionCode.size())
                return false;
        }

        const uint8_t op = bytes[cursor];
        if (op < 0x50 || op > 0x57)
            return false;

        const uint8_t lowReg = static_cast<uint8_t>(op - 0x50);
        const uint8_t extReg = static_cast<uint8_t>((rex & 0x01) ? 8 : 0);
        outReg               = static_cast<uint8_t>(lowReg + extReg);
        outLength            = static_cast<uint8_t>(cursor - codeOffset + 1);
        return true;
    }

    bool parseSetFramePointer(const ByteSpan functionCode, const size_t codeOffset, uint8_t& outLength)
    {
        outLength = 0;
        if (codeOffset + 2 >= functionCode.size())
            return false;

        const auto* bytes = reinterpret_cast<const uint8_t*>(functionCode.data());
        if (bytes[codeOffset] == 0x48 && bytes[codeOffset + 1] == 0x89 && bytes[codeOffset + 2] == 0xE5)
        {
            outLength = 3;
            return true;
        }

        if (bytes[codeOffset] == 0x48 && bytes[codeOffset + 1] == 0x8B && bytes[codeOffset + 2] == 0xEC)
        {
            outLength = 3;
            return true;
        }

        return false;
    }

    bool parseSubRsp(const ByteSpan functionCode, const size_t codeOffset, uint32_t& outStackSize, uint8_t& outLength)
    {
        outStackSize = 0;
        outLength    = 0;
        if (codeOffset >= functionCode.size())
            return false;

        const auto* bytes = reinterpret_cast<const uint8_t*>(functionCode.data());
        if (codeOffset + 3 < functionCode.size() && bytes[codeOffset] == 0x48 && bytes[codeOffset + 1] == 0x83 && bytes[codeOffset + 2] == 0xEC)
        {
            outStackSize = bytes[codeOffset + 3];
            outLength    = 4;
            return true;
        }

        if (codeOffset + 6 < functionCode.size() && bytes[codeOffset] == 0x48 && bytes[codeOffset + 1] == 0x81 && bytes[codeOffset + 2] == 0xEC)
        {
            const uint32_t imm0 = bytes[codeOffset + 3];
            const uint32_t imm1 = bytes[codeOffset + 4];
            const uint32_t imm2 = bytes[codeOffset + 5];
            const uint32_t imm3 = bytes[codeOffset + 6];
            outStackSize        = imm0 | (imm1 << 8) | (imm2 << 16) | (imm3 << 24);
            outLength           = 7;
            return true;
        }

        return false;
    }

    uint16_t packUnwindCodeSlot(const uint8_t codeOffset, const uint8_t unwindOp, const uint8_t opInfo)
    {
        const uint8_t  opByte = static_cast<uint8_t>(((opInfo & 0x0F) << 4) | (unwindOp & 0x0F));
        const uint16_t value  = static_cast<uint16_t>(codeOffset) | (static_cast<uint16_t>(opByte) << 8);
        return value;
    }

    bool buildWindowsX64JitUnwindInfo(std::vector<std::byte>& outUnwindInfo, const ByteSpan functionCode)
    {
        outUnwindInfo.clear();
        if (functionCode.empty())
            return false;

        constexpr uint8_t REG_RBP = 5;

        std::vector<JitUnwindOp> unwindOps;
        unwindOps.reserve(8);

        uint8_t frameReg    = 0;
        uint8_t frameOffset = 0;
        size_t  cursor      = 0;

        uint8_t pushReg = 0;
        uint8_t pushLen = 0;
        if (parsePushNonVol(functionCode, cursor, pushReg, pushLen) && pushReg == REG_RBP)
        {
            uint8_t movLen = 0;
            if (parseSetFramePointer(functionCode, cursor + pushLen, movLen))
            {
                unwindOps.push_back({
                    .kind       = JitUnwindOpKind::PushNonVol,
                    .codeOffset = static_cast<uint8_t>(cursor + pushLen),
                    .reg        = pushReg,
                });
                unwindOps.push_back({
                    .kind       = JitUnwindOpKind::SetFramePointer,
                    .codeOffset = static_cast<uint8_t>(cursor + pushLen + movLen),
                });
                frameReg    = REG_RBP;
                frameOffset = 0;
                cursor += pushLen + movLen;
            }
        }

        while (true)
        {
            uint8_t parsedReg    = 0;
            uint8_t parsedLength = 0;
            if (!parsePushNonVol(functionCode, cursor, parsedReg, parsedLength))
                break;
            if (!isWindowsX64NonVolatileReg(parsedReg))
                break;

            const size_t nextCursor = cursor + parsedLength;
            if (nextCursor > std::numeric_limits<uint8_t>::max())
                return false;

            unwindOps.push_back({
                .kind       = JitUnwindOpKind::PushNonVol,
                .codeOffset = static_cast<uint8_t>(nextCursor),
                .reg        = parsedReg,
            });
            cursor = nextCursor;
        }

        {
            uint32_t stackSize  = 0;
            uint8_t  stackInstr = 0;
            if (parseSubRsp(functionCode, cursor, stackSize, stackInstr) && stackSize)
            {
                const size_t nextCursor = cursor + stackInstr;
                if (nextCursor > std::numeric_limits<uint8_t>::max())
                    return false;

                unwindOps.push_back({
                    .kind       = JitUnwindOpKind::AllocateStack,
                    .codeOffset = static_cast<uint8_t>(nextCursor),
                    .stackSize  = stackSize,
                });
                cursor = nextCursor;
            }
        }

        if (cursor > std::numeric_limits<uint8_t>::max())
            return false;

        std::ranges::sort(unwindOps, [](const JitUnwindOp& left, const JitUnwindOp& right) {
            return left.codeOffset > right.codeOffset;
        });

        std::vector<uint16_t> unwindSlots;
        unwindSlots.reserve(unwindOps.size() + 4);
        for (const JitUnwindOp& op : unwindOps)
        {
            switch (op.kind)
            {
                case JitUnwindOpKind::PushNonVol:
                    unwindSlots.push_back(packUnwindCodeSlot(op.codeOffset, K_UWOP_PUSH_NONVOL, op.reg));
                    break;

                case JitUnwindOpKind::SetFramePointer:
                    unwindSlots.push_back(packUnwindCodeSlot(op.codeOffset, K_UWOP_SET_FPREG, 0));
                    break;

                case JitUnwindOpKind::AllocateStack:
                {
                    if (op.stackSize >= 8 && op.stackSize <= 128 && (op.stackSize % 8) == 0)
                    {
                        const uint8_t opInfo = static_cast<uint8_t>(op.stackSize / 8 - 1);
                        unwindSlots.push_back(packUnwindCodeSlot(op.codeOffset, K_UWOP_ALLOC_SMALL, opInfo));
                        break;
                    }

                    if ((op.stackSize % 8) == 0 && op.stackSize / 8 <= std::numeric_limits<uint16_t>::max())
                    {
                        unwindSlots.push_back(packUnwindCodeSlot(op.codeOffset, K_UWOP_ALLOC_LARGE, 0));
                        unwindSlots.push_back(static_cast<uint16_t>(op.stackSize / 8));
                        break;
                    }

                    unwindSlots.push_back(packUnwindCodeSlot(op.codeOffset, K_UWOP_ALLOC_LARGE, 1));
                    unwindSlots.push_back(static_cast<uint16_t>(op.stackSize & 0xFFFF));
                    unwindSlots.push_back(static_cast<uint16_t>((op.stackSize >> 16) & 0xFFFF));
                    break;
                }

                default:
                    SWC_FORCE_ASSERT(false);
                    return false;
            }
        }

        if (unwindSlots.size() > std::numeric_limits<uint8_t>::max())
            return false;

        const uint32_t unwindSlotCount        = static_cast<uint32_t>(unwindSlots.size());
        const uint32_t unwindSlotCountAligned = (unwindSlotCount + 1u) & ~1u;

        outUnwindInfo.resize(4 + unwindSlotCountAligned * sizeof(uint16_t));
        auto* const outBytes = reinterpret_cast<uint8_t*>(outUnwindInfo.data());
        outBytes[0]          = 1;
        outBytes[1]          = static_cast<uint8_t>(cursor);
        outBytes[2]          = static_cast<uint8_t>(unwindSlotCount);
        outBytes[3]          = static_cast<uint8_t>(((frameOffset & 0x0F) << 4) | (frameReg & 0x0F));

        for (uint32_t i = 0; i < unwindSlotCountAligned; ++i)
        {
            const uint16_t value    = i < unwindSlotCount ? unwindSlots[i] : 0;
            outBytes[4 + i * 2 + 0] = static_cast<uint8_t>(value & 0xFF);
            outBytes[4 + i * 2 + 1] = static_cast<uint8_t>((value >> 8) & 0xFF);
        }

        return true;
    }
#endif

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

    Os::HostExceptionHandlerFn& hostExceptionHandler()
    {
        static Os::HostExceptionHandlerFn handler = nullptr;
        return handler;
    }

    PVOID& vectoredExceptionHandle()
    {
        static PVOID handle = nullptr;
        return handle;
    }

    int dispatchHostException(const void* platformExceptionPointers)
    {
        const Os::HostExceptionHandlerFn handler = hostExceptionHandler();
        if (!handler)
            return SWC_EXCEPTION_EXECUTE_HANDLER;
        return handler(platformExceptionPointers);
    }

    // ReSharper disable once CppParameterMayBeConstPtrOrRef
    LONG WINAPI onUnhandledExceptionFilter(_EXCEPTION_POINTERS* exceptionPointers)
    {
        (void) dispatchHostException(exceptionPointers);
        return SWC_EXCEPTION_EXECUTE_HANDLER;
    }

    // ReSharper disable once CppParameterMayBeConstPtrOrRef
    LONG CALLBACK onVectoredExceptionHandler(_EXCEPTION_POINTERS* exceptionPointers)
    {
        (void) exceptionPointers;
        return EXCEPTION_CONTINUE_SEARCH;
    }

    void installHostExceptionHandlers(Os::HostExceptionHandlerFn exceptionHandler)
    {
        hostExceptionHandler() = exceptionHandler;

        PVOID& handle = vectoredExceptionHandle();
        if (!handle)
            handle = AddVectoredExceptionHandler(1, onVectoredExceptionHandler);

        SetUnhandledExceptionFilter(onUnhandledExceptionFilter);
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

    int runMainWithHostExceptionBarrier(const MainEntryPoint mainEntryPoint, const HostExceptionHandlerFn exceptionHandler, const int argc, char* argv[])
    {
        SWC_ASSERT(mainEntryPoint);
        SWC_ASSERT(exceptionHandler);

        installHostExceptionHandlers(exceptionHandler);

        SWC_TRY
        {
            return mainEntryPoint(argc, argv);
        }
        SWC_EXCEPT(dispatchHostException(SWC_GET_EXCEPTION_INFOS()))
        {
            return static_cast<int>(ExitCode::HardwareException);
        }
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
        return static_cast<size_t>(memoryCounters.PeakWorkingSetSize);
    }

    bool isHostIllegalInstructionException(const uint32_t exceptionCode)
    {
        return exceptionCode == EXCEPTION_ILLEGAL_INSTRUCTION;
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

    bool buildHostJitUnwindInfo(std::vector<std::byte>& outUnwindInfo, const ByteSpan functionCode)
    {
#ifdef _M_X64
        return buildWindowsX64JitUnwindInfo(outUnwindInfo, functionCode);
#else
        SWC_UNUSED(outUnwindInfo);
        SWC_UNUSED(functionCode);
        return false;
#endif
    }

    bool addHostJitFunctionTable(const void* functionAddress, const uint32_t codeSize, const uint32_t unwindInfoOffset)
    {
#ifdef _M_X64
        if (!functionAddress || !codeSize)
            return false;

        JitFunctionTableState& state = jitFunctionTableState();
        const std::scoped_lock lock(state.mutex);
        auto                   it = state.entries.find(functionAddress);
        if (it != state.entries.end())
        {
            (void) RtlDeleteFunctionTable(&it->second->runtimeFunction);
            state.entries.erase(it);
        }

        auto newEntry                          = std::make_unique<JitFunctionTableEntry>();
        newEntry->runtimeFunction.BeginAddress = 0;
        newEntry->runtimeFunction.EndAddress   = codeSize;
        newEntry->runtimeFunction.UnwindData   = unwindInfoOffset;

        const DWORD64 baseAddress = reinterpret_cast<DWORD64>(functionAddress);
        if (!RtlAddFunctionTable(&newEntry->runtimeFunction, 1, baseAddress))
            return false;

        state.entries[functionAddress] = std::move(newEntry);
        return true;
#else
        SWC_UNUSED(functionAddress);
        SWC_UNUSED(codeSize);
        SWC_UNUSED(unwindInfoOffset);
        return false;
#endif
    }

    void removeHostJitFunctionTable(const void* functionAddress)
    {
#ifdef _M_X64
        if (!functionAddress)
            return;

        JitFunctionTableState& state = jitFunctionTableState();
        const std::scoped_lock lock(state.mutex);
        const auto             it = state.entries.find(functionAddress);
        if (it == state.entries.end())
            return;

        (void) RtlDeleteFunctionTable(&it->second->runtimeFunction);
        state.entries.erase(it);
#else
        SWC_UNUSED(functionAddress);
#endif
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
}

SWC_END_NAMESPACE();

#endif // _WIN32
