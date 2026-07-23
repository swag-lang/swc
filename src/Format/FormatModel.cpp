#include "pch.h"
#include "Format/FormatModel.h"
#include "Compiler/Lexer/SourceView.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint32_t sourceTokenByteStart(const SourceView& srcView, const Token& token)
    {
        if (token.id == TokenId::Identifier)
            return srcView.identifiers()[token.byteStart].byteStart;
        return token.byteStart;
    }

    bool isEolChar(const char c)
    {
        return c == '\n' || c == '\r';
    }

    uint32_t countGapNewlines(const std::string_view text)
    {
        uint32_t total = 0;
        for (size_t i = 0; i < text.size(); ++i)
        {
            const char c = text[i];
            if (c == '\n')
                total++;
            else if (c == '\r')
            {
                total++;
                if (i + 1 < text.size() && text[i + 1] == '\n')
                    i++;
            }
        }

        return total;
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
            out.append(digits.data() + 0, headSize);
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

void FormatModel::build(const SourceView& srcView, const FormatOptions& options)
{
    srcView_ = &srcView;
    options_ = &options;
    pieces_.clear();
    gaps_.clear();
    blocks_.clear();
    ownedTexts_.clear();

    const auto& tokens = srcView.tokens();
    SWC_ASSERT(!tokens.empty());
    SWC_ASSERT(tokens.back().is(TokenId::EndOfFile));

    tokenToPiece_.assign(tokens.size(), FormatPiece::INVALID_INDEX);
    pieces_.reserve(tokens.size());
    gaps_.reserve(tokens.size() + 1);

    std::string_view pendingGap;
    uint32_t         pendingGapStart = 0;

    auto pushPiece = [&](const uint32_t byteStart, const std::string_view text, const TokenId id, const uint32_t tokenIndex) {
        FormatGap gap;
        gap.origText = pendingGap;
        gaps_.push_back(std::move(gap));
        pendingGap = {};

        FormatPiece piece;
        piece.text      = text;
        piece.byteStart = byteStart;
        piece.id        = id;
        piece.isComment = id == TokenId::CommentLine || id == TokenId::CommentBlock;
        if (tokenIndex != FormatPiece::INVALID_INDEX)
            tokenToPiece_[tokenIndex] = static_cast<uint32_t>(pieces_.size());
        pieces_.push_back(std::move(piece));
    };

    auto pushWhitespace = [&](const Token& tok) {
        const std::string_view text = tok.string(srcView);
        if (pendingGap.empty())
        {
            pendingGap      = text;
            pendingGapStart = tok.byteStart;
        }
        else
        {
            // Whitespace runs separated only by other trivia stay contiguous in source.
            SWC_ASSERT(pendingGapStart + pendingGap.size() == tok.byteStart);
            pendingGap = std::string_view(pendingGap.data(), pendingGap.size() + text.size());
        }
    };

    for (uint32_t tokenIndex = 0; tokenIndex < tokens.size(); ++tokenIndex)
    {
        const auto [triviaStart, triviaEnd] = srcView.triviaRangeForToken(TokenRef(tokenIndex));
        for (uint32_t triviaIndex = triviaStart; triviaIndex < triviaEnd; ++triviaIndex)
        {
            const Token& triviaTok = srcView.trivia()[triviaIndex].tok;
            if (triviaTok.is(TokenId::Whitespace))
                pushWhitespace(triviaTok);
            else
                pushPiece(triviaTok.byteStart, triviaTok.string(srcView), triviaTok.id, FormatPiece::INVALID_INDEX);
        }

        const Token& token = tokens[tokenIndex];
        if (token.is(TokenId::EndOfFile))
            break;

        pushPiece(sourceTokenByteStart(srcView, token), token.string(srcView), token.id, tokenIndex);
    }

    // Trailing whitespace before the end of file.
    FormatGap gap;
    gap.origText = pendingGap;
    gaps_.push_back(std::move(gap));

    detectEol();
    markDisabledRegions();
    computeBrackets();
}

void FormatModel::detectEol()
{
    const std::string_view text = srcView_->stringView();
    for (size_t i = 0; i < text.size(); ++i)
    {
        if (text[i] == '\r')
        {
            eol_ = (i + 1 < text.size() && text[i + 1] == '\n') ? "\r\n" : "\r";
            return;
        }

        if (text[i] == '\n')
        {
            eol_ = "\n";
            return;
        }
    }

    eol_ = "\n";
}

void FormatModel::markDisabledRegions()
{
    const std::string_view offMarker = options_->formatOffComment.view();
    const std::string_view onMarker  = options_->formatOnComment.view();
    if (offMarker.empty())
        return;

    bool enabled = true;
    for (uint32_t i = 0; i < pieces_.size(); ++i)
    {
        FormatPiece& piece = pieces_[i];
        if (piece.isComment && !enabled && !onMarker.empty() && piece.text.contains(onMarker))
        {
            // The gap before the on-comment still renders raw; the comment itself is formatted.
            gaps_[i].frozen = true;
            enabled         = true;
            continue;
        }

        if (!enabled)
        {
            piece.frozen    = true;
            gaps_[i].frozen = true;
        }

        if (piece.isComment && enabled && piece.text.contains(offMarker))
            enabled = false;
    }

    if (!enabled)
        gaps_.back().frozen = true;
}

void FormatModel::computeBrackets()
{
    std::vector<uint32_t> stack;
    for (uint32_t i = 0; i < pieces_.size(); ++i)
    {
        FormatPiece& piece = pieces_[i];
        if (piece.removed)
        {
            piece.depth = static_cast<uint32_t>(stack.size());
            continue;
        }

        piece.match = FormatPiece::INVALID_INDEX;

        switch (piece.id)
        {
            case TokenId::SymLeftParen:
            case TokenId::SymLeftBracket:
            case TokenId::SymLeftCurly:
            case TokenId::SymAttrStart:
                piece.depth = static_cast<uint32_t>(stack.size());
                stack.push_back(i);
                break;

            case TokenId::SymRightParen:
            case TokenId::SymRightBracket:
            case TokenId::SymRightCurly:
            {
                if (!stack.empty())
                {
                    const uint32_t openIndex = stack.back();
                    const TokenId  openId    = pieces_[openIndex].id;
                    if (Token::toRelated(openId) == piece.id)
                    {
                        stack.pop_back();
                        piece.match             = openIndex;
                        pieces_[openIndex].match = i;
                    }
                }
                piece.depth = static_cast<uint32_t>(stack.size());
                break;
            }

            default:
                piece.depth = static_cast<uint32_t>(stack.size());
                break;
        }
    }
}

uint32_t FormatModel::pieceOfToken(const uint32_t tokenIndex) const
{
    SWC_ASSERT(tokenIndex < tokenToPiece_.size());
    return tokenToPiece_[tokenIndex];
}

void FormatModel::setGapSpaces(const uint32_t pieceIndex, const uint32_t spaces)
{
    FormatGap& gap = gaps_[pieceIndex];
    SWC_ASSERT(!gap.frozen);
    gap.modified = true;
    gap.newlines = 0;
    gap.spaces   = spaces;
    gap.indent.clear();
}

void FormatModel::setGapBreak(const uint32_t pieceIndex, const uint32_t newlines, const std::string_view indent)
{
    FormatGap& gap = gaps_[pieceIndex];
    SWC_ASSERT(!gap.frozen);
    SWC_ASSERT(newlines > 0);
    gap.modified = true;
    gap.newlines = newlines;
    gap.spaces   = 0;
    gap.indent   = indent;
}

void FormatModel::replaceText(const uint32_t pieceIndex, Utf8 text)
{
    FormatPiece& piece = pieces_[pieceIndex];
    SWC_ASSERT(!piece.frozen);
    ownedTexts_.push_back(std::move(text));
    piece.text     = ownedTexts_.back().view();
    piece.replaced = true;
}

void FormatModel::removePiece(const uint32_t pieceIndex)
{
    FormatPiece& piece = pieces_[pieceIndex];
    SWC_ASSERT(!piece.frozen);
    piece.removed = true;
}

bool FormatModel::gapHasNewline(const uint32_t pieceIndex) const
{
    return gapNewlineCount(pieceIndex) > 0;
}

uint32_t FormatModel::gapNewlineCount(const uint32_t pieceIndex) const
{
    const FormatGap& gap = gaps_[pieceIndex];
    if (gap.modified)
        return gap.newlines;
    return countGapNewlines(gap.origText);
}

uint32_t FormatModel::gapColumns(const uint32_t pieceIndex) const
{
    const FormatGap& gap = gaps_[pieceIndex];
    if (gap.modified)
        return gap.spaces;
    return textColumns(gap.origText, std::max(options_->tabWidth, 1u));
}

uint32_t FormatModel::prevPiece(const uint32_t pieceIndex) const
{
    uint32_t i = pieceIndex;
    while (i > 0)
    {
        i--;
        if (!pieces_[i].removed)
            return i;
    }

    return FormatPiece::INVALID_INDEX;
}

uint32_t FormatModel::nextPiece(const uint32_t pieceIndex) const
{
    for (uint32_t i = pieceIndex + 1; i < pieces_.size(); ++i)
    {
        if (!pieces_[i].removed)
            return i;
    }

    return FormatPiece::INVALID_INDEX;
}

uint32_t FormatModel::lineStartOf(const uint32_t pieceIndex) const
{
    uint32_t current = pieceIndex;
    for (;;)
    {
        if (gapHasNewline(current))
            return current;

        const uint32_t prev = prevPiece(current);
        if (prev == FormatPiece::INVALID_INDEX)
            return current;
        current = prev;
    }
}

std::string_view FormatModel::lineIndentOf(const uint32_t pieceIndex) const
{
    const uint32_t   lineStart = lineStartOf(pieceIndex);
    const FormatGap& gap       = gaps_[lineStart];
    if (gap.modified)
        return gap.indent.view();

    const size_t lastEol = gap.origText.find_last_of("\r\n");
    if (lastEol == std::string_view::npos)
        return lineStart == 0 ? gap.origText : std::string_view{};
    return gap.origText.substr(lastEol + 1);
}

void FormatModel::collectLineStarts(std::vector<uint32_t>& out) const
{
    out.clear();
    bool atLineStart = true;
    for (uint32_t i = 0; i < pieces_.size(); ++i)
    {
        if (pieces_[i].removed)
            continue;
        if (atLineStart || gapHasNewline(i))
            out.push_back(i);
        atLineStart = false;
    }
}

const FormatBlock* FormatModel::blockOfOpen(const uint32_t pieceIndex) const
{
    for (const FormatBlock& block : blocks_)
    {
        if (block.openPiece == pieceIndex)
            return &block;
    }

    return nullptr;
}

const FormatBlock* FormatModel::blockOfClose(const uint32_t pieceIndex) const
{
    for (const FormatBlock& block : blocks_)
    {
        if (block.closePiece == pieceIndex)
            return &block;
    }

    return nullptr;
}

uint32_t FormatModel::textColumns(const std::string_view text, const uint32_t tabWidth, const uint32_t startColumn)
{
    uint32_t column = startColumn;
    for (const char c : text)
    {
        if (c == '\t')
            column = (column / tabWidth + 1) * tabWidth;
        else if ((c & 0xC0) != 0x80)
            column++;
    }

    return column - startColumn;
}

uint32_t FormatModel::maxAllowedNewlines(const uint32_t gapIndex) const
{
    uint32_t maxNewlines = std::numeric_limits<uint32_t>::max();

    if (options_->maxConsecutiveEmptyLines > 0)
        maxNewlines = std::min(maxNewlines, options_->maxConsecutiveEmptyLines + 1);

    if (!options_->keepEmptyLinesAtStartOfBlock.value_or(true) && gapIndex > 0)
    {
        const uint32_t prev = prevPiece(gapIndex);
        if (prev != FormatPiece::INVALID_INDEX && pieces_[prev].is(TokenId::SymLeftCurly))
            maxNewlines = std::min(maxNewlines, 1u);
    }

    if (!options_->keepEmptyLinesAtEndOfBlock.value_or(true) && gapIndex < pieces_.size())
    {
        uint32_t next = gapIndex;
        if (pieces_[next].removed)
            next = nextPiece(next);
        if (next != FormatPiece::INVALID_INDEX && pieces_[next].is(TokenId::SymRightCurly))
            maxNewlines = std::min(maxNewlines, 1u);
    }

    const bool isTrailingGap = gapIndex + 1 == gaps_.size();
    if (options_->trimTrailingNewlines.value_or(false) && isTrailingGap)
        maxNewlines = std::min(maxNewlines, 1u);

    return maxNewlines;
}

void FormatModel::render(Utf8& output) const
{
    output.clear();
    output.reserve(srcView_->stringView().size());

    const uint32_t prefixOffset = srcView_->sourceStartOffset();
    if (prefixOffset && options_->preserveBom.value_or(true))
        output += srcView_->codeView(0, prefixOffset);

    for (uint32_t i = 0; i < pieces_.size(); ++i)
    {
        if (pieces_[i].removed)
            continue;
        renderGap(output, i);
        renderPiece(output, i);
    }

    renderGap(output, static_cast<uint32_t>(gaps_.size()) - 1);

    if (options_->insertFinalNewline.value_or(false))
    {
        if (output.empty() || !isEolChar(output.back()))
            output += resolveFinalNewline(output);
    }
}

void FormatModel::renderGap(Utf8& output, const uint32_t gapIndex) const
{
    const FormatGap& gap = gaps_[gapIndex];
    if (gap.frozen)
    {
        output += gap.origText;
        return;
    }

    if (!gap.modified)
    {
        renderOriginalGap(output, gapIndex);
        return;
    }

    const uint32_t newlines = std::min(gap.newlines, maxAllowedNewlines(gapIndex));
    if (newlines == 0 && gap.newlines == 0)
    {
        output.append(gap.spaces, ' ');
        return;
    }

    for (uint32_t i = 0; i < newlines; ++i)
        appendEol(output);
    appendIndent(output, gap.indent.view());
}

void FormatModel::renderOriginalGap(Utf8& output, const uint32_t gapIndex) const
{
    const FormatGap&       gap  = gaps_[gapIndex];
    const std::string_view text = gap.origText;
    if (text.empty())
        return;

    const bool     rewriteIndent = options_->indentStyle != FormatIndentStyle::Preserve;
    const bool     rewriteEol    = options_->endOfLineStyle != FormatEndOfLineStyle::Preserve;
    const bool     trimTrailing  = !options_->preserveTrailingWhitespace.value_or(true);
    const uint32_t maxNewlines   = maxAllowedNewlines(gapIndex);
    const uint32_t totalNewlines = countGapNewlines(text);

    const bool limitsNewlines = totalNewlines > maxNewlines;
    if (!rewriteIndent && !rewriteEol && !trimTrailing && !limitsNewlines)
    {
        output += text;
        return;
    }

    const bool isTrailingGap = gapIndex + 1 == gaps_.size();

    bool     atLineStart     = output.empty() || output.back() == '\n';
    size_t   index           = 0;
    uint32_t emittedNewlines = 0;

    while (index < text.size())
    {
        const char c = text[index];
        if (isEolChar(c))
        {
            const bool   isCrLf      = c == '\r' && index + 1 < text.size() && text[index + 1] == '\n';
            const size_t newlineSize = isCrLf ? 2 : 1;

            if (emittedNewlines < maxNewlines)
            {
                if (rewriteEol)
                    appendEol(output);
                else if (isCrLf)
                    output += "\r\n";
                else
                    output += c;
                emittedNewlines++;
                atLineStart = true;
            }

            index += newlineSize;
            continue;
        }

        if (c != ' ' && c != '\t')
        {
            output += c;
            atLineStart = false;
            index++;
            continue;
        }

        const size_t runStart = index;
        while (index < text.size() && (text[index] == ' ' || text[index] == '\t'))
            index++;

        const bool nextIsEol = index < text.size() && isEolChar(text[index]);
        const bool nextIsEof = index == text.size() && isTrailingGap;
        if (trimTrailing && (nextIsEol || nextIsEof))
            continue;

        // Drop whitespace that lives on a blank line we are collapsing away.
        if (emittedNewlines >= maxNewlines && nextIsEol)
            continue;

        const std::string_view runText = text.substr(runStart, index - runStart);
        if (atLineStart && rewriteIndent)
            appendIndent(output, runText);
        else
            output += runText;

        atLineStart = false;
    }
}

void FormatModel::renderPiece(Utf8& output, const uint32_t pieceIndex) const
{
    const FormatPiece& piece = pieces_[pieceIndex];
    if (piece.frozen)
    {
        output += piece.text;
        return;
    }

    if (piece.isComment)
    {
        renderCommentPiece(output, piece);
        return;
    }

    switch (piece.id)
    {
        case TokenId::NumberHex:
        case TokenId::NumberBin:
        case TokenId::NumberInteger:
        case TokenId::NumberFloat:
            renderNumberPiece(output, piece);
            break;

        default:
            output += piece.text;
            break;
    }
}

void FormatModel::renderCommentPiece(Utf8& output, const FormatPiece& piece) const
{
    if (options_->endOfLineStyle == FormatEndOfLineStyle::Preserve)
    {
        output += piece.text;
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
            appendEol(output);
            index++;
            continue;
        }

        if (c == '\n')
        {
            appendEol(output);
            index++;
            continue;
        }

        output += c;
        index++;
    }
}

