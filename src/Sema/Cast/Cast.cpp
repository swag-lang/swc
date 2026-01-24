#include "pch.h"
#include "Sema/Cast/Cast.h"
#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

void CastFailure::set(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note)
{
    *this      = CastFailure{};
    diagId     = d;
    nodeRef    = errorNodeRef;
    srcTypeRef = srcRef;
    dstTypeRef = dstRef;
    valueStr   = std::string(value);
    noteId     = note;
}

CastContext::CastContext(CastKind kind) :
    kind(kind)
{
}

void CastContext::fail(DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note)
{
    failure.set(errorNodeRef, d, srcRef, dstRef, value, note);
}

Result Cast::emitCastFailure(Sema& sema, const CastFailure& f)
{
    auto diag = SemaError::report(sema, f.diagId, f.nodeRef);
    if (f.srcTypeRef.isValid())
        diag.addArgument(Diagnostic::ARG_TYPE, f.srcTypeRef);
    if (f.dstTypeRef.isValid())
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, f.dstTypeRef);
    if (f.optTypeRef.isValid())
        diag.addArgument(Diagnostic::ARG_OPT_TYPE, f.optTypeRef);
    diag.addArgument(Diagnostic::ARG_VALUE, f.valueStr);
    diag.addNote(f.noteId);
    diag.report(sema.ctx());
    return Result::Error;
}

AstNodeRef Cast::createImplicitCast(Sema& sema, TypeRef dstTypeRef, AstNodeRef nodeRef)
{
    SemaInfo&      semaInfo           = sema.semaInfo();
    const AstNode& node               = sema.ast().node(nodeRef);
    auto [substNodeRef, substNodePtr] = sema.ast().makeNode<AstNodeId::ImplicitCastExpr>(node.tokRef());
    substNodePtr->nodeExprRef         = nodeRef;
    semaInfo.setSubstitute(nodeRef, substNodeRef);
    semaInfo.setType(substNodeRef, dstTypeRef);
    SemaInfo::setIsValue(*substNodePtr);
    return substNodeRef;
}

SWC_END_NAMESPACE();
