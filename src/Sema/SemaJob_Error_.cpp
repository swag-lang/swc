#include "pch.h"
#include "Report/Diagnostic.h"
#include "Sema/SemaJob.h"

SWC_BEGIN_NAMESPACE()

Diagnostic SemaJob::reportError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tknRef)
{
    auto       diag    = Diagnostic::get(id, ast().srcView().fileRef());
    const auto srcView = compiler().srcView(srcViewRef);
    diag.last().addSpan(Diagnostic::tokenErrorLocation(ctx(), srcView, tknRef), "");
    return diag;
}

void SemaJob::raiseError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tknRef)
{
    const auto diag = reportError(id, srcViewRef, tknRef);
    diag.report(ctx());
}

void SemaJob::raiseError(DiagnosticId id, AstNodeRef nodeRef)
{
    const auto nodePtr = node(nodeRef);
    /*const auto  tokRefStart = nodePtr->tokRef();
    const auto  tokRefEnd   = nodePtr->tokRefEnd(*ast_);
    const auto& srcView     = compiler().srcView(nodePtr->srcViewRef());
    const auto  locStart    = Diagnostic::tokenErrorLocation(ctx(), srcView, tokRefStart);
    const auto  locEnd      = Diagnostic::tokenErrorLocation(ctx(), srcView, tokRefEnd);*/

    const auto diag = Diagnostic::get(id, ast().srcView().fileRef());
    const auto loc  = nodePtr->location(ctx(), ast());
    diag.last().addSpan(loc, "");
    diag.report(ctx());
}

SWC_END_NAMESPACE()
