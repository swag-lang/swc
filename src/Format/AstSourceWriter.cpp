#include "pch.h"
#include "Format/AstSourceWriter.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/SourceFile.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint32_t sourceTokenByteStart(const SourceView& srcView, const Token& token)
    {
        if (token.id == TokenId::Identifier)
            return srcView.identifiers()[token.byteStart].byteStart;
        return token.byteStart;
    }

    Result reportFormatFailure(TaskContext& ctx, const SourceFile* file, const std::string_view because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_format_failed);
        diag.addArgument(Diagnostic::ARG_PATH, file ? FileSystem::formatFileName(&ctx, file->path()) : Utf8("<unknown-file>"));
        diag.addArgument(Diagnostic::ARG_BECAUSE, Utf8(because));
        diag.report(ctx);
        return Result::Error;
    }

    Result validateAst(TaskContext& ctx, const SourceFile& file, const Ast& ast, const SourceView& srcView)
    {
        const AstNodeRef rootRef = ast.root();
        if (rootRef.isInvalid())
            return reportFormatFailure(ctx, &file, "parsed AST has no root node");

        const auto& tokens = srcView.tokens();
        if (tokens.empty())
            return reportFormatFailure(ctx, &file, "source view has no tokens");
        if (!tokens.back().is(TokenId::EndOfFile))
            return reportFormatFailure(ctx, &file, "source view is missing the end-of-file token");

        std::unordered_set<uint32_t> visited;
        SmallVector<AstNodeRef>      children;
        SmallVector<AstNodeRef>      stack;
        stack.push_back(rootRef);

        while (!stack.empty())
        {
            const AstNodeRef nodeRef = stack.back();
            stack.pop_back();
            if (!nodeRef.isValid())
                return reportFormatFailure(ctx, &file, "AST contains an invalid node reference");
            if (!visited.insert(nodeRef.get()).second)
                return reportFormatFailure(ctx, &file, "AST reuses a node in multiple places");

            const AstNode& node = ast.node(nodeRef);
            if (node.id() == AstNodeId::Invalid)
                return reportFormatFailure(ctx, &file, "AST exposes the invalid sentinel node");
            if (node.srcViewRef() != srcView.ref())
                return reportFormatFailure(ctx, &file, "AST node refers to a different source view");
            if (node.tokRef().isInvalid())
                return reportFormatFailure(ctx, &file, "AST node is missing its source token reference");
            if (node.tokRef().get() >= tokens.size())
                return reportFormatFailure(ctx, &file, "AST node token reference is outside the token stream");

            children.clear();
            Ast::nodeIdInfos(node.id()).collectChildren(children, ast, node);

            for (const AstNodeRef childRef : std::ranges::reverse_view(children))
            {
                if (!childRef.isValid())
                    return reportFormatFailure(ctx, &file, "AST contains an invalid child reference");

                const AstNode& child = ast.node(childRef);
                if (child.srcViewRef() != srcView.ref())
                    return reportFormatFailure(ctx, &file, "AST child refers to a different source view");
                if (child.tokRef().isInvalid())
                    return reportFormatFailure(ctx, &file, "AST child is missing its source token reference");
                if (child.tokRef().get() >= tokens.size())
                    return reportFormatFailure(ctx, &file, "AST child token reference is outside the token stream");
                if (child.tokRef().get() < node.tokRef().get())
                    return reportFormatFailure(ctx, &file, "AST child starts before its parent");

                stack.push_back(childRef);
            }

            uint32_t orderedToken = node.tokRef().get();
            for (const AstNodeRef childRef : children)
            {
                const AstNode& child = ast.node(childRef);
                if (child.tokRef().get() < orderedToken)
                    return reportFormatFailure(ctx, &file, "AST children are not ordered like the source");
                orderedToken = child.tokRef().get();
            }
        }

        return Result::Continue;
    }

    Result appendSourceRange(Format::Context& formatCtx, uint32_t& cursor, const uint32_t start, const uint32_t length, const std::string_view text, const std::string_view kind)
    {
        const SourceView& srcView     = *formatCtx.srcView;
        const SourceFile* sourceFile  = formatCtx.file;
        TaskContext&      taskContext = *formatCtx.task;
        const auto        sourceSize  = static_cast<uint32_t>(srcView.stringView().size());

        if (start > sourceSize || start + length > sourceSize)
            return reportFormatFailure(taskContext, sourceFile, std::format("a {} range escapes the source buffer", kind));
        if (start != cursor)
            return reportFormatFailure(taskContext, sourceFile, std::format("a {} is disconnected from the original source stream", kind));
        if (text.size() != length)
            return reportFormatFailure(taskContext, sourceFile, std::format("a {} text length does not match its source range", kind));

        formatCtx.output += text;
        cursor += length;
        return Result::Continue;
    }

    uint32_t firstSourceOffset(const SourceView& srcView)
    {
        const auto& tokens = srcView.tokens();
        SWC_ASSERT(!tokens.empty());

        uint32_t result = sourceTokenByteStart(srcView, tokens.back());
        for (const Token& token : tokens)
        {
            if (token.is(TokenId::EndOfFile))
                break;

            result = std::min(result, sourceTokenByteStart(srcView, token));
            break;
        }

        if (!srcView.trivia().empty())
            result = std::min(result, srcView.trivia().front().tok.byteStart);
        return result;
    }

    Result writeExactSource(Format::Context& formatCtx)
    {
        const SourceView& srcView = *formatCtx.srcView;
        const auto&       tokens  = srcView.tokens();
        const uint32_t    eofByte = sourceTokenByteStart(srcView, tokens.back());
        if (eofByte != srcView.stringView().size())
            return reportFormatFailure(*formatCtx.task, formatCtx.file, "end-of-file token does not point at the end of the source");

        const uint32_t prefixOffset = firstSourceOffset(srcView);
        formatCtx.output.clear();
        formatCtx.output.reserve(srcView.stringView().size());

        uint32_t cursor = 0;
        if (prefixOffset)
        {
            formatCtx.output += srcView.codeView(0, prefixOffset);
            cursor = prefixOffset;
        }

        for (uint32_t tokenIndex = 0; tokenIndex < tokens.size(); ++tokenIndex)
        {
            const auto [triviaStart, triviaEnd] = srcView.triviaRangeForToken(TokenRef(tokenIndex));
            for (uint32_t triviaIndex = triviaStart; triviaIndex < triviaEnd; ++triviaIndex)
            {
                const SourceTrivia& trivia = srcView.trivia()[triviaIndex];
                SWC_RESULT(appendSourceRange(formatCtx, cursor, trivia.tok.byteStart, trivia.tok.byteLength, trivia.tok.string(srcView), "trivia"));
            }

            const Token& token = tokens[tokenIndex];
            if (token.is(TokenId::EndOfFile))
                continue;

            SWC_RESULT(appendSourceRange(formatCtx, cursor, sourceTokenByteStart(srcView, token), token.byteLength, token.string(srcView), "token"));
        }

        if (cursor != eofByte)
            return reportFormatFailure(*formatCtx.task, formatCtx.file, "formatted output does not cover the full source");
        return Result::Continue;
    }
}

Result Format::AstSourceWriter::write(Context& formatCtx)
{
    if (!formatCtx.task)
        return Result::Error;

    TaskContext& taskContext = *formatCtx.task;
    if (!formatCtx.file || !formatCtx.ast || !formatCtx.srcView || !formatCtx.options)
        return reportFormatFailure(taskContext, formatCtx.file, "format context is incomplete");
    if (!formatCtx.options->exactRoundTrip)
        return reportFormatFailure(taskContext, formatCtx.file, "only exact round-trip formatting is implemented");

    SWC_RESULT(validateAst(taskContext, *formatCtx.file, *formatCtx.ast, *formatCtx.srcView));
    return writeExactSource(formatCtx);
}

SWC_END_NAMESPACE();
