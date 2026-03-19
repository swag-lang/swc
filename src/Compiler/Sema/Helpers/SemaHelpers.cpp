#include "pch.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.impl.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

SymbolVariable* SemaHelpers::currentRuntimeStorage(Sema& sema)
{
    SymbolVariable* const sym     = sema.frame().currentRuntimeStorageSym();
    const AstNodeRef      nodeRef = sema.frame().currentRuntimeStorageNodeRef();
    if (!sym || !nodeRef.isValid())
        return nullptr;

    const AstNodeRef resolvedTargetRef  = sema.viewZero(nodeRef).nodeRef();
    const AstNodeRef resolvedCurrentRef = sema.viewZero(sema.curNodeRef()).nodeRef();
    if (resolvedTargetRef != resolvedCurrentRef)
        return nullptr;

    return sym;
}

void SemaHelpers::addCurrentFunctionCallDependency(const Sema& sema, SymbolFunction* calleeSym)
{
    if (SymbolFunction* currentFn = currentFunction(sema); currentFn && calleeSym)
        currentFn->addCallDependency(calleeSym);
}

Result SemaHelpers::addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
{
    if (!isCurrentFunction(sema) || !typeRef.isValid())
        return Result::Continue;

    const TypeInfo& symType = sema.typeMgr().get(typeRef);
    SWC_RESULT(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
    currentFunction(sema)->addLocalVariable(sema.ctx(), &symVar);
    return Result::Continue;
}

Result SemaHelpers::addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar)
{
    return addCurrentFunctionLocalVariable(sema, symVar, symVar.typeRef());
}

bool SemaHelpers::needsPersistentCompilerRunReturn(const Sema& sema, TypeRef typeRef)
{
    if (!typeRef.isValid())
        return false;

    const auto needsPersistent = [&](auto&& self, TypeRef rawTypeRef) -> bool {
        if (!rawTypeRef.isValid())
            return false;

        const TypeInfo& typeInfo = sema.typeMgr().get(rawTypeRef);
        if (typeInfo.isAlias())
        {
            return self(self, typeInfo.unwrap(sema.ctx(), rawTypeRef, TypeExpandE::Alias));
        }

        if (typeInfo.isEnum())
        {
            return self(self, typeInfo.unwrap(sema.ctx(), rawTypeRef, TypeExpandE::Enum));
        }

        if (typeInfo.isString() || typeInfo.isSlice() || typeInfo.isAny() || typeInfo.isInterface() || typeInfo.isCString())
            return true;

        if (typeInfo.isArray())
        {
            return self(self, typeInfo.payloadArrayElemTypeRef());
        }

        if (typeInfo.isStruct())
        {
            for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
            {
                if (field && self(self, field->typeRef()))
                    return true;
            }
        }

        return false;
    };

    return needsPersistent(needsPersistent, typeRef);
}

bool SemaHelpers::functionUsesIndirectReturnStorage(TaskContext& ctx, const SymbolFunction& function)
{
    const TypeRef returnTypeRef = function.returnTypeRef();
    if (!returnTypeRef.isValid())
        return false;

    const CallConv&                        callConv      = CallConv::get(function.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(ctx, callConv, returnTypeRef, ABITypeNormalize::Usage::Return);
    return normalizedRet.isIndirect;
}

bool SemaHelpers::currentFunctionUsesIndirectReturnStorage(Sema& sema)
{
    const SymbolFunction* currentFn = currentFunction(sema);
    return currentFn && functionUsesIndirectReturnStorage(sema.ctx(), *currentFn);
}

bool SemaHelpers::usesCallerReturnStorage(TaskContext& ctx, const SymbolFunction& function, const SymbolVariable& symVar)
{
    return symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal) &&
           functionUsesIndirectReturnStorage(ctx, function);
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

        break;
    }

    return nodeRef;
}

