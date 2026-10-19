#include "pch.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Main/Command/CommandLine.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Hash.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Compiler-global conditions are inspected before a token stream exists.
    // Keep the raw expression helpers independent of Lexer state.
    enum class GlobalIfValue
    {
        Unknown,
        False,
        True,
    };

    uint32_t editDistance(const std::string_view lhs, const std::string_view rhs)
    {
        std::vector<uint32_t> prev(rhs.size() + 1);
        std::vector<uint32_t> curr(rhs.size() + 1);

        for (size_t j = 0; j <= rhs.size(); ++j)
            prev[j] = static_cast<uint32_t>(j);

        for (size_t i = 0; i < lhs.size(); ++i)
        {
            curr[0] = static_cast<uint32_t>(i + 1);

            for (size_t j = 0; j < rhs.size(); ++j)
            {
                const uint32_t cost = lhs[i] == rhs[j] ? 0u : 1u;
                curr[j + 1]         = std::min({prev[j + 1] + 1, curr[j] + 1, prev[j] + cost});
            }

            std::swap(prev, curr);
        }

        return prev[rhs.size()];
    }

    std::optional<std::string_view> findClosestTokenName(const std::string_view name, const bool compilerKind)
    {
        std::optional<std::string_view> bestCandidate;
        uint32_t                        bestDistance = UINT32_MAX;

        for (uint32_t i = 0; i < static_cast<uint32_t>(TokenId::Count); ++i)
        {
            const auto tokenId = static_cast<TokenId>(i);
            if (compilerKind)
            {
                if (!Token::isCompiler(tokenId) || Token::isCompilerUniq(tokenId))
                    continue;
            }
            else if (!Token::isIntrinsic(tokenId))
            {
                continue;
            }

            const std::string_view candidate = Token::toName(tokenId);
            if (candidate.empty())
                continue;

            const uint32_t distance = editDistance(name, candidate);
            if (distance >= bestDistance)
                continue;

            bestDistance  = distance;
            bestCandidate = candidate;
        }

        if (!bestCandidate.has_value())
            return std::nullopt;

        // Keep suggestions conservative: a noisy "did you mean" is worse than no
        // suggestion when compiler directives and intrinsics are intentionally terse.
        const size_t candidateLen = std::max(name.size(), bestCandidate->size());
        const auto   maxDistance  = static_cast<uint32_t>(
            candidateLen <= 5
                ? 1
            : candidateLen <= 8
                ? 2
                : 3);

        if (bestDistance > maxDistance)
            return std::nullopt;

        return bestCandidate;
    }

    void skipBlanksRaw(const LangSpec& langSpec, const char8_t*& cursor)
    {
        while (langSpec.isBlank(cursor[0]))
            cursor++;
    }

    std::string_view readIdentifierRaw(const LangSpec& langSpec, const char8_t*& cursor)
    {
        const char8_t* start = cursor;
        while (langSpec.isIdentifierPart(cursor[0]))
            cursor++;

        auto   constPointer = reinterpret_cast<std::string_view::const_pointer>(start);
        size_t size         = static_cast<std::string_view::size_type>(cursor - start);
        return {constPointer, size};
    }

    std::string_view readCompilerWordRaw(const LangSpec& langSpec, const char8_t*& cursor)
    {
        if (cursor[0] != '#')
            return {};

        const char8_t* start = cursor;
        cursor++;
        while (langSpec.isIdentifierPart(cursor[0]))
            cursor++;

        auto   constPointer = reinterpret_cast<std::string_view::const_pointer>(start);
        size_t size         = static_cast<std::string_view::size_type>(cursor - start);
        return {constPointer, size};
    }

    bool consumeRaw(const std::string_view value, const char8_t*& cursor)
    {
        if (std::strncmp(reinterpret_cast<const char*>(cursor), value.data(), value.size()) != 0)
            return false;

        cursor += value.size();
        return true;
    }

    bool commandFromName(Runtime::CompilerCommand& out, const std::string_view name)
    {
        if (name == "Test")
        {
            out = Runtime::CompilerCommand::Test;
            return true;
        }

        if (name == "Format")
        {
            out = Runtime::CompilerCommand::Format;
            return true;
        }

        if (name == "Build")
        {
            out = Runtime::CompilerCommand::Build;
            return true;
        }

        return false;
    }

    GlobalIfValue evaluateRawGlobalIf(const LangSpec& langSpec, const CommandLine& cmdLine, const char8_t*& cursor)
    {
        if (readIdentifierRaw(langSpec, cursor) != "if")
            return GlobalIfValue::Unknown;

        // Only recognize the small, side-effect-free subset that can decide whether the
        // source view should be skipped before the full parser/sema pipeline runs.
        skipBlanksRaw(langSpec, cursor);

        const char8_t* exprCursor = cursor;
        const auto     boolValue  = readIdentifierRaw(langSpec, exprCursor);
        if (boolValue == "false")
            return GlobalIfValue::False;
        if (boolValue == "true")
            return GlobalIfValue::True;

        if (readCompilerWordRaw(langSpec, cursor) != "#command")
            return GlobalIfValue::Unknown;

        skipBlanksRaw(langSpec, cursor);

        bool notEqual = false;
        if (!consumeRaw("==", cursor))
        {
            if (!consumeRaw("!=", cursor))
                return GlobalIfValue::Unknown;

            notEqual = true;
        }

        skipBlanksRaw(langSpec, cursor);
        if (readIdentifierRaw(langSpec, cursor) != "Swag")
            return GlobalIfValue::Unknown;
        if (!consumeRaw(".", cursor))
            return GlobalIfValue::Unknown;
        if (readIdentifierRaw(langSpec, cursor) != "CompilerCommand")
            return GlobalIfValue::Unknown;
        if (!consumeRaw(".", cursor))
            return GlobalIfValue::Unknown;

        Runtime::CompilerCommand expected;
        if (!commandFromName(expected, readIdentifierRaw(langSpec, cursor)))
            return GlobalIfValue::Unknown;

        bool value = compilerCommandFromKind(cmdLine.command) == expected;
        if (notEqual)
            value = !value;

        return value ? GlobalIfValue::True : GlobalIfValue::False;
    }
}

