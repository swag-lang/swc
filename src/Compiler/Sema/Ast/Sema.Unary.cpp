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
    Result constantFoldPlus(Sema& sema, ConstantRef& result, const SemaNodeView& view)
    {
        const TaskContext& ctx = sema.ctx();

        if (view.type()->isInt())
        {
            ApsInt value = view.cst()->getInt();
            value.setUnsigned(true);
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, view.type()->payloadIntBits(), TypeInfo::Sign::Unsigned));
            return Result::Continue;
        }

        result = view.cstRef();
        return Result::Continue;
    }

    Result constantFoldMinus(Sema& sema, ConstantRef& result, const SemaNodeView& view)
    {
        // In the case of a literal with a suffix, it has already been done
        // @MinusLiteralSuffix
        if (view.node()->is(AstNodeId::SuffixLiteral))
        {
            result = view.cstRef();
            return Result::Continue;
        }

        const TaskContext& ctx = sema.ctx();
        if (view.type()->isInt())
        {
            ApsInt value = view.cst()->getInt();

            bool overflow = false;
            value.negate(overflow);
            if (overflow)
                return SemaError::raiseLiteralOverflow(sema, view.nodeRef(), *view.cst(), view.typeRef());

            value.setUnsigned(false);
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, view.type()->payloadIntBits(), TypeInfo::Sign::Signed));
            return Result::Continue;
        }

        if (view.type()->isFloat())
        {
            ApFloat value = view.cst()->getFloat();
            value.negate();
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, value, view.type()->payloadFloatBits()));
            return Result::Continue;
        }

        return Result::Error;
    }

    Result constantFoldBang(Sema& sema, ConstantRef& result, const SemaNodeView& view)
    {
        const ConstantManager& cstMgr = sema.cstMgr();

        if (view.cst()->isBool())
        {
            result = cstMgr.cstNegBool(view.cstRef());
            return Result::Continue;
        }

        if (view.cst()->isInt())
        {
            result = cstMgr.cstBool(view.cst()->getInt().isZero());
            return Result::Continue;
        }

        if (view.cst()->isChar())
        {
            result = cstMgr.cstBool(view.cst()->getChar());
            return Result::Continue;
        }

        if (view.cst()->isRune())
        {
            result = cstMgr.cstBool(view.cst()->getRune());
            return Result::Continue;
        }

        if (view.cst()->isString())
        {
            result = cstMgr.cstFalse();
            return Result::Continue;
        }

        SWC_INTERNAL_ERROR();
    }

    Result constantFoldTilde(Sema& sema, ConstantRef& result, const AstUnaryExpr& expr, const SemaNodeView& view)
    {
        SWC_UNUSED(expr);
        const TaskContext& ctx   = sema.ctx();
        ApsInt             value = view.cst()->getInt();
        value.invertAllBits();
        result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, view.type()->payloadIntBits(), view.type()->payloadIntSign()));
        return Result::Continue;
    }

    Result constantFold(Sema& sema, ConstantRef& result, TokenId op, const AstUnaryExpr& node, const SemaNodeView& view)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return constantFoldMinus(sema, result, view);
            case TokenId::SymPlus:
                return constantFoldPlus(sema, result, view);
            case TokenId::SymBang:
                return constantFoldBang(sema, result, view);
            case TokenId::SymTilde:
                return constantFoldTilde(sema, result, node, view);
            default:
                break;
        }

        return Result::Error;
    }

    Result reportInvalidType(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& view)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_unary_operand_type, expr.codeRef());
        diag.addArgument(Diagnostic::ARG_TYPE, view.typeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result checkMinus(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& view)
    {
        if (view.type()->isFloat() || view.type()->isIntSigned() || view.type()->isIntUnsized())
            return Result::Continue;

        if (view.type()->isIntUnsigned())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_negate_unsigned, expr.codeRef());
            diag.addArgument(Diagnostic::ARG_TYPE, view.typeRef());
            diag.report(sema.ctx());
            return Result::Error;
        }

        return reportInvalidType(sema, expr, view);
    }

    Result checkPlus(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& view)
    {
        if (view.type()->isFloat() || view.type()->isIntUnsigned() || view.type()->isIntUnsized())
            return Result::Continue;

        if (view.type()->isIntSigned())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_negate_unsigned, expr.codeRef());
            diag.addArgument(Diagnostic::ARG_TYPE, view.typeRef());
            diag.report(sema.ctx());
            return Result::Error;
        }

        return reportInvalidType(sema, expr, view);
    }

    Result checkBang(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& view)
    {
        if (view.type()->isConvertibleToBool())
            return Result::Continue;
        return reportInvalidType(sema, expr, view);
    }

    Result checkTilde(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& view)
    {
        if (view.type()->isInt())
            return Result::Continue;
        return reportInvalidType(sema, expr, view);
    }

    Result checkTakeAddress(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& view)
    {
        if (view.cstRef().isValid())
        {
            const auto            diag      = SemaError::report(sema, DiagnosticId::sema_err_take_address_constant, node.codeRef());
            const SourceCodeRange codeRange = sema.node(view.nodeRef()).codeRangeWithChildren(sema.ctx(), sema.ast());
            diag.last().addSpan(codeRange, "", DiagnosticSeverity::Note);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!sema.isLValue(*view.node()))
        {
            const auto            diag      = SemaError::report(sema, DiagnosticId::sema_err_take_address_not_lvalue, node.codeRef());
            const SourceCodeRange codeRange = sema.node(view.nodeRef()).codeRangeWithChildren(sema.ctx(), sema.ast());
            diag.last().addSpan(codeRange, "", DiagnosticSeverity::Note);
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Continue;
    }

    Result semaTakeAddress(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& view)
    {
        SWC_UNUSED(node);
        TypeInfoFlags flags = TypeInfoFlagsE::Zero;
        if (view.type()->isConst())
        {
            flags.add(TypeInfoFlagsE::Const);
        }
        else if (view.sym() && view.sym()->isVariable())
        {
            const SymbolVariable& symVar = view.sym()->cast<SymbolVariable>();
            if (symVar.hasExtraFlag(SymbolVariableFlagsE::Let))
                flags.add(TypeInfoFlagsE::Const);
        }

        bool blockPointer = false;
        if (view.type()->isArray())
            blockPointer = true;

        // TODO @legacy &arr[0] should be a value pointer, not a block pointer
        if (const AstIndexExpr* idxExpr = view.node()->safeCast<AstIndexExpr>())
        {
            const SemaNodeView baseView = sema.viewType(idxExpr->nodeExprRef);
            if (baseView.type() && baseView.type()->isArray())
                blockPointer = true;
        }

        const TypeInfo& ty      = blockPointer ? TypeInfo::makeBlockPointer(view.typeRef(), flags) : TypeInfo::makeValuePointer(view.typeRef(), flags);
        const TypeRef   typeRef = sema.typeMgr().addType(ty);
        sema.setType(sema.curNodeRef(), typeRef);

        return Result::Continue;
    }

    Result semaBang(Sema& sema, const AstUnaryExpr& node, SemaNodeView& view)
    {
        SWC_UNUSED(node);
        RESULT_VERIFY(Cast::cast(sema, view, sema.typeMgr().typeBool(), CastKind::Condition));
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
        return Result::Continue;
    }

    Result checkDRef(Sema& sema, const SemaNodeView& view)
    {
        if (!view.type()->isAnyPointer())
            return SemaError::raiseUnaryOperandType(sema, sema.curNodeRef(), view.nodeRef(), view.typeRef());
        return Result::Continue;
    }

    Result semaDRef(Sema& sema, AstUnaryExpr& node, const SemaNodeView& view)
    {
        TypeRef resultTypeRef = view.type()->payloadTypeRef();
        if (view.type()->isConst())
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

    Result checkMoveRef(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& view)
    {
        SWC_UNUSED(node);
        if (view.type()->isAnyPointer() || view.type()->isReference())
            return Result::Continue;
        return SemaError::raiseUnaryOperandType(sema, sema.curNodeRef(), view.nodeRef(), view.typeRef());
    }

    Result semaMoveRef(Sema& sema, const SemaNodeView& view)
    {
        TypeInfoFlags flags = TypeInfoFlagsE::Zero;
        if (view.type()->isConst())
            flags.add(TypeInfoFlagsE::Const);

        TypeRef pointeeTypeRef = TypeRef::invalid();
        if (view.type()->isReference() || view.type()->isAnyPointer())
            pointeeTypeRef = view.type()->payloadTypeRef();

        SWC_ASSERT(pointeeTypeRef.isValid());
        const TypeInfo ty      = TypeInfo::makeMoveReference(pointeeTypeRef, flags);
        const TypeRef  typeRef = sema.typeMgr().addType(ty);
        sema.setType(sema.curNodeRef(), typeRef);
        return Result::Continue;
    }

    Result promote(Sema& sema, TokenId op, SemaNodeView& view)
    {
        if (op == TokenId::SymTilde)
        {
            if (view.type()->isEnum())
            {
                if (!view.type()->isEnumFlags())
                    return SemaError::raiseInvalidOpEnum(sema, sema.curNodeRef(), view.nodeRef(), view.typeRef());
                Cast::convertEnumToUnderlying(sema, view);
            }
        }

        return Result::Continue;
    }

    Result check(Sema& sema, TokenId op, const AstUnaryExpr& node, const SemaNodeView& view)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return checkMinus(sema, node, view);
            case TokenId::SymPlus:
                return checkPlus(sema, node, view);
            case TokenId::SymBang:
                return checkBang(sema, node, view);
            case TokenId::SymTilde:
                return checkTilde(sema, node, view);
            case TokenId::SymAmpersand:
                return checkTakeAddress(sema, node, view);
            case TokenId::KwdDRef:
                return checkDRef(sema, view);
            case TokenId::KwdMoveRef:
                return checkMoveRef(sema, node, view);
            default:
                SWC_INTERNAL_ERROR();
        }
    }
}

