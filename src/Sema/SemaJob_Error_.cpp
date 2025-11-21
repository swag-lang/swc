#include "pch.h"
#include "Report/Diagnostic.h"
#include "Sema/SemaJob.h"

SWC_BEGIN_NAMESPACE()

Diagnostic SemaJob::reportError(DiagnosticId id, TokenRef tknRef)
{
    auto diag = Diagnostic::get(id, visit().curSrcView().file());
    diag.last().addSpan(Diagnostic::tokenErrorLocation(ctx(), visit().curSrcView(), tknRef), "");
    return diag;
}

void SemaJob::raiseError(DiagnosticId id, TokenRef tknRef)
{
    const auto diag = reportError(id, tknRef);
    diag.report(ctx());
}

void SemaJob::raiseError(DiagnosticId id, AstNodeRef nodeRef)
{
    const auto nodePtr     = node(nodeRef);
    const auto tokRefStart = nodePtr->tokRef();
    const auto tokRefEnd   = nodePtr->tokRefEnd(*ast_);
}

SWC_END_NAMESPACE()