bool Lexer::isTerminatorAfterEscapeChar(uint8_t c, TokenId container)
{
    // An unterminated escape must stop before its enclosing quote or line ending.
    if (container == TokenId::Character)
        return c == '\'' || c == '\n' || c == '\r';

    return c == '"' || c == '\n' || c == '\r';
}

void Lexer::raiseUtf8Error(DiagnosticId id, uint32_t offset, uint32_t len)
{
    if (hasUtf8Error_)
        return;

    hasUtf8Error_ = true;
    hasFileError_ = true;

    if (isRawMode())
        return;

    const Diagnostic diag = Diagnostic::get(id, srcView_->fileRef());
    diag.last().addSpan(srcView_, offset, len);
    diag.report(*ctx_);
}

Diagnostic Lexer::reportTokenError(DiagnosticId id, uint32_t offset, uint32_t len)
{
    if (hasTokenError_)
        return {};

    hasTokenError_ = true;
    hasFileError_  = true;

    if (isRawMode())
        return {};

    Diagnostic diag = Diagnostic::get(id, srcView_->fileRef());
    diag.last().addSpan(srcView_, offset, len);

    if (len)
    {
        const std::string_view tkn = srcView_->codeView(offset, len);
        diag.addArgument(Diagnostic::ARG_TOK, tkn);

        if (id == DiagnosticId::parser_err_invalid_compiler)
        {
            const auto suggestion = findClosestTokenName(tkn, true);
            if (suggestion.has_value())
                diag.addArgument(Diagnostic::ARG_VALUE, *suggestion);
        }
    }

    return diag;
}

void Lexer::raiseTokenError(DiagnosticId id, uint32_t offset, uint32_t len)
{
    const auto diag = reportTokenError(id, offset, len);
    diag.report(*ctx_);
}

void Lexer::eatUtf8Char()
{
    auto [buf, wc, eat] = Utf8Helper::decodeOneChar(buffer_, endBuffer_);
    if (!buf)
    {
        raiseTokenError(DiagnosticId::lex_err_not_utf8, static_cast<uint32_t>(buffer_ - startBuffer_));

        hasUtf8Error_  = true;
        hasTokenError_ = true;

        buffer_++;
    }
    else
    {
        buffer_ = buf;
    }
}

// Consume exactly one logical EOL (CRLF | CR | LF). Push the next line start.
void Lexer::eatOneEol()
{
    if (buffer_[0] == '\r')
    {
        if (buffer_[1] == '\n')
            buffer_ += 2;
        else
            buffer_++;
    }
    else
    {
        SWC_ASSERT(buffer_[0] == '\n');
        buffer_++;
    }

    token_.flags.add(TokenFlagsE::EolInside);
    srcView_->lines().push_back(static_cast<uint32_t>(buffer_ - startBuffer_));
}

void Lexer::eatOne()
{
    if (langSpec_->isEol(buffer_[0]))
        eatOneEol();
    else
        buffer_++;
}

void Lexer::pushToken()
{
    token_.byteLength = static_cast<uint32_t>(buffer_ - startToken_);

    const TokenId tokenId      = token_.id;
    const bool    isTrivia     = Token::isTrivia(tokenId);
    const bool    hasEolInside = token_.hasFlag(TokenFlagsE::EolInside);

    // Trivia still supplies spacing and line-boundary flags to adjacent tokens.
    if (!srcView_->tokens().empty())
    {
        auto& back = srcView_->tokens().back();
        if (tokenId == TokenId::Whitespace)
            back.flags.add(TokenFlagsE::BlankAfter);
        if (hasEolInside)
            back.flags.add(TokenFlagsE::EolAfter);
    }

    if (prevTokenWasWhitespace_)
        token_.flags.add(TokenFlagsE::BlankBefore);
    if (prevTokenHadEolInside_)
        token_.flags.add(TokenFlagsE::EolBefore);

    // Always update the previous-token facts, even for filtered tokens.
    prevTokenWasWhitespace_ = tokenId == TokenId::Whitespace;
    prevTokenHadEolInside_  = hasEolInside;

    if (!isTrivia)
        prevCodeTokenId_ = tokenId;
    else if (hasEolInside)
        prevCodeTokenId_ = TokenId::Invalid;

    // '#raw' arms the next string literal. Trivia between the modifier and the literal is
    // transparent, so a comment or a blank does not disarm it.
    if (tokenId == TokenId::ModifierRaw)
        pendingRawStringLiteral_ = true;
    else if (!isTrivia)
        pendingRawStringLiteral_ = false;

    switch (tokenId)
    {
        case TokenId::Whitespace:
            if (lexerFlags_.has(LexerFlagsE::EmitTrivia))
                srcView_->trivia().push_back({.tokRef = TokenRef{srcView_->numTokens()}, .tok = token_});
            break;

        case TokenId::CommentLine:
        case TokenId::CommentBlock:
            if (!isRawMode() && lexerFlags_.hasNot(LexerFlagsE::EmitTrivia))
                break;

            srcView_->trivia().push_back({.tokRef = TokenRef{srcView_->numTokens()}, .tok = token_});
            break;

        default:
            if (isRawMode())
                break;

            srcView_->tokens().push_back(token_);
            break;
    }
}

