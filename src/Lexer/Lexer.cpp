#include "pch.h"

#include "LangSpec.h"
#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/Reporter.h"

void Lexer::pushToken()
{
    if (!lexerFlags_.has(LEXER_EXTRACT_COMMENTS_MODE) || token_.id == TokenId::Comment)
        tokens_.push_back(token_);
}

void Lexer::reportError(const Diagnostic& diag) const
{
    if (lexerFlags_.has(LEXER_EXTRACT_COMMENTS_MODE))
        return;
    (void) diag.report(*ci_);
}

// Consume exactly one logical EOL (CRLF | CR | LF). Push the next line start.
void Lexer::consumeOneEol()
{
    SWAG_ASSERT(buffer_ < end_);

    if (buffer_[0] == '\r')
    {
        if (buffer_ + 1 < end_ && buffer_[1] == '\n')
            buffer_ += 2;
        else
            buffer_ += 1;
    }
    else
    {
        SWAG_ASSERT(buffer_[0] == '\n');
        buffer_ += 1;
    }

    lines_.push_back(static_cast<uint32_t>(buffer_ - startBuffer_));
}

void Lexer::parseEol()
{
    token_.id                 = TokenId::Eol;
    const uint8_t* startToken = buffer_;

    // Consume the first logical EOL.
    consumeOneEol();

    // Collapse subsequent EOLs (any mix of CR/LF/CRLF).
    while (buffer_ < end_ && (buffer_[0] == '\r' || buffer_[0] == '\n'))
        consumeOneEol();

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseBlank()
{
    token_.id                 = TokenId::Blank;
    const uint8_t* startToken = buffer_;

    buffer_++;

    while (buffer_ < end_ && langSpec_->isBlank(buffer_[0]))
        buffer_++;

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseSingleLineStringLiteral()
{
    token_.id                 = TokenId::StringLiteral;
    token_.subTokenStringId   = SubTokenStringId::Line;
    const uint8_t* startToken = buffer_;

    buffer_ += 1;

    while (buffer_ < end_)
    {
        if (buffer_[0] == '"')
            break;

        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            consumeOneEol();
            Diagnostic diag(ctx_->sourceFile());
            const auto elem = diag.addError(DiagnosticId::EolInStringLiteral);
            elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(buffer_ - startBuffer_ - 1));
            reportError(diag);
        }

        // Escaped char
        if (buffer_[0] == '\\')
        {
            // Need one more char to escape
            if (buffer_ + 1 >= end_)
            {
                Diagnostic diag(ctx_->sourceFile());
                const auto elem = diag.addError(DiagnosticId::UnclosedStringLiteral);
                elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_));
                reportError(diag);
            }

            buffer_ += 2; // skip '\' and escaped char
            continue;
        }

        buffer_ += 1;
    }

    if (buffer_ == end_)
    {
        Diagnostic diag(ctx_->sourceFile());
        const auto elem = diag.addError(DiagnosticId::UnclosedStringLiteral);
        elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_));
        reportError(diag);
    }

    buffer_ += 1;
    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseMultiLineStringLiteral()
{
    token_.id                 = TokenId::StringLiteral;
    token_.subTokenStringId   = SubTokenStringId::MultiLine;
    const uint8_t* startToken = buffer_;

    buffer_ += 3;

    while (buffer_ < end_)
    {
        // Track line starts for accurate diagnostics later
        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            consumeOneEol();
            continue;
        }

        // Escaped char
        if (buffer_[0] == '\\')
        {
            // Need one more char to escape
            if (buffer_ + 1 >= end_)
            {
                Diagnostic diag(ctx_->sourceFile());
                const auto elem = diag.addError(DiagnosticId::UnclosedStringLiteral);
                elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_));
                reportError(diag);
            }

            buffer_ += 2; // skip '\' and escaped char
            continue;
        }

        // Closing delimiter
        if (buffer_ + 2 < end_ && buffer_[0] == '"' && buffer_[1] == '"' && buffer_[2] == '"')
        {
            buffer_ += 3;
            token_.len = static_cast<uint32_t>(buffer_ - startToken);
            pushToken();
            return;
        }

        buffer_++;
    }

    // EOF before closing delimiter
    Diagnostic diag(ctx_->sourceFile());
    const auto elem = diag.addError(DiagnosticId::UnclosedStringLiteral);
    elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_), 3);
    reportError(diag);
}

