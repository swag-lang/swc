#include "pch.h"
#include "Compiler/Lexer/Token.h"
#include "Lexer.h"

SWC_BEGIN_NAMESPACE();

std::string_view Token::string(const SourceView& srcView) const
{
    auto start = srcView.stringView().data();

    // In the case of an identifier, 'byteStart' is the index in the file identifier table.
    // And the real 'byteStart' is stored in that table
    if (id == TokenId::Identifier)
    {
        const auto& ids    = srcView.identifiers();
        const auto  offset = ids[byteStart].byteStart;
        return {start + offset, static_cast<size_t>(byteLength)};
    }

    return {start + byteStart, static_cast<size_t>(byteLength)};
}

uint32_t Token::crc(const SourceView& srcView) const
{
    SWC_ASSERT(id == TokenId::Identifier);
    return srcView.identifiers()[byteStart].crc;
}

SourceCodeRange Token::codeRange(const TaskContext& ctx, const SourceView& srcView) const
{
    SourceCodeRange codeRange;
    uint32_t        offset;
    if (id == TokenId::Identifier)
        offset = srcView.identifiers()[byteStart].byteStart;
    else
        offset = byteStart;
    codeRange.fromOffset(ctx, srcView, offset, byteLength);
    return codeRange;
}

std::string_view Token::toName(TokenId id)
{
    return TOKEN_ID_INFOS[static_cast<size_t>(id)].displayName;
}

std::string_view Token::toFamily(TokenId id)
{
    if (id == TokenId::Identifier)
        return "identifier";
    if (id == TokenId::EndOfFile)
        return "end of file";

    if (isSymbol(id))
        return "symbol";
    if (isKeyword(id))
        return "keyword";
    if (isType(id))
        return "type";
    if (isCompiler(id))
        return "compiler instruction";
    if (isIntrinsic(id))
        return "intrinsic";
    if (isModifier(id))
        return "modifier";
    if (isLiteral(id))
        return "literal";

    return "token";
}

TokenId Token::toRelated(TokenId id)
{
    switch (id)
    {
        case TokenId::SymLeftParen:
            return TokenId::SymRightParen;
        case TokenId::SymRightParen:
            return TokenId::SymLeftParen;

        case TokenId::SymLeftBracket:
            return TokenId::SymRightBracket;
        case TokenId::SymRightBracket:
            return TokenId::SymLeftBracket;

        case TokenId::SymLeftCurly:
            return TokenId::SymRightCurly;
        case TokenId::SymRightCurly:
            return TokenId::SymLeftCurly;

        case TokenId::SymAttrStart:
            return TokenId::SymRightBracket;

        case TokenId::SymPipe:
            return TokenId::SymPipe;

        default:
            return TokenId::Invalid;
    }
}

TokenId Token::assignToBinary(TokenId op)
{
    switch (op)
    {
        case TokenId::SymPlusEqual:
            return TokenId::SymPlus;
        case TokenId::SymMinusEqual:
            return TokenId::SymMinus;
        case TokenId::SymAsteriskEqual:
            return TokenId::SymAsterisk;
        case TokenId::SymSlashEqual:
            return TokenId::SymSlash;
        case TokenId::SymAmpersandEqual:
            return TokenId::SymAmpersand;
        case TokenId::SymPipeEqual:
            return TokenId::SymPipe;
        case TokenId::SymCircumflexEqual:
            return TokenId::SymCircumflex;
        case TokenId::SymPercentEqual:
            return TokenId::SymPercent;
        case TokenId::SymLowerLowerEqual:
            return TokenId::SymLowerLower;
        case TokenId::SymGreaterGreaterEqual:
            return TokenId::SymGreaterGreater;
        case TokenId::SymEqual:
            return TokenId::SymEqual;
        default:
            break;
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