void FormatModel::renderNumberPiece(Utf8& output, const FormatPiece& piece) const
{
    Utf8&            out  = output;
    std::string_view text = piece.text;

    // Split off the optional `'suffix` (e.g. `'u32`, `'f64`).
    std::string_view body;
    std::string_view suffix;
    const size_t     sufPos = text.find('\'');
    if (sufPos != std::string_view::npos)
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
    const bool       isHex = piece.id == TokenId::NumberHex;
    const bool       isBin = piece.id == TokenId::NumberBin;
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
    if (piece.id == TokenId::NumberFloat)
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

        if (!options_->normalizeDigitSeparators.value_or(false))
        {
            out += mantissa;
        }
        else
        {
            const size_t dotPos = mantissa.find('.');
            if (dotPos == std::string_view::npos)
            {
                appendDigitsRegrouped(out, mantissa, groupSize, FormatLiteralCase::Preserve);
            }
            else
            {
                appendDigitsRegrouped(out, mantissa.substr(0, dotPos), groupSize, FormatLiteralCase::Preserve);
                out += '.';
                appendDigitsRegroupedFromStart(out, mantissa.substr(dotPos + 1), groupSize, FormatLiteralCase::Preserve);
            }
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
            if (options_->normalizeDigitSeparators.value_or(false))
                appendDigitsRegrouped(out, expTail, groupSize, FormatLiteralCase::Preserve);
            else
                out += expTail;
        }
    }
    else if (isHex)
    {
        if (options_->normalizeDigitSeparators.value_or(false))
            appendDigitsRegrouped(out, body, options_->hexDigitSeparatorGroupSize, options_->hexLiteralCase);
        else
            appendDigitsPreservingSeparators(out, body, options_->hexLiteralCase);
    }
    else if (isBin)
    {
        if (options_->normalizeDigitSeparators.value_or(false))
            appendDigitsRegrouped(out, body, options_->hexDigitSeparatorGroupSize, FormatLiteralCase::Preserve);
        else
            out += body;
    }
    else // NumberInteger
    {
        if (options_->normalizeDigitSeparators.value_or(false))
            appendDigitsRegrouped(out, body, options_->decimalDigitSeparatorGroupSize, FormatLiteralCase::Preserve);
        else
            out += body;
    }

    out += suffix;
}

