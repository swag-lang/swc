#include "pch.h"
#include "Support/Report/HardwareException.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

#ifdef _WIN32
#include <dbghelp.h>
#pragma comment(lib, "Dbghelp.lib")
#endif

SWC_BEGIN_NAMESPACE();

namespace
{
    // ============================================================================
    // Host Identity
    // ============================================================================

    const char* hostOsName()
    {
#ifdef _WIN32
        return "windows";
#else
        return "unknown-os";
#endif
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
#ifdef _WIN32
        return "windows seh";
#else
        return "unknown-backend";
#endif
    }

    // ============================================================================
    // Windows Symbol Engine
    // ============================================================================

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
        auto&            state = symbolEngineState();
        std::scoped_lock lock(state.mutex);

        if (!state.attempted)
        {
            state.attempted      = true;
            const HANDLE process = GetCurrentProcess();
            SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES);
            state.initialized = SymInitialize(process, nullptr, TRUE) == TRUE;
        }

        return state.initialized;
    }

    bool useRichFormatting(const TaskContext& ctx)
    {
        return ctx.cmdLine().verboseHardwareException;
    }

    void appendSectionHeader(Utf8& outMsg, const std::string_view title)
    {
        outMsg += "\n";
        outMsg += title;
        outMsg += "\n";
        outMsg += "----------------------------------------\n";
    }

    const char* symbolKindName(const SymbolKind kind)
    {
        switch (kind)
        {
            case SymbolKind::Invalid:
                return "Invalid";
            case SymbolKind::Module:
                return "Module";
            case SymbolKind::Namespace:
                return "Namespace";
            case SymbolKind::Constant:
                return "Constant";
            case SymbolKind::Variable:
                return "Variable";
            case SymbolKind::Enum:
                return "Enum";
            case SymbolKind::EnumValue:
                return "EnumValue";
            case SymbolKind::Attribute:
                return "Attribute";
            case SymbolKind::Struct:
                return "Struct";
            case SymbolKind::Interface:
                return "Interface";
            case SymbolKind::Alias:
                return "Alias";
            case SymbolKind::Function:
                return "Function";
            case SymbolKind::Impl:
                return "Impl";
            default:
                return "Unknown";
        }
    }

    const char* taskStateKindName(const TaskStateKind kind)
    {
        switch (kind)
        {
            case TaskStateKind::None:
                return "None";
            case TaskStateKind::SemaWaitIdentifier:
                return "SemaWaitIdentifier";
            case TaskStateKind::SemaWaitCompilerDefined:
                return "SemaWaitCompilerDefined";
            case TaskStateKind::SemaWaitImplRegistrations:
                return "SemaWaitImplRegistrations";
            case TaskStateKind::SemaWaitSymDeclared:
                return "SemaWaitSymDeclared";
            case TaskStateKind::SemaWaitSymTyped:
                return "SemaWaitSymTyped";
            case TaskStateKind::SemaWaitSymSemaCompleted:
                return "SemaWaitSymSemaCompleted";
            case TaskStateKind::SemaWaitSymCodeGenCompleted:
                return "SemaWaitSymCodeGenCompleted";
            case TaskStateKind::SemaWaitTypeCompleted:
                return "SemaWaitTypeCompleted";
            default:
                return "Unknown";
        }
    }

    // ============================================================================
    // Windows Exception Decoding
    // ============================================================================

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

    void appendWindowsAddressSymbol(Utf8& outMsg, const uint64_t address)
    {
        if (!address)
            return;
        if (!ensureSymbolEngineInitialized())
            return;

        auto&            state = symbolEngineState();
        std::scoped_lock lock(state.mutex);

        const HANDLE process = GetCurrentProcess();

        std::array<uint8_t, sizeof(SYMBOL_INFO) + MAX_SYM_NAME> symbolBuffer{};
        auto*                                                   symbol = reinterpret_cast<SYMBOL_INFO*>(symbolBuffer.data());
        symbol->SizeOfStruct                                           = sizeof(SYMBOL_INFO);
        symbol->MaxNameLen                                             = MAX_SYM_NAME;

        DWORD64 displacement = 0;
        if (SymFromAddr(process, address, &displacement, symbol))
            outMsg += std::format("    symbol: {} + 0x{:X}\n", symbol->Name, static_cast<uint64_t>(displacement));

        IMAGEHLP_LINE64 lineInfo{};
        lineInfo.SizeOfStruct = sizeof(lineInfo);
        DWORD lineDisp        = 0;
        if (SymGetLineFromAddr64(process, address, &lineDisp, &lineInfo))
            outMsg += std::format("    source: {}:{} (+{})\n", lineInfo.FileName, lineInfo.LineNumber, lineDisp);
    }

    void appendCodeLocation(Utf8& outMsg, const TaskContext& ctx, const std::string_view label, const SourceCodeRef& codeRef)
    {
        if (!codeRef.srcViewRef.isValid() || !codeRef.tokRef.isValid())
            return;

        const auto& srcView = ctx.compiler().srcView(codeRef.srcViewRef);
        if (codeRef.tokRef.get() >= srcView.numTokens())
            return;

        const auto   codeRange = srcView.tokenCodeRange(ctx, codeRef.tokRef);
        const auto*  file      = srcView.file();
        const auto   path      = file ? file->path().string() : "<no-file>";
        const Token& token     = srcView.token(codeRef.tokRef);
        Utf8         line      = srcView.codeLine(ctx, codeRange.line);
        line.trim_end();
        if (line.length() > 220)
            line = line.substr(0, 220) + " ...";

        outMsg += std::format("  {}: {}:{}:{}\n", label, path, codeRange.line, codeRange.column);
        outMsg += std::format("    token: `{}` ({})\n", token.string(srcView), Token::toName(token.id));
        if (!line.empty())
            outMsg += std::format("    code: {}\n", line);
    }

    void appendTaskReadableContext(Utf8& outMsg, const TaskContext& ctx)
    {
        appendSectionHeader(outMsg, "Relevant Context");
        const auto& state = ctx.state();

        outMsg += std::format("  task state: {}\n", taskStateKindName(state.kind));

        if (state.idRef.isValid())
            outMsg += std::format("  identifier: {}\n", ctx.idMgr().get(state.idRef).name);

        if (state.symbol)
        {
            outMsg += std::format("  symbol: {} `{}`\n", symbolKindName(state.symbol->kind()), state.symbol->getFullScopedName(ctx));
            if (state.symbol->decl())
                outMsg += std::format("  symbol node kind: {}\n", Ast::nodeIdName(state.symbol->decl()->id()));
            if (state.symbol->decl())
                appendCodeLocation(outMsg, ctx, "symbol location", state.symbol->codeRef());
        }

        if (state.waiterSymbol)
        {
            outMsg += std::format("  waiter symbol: {} `{}`\n", symbolKindName(state.waiterSymbol->kind()), state.waiterSymbol->getFullScopedName(ctx));
            if (state.waiterSymbol->decl())
                appendCodeLocation(outMsg, ctx, "waiter symbol location", state.waiterSymbol->codeRef());
        }

        appendCodeLocation(outMsg, ctx, "task code location", state.codeRef);
    }

    void appendWindowsAddress(Utf8& outMsg, const uint64_t address, const bool rich)
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
            char       modulePath[MAX_PATH + 1]{};
            const auto len = GetModuleFileNameA(reinterpret_cast<HMODULE>(modBase), modulePath, MAX_PATH);
            if (len)
            {
                modulePath[len]       = 0;
                const auto moduleName = fs::path(modulePath).filename().string();
                outMsg += std::format(" ({} + 0x{:X})", moduleName, address - modBase);
            }
        }

        if (!rich)
            return;

        outMsg += "\n";
        if (modBase)
        {
            char       modulePath[MAX_PATH + 1]{};
            const auto len = GetModuleFileNameA(reinterpret_cast<HMODULE>(modBase), modulePath, MAX_PATH);
            if (len)
            {
                modulePath[len] = 0;
                outMsg += std::format("    module path: {}\n", modulePath);
            }
        }

        appendWindowsAddressSymbol(outMsg, address);
        outMsg += std::format("    memory: state={}, type={}, protect={}\n", windowsStateToString(mbi.State), windowsTypeToString(mbi.Type), windowsProtectToString(mbi.Protect));
    }

    void appendWindowsAnalysis(Utf8& outMsg, const EXCEPTION_RECORD* record, const CONTEXT* context)
    {
        if (!record)
            return;

        appendSectionHeader(outMsg, "Analysis");
        outMsg += std::format("  exception: 0x{:08X} ({})\n", record->ExceptionCode, windowsExceptionCodeName(record->ExceptionCode));

        if (record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION || record->ExceptionCode == EXCEPTION_IN_PAGE_ERROR)
        {
            if (record->NumberParameters < 2)
            {
                outMsg += "  cannot analyze access violation (missing parameters)\n";
                return;
            }

            const auto op         = record->ExceptionInformation[0];
            const auto accessAddr = static_cast<uint64_t>(record->ExceptionInformation[1]);
            outMsg += std::format("  fault: {} at 0x{:016X}\n", windowsAccessViolationOpName(op), accessAddr);

            if (accessAddr < 0x10000)
                outMsg += "  likely cause: null pointer dereference or null+offset access\n";

            MEMORY_BASIC_INFORMATION mbi{};
            if (VirtualQuery(reinterpret_cast<LPCVOID>(static_cast<uintptr_t>(accessAddr)), &mbi, sizeof(mbi)) && mbi.State == MEM_FREE)
                outMsg += "  likely cause: use-after-free or wild pointer (target page is FREE)\n";

#ifdef _M_X64
            if (context)
            {
                struct RegEntry
                {
                    const char* name;
                    uint64_t    value;
                };

                const RegEntry regs[] = {
                    {"rax", context->Rax},
                    {"rbx", context->Rbx},
                    {"rcx", context->Rcx},
                    {"rdx", context->Rdx},
                    {"rsi", context->Rsi},
                    {"rdi", context->Rdi},
                    {"r8", context->R8},
                    {"r9", context->R9},
                    {"r10", context->R10},
                    {"r11", context->R11},
                    {"r12", context->R12},
                    {"r13", context->R13},
                    {"r14", context->R14},
                    {"r15", context->R15},
                    {"rbp", context->Rbp},
                    {"rsp", context->Rsp},
                };

                bool found = false;
                outMsg += "  registers matching fault address:";
                for (const auto& reg : regs)
                {
                    if (reg.value != accessAddr)
                        continue;
                    found = true;
                    outMsg += std::format(" {}", reg.name);
                }
                if (!found)
                    outMsg += " none";
                outMsg += "\n";
            }
#endif
        }
    }

    void appendWindowsExceptionSummary(Utf8& outMsg, const EXCEPTION_RECORD* record, const bool rich)
    {
        appendSectionHeader(outMsg, "Exception");
        if (!record)
        {
            outMsg += "  no exception record\n";
            return;
        }

        outMsg += std::format("  code: 0x{:08X} ({})\n", record->ExceptionCode, windowsExceptionCodeName(record->ExceptionCode));
        outMsg += "  address: ";
        appendWindowsAddress(outMsg, reinterpret_cast<uintptr_t>(record->ExceptionAddress), rich);
        outMsg += "\n";

        if (record->NumberParameters && rich)
            outMsg += std::format("  parameters: {}\n", record->NumberParameters);

        if ((record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION || record->ExceptionCode == EXCEPTION_IN_PAGE_ERROR) && record->NumberParameters >= 2)
        {
            outMsg += std::format("  access: {} at ", windowsAccessViolationOpName(record->ExceptionInformation[0]));
            appendWindowsAddress(outMsg, record->ExceptionInformation[1], rich);
            outMsg += "\n";
        }
    }

    // ============================================================================
    // CPU Context Decoding
    // ============================================================================

    void appendCpuContextForHost(Utf8& outMsg, const CONTEXT* context)
    {
        appendSectionHeader(outMsg, "CPU Context");
        if (!context)
        {
            outMsg += "  <null>\n";
            return;
        }

#ifdef _M_X64
        outMsg += std::format("  rip=0x{:016X} rsp=0x{:016X} rbp=0x{:016X}\n", context->Rip, context->Rsp, context->Rbp);
        outMsg += std::format("  rax=0x{:016X} rbx=0x{:016X} rcx=0x{:016X} rdx=0x{:016X}\n", context->Rax, context->Rbx, context->Rcx, context->Rdx);
        outMsg += std::format("  rsi=0x{:016X} rdi=0x{:016X} r8=0x{:016X} r9=0x{:016X}\n", context->Rsi, context->Rdi, context->R8, context->R9);
        outMsg += std::format("  r10=0x{:016X} r11=0x{:016X} r12=0x{:016X} r13=0x{:016X}\n", context->R10, context->R11, context->R12, context->R13);
        outMsg += std::format("  r14=0x{:016X} r15=0x{:016X} eflags=0x{:08X}\n", context->R14, context->R15, context->EFlags);
#elifdef _M_IX86
        outMsg += std::format("  eip=0x{:08X} esp=0x{:08X} ebp=0x{:08X}\n", context->Eip, context->Esp, context->Ebp);
        outMsg += std::format("  eax=0x{:08X} ebx=0x{:08X} ecx=0x{:08X} edx=0x{:08X}\n", context->Eax, context->Ebx, context->Ecx, context->Edx);
        outMsg += std::format("  esi=0x{:08X} edi=0x{:08X} eflags=0x{:08X}\n", context->Esi, context->Edi, context->EFlags);
#else
        outMsg += "  unsupported architecture\n";
#endif
    }

    // ============================================================================
    // Windows Stack Trace
    // ============================================================================

    void appendWindowsHandlerStack(Utf8& outMsg)
    {
        appendSectionHeader(outMsg, "Handler Stack Trace");
        void*      frames[64]{};
        const auto numFrames = ::CaptureStackBackTrace(0, std::size(frames), frames, nullptr);
        outMsg += std::format("  frames: {}\n", numFrames);

        for (uint32_t i = 0; i < numFrames; ++i)
        {
            const auto address = reinterpret_cast<uintptr_t>(frames[i]);
            outMsg += std::format("  [{}] 0x{:016X}", i, address);

            MEMORY_BASIC_INFORMATION mbi{};
            if (VirtualQuery(reinterpret_cast<LPCVOID>(address), &mbi, sizeof(mbi)))
            {
                const uintptr_t modBase = reinterpret_cast<uintptr_t>(mbi.AllocationBase);
                if (modBase)
                {
                    char       modulePath[MAX_PATH + 1]{};
                    const auto len = GetModuleFileNameA(reinterpret_cast<HMODULE>(modBase), modulePath, MAX_PATH);
                    if (len)
                    {
                        modulePath[len]       = 0;
                        const auto moduleName = fs::path(modulePath).filename().string();
                        outMsg += std::format("  {} + 0x{:X}", moduleName, address - modBase);
                    }
                }
            }

            outMsg += "\n";
            appendWindowsAddressSymbol(outMsg, address);
        }
    }
}

