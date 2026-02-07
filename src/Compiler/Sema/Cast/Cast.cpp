#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

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
    SWC_ASSERT(f.nodeRef.isValid());
    auto diag = SemaError::report(sema, f.diagId, f.nodeRef);
    f.applyArguments(diag);
    diag.addNote(f.noteId);
    diag.report(sema.ctx());
    return Result::Error;
}

AstNodeRef Cast::createImplicitCast(Sema& sema, TypeRef dstTypeRef, AstNodeRef nodeRef)
{
    const AstNode& node               = sema.node(nodeRef);
    auto [substNodeRef, substNodePtr] = sema.ast().makeNode<AstNodeId::ImplicitCastExpr>(node.tokRef());
    substNodePtr->nodeExprRef         = nodeRef;
    sema.setSubstitute(nodeRef, substNodeRef);
    sema.setType(substNodeRef, dstTypeRef);
    sema.setIsValue(*substNodePtr);
    return substNodeRef;
}

SWC_END_NAMESPACE();