void FormatModel::appendIndent(Utf8& output, const std::string_view indentText) const
{
    if (indentText.empty())
        return;

    const uint32_t indentWidth = std::max(options_->indentWidth, 1u);

    switch (options_->indentStyle)
    {
        case FormatIndentStyle::Tabs:
        {
            uint32_t columns = 0;
            for (const char c : indentText)
            {
                if (c == '\t')
                    columns += indentWidth;
                else if (c == ' ')
                    columns++;
            }
            output.append(columns / indentWidth, '\t');
            output.append(columns % indentWidth, ' ');
            break;
        }

        case FormatIndentStyle::Spaces:
        {
            uint32_t columns = 0;
            for (const char c : indentText)
            {
                if (c == '\t')
                    columns += indentWidth;
                else if (c == ' ')
                    columns++;
            }
            output.append(columns, ' ');
            break;
        }

        case FormatIndentStyle::Preserve:
            output += indentText;
            break;
    }
}

void FormatModel::appendEol(Utf8& output) const
{
    switch (options_->endOfLineStyle)
    {
        case FormatEndOfLineStyle::Lf:
            output += '\n';
            break;
        case FormatEndOfLineStyle::CrLf:
            output += "\r\n";
            break;
        case FormatEndOfLineStyle::Preserve:
            output += eol_;
            break;
    }
}

std::string_view FormatModel::resolveFinalNewline(const Utf8& output) const
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

    const std::string_view text = output.view();
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

SWC_END_NAMESPACE();
