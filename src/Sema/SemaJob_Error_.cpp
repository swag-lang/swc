#include "pch.h"
#include "Report/Diagnostic.h"
#include "Sema/SemaJob.h"

SWC_BEGIN_NAMESPACE()

void SemaJob::setReportArguments(Diagnostic& diag, AstNodeRef nodeRef) const
{
}

Diagnostic SemaJob::reportError(DiagnosticId id, AstNodeRef nodeRef)
{
    auto       diag = Diagnostic::get(id, ast().srcView().fileRef());
    const auto loc  = node(nodeRef)->location(ctx(), ast());
    diag.last().addSpan(loc, "");
    setReportArguments(diag, nodeRef);
    return diag;
}

void SemaJob::raiseError(DiagnosticId id, AstNodeRef nodeRef)
{
    const auto diag = reportError(id, nodeRef);
    diag.report(ctx());
}

SWC_END_NAMESPACE()
