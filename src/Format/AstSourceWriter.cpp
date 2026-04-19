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
}

void AstSourceWriter::beginOutput()
{
    const uint32_t prefixOffset = srcView_->sourceStartOffset();
    SWC_ASSERT(prefixOffset <= eofByte_);
    SWC_ASSERT(eofByte_ == srcView_->stringView().size());

    formatCtx_->output.clear();
    formatCtx_->output.reserve(srcView_->stringView().size());

    if (prefixOffset)
        formatCtx_->output += srcView_->codeView(0, prefixOffset);

    cursorByte_ = prefixOffset;
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
        default:
            formatCtx_->output += piece.text;
            break;
    }

    cursorByte_ += piece.byteLength;
}

bool AstSourceWriter::shouldRewriteIndentation() const
{
    return !options_->preserveWhitespace && options_->indentStyle != FormatIndentStyle::Preserve;
}

bool AstSourceWriter::shouldRewriteEndOfLine() const
{
    return !options_->preserveEndOfLine && options_->endOfLineStyle != FormatEndOfLineStyle::Preserve;
}

bool AstSourceWriter::isAtLineStart() const
{
    return formatCtx_->output.empty() || formatCtx_->output.back() == '\n';
}

void AstSourceWriter::appendWhitespacePiece(const SourcePiece& piece)
{
    if (!shouldRewriteIndentation() && !shouldRewriteEndOfLine())
    {
        formatCtx_->output += piece.text;
        return;
    }

    const bool rewriteIndent = shouldRewriteIndentation();
    const bool rewriteEol    = shouldRewriteEndOfLine();

    const auto flushIndent = [this, &piece, rewriteIndent](const size_t indentStart, const size_t indentLen) {
        if (!indentLen)
            return;

        const std::string_view indentText = piece.text.substr(indentStart, indentLen);
        if (rewriteIndent)
            appendNormalizedIndent(indentText);
        else
            formatCtx_->output += indentText;
    };

    bool   atLineStart = isAtLineStart();
    size_t indentStart = 0;
    size_t indentLen   = 0;
    size_t index       = 0;

    while (index < piece.text.size())
    {
        const char c = piece.text[index];
        if (c == '\r' || c == '\n')
        {
            flushIndent(indentStart, indentLen);
            indentLen = 0;

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
            indentStart = index;
            continue;
        }

        if (atLineStart && (c == ' ' || c == '\t'))
        {
            if (!indentLen)
                indentStart = index;
            indentLen++;
            index++;
            continue;
        }

        flushIndent(indentStart, indentLen);
        indentLen   = 0;
        atLineStart = false;
        formatCtx_->output += c;
        index++;
    }

    flushIndent(indentStart, indentLen);
}

void AstSourceWriter::appendCommentPiece(const SourcePiece& piece)
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
        case FormatEndOfLineStyle::LF:
            formatCtx_->output += '\n';
            break;
        case FormatEndOfLineStyle::CRLF:
            formatCtx_->output += "\r\n";
            break;
        case FormatEndOfLineStyle::Preserve:
            SWC_UNREACHABLE();
    }
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
