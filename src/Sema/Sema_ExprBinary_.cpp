#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/SemaContext.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    struct BinaryOperands
    {
        const AstNode*       nodeLeft     = nullptr;
        const AstNode*       nodeRight    = nullptr;
        const ConstantValue* leftCst      = nullptr;
        const ConstantValue* rightCst     = nullptr;
        ConstantRef          leftCstRef   = ConstantRef::invalid();
        ConstantRef          rightCstRef  = ConstantRef::invalid();
        TypeRef              leftTypeRef  = TypeRef::invalid();
        TypeRef              rightTypeRef = TypeRef::invalid();
        const TypeInfo*      leftType     = nullptr;
        const TypeInfo*      rightType    = nullptr;

        BinaryOperands(Sema& sema, const AstBinaryExpr& expr) :
            nodeLeft(&sema.node(expr.nodeLeftRef)),
            nodeRight(&sema.node(expr.nodeRightRef)),
            leftTypeRef(sema.semaCtx().getTypeRef(sema.ctx(), expr.nodeLeftRef)),
            rightTypeRef(sema.semaCtx().getTypeRef(sema.ctx(), expr.nodeRightRef)),
            leftType(&sema.typeMgr().get(leftTypeRef)),
            rightType(&sema.typeMgr().get(rightTypeRef))
        {
        }
    };

    ConstantRef constantFoldPlusPlus(Sema& sema, const AstBinaryExpr& node, const BinaryOperands& ops)
    {
        const auto& ctx    = sema.ctx();
        Utf8        result = ops.leftCst->toString();
        result += ops.rightCst->toString();
        return sema.constMgr().addConstant(ctx, ConstantValue::makeString(ctx, result));
    }

    ConstantRef constantFold(Sema& sema, TokenId op, const AstBinaryExpr& node, BinaryOperands& ops)
    {
        ops.leftCstRef  = sema.semaCtx().getConstantRef(node.nodeLeftRef);
        ops.rightCstRef = sema.semaCtx().getConstantRef(node.nodeRightRef);
        ops.leftCst     = &sema.semaCtx().getConstant(sema.ctx(), node.nodeLeftRef);
        ops.rightCst    = &sema.semaCtx().getConstant(sema.ctx(), node.nodeRightRef);

        switch (op)
        {
            case TokenId::SymPlusPlus:
                return constantFoldPlusPlus(sema, node, ops);
            default:
                break;
        }

        return ConstantRef::invalid();
    }

    Result checkPlusPlus(Sema& sema, const AstBinaryExpr& node, const BinaryOperands& ops)
    {
        if (!sema.semaCtx().hasConstant(node.nodeLeftRef))
        {
            sema.raiseExprNotConst(node.nodeLeftRef);
            return Result::Error;
        }

        if (!sema.semaCtx().hasConstant(node.nodeRightRef))
        {
            sema.raiseExprNotConst(node.nodeRightRef);
            return Result::Error;
        }

        return Result::Success;
    }

    Result check(Sema& sema, TokenId op, const AstBinaryExpr& expr, const BinaryOperands& ops)
    {
        switch (op)
        {
            case TokenId::SymPlusPlus:
                return checkPlusPlus(sema, expr, ops);
            default:
                break;
        }

        sema.raiseInternalError(expr);
        return Result::Error;
    }
}

AstVisitStepResult AstBinaryExpr::semaPostNode(Sema& sema) const
{
    BinaryOperands ops(sema, *this);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (check(sema, tok.id, *this, ops) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    if (sema.semaCtx().hasConstant(nodeLeftRef) && sema.semaCtx().hasConstant(nodeRightRef))
    {
        const auto cst = constantFold(sema, tok.id, *this, ops);
        if (cst.isValid())
        {
            sema.semaCtx().setConstant(sema.currentNodeRef(), cst);
            return AstVisitStepResult::Continue;
        }

        return AstVisitStepResult::Stop;
    }

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
