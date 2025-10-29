#include "pch.h"

#include "LangSpec.h"
#include "Lexer/SourceFile.h"
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE();

std::string_view Token::toString(const SourceFile* file) const
{
    auto start = reinterpret_cast<const char*>(file->content().data());

    // In the case of an identifier, 'byteStart' is the index in the file identifier table.
    // And the real 'byteStart' is stored in that table
    if (id == TokenId::Identifier)
    {
        const auto offset = file->lexOut().identifiers()[byteStart].byteStart;
        return {start + offset, static_cast<size_t>(byteLength)};
    }

    return {start + byteStart, static_cast<size_t>(byteLength)};
}

std::string_view Token::toName(TokenId tknId)
{
    const auto result = TOKEN_ID_INFOS[static_cast<size_t>(tknId)].displayName;
    if (!result.empty())
        return result;

    return LangSpec::keywordName(tknId);
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
        std::unreachable();
    }
}

SWC_END_NAMESPACE();
