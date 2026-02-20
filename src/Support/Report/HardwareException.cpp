#include "pch.h"
#include "Support/Report/HardwareException.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Support/Os/Os.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const char* taskStateName(const TaskStateKind kind)
    {
        switch (kind)
        {
            case TaskStateKind::None:
                return "None";
            case TaskStateKind::RunJit:
                return "Run JIT";
            case TaskStateKind::SemaParsing:
                return "Semantic parsing";
            case TaskStateKind::CodeGenParsing:
                return "Codegen parsing";
            case TaskStateKind::SemaWaitIdentifier:
                return "Wait identifier";
            case TaskStateKind::SemaWaitCompilerDefined:
                return "Wait compiler-defined";
            case TaskStateKind::SemaWaitImplRegistrations:
                return "Wait impl registrations";
            case TaskStateKind::SemaWaitSymDeclared:
                return "Wait symbol declared";
            case TaskStateKind::SemaWaitSymTyped:
                return "Wait symbol typed";
            case TaskStateKind::SemaWaitSymSemaCompleted:
                return "Wait symbol sema completed";
            case TaskStateKind::SemaWaitSymCodeGenPreSolved:
                return "Wait symbol codegen pre-solved";
            case TaskStateKind::SemaWaitSymCodeGenCompleted:
                return "Wait symbol codegen completed";
            case TaskStateKind::SemaWaitTypeCompleted:
                return "Wait type completed";
            default:
                return "Unknown";
        }
    }

    void appendTaskFunction(Utf8& outMsg, const TaskContext& ctx, const char* label, const SymbolFunction* function)
    {
        if (!function)
            return;
        HardwareException::appendField(outMsg, label, function->name(ctx));
        const Utf8 fullName = function->getFullScopedName(ctx);
        if (!fullName.empty())
            HardwareException::appendField(outMsg, "function scope", fullName);
    }

    void appendTaskStateGroup(Utf8& outMsg, const TaskContext& ctx)
    {
        const TaskState& state = ctx.state();
        HardwareException::appendSectionHeader(outMsg, "task");
        HardwareException::appendField(outMsg, "state", taskStateName(state.kind));

        if (state.nodeRef.isValid())
            HardwareException::appendField(outMsg, "node ref", std::format("{}", state.nodeRef.get()));

        if (state.codeRef.isValid())
        {
            HardwareException::appendField(outMsg, "src view ref", std::format("{}", state.codeRef.srcViewRef.get()));
            HardwareException::appendField(outMsg, "token ref", std::format("{}", state.codeRef.tokRef.get()));

            const SourceView&     srcView    = ctx.compiler().srcView(state.codeRef.srcViewRef);
            const Token&          token      = srcView.token(state.codeRef.tokRef);
            const SourceCodeRange codeRange  = token.codeRange(ctx, srcView);
            const SourceFile*     sourceFile = srcView.file();
            if (sourceFile)
            {
                HardwareException::appendField(outMsg, "source", std::format("{}:{}:{}", sourceFile->path().string(), codeRange.line, codeRange.column));
            }
        }

        appendTaskFunction(outMsg, ctx, "jit function", state.runJitFunction);
        appendTaskFunction(outMsg, ctx, "codegen function", state.codeGenFunction);

        if (state.symbol)
            HardwareException::appendField(outMsg, "symbol", state.symbol->name(ctx));
        if (state.waiterSymbol)
            HardwareException::appendField(outMsg, "waiter symbol", state.waiterSymbol->name(ctx));
    }

    void appendCrashGroup(Utf8& outMsg, const TaskContext& ctx, SWC_LP_EXCEPTION_POINTERS args)
    {
        HardwareException::appendSectionHeader(outMsg, "infos");
        HardwareException::appendField(outMsg, "host", std::format("os = {}, cpu = {}, exception backend = {}", Os::hostOsName(), Os::hostCpuName(), Os::hostExceptionBackendName()));
        HardwareException::appendField(outMsg, "process id", std::format("{}", Os::currentProcessId()));
        HardwareException::appendField(outMsg, "thread id", std::format("{}", Os::currentThreadId()));
#if SWC_DEV_MODE
        HardwareException::appendField(outMsg, "cmd randomize", std::format("{} (seed {})", ctx.cmdLine().randomize, ctx.cmdLine().randSeed));
#endif
        outMsg += "\n";
        Os::appendHostExceptionSummary(outMsg, args);
    }

    void appendContextGroup(Utf8& outMsg, std::string_view extraInfo)
    {
        if (!extraInfo.empty())
        {
            HardwareException::appendSectionHeader(outMsg, "context");
            outMsg += std::format("{}\n", extraInfo);
        }
    }

    void appendHostTraceGroup(Utf8& outMsg, SWC_LP_EXCEPTION_POINTERS args)
    {
        HardwareException::appendSectionHeader(outMsg, "cpu context");
        Os::appendHostCpuContext(outMsg, args);
        HardwareException::appendSectionHeader(outMsg, "trace");
        Os::appendHostHandlerStack(outMsg);
    }
}

void HardwareException::appendSectionHeader(Utf8& outMsg, const std::string_view title)
{
    outMsg += "\n";
    outMsg += title;
    outMsg += ":";
    outMsg += "\n";
    outMsg += "---------------------------------\n";
}

void HardwareException::appendField(Utf8& outMsg, const std::string_view label, const std::string_view value)
{
    constexpr uint32_t kFieldWidth = 24;
    SWC_ASSERT(!label.empty());
    SWC_ASSERT(label.back() != ':');
    outMsg += label;
    outMsg += ":";
    uint32_t used = static_cast<uint32_t>(label.size()) + 1;
    while (used < kFieldWidth)
    {
        outMsg += " ";
        ++used;
    }
    outMsg += value;
    outMsg += "\n";
}

void HardwareException::log(const TaskContext& ctx, const std::string_view title, SWC_LP_EXCEPTION_POINTERS args, const std::string_view extraInfo)
{
    Logger::ScopedLock loggerLock(ctx.global().logger());

    Utf8 msg;
    msg += LogColorHelper::toAnsi(ctx, LogColor::BrightRed);
    msg += title;
    msg += LogColorHelper::toAnsi(ctx, LogColor::Reset);

    appendContextGroup(msg, extraInfo);
    appendTaskStateGroup(msg, ctx);
    appendCrashGroup(msg, ctx, args);
    appendHostTraceGroup(msg, args);
    Logger::print(ctx, msg);
}

SWC_END_NAMESPACE();
