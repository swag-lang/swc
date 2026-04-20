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

    uint32_t indentColumns(const std::string_view text, const uint32_t indentWidth)
    {
        uint32_t columns = 0;
        for (const char c : text)
        {
            if (c == '\t')
                columns += indentWidth;
            else if (c == ' ')
                columns++;
        }

        return columns;
    }

    char applyLiteralCase(const char c, const FormatLiteralCase mode)
    {
        switch (mode)
        {
            case FormatLiteralCase::Upper:
                if (c >= 'a' && c <= 'z')
                    return static_cast<char>(c - ('a' - 'A'));
                break;
            case FormatLiteralCase::Lower:
                if (c >= 'A' && c <= 'Z')
                    return static_cast<char>(c + ('a' - 'A'));
                break;
            case FormatLiteralCase::Preserve:
                break;
        }
        return c;
    }

    void appendRegrouped(Utf8& out, const std::string_view digits, const uint32_t groupSize)
    {
        if (groupSize == 0 || digits.size() <= groupSize)
        {
            out += digits;
            return;
        }

        const size_t headSize = digits.size() % groupSize;
        size_t       index    = 0;

        if (headSize != 0)
        {
            out.append(digits.data(), headSize);
            index = headSize;
            if (index < digits.size())
                out += '_';
        }

        while (index < digits.size())
        {
            out.append(digits.data() + index, groupSize);
            index += groupSize;
            if (index < digits.size())
                out += '_';
        }
    }

    void appendDigitsPreservingSeparators(Utf8& out, const std::string_view digits, const FormatLiteralCase digitCase)
    {
        out.reserve(out.size() + digits.size());
        for (const char c : digits)
        {
            if (c == '_')
                out += '_';
            else
                out += applyLiteralCase(c, digitCase);
        }
    }

    void appendDigitsRegrouped(Utf8& out, const std::string_view digits, const uint32_t groupSize, const FormatLiteralCase digitCase)
    {
        std::string cleaned;
        cleaned.reserve(digits.size());
        for (const char c : digits)
        {
            if (c != '_')
                cleaned += applyLiteralCase(c, digitCase);
        }
        appendRegrouped(out, cleaned, groupSize);
    }

    void appendDigitsRegroupedFromStart(Utf8& out, const std::string_view digits, const uint32_t groupSize, const FormatLiteralCase digitCase)
    {
        std::string cleaned;
        cleaned.reserve(digits.size());
        for (const char c : digits)
        {
            if (c != '_')
                cleaned += applyLiteralCase(c, digitCase);
        }

        if (groupSize == 0 || cleaned.size() <= groupSize)
        {
            out += cleaned;
            return;
        }

        size_t index = 0;
        while (index < cleaned.size())
        {
            const size_t chunkSize = std::min<size_t>(groupSize, cleaned.size() - index);
            out.append(cleaned.data() + index, chunkSize);
            index += chunkSize;
            if (index < cleaned.size())
                out += '_';
        }
    }
}

AstSourceWriter::AstSourceWriter(FormatContext& formatCtx) :
    formatCtx_(&formatCtx),
    ast_(formatCtx.ast),
    srcView_(formatCtx.srcView),
    options_(formatCtx.options)
{
    SWC_ASSERT(ast_ != nullptr);
    SWC_ASSERT(srcView_ != nullptr);
    SWC_ASSERT(options_ != nullptr);
    validateAst(*ast_, *srcView_);

    const auto& tokens = srcView_->tokens();
    eofByte_           = sourceTokenByteStart(*srcView_, tokens.back());
}

void AstSourceWriter::write()
{
    beginOutput();
    writeNode(ast_->root());
    flushUntilByte(eofByte_);
    SWC_ASSERT(cursorByte_ == eofByte_);
    finalizeOutput();
}

void AstSourceWriter::beginOutput()
{
    const uint32_t prefixOffset = srcView_->sourceStartOffset();
    SWC_ASSERT(prefixOffset <= eofByte_);
    SWC_ASSERT(eofByte_ == srcView_->stringView().size());

    formatCtx_->output.clear();
    formatCtx_->output.reserve(srcView_->stringView().size());

    if (prefixOffset && options_->preserveBom)
        formatCtx_->output += srcView_->codeView(0, prefixOffset);

    cursorByte_ = prefixOffset;
}

