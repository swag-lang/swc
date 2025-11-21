#include "pch.h"
#include "Report/Diagnostic.h"
#include "Sema/SemaJob.h"

SWC_BEGIN_NAMESPACE()

Diagnostic SemaJob::reportError(DiagnosticId id, TokenRef tknRef)
{
    auto diag = Diagnostic::get(id, visit().curSrcView().file());
    // setReportArguments(diag, tknRef);
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
    const auto  nodePtr = node(nodeRef);
    const auto& info    = Ast::nodeIdInfos(nodePtr->id);

    SmallVector<AstNodeRef> children;
    info.collectChildren(children, *ast_, *nodePtr);
}

SWC_END_NAMESPACE()
