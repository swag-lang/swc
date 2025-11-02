#pragma once
#include "Core/Types.h"
#include "Lexer/Token.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

struct ParserExpect
{
    TokenId      tokId      = TokenId::Invalid;
    DiagnosticId diag       = DiagnosticId::ParserExpectedToken;
    DiagnosticId becauseCtx = DiagnosticId::None;
    TokenRef     noteToken  = INVALID_REF;
    DiagnosticId noteId     = DiagnosticId::None;

    static ParserExpect one(TokenId tok, DiagnosticId d = DiagnosticId::ParserExpectedToken);

    bool          valid(TokenId id) const;
    ParserExpect& because(DiagnosticId b);
    ParserExpect& note(DiagnosticId id, TokenRef tok);
};

SWC_END_NAMESPACE()