void AstSourceWriter::finalizeOutput() const
{
    if (!options_->insertFinalNewline || hasTrailingLineBreak())
        return;

    formatCtx_->output += resolveFinalNewline();
}

void AstSourceWriter::writeNode(AstNodeRef nodeRef)
{
    if (!shouldVisitNode(nodeRef))
        return;
    const AstNode& node = ast_->node(nodeRef);
    if (hasCheckpoint(node))
        flushUntilByte(nodeCheckpointByte(nodeRef));
    writeNodeChildren(node);
}

void AstSourceWriter::writeNodeChildren(const AstNode& node)
{
    SmallVector<AstNodeRef> children;
    collectSourceOrderedChildren(children, node);
    for (const AstNodeRef childRef : children)
        writeNode(childRef);
}

void AstSourceWriter::collectSourceOrderedChildren(SmallVector<AstNodeRef>& out, const AstNode& node) const
{
    Ast::nodeIdInfos(node.id()).collectChildren(out, *ast_, node);
    std::ranges::stable_sort(out, [this](const AstNodeRef left, const AstNodeRef right) {
        return nodeSortByte(left) < nodeSortByte(right);
    });
}

bool AstSourceWriter::shouldVisitNode(AstNodeRef nodeRef) const
{
    return nodeRef.isValid() && !ast_->isAdditionalNode(nodeRef);
}

bool AstSourceWriter::hasCheckpoint(const AstNode& node) const
{
    if (!node.tokRef().isValid())
        return false;
    return srcView_->token(node.tokRef()).isNot(TokenId::EndOfFile);
}

uint32_t AstSourceWriter::nodeCheckpointByte(AstNodeRef nodeRef) const
{
    const AstNode& node = ast_->node(nodeRef);
    SWC_ASSERT(hasCheckpoint(node));

    const TokenRef tokRef               = node.tokRef();
    const auto [triviaStart, triviaEnd] = srcView_->triviaRangeForToken(tokRef);
    if (triviaStart < triviaEnd)
        return srcView_->trivia()[triviaStart].tok.byteStart;

    return sourceTokenByteStart(*srcView_, srcView_->token(tokRef));
}

uint32_t AstSourceWriter::nodeSortByte(AstNodeRef nodeRef) const
{
    if (!shouldVisitNode(nodeRef))
        return INVALID_BYTE;

    const AstNode& node = ast_->node(nodeRef);
    if (hasCheckpoint(node))
        return nodeCheckpointByte(nodeRef);

    SmallVector<AstNodeRef> children;
    Ast::nodeIdInfos(node.id()).collectChildren(children, *ast_, node);

    uint32_t result = INVALID_BYTE;
    for (const AstNodeRef childRef : children)
        result = std::min(result, nodeSortByte(childRef));
    return result;
}

void AstSourceWriter::flushUntilByte(uint32_t targetByte)
{
    SWC_ASSERT(targetByte <= eofByte_);
    if (targetByte <= cursorByte_)
        return;

    while (cursorByte_ < targetByte)
    {
        const SourcePiece piece = peekNextSourcePiece();
        SWC_ASSERT(piece.byteLength != 0);
        SWC_ASSERT(piece.byteStart == cursorByte_);
        SWC_ASSERT(piece.byteStart + piece.byteLength <= targetByte);
        appendNextSourcePiece();
    }
}

AstSourceWriter::SourcePiece AstSourceWriter::peekNextSourcePiece() const
{
    const auto& tokens      = srcView_->tokens();
    uint32_t    tokenIndex  = nextTokenIndex_;
    uint32_t    triviaIndex = nextTriviaIndex_;

    while (tokenIndex < tokens.size())
    {
        const auto [triviaStart, triviaEnd] = srcView_->triviaRangeForToken(TokenRef(tokenIndex));
        triviaIndex                         = std::max(triviaIndex, triviaStart);

        if (triviaIndex < triviaEnd)
            return makeTriviaPiece(triviaIndex);

        if (tokens[tokenIndex].isNot(TokenId::EndOfFile))
            return makeTokenPiece(tokenIndex);

        tokenIndex++;
    }

    return {};
}

