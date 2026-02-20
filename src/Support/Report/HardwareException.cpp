#include "pch.h"
#include "Support/Report/HardwareException.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void appendPointerField(Utf8& outMsg, std::string_view label, const void* ptr)
    {
        HardwareException::appendField(outMsg, label, std::format("0x{:016X}", reinterpret_cast<uint64_t>(ptr)));
    }

    void appendTaskFunction(Utf8& outMsg, const TaskContext& ctx, const char* label, const SymbolFunction* function)
    {
        if (!function)
            return;
        HardwareException::appendField(outMsg, "function name", function->name(ctx));
    }

    void appendTaskStateGroup(Utf8& outMsg, const TaskContext& ctx)
    {
        const TaskState& state = ctx.state();
        HardwareException::appendSectionHeader(outMsg, "task");
        HardwareException::appendField(outMsg, "state", state.kindName());

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
                HardwareException::appendField(outMsg, "source", FileSystem::formatFileLocation(&ctx, sourceFile->path(), codeRange.line, codeRange.column));
            }
        }

        appendTaskFunction(outMsg, ctx, "jit function", state.runJitFunction);
        appendTaskFunction(outMsg, ctx, "codegen function", state.codeGenFunction);

        if (state.symbol)
            appendPointerField(outMsg, "symbol ptr", state.symbol);

        if (state.waiterSymbol)
            appendPointerField(outMsg, "waiter symbol ptr", state.waiterSymbol);
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
        Os::appendHostExceptionSummary(ctx, outMsg, args);
    }

    void appendContextGroup(Utf8& outMsg, std::string_view extraInfo)
    {
        if (!extraInfo.empty())
        {
            HardwareException::appendSectionHeader(outMsg, "context");
            outMsg += std::format("{}\n", extraInfo);
        }
    }

    void appendHostTraceGroup(Utf8& outMsg, const TaskContext& ctx, SWC_LP_EXCEPTION_POINTERS args)
    {
        HardwareException::appendSectionHeader(outMsg, "cpu context");
        Os::appendHostCpuContext(outMsg, args);
        HardwareException::appendSectionHeader(outMsg, "trace");
        Os::appendHostHandlerStack(ctx, outMsg);
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
    appendHostTraceGroup(msg, ctx, args);
    Logger::print(ctx, msg);
}

SWC_END_NAMESPACE();