void Lexer::lexEscape(TokenId containerToken, bool eatEol)
{
    // Only multiline strings allow an escaped line ending.
    if (eatEol)
    {
        if (buffer_[1] == '\r' || buffer_[1] == '\n')
        {
            buffer_++;
            eatOneEol();
            return;
        }
    }

    if (!langSpec_->isEscape(buffer_[1]))
    {
        auto          diag = reportTokenError(DiagnosticId::lex_err_invalid_escape, static_cast<uint32_t>(buffer_ - startBuffer_), 2);
        const uint8_t c    = buffer_[1];
        if (c >= 'A' && c <= 'Z')
        {
            const uint8_t lower = c + 32;
            if (langSpec_->isEscape(lower) && lower != 'x' && lower != 'u')
            {
                const char suggestion[2] = {'\\', static_cast<char>(lower)};
                diag.addArgument(Diagnostic::ARG_VALUE, std::string_view(suggestion, 2));
            }
        }

        diag.report(*ctx_);
    }

    // buffer_ still points to the backslash.
    if (buffer_[1] != 'x' && buffer_[1] != 'u' && buffer_[1] != 'U')
    {
        buffer_++;
        eatOne();
        return;
    }

    const uint8_t escapeType     = buffer_[1];
    uint32_t      expectedDigits = 0;

    switch (escapeType)
    {
        case 'x':
            expectedDigits = 2;
            break;

        case 'u':
            expectedDigits = 4;
            break;

        case 'U':
            expectedDigits = 8;
            break;

        default:
            SWC_UNREACHABLE();
    }

    for (uint32_t i = 0; i < expectedDigits; i++)
    {
        if (!langSpec_->isHexNumber(buffer_[2 + i]))
        {
            const uint32_t actualDigits = i;
            const auto     offset       = static_cast<uint32_t>(buffer_ - startBuffer_);

            if (actualDigits == 0)
            {
                const uint8_t first = buffer_[2];
                if (isTerminatorAfterEscapeChar(first, containerToken))
                    raiseTokenError(DiagnosticId::lex_err_empty_hex_escape, offset, 2);
                else
                    raiseTokenError(DiagnosticId::lex_err_invalid_hex_digit, offset + 2);
            }
            else
            {
                auto diag = reportTokenError(DiagnosticId::lex_err_incomplete_hex_escape, offset, 2 + actualDigits);
                diag.addArgument(Diagnostic::ARG_VALUE, expectedDigits);
                diag.report(*ctx_);
            }

            buffer_ += 2 + actualDigits;
            return;
        }
    }

    buffer_ += 2 + expectedDigits;
}

void Lexer::lexWhitespace()
{
    token_.id = TokenId::Whitespace;

    eatOne();
    while (langSpec_->isWhiteSpace(buffer_[0]))
        eatOne();

    pushToken();
}

void Lexer::lexSingleLineStringLiteral()
{
    token_.id = TokenId::StringLine;

    const bool raw = pendingRawStringLiteral_;
    if (raw)
        token_.flags.add(TokenFlagsE::Raw);

    buffer_++;

    // Padding keeps the terminator checks valid when the scan reaches EOF.
    while (buffer_ < endBuffer_ && buffer_[0] != '"' && buffer_[0] != '\n' && buffer_[0] != '\r')
    {
        if (buffer_[0] == '\0')
        {
            raiseTokenError(DiagnosticId::lex_err_not_utf8, static_cast<uint32_t>(buffer_ - startBuffer_));
            buffer_++;
            continue;
        }

        // Raw backslashes are literal and cannot hide the closing quote.
        if (buffer_[0] == '\\' && !raw)
        {
            token_.flags.add(TokenFlagsE::Escaped);
            lexEscape(TokenId::StringLine, false);
            continue;
        }

        buffer_++;
    }

    if (buffer_[0] == '\n' || buffer_[0] == '\r')
    {
        const auto diag = reportTokenError(DiagnosticId::lex_err_string_eol, static_cast<uint32_t>(buffer_ - startBuffer_));
        if (!diag.elements().empty())
            diag.last().addSpan(srcView_, startTokenOffset_, 1, DiagnosticSeverity::Note, "unterminated string starts here");

        diag.report(*ctx_);
    }

    if (buffer_ >= endBuffer_)
        raiseTokenError(DiagnosticId::lex_err_unclosed_string, startTokenOffset_);

    if (buffer_[0] == '"')
        buffer_++;

    pushToken();
}

