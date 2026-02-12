#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

Result Cast::emitCastFailure(Sema& sema, const CastFailure& f)
{
    Diagnostic diag;
    if (f.codeRef.isValid())
        diag = SemaError::report(sema, f.diagId, f.codeRef);
    else
    {
        SWC_ASSERT(f.nodeRef.isValid());
        diag = SemaError::report(sema, f.diagId, f.nodeRef);
    }
    f.applyArguments(diag);
    diag.addNote(f.noteId);
    diag.report(sema.ctx());
    return Result::Error;
}

AstNodeRef Cast::createCast(Sema& sema, TypeRef dstTypeRef, AstNodeRef nodeRef, AstCastExprFlagsE castFlags)
{
    const AstNode& node               = sema.node(nodeRef);
    auto [substNodeRef, substNodePtr] = sema.ast().makeNode<AstNodeId::CastExpr>(node.tokRef());
    substNodePtr->addFlag(castFlags);
    substNodePtr->nodeExprRef = nodeRef;
    sema.setSubstitute(nodeRef, substNodeRef);
    sema.setType(substNodeRef, dstTypeRef);
    sema.setIsValue(*substNodePtr);
    return substNodeRef;
}

SWC_END_NAMESPACE();
