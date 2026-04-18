#include "pch.h"
#include "Format/AstSourceWriter.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint32_t sourceTokenByteStart(const SourceView& srcView, const Token& token)
    {
        if (token.id == TokenId::Identifier)
            return srcView.identifiers()[token.byteStart].byteStart;
        return token.byteStart;
    }

    void validateAst(const Ast& ast, const SourceView& srcView)
    {
        SWC_ASSERT(!ast.root().isInvalid());
        const auto& tokens = srcView.tokens();
        SWC_ASSERT(!tokens.empty());
        SWC_ASSERT(tokens.back().is(TokenId::EndOfFile));
    }

    void appendSourceRange(Format::Context& formatCtx, uint32_t& cursor, const uint32_t start, const uint32_t length, const std::string_view text)
    {
        const SourceView& srcView    = *formatCtx.srcView;
        const uint32_t    sourceSize = static_cast<uint32_t>(srcView.stringView().size());

        SWC_ASSERT(start <= sourceSize);
        SWC_ASSERT(length <= sourceSize - start);
        SWC_ASSERT(start == cursor);
        SWC_ASSERT(text.size() == length);

        formatCtx.output += text;
        cursor += length;
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

    void writeExactSource(Format::Context& formatCtx)
    {
        const SourceView& srcView = *formatCtx.srcView;
        const auto&       tokens  = srcView.tokens();
        const uint32_t    eofByte = sourceTokenByteStart(srcView, tokens.back());
        SWC_ASSERT(eofByte == srcView.stringView().size());

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
                appendSourceRange(formatCtx, cursor, trivia.tok.byteStart, trivia.tok.byteLength, trivia.tok.string(srcView));
            }

            const Token& token = tokens[tokenIndex];
            if (token.is(TokenId::EndOfFile))
                continue;

            appendSourceRange(formatCtx, cursor, sourceTokenByteStart(srcView, token), token.byteLength, token.string(srcView));
        }

        SWC_ASSERT(cursor == eofByte);
    }
}

void Format::AstSourceWriter::write(Context& formatCtx)
{
    SWC_ASSERT(formatCtx.ast != nullptr);
    SWC_ASSERT(formatCtx.srcView != nullptr);
    SWC_ASSERT(formatCtx.options != nullptr);
    SWC_ASSERT(formatCtx.options->exactRoundTrip);

    validateAst(*formatCtx.ast, *formatCtx.srcView);
    writeExactSource(formatCtx);
}

SWC_END_NAMESPACE();
