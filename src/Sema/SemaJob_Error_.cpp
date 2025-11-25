#include "pch.h"
#include "Report/Diagnostic.h"
#include "Sema/SemaJob.h"
#include "TypeManager.h"

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

void SemaJob::raiseInvalidType(AstNodeRef nodeRef, TypeInfoRef wantedType, TypeInfoRef hasType)
{
    auto diag = reportError(DiagnosticId::sema_err_invalid_type, nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, typeMgr().typeToString(hasType));
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, typeMgr().typeToString(wantedType));
    diag.report(ctx());
}

void SemaJob::raiseInternalError(const AstNode* node)
{
    raiseError(DiagnosticId::sema_err_internal, node->srcViewRef(), node->tokRef());
}

SWC_END_NAMESPACE()
