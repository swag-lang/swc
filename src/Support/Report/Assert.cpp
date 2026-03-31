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
    void appendContextField(Utf8& msg, const std::string_view label, const std::string_view value)
    {
        if (value.empty())
            return;

        msg += std::format("{}: {}\n", label, value);
    }

    void appendContextField(Utf8& msg, const std::string_view label, const Utf8& value)
    {
        appendContextField(msg, label, std::string_view(value));
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

    uint32_t codeRangeTokenLenChars(const SourceCodeRange& codeRange)
    {
        if (!codeRange.srcView || !codeRange.len)
            return 1;

        const uint32_t tokenLenChars = Utf8Helper::countChars(codeRange.srcView->codeView(codeRange.offset, codeRange.len));
        return std::max(1u, tokenLenChars);
    }

    void appendSourceContext(Utf8& msg, const TaskContext& ctx, const SourceCodeRange& codeRange)
    {
        SWC_ASSERT(codeRange.srcView != nullptr);

        const uint32_t    tokenLenChars = codeRangeTokenLenChars(codeRange);
        const Utf8        codeLine      = codeRange.srcView->codeLine(ctx, codeRange.line);
        const Utf8        lineNoStr     = std::to_string(codeRange.line);
        const SourceFile* sourceFile    = codeRange.srcView->file();
        const Utf8        fileLoc       = sourceFile ? FileSystem::formatFileLocation(&ctx, sourceFile->path(), codeRange.line, codeRange.column, codeRange.column + tokenLenChars) : FileSystem::formatFileLocation(&ctx, fs::path{}, codeRange.line, codeRange.column, codeRange.column + tokenLenChars);

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

        appendContextField(msg, "Phase", std::string_view(state.kindName()));

        if (state.codeGenFunction)
            appendContextField(msg, "Codegen function", (*state.codeGenFunction).getFullScopedName(ctx));
        if (state.runJitFunction)
            appendContextField(msg, "JIT function", (*state.runJitFunction).getFullScopedName(ctx));
        if (state.waiterSymbol)
            appendContextField(msg, "Current symbol", state.waiterSymbol->getFullScopedName(ctx));
        if (state.symbol)
            appendContextField(msg, "Blocking symbol", state.symbol->getFullScopedName(ctx));
        if (state.codeRef.isValid())
            appendContextField(msg, "Token", Diagnostic::tokenErrorString(ctx, state.codeRef));

        if (hasCodeRange)
            appendSourceContext(msg, ctx, codeRange);
    }
}

void swcAssert(const char* expr, const char* file, int line)
{
    const Utf8 fileLoc = FileSystem::formatFileLocation(nullptr, fs::path(file ? file : "<null>"), static_cast<uint32_t>(line));
    const Utf8 msg     = std::format("Assertion Failed!\nFile: {}\nExpression: {}\n", fileLoc, expr);
    Os::panicBox(msg.c_str());
}

void swcInternalError(const char* file, int line, const char* expr)
{
    const Utf8 fileLoc = FileSystem::formatFileLocation(nullptr, fs::path(file ? file : "<null>"), static_cast<uint32_t>(line));
    Utf8       msg     = std::format("Internal Error!\nFile: {}\n", fileLoc);
    if (expr)
        msg += std::format("Expression: {}\n", expr);
    if (const TaskContext* const ctx = TaskContext::current())
        appendInternalErrorTaskContext(msg, *ctx);
    Os::panicBox(msg.c_str());
}

SWC_END_NAMESPACE();
