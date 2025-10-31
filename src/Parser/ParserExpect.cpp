#include "pch.h"
#include "Parser/ParserExpect.h"

SWC_BEGIN_NAMESPACE()

bool ParserExpect::valid(TokenId id) const
{
    const bool ok = manyTok.empty() ? (id == oneTok) : std::ranges::find(manyTok, id) != manyTok.end();
    return ok;
}

ParserExpect ParserExpect::one(TokenId tok, DiagnosticId d)
{
    ParserExpect s;
    s.oneTok = tok;
    s.diag   = d;
    return s;
}

ParserExpect ParserExpect::oneOf(std::initializer_list<TokenId> set, DiagnosticId d)
{
    ParserExpect s;
    s.manyTok = set;
    s.diag    = d;
    return s;
}

ParserExpect& ParserExpect::because(DiagnosticId b)
{
    becauseCtx = b;
    return *this;
}

ParserExpect& ParserExpect::loc(TokenRef tok)
{
    locToken = tok;
    return *this;
}

ParserExpect& ParserExpect::note(DiagnosticId id, TokenRef tok)
{
    noteId    = id;
    noteToken = tok;
    return *this;
}

SWC_END_NAMESPACE()
