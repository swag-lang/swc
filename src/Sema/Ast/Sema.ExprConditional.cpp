#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Type/Cast.h"
#include "Sema/Type/TypeManager.h"

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

    const auto typeRef = sema.typeMgr().promote(nodeTrueView.typeRef, nodeFalseView.typeRef, false);
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
        ConstantRef cstRef = ConstantRef::invalid();
        if (nodeCondView.cst->getBool())
            cstRef = nodeTrueView.cstRef;
        else
            cstRef = nodeFalseView.cstRef;

        if (cstRef.isValid())
        {
            const auto& cst = sema.cstMgr().get(cstRef);
            if (cst.typeRef() == typeRef)
            {
                sema.setConstant(sema.curNodeRef(), cstRef);
            }
            else
            {
                ConstantRef promotedCstRef;
                CastContext castCtx(CastKind::Promotion);
                if (Cast::castConstant(sema, promotedCstRef, castCtx, cstRef, typeRef) == Result::Continue)
                    sema.setConstant(sema.curNodeRef(), promotedCstRef);
            }
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
