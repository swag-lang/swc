#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldBinaryExpr(Sema& sema, TokenId op, AstNodeRef left, AstNodeRef right)
    {
        const auto&    ctx      = sema.ctx();
        auto&          constMgr = sema.constMgr();
        const AstNode& leftPtr  = sema.node(left);
        const AstNode& rightPtr = sema.node(right);
        const auto&    leftCst  = leftPtr.getSemaConstant(ctx);
        const auto&    rightCst = rightPtr.getSemaConstant(ctx);

        switch (op)
        {
            case TokenId::SymPlusPlus:
            {
                Utf8 result = leftCst.toString();
                result += rightCst.toString();
                return constMgr.addConstant(ctx, ConstantValue::makeString(ctx, result));
            }

            default:
                break;
        }

        return ConstantRef::invalid();
    }

    ConstantRef constantFoldRelationalExpr(Sema& sema, TokenId op, AstNodeRef left, AstNodeRef right)
    {
        const auto&    ctx      = sema.ctx();
        auto&          constMgr = sema.constMgr();
        const AstNode& leftPtr  = sema.node(left);
        const AstNode& rightPtr = sema.node(right);
        const auto&    leftCst  = leftPtr.getSemaConstant(ctx);
        const auto&    rightCst = rightPtr.getSemaConstant(ctx);

        switch (op)
        {
            case TokenId::SymEqualEqual:
            {
                const bool result = leftCst == rightCst;
                return constMgr.addConstant(ctx, ConstantValue::makeBool(ctx, result));
            }

            default:
                break;
        }

        return ConstantRef::invalid();
    }
}

AstVisitStepResult AstBinaryExpr::semaPostNode(Sema& sema)
{
    const auto&    tok          = sema.token(srcViewRef(), tokRef());
    const AstNode& nodeLeftPtr  = sema.node(nodeLeft);
    const AstNode& nodeRightPtr = sema.node(nodeRight);

    if (nodeLeftPtr.isSemaConstant() && nodeRightPtr.isSemaConstant())
    {
        const auto cst = constantFoldBinaryExpr(sema, tok.id, nodeLeft, nodeRight);
        if (cst.isValid())
        {
            setSemaConstant(cst);
            return AstVisitStepResult::Continue;
        }
    }

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

AstVisitStepResult AstRelationalExpr::semaPostNode(Sema& sema)
{
    const auto&    tok          = sema.token(srcViewRef(), tokRef());
    const AstNode& nodeLeftPtr  = sema.node(nodeLeft);
    const AstNode& nodeRightPtr = sema.node(nodeRight);

    if (nodeLeftPtr.isSemaConstant() && nodeRightPtr.isSemaConstant())
    {
        const auto cst = constantFoldRelationalExpr(sema, tok.id, nodeLeft, nodeRight);
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
