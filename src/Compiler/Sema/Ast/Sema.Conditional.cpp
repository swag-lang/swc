#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

Result AstConditionalExpr::semaPostNode(Sema& sema)
{
    SemaNodeView       nodeCondView  = sema.nodeViewNodeTypeConstant(nodeCondRef);
    const SemaNodeView nodeTrueView  = sema.nodeViewNodeTypeConstant(nodeTrueRef);
    const SemaNodeView nodeFalseView = sema.nodeViewNodeTypeConstant(nodeFalseRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeCondView.nodeRef));
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeTrueView.nodeRef));
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeFalseView.nodeRef));
    sema.setIsValue(*this);

    // Condition must be bool
    RESULT_VERIFY(Cast::cast(sema, nodeCondView, sema.typeMgr().typeBool(), CastKind::Condition));

    // Make both branches compatible
    TypeRef typeRef = TypeRef::invalid();
    if (nodeTrueView.typeRef == nodeFalseView.typeRef)
        typeRef = nodeTrueView.typeRef;
    else
        typeRef = Cast::castAllowedBothWays(sema, nodeTrueView.typeRef, nodeFalseView.typeRef);

    if (!typeRef.isValid())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_binary_operand_type, codeRef());
        diag.addArgument(Diagnostic::ARG_TYPE, nodeTrueView.typeRef);
        diag.addNote(DiagnosticId::sema_note_other_definition);
        diag.last().addSpan(nodeFalseView.node->codeRangeWithChildren(sema.ctx(), sema.ast()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    sema.setType(sema.curNodeRef(), typeRef);

    // Constant folding
    if (nodeCondView.cstRef.isValid())
    {
        AstNodeRef   selectedBranchRef  = nodeCondView.cst->getBool() ? nodeTrueRef : nodeFalseRef;
        SemaNodeView selectedBranchView = sema.nodeViewNodeTypeConstant(selectedBranchRef);
        RESULT_VERIFY(Cast::cast(sema, selectedBranchView, typeRef, CastKind::Implicit));
        sema.setSubstitute(sema.curNodeRef(), selectedBranchView.nodeRef);
        if (selectedBranchView.cstRef.isValid())
            sema.setConstant(sema.curNodeRef(), selectedBranchView.cstRef);
    }
    else
    {
        SemaNodeView mutableTrueView  = sema.nodeViewNodeTypeConstant(nodeTrueRef);
        SemaNodeView mutableFalseView = sema.nodeViewNodeTypeConstant(nodeFalseRef);
        RESULT_VERIFY(Cast::cast(sema, mutableTrueView, typeRef, CastKind::Implicit));
        RESULT_VERIFY(Cast::cast(sema, mutableFalseView, typeRef, CastKind::Implicit));
    }

    return Result::Continue;
}

Result AstNullCoalescingExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeLeftView  = sema.nodeViewNodeTypeConstant(nodeLeftRef);
    SemaNodeView       nodeRightView = sema.nodeViewNodeTypeConstant(nodeRightRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeLeftView.nodeRef));
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeRightView.nodeRef));
    sema.setIsValue(*this);

    if (!nodeLeftView.type->isConvertibleToBool())
        return SemaError::raiseBinaryOperandType(sema, sema.curNodeRef(), nodeLeftRef, nodeLeftView.typeRef, nodeRightView.typeRef);

    RESULT_VERIFY(Cast::cast(sema, nodeRightView, nodeLeftView.typeRef, CastKind::Implicit));
    sema.setType(sema.curNodeRef(), nodeLeftView.typeRef);

    // Constant folding
    if (nodeLeftView.cstRef.isValid())
    {
        SemaNodeView nodeBoolView = sema.nodeViewNodeTypeConstant(nodeLeftRef);
        RESULT_VERIFY(Cast::cast(sema, nodeBoolView, sema.typeMgr().typeBool(), CastKind::Condition));

        const bool        leftIsFalse = nodeBoolView.cstRef == sema.cstMgr().cstFalse();
        const auto        selectedRef = leftIsFalse ? nodeRightView.nodeRef : nodeLeftView.nodeRef;
        const ConstantRef selectedCst = leftIsFalse ? nodeRightView.cstRef : nodeLeftView.cstRef;
        if (selectedCst.isValid())
            sema.setConstant(sema.curNodeRef(), selectedCst);
        else
            sema.setSubstitute(sema.curNodeRef(), selectedRef);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();

