#include "pch.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Helpers/SemaSymbolLookup.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbol.impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{

    TypeRef aliasEnumTypeRef(Sema& sema, TypeRef typeRef)
    {
        const TypeRef unwrappedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        SWC_ASSERT(unwrappedTypeRef.isValid());
        return unwrappedTypeRef;
    }

    const TypeInfo& aliasEnumType(Sema& sema, const SemaNodeView& view)
    {
        return sema.typeMgr().get(aliasEnumTypeRef(sema, view.typeRef()));
    }

    const TypeInfo& aliasType(Sema& sema, const SemaNodeView& view)
    {
        const TypeRef typeRef = sema.typeMgr().get(view.typeRef()).unwrap(sema.ctx(), view.typeRef(), TypeExpandE::Alias);
        SWC_ASSERT(typeRef.isValid());
        return sema.typeMgr().get(typeRef);
    }

    const SymbolEnum* enumSymbolFromTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return nullptr;

        const TypeRef   enumTypeRef = sema.typeMgr().get(typeRef).unwrap(sema.ctx(), typeRef, TypeExpandE::Alias);
        const TypeInfo& enumType    = sema.typeMgr().get(enumTypeRef);
        if (enumType.isEnum())
            return &enumType.payloadSymEnum();

        return nullptr;
    }

    bool isPointerOrReferenceAliasAware(Sema& sema, const SemaNodeView& view)
    {
        const TypeInfo& typeInfo = aliasEnumType(sema, view);
        return typeInfo.isAnyPointer() || typeInfo.isReference();
    }

    TypeRef countOfPassthroughTypeRef(TaskContext& ctx, TypeRef typeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
            if (typeInfo.isReference())
            {
                typeRef = typeInfo.payloadTypeRef();
                continue;
            }

            if (!typeInfo.isAlias())
                return typeRef;

            const TypeRef rawTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
            if (!rawTypeRef.isValid() || !ctx.typeMgr().get(rawTypeRef).isInt())
                return rawTypeRef;
            return typeRef;
        }

        return TypeRef::invalid();
    }

}

AstNodeRef SemaHelpers::unwrapCallCalleeRef(Sema& sema, AstNodeRef nodeRef)
{
    while (nodeRef.isValid())
    {
        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isValid() && resolvedRef != nodeRef)
        {
            nodeRef = resolvedRef;
            continue;
        }

        const AstNode& node = sema.node(nodeRef);
        if (node.is(AstNodeId::ParenExpr))
        {
            nodeRef = node.cast<AstParenExpr>().nodeExprRef;
            continue;
        }

        if (node.is(AstNodeId::QuotedExpr))
        {
            nodeRef = node.cast<AstQuotedExpr>().nodeExprRef;
            continue;
        }

        if (node.is(AstNodeId::QuotedListExpr))
        {
            nodeRef = node.cast<AstQuotedListExpr>().nodeExprRef;
            continue;
        }

        break;
    }

    return nodeRef;
}

const SymbolFunction* SemaHelpers::currentLocationFunction(const Sema& sema)
{
    const auto* inlinePayload = sema.frame().currentInlinePayload();
    if (inlinePayload && inlinePayload->sourceFunction)
        return SemaRuntime::transparentLocationFunction(inlinePayload->sourceFunction);

    return SemaRuntime::transparentLocationFunction(sema.currentFunction());
}

AstNodeRef SemaHelpers::defaultArgumentExprRef(const SymbolVariable& param)
{
    const AstNode* declNode = param.decl();
    if (!declNode)
        return AstNodeRef::invalid();

    if (const auto* singleVar = declNode->safeCast<AstSingleVarDecl>())
        return singleVar->nodeInitRef;

    if (const auto* multiVar = declNode->safeCast<AstMultiVarDecl>())
        return multiVar->nodeInitRef;

    return AstNodeRef::invalid();
}

bool SemaHelpers::isCallerLocationDefaultInitializer(Sema& sema, AstNodeRef initRef)
{
    if (initRef.isInvalid())
        return false;

    const AstNode& initNode = sema.node(initRef);
    if (!initNode.is(AstNodeId::CompilerLiteral))
        return false;

    const SourceCodeRef codeRef = initNode.codeRef();
    return codeRef.isValid() && sema.token(codeRef).id == TokenId::CompilerCallerLocation;
}

bool SemaHelpers::isDirectCallerLocationDefault(const Sema& /*sema*/, const SymbolVariable& param)
{
    return param.hasExtraFlag(SymbolVariableFlagsE::CallerLocationDefault);
}

void SemaHelpers::pushConstExprRequirement(Sema& sema, AstNodeRef childRef)
{
    SWC_ASSERT(childRef.isValid());
    auto frame = sema.frame();
    frame.addContextFlag(SemaFrameContextFlagsE::RequireConstExpr);
    sema.pushFramePopOnPostChild(frame, childRef);
}

IdentifierRef SemaHelpers::getUniqueIdentifier(Sema& sema, const std::string_view& name)
{
    const uint32_t id = sema.compiler().atomicId().fetch_add(1);
    return sema.idMgr().addIdentifierOwned(std::format("{}_{}", name, id));
}

IdentifierRef SemaHelpers::resolveIdentifier(Sema& sema, const SourceCodeRef& codeRef)
{
    const Token& tok = sema.srcView(codeRef.srcViewRef).token(codeRef.tokRef);
    if (Token::isCompilerUniq(tok.id))
        return resolveUniqIdentifier(sema, tok.id);

    if (Token::isCompilerAlias(tok.id))
    {
        const IdentifierRef idRef = resolveAliasIdentifier(sema, tok.id);
        if (idRef.isValid())
            return idRef;
    }

    return sema.idMgr().addIdentifier(sema.ctx(), codeRef);
}

uint32_t SemaHelpers::aliasSlotIndex(const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerAlias(tokenId));
    return static_cast<uint32_t>(tokenId) - static_cast<uint32_t>(TokenId::CompilerAlias0);
}

