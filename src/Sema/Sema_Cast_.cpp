#include "pch.h"
#include "Sema/Sema.h"
#include "Sema/SemaCast.h"
#include "Sema/SemaNodeView.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstExplicitCastExpr::semaPostNode(Sema& sema) const
{
    if (sema.checkModifiers(*this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst) == Result::Error)
        return AstVisitStepResult::Stop;

    const SemaNodeView nodeTypeView(sema, nodeTypeRef);
    const SemaNodeView nodeExprView(sema, nodeExprRef);

    CastContext castCtx(CastKind::Explicit);
    if (modifierFlags.has(AstModifierFlagsE::Bit))
        castCtx.flags.add(CastFlagsE::BitCast);
    castCtx.errorNodeRef = nodeTypeView.nodeRef;

    if (sema.hasConstant(nodeExprRef))
    {
        const ConstantRef cstRef = SemaCast::castConstant(sema, castCtx, nodeExprView.cstRef, nodeTypeView.typeRef);
        if (cstRef.isInvalid())
            return AstVisitStepResult::Stop;
        sema.setConstant(sema.curNodeRef(), cstRef);
        return AstVisitStepResult::Continue;
    }

    if (!SemaCast::castAllowed(sema, castCtx, nodeExprView.typeRef, nodeTypeView.typeRef))
        return AstVisitStepResult::Stop;

    sema.setType(sema.curNodeRef(), nodeTypeView.typeRef);
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
