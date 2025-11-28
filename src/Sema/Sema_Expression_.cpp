#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"
#include "TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldBinaryExpr(Sema& sema, TokenId op, AstNodeRef leftNodeRef, AstNodeRef rightNodeRef)
    {
        const auto&    ctx       = sema.ctx();
        auto&          constMgr  = sema.constMgr();
        const AstNode& leftNode  = sema.node(leftNodeRef);
        const AstNode& rightNode = sema.node(rightNodeRef);
        const auto&    leftCst   = leftNode.getSemaConstant(ctx);
        const auto&    rightCst  = rightNode.getSemaConstant(ctx);

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

    ConstantRef constantFoldRelationalExpr(Sema& sema, TokenId op, AstNodeRef leftNodeRef, AstNodeRef rightNodeRef)
    {
        const auto&    ctx       = sema.ctx();
        auto&          constMgr  = sema.constMgr();
        const AstNode& leftNode  = sema.node(leftNodeRef);
        const AstNode& rightNode = sema.node(rightNodeRef);
        const auto&    leftCst   = leftNode.getSemaConstant(ctx);
        const auto&    rightCst  = rightNode.getSemaConstant(ctx);

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

    ConstantRef constantFoldUnaryExpr(Sema& sema, TokenId op, AstNodeRef nodeRef)
    {
        const auto&          ctx      = sema.ctx();
        auto&                constMgr = sema.constMgr();
        const AstNode&       node     = sema.node(nodeRef);
        const ConstantValue& cst      = node.getSemaConstant(ctx);

        switch (op)
        {
            case TokenId::SymMinus:
            {
                ApsInt cpy = cst.getInt();

                bool overflow = false;
                cpy.negate(overflow);
                if (overflow)
                {
                    sema.raiseLiteralOverflow(nodeRef, node.getNodeTypeRef(sema.ctx()));
                    return ConstantRef::invalid();
                }

                cpy.setUnsigned(false);
                return constMgr.addConstant(ctx, ConstantValue::makeInt(ctx, cpy, cpy.bitWidth()));
            }

            default:
                break;
        }

        return ConstantRef::invalid();
    }
}

AstVisitStepResult AstBinaryExpr::semaPostNode(Sema& sema)
{
    const auto&    tok       = sema.token(srcViewRef(), tokRef());
    const AstNode& nodeLeft  = sema.node(nodeLeftRef);
    const AstNode& nodeRight = sema.node(nodeRightRef);

    if (nodeLeft.isSemaConstant() && nodeRight.isSemaConstant())
    {
        const auto cst = constantFoldBinaryExpr(sema, tok.id, nodeLeftRef, nodeRightRef);
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
    const auto&    tok       = sema.token(srcViewRef(), tokRef());
    const AstNode& nodeLeft  = sema.node(nodeLeftRef);
    const AstNode& nodeRight = sema.node(nodeRightRef);

    if (nodeLeft.isSemaConstant() && nodeRight.isSemaConstant())
    {
        const auto cst = constantFoldRelationalExpr(sema, tok.id, nodeLeftRef, nodeRightRef);
        if (cst.isValid())
        {
            setSemaConstant(cst);
            return AstVisitStepResult::Continue;
        }
    }

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

AstVisitStepResult AstUnaryExpr::semaPostNode(Sema& sema)
{
    const auto&     tok     = sema.token(srcViewRef(), tokRef());
    const AstNode&  node    = sema.node(nodeExprRef);
    TypeInfoRef     typeRef = node.getNodeTypeRef(sema.ctx());
    const TypeInfo& type    = sema.typeMgr().get(typeRef);

    switch (tok.id)
    {
        case TokenId::SymMinus:
            if (type.isFloat() || type.isIntSigned() || type.isInt0())
                break;
            if (type.isIntUnsigned())
            {
                auto diag = sema.reportError(DiagnosticId::sema_err_negate_unsigned, srcViewRef(), tokRef());
                diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
                diag.report(sema.ctx());
            }
            else
            {
                auto diag = sema.reportError(DiagnosticId::sema_err_unary_operand_type, srcViewRef(), tokRef());
                diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
                diag.report(sema.ctx());
            }
            return AstVisitStepResult::Stop;

        default:
            sema.raiseInternalError(*this);
            return AstVisitStepResult::Stop;
    }

    if (node.isSemaConstant())
    {
        const auto cst = constantFoldUnaryExpr(sema, tok.id, nodeExprRef);
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