IdentifierRef SemaHelpers::resolveAliasIdentifier(Sema& sema, const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerAlias(tokenId));

    const auto* inlinePayload = sema.frame().currentInlinePayload();
    if (!inlinePayload)
        return IdentifierRef::invalid();

    const uint32_t slot = aliasSlotIndex(tokenId);
    if (slot >= inlinePayload->aliasIdentifiers.size())
        return IdentifierRef::invalid();

    return inlinePayload->aliasIdentifiers[slot];
}

uint32_t SemaHelpers::uniqSlotIndex(const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerUniq(tokenId));
    return static_cast<uint32_t>(tokenId) - static_cast<uint32_t>(TokenId::CompilerUniq0);
}

AstNodeRef SemaHelpers::uniqSyntaxScopeNodeRef(Sema& sema)
{
    if (sema.curNode().is(AstNodeId::FunctionBody) || sema.curNode().is(AstNodeId::EmbeddedBlock))
        return sema.curNodeRef();

    for (size_t parentIndex = 0;; parentIndex++)
    {
        const AstNodeRef parentRef = sema.visit().parentNodeRef(parentIndex);
        if (parentRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNodeId parentId = sema.node(parentRef).id();
        if (parentId == AstNodeId::FunctionBody || parentId == AstNodeId::EmbeddedBlock)
            return parentRef;
    }
}

SemaInlinePayload* SemaHelpers::mixinInlinePayloadForUniq(Sema& sema)
{
    auto* inlinePayload = sema.frame().currentInlinePayload();
    if (!inlinePayload || !inlinePayload->sourceFunction)
        return nullptr;
    if (!inlinePayload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        return nullptr;
    if (uniqSyntaxScopeNodeRef(sema) != inlinePayload->inlineRootRef)
        return nullptr;
    return inlinePayload;
}

namespace
{
    bool isInsideInlineRoot(Sema& sema, AstNodeRef inlineRootRef)
    {
        if (inlineRootRef.isInvalid())
            return false;

        if (sema.curNodeRef() == inlineRootRef)
            return true;

        for (size_t parentIndex = 0;; parentIndex++)
        {
            const AstNodeRef parentRef = sema.visit().parentNodeRef(parentIndex);
            if (parentRef.isInvalid())
                return false;
            if (parentRef == inlineRootRef)
                return true;
        }
    }

    const SemaInlinePayload* mixinInlinePayloadForNestedUniqUse(Sema& sema)
    {
        const auto* inlinePayload = sema.frame().currentInlinePayload();
        if (!inlinePayload || !inlinePayload->sourceFunction)
            return nullptr;
        if (!inlinePayload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
            return nullptr;
        if (!isInsideInlineRoot(sema, inlinePayload->inlineRootRef))
            return nullptr;
        return inlinePayload;
    }
}

IdentifierRef SemaHelpers::ensureCurrentScopeUniqIdentifier(Sema& sema, const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerUniq(tokenId));
    const uint32_t slot = uniqSlotIndex(tokenId);
    if (auto* inlinePayload = mixinInlinePayloadForUniq(sema))
    {
        const IdentifierRef done = inlinePayload->uniqIdentifiers[slot];
        if (done.isValid())
            return done;

        const IdentifierRef idRef            = getUniqueIdentifier(sema, std::format("__uniq{}", slot));
        inlinePayload->uniqIdentifiers[slot] = idRef;
        return idRef;
    }

    auto&               scope = sema.curScope();
    const IdentifierRef done  = scope.uniqIdentifier(slot);
    if (done.isValid())
        return done;

    const IdentifierRef idRef = getUniqueIdentifier(sema, std::format("__uniq{}", slot));
    scope.setUniqIdentifier(slot, idRef);
    return idRef;
}

IdentifierRef SemaHelpers::resolveUniqIdentifier(Sema& sema, const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerUniq(tokenId));

    const uint32_t slot = uniqSlotIndex(tokenId);
    for (const SemaScope* scope = sema.lookupScope(); scope; scope = scope->lookupParent())
    {
        const IdentifierRef idRef = scope->uniqIdentifier(slot);
        if (idRef.isValid())
            return idRef;
    }

    if (const auto* inlinePayload = mixinInlinePayloadForNestedUniqUse(sema))
    {
        const IdentifierRef idRef = inlinePayload->uniqIdentifiers[slot];
        if (idRef.isValid())
            return idRef;
    }

    return ensureCurrentScopeUniqIdentifier(sema, tokenId);
}

Result SemaHelpers::checkBinaryOperandTypes(Sema& sema, AstNodeRef nodeRef, TokenId op, AstNodeRef leftRef, AstNodeRef rightRef, const SemaNodeView& leftView, const SemaNodeView& rightView)
{
    const auto checkPointerArithmeticOperand = [](Sema& inSema, AstNodeRef inNodeRef, AstNodeRef operandRef, const SemaNodeView& operandView) -> Result {
        if (!operandView.type())
            return Result::Continue;

        const TypeInfo& operandType = aliasEnumType(inSema, operandView);
        if (!operandType.isAnyPointer())
            return Result::Continue;

        TypeRef payloadTypeRef = operandType.payloadTypeRef();
        if (payloadTypeRef != inSema.typeMgr().typeVoid())
        {
            const TypeRef unwrappedTypeRef = inSema.typeMgr().unwrapAliasEnum(inSema.ctx(), payloadTypeRef);
            if (unwrappedTypeRef.isValid())
                payloadTypeRef = unwrappedTypeRef;
        }

        if (payloadTypeRef == inSema.typeMgr().typeVoid())
            return SemaError::raisePointerArithmeticVoidPointer(inSema, inNodeRef, operandRef, operandView.typeRef());
        if (operandType.isValuePointer())
            return SemaError::raisePointerArithmeticValuePointer(inSema, inNodeRef, operandRef, operandView.typeRef());

        return Result::Continue;
    };

    const auto blockPointerPayloadsMatch = [](Sema& inSema, const SemaNodeView& leftOperandView, const SemaNodeView& rightOperandView) {
        const TypeInfo& leftType  = aliasEnumType(inSema, leftOperandView);
        const TypeInfo& rightType = aliasEnumType(inSema, rightOperandView);

        TypeRef leftPayloadTypeRef  = leftType.payloadTypeRef();
        TypeRef rightPayloadTypeRef = rightType.payloadTypeRef();
        if (leftPayloadTypeRef == rightPayloadTypeRef)
            return true;

        const TypeRef leftUnwrappedTypeRef = inSema.typeMgr().unwrapAliasEnum(inSema.ctx(), leftPayloadTypeRef);
        if (leftUnwrappedTypeRef.isValid())
            leftPayloadTypeRef = leftUnwrappedTypeRef;

        const TypeRef rightUnwrappedTypeRef = inSema.typeMgr().unwrapAliasEnum(inSema.ctx(), rightPayloadTypeRef);
        if (rightUnwrappedTypeRef.isValid())
            rightPayloadTypeRef = rightUnwrappedTypeRef;

        return leftPayloadTypeRef == rightPayloadTypeRef;
    };

    const TypeInfo& leftType  = aliasEnumType(sema, leftView);
    const TypeInfo& rightType = aliasEnumType(sema, rightView);
    switch (op)
    {
        case TokenId::SymPlus:
            SWC_RESULT(checkPointerArithmeticOperand(sema, nodeRef, leftRef, leftView));
            SWC_RESULT(checkPointerArithmeticOperand(sema, nodeRef, rightRef, rightView));

            if (leftType.isBlockPointer() && aliasType(sema, rightView).isIntLike())
                return Result::Continue;
            if (leftType.isBlockPointer() && rightType.isBlockPointer())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef(), rightView.typeRef());
            if (aliasType(sema, leftView).isIntLike() && rightType.isBlockPointer())
                return Result::Continue;
            break;

        case TokenId::SymMinus:
            SWC_RESULT(checkPointerArithmeticOperand(sema, nodeRef, leftRef, leftView));
            SWC_RESULT(checkPointerArithmeticOperand(sema, nodeRef, rightRef, rightView));

            if (leftType.isBlockPointer() && aliasType(sema, rightView).isIntLike())
                return Result::Continue;
            if (leftType.isBlockPointer() && rightType.isBlockPointer() && blockPointerPayloadsMatch(sema, leftView, rightView))
                return Result::Continue;
            if (leftType.isBlockPointer() && rightType.isBlockPointer())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef(), rightView.typeRef());
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
            if (!aliasType(sema, leftView).isScalarNumeric())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, leftRef, leftView.typeRef(), rightView.typeRef());
            if (!aliasType(sema, rightView).isScalarNumeric())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef(), rightView.typeRef());
            break;

        case TokenId::SymAmpersand:
        case TokenId::SymPipe:
        case TokenId::SymCircumflex:
        case TokenId::SymGreaterGreater:
        case TokenId::SymLowerLower:
            if (op == TokenId::SymAmpersand || op == TokenId::SymPipe || op == TokenId::SymCircumflex)
            {
                const bool leftEnumFlags  = aliasType(sema, leftView).isEnumFlags();
                const bool rightEnumFlags = aliasType(sema, rightView).isEnumFlags();
                if (leftEnumFlags && rightEnumFlags && leftView.typeRef() == rightView.typeRef())
                    break;
            }

            if (!aliasType(sema, leftView).isIntLike())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, leftRef, leftView.typeRef(), rightView.typeRef());
            if (!aliasType(sema, rightView).isIntLike())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef(), rightView.typeRef());
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
        {
            const TypeInfo& leftType  = aliasEnumType(sema, leftView);
            const TypeInfo& rightType = aliasEnumType(sema, rightView);
            if (leftType.isAnyPointer() && aliasType(sema, rightView).isIntLike())
            {
                if (rightView.type()->isScalarNumeric())
                    SWC_RESULT(Cast::cast(sema, rightView, sema.typeMgr().typeS64(), CastKind::Implicit));
                return Result::Continue;
            }
            if (aliasType(sema, leftView).isIntLike() && rightType.isAnyPointer())
            {
                return Result::Continue;
            }
            if (leftType.isAnyPointer() && rightType.isAnyPointer())
            {
                return Result::Continue;
            }
            break;
        }

        default:
            break;
    }

    if (op == TokenId::SymGreaterGreater || op == TokenId::SymLowerLower)
        return Result::Continue;

    SWC_RESULT(Cast::cast(sema, rightView, leftView.typeRef(), castKind));
    return Result::Continue;
}