void HardwareException::log(const TaskContext& ctx, const std::string_view title, SWC_LP_EXCEPTION_POINTERS args, HardwareExceptionExtraInfoFn extraInfoFn, const void* userData)
{
    auto& logger = ctx.global().logger();
    logger.lock();

    const bool rich = useRichFormatting(ctx);
    Utf8       msg;
    msg += LogColorHelper::toAnsi(ctx, LogColor::BrightRed);
    msg += title;
    if (title.empty() || title.back() != '\n')
        msg += "\n";
    msg += LogColorHelper::toAnsi(ctx, LogColor::Reset);

    appendSectionHeader(msg, "Environment");
    msg += std::format("  host os: {}\n", hostOsName());
    msg += std::format("  host cpu: {}\n", hostCpuName());
    msg += std::format("  host exception backend: {}\n", hostExceptionBackendName());
    msg += std::format("  process id: {}\n", static_cast<uint32_t>(GetCurrentProcessId()));
    msg += std::format("  thread id: {}\n", static_cast<uint32_t>(GetCurrentThreadId()));

#if SWC_DEV_MODE
    msg += std::format("  cmd randomize: {}, seed: {}\n", ctx.cmdLine().randomize, ctx.cmdLine().randSeed);
#endif
    msg += std::format("  rich diagnostics: {}\n", rich);

    const EXCEPTION_RECORD* record  = args ? args->ExceptionRecord : nullptr;
    const CONTEXT*          context = args ? args->ContextRecord : nullptr;

    appendTaskReadableContext(msg, ctx);
    appendWindowsExceptionSummary(msg, record, rich);
    appendWindowsAnalysis(msg, record, context);

    appendSectionHeader(msg, "Path Context");
    if (extraInfoFn)
        extraInfoFn(msg, ctx, userData);
    else
        msg += "  <none>\n";

    if (rich)
    {
        appendCpuContextForHost(msg, context);
        appendWindowsHandlerStack(msg);
    }

    Logger::print(ctx, msg);
    logger.unlock();
}

SWC_END_NAMESPACE();