void AstSourceWriter::appendNextSourcePiece()
{
    const auto& tokens = srcView_->tokens();
    while (nextTokenIndex_ < tokens.size())
    {
        const auto [triviaStart, triviaEnd] = srcView_->triviaRangeForToken(TokenRef(nextTokenIndex_));
        nextTriviaIndex_                    = std::max(nextTriviaIndex_, triviaStart);

        if (nextTriviaIndex_ < triviaEnd)
        {
            appendSourcePiece(makeTriviaPiece(nextTriviaIndex_));
            nextTriviaIndex_++;
            return;
        }

        const uint32_t tokenIndex = nextTokenIndex_++;
        if (tokens[tokenIndex].is(TokenId::EndOfFile))
            continue;

        appendSourcePiece(makeTokenPiece(tokenIndex));
        return;
    }

    SWC_UNREACHABLE();
}

void AstSourceWriter::appendSourcePiece(const SourcePiece& piece)
{
    const uint32_t sourceSize = static_cast<uint32_t>(srcView_->stringView().size());
    SWC_ASSERT(piece.byteStart <= sourceSize);
    SWC_ASSERT(piece.byteLength <= sourceSize - piece.byteStart);
    SWC_ASSERT(piece.byteStart == cursorByte_);
    SWC_ASSERT(piece.text.size() == piece.byteLength);

    switch (piece.tokenId)
    {
        case TokenId::Whitespace:
            appendWhitespacePiece(piece);
            break;
        case TokenId::CommentBlock:
            appendCommentPiece(piece);
            break;
        case TokenId::NumberHex:
        case TokenId::NumberBin:
        case TokenId::NumberInteger:
        case TokenId::NumberFloat:
            appendNumberPiece(piece);
            break;
        default:
            formatCtx_->output += piece.text;
            break;
    }

    cursorByte_ += piece.byteLength;
}

bool AstSourceWriter::shouldRewriteIndentation() const
{
    return options_->indentStyle != FormatIndentStyle::Preserve;
}

bool AstSourceWriter::shouldRewriteEndOfLine() const
{
    return options_->endOfLineStyle != FormatEndOfLineStyle::Preserve;
}

bool AstSourceWriter::hasTrailingLineBreak() const
{
    if (formatCtx_->output.empty())
        return false;
    return formatCtx_->output.back() == '\n' || formatCtx_->output.back() == '\r';
}

bool AstSourceWriter::isAtLineStart() const
{
    return formatCtx_->output.empty() || formatCtx_->output.back() == '\n';
}

void AstSourceWriter::appendWhitespacePiece(const SourcePiece& piece) const
{
    const bool rewriteIndent = shouldRewriteIndentation();
    const bool rewriteEol    = shouldRewriteEndOfLine();
    const bool trimTrailing  = !options_->preserveTrailingWhitespace;
    if (!rewriteIndent && !rewriteEol && !trimTrailing)
    {
        formatCtx_->output += piece.text;
        return;
    }

    const bool pieceEndsAtEof = piece.byteStart + piece.byteLength == eofByte_;

    const auto emitIndent = [this, rewriteIndent](const std::string_view indentText) {
        if (indentText.empty())
            return;

        if (rewriteIndent)
            appendNormalizedIndent(indentText);
        else
            formatCtx_->output += indentText;
    };

    bool   atLineStart = isAtLineStart();
    size_t index       = 0;

    while (index < piece.text.size())
    {
        const char c = piece.text[index];
        if (c == '\r' || c == '\n')
        {
            if (c == '\r' && index + 1 < piece.text.size() && piece.text[index + 1] == '\n')
                index++;

            if (rewriteEol)
                appendConfiguredEndOfLine();
            else if (c == '\r' && index < piece.text.size() && piece.text[index] == '\n')
                formatCtx_->output += "\r\n";
            else
                formatCtx_->output += c;

            atLineStart = true;
            index++;
            continue;
        }

        if (c != ' ' && c != '\t')
        {
            formatCtx_->output += c;
            atLineStart = false;
            index++;
            continue;
        }

        const size_t runStart = index;
        while (index < piece.text.size() && (piece.text[index] == ' ' || piece.text[index] == '\t'))
            index++;

        const bool nextIsEol = index < piece.text.size() && (piece.text[index] == '\r' || piece.text[index] == '\n');
        const bool nextIsEof = index == piece.text.size() && pieceEndsAtEof;
        if (trimTrailing && (nextIsEol || nextIsEof))
        {
            continue;
        }

        const std::string_view runText = piece.text.substr(runStart, index - runStart);
        if (atLineStart)
            emitIndent(runText);
        else
            formatCtx_->output += runText;

        atLineStart = false;
    }
}