void Lexer::lexMultiLineStringLiteral()
{
    token_.id = TokenId::StringMultiLine;

    const bool raw = pendingRawStringLiteral_;
    if (raw)
        token_.flags.add(TokenFlagsE::Raw);

    buffer_ += 3;

    while (buffer_ < endBuffer_)
    {
        if (buffer_[0] == '\0')
        {
            raiseUtf8Error(DiagnosticId::lex_err_not_utf8, static_cast<uint32_t>(buffer_ - startBuffer_));
            buffer_++;
            continue;
        }

        // Record line starts for later diagnostics.
        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            eatOneEol();
            continue;
        }

        // Escaped char. A raw literal takes the backslash verbatim.
        if (buffer_[0] == '\\' && !raw)
        {
            token_.flags.add(TokenFlagsE::Escaped);
            lexEscape(TokenId::StringMultiLine, true);
            continue;
        }

        // Padding permits the two-byte lookahead at the closing delimiter.
        if (buffer_[0] == '"' && buffer_[1] == '"' && buffer_[2] == '"')
        {
            buffer_ += 3;
            token_.byteLength = static_cast<uint32_t>(buffer_ - startToken_);
            pushToken();
            return;
        }

        buffer_++;
    }

    raiseTokenError(DiagnosticId::lex_err_unclosed_string, startTokenOffset_, 3);

    pushToken();
}

void Lexer::lexCharacterLiteral()
{
    token_.id = TokenId::Character;
    buffer_++;

    if (buffer_[0] == '\'')
    {
        raiseTokenError(DiagnosticId::lex_err_empty_char, startTokenOffset_, 2);
        buffer_++;
        pushToken();
        return;
    }

    uint32_t charCount = 0;

    while (buffer_ < endBuffer_ && buffer_[0] != '\'')
    {
        if (buffer_[0] == '\0')
        {
            raiseUtf8Error(DiagnosticId::lex_err_not_utf8, static_cast<uint32_t>(buffer_ - startBuffer_));
            buffer_++;
            continue;
        }

        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            raiseTokenError(DiagnosticId::lex_err_unclosed_char, startTokenOffset_, static_cast<uint32_t>(buffer_ - startToken_));
            pushToken();
            eatOneEol();
            return;
        }

        if (buffer_[0] == '\\')
        {
            token_.flags.add(TokenFlagsE::Escaped);
            lexEscape(TokenId::Character, false);
        }
        else
            eatUtf8Char();

        charCount++;
    }

    if (buffer_ >= endBuffer_)
        raiseTokenError(DiagnosticId::lex_err_unclosed_char, startTokenOffset_, static_cast<uint32_t>(buffer_ - startToken_));

    if (buffer_[0] == '\'')
        buffer_++;

    if (charCount > 1)
    {
        auto diag = reportTokenError(DiagnosticId::lex_err_too_many_char_char, startTokenOffset_, static_cast<uint32_t>(buffer_ - startToken_));
        diag.addArgument(Diagnostic::ARG_VALUE, charCount);
        diag.report(*ctx_);
    }

    pushToken();
}

