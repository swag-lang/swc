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
    auto diag = Diagnostic::get(*ctx_, id, file_);
    setReportArguments(diag, tkn);
    diag.last().setLocation(tkn.toLocation(*ctx_, *file_));
    return diag;
}

void Parser::raiseError(DiagnosticId id, const Token& tkn) const
{
    const auto diag = reportError(id, tkn);
    diag.report(*ctx_);
}

Diagnostic Parser::reportError(DiagnosticId id, TokenRef tknRef) const
{
    auto       diag  = Diagnostic::get(*ctx_, id, file_);
    const auto token = file_->lexOut().token(tknRef);
    setReportArguments(diag, token);
    diag.last().setLocation(token.toLocation(*ctx_, *file_));
    return diag;
}

void Parser::raiseError(DiagnosticId id, TokenRef tknRef) const
{
    const auto diag = reportError(id, tknRef);
    diag.report(*ctx_);
}

Diagnostic Parser::reportExpected(const ParserExpect& expect) const
{
    SWC_ASSERT(expect.tokId != TokenId::Invalid);

    auto diag = reportError(expect.diag, tok());
    setReportArguments(diag, tok());
    setReportExpected(diag, expect.tokId);
    diag.addArgument(Diagnostic::ARG_BECAUSE, Diagnostic::diagIdMessage(expect.becauseCtx), false);

    // Additional notes
    if (expect.tokId == TokenId::Identifier && tok().isReservedWord())
        diag.addElement(DiagnosticId::ParserReservedAsIdentifier);

    if (expect.noteId != DiagnosticId::None)
    {
        const auto tknLoc = file_->lexOut().token(expect.noteToken);
        diag.addElement(expect.noteId).setLocation(tknLoc.toLocation(*ctx_, *file_));
    }

    return diag;
}

void Parser::raiseExpected(const ParserExpect& expect) const
{
    const auto diag = reportExpected(expect);
    diag.report(*ctx_);
}

SWC_END_NAMESPACE()
