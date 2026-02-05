#include "pch.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Attribute.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Runtime/Runtime.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

void SemaHelpers::handleSymbolRegistration(Sema& sema, SymbolMap* symbolMap, Symbol* sym)
{
    if (sym->isVariable())
    {
        if (const auto symStruct = symbolMap->safeCast<SymbolStruct>())
            symStruct->addField(reinterpret_cast<SymbolVariable*>(sym));

        if (sema.curScope().isParameters())
        {
            if (const auto symAttr = symbolMap->safeCast<SymbolAttribute>())
                symAttr->addParameter(reinterpret_cast<SymbolVariable*>(sym));
            if (const auto symFunc = symbolMap->safeCast<SymbolFunction>())
                symFunc->addParameter(reinterpret_cast<SymbolVariable*>(sym));
        }
    }

    if (sym->isFunction())
    {
        if (const auto symInterface = symbolMap->safeCast<SymbolInterface>())
            symInterface->addMethod(reinterpret_cast<SymbolFunction*>(sym));
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
                return Result::Continue;
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
    (void) nodeRef;
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

ConstantRef SemaHelpers::makeConstantLocation(Sema& sema, const AstNode& node)
{
    auto&                 ctx       = sema.ctx();
    const SourceCodeRange codeRange = node.codeRangeWithChildren(ctx, sema.ast());
    const TypeRef         typeRef   = sema.typeMgr().structSourceCodeLocation();

    Runtime::SourceCodeLocation rtLoc;

    const std::string_view nameView = sema.cstMgr().addString(ctx, codeRange.srcView->file()->path().string());
    rtLoc.fileName.ptr              = nameView.data();
    rtLoc.fileName.length           = nameView.size();

    rtLoc.funcName.ptr    = nullptr;
    rtLoc.funcName.length = 0;

    rtLoc.lineStart = codeRange.line;
    rtLoc.colStart  = codeRange.column;
    rtLoc.lineEnd   = codeRange.line;
    rtLoc.colEnd    = codeRange.column + codeRange.len;

    const auto view   = ByteSpan{reinterpret_cast<const std::byte*>(&rtLoc), sizeof(rtLoc)};
    const auto cstVal = ConstantValue::makeStruct(ctx, typeRef, view);
    return sema.cstMgr().addConstant(ctx, cstVal);
}

Result SemaHelpers::intrinsicCountOf(Sema& sema, AstNodeRef targetRef, AstNodeRef exprRef)
{
    auto               ctx = sema.ctx();
    const SemaNodeView nodeView(sema, exprRef);

    if (!nodeView.type)
        return SemaError::raise(sema, DiagnosticId::sema_err_invalid_countof, nodeView.nodeRef);

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
        RESULT_VERIFY(sema.waitCompleted(nodeView.type, nodeView.nodeRef));
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

    auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_countof_type, nodeView.nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
    diag.report(ctx);
    return Result::Error;
}

SWC_END_NAMESPACE();