// Count digits while accepting separators and reporting doubled separators.
// Padded zero bytes stop the scan; ioLastWasSep preserves the trailing state.
template<bool (LangSpec::*IsDigit)(uint32_t) const>
uint32_t Lexer::lexDigitRun(bool& ioLastWasSep)
{
    const char8_t* sepStart = nullptr;
    uint32_t       digits   = 0;

    while (true)
    {
        // All digit classes exclude the numeric separator.
        if ((langSpec_->*IsDigit)(buffer_[0]))
        {
            digits++;
            ioLastWasSep = false;
            buffer_++;
            continue;
        }

        if (!langSpec_->isNumberSep(buffer_[0]))
            break;

        if (ioLastWasSep)
        {
            while (langSpec_->isNumberSep(buffer_[0]))
                buffer_++;

            raiseTokenError(DiagnosticId::lex_err_consecutive_num_sep, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
            continue;
        }

        sepStart     = buffer_;
        ioLastWasSep = true;
        buffer_++;
    }

    return digits;
}

void Lexer::lexHexNumber()
{
    token_.id = TokenId::NumberHex;
    buffer_ += 2;

    bool           lastWasSep = false;
    const uint32_t digits     = lexDigitRun<&LangSpec::isHexNumber>(lastWasSep);

    if (digits == 0)
        raiseTokenError(DiagnosticId::lex_err_missing_hex_digit, startTokenOffset_, 2 + (lastWasSep ? 1 : 0));

    if (lastWasSep)
        raiseTokenError(DiagnosticId::lex_err_trailing_num_sep, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

    if (langSpec_->isLetter(buffer_[0]))
        raiseTokenError(DiagnosticId::lex_err_invalid_hex_digit, static_cast<uint32_t>(buffer_ - startBuffer_), 1);

    pushToken();
}

void Lexer::lexBinNumber()
{
    token_.id = TokenId::NumberBin;
    buffer_ += 2;

    bool           lastWasSep = false;
    const uint32_t digits     = lexDigitRun<&LangSpec::isBinNumber>(lastWasSep);

    if (digits == 0)
        raiseTokenError(DiagnosticId::lex_err_missing_bin_digit, startTokenOffset_, 2 + (lastWasSep ? 1 : 0));

    if (lastWasSep)
        raiseTokenError(DiagnosticId::lex_err_trailing_num_sep, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

    if (langSpec_->isLetter(buffer_[0]) ||
        (langSpec_->isDigit(buffer_[0]) && !langSpec_->isBinNumber(buffer_[0])))
        raiseTokenError(DiagnosticId::lex_err_invalid_bin_digit, static_cast<uint32_t>(buffer_ - startBuffer_), 1);

    pushToken();
}

void Lexer::lexDecimalNumber()
{
    token_.id = TokenId::NumberInteger;

    bool lastWasSep = false;
    bool hasDot     = false;
    bool hasExp     = false;

    // Parse integer part
    lexDigitRun<&LangSpec::isDigit>(lastWasSep);

    // Check for trailing separator before the decimal point
    if (lastWasSep)
        raiseTokenError(DiagnosticId::lex_err_trailing_num_sep, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

    // Parse decimal part
    if (buffer_[0] == '.')
    {
        hasDot = true;
        buffer_++;
        lastWasSep = false;

        if (langSpec_->isNumberSep(buffer_[0]))
            raiseTokenError(DiagnosticId::lex_err_leading_num_sep, static_cast<uint32_t>(buffer_ - startBuffer_));

        lexDigitRun<&LangSpec::isDigit>(lastWasSep);

        if (hasDot)
            token_.id = TokenId::NumberFloat;
    }

    if (lastWasSep)
        raiseTokenError(DiagnosticId::lex_err_trailing_num_sep, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

    // Parse exponent part
    if (buffer_[0] == 'e' || buffer_[0] == 'E')
    {
        hasExp = true;
        buffer_++;

        if (buffer_[0] == '+' || buffer_[0] == '-')
            buffer_++;

        if (langSpec_->isNumberSep(buffer_[0]))
            raiseTokenError(DiagnosticId::lex_err_leading_num_sep, static_cast<uint32_t>(buffer_ - startBuffer_));

        lastWasSep = false;

        const uint32_t expDigits = lexDigitRun<&LangSpec::isDigit>(lastWasSep);

        if (expDigits == 0)
            raiseTokenError(DiagnosticId::lex_err_missing_exponent, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

        if (hasExp)
            token_.id = TokenId::NumberFloat;
    }

    if (lastWasSep)
        raiseTokenError(DiagnosticId::lex_err_trailing_num_sep, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

    pushToken();
}

void Lexer::lexNumber()
{
    // Padding permits one-byte lookahead when selecting the numeric base.
    if (buffer_[0] == '0' && (buffer_[1] == 'x' || buffer_[1] == 'X'))
        lexHexNumber();
    else if (buffer_[0] == '0' && (buffer_[1] == 'b' || buffer_[1] == 'B'))
        lexBinNumber();
    else
        lexDecimalNumber();

    // Report the entire invalid suffix, rather than just its first letter.
    if (langSpec_->isLetter(buffer_[0]))
    {
        const uint32_t suffixOffset = static_cast<uint32_t>(buffer_ - startBuffer_);
        const char8_t* suffixStart  = buffer_;
        const char8_t* suffixEnd    = suffixStart;
        while (langSpec_->isIdentifierPart(suffixEnd[0]))
            suffixEnd++;

        raiseTokenError(DiagnosticId::lex_err_invalid_number_suffix, suffixOffset, static_cast<uint32_t>(suffixEnd - suffixStart));
    }
}

void Lexer::checkGlobalCompilerIfSkip() const
{
    if (token_.id != TokenId::CompilerGlobal || lexerFlags_.has(LexerFlagsE::IgnoreGlobalCompilerIfSkip))
        return;

    // Inspect with a separate cursor: diagnostics and modes that ignore skipping
    // still require the current bytes to be tokenized.
    const char8_t* cursor = buffer_;
    skipBlanksRaw(*langSpec_, cursor);

    if (evaluateRawGlobalIf(*langSpec_, ctx_->cmdLine(), cursor) == GlobalIfValue::False)
        srcView_->setMustSkip();
}

void Lexer::lexIdentifier()
{
    buffer_++;
    while (langSpec_->isIdentifierPart(buffer_[0]))
        buffer_++;

    const auto name = std::string_view(reinterpret_cast<std::string_view::const_pointer>(startToken_), buffer_ - startToken_);
    if (name[0] == '#' && name.length() > 1 && name[1] >= 'A' && name[1] <= 'Z')
        token_.id = TokenId::SharpIdentifier;
    else if (isRawMode())
        token_.id = TokenId::Identifier;
    else
    {
        const uint32_t hash32 = Math::hash(name);

        token_.id = langSpec_->keyword(name, hash32);
        if (token_.id == TokenId::Identifier)
        {
            if (name[0] == '#')
                raiseTokenError(DiagnosticId::parser_err_invalid_compiler, startTokenOffset_, static_cast<uint32_t>(name.size()));
            else if (!srcView_->isRuntimeFile() && !lexerFlags_.has(LexerFlagsE::AllowReservedIdentifiers) &&
                     name.size() >= 2 && name[0] == '_' && name[1] == '_')
                raiseTokenError(DiagnosticId::lex_err_reserved_identifier, startTokenOffset_, static_cast<uint32_t>(name.size()));

            // Identifier tokens store an index; the table keeps their source offset.
            const auto idx = static_cast<uint32_t>(srcView_->identifiers().size());
            srcView_->identifiers().push_back({.crc = hash32, .byteStart = token_.byteStart});
            token_.byteStart = idx;
        }
        else
        {
            // Only a keyword can be '#global'.
            checkGlobalCompilerIfSkip();
        }
    }

    pushToken();
}

bool Lexer::canPrecedeQuoteOperator() const
{
    switch (prevCodeTokenId_)
    {
        case TokenId::Identifier:
        case TokenId::NumberHex:
        case TokenId::NumberBin:
        case TokenId::NumberInteger:
        case TokenId::NumberFloat:
        case TokenId::StringLine:
        case TokenId::StringMultiLine:
            return true;

        default:
            return false;
    }
}

void Lexer::lexSymbol()
{
    // Safe to read buffer_[1] and buffer_[2] due to padding after endBuffer_
    const uint8_t c = buffer_[0];

    switch (c)
    {
        case '\'':
            token_.id = TokenId::SymSingleQuote;
            buffer_++;
            break;

        case '\\':
            token_.id = TokenId::SymBackSlash;
            buffer_++;
            break;

        case '(':
            token_.id = TokenId::SymLeftParen;
            buffer_++;
            break;

        case ')':
            token_.id = TokenId::SymRightParen;
            buffer_++;
            break;

        case '[':
            token_.id = TokenId::SymLeftBracket;
            buffer_++;
            break;

        case ']':
            token_.id = TokenId::SymRightBracket;
            buffer_++;
            break;

        case '{':
            token_.id = TokenId::SymLeftCurly;
            buffer_++;
            break;

        case '}':
            token_.id = TokenId::SymRightCurly;
            buffer_++;
            break;

        case ';':
            token_.id = TokenId::SymSemiColon;
            buffer_++;
            break;

        case ',':
            token_.id = TokenId::SymComma;
            buffer_++;
            break;

        case '@':
            token_.id = TokenId::SymAt;
            buffer_++;
            break;

        case '?':
            if (buffer_[1] == '.')
            {
                token_.id = TokenId::SymQuestionDot;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::SymQuestion;
                buffer_++;
            }
            break;

        case '~':
            token_.id = TokenId::SymTilde;
            buffer_++;
            break;

        case '=':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::SymEqualEqual;
                buffer_ += 2;
            }
            else if (buffer_[1] == '>')
            {
                token_.id = TokenId::SymEqualGreater;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::SymEqual;
                buffer_++;
            }
            break;

        case ':':
            token_.id = TokenId::SymColon;
            buffer_++;
            break;

        case '!':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::SymBangEqual;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::SymBang;
                buffer_++;
            }
            break;

        case '-':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::SymMinusEqual;
                buffer_ += 2;
            }
            else if (buffer_[1] == '>')
            {
                token_.id = TokenId::SymMinusGreater;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::SymMinus;
                buffer_++;
            }
            break;

        case '+':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::SymPlusEqual;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::SymPlus;
                buffer_++;
            }
            break;

        case '*':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::SymAsteriskEqual;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::SymAsterisk;
                buffer_++;
            }
            break;

        case '/':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::SymSlashEqual;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::SymSlash;
                buffer_++;
            }
            break;

        case '&':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::SymAmpersandEqual;
                buffer_ += 2;
            }
            else if (buffer_[1] == '&')
            {
                token_.id = TokenId::SymAmpersandAmpersand;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::SymAmpersand;
                buffer_++;
            }
            break;

        case '|':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::SymPipeEqual;
                buffer_ += 2;
            }
            else if (buffer_[1] == '|')
            {
                token_.id = TokenId::SymPipePipe;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::SymPipe;
                buffer_++;
            }
            break;

        case '^':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::SymCircumflexEqual;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::SymCircumflex;
                buffer_++;
            }
            break;

        case '%':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::SymPercentEqual;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::SymPercent;
                buffer_++;
            }
            break;

        case '.':
            if (buffer_[1] == '.')
            {
                if (buffer_[2] == '.')
                {
                    token_.id = TokenId::SymDotDotDot;
                    buffer_ += 3;
                }
                else
                {
                    token_.id = TokenId::SymDotDot;
                    buffer_ += 2;
                }
            }
            else
            {
                token_.id = TokenId::SymDot;
                buffer_++;
            }
            break;

        case '<':
            if (buffer_[1] == '=')
            {
                if (buffer_[2] == '>')
                {
                    token_.id = TokenId::SymLessEqualGreater;
                    buffer_ += 3;
                }
                else
                {
                    token_.id = TokenId::SymLessEqual;
                    buffer_ += 2;
                }
            }
            else if (buffer_[1] == '<')
            {
                if (buffer_[2] == '=')
                {
                    token_.id = TokenId::SymLowerLowerEqual;
                    buffer_ += 3;
                }
                else
                {
                    token_.id = TokenId::SymLowerLower;
                    buffer_ += 2;
                }
            }
            else
            {
                token_.id = TokenId::SymLess;
                buffer_++;
            }
            break;

        case '>':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::SymGreaterEqual;
                buffer_ += 2;
            }
            else if (buffer_[1] == '>')
            {
                if (buffer_[2] == '=')
                {
                    token_.id = TokenId::SymGreaterGreaterEqual;
                    buffer_ += 3;
                }
                else
                {
                    token_.id = TokenId::SymGreaterGreater;
                    buffer_ += 2;
                }
            }
            else
            {
                token_.id = TokenId::SymGreater;
                buffer_++;
            }
            break;

        default:
        {
            auto [buf, wc, eat] = Utf8Helper::decodeOneChar(buffer_, endBuffer_);
            if (buf)
                buffer_ = buf;
            else
            {
                raiseTokenError(DiagnosticId::lex_err_not_utf8, static_cast<uint32_t>(buffer_ - startBuffer_));

                hasUtf8Error_  = true;
                hasTokenError_ = true;

                buffer_++;
                break;
            }

            const uint32_t tokenLen = static_cast<uint32_t>(buffer_ - startToken_);

            auto diag = reportTokenError(DiagnosticId::lex_err_invalid_char, startTokenOffset_, tokenLen);
            diag.addArgument(Diagnostic::ARG_VALUE, std::format("{:04X}", static_cast<uint32_t>(wc)));
            diag.report(*ctx_);
        }
        break;
    }

    pushToken();
}