Result SemaHelpers::resolveCountOfResult(Sema& sema, CountOfResultInfo& outResult, AstNodeRef exprRef)
{
    outResult               = {};
    auto               ctx  = sema.ctx();
    const SemaNodeView view = sema.viewTypeConstant(exprRef);

    if (!view.type())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, view.nodeRef());

    if (view.cst())
    {
        if (view.cst()->isString())
        {
            outResult.cstRef  = sema.cstMgr().addInt(ctx, view.cst()->getString().length());
            outResult.typeRef = sema.cstMgr().get(outResult.cstRef).typeRef();
            return Result::Continue;
        }

        if (view.cst()->isSlice())
        {
            const uint64_t count = view.cst()->getSliceCount();
            outResult.cstRef     = sema.cstMgr().addInt(ctx, count);
            outResult.typeRef    = sema.cstMgr().get(outResult.cstRef).typeRef();
            return Result::Continue;
        }

        if (view.cst()->isInt())
        {
            const ApsInt& countValue = view.cst()->getInt();
            if (!countValue.isUnsigned() && countValue.isNegative())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_count_negative, view.nodeRef());
                diag.addArgument(Diagnostic::ARG_VALUE, view.cst()->toString(ctx));
                diag.report(ctx);
                return Result::Error;
            }

            SWC_RESULT(Cast::concretizeConstant(sema, outResult.cstRef, view.nodeRef(), view.cstRef(), TypeInfo::Sign::Unsigned));
            outResult.typeRef = sema.cstMgr().get(outResult.cstRef).typeRef();
            return Result::Continue;
        }
    }

    const TypeRef   countTypeRef = unwrapAliasRefType(ctx, view.typeRef());
    const TypeInfo& countType    = sema.typeMgr().get(countTypeRef);

    if (countType.isEnum())
    {
        SWC_RESULT(sema.waitSemaCompleted(&countType, view.nodeRef()));
        outResult.cstRef  = sema.cstMgr().addInt(ctx, countType.payloadSymEnum().count());
        outResult.typeRef = sema.cstMgr().get(outResult.cstRef).typeRef();
        return Result::Continue;
    }

    if (countType.isCString())
    {
        outResult.typeRef = sema.typeMgr().typeU64();
        return Result::Continue;
    }

    if (countType.isString())
    {
        outResult.typeRef = sema.typeMgr().typeU64();
        return Result::Continue;
    }

    if (countType.isArray())
    {
        const uint64_t  sizeOf     = countType.sizeOf(ctx);
        const TypeRef   typeRef    = countType.payloadArrayElemTypeRef();
        const TypeInfo& ty         = sema.typeMgr().get(typeRef);
        const uint64_t  sizeOfElem = ty.sizeOf(ctx);
        SWC_ASSERT(sizeOfElem > 0);
        outResult.cstRef  = sema.cstMgr().addInt(ctx, sizeOf / sizeOfElem);
        outResult.typeRef = sema.cstMgr().get(outResult.cstRef).typeRef();
        return Result::Continue;
    }

    if (countType.isAggregateArray())
    {
        outResult.cstRef  = sema.cstMgr().addInt(ctx, countType.payloadAggregate().types.size());
        outResult.typeRef = sema.cstMgr().get(outResult.cstRef).typeRef();
        return Result::Continue;
    }

    if (countType.isSlice() || countType.isAnyVariadic())
    {
        outResult.typeRef = sema.typeMgr().typeU64();
        return Result::Continue;
    }

    if (countType.isInt())
    {
        outResult.typeRef = countOfPassthroughTypeRef(ctx, view.typeRef());
        if (!outResult.typeRef.isValid())
            outResult.typeRef = countTypeRef;
        return Result::Continue;
    }

    bool            handledSpecOp = false;
    SymbolFunction* calledFn      = nullptr;
    SWC_RESULT(SemaSpecOp::tryResolveCountOf(sema, exprRef, calledFn, handledSpecOp));
    if (handledSpecOp)
    {
        const SemaNodeView resultView = sema.viewNodeTypeConstant(sema.curNodeRef());
        outResult.typeRef             = resultView.typeRef();
        outResult.cstRef              = resultView.cstRef();
        outResult.calledFn            = calledFn;
        if (!outResult.typeRef.isValid() && calledFn)
            outResult.typeRef = calledFn->returnTypeRef();
        return Result::Continue;
    }

    auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_countof_type, view.nodeRef());
    diag.addArgument(Diagnostic::ARG_TYPE, view.typeRef());
    diag.report(ctx);
    return Result::Error;
}

