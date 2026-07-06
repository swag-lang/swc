#include "pch.h"
#include "Compiler/Sema/Helpers/SemaEscape.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_TYPE_BUDGET = 128;
    constexpr uint32_t K_EXPR_BUDGET = 128;

    TypeRef unwrapAliasEnum(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeRef unwrapped = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        return unwrapped.isValid() ? unwrapped : typeRef;
    }

    TypeRef normalizeBindingType(Sema& sema, TypeRef typeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& typeInfo  = sema.typeMgr().get(typeRef);
            const TypeRef   unwrapped = typeInfo.unwrap(sema.ctx(), TypeRef::invalid(), TypeExpandE::Alias | TypeExpandE::Enum);
            if (unwrapped.isValid())
            {
                typeRef = unwrapped;
                continue;
            }

            if (typeInfo.isReference())
            {
                typeRef = typeInfo.payloadTypeRef();
                continue;
            }

            break;
        }

        return typeRef;
    }

    TypeRef expressionTypeRef(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return TypeRef::invalid();
        return sema.viewType(nodeRef).typeRef();
    }

    bool isDirectBorrowCarrier(Sema& sema, TypeRef typeRef)
    {
        typeRef = unwrapAliasEnum(sema, typeRef);
        if (!typeRef.isValid())
            return false;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        return type.isString() ||
               type.isCString() ||
               type.isSlice() ||
               type.isAnyPointer() ||
               type.isReference() ||
               type.isInterface() ||
               type.isLambdaClosure();
    }

    bool hasOwningLifecycle(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeGen::LifecycleFlags lifecycle = TypeGen::lifecycleFlagsOfTypeRef(sema.ctx(), typeRef);
        return lifecycle.hasDrop || lifecycle.hasPostCopy || lifecycle.hasPostMove || !lifecycle.canCopy;
    }

    bool typeCanCarryBorrowRec(Sema& sema, TypeRef typeRef, std::unordered_set<TypeRef>& visiting, uint32_t& budget)
    {
        if (!budget || !typeRef.isValid())
            return false;
        budget--;

        typeRef = unwrapAliasEnum(sema, typeRef);
        if (!typeRef.isValid())
            return false;

        if (isDirectBorrowCarrier(sema, typeRef))
            return true;

        if (!visiting.insert(typeRef).second)
            return false;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isArray())
            return typeCanCarryBorrowRec(sema, type.payloadArrayElemTypeRef(), visiting, budget);

        if (type.isAggregate())
        {
            for (const TypeRef fieldTypeRef : type.payloadAggregate().types)
            {
                if (typeCanCarryBorrowRec(sema, fieldTypeRef, visiting, budget))
                    return true;
            }

            return false;
        }

        if (!type.isStruct())
            return false;

        // Owner structs such as Core.String contain raw pointers internally, but their
        // lifecycle means a bitwise field scan would confuse ownership with borrowing.
        if (hasOwningLifecycle(sema, typeRef))
            return false;

        for (const SymbolVariable* field : type.payloadSymStruct().fields())
        {
            if (field && typeCanCarryBorrowRec(sema, field->typeRef(), visiting, budget))
                return true;
        }

        return false;
    }

    bool typeCanCarryBorrowImpl(Sema& sema, TypeRef typeRef)
    {
        std::unordered_set<TypeRef> visiting;
        uint32_t                    budget = K_TYPE_BUDGET;
        return typeCanCarryBorrowRec(sema, typeRef, visiting, budget);
    }

    int escapeRank(SemaEscapeKind kind)
    {
        switch (kind)
        {
            case SemaEscapeKind::Local:
                return 4;
            case SemaEscapeKind::Parameter:
                return 3;
            case SemaEscapeKind::Unknown:
                return 2;
            case SemaEscapeKind::Static:
                return 1;
            case SemaEscapeKind::None:
                return 0;
        }

        SWC_UNREACHABLE();
    }

    SemaEscapeInfo mergeEscapeInfo(const SemaEscapeInfo& left, const SemaEscapeInfo& right)
    {
        return escapeRank(right.kind) > escapeRank(left.kind) ? right : left;
    }

    bool isLocalVariableStorage(Sema& sema, const SymbolVariable& symVar)
    {
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::GlobalStorage) ||
            symVar.hasExtraFlag(SymbolVariableFlagsE::RuntimeStorage) ||
            symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal) ||
            symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
            return false;

        if (const SymbolFunction* currentFn = sema.currentFunction())
        {
            if (symVar.isFunctionLocalVariable(*currentFn))
                return true;
            if (currentFn->containsLocalVariable(symVar))
                return true;
        }

        return symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal);
    }

    SemaEscapeInfo variableStorageInfo(Sema& sema, const SymbolVariable& symVar, AstNodeRef sourceRef, TypeRef typeRef)
    {
        if (symVar.isClosureCapture())
        {
            if (const SemaEscapeInfo* existing = sema.variableEscapeInfo(symVar))
                return *existing;
            if (symVar.closureCaptureByRef() && symVar.closureCapturedSource())
                return variableStorageInfo(sema, *symVar.closureCapturedSource(), sourceRef, typeRef);
        }

        SemaEscapeInfo info;
        info.sourceVar = &symVar;
        info.sourceRef = sourceRef;
        info.typeRef   = typeRef;

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::GlobalStorage))
            info.kind = SemaEscapeKind::Static;
        else if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
            info.kind = SemaEscapeKind::Parameter;
        else if (isLocalVariableStorage(sema, symVar))
            info.kind = SemaEscapeKind::Local;
        else
            info.kind = SemaEscapeKind::Unknown;

        return info;
    }

    const SymbolVariable* identifierVariable(Sema& sema, AstNodeRef nodeRef)
    {
        const SemaNodeView view = sema.viewSymbol(nodeRef);
        if (!view.hasSymbol() || !view.sym() || !view.sym()->isVariable())
            return nullptr;
        return &view.sym()->cast<SymbolVariable>();
    }

    bool isArrayStorageExpr(Sema& sema, AstNodeRef nodeRef)
    {
        const TypeRef typeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, nodeRef));
        return typeRef.isValid() && sema.typeMgr().get(typeRef).isArray();
    }

    const SymbolVariable* storageRootVariable(Sema& sema, AstNodeRef nodeRef, bool forAssignment, bool& outWholeVariable)
    {
        outWholeVariable = false;
        if (nodeRef.isInvalid())
            return nullptr;

        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isInvalid())
            return nullptr;

        const AstNode& node = sema.node(resolvedRef);
        switch (node.id())
        {
            case AstNodeId::Identifier:
                outWholeVariable = true;
                return identifierVariable(sema, resolvedRef);

            case AstNodeId::ParenExpr:
                return storageRootVariable(sema, node.cast<AstParenExpr>().nodeExprRef, forAssignment, outWholeVariable);

            case AstNodeId::InitializerExpr:
                return storageRootVariable(sema, node.cast<AstInitializerExpr>().nodeExprRef, forAssignment, outWholeVariable);

            case AstNodeId::AutoCastExpr:
                return storageRootVariable(sema, node.cast<AstAutoCastExpr>().nodeExprRef, forAssignment, outWholeVariable);

            case AstNodeId::AsCastExpr:
                return storageRootVariable(sema, node.cast<AstAsCastExpr>().nodeExprRef, forAssignment, outWholeVariable);

            case AstNodeId::CastExpr:
                return storageRootVariable(sema, node.cast<AstCastExpr>().nodeExprRef, forAssignment, outWholeVariable);

            case AstNodeId::MemberAccessExpr:
            {
                const AstNodeRef leftRef      = node.cast<AstMemberAccessExpr>().nodeLeftRef;
                const TypeRef    leftTypeRef  = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, leftRef));
                if (isDirectBorrowCarrier(sema, leftTypeRef))
                    return nullptr;

                outWholeVariable = false;
                return storageRootVariable(sema, leftRef, forAssignment, outWholeVariable);
            }

            case AstNodeId::IndexExpr:
            {
                const auto& index = node.cast<AstIndexExpr>();
                if (isArrayStorageExpr(sema, index.nodeExprRef))
                {
                    outWholeVariable = false;
                    return storageRootVariable(sema, index.nodeExprRef, forAssignment, outWholeVariable);
                }

                return nullptr;
            }

            case AstNodeId::IndexListExpr:
            {
                const auto& index = node.cast<AstIndexListExpr>();
                if (isArrayStorageExpr(sema, index.nodeExprRef))
                {
                    outWholeVariable = false;
                    return storageRootVariable(sema, index.nodeExprRef, forAssignment, outWholeVariable);
                }

                return nullptr;
            }

            case AstNodeId::UnaryExpr:
                return forAssignment ? nullptr : storageRootVariable(sema, node.cast<AstUnaryExpr>().nodeExprRef, forAssignment, outWholeVariable);

            default:
                return nullptr;
        }
    }

    const SymbolVariable* storageRootVariable(Sema& sema, AstNodeRef nodeRef)
    {
        bool wholeVariable = false;
        return storageRootVariable(sema, nodeRef, false, wholeVariable);
    }

    SemaEscapeInfo storageBorrowInfo(Sema& sema, AstNodeRef sourceRef, TypeRef typeRef, bool allowDirectCarrier = false)
    {
        const TypeRef rawSourceTypeRef = unwrapAliasEnum(sema, expressionTypeRef(sema, sourceRef));
        if (!allowDirectCarrier && isDirectBorrowCarrier(sema, rawSourceTypeRef))
            return {};

        bool                  wholeVariable = false;
        const SymbolVariable* sourceVar     = storageRootVariable(sema, sourceRef, false, wholeVariable);
        if (sourceVar)
        {
            if (wholeVariable && rawSourceTypeRef.isValid() && sema.typeMgr().get(rawSourceTypeRef).isReference())
            {
                if (const SemaEscapeInfo* existing = sema.variableEscapeInfo(*sourceVar))
                {
                    SemaEscapeInfo info = *existing;
                    info.typeRef        = typeRef;
                    return info;
                }

                return {};
            }

            return variableStorageInfo(sema, *sourceVar, sourceRef, typeRef);
        }
        return {};
    }

    SemaEscapeInfo expressionEscapeInfoRec(Sema& sema, AstNodeRef nodeRef, uint32_t& budget);
    SemaEscapeInfo expressionEscapeInfoWithTarget(Sema& sema, AstNodeRef nodeRef, TypeRef targetTypeRef, uint32_t& budget);

    AstNodeRef argumentValueRef(Sema& sema, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNodeRef resolvedRef = sema.viewZero(argRef).nodeRef();
        if (resolvedRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& node = sema.node(resolvedRef);
        if (node.is(AstNodeId::NamedArgument))
            return node.cast<AstNamedArgument>().nodeArgRef;

        return resolvedRef;
    }

    IdentifierRef namedArgumentIdentifier(Sema& sema, AstNodeRef childRef)
    {
        const AstNode& childNode = sema.node(childRef);
        if (childNode.isNot(AstNodeId::NamedArgument))
            return IdentifierRef::invalid();

        return sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef());
    }

    template<typename T>
    bool resolveAggregateChildIndex(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, size_t memberCount, const T& resolveNamedIndex, size_t& outIndex)
    {
        outIndex = 0;
        if (!memberCount)
            return false;

        std::vector<uint8_t> assigned(memberCount, 0);
        size_t               nextPos = 0;

        for (const AstNodeRef currentChildRef : children)
        {
            const IdentifierRef namedIdRef = namedArgumentIdentifier(sema, currentChildRef);
            if (namedIdRef.isValid())
            {
                size_t namedIndex = 0;
                if (!resolveNamedIndex(namedIdRef, namedIndex) || namedIndex >= memberCount)
                {
                    if (currentChildRef == childRef)
                        return false;
                    continue;
                }

                if (currentChildRef == childRef)
                {
                    outIndex = namedIndex;
                    return true;
                }

                assigned[namedIndex] = 1;
                continue;
            }

            while (nextPos < memberCount && assigned[nextPos])
                ++nextPos;

            if (currentChildRef == childRef)
            {
                if (nextPos >= memberCount)
                    return false;

                outIndex = nextPos;
                return true;
            }

            if (nextPos < memberCount)
            {
                assigned[nextPos] = 1;
                ++nextPos;
            }
        }

        return false;
    }

    TypeRef structLikeChildTargetType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef)
    {
        const TypeRef targetRef = normalizeBindingType(sema, targetTypeRef);
        if (!targetRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& targetType = sema.typeMgr().get(targetRef);
        size_t          fieldIndex = 0;

        if (targetType.isStruct())
        {
            const SymbolStruct& targetStruct = targetType.payloadSymStruct();
            const auto&         fields       = targetStruct.fields();
            const auto          findFieldIndex = [&](IdentifierRef idRef, size_t& outIndex) {
                return targetStruct.tryGetFieldIndexByName(outIndex, idRef);
            };

            const bool found = resolveAggregateChildIndex(sema, children, childRef, fields.size(), findFieldIndex, fieldIndex);
            if (!found || fieldIndex >= fields.size() || !fields[fieldIndex])
                return TypeRef::invalid();

            return fields[fieldIndex]->typeRef();
        }

        if (!targetType.isAggregateStruct())
            return TypeRef::invalid();

        const auto& aggregate = targetType.payloadAggregate();
        const auto  resolveMemberIndex = [&](IdentifierRef idRef, size_t& outIndex) {
            return targetType.tryGetAggregateMemberIndexByName(outIndex, sema.ctx(), idRef);
        };

        const bool found = resolveAggregateChildIndex(sema, children, childRef, aggregate.types.size(), resolveMemberIndex, fieldIndex);
        if (!found || fieldIndex >= aggregate.types.size())
            return TypeRef::invalid();

        return aggregate.types[fieldIndex];
    }

    SemaEscapeInfo childrenEscapeInfo(Sema& sema, const AstNode& node, uint32_t& budget)
    {
        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());

        SemaEscapeInfo result;
        for (const AstNodeRef childRef : children)
            result = mergeEscapeInfo(result, expressionEscapeInfoRec(sema, childRef, budget));
        return result;
    }

    SemaEscapeInfo argumentEscapeInfo(Sema& sema, AstNodeRef argRef, uint32_t& budget)
    {
        return expressionEscapeInfoRec(sema, argumentValueRef(sema, argRef), budget);
    }

    bool expressionMayExposeStorageBorrow(Sema& sema, AstNodeRef exprRef)
    {
        const TypeRef typeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, exprRef));
        return typeRef.isValid() && !isDirectBorrowCarrier(sema, typeRef);
    }

    SemaEscapeInfo borrowInfoFromCallArgument(Sema& sema, const ResolvedCallArgument& arg, TypeRef resultTypeRef, uint32_t& budget)
    {
        SemaEscapeInfo info = argumentEscapeInfo(sema, arg.argRef, budget);
        if (info.hasBorrow())
        {
            info.typeRef = resultTypeRef;
            return info;
        }

        const AstNodeRef valueRef = argumentValueRef(sema, arg.argRef);
        if (!expressionMayExposeStorageBorrow(sema, valueRef))
            return {};

        return storageBorrowInfo(sema, valueRef, resultTypeRef);
    }

    SemaEscapeInfo borrowInfoFromStorageExpression(Sema& sema, AstNodeRef exprRef, TypeRef resultTypeRef, uint32_t& budget)
    {
        SemaEscapeInfo info = expressionEscapeInfoRec(sema, exprRef, budget);
        if (info.hasBorrow())
        {
            info.typeRef = resultTypeRef;
            return info;
        }

        const AstNodeRef valueRef = argumentValueRef(sema, exprRef);
        if (!expressionMayExposeStorageBorrow(sema, valueRef))
            return {};

        return storageBorrowInfo(sema, valueRef, resultTypeRef);
    }

    SemaEscapeInfo intrinsicCallEscapeInfo(Sema& sema, AstNodeRef intrinsicRef, const AstIntrinsicCall& intrinsic, uint32_t& budget)
    {
        const Token& tok = sema.token(sema.node(intrinsicRef).codeRef());
        if (!tok.isAny({TokenId::IntrinsicMakeString, TokenId::IntrinsicMakeSlice, TokenId::IntrinsicDataOf}))
            return {};

        SmallVector<AstNodeRef> children;
        sema.ast().appendNodes(children, intrinsic.spanChildrenRef);
        if (children.empty())
            return {};

        return borrowInfoFromStorageExpression(sema, children.front(), expressionTypeRef(sema, intrinsicRef), budget);
    }

    SemaEscapeInfo opCastEscapeInfo(Sema& sema, AstNodeRef castRef, const AstCastExpr& cast, TypeRef resultTypeRef, uint32_t& budget)
    {
        const auto* payload = sema.semaPayload<CastSpecOpPayload>(castRef);
        if (!payload || payload->kind != CastSpecialOpPayloadKind::OpCast || !payload->calledFn)
            return {};

        SmallVector<ResolvedCallArgument> args;
        sema.appendResolvedCallArguments(castRef, args);
        if (!args.empty() && args.front().argRef.isValid())
            return borrowInfoFromCallArgument(sema, args.front(), resultTypeRef, budget);

        if (expressionMayExposeStorageBorrow(sema, cast.nodeExprRef))
            return storageBorrowInfo(sema, cast.nodeExprRef, resultTypeRef);

        return {};
    }

    SemaEscapeInfo castEscapeInfo(Sema& sema, AstNodeRef castRef, const AstCastExpr& cast, uint32_t& budget)
    {
        const TypeRef resultTypeRef = expressionTypeRef(sema, castRef);
        SemaEscapeInfo info         = expressionEscapeInfoRec(sema, cast.nodeExprRef, budget);
        if (info.hasBorrow())
        {
            info.typeRef = resultTypeRef;
            return info;
        }

        if (!typeCanCarryBorrowImpl(sema, resultTypeRef))
            return {};

        info = opCastEscapeInfo(sema, castRef, cast, resultTypeRef, budget);
        if (info.hasBorrow())
            return info;

        const TypeRef sourceTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, cast.nodeExprRef));
        if (sourceTypeRef.isValid() && sema.typeMgr().get(sourceTypeRef).isArray())
            return storageBorrowInfo(sema, cast.nodeExprRef, resultTypeRef);

        return {};
    }

    SemaEscapeInfo indexEscapeInfo(Sema& sema, AstNodeRef indexRef, AstNodeRef indexedRef, uint32_t& budget)
    {
        SemaEscapeInfo info = expressionEscapeInfoRec(sema, indexedRef, budget);
        if (info.hasBorrow())
        {
            info.typeRef = expressionTypeRef(sema, indexRef);
            return info;
        }

        const TypeRef resultTypeRef = expressionTypeRef(sema, indexRef);
        if (!isDirectBorrowCarrier(sema, resultTypeRef))
            return {};

        if (isArrayStorageExpr(sema, indexedRef))
            return storageBorrowInfo(sema, indexedRef, resultTypeRef);

        return {};
    }

    SemaEscapeInfo unaryEscapeInfo(Sema& sema, AstNodeRef unaryRef, const AstUnaryExpr& unary, uint32_t& budget)
    {
        const Token& tok = sema.token(sema.node(unaryRef).codeRef());
        if (tok.id == TokenId::SymAmpersand)
            return storageBorrowInfo(sema, unary.nodeExprRef, expressionTypeRef(sema, unaryRef), true);

        SemaEscapeInfo info = expressionEscapeInfoRec(sema, unary.nodeExprRef, budget);
        if (info.hasBorrow())
            info.typeRef = expressionTypeRef(sema, unaryRef);
        return info;
    }

    SemaEscapeInfo expressionEscapeInfoRec(Sema& sema, AstNodeRef nodeRef, uint32_t& budget)
    {
        if (!budget || nodeRef.isInvalid())
            return {};
        budget--;

        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isInvalid())
            return {};

        const AstNode& node = sema.node(resolvedRef);
        switch (node.id())
        {
            case AstNodeId::Identifier:
            {
                const SymbolVariable* symVar = identifierVariable(sema, resolvedRef);
                if (!symVar)
                    return {};
                if (const SemaEscapeInfo* info = sema.variableEscapeInfo(*symVar))
                    return *info;
                return {};
            }

            case AstNodeId::ParenExpr:
                return expressionEscapeInfoRec(sema, node.cast<AstParenExpr>().nodeExprRef, budget);

            case AstNodeId::InitializerExpr:
                return expressionEscapeInfoRec(sema, node.cast<AstInitializerExpr>().nodeExprRef, budget);

            case AstNodeId::AutoCastExpr:
            {
                SemaEscapeInfo info = expressionEscapeInfoRec(sema, node.cast<AstAutoCastExpr>().nodeExprRef, budget);
                if (info.hasBorrow())
                    info.typeRef = expressionTypeRef(sema, resolvedRef);
                return info;
            }

            case AstNodeId::AsCastExpr:
            {
                SemaEscapeInfo info = expressionEscapeInfoRec(sema, node.cast<AstAsCastExpr>().nodeExprRef, budget);
                if (info.hasBorrow())
                    info.typeRef = expressionTypeRef(sema, resolvedRef);
                return info;
            }

            case AstNodeId::CastExpr:
                return castEscapeInfo(sema, resolvedRef, node.cast<AstCastExpr>(), budget);

            case AstNodeId::IntrinsicCall:
                return intrinsicCallEscapeInfo(sema, resolvedRef, node.cast<AstIntrinsicCall>(), budget);

            case AstNodeId::CallExpr:
            case AstNodeId::IntrinsicCallExpr:
                return {};

            case AstNodeId::NamedArgument:
                return expressionEscapeInfoRec(sema, node.cast<AstNamedArgument>().nodeArgRef, budget);

            case AstNodeId::MemberAccessExpr:
            {
                SemaEscapeInfo info = expressionEscapeInfoRec(sema, node.cast<AstMemberAccessExpr>().nodeLeftRef, budget);
                if (info.hasBorrow())
                    info.typeRef = expressionTypeRef(sema, resolvedRef);
                return info;
            }

            case AstNodeId::IndexExpr:
                return indexEscapeInfo(sema, resolvedRef, node.cast<AstIndexExpr>().nodeExprRef, budget);

            case AstNodeId::IndexListExpr:
                return indexEscapeInfo(sema, resolvedRef, node.cast<AstIndexListExpr>().nodeExprRef, budget);

            case AstNodeId::UnaryExpr:
                return unaryEscapeInfo(sema, resolvedRef, node.cast<AstUnaryExpr>(), budget);

            default:
                if (typeCanCarryBorrowImpl(sema, expressionTypeRef(sema, resolvedRef)))
                    return childrenEscapeInfo(sema, node, budget);
                return {};
        }
    }

    SemaEscapeInfo expressionEscapeInfo(Sema& sema, AstNodeRef nodeRef)
    {
        uint32_t budget = K_EXPR_BUDGET;
        return expressionEscapeInfoRec(sema, nodeRef, budget);
    }

    SemaEscapeInfo aggregateChildrenEscapeInfoWithTarget(Sema& sema, std::span<const AstNodeRef> children, TypeRef targetTypeRef, uint32_t& budget)
    {
        SemaEscapeInfo result;
        for (const AstNodeRef childRef : children)
        {
            const TypeRef childTargetTypeRef = structLikeChildTargetType(sema, children, childRef, targetTypeRef);
            if (!childTargetTypeRef.isValid())
                continue;

            result = mergeEscapeInfo(result, expressionEscapeInfoWithTarget(sema, childRef, childTargetTypeRef, budget));
        }

        return result;
    }

    SemaEscapeInfo expressionEscapeInfoWithTarget(Sema& sema, AstNodeRef nodeRef, TypeRef targetTypeRef, uint32_t& budget)
    {
        if (!budget || nodeRef.isInvalid())
            return {};

        const AstNode& rawNode = sema.node(nodeRef);
        switch (rawNode.id())
        {
            case AstNodeId::InitializerExpr:
                return expressionEscapeInfoWithTarget(sema, rawNode.cast<AstInitializerExpr>().nodeExprRef, targetTypeRef, budget);

            case AstNodeId::NamedArgument:
                return expressionEscapeInfoWithTarget(sema, rawNode.cast<AstNamedArgument>().nodeArgRef, targetTypeRef, budget);

            case AstNodeId::StructLiteral:
            {
                SmallVector<AstNodeRef> children;
                rawNode.cast<AstStructLiteral>().collectChildren(children, sema.ast());
                return aggregateChildrenEscapeInfoWithTarget(sema, children.span(), targetTypeRef, budget);
            }

            case AstNodeId::StructInitializerList:
            {
                SmallVector<AstNodeRef> children;
                AstNode::collectChildren(children, sema.ast(), rawNode.cast<AstStructInitializerList>().spanArgsRef);
                return aggregateChildrenEscapeInfoWithTarget(sema, children.span(), targetTypeRef, budget);
            }

            default:
                break;
        }

        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isInvalid())
            return {};

        const AstNode& node = sema.node(resolvedRef);
        switch (node.id())
        {
            case AstNodeId::InitializerExpr:
                return expressionEscapeInfoWithTarget(sema, node.cast<AstInitializerExpr>().nodeExprRef, targetTypeRef, budget);

            case AstNodeId::CastExpr:
            {
                SemaEscapeInfo info = castEscapeInfo(sema, resolvedRef, node.cast<AstCastExpr>(), budget);
                if (info.hasBorrow())
                {
                    info.typeRef = targetTypeRef;
                    return info;
                }

                return expressionEscapeInfoWithTarget(sema, node.cast<AstCastExpr>().nodeExprRef, targetTypeRef, budget);
            }

            case AstNodeId::NamedArgument:
                return expressionEscapeInfoWithTarget(sema, node.cast<AstNamedArgument>().nodeArgRef, targetTypeRef, budget);

            case AstNodeId::StructLiteral:
            {
                SmallVector<AstNodeRef> children;
                node.cast<AstStructLiteral>().collectChildren(children, sema.ast());
                return aggregateChildrenEscapeInfoWithTarget(sema, children.span(), targetTypeRef, budget);
            }

            case AstNodeId::StructInitializerList:
            {
                SmallVector<AstNodeRef> children;
                AstNode::collectChildren(children, sema.ast(), node.cast<AstStructInitializerList>().spanArgsRef);
                return aggregateChildrenEscapeInfoWithTarget(sema, children.span(), targetTypeRef, budget);
            }

            default:
                break;
        }

        SemaEscapeInfo info = expressionEscapeInfoRec(sema, resolvedRef, budget);
        if (info.hasBorrow())
        {
            info.typeRef = targetTypeRef;
            return info;
        }

        if (!isDirectBorrowCarrier(sema, targetTypeRef))
            return {};

        if (!expressionMayExposeStorageBorrow(sema, resolvedRef))
            return {};

        return storageBorrowInfo(sema, resolvedRef, targetTypeRef);
    }

    TypeRef destinationTypeRef(Sema& sema, AstNodeRef leftRef)
    {
        const SemaNodeView leftView = sema.viewType(leftRef);
        TypeRef            typeRef  = leftView.typeRef();
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        return type.isReference() ? type.payloadTypeRef() : typeRef;
    }

    void reportBorrowEscape(Sema& sema, AstNodeRef atNodeRef, const SemaEscapeInfo& info, std::string_view what)
    {
        if (!info.isLocalBorrow())
            return;

        auto diag = SemaError::report(sema, DiagnosticId::sema_warn_borrow_escape, atNodeRef);
        diag.addArgument(Diagnostic::ARG_SYM, info.sourceVar->name(sema.ctx()));
        diag.addArgument(Diagnostic::ARG_WHAT, what);
        if (info.typeRef.isValid())
            diag.addArgument(Diagnostic::ARG_TYPE, info.typeRef);

        diag.addNote(DiagnosticId::sema_note_borrow_source_declared_here);
        diag.last().addArgument(Diagnostic::ARG_SYM, info.sourceVar->name(sema.ctx()));
        diag.last().addSpan(info.sourceVar->codeRange(sema.ctx()));
        diag.report(sema.ctx());
    }

    void storeOrReportDestinationInfo(Sema& sema, const SymbolVariable& dstVar, AstNodeRef atNodeRef, const SemaEscapeInfo& info, std::string_view what)
    {
        if (info.sourceVar == &dstVar)
        {
            sema.clearVariableEscapeInfo(dstVar);
            return;
        }

        if (info.hasBorrow() && isLocalVariableStorage(sema, dstVar))
        {
            sema.setVariableEscapeInfo(dstVar, info);
            return;
        }

        if (info.isLocalBorrow())
            reportBorrowEscape(sema, atNodeRef, info, what);
    }

    bool variableInitializerCanEscape(const SymbolVariable& symVar)
    {
        return symVar.hasExtraFlag(SymbolVariableFlagsE::GlobalStorage) ||
               symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal);
    }
}

