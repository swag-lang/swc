#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

Diagnostic Parser::reportError(DiagnosticId id, const Token& myToken) const
{
    auto diag = Diagnostic::raise(*ctx_, id, file_);
    diag.last().setLocation(file_, myToken.byteStart, myToken.byteLength);
    diag.last().addArgument(Diagnostic::ARG_TOK, file_->codeView(myToken.byteStart, myToken.byteLength));
    return diag;
}

Diagnostic Parser::reportExpected(TokenId expected, DiagnosticId diagId) const
{
    if (diagId == DiagnosticId::None)
        diagId = DiagnosticId::ParserExpectedToken;

    auto diag = reportError(diagId, tok());
    diag.last().addArgument(Diagnostic::ARG_EXPECT, Token::toName(expected));

    if (diagId == DiagnosticId::ParserExpectedTokenAfter)
    {
        SWC_ASSERT(curToken_ != firstToken_);
        diag.last().addArgument(Diagnostic::ARG_AFTER, Token::toName(curToken_[-1].id));
    }

    if (expected == TokenId::Identifier && tok().id == TokenId::KwdEnum)
    {
        diag.addElement(DiagnosticId::ParserKeywordAsIdentifier).addArgument(Diagnostic::ARG_TOK, Token::toName(tok().id));
    }

    return diag;
}

SWC_END_NAMESPACE()
