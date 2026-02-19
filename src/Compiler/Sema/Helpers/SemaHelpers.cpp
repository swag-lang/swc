#include "pch.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.impl.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

void SemaHelpers::handleSymbolRegistration(Sema& sema, SymbolMap* symbolMap, Symbol* sym)
{
    if (SymbolVariable* symVar = sym->safeCast<SymbolVariable>())
    {
        if (const auto symStruct = symbolMap->safeCast<SymbolStruct>())
            symStruct->addField(symVar);

        if (sema.curScope().isParameters())
        {
            symVar->addExtraFlag(SymbolVariableFlagsE::Parameter);
            if (const auto symFunc = symbolMap->safeCast<SymbolFunction>())
                symFunc->addParameter(symVar);
        }
    }

    if (SymbolFunction* symFunc = sym->safeCast<SymbolFunction>())
    {
        if (const auto symInterface = symbolMap->safeCast<SymbolInterface>())
            symInterface->addFunction(symFunc);
        if (const auto symImpl = symbolMap->safeCast<SymbolImpl>())
            symImpl->addFunction(sema.ctx(), symFunc);
    }
}

Result SemaHelpers::checkBinaryOperandTypes(Sema& sema, AstNodeRef nodeRef, TokenId op, AstNodeRef leftRef, AstNodeRef rightRef, const SemaNodeView& leftView, const SemaNodeView& rightView)
{
    switch (op)
    {
        case TokenId::SymPlus:
            if (leftView.type->isValuePointer())
                return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, leftRef, leftView.typeRef);
            if (rightView.type->isValuePointer())
                return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, rightRef, rightView.typeRef);

            if (leftView.type->isBlockPointer() && leftView.type->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, leftRef, leftView.typeRef);
            if (rightView.type->isBlockPointer() && rightView.type->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, rightRef, rightView.typeRef);

            if (leftView.type->isBlockPointer() && rightView.type->isScalarNumeric())
                return Result::Continue;
            if (leftView.type->isBlockPointer() && rightView.type->isBlockPointer())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef, rightView.typeRef);
            if (leftView.type->isScalarNumeric() && rightView.type->isBlockPointer())
                return Result::Continue;
            break;

        case TokenId::SymMinus:
            if (leftView.type->isValuePointer())
                return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, leftRef, leftView.typeRef);
            if (rightView.type->isValuePointer())
                return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, rightRef, rightView.typeRef);

            if (leftView.type->isBlockPointer() && leftView.type->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, leftRef, leftView.typeRef);
            if (rightView.type->isBlockPointer() && rightView.type->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, rightRef, rightView.typeRef);

            if (leftView.type->isBlockPointer() && rightView.type->isScalarNumeric())
                return Result::Continue;
            if (leftView.type->isBlockPointer() && rightView.type->isBlockPointer())
                return Result::Continue;
            break;

        default:
            break;
    }

    switch (op)
    {
        case TokenId::SymSlash:
        case TokenId::SymPercent:
        case TokenId::SymPlus:
        case TokenId::SymMinus:
        case TokenId::SymAsterisk:
            if (!leftView.type->isScalarNumeric())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, leftRef, leftView.typeRef, rightView.typeRef);
            if (!rightView.type->isScalarNumeric())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef, rightView.typeRef);
            break;

        case TokenId::SymAmpersand:
        case TokenId::SymPipe:
        case TokenId::SymCircumflex:
        case TokenId::SymGreaterGreater:
        case TokenId::SymLowerLower:
            if (op == TokenId::SymAmpersand || op == TokenId::SymPipe || op == TokenId::SymCircumflex)
            {
                const bool leftEnumFlags  = leftView.type->isEnumFlags();
                const bool rightEnumFlags = rightView.type->isEnumFlags();
                if (leftEnumFlags && rightEnumFlags && leftView.typeRef == rightView.typeRef)
                    break;
            }

            if (!leftView.type->isInt())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, leftRef, leftView.typeRef, rightView.typeRef);
            if (!rightView.type->isInt())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef, rightView.typeRef);
            break;

        default:
            break;
    }

    return Result::Continue;
}

Result SemaHelpers::castBinaryRightToLeft(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& leftView, SemaNodeView& rightView, CastKind castKind)
{
    SWC_UNUSED(nodeRef);
    switch (op)
    {
        case TokenId::SymPlus:
        case TokenId::SymMinus:
            if (leftView.type->isBlockPointer() && rightView.type->isScalarNumeric())
            {
                RESULT_VERIFY(Cast::cast(sema, rightView, sema.typeMgr().typeS64(), CastKind::Implicit));
                return Result::Continue;
            }
            if (leftView.type->isScalarNumeric() && rightView.type->isBlockPointer())
            {
                return Result::Continue;
            }
            if (leftView.type->isBlockPointer() && rightView.type->isBlockPointer())
            {
                return Result::Continue;
            }
            break;

        default:
            break;
    }

    RESULT_VERIFY(Cast::cast(sema, rightView, leftView.typeRef, castKind));
    return Result::Continue;
}

