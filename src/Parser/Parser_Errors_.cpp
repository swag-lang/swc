#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticIds.h"

SWC_BEGIN_NAMESPACE();

void Parser::reportError(DiagnosticId id, const Token& myToken) const
{
    const auto diag = Diagnostic::error(id, file_);
    diag.last()->setLocation(file_, myToken.byteStart, myToken.byteLength);
    diag.last()->addArgument("tkn", file_->codeView(myToken.byteStart, myToken.byteLength));
    diag.report(*ctx_);
}

SWC_END_NAMESPACE();
