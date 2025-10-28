#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

Diagnostic Parser::reportError(DiagnosticId id, const Token& myToken) const
{
    auto diag = Diagnostic::raise(*ctx_, id, file_);
    diag.last().setLocation(file_, myToken.byteStart, myToken.byteLength);
    diag.last().addArgument("tok", file_->codeView(myToken.byteStart, myToken.byteLength));
    return diag;
}

Diagnostic Parser::reportExpected(TokenId expected, DiagnosticId diagId) const
{
    if (diagId == DiagnosticId::None)
        diagId = DiagnosticId::ParserExpectedToken;

    auto diag = reportError(diagId, tok());
    diag.last().addArgument("expect", Token::toName(expected));

    if (diagId == DiagnosticId::ParserExpectedTokenAfter)
    {
        SWC_ASSERT(curToken_ != firstToken_);
        diag.last().addArgument("after", Token::toName(curToken_[-1].id));
    }

    return diag;
}

SWC_END_NAMESPACE();