void Lexer::lexSingleLineComment()
{
    token_.id = TokenId::CommentLine;
    buffer_ += 2;

    // Leave the line ending for the following whitespace token.
    while (buffer_ < endBuffer_ && buffer_[0] != '\n' && buffer_[0] != '\r')
        buffer_++;

    pushToken();
}

void Lexer::lexMultiLineComment()
{
    token_.id = TokenId::CommentBlock;
    buffer_ += 2;

    uint32_t depth = 1;

    while (buffer_ < endBuffer_ && depth > 0)
    {
        if (buffer_[0] == '\0')
        {
            raiseUtf8Error(DiagnosticId::lex_err_not_utf8, static_cast<uint32_t>(buffer_ - startBuffer_));
            buffer_++;
            continue;
        }

        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            eatOneEol();
            continue;
        }

        // Safe to check buffer_[1] due to padding after endBuffer_
        if (buffer_[0] == '/' && buffer_[1] == '*')
        {
            depth++;
            buffer_ += 2;
            continue;
        }

        if (buffer_[0] == '*' && buffer_[1] == '/')
        {
            depth--;
            buffer_ += 2;
            continue;
        }

        buffer_++;
    }

    if (depth > 0)
        raiseTokenError(DiagnosticId::lex_err_unclosed_comment, startTokenOffset_, 2);

    pushToken();
}

