#include "pch.h"
#include "Lexer/Token.h"
#include "Lexer.h"

SWC_BEGIN_NAMESPACE()

std::string_view Token::string(const LexerOutput& lex) const
{
    auto start = lex.sourceView().data();

    // In the case of an identifier, 'byteStart' is the index in the file identifier table.
    // And the real 'byteStart' is stored in that table
    if (id == TokenId::Identifier)
    {
        const auto offset = lex.identifiers()[byteStart].byteStart;
        return {start + offset, static_cast<size_t>(byteLength)};
    }

    return {start + byteStart, static_cast<size_t>(byteLength)};
}

SourceCodeLocation Token::location(const TaskContext& ctx, const LexerOutput& lex) const
{
    SourceCodeLocation loc;
    uint32_t           offset;
    if (id == TokenId::Identifier)
        offset = lex.identifiers()[byteStart].byteStart;
    else
        offset = byteStart;
    loc.fromOffset(ctx, lex, offset, byteLength);
    return loc;
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

std::string_view Token::toAFamily(TokenId id)
{
    if (id == TokenId::Identifier)
        return "an identifier";
    if (id == TokenId::EndOfFile)
        return "a end of file";

    if (isSymbol(id))
        return "a symbol";
    if (isKeyword(id))
        return "a keyword";
    if (isType(id))
        return "a type";
    if (isCompiler(id))
        return "a compiler instruction";
    if (isIntrinsic(id))
        return "a intrinsic";
    if (isModifier(id))
        return "a modifier";
    if (isLiteral(id))
        return "a literal";

    return "a token";
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

        case TokenId::SymVertical:
            return TokenId::SymVertical;

        default:
            return TokenId::Invalid;
    }
}

SWC_END_NAMESPACE()