const SymbolFunction* SemaHelpers::currentLocationFunction(const Sema& sema)
{
    const auto* inlinePayload = sema.frame().currentInlinePayload();
    if (inlinePayload && inlinePayload->sourceFunction)
        return SemaRuntime::transparentLocationFunction(inlinePayload->sourceFunction);

    return SemaRuntime::transparentLocationFunction(currentFunction(sema));
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

bool SemaHelpers::isDirectCallerLocationDefault(const Sema& sema, const SymbolVariable& param)
{
    const AstNodeRef initRef = defaultArgumentExprRef(param);
    if (initRef.isInvalid())
        return false;

    const AstNode& initNode = sema.node(initRef);
    if (initNode.isNot(AstNodeId::CompilerLiteral))
        return false;

    return sema.token(initNode.codeRef()).id == TokenId::CompilerCallerLocation;
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
    auto* inlinePayload = const_cast<SemaInlinePayload*>(sema.frame().currentInlinePayload());
    if (!inlinePayload || !inlinePayload->sourceFunction)
        return nullptr;
    if (!inlinePayload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        return nullptr;
    if (uniqSyntaxScopeNodeRef(sema) != inlinePayload->inlineRootRef)
        return nullptr;
    return inlinePayload;
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
    for (const SemaScope* scope = &sema.curScope(); scope; scope = scope->parent())
    {
        const IdentifierRef idRef = scope->uniqIdentifier(slot);
        if (idRef.isValid())
            return idRef;
    }

    if (const auto* inlinePayload = mixinInlinePayloadForUniq(sema))
    {
        const IdentifierRef idRef = inlinePayload->uniqIdentifiers[slot];
        if (idRef.isValid())
            return idRef;
    }

    return ensureCurrentScopeUniqIdentifier(sema, tokenId);
}

Result SemaHelpers::checkBinaryOperandTypes(Sema& sema, AstNodeRef nodeRef, TokenId op, AstNodeRef leftRef, AstNodeRef rightRef, const SemaNodeView& leftView, const SemaNodeView& rightView)
{
    switch (op)
    {
        case TokenId::SymPlus:
            if (leftView.type()->isValuePointer())
                return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, leftRef, leftView.typeRef());
            if (rightView.type()->isValuePointer())
                return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, rightRef, rightView.typeRef());

            if (leftView.type()->isBlockPointer() && leftView.type()->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, leftRef, leftView.typeRef());
            if (rightView.type()->isBlockPointer() && rightView.type()->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, rightRef, rightView.typeRef());

            if (leftView.type()->isBlockPointer() && rightView.type()->isScalarNumeric())
                return Result::Continue;
            if (leftView.type()->isBlockPointer() && rightView.type()->isBlockPointer())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef(), rightView.typeRef());
            if (leftView.type()->isScalarNumeric() && rightView.type()->isBlockPointer())
                return Result::Continue;
            break;

        case TokenId::SymMinus:
            if (leftView.type()->isValuePointer())
                return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, leftRef, leftView.typeRef());
            if (rightView.type()->isValuePointer())
                return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, rightRef, rightView.typeRef());

            if (leftView.type()->isBlockPointer() && leftView.type()->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, leftRef, leftView.typeRef());
            if (rightView.type()->isBlockPointer() && rightView.type()->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, rightRef, rightView.typeRef());

            if (leftView.type()->isBlockPointer() && rightView.type()->isScalarNumeric())
                return Result::Continue;
            if (leftView.type()->isBlockPointer() && rightView.type()->isBlockPointer())
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
            if (!leftView.type()->isScalarNumeric())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, leftRef, leftView.typeRef(), rightView.typeRef());
            if (!rightView.type()->isScalarNumeric())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef(), rightView.typeRef());
            break;

        case TokenId::SymAmpersand:
        case TokenId::SymPipe:
        case TokenId::SymCircumflex:
        case TokenId::SymGreaterGreater:
        case TokenId::SymLowerLower:
            if (op == TokenId::SymAmpersand || op == TokenId::SymPipe || op == TokenId::SymCircumflex)
            {
                const bool leftEnumFlags  = leftView.type()->isEnumFlags();
                const bool rightEnumFlags = rightView.type()->isEnumFlags();
                if (leftEnumFlags && rightEnumFlags && leftView.typeRef() == rightView.typeRef())
                    break;
            }

            if (!leftView.type()->isInt())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, leftRef, leftView.typeRef(), rightView.typeRef());
            if (!rightView.type()->isInt())
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
            if (leftView.type()->isBlockPointer() && rightView.type()->isScalarNumeric())
            {
                SWC_RESULT(Cast::cast(sema, rightView, sema.typeMgr().typeS64(), CastKind::Implicit));
                return Result::Continue;
            }
            if (leftView.type()->isScalarNumeric() && rightView.type()->isBlockPointer())
            {
                return Result::Continue;
            }
            if (leftView.type()->isBlockPointer() && rightView.type()->isBlockPointer())
            {
                return Result::Continue;
            }
            break;

        default:
            break;
    }

    SWC_RESULT(Cast::cast(sema, rightView, leftView.typeRef(), castKind));
    return Result::Continue;
}

