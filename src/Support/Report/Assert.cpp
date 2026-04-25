#include "pch.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/SourceFile.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void appendCallStack(Utf8& msg, const TaskContext* ctx)
    {
        std::array<uintptr_t, 32> frames{};
        const uint32_t            numFrames = Os::captureCallStack(frames, 2);
        if (!numFrames)
            return;

        msg += "Call stack:\n";
        for (uint32_t i = 0; i < numFrames; ++i)
        {
            const uintptr_t address = frames[i];
            msg += std::format("  [{:02}] 0x{:016X}", i, address);

            Os::ResolvedAddress resolved;
            if (Os::resolveAddress(resolved, address, ctx))
            {
                if (!resolved.moduleName.empty())
                    msg += std::format(" {}", resolved.moduleName);
                if (!resolved.symbolName.empty())
                    msg += std::format(" | {}", resolved.symbolName);
                if (!resolved.sourceLocation.empty())
                    msg += std::format(" | {}", resolved.sourceLocation);
            }

            msg += "\n";
        }
    }

    bool tryGetTaskStateCodeRange(const TaskContext& ctx, SourceCodeRange& outCodeRange)
    {
        const TaskState& state = ctx.state();
        if (!state.codeRef.isValid())
            return false;

        const SourceView& srcView = ctx.compiler().srcView(state.codeRef.srcViewRef);
        if (state.codeRef.tokRef.get() >= srcView.tokens().size())
            return false;

        outCodeRange = srcView.tokenCodeRange(ctx, state.codeRef.tokRef);
        return outCodeRange.srcView != nullptr && outCodeRange.line != 0;
    }

    void appendSourceContext(Utf8& msg, const TaskContext& ctx, const SourceCodeRange& codeRange)
    {
        SWC_ASSERT(codeRange.srcView != nullptr);

        const uint32_t tokenLenChars = !codeRange.len ? 1 : std::max(1u, Utf8Helper::countChars(codeRange.srcView->codeView(codeRange.offset, codeRange.len)));
        const Utf8     codeLine   = codeRange.srcView->codeLine(ctx, codeRange.line);
        const Utf8     lineNoStr  = std::to_string(codeRange.line);
        const SourceFile* sourceFile = codeRange.srcView->file();
        const Utf8     fileLoc    = sourceFile ? sourceFile->formatFileLocation(&ctx, codeRange.line, codeRange.column, codeRange.column + tokenLenChars) : FileSystem::formatFileLocation(&ctx, fs::path{}, codeRange.line, codeRange.column, codeRange.column + tokenLenChars);

        msg += "Source context:\n";
        msg += std::format("  --> {}\n", fileLoc);
        msg += std::format(" {} | {}\n", lineNoStr, codeLine);
        msg += std::format(" {} | ", Utf8(static_cast<uint32_t>(lineNoStr.length()), ' '));
        msg.append(codeRange.column > 1 ? codeRange.column - 1 : 0, ' ');
        msg.append(tokenLenChars, '^');
        msg += "\n";
    }

    void appendInternalErrorTaskContext(Utf8& msg, const TaskContext& ctx)
    {
        const TaskState& state = ctx.state();
        SourceCodeRange  codeRange;
        const bool       hasCodeRange = tryGetTaskStateCodeRange(ctx, codeRange);

        if (state.kind == TaskStateKind::None &&
            !hasCodeRange &&
            !state.runJitFunction &&
            !state.codeGenFunction &&
            !state.symbol &&
            !state.waiterSymbol)
            return;

        msg += std::format("Phase: {}\n", TaskState::kindName(state.kind));

        if (state.codeGenFunction)
            msg += std::format("Codegen function: {}\n", state.codeGenFunction->getFullScopedName(ctx));
        if (state.runJitFunction)
            msg += std::format("JIT function: {}\n", state.runJitFunction->getFullScopedName(ctx));
        if (state.waiterSymbol)
            msg += std::format("Current symbol: {}\n", state.waiterSymbol->getFullScopedName(ctx));
        if (state.symbol)
            msg += std::format("Blocking symbol: {}\n", state.symbol->getFullScopedName(ctx));
        if (state.codeRef.isValid())
            msg += std::format("Token: {}\n", Diagnostic::tokenErrorString(ctx, state.codeRef));

        if (hasCodeRange)
            appendSourceContext(msg, ctx, codeRange);
    }
}

void swcAssert(const char* expr, const char* file, int line)
{
    const Utf8               fileLoc = FileSystem::formatFileLocation(nullptr, fs::path(file ? file : "<null>"), static_cast<uint32_t>(line));
    Utf8                     msg     = std::format("Assertion Failed!\nFile: {}\nExpression: {}\n", fileLoc, expr);
    const TaskContext* const ctx     = TaskContext::current();
    if (ctx)
        appendInternalErrorTaskContext(msg, *ctx);
    appendCallStack(msg, ctx);
    Os::panicBox(msg.c_str());
}

void swcInternalError(const char* file, int line, const char* expr)
{
    const Utf8 fileLoc = FileSystem::formatFileLocation(nullptr, fs::path(file ? file : "<null>"), static_cast<uint32_t>(line));
    Utf8       msg     = std::format("Internal Error!\nFile: {}\n", fileLoc);
    if (expr)
        msg += std::format("Expression: {}\n", expr);
    const TaskContext* const ctx = TaskContext::current();
    if (ctx)
        appendInternalErrorTaskContext(msg, *ctx);
    appendCallStack(msg, ctx);
    Os::panicBox(msg.c_str());
}

SWC_END_NAMESPACE();
