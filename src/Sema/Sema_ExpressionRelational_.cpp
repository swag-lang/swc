#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldEqual(Sema& sema, const AstNode& leftNode, const AstNode& rightNode)
    {
        const auto& ctx      = sema.ctx();
        auto&       constMgr = sema.constMgr();

        const auto& leftCst  = leftNode.getSemaConstant(ctx);
        const auto& rightCst = rightNode.getSemaConstant(ctx);

        const bool result = (leftCst == rightCst);
        return constMgr.addConstant(ctx, ConstantValue::makeBool(ctx, result));
    }

    ConstantRef constantFold(Sema& sema, TokenId op, AstNodeRef leftNodeRef, AstNodeRef rightNodeRef)
    {
        const AstNode& leftNode  = sema.node(leftNodeRef);
        const AstNode& rightNode = sema.node(rightNodeRef);

        switch (op)
        {
            case TokenId::SymEqualEqual:
                return constantFoldEqual(sema, leftNode, rightNode);
            default:
                break;
        }

        return ConstantRef::invalid();
    }
}

AstVisitStepResult AstRelationalExpr::semaPostNode(Sema& sema)
{
    const auto&    tok       = sema.token(srcViewRef(), tokRef());
    const AstNode& nodeLeft  = sema.node(nodeLeftRef);
    const AstNode& nodeRight = sema.node(nodeRightRef);

    if (nodeLeft.isSemaConstant() && nodeRight.isSemaConstant())
    {
        const auto cst = constantFold(sema, tok.id, nodeLeftRef, nodeRightRef);
        if (cst.isValid())
        {
            setSemaConstant(cst);
            return AstVisitStepResult::Continue;
        }
    }

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