void Lexer::parseRawStringLiteral()
{
    token_.id                 = TokenId::StringLiteral;
    token_.subTokenStringId   = SubTokenStringId::Raw;
    const uint8_t* startToken = buffer_;

    buffer_ += 2;

    while (buffer_ < end_ - 1 && (buffer_[0] != '"' || buffer_[1] != '#'))
    {
        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            consumeOneEol();
            continue;
        }

        buffer_++;
    }

    if (buffer_ + 1 >= end_)
    {
        Diagnostic diag(ctx_->sourceFile());
        const auto elem = diag.addError(DiagnosticId::UnclosedStringLiteral);
        elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_), 2);
        reportError(diag);
    }

    // Consume closing "#"
    buffer_ += 2;
    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseHexNumber()
{
    token_.subTokenNumberId   = SubTokenNumberId::Hexadecimal;
    const uint8_t* startToken = buffer_;

    buffer_ += 2;

    bool           lastWasSep = false;
    uint32_t       digits     = 0;
    bool error = false;
    const uint8_t* startSep   = buffer_;
    while (langSpec_->isHexNumber(buffer_[0]))
    {
        if (langSpec_->isNumberSep(buffer_[0]))
        {
            if (lastWasSep)
            {
                Diagnostic diag(ctx_->sourceFile());
                const auto elem = diag.addError(DiagnosticId::SyntaxNumberSepMulti);
                while (buffer_ < end_ && langSpec_->isNumberSep(buffer_[0]))
                    buffer_++;
                elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startSep - startBuffer_), static_cast<uint32_t>(buffer_ - startSep));
                reportError(diag);
                error = true;
            }

            startSep   = buffer_;
            lastWasSep = true;
            buffer_++;
            continue;
        }

        digits++;
        lastWasSep = false;
        buffer_++;
    }

    // Require at least one digit
    if (!error && digits == 0)
    {
        Diagnostic diag(ctx_->sourceFile());
        const auto elem = diag.addError(DiagnosticId::SyntaxMissingHexDigits);
        elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_), 2 + (lastWasSep ? 1 : 0));
        reportError(diag);
        error = true;
    }

    // No trailing separator
    if (!error && lastWasSep)
    {
        Diagnostic diag(ctx_->sourceFile());
        const auto elem = diag.addError(DiagnosticId::SyntaxNumberSepAtEnd);
        elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(buffer_ - startBuffer_ - 1));
        reportError(diag);
        error = true;
    }

    // Letters immediately following the literal
    if (!error && buffer_ < end_ && langSpec_->isLetter(buffer_[0]))
    {
        Diagnostic diag(ctx_->sourceFile());
        const auto elem = diag.addError(DiagnosticId::SyntaxMalformedHexNumber);
        elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(buffer_ - startBuffer_));
        reportError(diag);
    }

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseBinNumber()
{
    token_.subTokenNumberId = SubTokenNumberId::Binary;
    buffer_ += 2;
}

void Lexer::parseNumber()
{
    token_.id = TokenId::NumberLiteral;

    if (buffer_[0] == '0' && buffer_ + 1 < end_ && (buffer_[1] == 'x' || buffer_[1] == 'X'))
    {
        parseHexNumber();
        return;
    }

    if (buffer_[0] == '0' && buffer_ + 1 < end_ && (buffer_[1] == 'b' || buffer_[1] == 'B'))
    {
        parseBinNumber();
        return;
    }

    buffer_++;
}