Result AstUnaryExpr::semaPostNode(Sema& sema)
{
    SemaNodeView view = sema.viewNodeTypeConstantSymbol(nodeExprRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, view.nodeRef()));
    sema.setIsValue(*this);

    // Force types
    const Token& tok = sema.token(codeRef());
    RESULT_VERIFY(promote(sema, tok.id, view));

    // Type-check
    RESULT_VERIFY(check(sema, tok.id, *this, view));

    // Constant folding
    if (view.cstRef().isValid())
    {
        ConstantRef result;
        RESULT_VERIFY(constantFold(sema, result, tok.id, *this, view));
        sema.setConstant(sema.curNodeRef(), result);
        return Result::Continue;
    }

    switch (tok.id)
    {
        case TokenId::KwdDRef:
            return semaDRef(sema, *this, view);
        case TokenId::SymAmpersand:
            return semaTakeAddress(sema, *this, view);
        case TokenId::SymBang:
            return semaBang(sema, *this, view);
        case TokenId::KwdMoveRef:
            return semaMoveRef(sema, view);
        case TokenId::SymPlus:
        case TokenId::SymMinus:
        case TokenId::SymTilde:
            sema.setType(sema.curNodeRef(), view.typeRef());
            break;

        default:
            SWC_INTERNAL_ERROR();
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