Result SemaHelpers::intrinsicCountOf(Sema& sema, AstNodeRef targetRef, AstNodeRef exprRef)
{
    auto               ctx = sema.ctx();
    const SemaNodeView nodeView = sema.nodeViewTypeConstant(exprRef);

    if (!nodeView.type)
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, nodeView.nodeRef);

    if (nodeView.cst)
    {
        if (nodeView.cst->isString())
        {
            sema.setConstant(targetRef, sema.cstMgr().addInt(ctx, nodeView.cst->getString().length()));
            return Result::Continue;
        }

        if (nodeView.cst->isSlice())
        {
            sema.setConstant(targetRef, sema.cstMgr().addInt(ctx, nodeView.cst->getSlice().size()));
            return Result::Continue;
        }

        if (nodeView.cst->isInt())
        {
            if (nodeView.cst->getInt().isNegative())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_count_negative, nodeView.nodeRef);
                diag.addArgument(Diagnostic::ARG_VALUE, nodeView.cst->toString(ctx));
                diag.report(ctx);
                return Result::Error;
            }

            ConstantRef newCstRef;
            RESULT_VERIFY(Cast::concretizeConstant(sema, newCstRef, nodeView.nodeRef, nodeView.cstRef, TypeInfo::Sign::Unsigned));
            sema.setConstant(targetRef, newCstRef);
            return Result::Continue;
        }
    }

    if (nodeView.type->isEnum())
    {
        RESULT_VERIFY(sema.waitSemaCompleted(nodeView.type, nodeView.nodeRef));
        sema.setConstant(targetRef, sema.cstMgr().addInt(ctx, nodeView.type->payloadSymEnum().count()));
        return Result::Continue;
    }

    if (nodeView.type->isAnyString())
    {
        sema.setType(targetRef, sema.typeMgr().typeU64());
        sema.setIsValue(targetRef);
        return Result::Continue;
    }

    if (nodeView.type->isArray())
    {
        const uint64_t  sizeOf     = nodeView.type->sizeOf(ctx);
        const TypeRef   typeRef    = nodeView.type->payloadArrayElemTypeRef();
        const TypeInfo& ty         = sema.typeMgr().get(typeRef);
        const uint64_t  sizeOfElem = ty.sizeOf(ctx);
        SWC_ASSERT(sizeOfElem > 0);
        sema.setConstant(targetRef, sema.cstMgr().addInt(ctx, sizeOf / sizeOfElem));
        return Result::Continue;
    }

    if (nodeView.type->isSlice())
    {
        sema.setType(targetRef, sema.typeMgr().typeU64());
        sema.setIsValue(targetRef);
        return Result::Continue;
    }

    if (nodeView.type->isIntUnsigned())
    {
        sema.setType(targetRef, nodeView.typeRef);
        sema.setIsValue(targetRef);
        return Result::Continue;
    }

    auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_countof_type, nodeView.nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
    diag.report(ctx);
    return Result::Error;
}

Result SemaHelpers::finalizeAggregateStruct(Sema& sema, const SmallVector<AstNodeRef>& children)
{
    SmallVector<TypeRef>       memberTypes;
    SmallVector<IdentifierRef> memberNames;
    memberTypes.reserve(children.size());
    memberNames.reserve(children.size());

    bool                     allConstant = true;
    SmallVector<ConstantRef> values;
    values.reserve(children.size());

    for (const AstNodeRef& child : children)
    {
        const AstNode& childNode = sema.node(child);
        if (childNode.is(AstNodeId::NamedArgument))
            memberNames.push_back(sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef()));
        else
            memberNames.push_back(IdentifierRef::invalid());

        SemaNodeView nodeView = sema.nodeViewTypeConstant(child);
        SWC_ASSERT(nodeView.typeRef.isValid());
        memberTypes.push_back(nodeView.typeRef);
        allConstant = allConstant && nodeView.cstRef.isValid();
        values.push_back(nodeView.cstRef);
    }

    if (allConstant)
    {
        const auto val = ConstantValue::makeAggregateStruct(sema.ctx(), memberNames, values);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), val));
    }
    else
    {
        const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeAggregateStruct(memberNames, memberTypes));
        sema.setType(sema.curNodeRef(), typeRef);
    }

    sema.setIsValue(sema.curNodeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
