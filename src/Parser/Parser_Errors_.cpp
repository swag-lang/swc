#include "pch.h"
#include "Lexer/SourceCodeLocation.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

void Parser::reportArguments(Diagnostic& diag, const Token& myToken) const
{
    if (atEnd())
    {
        diag.addArgument(Diagnostic::ARG_TOK, "<eof>");
        diag.addArgument(Diagnostic::ARG_TOK_FAM, "end of file", false);
        diag.addArgument(Diagnostic::ARG_A_TOK_FAM, "end of file", false);
    }
    else
    {
        diag.addArgument(Diagnostic::ARG_TOK, myToken.toString(*file_));
        diag.addArgument(Diagnostic::ARG_TOK_FAM, Token::toFamily(myToken.id), false);
        diag.addArgument(Diagnostic::ARG_A_TOK_FAM, Token::toAFamily(myToken.id), false);
    }

    if (curToken_ != firstToken_)
    {
        const auto& prevToken = curToken_[-1];
        diag.addArgument(Diagnostic::ARG_AFTER, prevToken.toString(*file_));
    }
}

Diagnostic Parser::reportError(DiagnosticId id, const Token& myToken) const
{
    auto diag = Diagnostic::raise(*ctx_, id, file_);
    reportArguments(diag, myToken);
    diag.last().setLocation(myToken.toLocation(*ctx_, *file_));
    return diag;
}

Diagnostic Parser::reportExpected(TokenId expected, DiagnosticId diagId) const
{
    if (diagId == DiagnosticId::None)
        diagId = DiagnosticId::ParserExpectedToken;

    auto diag = reportError(diagId, tok());
    reportArguments(diag, tok());

    diag.addArgument(Diagnostic::ARG_EXPECT, Token::toName(expected));
    diag.addArgument(Diagnostic::ARG_EXPECT_FAM, Token::toFamily(expected), false);
    diag.addArgument(Diagnostic::ARG_A_EXPECT_FAM, Token::toAFamily(expected), false);

    if (expected == TokenId::Identifier && tok().isReserved())
        diag.addElement(DiagnosticId::ParserReservedAsIdentifier);

    return diag;
}

SWC_END_NAMESPACE()