void Lexer::parseSingleLineComment()
{
    token_.id                 = TokenId::Comment;
    token_.subTokenCommentId  = SubTokenCommentId::Line;
    const uint8_t* startToken = buffer_;

    // Stop before EOL (LF or CR), do not consume it here.
    while (buffer_ < end_ && buffer_[0] != '\n' && buffer_[0] != '\r')
        buffer_++;

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseMultiLineComment()
{
    token_.id                 = TokenId::Comment;
    token_.subTokenCommentId  = SubTokenCommentId::MultiLine;
    const uint8_t* startToken = buffer_;

    buffer_ += 2;
    uint32_t depth = 1;

    while (buffer_ < end_ && depth > 0)
    {
        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            consumeOneEol();
            continue;
        }

        // Need two chars to check either "/*" or "*/"
        if (buffer_ + 1 >= end_)
            break;

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
    {
        Diagnostic diag(ctx_->sourceFile());
        const auto elem = diag.addError(DiagnosticId::UnclosedComment);
        elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_), 2);
        reportError(diag);
    }

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::checkFormat(const CompilerInstance& ci, const CompilerContext& ctx, uint32_t& startOffset) const
{
    // Read header
    const auto    file = ctx.sourceFile();
    const uint8_t c1   = file->content_[0];
    const uint8_t c2   = file->content_[1];
    const uint8_t c3   = file->content_[2];
    const uint8_t c4   = file->content_[3];

    if (c1 == 0xEF && c2 == 0xBB && c3 == 0xBF)
    {
        startOffset = 3;
        return;
    }

    bool badFormat = false;
    if ((c1 == 0xFE && c2 == 0xFF)     // UTF-16 BigEndian
        || (c1 == 0xFF && c2 == 0xFE)) // UTF-16 LittleEndian
    {
        startOffset = 2;
        badFormat   = true;
    }

    if ((c1 == 0x0E && c2 == 0xFE && c3 == 0xFF)     // SCSU
        || (c1 == 0xFB && c2 == 0xEE && c3 == 0x28)  // BOCU-1
        || (c1 == 0xF7 && c2 == 0x64 && c3 == 0x4C)) // UTF-1 BigEndian
    {
        startOffset = 3;
        badFormat   = true;
    }

    if ((c1 == 0x00 && c2 == 0x00 && c3 == 0xFE && c4 == 0xFF)    // UTF-32 BigEndian
        || (c1 == 0xFF && c2 == 0xFE && c3 == 0x00 && c4 == 0x00) // UTF-32 LittleEndian
        || (c1 == 0x2B && c2 == 0x2F && c3 == 0x76 && c4 == 0x38) // UTF-7
        || (c1 == 0x2B && c2 == 0x2F && c3 == 0x76 && c4 == 0x39) // UTF-7
        || (c1 == 0x2B && c2 == 0x2F && c3 == 0x76 && c4 == 0x2B) // UTF-7
        || (c1 == 0x2B && c2 == 0x2F && c3 == 0x76 && c4 == 0x2F) // UTF-7
        || (c1 == 0xDD && c2 == 0x73 && c3 == 0x66 && c4 == 0x73) // UTF-EBCDIC
        || (c1 == 0x84 && c2 == 0x31 && c3 == 0x95 && c4 == 0x33) // GB-18030
    )
    {
        startOffset = 4;
        badFormat   = true;
    }

    if (badFormat)
    {
        Diagnostic diag(ctx_->sourceFile());
        const auto elem = diag.addElement(DiagnosticKind::Error, DiagnosticId::FileNotUtf8);
        elem->setLocation(ctx.sourceFile());
        elem->addArgument(file->path_.string());
        reportError(diag);
    }

    startOffset = 0;
}

Result Lexer::tokenize(const CompilerInstance& ci, const CompilerContext& ctx, LexerFlags flags)
{
    tokens_.clear();
    lines_.clear();

    const auto file = ctx.sourceFile();
    langSpec_       = &ci.langSpec();
    ci_             = &ci;
    ctx_            = &ctx;
    lexerFlags_     = flags;

    uint32_t startOffset = 0;
    checkFormat(ci, ctx, startOffset);

    const auto base = reinterpret_cast<const uint8_t*>(file->content_.data());
    buffer_         = base + startOffset;
    end_            = base + file->content_.size();
    startBuffer_    = base;

    tokens_.reserve(file->content_.size() / 8);
    lines_.reserve(file->content_.size() / 80);
    lines_.push_back(0);

    while (buffer_ < end_)
    {
        const auto startToken = buffer_;
        token_.start          = static_cast<uint32_t>(startToken - startBuffer_);
        token_.len            = 1;

        // End of line (LF, CRLF, or CR)
        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            parseEol();
            continue;
        }

        // Blanks
        if (langSpec_->isBlank(buffer_[0]))
        {
            parseBlank();
            continue;
        }

        // Number literal
        if (langSpec_->isDigit(buffer_[0]))
        {
            parseNumber();
            continue;
        }

        // String literal
        if (buffer_ + 1 < end_ && buffer_[0] == '#' && buffer_[1] == '"')
        {
            parseRawStringLiteral();
            continue;
        }

        if (buffer_ + 2 < end_ && buffer_[0] == '"' && buffer_[1] == '"' && buffer_[2] == '"')
        {
            parseMultiLineStringLiteral();
            continue;
        }

        if (buffer_[0] == '"')
        {
            parseSingleLineStringLiteral();
            continue;
        }

        // Line comment
        if (buffer_ + 1 < end_ && buffer_[0] == '/' && buffer_[1] == '/')
        {
            parseSingleLineComment();
            continue;
        }

        // Multi-line comment
        if (buffer_ + 1 < end_ && buffer_[0] == '/' && buffer_[1] == '*')
        {
            parseMultiLineComment();
            continue;
        }

        buffer_++;
    }

    return Result::Success;
}
