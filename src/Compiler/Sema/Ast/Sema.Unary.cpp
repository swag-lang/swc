#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const TypeInfo& aliasEnumType(Sema& sema, const SemaNodeView& view)
    {
        const TypeRef typeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), view.typeRef());
        SWC_ASSERT(typeRef.isValid());
        return sema.typeMgr().get(typeRef);
    }

    const TypeInfo& aliasType(Sema& sema, const SemaNodeView& view)
    {
        const TypeRef typeRef = sema.typeMgr().get(view.typeRef()).unwrap(sema.ctx(), view.typeRef(), TypeExpandE::Alias);
        SWC_ASSERT(typeRef.isValid());
        return sema.typeMgr().get(typeRef);
    }

    Result constantFoldPlus(Sema& sema, ConstantRef& result, const SemaNodeView& view)
    {
        if (view.type()->isInt())
        {
            ApsInt                 foldedValue;
            const Math::FoldStatus foldStatus = Math::foldUnaryInt(foldedValue, view.cst()->getInt(), Math::FoldUnaryOp::Plus);
            SWC_ASSERT(foldStatus == Math::FoldStatus::Ok);
            result = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeInt(sema.ctx(), foldedValue, view.type()->payloadIntBits(), view.type()->payloadIntSign()));
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

        const TypeInfo& type = aliasType(sema, view);
        if (type.isInt())
        {
            ApsInt                 foldedValue;
            const Math::FoldStatus foldStatus = Math::foldUnaryInt(foldedValue, view.cst()->getInt(), Math::FoldUnaryOp::Minus);
            if (foldStatus == Math::FoldStatus::Overflow)
                return SemaError::raiseLiteralOverflow(sema, view.nodeRef(), *view.cst(), view.typeRef());
            if (foldStatus != Math::FoldStatus::Ok)
            {
                if (Math::isSafetyError(foldStatus))
                    return SemaError::raiseFoldSafety(sema, foldStatus, sema.curNodeRef(), view.nodeRef(), SemaError::ReportLocation::Token);
                return Result::Error;
            }

            ConstantValue resultValue = ConstantValue::makeInt(sema.ctx(), foldedValue, type.payloadIntBits(), TypeInfo::Sign::Signed);
            if (view.type()->isAlias())
                resultValue.setTypeRef(view.typeRef());
            result = sema.cstMgr().addConstant(sema.ctx(), resultValue);
            return Result::Continue;
        }

        if (type.isFloat())
        {
            ApFloat                foldedValue;
            const Math::FoldStatus foldStatus = Math::foldUnaryFloat(foldedValue, view.cst()->getFloat(), Math::FoldUnaryOp::Minus);
            SWC_ASSERT(foldStatus == Math::FoldStatus::Ok);

            ConstantValue resultValue = ConstantValue::makeFloat(sema.ctx(), foldedValue, type.payloadFloatBits());
            if (view.type()->isAlias())
                resultValue.setTypeRef(view.typeRef());
            result = sema.cstMgr().addConstant(sema.ctx(), resultValue);
            return Result::Continue;
        }

        SWC_UNREACHABLE();
    }

    Result constantFoldBang(Sema& sema, ConstantRef& result, const SemaNodeView& view)
    {
        CastRequest castRequest(CastKind::BoolExpr);
        castRequest.errorNodeRef = view.nodeRef();
        castRequest.setConstantFoldingSrc(view.cstRef());
        const Result castResult = Cast::castAllowed(sema, castRequest, view.typeRef(), sema.typeMgr().typeBool());
        if (castResult != Result::Continue)
        {
            if (castResult == Result::Error)
                return Cast::emitCastFailure(sema, castRequest.failure);
            return castResult;
        }

        SWC_ASSERT(castRequest.constantFoldingResult().isValid());
        result = sema.cstMgr().cstNegBool(castRequest.constantFoldingResult());
        return Result::Continue;
    }

    Result constantFoldTilde(Sema& sema, ConstantRef& result, const AstUnaryExpr& expr, const SemaNodeView& view)
    {
        SWC_UNUSED(expr);
        const TypeInfo& valueType    = aliasType(sema, view);
        const TypeInfo* storageType  = &valueType;
        ConstantRef     storageCstRef = view.cstRef();

        if (valueType.isEnum())
        {
            SWC_ASSERT(valueType.isEnumFlags());
            const ConstantValue& enumValue = sema.cstMgr().get(storageCstRef);
            if (enumValue.isEnumValue())
                storageCstRef = enumValue.getEnumValue();
            storageType = &sema.typeMgr().get(valueType.payloadSymEnum().underlyingTypeRef());
        }

        const ConstantValue& storageCst = sema.cstMgr().get(storageCstRef);
        ApsInt                 foldedValue;
        const Math::FoldStatus foldStatus = Math::foldUnaryInt(foldedValue, storageCst.getIntLike(), Math::FoldUnaryOp::BitwiseNot);
        SWC_ASSERT(foldStatus == Math::FoldStatus::Ok);

        SWC_ASSERT(storageType->isIntLike());
        ConstantValue resultValue = ConstantValue::makeFromIntLike(sema.ctx(), foldedValue, *storageType);
        if (valueType.isEnum())
        {
            const ConstantRef underlyingRef = sema.cstMgr().addConstant(sema.ctx(), resultValue);
            const ConstantValue enumValue  = ConstantValue::makeEnumValue(sema.ctx(), underlyingRef, view.typeRef());
            result                         = sema.cstMgr().addConstant(sema.ctx(), enumValue);
            return Result::Continue;
        }

        if (view.type()->isAlias())
            resultValue.setTypeRef(view.typeRef());
        result = sema.cstMgr().addConstant(sema.ctx(), resultValue);
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
                return Result::Error; // This is ok
        }
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
        const TypeInfo& type = aliasType(sema, view);
        if (type.isFloat() || type.isIntSigned() || type.isIntUnsized())
            return Result::Continue;

        if (type.isIntUnsigned())
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
        SWC_UNUSED(expr);
        const TypeInfo& type = aliasType(sema, view);
        if (type.isFloat() || type.isIntLike())
            return Result::Continue;

        return reportInvalidType(sema, expr, view);
    }

    Result checkBang(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& view)
    {
        if (view.type()->isConvertibleToBoolAliasAware(sema.ctx()))
            return Result::Continue;
        return reportInvalidType(sema, expr, view);
    }

    Result checkTilde(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& view)
    {
        const TypeInfo& type = aliasType(sema, view);
        if (type.isIntLike() || type.isEnum())
            return Result::Continue;
        return reportInvalidType(sema, expr, view);
    }

    // Returns true when the operand of '&' is an index into a constant with
    // data-segment storage (array or struct). The data has a real address even
    // though the element value is known at compile time.
    bool isAddressableConstantIndex(Sema& sema, const SemaNodeView& view)
    {
        if (!view.node() || !view.node()->is(AstNodeId::IndexExpr))
            return false;
        const auto&        idxExpr  = view.node()->cast<AstIndexExpr>();
        const SemaNodeView baseView = sema.viewTypeConstant(idxExpr.nodeExprRef);
        if (!baseView.hasConstant() || baseView.typeRef().isInvalid())
            return false;

        const TypeRef baseTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), baseView.typeRef());
        return sema.typeMgr().get(baseTypeRef).isArray();
    }

    Result checkTakeAddress(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& view)
    {
        SWC_ASSERT(view.node() != nullptr);
        if (!sema.isLValue(*view.node()) && !isAddressableConstantIndex(sema, view))
        {
            const DiagnosticId diagId = view.cstRef().isValid() ? DiagnosticId::sema_err_take_address_constant : DiagnosticId::sema_err_take_address_not_lvalue;
            auto               diag   = SemaError::report(sema, diagId, node.codeRef());
            if (diagId == DiagnosticId::sema_err_take_address_not_lvalue)
            {
                diag.addNote(DiagnosticId::sema_note_expression_not_addressable);
                SemaError::addSpan(sema, diag.last(), view.nodeRef());
            }
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Continue;
    }

    bool isCallLikeNode(const AstNode& node)
    {
        return node.is(AstNodeId::CallExpr) ||
               node.is(AstNodeId::IntrinsicCallExpr) ||
               node.is(AstNodeId::AliasCallExpr) ||
               node.is(AstNodeId::CompilerCall) ||
               node.is(AstNodeId::CompilerCallOne);
    }

    bool isFunctionAddressOperand(const SemaNodeView& view)
    {
        return view.sym() &&
               view.sym()->isFunction() &&
               view.node() &&
               !isCallLikeNode(*view.node());
    }

    Result semaTakeAddress(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& view)
    {
        SWC_UNUSED(node);
        if (isFunctionAddressOperand(view))
        {
            auto& symFunc = view.sym()->cast<SymbolFunction>();
            SemaHelpers::addCurrentFunctionCallDependency(sema, &symFunc);

            sema.setType(sema.curNodeRef(), view.typeRef());
            return Result::Continue;
        }

        if (view.sym() && view.sym()->isVariable() && view.type() && !view.type()->isReference())
        {
            auto& symVar = view.sym()->cast<SymbolVariable>();
            if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
                symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
                symVar.addExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);
        }

        TypeRef pointeeTypeRef = view.typeRef();
        if (view.type()->isReference())
            pointeeTypeRef = view.type()->payloadTypeRef();

        TypeInfoFlags flags = TypeInfoFlagsE::Zero;
        if (view.type()->isReference() && view.type()->isConst())
            flags.add(TypeInfoFlagsE::Const);
        if (SemaCheck::isConstAssignmentTarget(sema, view.nodeRef(), view))
            flags.add(TypeInfoFlagsE::Const);
        if ((view.sym() && (view.sym()->isLetVariable() || view.sym()->isConstant())) ||
            (view.node() && sema.isLValue(*view.node()) && view.cstRef().isValid()))
            flags.add(TypeInfoFlagsE::Const);

        bool blockPointer = false;
        if (pointeeTypeRef.isValid())
        {
            const TypeRef storageTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), pointeeTypeRef);
            if (sema.typeMgr().get(storageTypeRef).isArray())
                blockPointer = true;
        }

        const TypeInfo& ty      = blockPointer ? TypeInfo::makeBlockPointer(pointeeTypeRef, flags) : TypeInfo::makeValuePointer(pointeeTypeRef, flags);
        const TypeRef   typeRef = sema.typeMgr().addType(ty);
        sema.setType(sema.curNodeRef(), typeRef);

        return Result::Continue;
    }

    Result semaBang(Sema& sema, const AstUnaryExpr& node, SemaNodeView& view)
    {
        SWC_UNUSED(node);
        SWC_RESULT(Cast::cast(sema, view, sema.typeMgr().typeBool(), CastKind::BoolExpr));
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
        return Result::Continue;
    }

    Result checkDRef(Sema& sema, const SemaNodeView& view)
    {
        const TypeInfo& type = aliasEnumType(sema, view);
        if (!type.isPointerOrReference())
            return SemaError::raiseUnaryOperandType(sema, sema.curNodeRef(), view.nodeRef(), view.typeRef());
        return Result::Continue;
    }

    Result semaDRef(Sema& sema, AstUnaryExpr& node, const SemaNodeView& view)
    {
        const TypeInfo& type          = aliasEnumType(sema, view);
        const TypeRef   resultTypeRef = type.dereferenceTypeRef(sema.ctx());

        SWC_RESULT(sema.waitSemaCompleted(&sema.typeMgr().get(resultTypeRef), node.nodeExprRef));
        sema.setType(sema.curNodeRef(), resultTypeRef);
        sema.setIsLValue(node);
        return Result::Continue;
    }

    Result checkMoveRef(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& view)
    {
        SWC_UNUSED(node);
        const TypeInfo& type = aliasEnumType(sema, view);
        if (type.isPointerOrReference())
            return Result::Continue;
        return SemaError::raiseUnaryOperandType(sema, sema.curNodeRef(), view.nodeRef(), view.typeRef());
    }

    Result semaMoveRef(Sema& sema, const SemaNodeView& view)
    {
        const TypeInfo& type  = aliasEnumType(sema, view);
        TypeInfoFlags flags = TypeInfoFlagsE::Zero;
        if (type.isConst())
            flags.add(TypeInfoFlagsE::Const);

        TypeRef pointeeTypeRef = TypeRef::invalid();
        if (type.isReference() || type.isAnyPointer())
            pointeeTypeRef = type.payloadTypeRef();

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
            const TypeInfo& type = aliasType(sema, view);
            if (type.isEnum())
            {
                if (!type.isEnumFlags())
                    return SemaError::raiseInvalidOpEnum(sema, sema.curNodeRef(), view.nodeRef(), view.typeRef());
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
    const Token& tok  = sema.token(codeRef());

    // Function declarations are addressable even if they are not plain value expressions.
    const bool takesFunctionAddress = tok.id == TokenId::SymAmpersand && isFunctionAddressOperand(view);
    if (!takesFunctionAddress)
        SWC_RESULT(SemaCheck::isValue(sema, view.nodeRef()));
    sema.setIsValue(*this);

    bool handledSpecialOp = false;
    SWC_RESULT(SemaSpecOp::tryResolveUnary(sema, *this, view, handledSpecialOp));
    if (handledSpecialOp)
        return Result::Continue;

    // Force types
    SWC_RESULT(promote(sema, tok.id, view));

    // Type-check
    SWC_RESULT(check(sema, tok.id, *this, view));

    // Taking the address of a constant array element: the element value was
    // constant-folded during index resolution, but the array data lives in the
    // data segment so the address is valid. Replace the scalar constant on the
    // index node with its type so codegen emits the element address instead of
    // the folded value.
    if (tok.id == TokenId::SymAmpersand && view.cstRef().isValid() && isAddressableConstantIndex(sema, view))
    {
        const TypeRef childTypeRef = view.typeRef();
        sema.setType(view.nodeRef(), childTypeRef);
        sema.setIsLValue(sema.node(view.nodeRef()));

        // The pointer is const because the underlying data belongs to a constant.
        const TypeInfo& ty      = TypeInfo::makeValuePointer(childTypeRef, TypeInfoFlagsE::Const);
        const TypeRef   typeRef = sema.typeMgr().addType(ty);
        sema.setType(sema.curNodeRef(), typeRef);
        return Result::Continue;
    }

    // Constant folding
    if (view.cstRef().isValid())
    {
        ConstantRef result;
        SWC_RESULT(constantFold(sema, result, tok.id, *this, view));
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

    if (tok.id == TokenId::SymMinus && aliasType(sema, view).isIntSigned())
        SWC_RESULT(SemaHelpers::setupRuntimeSafetyPanic(sema, sema.curNodeRef(), Runtime::SafetyWhat::Overflow, codeRef()));
    return Result::Continue;
}

SWC_END_NAMESPACE();