Result SemaHelpers::intrinsicCountOf(Sema& sema, AstNodeRef targetRef, AstNodeRef exprRef)
{
    CountOfResultInfo result;
    SWC_RESULT(resolveCountOfResult(sema, result, exprRef));
    if (result.calledFn != nullptr)
    {
        auto* payload = sema.semaPayload<CountOfSpecOpPayload>(targetRef);
        if (!payload)
        {
            payload = sema.compiler().allocate<CountOfSpecOpPayload>();
            sema.setSemaPayload(targetRef, payload);
        }

        payload->calledFn = result.calledFn;
    }

    if (result.cstRef.isValid())
    {
        sema.setConstant(targetRef, result.cstRef);
        return Result::Continue;
    }

    sema.setType(targetRef, result.typeRef);
    sema.setIsValue(targetRef);
    return Result::Continue;
}

void SemaHelpers::handleSymbolRegistration(Sema& sema, SymbolMap* symbolMap, Symbol* sym)
{
    SWC_ASSERT(symbolMap != nullptr);
    SWC_ASSERT(sym != nullptr);

    if (sym->isVariable())
    {
        auto& symVar = sym->cast<SymbolVariable>();
        if (symbolMap->isStruct())
            symbolMap->cast<SymbolStruct>().addField(&symVar);

        if (sema.curScope().isParameters())
        {
            symVar.addExtraFlag(SymbolVariableFlagsE::Parameter);
            if (symbolMap->isFunction())
                symbolMap->cast<SymbolFunction>().addParameter(&symVar);
        }
    }

    if (sym->isFunction())
    {
        auto& symFunc = sym->cast<SymbolFunction>();
        if (symbolMap->isInterface())
            symbolMap->cast<SymbolInterface>().addFunction(&symFunc);
        if (symbolMap->isImpl())
            symbolMap->cast<SymbolImpl>().addFunction(sema.ctx(), &symFunc);
    }
}

namespace
{
    bool hasImmediatePostfixCall(const Sema& sema, const AstMemberAccessExpr& node)
    {
        if (node.nodeRightRef.isInvalid())
            return false;

        const TokenRef tokRightRef = sema.node(node.nodeRightRef).tokRef();
        if (!tokRightRef.isValid())
            return false;

        const SourceView& srcView   = sema.srcView(node.srcViewRef());
        const uint32_t    nextIndex = tokRightRef.get() + 1;
        if (nextIndex >= srcView.numTokens())
            return false;

        return srcView.token(TokenRef{nextIndex}).id == TokenId::SymLeftParen;
    }

    const SymbolStruct* resolveGenericRootStructAlias(const Symbol* symbol)
    {
        const Symbol* current = symbol;
        while (current && current->isAlias())
        {
            const auto& alias = current->cast<SymbolAlias>();
            if (alias.isStrict())
                return nullptr;

            const Symbol* next = alias.aliasedSymbol();
            if (!next || next == current)
                return nullptr;

            current = next;
        }

        if (!current || !current->isStruct())
            return nullptr;

        const auto& st = current->cast<SymbolStruct>();
        return st.isGenericRoot() && !st.isGenericInstance() ? &st : nullptr;
    }

    const SymbolStruct* genericStructRootFromQuotedBase(Sema& sema, AstNodeRef exprRef)
    {
        SmallVector<Symbol*> symbols;
        sema.viewNodeTypeSymbol(exprRef).getSymbols(symbols);
        for (const Symbol* sym : symbols)
        {
            if (!sym)
                continue;

            if (const auto* genericRoot = resolveGenericRootStructAlias(sym))
                return genericRoot;
        }

        return nullptr;
    }