namespace SemaEscape
{
    bool typeCanCarryBorrow(Sema& sema, TypeRef typeRef)
    {
        return typeCanCarryBorrowImpl(sema, typeRef);
    }

    Result checkVariableInitializer(Sema& sema, const SymbolVariable& symVar, AstNodeRef initRef, TypeRef targetTypeRef)
    {
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) || symVar.isClosureCapture())
        {
            sema.clearVariableEscapeInfo(symVar);
            return Result::Continue;
        }

        if (!typeCanCarryBorrowImpl(sema, targetTypeRef))
        {
            sema.clearVariableEscapeInfo(symVar);
            return Result::Continue;
        }

        uint32_t                 budget = K_EXPR_BUDGET;
        const SemaEscapeInfo info       = expressionEscapeInfoWithTarget(sema, initRef, targetTypeRef, budget);
        if (!info.hasBorrow())
        {
            sema.clearVariableEscapeInfo(symVar);
            return Result::Continue;
        }

        if (info.sourceVar == &symVar)
            sema.clearVariableEscapeInfo(symVar);
        else if (isLocalVariableStorage(sema, symVar))
            sema.setVariableEscapeInfo(symVar, info);
        else if (info.isLocalBorrow() && variableInitializerCanEscape(symVar))
            reportBorrowEscape(sema, initRef, info, "an initializer");
        else
            sema.clearVariableEscapeInfo(symVar);
        return Result::Continue;
    }

    Result applyAssignment(Sema& sema, AstNodeRef leftRef, AstNodeRef rightRef)
    {
        const TypeRef targetTypeRef = destinationTypeRef(sema, leftRef);

        bool                  wholeVariable = false;
        const SymbolVariable* dstVar        = storageRootVariable(sema, leftRef, true, wholeVariable);
        if (!typeCanCarryBorrowImpl(sema, targetTypeRef))
        {
            if (dstVar && wholeVariable)
                sema.clearVariableEscapeInfo(*dstVar);
            return Result::Continue;
        }

        uint32_t                 budget = K_EXPR_BUDGET;
        const SemaEscapeInfo info       = expressionEscapeInfoWithTarget(sema, rightRef, targetTypeRef, budget);
        if (!info.hasBorrow())
        {
            if (dstVar && wholeVariable)
                sema.clearVariableEscapeInfo(*dstVar);
            return Result::Continue;
        }

        if (dstVar)
            storeOrReportDestinationInfo(sema, *dstVar, leftRef, info, "an assignment");
        else if (info.isLocalBorrow())
            reportBorrowEscape(sema, leftRef, info, "an assignment");

        return Result::Continue;
    }

    Result checkReturn(Sema& sema, AstNodeRef exprRef, TypeRef returnTypeRef)
    {
        if (!typeCanCarryBorrowImpl(sema, returnTypeRef))
            return Result::Continue;

        uint32_t                 budget = K_EXPR_BUDGET;
        const SemaEscapeInfo info       = expressionEscapeInfoWithTarget(sema, exprRef, returnTypeRef, budget);
        if (info.isLocalBorrow())
            reportBorrowEscape(sema, exprRef, info, "a return value");

        return Result::Continue;
    }

    Result checkClosureCapture(Sema& sema, AstNodeRef captureRef, const SymbolVariable& sourceVar, bool captureByRef)
    {
        if (captureByRef)
            return Result::Continue;

        const SemaEscapeInfo* info = sema.variableEscapeInfo(sourceVar);
        if (info && info->isLocalBorrow())
            reportBorrowEscape(sema, captureRef, *info, "a closure capture");

        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
