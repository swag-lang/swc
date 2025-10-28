#include "pch.h"

#include "LangSpec.h"
#include "Lexer/SourceFile.h"
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE();

std::string_view Token::toString(const SourceFile* file) const
{
    return {reinterpret_cast<const char*>(file->content().data()) + byteStart, reinterpret_cast<const char*>(file->content().data()) + byteStart + byteLength};
}

std::string_view Token::toName(TokenId tknId)
{
    if (has_any(toFlags(tknId), TokenIdFlags::Symbol))
        return TOKEN_ID_INFOS[static_cast<size_t>(tknId)].displayName;
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
