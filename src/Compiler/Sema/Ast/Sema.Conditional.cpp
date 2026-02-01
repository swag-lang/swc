#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/SemaInfo.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

Result AstConditionalExpr::semaPostNode(Sema& sema)
{
    SemaNodeView       nodeCondView(sema, nodeCondRef);
    const SemaNodeView nodeTrueView(sema, nodeTrueRef);
    const SemaNodeView nodeFalseView(sema, nodeFalseRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeCondView.nodeRef));
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeTrueView.nodeRef));
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeFalseView.nodeRef));
    SemaInfo::setIsValue(*this);

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
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_binary_operand_type, srcViewRef(), tokRef());
        diag.addArgument(Diagnostic::ARG_TYPE, nodeTrueView.typeRef);
        diag.addNote(DiagnosticId::sema_note_other_definition);
        diag.last().addSpan(nodeFalseView.node->locationWithChildren(sema.ctx(), sema.ast()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    sema.setType(sema.curNodeRef(), typeRef);

    // Constant folding
    if (nodeCondView.cstRef.isValid())
    {
        AstNodeRef   selectedBranchRef = nodeCondView.cst->getBool() ? nodeTrueRef : nodeFalseRef;
        SemaNodeView selectedBranchView(sema, selectedBranchRef);
        RESULT_VERIFY(Cast::cast(sema, selectedBranchView, typeRef, CastKind::Implicit));
        sema.semaInfo().setSubstitute(sema.curNodeRef(), selectedBranchView.nodeRef);
        if (selectedBranchView.cstRef.isValid())
            sema.setConstant(sema.curNodeRef(), selectedBranchView.cstRef);
    }
    else
    {
        SemaNodeView mutableTrueView(sema, nodeTrueRef);
        SemaNodeView mutableFalseView(sema, nodeFalseRef);
        RESULT_VERIFY(Cast::cast(sema, mutableTrueView, typeRef, CastKind::Implicit));
        RESULT_VERIFY(Cast::cast(sema, mutableFalseView, typeRef, CastKind::Implicit));
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
