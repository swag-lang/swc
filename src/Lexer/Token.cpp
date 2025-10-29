#include "pch.h"

#include "LangSpec.h"
#include "Lexer/SourceFile.h"
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE()

std::string_view Token::toString(const SourceFile& file) const
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

SourceCodeLocation Token::toLocation(const Context& ctx, const SourceFile& file) const
{
    SourceCodeLocation loc;
    uint32_t offset;
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
    if (has_any(infos.flags, TokenIdFlags::Symbol))
        return "symbol";
    if(tknId == TokenId::Identifier)
        return "identifier";
    if (has_any(infos.flags, TokenIdFlags::Keyword))
        return "keyword";
    if (has_any(infos.flags, TokenIdFlags::Type))
        return "type";
    if (has_any(infos.flags, TokenIdFlags::Compiler))
        return "compiler instruction";
    if (has_any(infos.flags, TokenIdFlags::Intrinsic))
        return "intrinsic";
    if (has_any(infos.flags, TokenIdFlags::Modifier))
        return "modifier";

    return "token";
}

std::string_view Token::toAFamily(TokenId tknId)
{
    const auto& infos = TOKEN_ID_INFOS[static_cast<size_t>(tknId)];
    if (has_any(infos.flags, TokenIdFlags::Symbol))
        return "a symbol";
    if (tknId == TokenId::Identifier)
        return "an identifier";
    if (has_any(infos.flags, TokenIdFlags::Keyword))
        return "a keyword";
    if (has_any(infos.flags, TokenIdFlags::Type))
        return "a type";
    if (has_any(infos.flags, TokenIdFlags::Compiler))
        return "a compiler instruction";
    if (has_any(infos.flags, TokenIdFlags::Intrinsic))
        return "an intrinsic";
    if (has_any(infos.flags, TokenIdFlags::Modifier))
        return "a modifier";

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
    default:
        return TokenId::Invalid;
    }
}

SWC_END_NAMESPACE()
