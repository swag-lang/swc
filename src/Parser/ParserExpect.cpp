#include "pch.h"
#include "Parser/ParserExpect.h"

SWC_BEGIN_NAMESPACE()

bool ParserExpect::valid(TokenId id) const
{
    return id == tokId;
}

ParserExpect ParserExpect::one(TokenId tok, DiagnosticId d)
{
    ParserExpect s;
    s.tokId = tok;
    s.diag  = d;
    return s;
}

ParserExpect& ParserExpect::because(DiagnosticId b)
{
    becauseCtx = b;
    return *this;
}

ParserExpect& ParserExpect::note(DiagnosticId id, TokenRef tok)
{
    noteId    = id;
    noteToken = tok;
    return *this;
}

SWC_END_NAMESPACE()