void AstSourceWriter::appendCommentPiece(const SourcePiece& piece) const
{
    if (!shouldRewriteEndOfLine())
    {
        formatCtx_->output += piece.text;
        return;
    }

    size_t index = 0;
    while (index < piece.text.size())
    {
        const char c = piece.text[index];
        if (c == '\r')
        {
            if (index + 1 < piece.text.size() && piece.text[index + 1] == '\n')
                index++;
            appendConfiguredEndOfLine();
            index++;
            continue;
        }

        if (c == '\n')
        {
            appendConfiguredEndOfLine();
            index++;
            continue;
        }

        formatCtx_->output += c;
        index++;
    }
}

void AstSourceWriter::appendNumberPiece(const SourcePiece& piece) const
{
    SWC_ASSERT(piece.tokenId == TokenId::NumberHex ||
               piece.tokenId == TokenId::NumberBin ||
               piece.tokenId == TokenId::NumberInteger ||
               piece.tokenId == TokenId::NumberFloat);

    Utf8&            out  = formatCtx_->output;
    std::string_view text = piece.text;

    // Split off the optional `'suffix` (e.g. `'u32`, `'f64`).
    std::string_view body;
    std::string_view suffix;
    if (const size_t sufPos = text.find('\''); sufPos != std::string_view::npos)
    {
        body   = text.substr(0, sufPos);
        suffix = text.substr(sufPos);
    }
    else
    {
        body = text;
    }

    // Split off the `0x` / `0b` radix prefix for hex / binary literals.
    std::string_view prefix;
    const bool       isHex = piece.tokenId == TokenId::NumberHex;
    const bool       isBin = piece.tokenId == TokenId::NumberBin;
    if ((isHex || isBin) && body.size() >= 2 && body[0] == '0')
    {
        prefix = body.substr(0, 2);
        body   = body.substr(2);
    }

    // Emit the radix prefix with the configured prefix case.
    if (!prefix.empty())
    {
        out += prefix[0];
        out += applyLiteralCase(prefix[1], options_->hexLiteralPrefixCase);
    }

    // Emit the digit body (with fractional and exponent parts for floats).
    if (piece.tokenId == TokenId::NumberFloat)
    {
        size_t expPos = std::string_view::npos;
        for (size_t i = 0; i < body.size(); ++i)
        {
            if (body[i] == 'e' || body[i] == 'E')
            {
                expPos = i;
                break;
            }
        }

        const std::string_view mantissa  = expPos == std::string_view::npos ? body : body.substr(0, expPos);
        const uint32_t         groupSize = options_->decimalDigitSeparatorGroupSize;

        if (!options_->normalizeDigitSeparators)
        {
            out += mantissa;
        }
        else if (const size_t dotPos = mantissa.find('.'); dotPos == std::string_view::npos)
        {
            appendDigitsRegrouped(out, mantissa, groupSize, FormatLiteralCase::Preserve);
        }
        else
        {
            appendDigitsRegrouped(out, mantissa.substr(0, dotPos), groupSize, FormatLiteralCase::Preserve);
            out += '.';
            appendDigitsRegroupedFromStart(out, mantissa.substr(dotPos + 1), groupSize, FormatLiteralCase::Preserve);
        }

        if (expPos != std::string_view::npos)
        {
            out += applyLiteralCase(body[expPos], options_->floatExponentCase);
            std::string_view expTail = body.substr(expPos + 1);
            if (!expTail.empty() && (expTail[0] == '+' || expTail[0] == '-'))
            {
                out += expTail[0];
                expTail = expTail.substr(1);
            }
            if (options_->normalizeDigitSeparators)
                appendDigitsRegrouped(out, expTail, groupSize, FormatLiteralCase::Preserve);
            else
                out += expTail;
        }
    }
    else if (isHex)
    {
        if (options_->normalizeDigitSeparators)
            appendDigitsRegrouped(out, body, options_->hexDigitSeparatorGroupSize, options_->hexLiteralCase);
        else
            appendDigitsPreservingSeparators(out, body, options_->hexLiteralCase);
    }
    else if (isBin)
    {
        if (options_->normalizeDigitSeparators)
            appendDigitsRegrouped(out, body, options_->hexDigitSeparatorGroupSize, FormatLiteralCase::Preserve);
        else
            out += body;
    }
    else // NumberInteger
    {
        if (options_->normalizeDigitSeparators)
            appendDigitsRegrouped(out, body, options_->decimalDigitSeparatorGroupSize, FormatLiteralCase::Preserve);
        else
            out += body;
    }

    out += suffix;
}

