#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result resolveConditionalResultType(Sema& sema, TypeRef& outTypeRef, const SemaNodeView& nodeTrueView, const SemaNodeView& nodeFalseView)
    {
        outTypeRef = TypeRef::invalid();

        const std::span<const SemaFrame> frames = sema.frames();
        for (size_t frameIndex = frames.size(); frameIndex > 0; --frameIndex)
        {
            const std::span<const TypeRef> bindingTypes = frames[frameIndex - 1].bindingTypes();
            for (size_t bindingIndex = bindingTypes.size(); bindingIndex > 0; --bindingIndex)
            {
                const TypeRef bindingTypeRef = bindingTypes[bindingIndex - 1];
                if (!bindingTypeRef.isValid())
                    continue;

                CastRequest trueCastRequest(CastKind::Implicit);
                trueCastRequest.errorNodeRef = nodeTrueView.nodeRef();
                const Result trueCastResult  = Cast::castAllowed(sema, trueCastRequest, nodeTrueView.typeRef(), bindingTypeRef);
                if (trueCastResult == Result::Pause)
                    return Result::Pause;
                if (trueCastResult != Result::Continue)
                    continue;

                CastRequest falseCastRequest(CastKind::Implicit);
                falseCastRequest.errorNodeRef = nodeFalseView.nodeRef();
                const Result falseCastResult  = Cast::castAllowed(sema, falseCastRequest, nodeFalseView.typeRef(), bindingTypeRef);
                if (falseCastResult == Result::Pause)
                    return Result::Pause;
                if (falseCastResult != Result::Continue)
                    continue;

                outTypeRef = bindingTypeRef;
                return Result::Continue;
            }
        }

        if (nodeTrueView.typeRef() == nodeFalseView.typeRef())
        {
            outTypeRef = nodeTrueView.typeRef();
            return Result::Continue;
        }

        outTypeRef = Cast::castAllowedBothWays(sema, nodeTrueView.typeRef(), nodeFalseView.typeRef());
        return Result::Continue;
    }
}

Result AstConditionalExpr::semaPostNode(Sema& sema)
{
    SemaNodeView       nodeCondView  = sema.viewNodeTypeConstant(nodeCondRef);
    const SemaNodeView nodeTrueView  = sema.viewNodeTypeConstant(nodeTrueRef);
    const SemaNodeView nodeFalseView = sema.viewNodeTypeConstant(nodeFalseRef);

    // Value-check
    SWC_RESULT_VERIFY(SemaCheck::isValue(sema, nodeCondView.nodeRef()));
    SWC_RESULT_VERIFY(SemaCheck::isValue(sema, nodeTrueView.nodeRef()));
    SWC_RESULT_VERIFY(SemaCheck::isValue(sema, nodeFalseView.nodeRef()));
    sema.setIsValue(*this);

    // Condition must be bool
    SWC_RESULT_VERIFY(Cast::cast(sema, nodeCondView, sema.typeMgr().typeBool(), CastKind::Condition));

    // Make both branches compatible
    TypeRef typeRef = TypeRef::invalid();
    SWC_RESULT_VERIFY(resolveConditionalResultType(sema, typeRef, nodeTrueView, nodeFalseView));

    if (!typeRef.isValid())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_binary_operand_type, codeRef());
        diag.addArgument(Diagnostic::ARG_TYPE, nodeTrueView.typeRef());
        diag.addNote(DiagnosticId::sema_note_other_definition);
        diag.last().addSpan(nodeFalseView.node()->codeRangeWithChildren(sema.ctx(), sema.ast()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    sema.setType(sema.curNodeRef(), typeRef);

    // Constant folding
    if (nodeCondView.cstRef().isValid())
    {
        AstNodeRef const selectedBranchRef  = nodeCondView.cst()->getBool() ? nodeTrueRef : nodeFalseRef;
        SemaNodeView     selectedBranchView = sema.viewNodeTypeConstant(selectedBranchRef);
        SWC_RESULT_VERIFY(Cast::cast(sema, selectedBranchView, typeRef, CastKind::Implicit));
        sema.setSubstitute(sema.curNodeRef(), selectedBranchView.nodeRef());
        if (selectedBranchView.cstRef().isValid())
            sema.setConstant(sema.curNodeRef(), selectedBranchView.cstRef());
    }
    else
    {
        SemaNodeView mutableTrueView  = sema.viewNodeTypeConstant(nodeTrueRef);
        SemaNodeView mutableFalseView = sema.viewNodeTypeConstant(nodeFalseRef);
        SWC_RESULT_VERIFY(Cast::cast(sema, mutableTrueView, typeRef, CastKind::Implicit));
        SWC_RESULT_VERIFY(Cast::cast(sema, mutableFalseView, typeRef, CastKind::Implicit));
    }

    return Result::Continue;
}

Result AstNullCoalescingExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeLeftView  = sema.viewNodeTypeConstant(nodeLeftRef);
    SemaNodeView       nodeRightView = sema.viewNodeTypeConstant(nodeRightRef);

    // Value-check
    SWC_RESULT_VERIFY(SemaCheck::isValue(sema, nodeLeftView.nodeRef()));
    SWC_RESULT_VERIFY(SemaCheck::isValue(sema, nodeRightView.nodeRef()));
    sema.setIsValue(*this);

    if (!nodeLeftView.type()->isConvertibleToBool())
        return SemaError::raiseBinaryOperandType(sema, sema.curNodeRef(), nodeLeftRef, nodeLeftView.typeRef(), nodeRightView.typeRef());

    SWC_RESULT_VERIFY(Cast::cast(sema, nodeRightView, nodeLeftView.typeRef(), CastKind::Implicit));
    sema.setType(sema.curNodeRef(), nodeLeftView.typeRef());

    // Constant folding
    if (nodeLeftView.cstRef().isValid())
    {
        SemaNodeView nodeBoolView = sema.viewNodeTypeConstant(nodeLeftRef);
        SWC_RESULT_VERIFY(Cast::cast(sema, nodeBoolView, sema.typeMgr().typeBool(), CastKind::Condition));

        const bool        leftIsFalse = nodeBoolView.cstRef() == sema.cstMgr().cstFalse();
        const auto        selectedRef = leftIsFalse ? nodeRightView.nodeRef() : nodeLeftView.nodeRef();
        const ConstantRef selectedCst = leftIsFalse ? nodeRightView.cstRef() : nodeLeftView.cstRef();
        if (selectedCst.isValid())
            sema.setConstant(sema.curNodeRef(), selectedCst);
        else
            sema.setSubstitute(sema.curNodeRef(), selectedRef);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
