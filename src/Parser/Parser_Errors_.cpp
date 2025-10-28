#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

Diagnostic Parser::reportError(DiagnosticId id, const Token& myToken) const
{
    auto diag = Diagnostic::raise(*ctx_, id, file_);
    diag.last().setLocation(file_, myToken.byteStart, myToken.byteLength);
    diag.last().addArgument("tkn", file_->codeView(myToken.byteStart, myToken.byteLength));
    return diag;
}

SWC_END_NAMESPACE();
