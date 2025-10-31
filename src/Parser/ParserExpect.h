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
    TokenRef             noteToken  = INVALID_REF;
    DiagnosticId         noteId     = DiagnosticId::None;

    static ParserExpect one(TokenId tok, DiagnosticId d = DiagnosticId::ParserExpectedToken);
    static ParserExpect oneOf(std::initializer_list<TokenId> set, DiagnosticId d = DiagnosticId::ParserExpectedToken);

    bool          valid(TokenId id) const;
    ParserExpect& because(DiagnosticId b);
    ParserExpect& loc(TokenRef tok);
    ParserExpect& note(DiagnosticId id, TokenRef tok);
};

SWC_END_NAMESPACE()
