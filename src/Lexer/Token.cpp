#include "pch.h"

#include "LangSpec.h"
#include "Lexer/SourceFile.h"
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE()

std::string_view Token::string(const SourceFile& file) const
{
    auto start = reinterpret_cast<const char*>(file.content().data());

    // In the case of an identifier, 'byteStart' is the index in the file identifier table.
    // And the real 'byteStart' is stored in that table
    if (id == TokenId::Identifier)
    {
        const auto offset = file.lexOut().identifiers()[byteStart].byteStart;
        return {start + offset, static_cast<size_t>(byteLength)};
    }

    return {start + byteStart, static_cast<size_t>(byteLength)};
}

SourceCodeLocation Token::location(const Context& ctx, const SourceFile& file) const
{
    SourceCodeLocation loc;
    uint32_t           offset;
    if (id == TokenId::Identifier)
        offset = file.lexOut().identifiers()[byteStart].byteStart;
    else
        offset = byteStart;
    loc.fromOffset(ctx, file, offset, byteLength);
    return loc;
}

std::string_view Token::toName(TokenId tknId)
{
    return TOKEN_ID_INFOS[static_cast<size_t>(tknId)].displayName;
}

std::string_view Token::toFamily(TokenId tknId)
{
    const auto& infos = TOKEN_ID_INFOS[static_cast<size_t>(tknId)];
    if (infos.flags.has(TokenIdFlagsE::Symbol))
        return "symbol";
    if (tknId == TokenId::Identifier)
        return "identifier";
    if (tknId == TokenId::EndOfFile)
        return "end of file";
    if (infos.flags.has(TokenIdFlagsE::Keyword))
        return "keyword";
    if (infos.flags.has(TokenIdFlagsE::Type))
        return "type";
    if (infos.flags.has(TokenIdFlagsE::Compiler))
        return "compiler instruction";
    if (infos.flags.has(TokenIdFlagsE::Intrinsic))
        return "intrinsic";
    if (infos.flags.has(TokenIdFlagsE::Modifier))
        return "modifier";
    if (infos.flags.has(TokenIdFlagsE::Literal))
        return "literal";

    return "token";
}

std::string_view Token::toAFamily(TokenId tknId)
{
    const auto& infos = TOKEN_ID_INFOS[static_cast<size_t>(tknId)];
    if (infos.flags.has(TokenIdFlagsE::Symbol))
        return "a symbol";
    if (tknId == TokenId::Identifier)
        return "an identifier";
    if (tknId == TokenId::EndOfFile)
        return "a end of file";
    if (infos.flags.has(TokenIdFlagsE::Keyword))
        return "a keyword";
    if (infos.flags.has(TokenIdFlagsE::Type))
        return "a type";
    if (infos.flags.has(TokenIdFlagsE::Compiler))
        return "a compiler instruction";
    if (infos.flags.has(TokenIdFlagsE::Intrinsic))
        return "an intrinsic";
    if (infos.flags.has(TokenIdFlagsE::Modifier))
        return "a modifier";
    if (infos.flags.has(TokenIdFlagsE::Literal))
        return "a literal";

    return "a token";
}

TokenId Token::toRelated(TokenId tkn)
{
    switch (tkn)
    {
    case TokenId::SymLeftParen:
        return TokenId::SymRightParen;
    case TokenId::SymLeftBracket:
        return TokenId::SymRightBracket;
    case TokenId::SymLeftCurly:
        return TokenId::SymRightCurly;
    case TokenId::SymAttrStart:
        return TokenId::SymRightBracket;
    case TokenId::SymVertical:
        return TokenId::SymVertical;
    default:
        return TokenId::Invalid;
    }
}

SWC_END_NAMESPACE()
