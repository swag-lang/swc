#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldPlusPlus(Sema& sema, const AstNode& leftNode, const AstNode& rightNode)
    {
        const auto& ctx      = sema.ctx();
        auto&       constMgr = sema.constMgr();
        const auto& leftCst  = leftNode.getSemaConstant(ctx);
        const auto& rightCst = rightNode.getSemaConstant(ctx);

        Utf8 result = leftCst.toString();
        result += rightCst.toString();
        return constMgr.addConstant(ctx, ConstantValue::makeString(ctx, result));
    }

    ConstantRef constantFold(Sema& sema, TokenId op, AstNodeRef leftNodeRef, AstNodeRef rightNodeRef)
    {
        const AstNode& leftNode  = sema.node(leftNodeRef);
        const AstNode& rightNode = sema.node(rightNodeRef);

        switch (op)
        {
            case TokenId::SymPlusPlus:
                return constantFoldPlusPlus(sema, leftNode, rightNode);
            default:
                break;
        }

        return ConstantRef::invalid();
    }

    Result checkPlusPlus(Sema& sema, const AstBinaryExpr& expr)
    {
        return Result::Success;
    }

    Result check(Sema& sema, TokenId op, const AstBinaryExpr& expr)
    {
        switch (op)
        {
            case TokenId::SymPlusPlus:
                return checkPlusPlus(sema, expr);
            default:
                break;
        }

        sema.raiseInternalError(expr);
        return Result::Error;
    }
}

AstVisitStepResult AstBinaryExpr::semaPostNode(Sema& sema)
{
    const auto& tok = sema.token(srcViewRef(), tokRef());

    // Type-check
    if (check(sema, tok.id, *this) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
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
