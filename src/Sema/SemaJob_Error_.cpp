#include "pch.h"
#include "Report/Diagnostic.h"
#include "Sema/SemaJob.h"

SWC_BEGIN_NAMESPACE()

Diagnostic SemaJob::reportError(DiagnosticId id, AstNodeRef nodeRef)
{
    auto       diag = Diagnostic::get(id, ast().srcView().fileRef());
    const auto loc  = node(nodeRef)->location(ctx(), ast());
    diag.last().addSpan(loc, "");
    return diag;
}

Diagnostic SemaJob::reportError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokenRef)
{
    auto        diag    = Diagnostic::get(id, ast().srcView().fileRef());
    const auto& srcView = compiler().srcView(srcViewRef);
    diag.last().addSpan(Diagnostic::tokenErrorLocation(ctx(), srcView, tokenRef), "");
    return diag;
}

void SemaJob::raiseError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokenRef)
{
    const auto diag = reportError(id, srcViewRef, tokenRef);
    diag.report(ctx());
}

void SemaJob::raiseError(DiagnosticId id, AstNodeRef nodeRef)
{
    const auto diag = reportError(id, nodeRef);
    diag.report(ctx());
}

SWC_END_NAMESPACE()