void Lexer::checkFormat(uint32_t& startOffset)
{
    static constexpr char8_t UTF8[]     = {0xEF, 0xBB, 0xBF};
    static constexpr char8_t UTF16_BE[] = {0xFE, 0xFF};
    static constexpr char8_t UTF16_LE[] = {0xFF, 0xFE};
    static constexpr char8_t UTF32_BE[] = {0x00, 0x00, 0xFE, 0xFF};
    static constexpr char8_t UTF32_LE[] = {0xFF, 0xFE, 0x00, 0x00};

    const std::string_view content = srcView_->stringView();

    if (content.size() < 3)
    {
        startOffset = 0;
        return;
    }

    const auto* data = reinterpret_cast<const char8_t*>(content.data());

    // UTF-8 BOM
    if (content.size() >= 3 &&
        data[0] == UTF8[0] && data[1] == UTF8[1] && data[2] == UTF8[2])
    {
        startOffset = 3;
        return;
    }

    bool badFormat = false;

    // UTF-16 BOMs (2 bytes)
    if (content.size() >= 2)
    {
        if ((data[0] == UTF16_BE[0] && data[1] == UTF16_BE[1]) ||
            (data[0] == UTF16_LE[0] && data[1] == UTF16_LE[1]))
        {
            startOffset = 2;
            badFormat   = true;
        }
    }

    // 3-byte BOMs
    if (!badFormat && content.size() >= 3)
    {
        if ((data[0] == 0x0E && data[1] == 0xFE && data[2] == 0xFF) || // SCSU
            (data[0] == 0xFB && data[1] == 0xEE && data[2] == 0x28) || // BOCU-1
            (data[0] == 0xF7 && data[1] == 0x64 && data[2] == 0x4C))   // UTF-1
        {
            startOffset = 3;
            badFormat   = true;
        }
    }

    // 4-byte BOMs
    if (!badFormat && content.size() >= 4)
    {
        if ((data[0] == UTF32_BE[0] && data[1] == UTF32_BE[1] && data[2] == UTF32_BE[2] && data[3] == UTF32_BE[3]) ||
            (data[0] == UTF32_LE[0] && data[1] == UTF32_LE[1] && data[2] == UTF32_LE[2] && data[3] == UTF32_LE[3]) ||
            // UTF-7
            (data[0] == 0x2B && data[1] == 0x2F && data[2] == 0x76 && (data[3] == 0x38 || data[3] == 0x39 || data[3] == 0x2B || data[3] == 0x2F)) ||
            // UTF-EBCDIC
            (data[0] == 0xDD && data[1] == 0x73 && data[2] == 0x66 && data[3] == 0x73) ||
            // GB-18030
            (data[0] == 0x84 && data[1] == 0x31 && data[2] == 0x95 && data[3] == 0x33))
        {
            startOffset = 4;
            badFormat   = true;
        }
    }

    if (badFormat)
    {
        raiseUtf8Error(DiagnosticId::lex_err_not_utf8, 0, 0);
        return;
    }

    startOffset = 0;
}

