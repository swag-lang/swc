#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result constantFoldPlus(Sema& sema, ConstantRef& result, const SemaNodeView& ops)
    {
        const auto& ctx = sema.ctx();

        if (ops.type->isInt())
        {
            ApsInt value = ops.cst->getInt();
            value.setUnsigned(true);
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, ops.type->intBits(), TypeInfo::Sign::Unsigned));
            return Result::Continue;
        }

        result = ops.cstRef;
        return Result::Continue;
    }

    Result constantFoldMinus(Sema& sema, ConstantRef& result, const SemaNodeView& ops)
    {
        // In the case of a literal with a suffix, it has already been done
        // @MinusLiteralSuffix
        if (ops.node->is(AstNodeId::SuffixLiteral))
        {
            result = sema.constantRefOf(ops.nodeRef);
            return Result::Continue;
        }

        const auto& ctx = sema.ctx();
        if (ops.type->isInt())
        {
            ApsInt value = ops.cst->getInt();

            bool overflow = false;
            value.negate(overflow);
            if (overflow)
                return SemaError::raiseLiteralOverflow(sema, ops.nodeRef, *ops.cst, ops.typeRef);

            value.setUnsigned(false);
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, ops.type->intBits(), TypeInfo::Sign::Signed));
            return Result::Continue;
        }

        if (ops.type->isFloat())
        {
            ApFloat value = ops.cst->getFloat();
            value.negate();
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, value, ops.type->floatBits()));
            return Result::Continue;
        }

        return Result::Error;
    }

    Result constantFoldBang(Sema& sema, ConstantRef& result, const AstUnaryExpr&, const SemaNodeView& ops)
    {
        if (ops.cst->isBool())
        {
            result = sema.cstMgr().cstNegBool(ops.cstRef);
            return Result::Continue;
        }

        SWC_ASSERT(ops.cst->isInt());
        result = sema.cstMgr().cstBool(ops.cst->getInt().isZero());
        return Result::Continue;
    }

    Result constantFoldTilde(Sema& sema, ConstantRef& result, const AstUnaryExpr&, const SemaNodeView& ops)
    {
        const auto& ctx = sema.ctx();

        ApsInt value = ops.cst->getInt();
        value.invertAllBits();
        result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, ops.type->intBits(), ops.type->intSign()));
        return Result::Continue;
    }

    Result constantFold(Sema& sema, ConstantRef& result, TokenId op, const AstUnaryExpr& node, const SemaNodeView& ops)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return constantFoldMinus(sema, result, ops);
            case TokenId::SymPlus:
                return constantFoldPlus(sema, result, ops);
            case TokenId::SymBang:
                return constantFoldBang(sema, result, node, ops);
            case TokenId::SymTilde:
                return constantFoldTilde(sema, result, node, ops);
            default:
                break;
        }

        return Result::Error;
    }

    Result reportInvalidType(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_unary_operand_type, expr.srcViewRef(), expr.tokRef());
        diag.addArgument(Diagnostic::ARG_TYPE, ops.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result checkMinus(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        if (ops.type->isFloat() || ops.type->isIntSigned() || ops.type->isIntUnsized())
            return Result::Continue;

        if (ops.type->isIntUnsigned())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_negate_unsigned, expr.srcViewRef(), expr.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        return reportInvalidType(sema, expr, ops);
    }

    Result checkPlus(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        if (ops.type->isFloat() || ops.type->isIntUnsigned() || ops.type->isIntUnsized())
            return Result::Continue;

        if (ops.type->isIntSigned())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_negate_unsigned, expr.srcViewRef(), expr.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        return reportInvalidType(sema, expr, ops);
    }

    Result checkBang(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        if (ops.type->isBool() || ops.type->isInt())
            return Result::Continue;
        return reportInvalidType(sema, expr, ops);
    }

    Result checkTilde(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        if (ops.type->isInt())
            return Result::Continue;
        return reportInvalidType(sema, expr, ops);
    }

    Result checkTakeAddress(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& nodeView)
    {
        if (nodeView.cstRef.isValid())
        {
            const auto               diag = SemaError::report(sema, DiagnosticId::sema_err_take_address_constant, node.srcViewRef(), node.tokRef());
            const SourceCodeLocation loc  = sema.node(nodeView.nodeRef).locationWithChildren(sema.ctx(), sema.ast());
            diag.last().addSpan(loc, "", DiagnosticSeverity::Note);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!SemaInfo::isLValue(*nodeView.node))
        {
            const auto               diag = SemaError::report(sema, DiagnosticId::sema_err_take_address_not_lvalue, node.srcViewRef(), node.tokRef());
            const SourceCodeLocation loc  = sema.node(nodeView.nodeRef).locationWithChildren(sema.ctx(), sema.ast());
            diag.last().addSpan(loc, "", DiagnosticSeverity::Note);
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Continue;
    }

    Result semaTakeAddress(Sema& sema, const AstUnaryExpr&, const SemaNodeView& nodeView)
    {
        TypeInfoFlags flags = TypeInfoFlagsE::Zero;
        if (nodeView.type->isConst())
        {
            flags.add(TypeInfoFlagsE::Const);
        }
        else if (nodeView.sym && nodeView.sym->isVariable())
        {
            const auto symVar = &nodeView.sym->cast<SymbolVariable>();
            if (symVar->hasExtraFlag(SymbolVariableFlagsE::Let))
                flags.add(TypeInfoFlagsE::Const);
        }

        bool blockPointer = false;
        if (nodeView.type->isArray())
            blockPointer = true;

        const TypeInfo& ty      = blockPointer ? TypeInfo::makeBlockPointer(nodeView.typeRef, flags) : TypeInfo::makeValuePointer(nodeView.typeRef, flags);
        const TypeRef   typeRef = sema.typeMgr().addType(ty);
        sema.setType(sema.curNodeRef(), typeRef);

        return Result::Continue;
    }

    Result checkDRef(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& nodeView)
    {
        if (!nodeView.type->isPointer())
            return SemaError::raiseUnaryOperandType(sema, node, nodeView.nodeRef, nodeView.typeRef);
        return Result::Continue;
    }

    Result semaDRef(Sema& sema, AstUnaryExpr& node, const SemaNodeView& nodeView)
    {
        TypeRef resultTypeRef = nodeView.type->typeRef();
        if (nodeView.type->isConst())
        {
            const TypeInfo ty = sema.typeMgr().get(resultTypeRef);
            ty.flags().add(TypeInfoFlagsE::Const);
            resultTypeRef = sema.typeMgr().addType(ty);
        }

        sema.setType(sema.curNodeRef(), resultTypeRef);
        SemaInfo::setIsLValue(node);
        return Result::Continue;
    }

    Result checkMoveRef(Sema&, const AstUnaryExpr&, const SemaNodeView&)
    {
        return Result::Continue;
    }

    Result check(Sema& sema, TokenId op, const AstUnaryExpr& node, const SemaNodeView& ops)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return checkMinus(sema, node, ops);
            case TokenId::SymPlus:
                return checkPlus(sema, node, ops);
            case TokenId::SymBang:
                return checkBang(sema, node, ops);
            case TokenId::SymTilde:
                return checkTilde(sema, node, ops);
            case TokenId::SymAmpersand:
                return checkTakeAddress(sema, node, ops);
            case TokenId::KwdDRef:
                return checkDRef(sema, node, ops);
            case TokenId::KwdMoveRef:
                return checkMoveRef(sema, node, ops);
            default:
                return SemaError::raiseInternal(sema, node);
        }
    }
}

Result AstUnaryExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeView(sema, nodeExprRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));
    SemaInfo::setIsValue(*this);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    RESULT_VERIFY(check(sema, tok.id, *this, nodeView));

    // Constant folding
    if (sema.hasConstant(nodeExprRef))
    {
        ConstantRef result;
        RESULT_VERIFY(constantFold(sema, result, tok.id, *this, nodeView));
        sema.setConstant(sema.curNodeRef(), result);
        return Result::Continue;
    }

    switch (tok.id)
    {
        case TokenId::KwdDRef:
            return semaDRef(sema, *this, nodeView);
        case TokenId::KwdMoveRef:
            // TODO
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
            break;

        case TokenId::SymAmpersand:
            return semaTakeAddress(sema, *this, nodeView);

        default:
            sema.setType(sema.curNodeRef(), nodeView.typeRef);
            break;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
