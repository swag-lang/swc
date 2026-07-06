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
               type.isAny() ||
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

    SemaEscapeInfo mergeEscapeInfo(const SemaEscapeInfo& left, const SemaEscapeInfo& right)
    {
        return right.rank() > left.rank() ? right : left;
    }

    // A by-value parameter is a copy living in the callee frame: its storage behaves
    // exactly like a local. Only pointer/reference parameters reach caller-owned data.
    bool isByValueParameterStorage(Sema& sema, const SymbolVariable& symVar)
    {
        if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
            return false;

        const TypeRef paramTypeRef = unwrapAliasEnum(sema, symVar.typeRef());
        if (!paramTypeRef.isValid())
            return false;

        const TypeInfo& paramType = sema.typeMgr().get(paramTypeRef);
        return !paramType.isAnyPointer() && !paramType.isReference() && !paramType.isAnyVariadic();
    }

    bool isLocalVariableStorage(Sema& sema, const SymbolVariable& symVar)
    {
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::GlobalStorage) ||
            symVar.hasExtraFlag(SymbolVariableFlagsE::RuntimeStorage) ||
            symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal))
            return false;

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
            return isByValueParameterStorage(sema, symVar);

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
            info.kind = isByValueParameterStorage(sema, symVar) ? SemaEscapeKind::Local : SemaEscapeKind::Parameter;
        else if (isLocalVariableStorage(sema, symVar))
            info.kind = SemaEscapeKind::Local;
        else
        {
            // Inside a method, a symbol that is neither a parameter, a local nor a global
            // is a struct field reached through the implicit 'me' receiver: caller-owned
            // data, rooted at the receiver so returns feed the borrow summary.
            const SymbolFunction* currentFn = sema.currentFunction();
            if (currentFn &&
                currentFn->hasExtraFlag(SymbolFunctionFlagsE::Method) &&
                !currentFn->parameters().empty())
            {
                info.sourceVar = currentFn->parameters().front();
                info.kind      = SemaEscapeKind::Parameter;
            }
            else
                info.kind = SemaEscapeKind::Unknown;
        }

        return info;
    }

    const SymbolVariable* identifierVariable(Sema& sema, AstNodeRef nodeRef)
    {
        SemaNodeView view = sema.viewSymbol(nodeRef);
        if (!view.hasSymbol() || !view.sym())
        {
            // A substituted node (an implicit cast wrapper, ...) has no symbol of its own:
            // fall back to the symbol stored on the original node.
            view = sema.viewStored(nodeRef, SemaNodeViewPartE::Symbol);
        }

        if (!view.hasSymbol() || !view.sym() || !view.sym()->isVariable())
            return nullptr;
        return &view.sym()->cast<SymbolVariable>();
    }

    // 'Cast::createCast' substitutes the source node with the cast wrapper itself, so
    // resolved views on the operand loop back to the cast. Such operands must be analyzed
    // through their stored (pre-substitution) node and type.
    bool castOperandSelfSubstituted(Sema& sema, AstNodeRef castRef, AstNodeRef operandRef)
    {
        return operandRef.isValid() && sema.viewZero(operandRef).nodeRef() == castRef;
    }

    TypeRef castOperandTypeRef(Sema& sema, AstNodeRef castRef, AstNodeRef operandRef)
    {
        if (operandRef.isInvalid())
            return TypeRef::invalid();
        if (castOperandSelfSubstituted(sema, castRef, operandRef))
            return sema.viewStored(operandRef, SemaNodeViewPartE::Type).typeRef();
        return expressionTypeRef(sema, operandRef);
    }

    bool isArrayStorageExpr(Sema& sema, AstNodeRef nodeRef)
    {
        const TypeRef typeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, nodeRef));
        return typeRef.isValid() && sema.typeMgr().get(typeRef).isArray();
    }

    const SymbolVariable* storageRootVariableAt(Sema& sema, AstNodeRef resolvedRef, bool forAssignment, bool& outWholeVariable);

    const SymbolVariable* storageRootVariable(Sema& sema, AstNodeRef nodeRef, bool forAssignment, bool& outWholeVariable)
    {
        outWholeVariable = false;
        if (nodeRef.isInvalid())
            return nullptr;

        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isInvalid())
            return nullptr;

        return storageRootVariableAt(sema, resolvedRef, forAssignment, outWholeVariable);
    }

    const SymbolVariable* storageRootVariableAt(Sema& sema, AstNodeRef resolvedRef, bool forAssignment, bool& outWholeVariable)
    {
        outWholeVariable = false;

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
            {
                const AstNodeRef operandRef = node.cast<AstCastExpr>().nodeExprRef;
                if (castOperandSelfSubstituted(sema, resolvedRef, operandRef))
                    return storageRootVariableAt(sema, operandRef, forAssignment, outWholeVariable);
                return storageRootVariable(sema, operandRef, forAssignment, outWholeVariable);
            }

            case AstNodeId::MemberAccessExpr:
            {
                const AstNodeRef leftRef      = node.cast<AstMemberAccessExpr>().nodeLeftRef;
                const TypeRef    leftTypeRef  = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, leftRef));
                if (isDirectBorrowCarrier(sema, leftTypeRef))
                {
                    // Accessing storage through a pointer that itself borrows a known local
                    // stays inside that local's storage: keep tracking on the borrowed root.
                    bool leftWholeVariable = false;
                    if (const SymbolVariable* leftVar = storageRootVariable(sema, leftRef, false, leftWholeVariable); leftVar && leftWholeVariable)
                    {
                        const SemaEscapeInfo* leftInfo = sema.variableEscapeInfo(*leftVar);
                        if (leftInfo && leftInfo->isLocalBorrow())
                        {
                            outWholeVariable = false;
                            return leftInfo->sourceVar;
                        }

                        // Writing through a local pointer reaches storage only known to this
                        // frame so far: track the borrow on the pointer variable and report
                        // later if that pointer itself escapes. Writing through a parameter
                        // or global pointer reaches caller-visible storage and must report.
                        if (forAssignment && isLocalVariableStorage(sema, *leftVar))
                        {
                            outWholeVariable = false;
                            return leftVar;
                        }

                        // Data reached through a pointer/reference parameter (including the
                        // body 'me' binding) belongs to the caller: root at the parameter so
                        // returns feed the borrow summary.
                        if (!forAssignment)
                        {
                            const SemaEscapeInfo leftStorage = variableStorageInfo(sema, *leftVar, leftRef, TypeRef::invalid());
                            if (leftStorage.kind == SemaEscapeKind::Parameter && leftStorage.sourceVar)
                            {
                                outWholeVariable = false;
                                return leftStorage.sourceVar;
                            }
                        }
                    }

                    return nullptr;
                }

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
            {
                const auto& unary = node.cast<AstUnaryExpr>();

                // 'dref ptr' designates the pointee storage, not the pointer variable: it is
                // a borrow root only when the pointer itself borrows a tracked local. A heap
                // or caller-owned pointee is not a borrow root.
                if (sema.token(node.codeRef()).id == TokenId::KwdDRef)
                {
                    bool operandWholeVariable = false;
                    if (const SymbolVariable* operandVar = storageRootVariable(sema, unary.nodeExprRef, false, operandWholeVariable); operandVar && operandWholeVariable)
                    {
                        const SemaEscapeInfo* operandInfo = sema.variableEscapeInfo(*operandVar);
                        if (operandInfo && operandInfo->isLocalBorrow())
                        {
                            outWholeVariable = false;
                            return operandInfo->sourceVar;
                        }

                        // Same rule as member access through a pointer: assigning through a
                        // local pointer tracks the borrow on that pointer instead of reporting.
                        if (forAssignment && isLocalVariableStorage(sema, *operandVar))
                        {
                            outWholeVariable = false;
                            return operandVar;
                        }

                        // Data reached through a pointer/reference parameter (including the
                        // body 'me' binding) belongs to the caller: root at the parameter so
                        // returns feed the borrow summary.
                        if (!forAssignment)
                        {
                            const SemaEscapeInfo operandStorage = variableStorageInfo(sema, *operandVar, unary.nodeExprRef, TypeRef::invalid());
                            if (operandStorage.kind == SemaEscapeKind::Parameter && operandStorage.sourceVar)
                            {
                                outWholeVariable = false;
                                return operandStorage.sourceVar;
                            }
                        }
                    }

                    return nullptr;
                }

                return forAssignment ? nullptr : storageRootVariable(sema, unary.nodeExprRef, forAssignment, outWholeVariable);
            }

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
    SemaEscapeInfo expressionEscapeInfoAt(Sema& sema, AstNodeRef resolvedRef, uint32_t& budget);
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

    // Only composite storage can be aliased by an implicit carrier binding (array decay,
    // opCast borrowing 'self', interface creation, ...). Scalars convert by value: casting
    // a 'u64' to a pointer reinterprets the value and never borrows the variable storage.
    bool typeHasBorrowableStorage(Sema& sema, TypeRef typeRef)
    {
        typeRef = unwrapAliasEnum(sema, typeRef);
        if (!typeRef.isValid())
            return false;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isArray() || type.isAggregate())
            return true;

        if (!type.isStruct())
            return false;

        // Owner structs such as Core.String manage their payload through their lifecycle:
        // a view of their storage is an ownership question, not a frame borrow.
        return !hasOwningLifecycle(sema, typeRef);
    }

    bool expressionMayExposeStorageBorrow(Sema& sema, AstNodeRef exprRef)
    {
        const TypeRef typeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, exprRef));
        return typeRef.isValid() && !isDirectBorrowCarrier(sema, typeRef) && typeHasBorrowableStorage(sema, typeRef);
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

        // An implicit conversion substitutes its source node with this wrapper: the resolved
        // 'self' argument loops back here, so analyze the stored operand instead.
        if (castOperandSelfSubstituted(sema, castRef, cast.nodeExprRef))
        {
            const TypeRef operandTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), castOperandTypeRef(sema, castRef, cast.nodeExprRef));
            if (!operandTypeRef.isValid() || isDirectBorrowCarrier(sema, operandTypeRef) || !typeHasBorrowableStorage(sema, operandTypeRef))
                return {};

            return storageBorrowInfo(sema, cast.nodeExprRef, resultTypeRef, true);
        }

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
        const TypeRef resultTypeRef        = expressionTypeRef(sema, castRef);
        const bool    operandSelfSubst     = castOperandSelfSubstituted(sema, castRef, cast.nodeExprRef);
        SemaEscapeInfo info                = operandSelfSubst
                                                 ? expressionEscapeInfoAt(sema, cast.nodeExprRef, budget)
                                                 : expressionEscapeInfoRec(sema, cast.nodeExprRef, budget);
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

        // Casting composite storage to a carrier aliases that storage: array decay to a
        // slice, boxing a value into 'any', building an interface from a struct, ...
        const TypeRef sourceTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), castOperandTypeRef(sema, castRef, cast.nodeExprRef));
        if (sourceTypeRef.isValid() &&
            isDirectBorrowCarrier(sema, resultTypeRef) &&
            !isDirectBorrowCarrier(sema, sourceTypeRef) &&
            typeHasBorrowableStorage(sema, sourceTypeRef))
        {
            info = storageBorrowInfo(sema, cast.nodeExprRef, resultTypeRef, operandSelfSubst);
            if (info.hasBorrow())
                return info;

            // No variable roots the storage: an rvalue produced by a call or materialized
            // from a literal is a temporary destroyed at the end of the statement.
            const AstNodeRef operandRef = operandSelfSubst ? cast.nodeExprRef : sema.viewZero(cast.nodeExprRef).nodeRef();
            if (operandRef.isValid())
            {
                const AstNode& operandNode = sema.node(operandRef);
                if (operandNode.is(AstNodeId::CallExpr) ||
                    operandNode.is(AstNodeId::IntrinsicCallExpr) ||
                    operandNode.is(AstNodeId::StructLiteral) ||
                    operandNode.is(AstNodeId::StructInitializerList))
                {
                    // A structural cast of an rvalue is ALWAYS materialized by the compiler
                    // into a frame-lifetime runtime storage (Cast::runtimeStorageTypeRef:
                    // array→slice/string, value→any, struct→interface, ...): nothing dies at
                    // end of statement. Only a user 'opCast' borrows the rvalue itself — its
                    // runtime storage holds the call RESULT, not the source.
                    const auto* specOp   = sema.semaPayload<CastSpecOpPayload>(castRef);
                    const bool  isOpCast = specOp && specOp->kind == CastSpecialOpPayloadKind::OpCast && specOp->calledFn;
                    if (!isOpCast)
                        return {};

                    info.kind      = SemaEscapeKind::Temporary;
                    info.sourceRef = operandRef;
                    info.typeRef   = resultTypeRef;
                    return info;
                }
            }

            return {};
        }

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

        if (!isArrayStorageExpr(sema, indexedRef))
            return {};

        // Reading a carrier ELEMENT by value copies it: the copy does not alias the array
        // storage. Only slicing (the result aliases the elements themselves) borrows it.
        const TypeRef arrayTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, indexedRef));
        const TypeRef elemTypeRef  = arrayTypeRef.isValid() ? sema.typeMgr().get(arrayTypeRef).payloadArrayElemTypeRef() : TypeRef::invalid();
        if (elemTypeRef.isValid() && unwrapAliasEnum(sema, elemTypeRef) == unwrapAliasEnum(sema, resultTypeRef))
            return {};

        return storageBorrowInfo(sema, indexedRef, resultTypeRef);
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

    // A closure value carries the borrows of its captures: capturing by reference borrows
    // the source storage itself, and capturing a borrowing value (a pointer to a local, ...)
    // by value propagates that borrow. The borrow is reported only when the closure value
    // escapes (return, assignment to escaping storage, ...), not at the capture itself.
    SemaEscapeInfo closureEscapeInfo(Sema& sema, AstNodeRef closureRef, const AstClosureExpr& closure)
    {
        SmallVector<AstNodeRef> captures;
        sema.ast().appendNodes(captures, closure.nodeCaptureArgsRef);

        const TypeRef  closureTypeRef = expressionTypeRef(sema, closureRef);
        SemaEscapeInfo result;
        for (const AstNodeRef captureRef : captures)
        {
            const auto*           captureArg = sema.node(captureRef).safeCast<AstClosureArgument>();
            const SymbolVariable* sourceVar  = captureArg ? identifierVariable(sema, captureArg->nodeIdentifierRef) : nullptr;
            if (!sourceVar)
                continue;

            if (captureArg->hasFlag(AstClosureArgumentFlagsE::Address))
                result = mergeEscapeInfo(result, variableStorageInfo(sema, *sourceVar, captureArg->nodeIdentifierRef, closureTypeRef));
            else if (const SemaEscapeInfo* info = sema.variableEscapeInfo(*sourceVar))
                result = mergeEscapeInfo(result, *info);
        }

        if (result.hasBorrow())
            result.typeRef = closureTypeRef;
        return result;
    }

    SemaEscapeInfo expressionEscapeInfoRec(Sema& sema, AstNodeRef nodeRef, uint32_t& budget)
    {
        if (!budget || nodeRef.isInvalid())
            return {};
        budget--;

        const AstNode& rawNode = sema.node(nodeRef);
        if (rawNode.is(AstNodeId::ClosureExpr))
            return closureEscapeInfo(sema, nodeRef, rawNode.cast<AstClosureExpr>());

        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isInvalid())
            return {};

        return expressionEscapeInfoAt(sema, resolvedRef, budget);
    }

    const SymbolFunction* resolvedCallFunction(Sema& sema, AstNodeRef callRef, AstNodeRef calleeRef)
    {
        const auto singleFunction = [](const SemaNodeView& view) -> const SymbolFunction* {
            Symbol* symbol = view.singleSymbol();
            if (!symbol || !symbol->isFunction())
                return nullptr;
            return &symbol->cast<SymbolFunction>();
        };

        if (const SymbolFunction* fn = singleFunction(sema.viewSymbol(callRef)))
            return fn;
        if (calleeRef.isValid())
        {
            if (const SymbolFunction* fn = singleFunction(sema.viewSymbol(calleeRef)))
                return fn;
        }

        return nullptr;
    }

    // The per-function summary recorded by checkReturn: when the callee's returned value
    // may borrow one of its parameters, the call result borrows the matching arguments.
    //
    // NOT CONSUMED YET: sema jobs run in a non-deterministic order, so an intra-module
    // callee may or may not be sema-completed when its call site is analyzed — and
    // waiting for a function body from another function body turns legal mutual
    // recursion into a stalled-dependency error (SemaCycle). Consuming the mask here
    // would make the warnings flicker between otherwise identical builds. Activation
    // needs either an end-of-module recheck pass or the mask serialized in the module
    // API plus topological gating.
    SemaEscapeInfo callResultEscapeInfo(Sema& sema, AstNodeRef callRef, const AstCallExpr& call, uint32_t& budget)
    {
        SWC_UNUSED(call);
        SWC_UNUSED(callRef);
        SWC_UNUSED(sema);
        SWC_UNUSED(budget);
        return {};
    }

    SemaEscapeInfo expressionEscapeInfoAt(Sema& sema, AstNodeRef resolvedRef, uint32_t& budget)
    {
        if (!budget)
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

                // A carrier-typed parameter value transports caller-owned data: synthesize
                // its borrow so copies and returns feed the per-function borrow summaries.
                if (symVar->hasExtraFlag(SymbolVariableFlagsE::Parameter))
                {
                    const TypeRef paramTypeRef = unwrapAliasEnum(sema, symVar->typeRef());
                    if (paramTypeRef.isValid() && isDirectBorrowCarrier(sema, paramTypeRef))
                    {
                        SemaEscapeInfo info;
                        info.kind      = SemaEscapeKind::Parameter;
                        info.sourceVar = symVar;
                        info.sourceRef = resolvedRef;
                        info.typeRef   = symVar->typeRef();
                        return info;
                    }
                }

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
                return callResultEscapeInfo(sema, resolvedRef, node.cast<AstCallExpr>(), budget);

            case AstNodeId::IntrinsicCallExpr:
                return {};

            case AstNodeId::NamedArgument:
                return expressionEscapeInfoRec(sema, node.cast<AstNamedArgument>().nodeArgRef, budget);

            case AstNodeId::MemberAccessExpr:
            {
                SemaEscapeInfo info = expressionEscapeInfoRec(sema, node.cast<AstMemberAccessExpr>().nodeLeftRef, budget);
                if (info.hasBorrow())
                {
                    // Reading a carrier member copies its value: the copy does not alias
                    // the borrowed storage. Only a composite member designates storage
                    // inside it and keeps the borrow alive.
                    const TypeRef memberTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, resolvedRef));
                    if (isDirectBorrowCarrier(sema, memberTypeRef))
                        return {};

                    info.typeRef = expressionTypeRef(sema, resolvedRef);
                }

                return info;
            }

            case AstNodeId::IndexExpr:
                return indexEscapeInfo(sema, resolvedRef, node.cast<AstIndexExpr>().nodeExprRef, budget);

            case AstNodeId::IndexListExpr:
                return indexEscapeInfo(sema, resolvedRef, node.cast<AstIndexListExpr>().nodeExprRef, budget);

            case AstNodeId::UnaryExpr:
                return unaryEscapeInfo(sema, resolvedRef, node.cast<AstUnaryExpr>(), budget);

            case AstNodeId::ClosureExpr:
                return closureEscapeInfo(sema, resolvedRef, node.cast<AstClosureExpr>());

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

            case AstNodeId::ClosureExpr:
                return closureEscapeInfo(sema, nodeRef, rawNode.cast<AstClosureExpr>());

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
                const auto&    castNode = node.cast<AstCastExpr>();
                SemaEscapeInfo info     = castEscapeInfo(sema, resolvedRef, castNode, budget);
                if (info.hasBorrow())
                {
                    info.typeRef = targetTypeRef;
                    return info;
                }

                // A self-substituted operand resolves back to this wrapper: recursing would
                // loop. castEscapeInfo already analyzed the stored operand, except for the
                // literal shapes the raw switch above handles directly.
                if (castOperandSelfSubstituted(sema, resolvedRef, castNode.nodeExprRef))
                {
                    const AstNode& rawOperand = sema.node(castNode.nodeExprRef);
                    if (rawOperand.isNot(AstNodeId::InitializerExpr) &&
                        rawOperand.isNot(AstNodeId::ClosureExpr) &&
                        rawOperand.isNot(AstNodeId::NamedArgument) &&
                        rawOperand.isNot(AstNodeId::StructLiteral) &&
                        rawOperand.isNot(AstNodeId::StructInitializerList))
                        return {};
                }

                return expressionEscapeInfoWithTarget(sema, castNode.nodeExprRef, targetTypeRef, budget);
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

    // Under the Lifecycle safety contract a dangling borrow is a hard error, not advice.
    bool lifecycleSafetyEnabled(Sema& sema)
    {
        return sema.frame().currentAttributes().hasRuntimeSafety(sema.buildCfg().safetyGuards, Runtime::SafetyWhat::Lifecycle);
    }

    Result reportBorrowEscape(Sema& sema, AstNodeRef atNodeRef, const SemaEscapeInfo& info, std::string_view what)
    {
        const bool asError = lifecycleSafetyEnabled(sema);

        if (info.isTemporaryBorrow())
        {
            auto diag = SemaError::report(sema, asError ? DiagnosticId::sema_err_borrow_temporary : DiagnosticId::sema_warn_borrow_temporary, atNodeRef);
            diag.addArgument(Diagnostic::ARG_WHAT, what);
            if (info.typeRef.isValid())
                diag.addArgument(Diagnostic::ARG_TYPE, info.typeRef);

            if (info.sourceRef.isValid())
            {
                diag.addNote(DiagnosticId::sema_note_borrow_temporary_here);
                diag.last().addSpan(sema.node(info.sourceRef).codeRange(sema.ctx()));
            }

            diag.report(sema.ctx());
            return asError ? Result::Error : Result::Continue;
        }

        if (!info.isLocalBorrow())
            return Result::Continue;

        auto diag = SemaError::report(sema, asError ? DiagnosticId::sema_err_borrow_escape : DiagnosticId::sema_warn_borrow_escape, atNodeRef);
        diag.addArgument(Diagnostic::ARG_SYM, info.sourceVar->name(sema.ctx()));
        diag.addArgument(Diagnostic::ARG_WHAT, what);
        if (info.typeRef.isValid())
            diag.addArgument(Diagnostic::ARG_TYPE, info.typeRef);

        diag.addNote(DiagnosticId::sema_note_borrow_source_declared_here);
        diag.last().addArgument(Diagnostic::ARG_SYM, info.sourceVar->name(sema.ctx()));
        diag.last().addSpan(info.sourceVar->codeRange(sema.ctx()));
        diag.report(sema.ctx());
        return asError ? Result::Error : Result::Continue;
    }

    Result reportBorrowScopeEscape(Sema& sema, AstNodeRef atNodeRef, const SemaEscapeInfo& info, const SymbolVariable& dstVar)
    {
        const bool asError = lifecycleSafetyEnabled(sema);

        auto diag = SemaError::report(sema, asError ? DiagnosticId::sema_err_borrow_scope_escape : DiagnosticId::sema_warn_borrow_scope_escape, atNodeRef);
        diag.addArgument(Diagnostic::ARG_SYM, info.sourceVar->name(sema.ctx()));
        diag.addArgument(Diagnostic::ARG_VALUE, dstVar.name(sema.ctx()));

        diag.addNote(DiagnosticId::sema_note_borrow_source_declared_here);
        diag.last().addArgument(Diagnostic::ARG_SYM, info.sourceVar->name(sema.ctx()));
        diag.last().addSpan(info.sourceVar->codeRange(sema.ctx()));
        diag.report(sema.ctx());
        return asError ? Result::Error : Result::Continue;
    }

    Result storeOrReportDestinationInfo(Sema& sema, const SymbolVariable& dstVar, AstNodeRef atNodeRef, const SemaEscapeInfo& info, std::string_view what)
    {
        // A borrow of a temporary outlives it as soon as it is bound anywhere.
        if (info.isTemporaryBorrow())
            return reportBorrowEscape(sema, atNodeRef, info, what);

        if (info.sourceVar == &dstVar)
        {
            sema.clearVariableEscapeInfo(dstVar);
            return Result::Continue;
        }

        if (info.hasBorrow() && isLocalVariableStorage(sema, dstVar))
        {
            // Storing a borrow of a variable declared in a DEEPER scope: the destination
            // outlives the borrowed storage even though both live in the same frame.
            if (info.isLocalBorrow())
            {
                const uint32_t srcDepth = sema.variableScopeDepth(*info.sourceVar);
                const uint32_t dstDepth = sema.variableScopeDepth(dstVar);
                if (srcDepth && dstDepth && srcDepth > dstDepth)
                    return reportBorrowScopeEscape(sema, atNodeRef, info, dstVar);
            }

            sema.setVariableEscapeInfo(dstVar, info);
            return Result::Continue;
        }

        if (info.isLocalBorrow())
            return reportBorrowEscape(sema, atNodeRef, info, what);

        return Result::Continue;
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

        // A borrow of a temporary outlives it as soon as it is bound to a variable.
        // Bindings materialized by an inline expansion live within the enclosing
        // statement, exactly like the temporary itself: nothing escapes there.
        if (info.isTemporaryBorrow())
        {
            Result reportResult = Result::Continue;
            if (!SemaHelpers::effectiveInlinePayload(sema))
                reportResult = reportBorrowEscape(sema, initRef, info, "an initializer");
            sema.clearVariableEscapeInfo(symVar);
            return reportResult;
        }

        if (info.sourceVar == &symVar)
            sema.clearVariableEscapeInfo(symVar);
        else if (isLocalVariableStorage(sema, symVar))
            sema.setVariableEscapeInfo(symVar, info);
        else if (info.isLocalBorrow() && variableInitializerCanEscape(symVar))
            return reportBorrowEscape(sema, initRef, info, "an initializer");
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
            return storeOrReportDestinationInfo(sema, *dstVar, leftRef, info, "an assignment");
        if (info.isLocalBorrow() || info.isTemporaryBorrow())
            return reportBorrowEscape(sema, leftRef, info, "an assignment");

        return Result::Continue;
    }

    // A 'foreach &it' alias points into the iterated storage: bind the alias to that
    // storage's borrow so uses of 'it' escaping the loop are tracked like any pointer.
    void bindForeachAddressAlias(Sema& sema, const SymbolVariable& symVar, AstNodeRef exprRef)
    {
        uint32_t       budget = K_EXPR_BUDGET;
        SemaEscapeInfo info   = expressionEscapeInfoRec(sema, exprRef, budget);
        if (!info.hasBorrow() && expressionMayExposeStorageBorrow(sema, exprRef))
            info = storageBorrowInfo(sema, exprRef, symVar.typeRef());

        if (info.hasBorrow())
            sema.setVariableEscapeInfo(symVar, info);
        else
            sema.clearVariableEscapeInfo(symVar);
    }

    Result checkReturn(Sema& sema, AstNodeRef returnRef, AstNodeRef exprRef, TypeRef returnTypeRef, const SymbolFunction* inlineSourceFn)
    {
        if (!typeCanCarryBorrowImpl(sema, returnTypeRef))
            return Result::Continue;

        uint32_t                 budget = K_EXPR_BUDGET;
        const SemaEscapeInfo info       = expressionEscapeInfoWithTarget(sema, exprRef, returnTypeRef, budget);

        // A temporary lives until the end of the enclosing statement. An inline-expanded
        // return hands it to the call site within that same statement, so only a real
        // function return outlives it; bindings at the call site handle the rest.
        if (info.isTemporaryBorrow())
        {
            if (!inlineSourceFn)
                return reportBorrowEscape(sema, returnRef, info, "a return value");
            return Result::Continue;
        }

        // Returning a borrow of caller-owned data is fine for THIS function, but feeds
        // the per-function summary consumed at call sites (callResultEscapeInfo).
        if (!inlineSourceFn && info.kind == SemaEscapeKind::Parameter && info.sourceVar)
        {
            if (SymbolFunction* currentFn = sema.currentFunction())
            {
                const auto& params = currentFn->parameters();
                for (size_t i = 0; i < params.size(); ++i)
                {
                    if (params[i] == info.sourceVar)
                    {
                        currentFn->addReturnBorrowsParam(i);
                        break;
                    }
                }
            }
        }

        if (!info.isLocalBorrow())
            return Result::Continue;

        // A return inside an inline expansion hands the value back to the calling frame:
        // borrowing the caller's own storage does not escape anything. Only storage the
        // inlined callee owns dies with the expansion.
        if (inlineSourceFn && info.sourceVar &&
            !info.sourceVar->isFunctionLocalVariable(*inlineSourceFn) &&
            !inlineSourceFn->containsLocalVariable(*info.sourceVar))
            return Result::Continue;

        return reportBorrowEscape(sema, returnRef, info, "a return value");
    }
}

SWC_END_NAMESPACE();