    bool canSplitQuotedSuffixArgument(Sema& sema, const SymbolStruct& genericRoot, const SemaNodeView& leftView)
    {
        const AstNode* decl = genericRoot.decl();
        if (!decl)
            return false;

        SpanRef spanGenericParamsRef = SpanRef::invalid();
        if (const auto* structDecl = decl->safeCast<AstStructDecl>())
            spanGenericParamsRef = structDecl->spanGenericParamsRef;
        else if (const auto* unionDecl = decl->safeCast<AstUnionDecl>())
            spanGenericParamsRef = unionDecl->spanGenericParamsRef;

        if (!spanGenericParamsRef.isValid())
            return false;

        SmallVector<SemaGeneric::GenericParamDesc> params;
        SemaGeneric::collectGenericParams(sema, *decl, spanGenericParamsRef, params);
        if (params.empty())
            return false;

        switch (params.front().kind)
        {
            case SemaGeneric::GenericParamKind::Type:
                return leftView.typeRef().isValid();
            case SemaGeneric::GenericParamKind::Value:
                return leftView.cstRef().isValid();
        }

        return false;
    }

    Result substituteQuotedGenericMemberCall(Sema& sema, AstNodeRef parentRef, AstNodeRef currentRef, TokenRef tokNameRef, std::span<const Symbol*> symbols, bool& outHandled)
    {
        if (symbols.empty())
            return Result::Continue;

        auto [calleeRef, calleePtr] = sema.ast().makeNode<AstNodeId::Identifier>(tokNameRef);
        SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, calleeRef, true, symbols));
        sema.setSubstitute(parentRef, calleeRef);
        sema.setSubstitute(currentRef, calleeRef);
        sema.setIsValue(*calleePtr);
        outHandled = true;
        return Result::Continue;
    }

    Result tryLiftQuotedGenericStructMemberAccess(Sema& sema, AstNodeRef currentRef, const AstMemberAccessExpr& node, bool& outHandled)
    {
        outHandled                 = false;
        const AstNodeRef parentRef = sema.visit().parentNodeRef();
        if (parentRef.isInvalid())
            return Result::Continue;

        AstNode&    parentNode = sema.node(parentRef);
        const auto* quotedExpr = parentNode.safeCast<AstQuotedExpr>();
        if (!quotedExpr || quotedExpr->nodeSuffixRef != currentRef)
            return Result::Continue;
        if (!hasImmediatePostfixCall(sema, node))
            return Result::Continue;

        const SymbolStruct* genericRoot = genericStructRootFromQuotedBase(sema, quotedExpr->nodeExprRef);
        if (!genericRoot)
            return Result::Continue;

        const SemaNodeView leftView = sema.viewNodeTypeConstant(node.nodeLeftRef);
        if (!canSplitQuotedSuffixArgument(sema, *genericRoot, leftView))
            return Result::Continue;

        const auto* identRight = sema.node(node.nodeRightRef).safeCast<AstIdentifier>();
        if (!identRight)
            return Result::Continue;

        const IdentifierRef idRef      = SemaHelpers::resolveIdentifier(sema, identRight->codeRef());
        const TokenRef      tokNameRef = identRight->tokRef();
        const SourceCodeRef memberCode{node.srcViewRef(), tokNameRef};

        const AstNodeRef           genericArgRef = node.nodeLeftRef;
        SmallVector<const Symbol*> specializedFunctions;
        for (const SymbolImpl* symImpl : genericRoot->impls())
        {
            if (!symImpl)
                continue;

            std::vector<const Symbol*> symbols;
            symImpl->getAllSymbols(symbols);
            for (const Symbol* sym : symbols)
            {
                if (!sym || !sym->isFunction() || sym->idRef() != idRef)
                    continue;

                SymbolFunction* instance = nullptr;
                auto&           fn       = const_cast<SymbolFunction&>(sym->cast<SymbolFunction>());
                SWC_RESULT(SemaGeneric::instantiateFunctionExplicit(sema, fn, std::span{&genericArgRef, 1}, instance));
                if (instance)
                    specializedFunctions.push_back(instance);
            }
        }

        // `Type'Arg.member()` is parsed as `Type'(Arg.member)()`. When `member`
        // resolves to a generic static function of the generic root, reinterpret
        // that syntax as an explicit specialization of the function itself.
        if (!specializedFunctions.empty())
            return substituteQuotedGenericMemberCall(sema, parentRef, currentRef, tokNameRef, specializedFunctions.span(), outHandled);

        // For a concrete generic struct specialization, reinterpret the suffix
        // as member lookup on the specialized struct instead of on the suffix argument.
        SymbolStruct* specializedStruct = nullptr;
        auto&         genericRootRef    = const_cast<SymbolStruct&>(*genericRoot);
        SWC_RESULT(SemaGeneric::instantiateStructExplicit(sema, genericRootRef, std::span{&genericArgRef, 1}, specializedStruct));
        if (!specializedStruct)
            return Result::Continue;

        MatchContext lookUpCxt;
        lookUpCxt.codeRef       = memberCode;
        lookUpCxt.noWaitOnEmpty = true;
        lookUpCxt.symMapHint    = specializedStruct;
        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        if (lookUpCxt.empty())
            return Result::Continue;

        SmallVector<const Symbol*> specializedMembers;
        specializedMembers.reserve(lookUpCxt.count());
        for (const Symbol* sym : lookUpCxt.symbols())
            specializedMembers.push_back(sym);

        return substituteQuotedGenericMemberCall(sema, parentRef, currentRef, tokNameRef, specializedMembers.span(), outHandled);
    }

    bool needsStructMemberRuntimeStorage(Sema& sema, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView)
    {
        if (sema.isGlobalScope())
            return false;
        if (!nodeLeftView.type())
            return false;
        if (nodeLeftView.type()->isReference())
            return false;
        if (!sema.isLValue(node.nodeLeftRef))
            return true;

        const SemaNodeView leftSymbolView = sema.viewSymbol(node.nodeLeftRef);
        if (!leftSymbolView.sym() || !leftSymbolView.sym()->isVariable())
            return false;

        const auto& leftSymVar = leftSymbolView.sym()->cast<SymbolVariable>();
        return leftSymVar.hasExtraFlag(SymbolVariableFlagsE::Parameter);
    }

    Result ensureMemberRuntimeStorage(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node)
    {
        auto& payload = SemaHelpers::ensureCodeGenLoweringPayload(sema, targetNodeRef);
        if (payload.runtimeStorageSym == nullptr)
        {
            if (SymbolVariable* boundStorage = SemaHelpers::currentRuntimeStorage(sema))
                payload.runtimeStorageSym = boundStorage;
            else
                payload.runtimeStorageSym = &SemaHelpers::registerUniqueRuntimeStorageSymbol(sema, node, "__member_runtime_storage");
        }

        SmallVector<uint64_t> storageDims;
        storageDims.push_back(8);
        const TypeRef storageTypeRef = sema.typeMgr().addType(TypeInfo::makeArray(storageDims.span(), sema.typeMgr().typeU8()));
        return SemaHelpers::ensureRuntimeStorageDeclaredAndCompleted(sema, *payload.runtimeStorageSym, storageTypeRef);
    }

    Result bindMatchedMemberSymbols(Sema& sema, AstNodeRef targetNodeRef, AstNodeRef rightNodeRef, bool allowOverloadSet, std::span<const Symbol*> matchedSymbols)
    {
        SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, targetNodeRef, allowOverloadSet, matchedSymbols));
        SWC_RESULT(SemaSymbolLookup::bindSymbolList(sema, rightNodeRef, allowOverloadSet, matchedSymbols));
        return Result::Continue;
    }

    Result reportUnknownMemberSymbol(Sema& sema, const AstMemberAccessExpr& node, IdentifierRef idRef, TokenRef tokNameRef)
    {
        const SourceCodeRef codeRef{node.srcViewRef(), tokNameRef};
        auto                diag = SemaError::report(sema, DiagnosticId::sema_err_unknown_symbol, codeRef);
        diag.addArgument(Diagnostic::ARG_SYM, idRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    bool isCompilerDefinedMemberAccess(Sema& sema, const AstMemberAccessExpr& node)
    {
        const auto* ident = sema.node(node.nodeRightRef).safeCast<AstIdentifier>();
        return ident && ident->hasFlag(AstIdentifierFlagsE::InCompilerDefined);
    }

    Result bindMissingCompilerDefinedMember(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, bool& outHandled)
    {
        outHandled = false;
        if (!isCompilerDefinedMemberAccess(sema, node))
            return Result::Continue;

        constexpr std::span<const Symbol*> empty;
        sema.setSymbolList(targetNodeRef, empty);
        sema.setSymbolList(node.nodeRightRef, empty);
        outHandled = true;
        return Result::Continue;
    }

    Result tryBindUfcsFreeFunctions(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, IdentifierRef idRef, TokenRef tokNameRef, bool allowOverloadSet, bool& outHandled)
    {
        outHandled = false;
        if (!allowOverloadSet)
            return Result::Continue;

        MatchContext lookUpCxt;
        lookUpCxt.codeRef       = SourceCodeRef{node.srcViewRef(), tokNameRef};
        lookUpCxt.noWaitOnEmpty = true;
        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));

        SmallVector<const Symbol*> callableSymbols;
        if (!SemaSymbolLookup::filterCallCalleeCandidates(lookUpCxt.symbols().span(), callableSymbols))
            return Result::Continue;

        SWC_RESULT(bindMatchedMemberSymbols(sema, targetNodeRef, node.nodeRightRef, true, callableSymbols.span()));
        outHandled = true;
        return Result::SkipChildren;
    }

    Result lookupScopedMember(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SymbolMap& symMap, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{node.srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &symMap;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        if (sema.node(node.nodeRightRef).is(AstNodeId::QuotedExpr) || sema.node(node.nodeRightRef).is(AstNodeId::QuotedListExpr))
        {
            const AstNodeRef calleeRef = SemaHelpers::unwrapCallCalleeRef(sema, node.nodeRightRef);
            SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, targetNodeRef, allowOverloadSet, lookUpCxt.symbols().span()));
            SWC_RESULT(SemaSymbolLookup::bindSymbolList(sema, calleeRef, allowOverloadSet, lookUpCxt.symbols().span()));
            sema.setSubstitute(targetNodeRef, node.nodeRightRef);
            return Result::Continue;
        }
        SWC_RESULT(bindMatchedMemberSymbols(sema, targetNodeRef, node.nodeRightRef, allowOverloadSet, lookUpCxt.symbols().span()));
        return Result::SkipChildren;
    }

    Result memberNamespace(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolNamespace& namespaceSym = nodeLeftView.sym()->cast<SymbolNamespace>();
        return lookupScopedMember(sema, targetNodeRef, node, namespaceSym, idRef, tokNameRef, allowOverloadSet);
    }

    Result waitPendingEnumUsingSymMaps(Sema& sema, const SymbolEnum& enumSym, const SourceCodeRef& codeRef)
    {
        SmallVector<const SymbolMap*> usingSymMaps;
        enumSym.copyUsingSymMaps(usingSymMaps);
        for (const SymbolMap* usingSymMap : usingSymMaps)
        {
            if (!usingSymMap || !usingSymMap->isEnum())
                continue;

            const auto& usingEnum = usingSymMap->cast<SymbolEnum>();
            if (!usingEnum.isSemaCompleted())
                return sema.waitSemaCompleted(&usingEnum, codeRef);
        }

        return Result::Continue;
    }

    Result memberEnum(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SymbolEnum& enumSym, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SourceCodeRef codeRef{node.srcViewRef(), tokNameRef};
        SWC_RESULT(sema.waitSemaCompleted(&enumSym, codeRef));

        MatchContext lookUpCxt;
        lookUpCxt.codeRef       = codeRef;
        lookUpCxt.symMapHint    = &enumSym;
        lookUpCxt.noWaitOnEmpty = true;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        if (lookUpCxt.empty())
        {
            SWC_RESULT(waitPendingEnumUsingSymMaps(sema, enumSym, codeRef));
            if (sema.compiler().pendingImplRegistrations(enumSym.idRef()) != 0)
                return sema.waitImplRegistrations(enumSym.idRef(), codeRef);

            bool handled = false;
            SWC_RESULT(tryBindUfcsFreeFunctions(sema, targetNodeRef, node, idRef, tokNameRef, allowOverloadSet, handled));
            if (handled)
                return Result::SkipChildren;
            return reportUnknownMemberSymbol(sema, node, idRef, tokNameRef);
        }

        SWC_RESULT(bindMatchedMemberSymbols(sema, targetNodeRef, node.nodeRightRef, allowOverloadSet, lookUpCxt.symbols().span()));
        return Result::SkipChildren;
    }

    Result memberInterface(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolInterface& symInterface = nodeLeftView.type()->payloadSymInterface();
        const SourceCodeRef    codeRef{node.srcViewRef(), tokNameRef};
        SWC_RESULT(sema.waitSemaCompleted(&symInterface, codeRef));

        const SymbolMap& lookupMap = nodeLeftView.sym() && nodeLeftView.sym()->isImpl() ? *nodeLeftView.sym()->asSymMap() : static_cast<const SymbolMap&>(symInterface);
        return lookupScopedMember(sema, targetNodeRef, node, lookupMap, idRef, tokNameRef, allowOverloadSet);
    }

    Result memberStruct(Sema& sema, AstNodeRef targetNodeRef, AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet, const TypeInfo& typeInfo)
    {
        const SymbolStruct& symStruct = typeInfo.payloadSymStruct();
        const SourceCodeRef codeRef{node.srcViewRef(), tokNameRef};
        SWC_RESULT(sema.waitSemaCompleted(&symStruct, codeRef));

        MatchContext lookUpCxt;
        lookUpCxt.codeRef       = codeRef;
        lookUpCxt.symMapHint    = &symStruct;
        lookUpCxt.noWaitOnEmpty = true;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        if (lookUpCxt.empty())
        {
            bool handled = false;
            SWC_RESULT(bindMissingCompilerDefinedMember(sema, targetNodeRef, node, handled));
            if (handled)
                return Result::SkipChildren;
            SWC_RESULT(tryBindUfcsFreeFunctions(sema, targetNodeRef, node, idRef, tokNameRef, allowOverloadSet, handled));
            if (handled)
                return Result::SkipChildren;
            return reportUnknownMemberSymbol(sema, node, idRef, tokNameRef);
        }

        // Bind member-access node (curNodeRef) and RHS identifier.
        SWC_RESULT(bindMatchedMemberSymbols(sema, targetNodeRef, node.nodeRightRef, allowOverloadSet, lookUpCxt.symbols().span()));

        // Constant struct member access
        const SemaNodeView       nodeRightView            = sema.viewSymbolList(node.nodeRightRef);
        const std::span<Symbol*> symbols                  = nodeRightView.symList();
        const size_t             finalSymCount            = symbols.size();
        const bool               throughPointerOrRef      = isPointerOrReferenceAliasAware(sema, nodeLeftView);
        bool                     canExtractConstantMember = !throughPointerOrRef;
        if (throughPointerOrRef && nodeLeftView.cst())
        {
            const ConstantValue& cst = *nodeLeftView.cst();
            canExtractConstantMember = (cst.isValuePointer() && cst.getValuePointer() != 0) || (cst.isBlockPointer() && cst.getBlockPointer() != 0);
        }

        if (nodeLeftView.cst() && canExtractConstantMember && finalSymCount == 1 && symbols[0]->isVariable())
        {
            const SymbolVariable& symVar = symbols[0]->cast<SymbolVariable>();
            SWC_RESULT(ConstantExtract::structMember(sema, *nodeLeftView.cst(), symVar, targetNodeRef, node.nodeRightRef));
            return Result::SkipChildren;
        }

        if (throughPointerOrRef || sema.isLValue(node.nodeLeftRef))
            sema.setIsLValue(node);

        if (finalSymCount == 1 && symbols[0]->isVariable() && needsStructMemberRuntimeStorage(sema, node, nodeLeftView))
            SWC_RESULT(ensureMemberRuntimeStorage(sema, targetNodeRef, node));

        return Result::SkipChildren;
    }

    Result memberAggregateStruct(Sema& sema, AstNodeRef targetNodeRef, AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, IdentifierRef idRef, TokenRef tokNameRef, bool allowOverloadSet, const TypeInfo& typeInfo)
    {
        const auto& aggregate = typeInfo.payloadAggregate();
        const auto& types     = aggregate.types;
        SWC_ASSERT(aggregate.names.size() == types.size());

        size_t memberIndex = 0;
        if (!SemaHelpers::resolveAggregateMemberIndex(sema, typeInfo, idRef, memberIndex))
        {
            bool handled = false;
            SWC_RESULT(tryBindUfcsFreeFunctions(sema, targetNodeRef, node, idRef, tokNameRef, allowOverloadSet, handled));
            if (handled)
                return Result::SkipChildren;
            return reportUnknownMemberSymbol(sema, node, idRef, tokNameRef);
        }

        const TypeRef memberTypeRef = types[memberIndex];
        sema.setType(targetNodeRef, memberTypeRef);
        sema.setType(node.nodeRightRef, memberTypeRef);
        sema.setIsValue(node);
        sema.setIsValue(node.nodeRightRef);
        if (sema.isLValue(node.nodeLeftRef))
            sema.setIsLValue(node);

        if (nodeLeftView.cst() && nodeLeftView.cst()->isAggregateStruct())
        {
            const auto& values = nodeLeftView.cst()->getAggregateStruct();
            SWC_ASSERT(memberIndex < values.size());
            sema.setConstant(targetNodeRef, values[memberIndex]);
        }

        if (needsStructMemberRuntimeStorage(sema, node, nodeLeftView))
            SWC_RESULT(ensureMemberRuntimeStorage(sema, targetNodeRef, node));

        return Result::SkipChildren;
    }
}

