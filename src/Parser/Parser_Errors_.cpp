#include "pch.h"
#include "Lexer/SourceCodeLocation.h"
#include "Lexer/SourceFile.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

void Parser::setReportArguments(Diagnostic& diag, const Token& token) const
{
    diag.addArgument(Diagnostic::ARG_TOK, token.toString(*file_));
    diag.addArgument(Diagnostic::ARG_TOK_FAM, Token::toFamily(token.id), false);
    diag.addArgument(Diagnostic::ARG_A_TOK_FAM, Token::toAFamily(token.id), false);

    // Get the last non-trivia token
    if (curToken_ != firstToken_)
        diag.addArgument(Diagnostic::ARG_AFTER, curToken_[-1].toString(*file_));
}

void Parser::setReportExpected(Diagnostic& diag, TokenId expectedTknId)
{
    diag.addArgument(Diagnostic::ARG_EXPECT, Token::toName(expectedTknId));
    diag.addArgument(Diagnostic::ARG_EXPECT_FAM, Token::toFamily(expectedTknId), false);
    diag.addArgument(Diagnostic::ARG_A_EXPECT_FAM, Token::toAFamily(expectedTknId), false);
}

Diagnostic Parser::reportError(DiagnosticId id, const Token& tkn) const
{
    auto diag = Diagnostic::raise(*ctx_, id, file_);
    setReportArguments(diag, tkn);
    diag.last().setLocation(tkn.toLocation(*ctx_, *file_));
    return diag;
}

Diagnostic Parser::reportError(DiagnosticId id, TokenRef tknRef) const
{
    auto       diag  = Diagnostic::raise(*ctx_, id, file_);
    const auto token = file_->lexOut().token(tknRef);
    setReportArguments(diag, token);
    diag.last().setLocation(token.toLocation(*ctx_, *file_));
    return diag;
}

Diagnostic Parser::reportExpected(const ParserExpect& expect) const
{
    // Expected one single token
    SWC_ASSERT(expect.tokId != TokenId::Invalid);

    const auto expectedTknId = expect.tokId;

    auto diagId = expect.diag;
    if (expectedTknId == TokenId::Identifier && diagId == DiagnosticId::ParserExpectedToken)
        diagId = DiagnosticId::ParserExpectedTokenFam;

    auto diag = reportError(diagId, tok());
    setReportArguments(diag, tok());
    setReportExpected(diag, expectedTknId);
    diag.addArgument(Diagnostic::ARG_BECAUSE, Diagnostic::diagIdMessage(expect.becauseCtx), false);

    if (expectedTknId == TokenId::Identifier && tok().isReservedWord())
        diag.addElement(DiagnosticId::ParserReservedAsIdentifier);

    if (expect.noteId != DiagnosticId::None)
    {
        const auto tknLoc = file_->lexOut().token(expect.noteToken);
        diag.addElement(expect.noteId).setLocation(tknLoc.toLocation(*ctx_, *file_));
    }

    return diag;
}

SWC_END_NAMESPACE()
