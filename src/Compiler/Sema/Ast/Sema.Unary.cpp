#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result constantFoldPlus(Sema& sema, ConstantRef& result, const SemaNodeView& nodeView)
    {
        auto& ctx = sema.ctx();

        if (nodeView.type->isInt())
        {
            ApsInt value = nodeView.cst->getInt();
            value.setUnsigned(true);
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, nodeView.type->payloadIntBits(), TypeInfo::Sign::Unsigned));
            return Result::Continue;
        }

        result = nodeView.cstRef;
        return Result::Continue;
    }

    Result constantFoldMinus(Sema& sema, ConstantRef& result, const SemaNodeView& nodeView)
    {
        // In the case of a literal with a suffix, it has already been done
        // @MinusLiteralSuffix
        if (nodeView.node->is(AstNodeId::SuffixLiteral))
        {
            result = nodeView.cstRef;
            return Result::Continue;
        }

        auto& ctx = sema.ctx();
        if (nodeView.type->isInt())
        {
            ApsInt value = nodeView.cst->getInt();

            bool overflow = false;
            value.negate(overflow);
            if (overflow)
                return SemaError::raiseLiteralOverflow(sema, nodeView.nodeRef, *nodeView.cst, nodeView.typeRef);

            value.setUnsigned(false);
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, nodeView.type->payloadIntBits(), TypeInfo::Sign::Signed));
            return Result::Continue;
        }

        if (nodeView.type->isFloat())
        {
            ApFloat value = nodeView.cst->getFloat();
            value.negate();
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, value, nodeView.type->payloadFloatBits()));
            return Result::Continue;
        }

        return Result::Error;
    }

    Result constantFoldBang(Sema& sema, ConstantRef& result, const SemaNodeView& nodeView)
    {
        const auto& cstMgr = sema.cstMgr();

        if (nodeView.cst->isBool())
        {
            result = cstMgr.cstNegBool(nodeView.cstRef);
            return Result::Continue;
        }

        if (nodeView.cst->isInt())
        {
            result = cstMgr.cstBool(nodeView.cst->getInt().isZero());
            return Result::Continue;
        }

        if (nodeView.cst->isChar())
        {
            result = cstMgr.cstBool(nodeView.cst->getChar());
            return Result::Continue;
        }

        if (nodeView.cst->isRune())
        {
            result = cstMgr.cstBool(nodeView.cst->getRune());
            return Result::Continue;
        }

        if (nodeView.cst->isString())
        {
            result = cstMgr.cstFalse();
            return Result::Continue;
        }

        SWC_INTERNAL_ERROR();
    }

    Result constantFoldTilde(Sema& sema, ConstantRef& result, const AstUnaryExpr&, const SemaNodeView& nodeView)
    {
        auto&  ctx   = sema.ctx();
        ApsInt value = nodeView.cst->getInt();
        value.invertAllBits();
        result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, nodeView.type->payloadIntBits(), nodeView.type->payloadIntSign()));
        return Result::Continue;
    }

    Result constantFold(Sema& sema, ConstantRef& result, TokenId op, const AstUnaryExpr& node, const SemaNodeView& nodeView)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return constantFoldMinus(sema, result, nodeView);
            case TokenId::SymPlus:
                return constantFoldPlus(sema, result, nodeView);
            case TokenId::SymBang:
                return constantFoldBang(sema, result, nodeView);
            case TokenId::SymTilde:
                return constantFoldTilde(sema, result, node, nodeView);
            default:
                break;
        }

        return Result::Error;
    }

    Result reportInvalidType(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& nodeView)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_unary_operand_type, expr.codeRef());
        diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result checkMinus(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& nodeView)
    {
        if (nodeView.type->isFloat() || nodeView.type->isIntSigned() || nodeView.type->isIntUnsized())
            return Result::Continue;

        if (nodeView.type->isIntUnsigned())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_negate_unsigned, expr.codeRef());
            diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        return reportInvalidType(sema, expr, nodeView);
    }

    Result checkPlus(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& nodeView)
    {
        if (nodeView.type->isFloat() || nodeView.type->isIntUnsigned() || nodeView.type->isIntUnsized())
            return Result::Continue;

        if (nodeView.type->isIntSigned())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_negate_unsigned, expr.codeRef());
            diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        return reportInvalidType(sema, expr, nodeView);
    }

    Result checkBang(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& nodeView)
    {
        if (nodeView.type->isConvertibleToBool())
            return Result::Continue;
        return reportInvalidType(sema, expr, nodeView);
    }

    Result checkTilde(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& nodeView)
    {
        if (nodeView.type->isInt())
            return Result::Continue;
        return reportInvalidType(sema, expr, nodeView);
    }

    Result checkTakeAddress(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& nodeView)
    {
        if (nodeView.cstRef.isValid())
        {
            const auto            diag      = SemaError::report(sema, DiagnosticId::sema_err_take_address_constant, node.codeRef());
            const SourceCodeRange codeRange = sema.node(nodeView.nodeRef).codeRangeWithChildren(sema.ctx(), sema.ast());
            diag.last().addSpan(codeRange, "", DiagnosticSeverity::Note);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!sema.isLValue(*nodeView.node))
        {
            const auto            diag      = SemaError::report(sema, DiagnosticId::sema_err_take_address_not_lvalue, node.codeRef());
            const SourceCodeRange codeRange = sema.node(nodeView.nodeRef).codeRangeWithChildren(sema.ctx(), sema.ast());
            diag.last().addSpan(codeRange, "", DiagnosticSeverity::Note);
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
            const SymbolVariable& symVar = nodeView.sym->cast<SymbolVariable>();
            if (symVar.hasExtraFlag(SymbolVariableFlagsE::Let))
                flags.add(TypeInfoFlagsE::Const);
        }

        bool blockPointer = false;
        if (nodeView.type->isArray())
            blockPointer = true;

        // TODO @legacy &arr[0] should be a value pointer, not a block pointer
        if (const auto* idxExpr = nodeView.node->safeCast<AstIndexExpr>())
        {
            const SemaNodeView baseView = sema.nodeView(idxExpr->nodeExprRef);
            if (baseView.type && baseView.type->isArray())
                blockPointer = true;
        }

        const TypeInfo& ty      = blockPointer ? TypeInfo::makeBlockPointer(nodeView.typeRef, flags) : TypeInfo::makeValuePointer(nodeView.typeRef, flags);
        const TypeRef   typeRef = sema.typeMgr().addType(ty);
        sema.setType(sema.curNodeRef(), typeRef);

        return Result::Continue;
    }

    Result semaBang(Sema& sema, const AstUnaryExpr&, SemaNodeView& nodeView)
    {
        RESULT_VERIFY(Cast::cast(sema, nodeView, sema.typeMgr().typeBool(), CastKind::Condition));
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
        return Result::Continue;
    }

    Result checkDRef(Sema& sema, const SemaNodeView& nodeView)
    {
        if (!nodeView.type->isAnyPointer())
            return SemaError::raiseUnaryOperandType(sema, sema.curNodeRef(), nodeView.nodeRef, nodeView.typeRef);
        return Result::Continue;
    }

    Result semaDRef(Sema& sema, AstUnaryExpr& node, const SemaNodeView& nodeView)
    {
        TypeRef resultTypeRef = nodeView.type->payloadTypeRef();
        if (nodeView.type->isConst())
        {
            const TypeInfo ty = sema.typeMgr().get(resultTypeRef);
            ty.flags().add(TypeInfoFlagsE::Const);
            resultTypeRef = sema.typeMgr().addType(ty);
        }

        RESULT_VERIFY(sema.waitSemaCompleted(&sema.typeMgr().get(resultTypeRef), node.nodeExprRef));
        sema.setType(sema.curNodeRef(), resultTypeRef);
        sema.setIsLValue(node);
        return Result::Continue;
    }

    Result checkMoveRef(Sema& sema, const AstUnaryExpr&, const SemaNodeView& nodeView)
    {
        if (nodeView.type->isAnyPointer() || nodeView.type->isReference())
            return Result::Continue;
        return SemaError::raiseUnaryOperandType(sema, sema.curNodeRef(), nodeView.nodeRef, nodeView.typeRef);
    }

    Result semaMoveRef(Sema& sema, const SemaNodeView& nodeView)
    {
        TypeInfoFlags flags = TypeInfoFlagsE::Zero;
        if (nodeView.type->isConst())
            flags.add(TypeInfoFlagsE::Const);

        TypeRef pointeeTypeRef = TypeRef::invalid();
        if (nodeView.type->isReference() || nodeView.type->isAnyPointer())
            pointeeTypeRef = nodeView.type->payloadTypeRef();

        SWC_ASSERT(pointeeTypeRef.isValid());
        const TypeInfo ty      = TypeInfo::makeMoveReference(pointeeTypeRef, flags);
        const TypeRef  typeRef = sema.typeMgr().addType(ty);
        sema.setType(sema.curNodeRef(), typeRef);
        return Result::Continue;
    }

    Result promote(Sema& sema, TokenId op, SemaNodeView& nodeView)
    {
        if (op == TokenId::SymTilde)
        {
            if (nodeView.type->isEnum())
            {
                if (!nodeView.type->isEnumFlags())
                    return SemaError::raiseInvalidOpEnum(sema, sema.curNodeRef(), nodeView.nodeRef, nodeView.typeRef);
                Cast::convertEnumToUnderlying(sema, nodeView);
            }
        }

        return Result::Continue;
    }

    Result check(Sema& sema, TokenId op, const AstUnaryExpr& node, const SemaNodeView& nodeView)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return checkMinus(sema, node, nodeView);
            case TokenId::SymPlus:
                return checkPlus(sema, node, nodeView);
            case TokenId::SymBang:
                return checkBang(sema, node, nodeView);
            case TokenId::SymTilde:
                return checkTilde(sema, node, nodeView);
            case TokenId::SymAmpersand:
                return checkTakeAddress(sema, node, nodeView);
            case TokenId::KwdDRef:
                return checkDRef(sema, nodeView);
            case TokenId::KwdMoveRef:
                return checkMoveRef(sema, node, nodeView);
            default:
                SWC_INTERNAL_ERROR();
        }
    }
}

Result AstUnaryExpr::semaPostNode(Sema& sema)
{
    SemaNodeView nodeView = sema.nodeView(nodeExprRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));
    sema.setIsValue(*this);

    // Force types
    const Token& tok = sema.token(codeRef());
    RESULT_VERIFY(promote(sema, tok.id, nodeView));

    // Type-check
    RESULT_VERIFY(check(sema, tok.id, *this, nodeView));

    // Constant folding
    if (nodeView.cstRef.isValid())
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
        case TokenId::SymAmpersand:
            return semaTakeAddress(sema, *this, nodeView);
        case TokenId::SymBang:
            return semaBang(sema, *this, nodeView);
        case TokenId::KwdMoveRef:
            return semaMoveRef(sema, nodeView);
        case TokenId::SymPlus:
        case TokenId::SymMinus:
        case TokenId::SymTilde:
            sema.setType(sema.curNodeRef(), nodeView.typeRef);
            break;

        default:
            SWC_INTERNAL_ERROR();
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
