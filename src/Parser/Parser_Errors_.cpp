#include "pch.h"
#include "Lexer/SourceCodeLocation.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

void Parser::reportArguments(Diagnostic& diag, const Token& myToken) const
{
    diag.addArgument(Diagnostic::ARG_TOK, myToken.toString(*file_));
    diag.addArgument(Diagnostic::ARG_TOK_FAM, Token::toFamily(myToken.id), false);
    diag.addArgument(Diagnostic::ARG_A_TOK_FAM, Token::toAFamily(myToken.id), false);

    // Get the last non trivia token
    auto last = lastNonTrivia();
    if(last)
        diag.addArgument(Diagnostic::ARG_AFTER, last->toString(*file_));
}

Diagnostic Parser::reportError(DiagnosticId id, const Token& myToken) const
{
    auto diag = Diagnostic::raise(*ctx_, id, file_);
    reportArguments(diag, myToken);
    diag.last().setLocation(myToken.toLocation(*ctx_, *file_));
    return diag;
}

Diagnostic Parser::reportExpected(const Expect& expect) const
{
    // Expected one single token
    if (expect.tok != TokenId::Invalid)
    {
        const auto expected = expect.tok;

        auto diagId = expect.diag;
        if (expected == TokenId::Identifier && diagId == DiagnosticId::ParserExpectedToken)
            diagId = DiagnosticId::ParserExpectedTokenFam;

        auto diag = reportError(diagId, tok());
        reportArguments(diag, tok());

        diag.addArgument(Diagnostic::ARG_EXPECT, Token::toName(expected));
        diag.addArgument(Diagnostic::ARG_EXPECT_FAM, Token::toFamily(expected), false);
        diag.addArgument(Diagnostic::ARG_A_EXPECT_FAM, Token::toAFamily(expected), false);
        diag.addArgument(Diagnostic::ARG_BECAUSE, Diagnostic::diagIdMessage(expect.becauseCtx), false);

        if (expected == TokenId::Identifier && tok().isReservedWord())
            diag.addElement(DiagnosticId::ParserReservedAsIdentifier);
        return diag;
    }

    // Expected one of multiple tokens
    else
    {
        auto diag = reportError(expect.diag, tok());
        reportArguments(diag, tok());

        Utf8 msg = "one of ";
        bool first = true;
        for (const auto& t : expect.oneOf)
        {
            if (!first)
                msg += ", ";
            msg += std::format("'{}'", Token::toName(t));
            first = false;
        }

        diag.addArgument(Diagnostic::ARG_EXPECT, msg);
        diag.addArgument(Diagnostic::ARG_BECAUSE, Diagnostic::diagIdMessage(expect.becauseCtx), false);
        return diag;
    }
}

SWC_END_NAMESPACE()
