#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Type/Cast.h"

SWC_BEGIN_NAMESPACE();

Result AstConditionalExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeCondView(sema, nodeCondRef);
    const SemaNodeView nodeTrueView(sema, nodeTrueRef);
    const SemaNodeView nodeFalseView(sema, nodeFalseRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeCondRef));
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeTrueRef));
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeFalseRef));
    SemaInfo::setIsValue(*this);

    // Type-check
    if (!nodeCondView.type->isBool())
        return SemaError::raiseBinaryOperandType(sema, *this, nodeCondRef, nodeCondView.typeRef);

    TypeRef typeRef = TypeRef::invalid();
    if (nodeTrueView.typeRef == nodeFalseView.typeRef)
        typeRef = nodeTrueView.typeRef;
    else
    {
        CastContext castCtxTrue(CastKind::Implicit);
        CastContext castCtxFalse(CastKind::Implicit);

        if (Cast::castAllowed(sema, castCtxTrue, nodeTrueView.typeRef, nodeFalseView.typeRef) == Result::Continue)
            typeRef = nodeFalseView.typeRef;
        else if (Cast::castAllowed(sema, castCtxFalse, nodeFalseView.typeRef, nodeTrueView.typeRef) == Result::Continue)
            typeRef = nodeTrueView.typeRef;
    }

    if (!typeRef.isValid())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_binary_operand_type, srcViewRef(), tokRef());
        diag.addArgument(Diagnostic::ARG_TYPE, nodeTrueView.typeRef);
        diag.addNote(DiagnosticId::sema_note_other_definition);
        diag.last().addSpan(nodeFalseView.node->locationWithChildren(sema.ctx(), sema.ast()));
        diag.report(sema.ctx());
        return Result::Stop;
    }

    sema.setType(sema.curNodeRef(), typeRef);

    // Constant folding
    if (nodeCondView.cstRef.isValid())
    {
        AstNodeRef selectedBranchRef = nodeCondView.cst->getBool() ? nodeTrueRef : nodeFalseRef;
        const auto selectedBranchView = selectedBranchRef == nodeTrueRef ? nodeTrueView : nodeFalseView;
        if (selectedBranchView.typeRef != typeRef)
            selectedBranchRef = Cast::createImplicitCast(sema, typeRef, selectedBranchRef);
        sema.semaInfo().setSubstitute(sema.curNodeRef(), selectedBranchRef);

        ConstantRef cstRef = selectedBranchView.cstRef;
        if (cstRef.isValid())
        {
            sema.setConstant(sema.curNodeRef(), cstRef);

            const ConstantValue& cst = sema.cstMgr().get(cstRef);
            if (cst.typeRef() != typeRef)
            {
                ConstantRef promotedCstRef;
                CastContext castCtx(CastKind::Implicit);
                castCtx.setFoldSrc(cstRef);
                if (Cast::castConstant(sema, promotedCstRef, castCtx, cstRef, typeRef) == Result::Continue)
                    sema.setConstant(sema.curNodeRef(), promotedCstRef);
            }
        }
    }
    else
    {
        if (nodeTrueView.typeRef != typeRef)
            Cast::createImplicitCast(sema, typeRef, nodeTrueRef);
        if (nodeFalseView.typeRef != typeRef)
            Cast::createImplicitCast(sema, typeRef, nodeFalseRef);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
