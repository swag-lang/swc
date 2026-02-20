#include "pch.h"
#include "Support/Report/HardwareException.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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
            case TaskStateKind::SemaWaitSymCodeGenPreSolved:
                return "SemaWaitSymCodeGenPreSolved";
            case TaskStateKind::SemaWaitSymCodeGenCompleted:
                return "SemaWaitSymCodeGenCompleted";
            case TaskStateKind::SemaWaitTypeCompleted:
                return "SemaWaitTypeCompleted";
            default:
                return "Unknown";
        }
    }

    void appendCodeLocation(Utf8& outMsg, const TaskContext& ctx, const std::string_view label, const SourceCodeRef& codeRef)
    {
        if (!codeRef.srcViewRef.isValid() || !codeRef.tokRef.isValid())
            return;

        const SourceView& srcView = ctx.compiler().srcView(codeRef.srcViewRef);
        if (codeRef.tokRef.get() >= srcView.numTokens())
            return;

        const SourceCodeRange codeRange = srcView.tokenCodeRange(ctx, codeRef.tokRef);
        const SourceFile*     file      = srcView.file();
        const std::string     path      = file ? file->path().string() : "<no-file>";
        const Token&          token     = srcView.token(codeRef.tokRef);
        Utf8                  line      = srcView.codeLine(ctx, codeRange.line);
        line.trim_end();
        if (line.length() > 220)
            line = line.substr(0, 220) + " ...";

        outMsg += std::format("{}: {}:{}:{}\n", label, path, codeRange.line, codeRange.column);
        outMsg += std::format("token: `{}` ({})\n", token.string(srcView), Token::toName(token.id));
        outMsg += std::format("code: {}\n", line);
    }

    void appendCrashGroup(Utf8& outMsg, const TaskContext& ctx, SWC_LP_EXCEPTION_POINTERS args)
    {
        HardwareException::appendSectionHeader(outMsg, "Crash");
        HardwareException::appendField(outMsg, "host os:", Os::hostOsName());
        HardwareException::appendField(outMsg, "host cpu:", Os::hostCpuName());
        HardwareException::appendField(outMsg, "host exception backend:", Os::hostExceptionBackendName());
        HardwareException::appendField(outMsg, "process id:", std::format("{}", Os::currentProcessId()));
        HardwareException::appendField(outMsg, "thread id:", std::format("{}", Os::currentThreadId()));
#if SWC_DEV_MODE
        HardwareException::appendField(outMsg, "cmd randomize:", std::format("{}, seed: {}", ctx.cmdLine().randomize, ctx.cmdLine().randSeed));
#endif
        HardwareException::appendField(outMsg, "mode:", "full diagnostics");
        Os::appendHostExceptionSummary(outMsg, args);
    }

    void appendContextGroup(Utf8& outMsg, const TaskContext& ctx, HardwareExceptionExtraInfoFn extraInfoFn, const void* userData)
    {
        HardwareException::appendSectionHeader(outMsg, "Context");
        if (extraInfoFn)
            extraInfoFn(outMsg, ctx, userData);
        else
            HardwareException::appendField(outMsg, "info:", "<none>");
    }

    void appendHostTraceGroup(Utf8& outMsg, SWC_LP_EXCEPTION_POINTERS args)
    {
        HardwareException::appendSectionHeader(outMsg, "Host Trace");
        HardwareException::appendField(outMsg, "cpu context:", "");
        Os::appendHostCpuContext(outMsg, args);
        HardwareException::appendField(outMsg, "handler stack:", "");
        Os::appendHostHandlerStack(outMsg);
    }
}

void HardwareException::appendSectionHeader(Utf8& outMsg, const std::string_view title)
{
    outMsg += "\n";
    outMsg += title;
    outMsg += "\n\n";
}

void HardwareException::appendField(Utf8& outMsg, const std::string_view label, const std::string_view value)
{
    constexpr uint32_t kFieldWidth = 24;
    outMsg += std::format("{:<{}}{}\n", label, kFieldWidth, value);
}

void HardwareException::appendFieldPrefix(Utf8& outMsg, const std::string_view label)
{
    constexpr uint32_t kFieldWidth = 24;
    outMsg += std::format("{:<{}}", label, kFieldWidth);
}

void HardwareException::log(const TaskContext& ctx, const std::string_view title, SWC_LP_EXCEPTION_POINTERS args, HardwareExceptionExtraInfoFn extraInfoFn, const void* userData)
{
    Logger::ScopedLock loggerLock(ctx.global().logger());

    Utf8 msg;
    msg += LogColorHelper::toAnsi(ctx, LogColor::BrightRed);
    msg += title;
    if (title.empty() || title.back() != '\n')
        msg += "\n";
    msg += LogColorHelper::toAnsi(ctx, LogColor::Reset);

    appendCrashGroup(msg, ctx, args);
    appendContextGroup(msg, ctx, extraInfoFn, userData);
    appendHostTraceGroup(msg, args);
    Logger::print(ctx, msg);
}

SWC_END_NAMESPACE();