void AstSourceWriter::appendNormalizedIndent(const std::string_view text) const
{
    const uint32_t columns     = indentColumns(text, std::max(options_->indentWidth, 1u));
    const uint32_t indentWidth = std::max(options_->indentWidth, 1u);

    switch (options_->indentStyle)
    {
        case FormatIndentStyle::Tabs:
        {
            formatCtx_->output.append(columns / indentWidth, '\t');
            formatCtx_->output.append(columns % indentWidth, ' ');
            break;
        }

        case FormatIndentStyle::Spaces:
            formatCtx_->output.append(columns, ' ');
            break;

        case FormatIndentStyle::Preserve:
            formatCtx_->output += text;
            break;
    }
}

void AstSourceWriter::appendConfiguredEndOfLine() const
{
    switch (options_->endOfLineStyle)
    {
        case FormatEndOfLineStyle::Lf:
            formatCtx_->output += '\n';
            break;
        case FormatEndOfLineStyle::CrLf:
            formatCtx_->output += "\r\n";
            break;
        case FormatEndOfLineStyle::Preserve:
            SWC_UNREACHABLE();
    }
}

std::string_view AstSourceWriter::resolveFinalNewline() const
{
    switch (options_->endOfLineStyle)
    {
        case FormatEndOfLineStyle::Lf:
            return "\n";

        case FormatEndOfLineStyle::CrLf:
            return "\r\n";

        case FormatEndOfLineStyle::Preserve:
            break;
    }

    const std::string_view text = formatCtx_->output.view();
    for (size_t i = text.size(); i != 0; --i)
    {
        if (text[i - 1] == '\n')
        {
            if (i >= 2 && text[i - 2] == '\r')
                return "\r\n";
            return "\n";
        }

        if (text[i - 1] == '\r')
            return "\r";
    }

    return "\n";
}

AstSourceWriter::SourcePiece AstSourceWriter::makeTriviaPiece(uint32_t triviaIndex) const
{
    const SourceTrivia& trivia = srcView_->trivia()[triviaIndex];
    return {
        .byteStart  = trivia.tok.byteStart,
        .byteLength = trivia.tok.byteLength,
        .tokenId    = trivia.tok.id,
        .text       = trivia.tok.string(*srcView_),
    };
}

AstSourceWriter::SourcePiece AstSourceWriter::makeTokenPiece(uint32_t tokenIndex) const
{
    const Token& token = srcView_->tokens()[tokenIndex];
    SWC_ASSERT(token.isNot(TokenId::EndOfFile));
    return {
        .byteStart  = sourceTokenByteStart(*srcView_, token),
        .byteLength = token.byteLength,
        .tokenId    = token.id,
        .text       = token.string(*srcView_),
    };
}

SWC_END_NAMESPACE();
