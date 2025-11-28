#include "pch.h"

#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldPlusPlus(Sema& sema, const AstBinaryExpr& node)
    {
        const auto&    ctx       = sema.ctx();
        const AstNode& leftNode  = sema.node(node.nodeLeftRef);
        const AstNode& rightNode = sema.node(node.nodeRightRef);
        const auto&    leftCst   = leftNode.getSemaConstant(ctx);
        const auto&    rightCst  = rightNode.getSemaConstant(ctx);

        Utf8 result = leftCst.toString();
        result += rightCst.toString();
        return sema.constMgr().addConstant(ctx, ConstantValue::makeString(ctx, result));
    }

    ConstantRef constantFold(Sema& sema, TokenId op, const AstBinaryExpr& node)
    {
        switch (op)
        {
            case TokenId::SymPlusPlus:
                return constantFoldPlusPlus(sema, node);
            default:
                break;
        }

        return ConstantRef::invalid();
    }

    Result checkPlusPlus(Sema& sema, const AstBinaryExpr& expr)
    {
        const AstNode& nodeLeft = sema.node(expr.nodeLeftRef);
        if (!nodeLeft.isSemaConstant())
        {
            sema.raiseExprNotConst(expr.nodeLeftRef);
            return Result::Error;
        }

        const AstNode& nodeRight = sema.node(expr.nodeRightRef);
        if (!nodeRight.isSemaConstant())
        {
            sema.raiseExprNotConst(expr.nodeRightRef);
            return Result::Error;
        }

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
    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (check(sema, tok.id, *this) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    const AstNode& nodeLeft  = sema.node(nodeLeftRef);
    const AstNode& nodeRight = sema.node(nodeRightRef);
    if (nodeLeft.isSemaConstant() && nodeRight.isSemaConstant())
    {
        const auto cst = constantFold(sema, tok.id, *this);
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
