#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantFold.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result check(Sema& sema, AstNodeRef nodeRef, const AstLogicalExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (!nodeLeftView.type->isConvertibleToBool())
            return SemaError::raiseBinaryOperandType(sema, nodeRef, node.nodeLeftRef, nodeLeftView.typeRef, nodeRightView.typeRef);
        if (!nodeRightView.type->isConvertibleToBool())
            return SemaError::raiseBinaryOperandType(sema, nodeRef, node.nodeRightRef, nodeLeftView.typeRef, nodeRightView.typeRef);
        return Result::Continue;
    }
}

Result AstLogicalExpr::semaPostNode(Sema& sema)
{
    const AstNodeRef nodeRef = sema.curNodeRef();
    SemaNodeView     nodeLeftView(sema, nodeLeftRef);
    SemaNodeView     nodeRightView(sema, nodeRightRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeLeftView.nodeRef));
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeRightView.nodeRef));
    sema.setIsValue(*this);

    // Type-check
    const auto& tok = sema.token(codeRef());
    RESULT_VERIFY(check(sema, nodeRef, *this, nodeLeftView, nodeRightView));

    // Set the result type
    RESULT_VERIFY(Cast::cast(sema, nodeLeftView, sema.typeMgr().typeBool(), CastKind::Condition));
    RESULT_VERIFY(Cast::cast(sema, nodeRightView, sema.typeMgr().typeBool(), CastKind::Condition));
    sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());

    // Constant folding
    if (nodeLeftView.cstRef.isValid() && nodeRightView.cstRef.isValid())
    {
        ConstantRef result;
        RESULT_VERIFY(ConstantFold::logical(sema, result, tok.id, nodeLeftView, nodeRightView));
        sema.setConstant(sema.curNodeRef(), result);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