Result SemaHelpers::intrinsicCountOf(Sema& sema, AstNodeRef targetRef, AstNodeRef exprRef)
{
    auto               ctx  = sema.ctx();
    const SemaNodeView view = sema.viewTypeConstant(exprRef);

    if (!view.type())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, view.nodeRef());

    if (view.cst())
    {
        if (view.cst()->isString())
        {
            sema.setConstant(targetRef, sema.cstMgr().addInt(ctx, view.cst()->getString().length()));
            return Result::Continue;
        }

        if (view.cst()->isSlice())
        {
            const TypeInfo& elementType = sema.typeMgr().get(view.type()->payloadTypeRef());
            const uint64_t  elementSize = elementType.sizeOf(ctx);
            const uint64_t  count       = elementSize ? view.cst()->getSlice().size() / elementSize : 0;
            sema.setConstant(targetRef, sema.cstMgr().addInt(ctx, count));
            return Result::Continue;
        }

        if (view.cst()->isInt())
        {
            if (view.cst()->getInt().isNegative())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_count_negative, view.nodeRef());
                diag.addArgument(Diagnostic::ARG_VALUE, view.cst()->toString(ctx));
                diag.report(ctx);
                return Result::Error;
            }

            ConstantRef newCstRef;
            SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, view.nodeRef(), view.cstRef(), TypeInfo::Sign::Unsigned));
            sema.setConstant(targetRef, newCstRef);
            return Result::Continue;
        }
    }

    if (view.type()->isEnum())
    {
        SWC_RESULT(sema.waitSemaCompleted(view.type(), view.nodeRef()));
        sema.setConstant(targetRef, sema.cstMgr().addInt(ctx, view.type()->payloadSymEnum().count()));
        return Result::Continue;
    }

    if (view.type()->isCString())
    {
        sema.setType(targetRef, sema.typeMgr().typeU64());
        sema.setIsValue(targetRef);
        return Result::Continue;
    }

    if (view.type()->isString())
    {
        sema.setType(targetRef, sema.typeMgr().typeU64());
        sema.setIsValue(targetRef);
        return Result::Continue;
    }

    if (view.type()->isArray())
    {
        const uint64_t  sizeOf     = view.type()->sizeOf(ctx);
        const TypeRef   typeRef    = view.type()->payloadArrayElemTypeRef();
        const TypeInfo& ty         = sema.typeMgr().get(typeRef);
        const uint64_t  sizeOfElem = ty.sizeOf(ctx);
        SWC_ASSERT(sizeOfElem > 0);
        sema.setConstant(targetRef, sema.cstMgr().addInt(ctx, sizeOf / sizeOfElem));
        return Result::Continue;
    }

    if (view.type()->isSlice() || view.type()->isAnyVariadic())
    {
        sema.setType(targetRef, sema.typeMgr().typeU64());
        sema.setIsValue(targetRef);
        return Result::Continue;
    }

    if (view.type()->isIntUnsigned())
    {
        sema.setType(targetRef, view.typeRef());
        sema.setIsValue(targetRef);
        return Result::Continue;
    }

    auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_countof_type, view.nodeRef());
    diag.addArgument(Diagnostic::ARG_TYPE, view.typeRef());
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

        SemaNodeView view = sema.viewTypeConstant(child);
        SWC_ASSERT(view.typeRef().isValid());
        memberTypes.push_back(view.typeRef());
        allConstant = allConstant && view.cstRef().isValid();
        values.push_back(view.cstRef());
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

SWC_END_NAMESPACE();
