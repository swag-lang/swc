#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldEqual(Sema& sema, const AstRelationalExpr& node)
    {
        const auto&    ctx       = sema.ctx();
        const AstNode& leftNode  = sema.node(node.nodeLeftRef);
        const AstNode& rightNode = sema.node(node.nodeRightRef);
        const auto&    leftCst   = leftNode.getSemaConstant(ctx);
        const auto&    rightCst  = rightNode.getSemaConstant(ctx);

        const bool result = (leftCst == rightCst);
        return sema.constMgr().addConstant(ctx, ConstantValue::makeBool(ctx, result));
    }

    ConstantRef constantFold(Sema& sema, TokenId op, const AstRelationalExpr& node)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
                return constantFoldEqual(sema, node);
            default:
                break;
        }

        return ConstantRef::invalid();
    }

    Result checkEqualEqual(Sema& sema, const AstRelationalExpr& expr)
    {
        return Result::Success;
    }

    Result check(Sema& sema, TokenId op, const AstRelationalExpr& expr)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
                return checkEqualEqual(sema, expr);
            default:
                break;
        }

        sema.raiseInternalError(expr);
        return Result::Error;
    }
}

AstVisitStepResult AstRelationalExpr::semaPostNode(Sema& sema)
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
