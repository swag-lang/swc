#pragma once
#include "Core/Types.h"
#include "Lexer/Token.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

struct ParserExpect
{
    TokenId              oneTok     = TokenId::Invalid;
    SmallVector<TokenId> manyTok    = {};
    DiagnosticId         diag       = DiagnosticId::ParserExpectedToken;
    DiagnosticId         becauseCtx = DiagnosticId::None;
    TokenRef             locToken   = INVALID_REF;

    bool valid(TokenId id) const
    {
        const bool ok = manyTok.empty() ? (id == oneTok) : std::ranges::find(manyTok, id) != manyTok.end();
        return ok;
    }

    static ParserExpect one(TokenId tok, DiagnosticId d = DiagnosticId::ParserExpectedToken)
    {
        ParserExpect s;
        s.oneTok = tok;
        s.diag   = d;
        return s;
    }

    static ParserExpect oneOf(std::initializer_list<TokenId> set, DiagnosticId d = DiagnosticId::ParserExpectedToken)
    {
        ParserExpect s;
        s.manyTok = set;
        s.diag    = d;
        return s;
    }

    ParserExpect& because(DiagnosticId b)
    {
        becauseCtx = b;
        return *this;
    }

    ParserExpect& loc(TokenRef tok)
    {
        locToken = tok;
        return *this;
    }
};

SWC_END_NAMESPACE()