Result SemaHelpers::resolveMemberAccess(Sema& sema, AstNodeRef memberRef, AstMemberAccessExpr& node, bool allowOverloadSet)
{
    bool handled = false;
    SWC_RESULT(tryLiftQuotedGenericStructMemberAccess(sema, memberRef, node, handled));
    if (handled)
        return Result::SkipChildren;

    SemaNodeView       nodeLeftView      = sema.viewNodeTypeConstantSymbol(node.nodeLeftRef);
    const AstNodeRef   memberNameRef     = unwrapCallCalleeRef(sema, node.nodeRightRef);
    const SemaNodeView nodeRightNameView = sema.viewNode(memberNameRef);
    SWC_ASSERT(nodeRightNameView.node());
    SWC_ASSERT(nodeRightNameView.node()->is(AstNodeId::Identifier));
    const TokenRef      tokNameRef = nodeRightNameView.node()->tokRef();
    const IdentifierRef idRef      = sema.idMgr().addIdentifier(sema.ctx(), nodeRightNameView.node()->codeRef());

    // Namespace
    if (nodeLeftView.sym() && nodeLeftView.sym()->isNamespace())
        return memberNamespace(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Auto-deduce generic arguments for bare generic root structs in expression context.
    // Generic roots have a type payload so they can be used as type values, but member
    // lookup inside a generic impl must still happen on the current specialization.
    SymbolStruct* contextualGenericRoot = nullptr;
    if (nodeLeftView.sym() && nodeLeftView.sym()->isStruct())
    {
        auto& st = nodeLeftView.sym()->cast<SymbolStruct>();
        if (st.isGenericRoot() && !st.isGenericInstance())
            contextualGenericRoot = &st;
    }
    else if (nodeLeftView.sym() && nodeLeftView.sym()->isAlias())
    {
        contextualGenericRoot = const_cast<SymbolStruct*>(resolveGenericRootStructAlias(nodeLeftView.sym()));
    }

    if (contextualGenericRoot)
    {
        SymbolStruct* instance = nullptr;
        SWC_RESULT(SemaGeneric::instantiateStructFromContext(sema, *contextualGenericRoot, instance));
        if (instance)
        {
            const TypeRef specializedTypeRef = ensureStructTypeRef(sema, *instance);
            sema.setSymbol(node.nodeLeftRef, instance);
            if (specializedTypeRef.isValid())
                sema.setType(node.nodeLeftRef, specializedTypeRef);
            nodeLeftView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        }
    }

    SWC_ASSERT(nodeLeftView.type());

    // Enum
    if (const SymbolEnum* enumSym = enumSymbolFromTypeRef(sema, nodeLeftView.typeRef()))
        return memberEnum(sema, memberRef, node, *enumSym, idRef, tokNameRef, allowOverloadSet);

    // Interface
    if (nodeLeftView.type()->isInterface())
        return memberInterface(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Aggregate struct
    if (nodeLeftView.type()->isAggregateStruct())
        return memberAggregateStruct(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet, *nodeLeftView.type());

    // Dereference pointer
    const TypeInfo* typeInfo = nodeLeftView.type();
    if (typeInfo->isTypeValue())
    {
        const TypeRef typeInfoRef = sema.typeMgr().typeTypeInfo();
        SWC_RESULT(Cast::cast(sema, nodeLeftView, typeInfoRef, CastKind::Explicit));

        // Resolve the derived TypeInfo struct that matches the underlying type,
        // so that type-specific fields (e.g. TypeInfoArray.count) are accessible.
        const TypeInfo& underlying = sema.typeMgr().get(typeInfo->payloadTypeRef());
        TypeRef         structRef  = sema.typeMgr().structTypeInfo();
        if (underlying.isArray() || underlying.isAggregateArray())
            structRef = sema.typeMgr().structTypeInfoArray();
        else if (underlying.isStruct() || underlying.isAggregateStruct())
            structRef = sema.typeMgr().structTypeInfoStruct();
        else if (underlying.isEnum())
            structRef = sema.typeMgr().structTypeInfoEnum();
        else if (underlying.isFunction())
            structRef = sema.typeMgr().structTypeInfoFunc();
        else if (underlying.isSlice())
            structRef = sema.typeMgr().structTypeInfoSlice();
        else if (underlying.isAnyPointer())
            structRef = sema.typeMgr().structTypeInfoPointer();
        else if (underlying.isAlias())
            structRef = sema.typeMgr().structTypeInfoAlias();
        else if (underlying.isAnyVariadic())
            structRef = sema.typeMgr().structTypeInfoVariadic();
        else if (underlying.isCodeBlock())
            structRef = sema.typeMgr().structTypeInfoCodeBlock();
        typeInfo = &sema.typeMgr().get(structRef);
    }
    else if (typeInfo->isTypeInfo())
    {
        TypeRef typeInfoRef = sema.typeMgr().structTypeInfo();
        if (!typeInfoRef.isValid())
            SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::TypeInfo, typeInfoRef, {node.srcViewRef(), tokNameRef}));
        SWC_ASSERT(typeInfoRef.isValid());
        typeInfo = &sema.typeMgr().get(typeInfoRef);
    }
    else
    {
        TypeRef typeRef = aliasEnumTypeRef(sema, nodeLeftView.typeRef());
        typeInfo        = &sema.typeMgr().get(typeRef);
        if (typeInfo->isAnyPointer() || typeInfo->isReference())
        {
            typeRef  = aliasEnumTypeRef(sema, typeInfo->payloadTypeRef());
            typeInfo = &sema.typeMgr().get(typeRef);
        }
    }

    // Aggregate struct through pointer/reference
    if (typeInfo->isAggregateStruct())
        return memberAggregateStruct(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet, *typeInfo);

    // Struct
    if (typeInfo->isStruct())
        return memberStruct(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet, *typeInfo);

    // Pointer/Reference
    const TypeInfo& leftType = aliasEnumType(sema, nodeLeftView);
    if (leftType.isAnyPointer() || leftType.isReference())
    {
        sema.setType(memberRef, leftType.payloadTypeRef());
        sema.setIsValue(node);
        return Result::SkipChildren;
    }

    bool ufcsHandled = false;
    SWC_RESULT(bindMissingCompilerDefinedMember(sema, memberRef, node, ufcsHandled));
    if (ufcsHandled)
        return Result::SkipChildren;

    SWC_RESULT(tryBindUfcsFreeFunctions(sema, memberRef, node, idRef, tokNameRef, allowOverloadSet, ufcsHandled));
    if (ufcsHandled)
        return Result::SkipChildren;
    return reportUnknownMemberSymbol(sema, node, idRef, tokNameRef);
}

SWC_END_NAMESPACE();