void Lexer::tokenizeRaw(TaskContext& ctx, SourceView& srcView)
{
    tokenize(ctx, srcView, LexerFlagsE::RawMode);
}

void Lexer::tokenize(TaskContext& ctx, SourceView& srcView, LexerFlags flags)
{
    srcView_ = &srcView;
    srcView_->tokens().clear();
    srcView_->lines().clear();
    srcView_->lines().push_back(0);

    prevTokenWasWhitespace_ = false;
    prevTokenHadEolInside_  = false;
    prevCodeTokenId_        = TokenId::Invalid;

    hasFileError_ = false;
    hasUtf8Error_ = false;

    langSpec_   = &ctx.global().langSpec();
    ctx_        = &ctx;
    lexerFlags_ = flags;

    uint32_t startOffset = 0;
    checkFormat(startOffset);
    srcView_->setSourceStartOffset(startOffset);

    const auto* base = reinterpret_cast<const char8_t*>(srcView.stringView().data());

    buffer_      = base + startOffset;
    startBuffer_ = base;
    endBuffer_   = startBuffer_ + srcView.stringView().size();

    srcView_->tokens().reserve(srcView.stringView().size() / 10);
    if (!isRawMode())
        srcView_->lines().reserve(srcView.stringView().size() / 60);

    // Padded source storage permits two-byte lookahead throughout dispatch.
    while (buffer_ < endBuffer_)
    {
        // Every branch must advance buffer_ or finish lexing so recovery cannot
        // retry the same invalid input indefinitely.
        hasTokenError_    = false;
        startToken_       = buffer_;
        startTokenOffset_ = static_cast<uint32_t>(startToken_ - startBuffer_);
        token_.byteStart  = startTokenOffset_;
        token_.flags      = TokenFlagsE::Zero;

#if SWC_HAS_TOKEN_DEBUG_INFO
        token_.dbgPtr     = startToken_;
        token_.dbgSrcView = &srcView;
        token_.dbgLoc.fromOffset(ctx, srcView, token_.byteStart);
#endif

        if (buffer_[0] == '\0')
        {
            raiseUtf8Error(DiagnosticId::lex_err_not_utf8, static_cast<uint32_t>(buffer_ - startBuffer_));
            hasTokenError_ = true;
            buffer_++;
            continue;
        }

        if (langSpec_->isWhiteSpace(buffer_[0]))
        {
            lexWhitespace();
            continue;
        }

        if (langSpec_->isDigit(buffer_[0]))
        {
            lexNumber();
            continue;
        }

        if (buffer_[0] == '#' && buffer_[1] == '[')
        {
            token_.id = TokenId::SymAttrStart;
            buffer_ += 2;
            pushToken();
            continue;
        }

        if (buffer_[0] == '"' && buffer_[1] == '"' && buffer_[2] == '"')
        {
            lexMultiLineStringLiteral();
            continue;
        }

        if (buffer_[0] == '"')
        {
            lexSingleLineStringLiteral();
            continue;
        }

        if (buffer_[0] == '/' && buffer_[1] == '/')
        {
            lexSingleLineComment();
            continue;
        }

        if (buffer_[0] == '/' && buffer_[1] == '*')
        {
            lexMultiLineComment();
            continue;
        }

        if (langSpec_->isIdentifierStart(buffer_[0]))
        {
            lexIdentifier();
            if (srcView_->mustSkip())
                return;

            continue;
        }

        // After a token that can carry a suffix or generic arguments on this line,
        // ' is a quote operator; otherwise it opens a character literal. Trivia does
        // not change the meaning of 5's32 versus 5 's32.
        if (buffer_[0] == '\'')
        {
            if (!canPrecedeQuoteOperator())
            {
                lexCharacterLiteral();
                continue;
            }
        }

        lexSymbol();
    }

    // End marker
    token_.id        = TokenId::EndOfFile;
    startToken_      = buffer_++;
    token_.byteStart = static_cast<uint32_t>(startToken_ - startBuffer_);
    pushToken();

    if (lexerFlags_.has(LexerFlagsE::EmitTrivia))
        buildTriviaIndex();

    if (!isRawMode() && hasFileError_)
        srcView_->setLexOnly();

    if (!isRawMode())
        Stats::get().numTokens.fetch_add(srcView_->tokens().size(), std::memory_order_relaxed);
}

void Lexer::buildTriviaIndex() const
{
    const uint32_t numTok      = srcView_->numTokens();
    auto&          triviaStart = srcView_->triviaStart();
    triviaStart.resize(numTok + 1);

    // trivia_ is in lex order and tokRef is monotonic, so a single cursor builds
    // the compact token -> trivia slice table without per-token searches.
    uint32_t tIdx = 0;

    for (uint32_t tokIdx = 0; tokIdx < numTok; ++tokIdx)
    {
        triviaStart[tokIdx] = tIdx;
        while (tIdx < srcView_->trivia().size() && srcView_->trivia()[tIdx].tokRef.get() == tokIdx)
            ++tIdx;
    }

    triviaStart[numTok] = tIdx;
}

SWC_END_NAMESPACE();
