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
#include "Main/CompilerInstance.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Recursive shape probes are conservative filters, not proof engines. The caps keep
    // pathological recursive types/expressions from turning borrow checking into an
    // unbounded walk; exhausting a budget means "do not infer a borrow carrier".
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
        // Bindings are tracked on the storage they ultimately expose. Strip aliases,
        // enum wrappers and references so later checks compare the carried payload,
        // not the syntax that happened to produce it.
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

    bool isDirectStorageHandle(Sema& sema, TypeRef typeRef)
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

    bool localProjectionRootCanReceiveLocalStore(Sema& sema, const SymbolVariable& root)
    {
        if (!isDirectStorageHandle(sema, root.typeRef()))
            return true;

        const SemaEscapeInfo* info = sema.variableEscapeInfo(root);
        return !info || info->isLocalBorrow() || info->isMaterializedBorrow();
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

        // Structural carriers are discovered through fields/elements, but cycles are
        // common in user types. A back-edge only says "already being inspected", so
        // treat it as neutral and let another path prove the carrier if one exists.
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

        // A struct still being analyzed can grow its field vector concurrently:
        // iterating it would race. Conservative no-carrier answer (no tracking, never
        // a false positive).
        if (!type.payloadSymStruct().isSemaCompleted())
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
        SemaEscapeInfo result = left;
        result.mergeFrom(right);
        return result;
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

    void setParameterOrigin(Sema& sema, SemaEscapeInfo& info, const SymbolVariable& parameter)
    {
        const SymbolFunction* currentFn = sema.currentFunction();
        if (!currentFn)
            return;

        const auto& params = currentFn->parameters();
        for (size_t i = 0; i < params.size() && i < 64; ++i)
        {
            if (params[i] == &parameter)
            {
                info.parameterOriginsMask = 1ULL << i;
                return;
            }
        }
    }

    SemaEscapeInfo variableStorageInfo(Sema& sema, const SymbolVariable& symVar, AstNodeRef sourceRef, TypeRef typeRef)
    {
        if (symVar.isClosureCapture())
        {
            // By-ref captures are aliases of their source variable. If the capture has
            // no explicit escape info yet, continue from the original symbol so copies
            // of the closure report against the storage that actually dies.
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
        {
            info.kind = isByValueParameterStorage(sema, symVar) ? SemaEscapeKind::Local : SemaEscapeKind::Parameter;
            if (info.kind == SemaEscapeKind::Parameter)
                setParameterOrigin(sema, info, symVar);
        }
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
                setParameterOrigin(sema, info, *info.sourceVar);
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
    bool                  typeHasBorrowableStorage(Sema& sema, TypeRef typeRef);

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

    bool storageProjection(Sema& sema, AstNodeRef nodeRef, SemaEscapeProjection& outProjection)
    {
        if (nodeRef.isInvalid())
            return false;

        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isInvalid())
            return false;

        const AstNode& node = sema.node(resolvedRef);
        switch (node.id())
        {
            case AstNodeId::Identifier:
                outProjection.root = identifierVariable(sema, resolvedRef);
                return outProjection.root != nullptr;

            case AstNodeId::ParenExpr:
                return storageProjection(sema, node.cast<AstParenExpr>().nodeExprRef, outProjection);

            case AstNodeId::InitializerExpr:
                return storageProjection(sema, node.cast<AstInitializerExpr>().nodeExprRef, outProjection);

            case AstNodeId::AutoCastExpr:
                return storageProjection(sema, node.cast<AstAutoCastExpr>().nodeExprRef, outProjection);

            case AstNodeId::AsCastExpr:
                return storageProjection(sema, node.cast<AstAsCastExpr>().nodeExprRef, outProjection);

            case AstNodeId::MemberAccessExpr:
            {
                if (!storageProjection(sema, node.cast<AstMemberAccessExpr>().nodeLeftRef, outProjection))
                    return false;
                const SymbolVariable* field = identifierVariable(sema, resolvedRef);
                if (!field || field == outProjection.root)
                    return false;
                outProjection.components.push_back({.kind = SemaEscapeProjectionKind::Field, .field = field});
                return true;
            }

            case AstNodeId::IndexExpr:
            {
                const auto& index = node.cast<AstIndexExpr>();
                if (!storageProjection(sema, index.nodeExprRef, outProjection))
                    return false;

                const SemaNodeView indexView = sema.viewConstant(index.nodeArgRef);
                if (indexView.hasConstant() && indexView.cst()->isInt() && indexView.cst()->getInt().fits64() && !indexView.cst()->getInt().isNegative())
                    outProjection.components.push_back({.kind = SemaEscapeProjectionKind::ConstantIndex, .index = static_cast<uint64_t>(indexView.cst()->getInt().asI64())});
                else
                    outProjection.components.push_back({.kind = SemaEscapeProjectionKind::AnyIndex});
                return true;
            }

            default:
                return false;
        }
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
                const AstNodeRef leftRef     = node.cast<AstMemberAccessExpr>().nodeLeftRef;
                const TypeRef    leftTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, leftRef));
                if (isDirectBorrowCarrier(sema, leftTypeRef))
                {
                    // Accessing storage through a pointer that itself borrows a known local
                    // stays inside that local's storage: keep tracking on the borrowed root.
                    bool leftWholeVariable = false;
                    if (const SymbolVariable* leftVar = storageRootVariable(sema, leftRef, forAssignment, leftWholeVariable); leftVar && leftWholeVariable)
                    {
                        const SemaEscapeInfo* leftInfo = sema.variableEscapeInfo(*leftVar);
                        if (leftInfo && leftInfo->isLocalBorrow())
                        {
                            outWholeVariable = false;
                            return leftInfo->sourceVar;
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

                // A member access never designates the WHOLE variable, whatever the
                // recursion reports for the left side.
                bool                  leftWhole = false;
                const SymbolVariable* leftRoot  = storageRootVariable(sema, leftRef, forAssignment, leftWhole);
                outWholeVariable                = false;
                return leftRoot;
            }

            case AstNodeId::IndexExpr:
            {
                const auto& index = node.cast<AstIndexExpr>();
                if (isArrayStorageExpr(sema, index.nodeExprRef))
                {
                    bool                  indexedWhole = false;
                    const SymbolVariable* indexedRoot  = storageRootVariable(sema, index.nodeExprRef, forAssignment, indexedWhole);
                    outWholeVariable                   = false;
                    return indexedRoot;
                }

                return nullptr;
            }

            case AstNodeId::IndexListExpr:
            {
                const auto& index = node.cast<AstIndexListExpr>();
                if (isArrayStorageExpr(sema, index.nodeExprRef))
                {
                    bool                  indexedWhole = false;
                    const SymbolVariable* indexedRoot  = storageRootVariable(sema, index.nodeExprRef, forAssignment, indexedWhole);
                    outWholeVariable                   = false;
                    return indexedRoot;
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
                    if (const SymbolVariable* operandVar = storageRootVariable(sema, unary.nodeExprRef, forAssignment, operandWholeVariable); operandVar && operandWholeVariable)
                    {
                        const SemaEscapeInfo* operandInfo = sema.variableEscapeInfo(*operandVar);
                        if (operandInfo && operandInfo->isLocalBorrow())
                        {
                            outWholeVariable = false;
                            return operandInfo->sourceVar;
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

    SemaEscapeInfo storageBorrowInfo(Sema& sema, AstNodeRef sourceRef, TypeRef typeRef, bool allowDirectCarrier = false)
    {
        const TypeRef rawSourceTypeRef = unwrapAliasEnum(sema, expressionTypeRef(sema, sourceRef));
        if (!allowDirectCarrier && isDirectBorrowCarrier(sema, rawSourceTypeRef))
            return {};

        bool                  wholeVariable = false;
        const SymbolVariable* sourceVar     = storageRootVariable(sema, sourceRef, false, wholeVariable);
        if (sourceVar)
        {
            // A reference-typed VARIABLE designates the storage it was bound to: return
            // that binding's borrow. Decided on the declared type - a self-substituted
            // cast operand (implicit receiver conversion) reports the cast's result
            // type, not the variable's.
            const TypeRef varTypeRef = unwrapAliasEnum(sema, sourceVar->typeRef());
            if (wholeVariable && varTypeRef.isValid() && sema.typeMgr().get(varTypeRef).isReference())
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

    SemaEscapeInfo directTargetStorageBorrowInfo(Sema& sema, AstNodeRef sourceRef, TypeRef targetTypeRef)
    {
        if (!isDirectBorrowCarrier(sema, targetTypeRef) || sourceRef.isInvalid())
            return {};

        AstNodeRef candidateRef = sourceRef;
        TypeRef    candidateTypeRef;

        uint32_t unwrapGuard = 8;
        while (candidateRef.isValid() && unwrapGuard--)
        {
            const AstNode& candidateNode = sema.node(candidateRef);
            if (candidateNode.is(AstNodeId::InitializerExpr))
                candidateRef = candidateNode.cast<AstInitializerExpr>().nodeExprRef;
            else if (candidateNode.is(AstNodeId::AutoCastExpr))
                candidateRef = candidateNode.cast<AstAutoCastExpr>().nodeExprRef;
            else if (candidateNode.is(AstNodeId::AsCastExpr))
                candidateRef = candidateNode.cast<AstAsCastExpr>().nodeExprRef;
            else if (candidateNode.is(AstNodeId::ParenExpr))
                candidateRef = candidateNode.cast<AstParenExpr>().nodeExprRef;
            else
                break;
        }

        const AstNodeRef resolvedRef = sema.viewZero(candidateRef).nodeRef();
        if (resolvedRef.isValid() && sema.node(resolvedRef).is(AstNodeId::CastExpr))
        {
            const auto& cast = sema.node(resolvedRef).cast<AstCastExpr>();
            candidateRef     = cast.nodeExprRef;
            candidateTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), castOperandTypeRef(sema, resolvedRef, cast.nodeExprRef));
        }
        else
        {
            candidateTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, sourceRef));
        }

        const AstNodeRef candidateResolvedRef = sema.viewZero(candidateRef).nodeRef();
        if (candidateResolvedRef.isValid() && sema.node(candidateResolvedRef).is(AstNodeId::Identifier))
        {
            if (const SymbolVariable* candidateVar = identifierVariable(sema, candidateResolvedRef))
                candidateTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), candidateVar->typeRef());
        }

        if (!candidateTypeRef.isValid() || isDirectBorrowCarrier(sema, candidateTypeRef) || !typeHasBorrowableStorage(sema, candidateTypeRef))
            return {};

        return storageBorrowInfo(sema, candidateRef, targetTypeRef, true);
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
            const SymbolStruct& targetStruct   = targetType.payloadSymStruct();
            const auto&         fields         = targetStruct.fields();
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

        const auto& aggregate          = targetType.payloadAggregate();
        const auto  resolveMemberIndex = [&](IdentifierRef idRef, size_t& outIndex) {
            return targetType.tryGetAggregateMemberIndexByName(outIndex, sema.ctx(), idRef);
        };

        const bool found = resolveAggregateChildIndex(sema, children, childRef, aggregate.types.size(), resolveMemberIndex, fieldIndex);
        if (!found || fieldIndex >= aggregate.types.size())
            return TypeRef::invalid();

        return aggregate.types[fieldIndex];
    }

    bool structLikeChildProjectionComponent(Sema& sema, SemaEscapeProjectionComponent& outComponent, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef)
    {
        const TypeRef targetRef = normalizeBindingType(sema, targetTypeRef);
        if (!targetRef.isValid())
            return false;

        const TypeInfo& targetType = sema.typeMgr().get(targetRef);
        size_t          fieldIndex = 0;
        if (targetType.isStruct())
        {
            const SymbolStruct& targetStruct   = targetType.payloadSymStruct();
            const auto&         fields         = targetStruct.fields();
            const auto          findFieldIndex = [&](IdentifierRef idRef, size_t& outIndex) { return targetStruct.tryGetFieldIndexByName(outIndex, idRef); };
            if (!resolveAggregateChildIndex(sema, children, childRef, fields.size(), findFieldIndex, fieldIndex) || fieldIndex >= fields.size() || !fields[fieldIndex])
                return false;
            outComponent = {.kind = SemaEscapeProjectionKind::Field, .field = fields[fieldIndex]};
            return true;
        }

        if (!targetType.isAggregateStruct())
            return false;

        const auto& aggregate          = targetType.payloadAggregate();
        const auto  resolveMemberIndex = [&](IdentifierRef idRef, size_t& outIndex) { return targetType.tryGetAggregateMemberIndexByName(outIndex, sema.ctx(), idRef); };
        if (!resolveAggregateChildIndex(sema, children, childRef, aggregate.types.size(), resolveMemberIndex, fieldIndex))
            return false;
        outComponent = {.kind = SemaEscapeProjectionKind::ConstantIndex, .index = fieldIndex};
        return true;
    }

    bool aggregateLiteralChildren(Sema& sema, SmallVector<AstNodeRef>& outChildren, AstNodeRef exprRef)
    {
        if (exprRef.isInvalid())
            return false;

        const AstNode& rawNode = sema.node(exprRef);
        if (rawNode.is(AstNodeId::InitializerExpr))
            return aggregateLiteralChildren(sema, outChildren, rawNode.cast<AstInitializerExpr>().nodeExprRef);
        if (rawNode.is(AstNodeId::NamedArgument))
            return aggregateLiteralChildren(sema, outChildren, rawNode.cast<AstNamedArgument>().nodeArgRef);
        if (rawNode.is(AstNodeId::CastExpr))
            return aggregateLiteralChildren(sema, outChildren, rawNode.cast<AstCastExpr>().nodeExprRef);
        if (rawNode.is(AstNodeId::StructLiteral))
        {
            rawNode.cast<AstStructLiteral>().collectChildren(outChildren, sema.ast());
            return true;
        }
        if (rawNode.is(AstNodeId::StructInitializerList))
        {
            AstNode::collectChildren(outChildren, sema.ast(), rawNode.cast<AstStructInitializerList>().spanArgsRef);
            return true;
        }
        return false;
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
    // Owner structs (Core.String, ...) qualify too: their heap payload is freed when the
    // owner drops, and for a LOCAL owner the drop coincides with scope death - rooting a
    // view at the owner variable reports exactly the escapes that dangle. Parameter and
    // global owners yield Parameter/Static kinds and stay silent locally.
    bool typeHasBorrowableStorage(Sema& sema, TypeRef typeRef)
    {
        typeRef = unwrapAliasEnum(sema, typeRef);
        if (!typeRef.isValid())
            return false;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        return type.isArray() || type.isAggregate() || type.isStruct();
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
        const TypeRef  resultTypeRef    = expressionTypeRef(sema, castRef);
        const bool     operandSelfSubst = castOperandSelfSubstituted(sema, castRef, cast.nodeExprRef);
        SemaEscapeInfo info             = operandSelfSubst
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
                    // array->slice/string, value->any, struct->interface, ...): local bindings
                    // are safe, but the storage still dies with the frame. Only a user
                    // 'opCast' borrows the rvalue itself - its runtime storage holds the
                    // call RESULT, not the source, and the source dies at end of statement.
                    const auto* specOp   = sema.semaPayload<CastSpecOpPayload>(castRef);
                    const bool  isOpCast = specOp && specOp->kind == CastSpecialOpPayloadKind::OpCast && specOp->calledFn;

                    info.kind      = isOpCast ? SemaEscapeKind::Temporary : SemaEscapeKind::Materialized;
                    info.sourceRef = operandRef;
                    info.typeRef   = resultTypeRef;
                    // The runtime storage behaves like an anonymous local of the
                    // CURRENT scope: a shallower destination outlives it.
                    info.sourceScopeDepth = sema.currentScopeDepth();
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

    bool isIndirectCallResult(Sema& sema, AstNodeRef exprRef)
    {
        if (exprRef.isInvalid())
            return false;

        AstNodeRef resolvedRef = sema.viewZero(exprRef).nodeRef();
        uint32_t   unwrapGuard = 8;
        while (resolvedRef.isValid() && unwrapGuard--)
        {
            const AstNode& node = sema.node(resolvedRef);
            AstNodeRef     innerRef = AstNodeRef::invalid();
            if (node.is(AstNodeId::ParenExpr))
                innerRef = node.cast<AstParenExpr>().nodeExprRef;
            else if (node.is(AstNodeId::InitializerExpr))
                innerRef = node.cast<AstInitializerExpr>().nodeExprRef;
            else if (node.is(AstNodeId::AutoCastExpr))
                innerRef = node.cast<AstAutoCastExpr>().nodeExprRef;
            else if (node.is(AstNodeId::AsCastExpr))
                innerRef = node.cast<AstAsCastExpr>().nodeExprRef;
            else
                break;
            resolvedRef = sema.viewZero(innerRef).nodeRef();
        }

        if (resolvedRef.isInvalid() || !sema.node(resolvedRef).is(AstNodeId::CallExpr))
            return false;

        const auto& call = sema.node(resolvedRef).cast<AstCallExpr>();
        return identifierVariable(sema, call.nodeExprRef) != nullptr;
    }

    // The per-function summary recorded by checkReturn: when the callee's returned value
    // may borrow one of its parameters, the call result borrows the matching arguments.
    //
    // NOT CONSUMED INLINE: sema jobs run in a non-deterministic order, so an intra-module
    // callee may or may not be sema-completed when its call site is analyzed - and
    // waiting for a function body from another function body turns legal mutual
    // recursion into a stalled-dependency error (SemaCycle). Consuming the mask here
    // would make the errors flicker between otherwise identical builds. Instead, call
    // sites in escaping positions snapshot their argument borrows into deferred records
    // (recordDeferredCallBorrow below), judged once the module has no pending sema job.
    SemaEscapeInfo callResultEscapeInfo(const Sema& sema, AstNodeRef callRef, const AstCallExpr& call, const uint32_t& budget)
    {
        SWC_UNUSED(call);
        SWC_UNUSED(callRef);
        SWC_UNUSED(sema);
        SWC_UNUSED(budget);
        return {};
    }

    // How the analyzed site uses the opaque call: its result is returned by the
    // caller, its result is stored outside the local frame, or the call just happens
    // and only its arguments matter.
    enum class DeferredCallUse : uint8_t
    {
        Return,
        Store,
        Argument,
    };

    // Resolves a variable to the signature parameter it stands for: the variable
    // itself when flagged Parameter, or the receiver when it is the body 'me' binding
    // of a method (which carries no Parameter flag).
    const SymbolVariable* signatureParameterFor(Sema& sema, const SymbolVariable& symVar)
    {
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
            return &symVar;

        if (symVar.idRef() == sema.idMgr().predefined(IdentifierManager::PredefinedName::Me))
        {
            const SymbolFunction* currentFn = sema.currentFunction();
            if (currentFn && currentFn->hasExtraFlag(SymbolFunctionFlagsE::Method) && !currentFn->parameters().empty())
                return currentFn->parameters().front();
        }

        return nullptr;
    }

    // Maps a Parameter-kind borrow source to its index in the function's signature.
    bool findCallerParameterIndex(const SymbolFunction& fn, const SymbolVariable& sourceVar, size_t& outIndex)
    {
        const auto& params = fn.parameters();
        for (size_t i = 0; i < params.size(); ++i)
        {
            if (params[i] == &sourceVar)
            {
                outIndex = i;
                return true;
            }
        }

        return false;
    }

    uint64_t parameterOriginsMask(const SymbolFunction& fn, const SemaEscapeInfo& info)
    {
        if (info.parameterOriginsMask)
            return info.parameterOriginsMask;

        if (!info.sourceVar)
            return 0;

        size_t paramIndex = 0;
        if (!findCallerParameterIndex(fn, *info.sourceVar, paramIndex) || paramIndex >= 64)
            return 0;
        return 1ULL << paramIndex;
    }

    void addReturnBorrowOrigins(SymbolFunction& fn, const SemaEscapeInfo& info)
    {
        const uint64_t origins = parameterOriginsMask(fn, info);
        for (size_t i = 0; i < 64; ++i)
        {
            if (origins & (1ULL << i))
                fn.addReturnBorrowsParam(i);
        }
    }

    void addStoredBorrowOrigins(SymbolFunction& fn, const SemaEscapeInfo& info)
    {
        const uint64_t origins = parameterOriginsMask(fn, info);
        for (size_t i = 0; i < 64; ++i)
        {
            if (origins & (1ULL << i))
                fn.addStoresParam(i);
        }
    }

    void addFreedBorrowOrigins(SymbolFunction& fn, const SemaEscapeInfo& info)
    {
        const uint64_t origins = parameterOriginsMask(fn, info);
        for (size_t i = 0; i < 64; ++i)
        {
            if (origins & (1ULL << i))
                fn.addFreesParam(i);
        }
    }

    // Fills the diagnostic payload of a check template from the borrowed argument's
    // info (identity of the borrowed source; site and wording are stamped at commit).
    void fillDeferredCheckDiag(Sema& sema, SemaEscapeDeferredCheck& check, const SemaEscapeInfo& info)
    {
        check.typeRef = info.typeRef;

        if (info.isLocalBorrow())
        {
            check.diagId      = DiagnosticId::sanity_err_borrow_escape;
            check.symName     = info.sourceVar->name(sema.ctx());
            check.noteId      = DiagnosticId::sema_note_borrow_source_declared_here;
            check.noteSymName = check.symName;
            check.noteRange   = info.sourceVar->codeRange(sema.ctx());
            check.ownerSource = hasOwningLifecycle(sema, info.sourceVar->typeRef());
            return;
        }

        check.diagId = info.isTemporaryBorrow() ? DiagnosticId::sanity_err_borrow_temporary : DiagnosticId::sanity_err_borrow_materialized;
        if (info.sourceRef.isValid())
        {
            check.noteId    = DiagnosticId::sema_note_borrow_temporary_here;
            check.noteRange = sema.node(info.sourceRef).codeRange(sema.ctx());
        }
    }

    // Snapshots the borrows carried by the arguments of an opaque call into check
    // templates (escaping borrows) and proto-edges (caller-parameter arguments). The
    // flow state is only valid NOW, so the argument side is captured eagerly; the
    // callee's summaries are read later, when they are final regardless of the sema
    // job order. 'collectPairs' additionally crosses the arguments against the
    // callee's stores-into-parameter pairs ('g_container.add(&local)') - only wanted
    // from the once-per-call Argument hook. Returns false when nothing borrows or the
    // call is not summarizable.
    bool captureOpaqueCallBorrows(Sema& sema, AstNodeRef exprRef, bool collectPairs, SemaEscapeDeferredCallSnapshot& outCapture)
    {
        if (exprRef.isInvalid())
            return false;

        AstNodeRef resolvedRef = sema.viewZero(exprRef).nodeRef();
        uint32_t   unwrapGuard = 8;
        while (resolvedRef.isValid() && unwrapGuard--)
        {
            const AstNode& node = sema.node(resolvedRef);
            if (node.is(AstNodeId::ParenExpr))
                resolvedRef = sema.viewZero(node.cast<AstParenExpr>().nodeExprRef).nodeRef();
            else if (node.is(AstNodeId::InitializerExpr))
                resolvedRef = sema.viewZero(node.cast<AstInitializerExpr>().nodeExprRef).nodeRef();
            else if (node.is(AstNodeId::NamedArgument))
                resolvedRef = sema.viewZero(node.cast<AstNamedArgument>().nodeArgRef).nodeRef();
            else
                break;
        }

        if (resolvedRef.isInvalid() || !sema.node(resolvedRef).is(AstNodeId::CallExpr))
            return false;

        const auto&           call = sema.node(resolvedRef).cast<AstCallExpr>();
        const SymbolFunction* fn   = resolvedCallFunction(sema, resolvedRef, call.nodeExprRef);
        if (!fn)
            return false;

        // Inline expansions are analyzed within the caller with exact information: the
        // summary path only covers opaque calls.
        if (fn->attributes().hasRtFlag(RtAttributeFlagsE::Inline) ||
            fn->attributes().hasRtFlag(RtAttributeFlagsE::Macro) ||
            fn->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
            return false;

        const auto& params = fn->parameters();
        if (params.empty())
            return false;

        // The LANGUAGE allocator interface: 'free'/'realloc' invalidate the pointer
        // carried by the request's 'address' field. Cheap name test first, the
        // qualified name only on candidates.
        bool calleeIsAllocFree = false;
        {
            const auto calleeName = fn->name(sema.ctx());
            if (calleeName == "free" || calleeName == "realloc")
            {
                // The qualified name is prefixed by the module: match the language
                // interface by suffix. Interface IMPLEMENTATIONS ('X.IAllocator.free')
                // do not match - only the declared interface method reached by
                // dispatch does, which is exactly the semantic anchor.
                const Utf8             fullName = fn->getFullScopedName(sema.ctx());
                const std::string_view view{fullName};
                calleeIsAllocFree = view.ends_with("Swag.IAllocator.free") || view.ends_with("Swag.IAllocator.realloc");
            }
        }

        SmallVector<ResolvedCallArgument> args;
        sema.appendResolvedCallArguments(resolvedRef, args);

        SmallVector<std::pair<uint32_t, SemaEscapeInfo>> argBorrows;
        SmallVector<std::pair<uint32_t, uint32_t>>        parameterMappings;

        size_t paramIndex = 0;
        for (const ResolvedCallArgument& arg : args)
        {
            // Interface dispatch prepends the runtime receiver object, which does not
            // consume a declared parameter slot.
            if (arg.passKind == CallArgumentPassKind::InterfaceObject)
                continue;
            if (paramIndex >= params.size())
                break;

            const size_t          thisParam = paramIndex++;
            const SymbolVariable* param     = params[thisParam];
            if (arg.argRef.isInvalid() || !param || thisParam >= 64)
                continue;

            // A variadic tail bundles its values into a temporary slice: the pairing
            // with a single summary bit stops there.
            const TypeRef paramTypeRef = unwrapAliasEnum(sema, param->typeRef());
            if (paramTypeRef.isValid() && sema.typeMgr().get(paramTypeRef).isAnyVariadic())
                break;

            // A parameter that cannot carry a borrow can neither return nor store one.
            if (paramTypeRef.isValid() && !typeCanCarryBorrowImpl(sema, paramTypeRef))
                continue;

            uint32_t             budget = K_EXPR_BUDGET;
            const SemaEscapeInfo info   = borrowInfoFromCallArgument(sema, arg, param->typeRef(), budget);
            if (collectPairs && info.hasBorrow())
                argBorrows.push_back({static_cast<uint32_t>(thisParam), info});

            // Allocator-interface free: what the call invalidates is the borrow the
            // REQUEST variable carries (tracked when 'req.address = x' was analyzed).
            // A caller parameter seeds this function's FREES summary; a frame-local
            // borrow (non-owner: an owner's payload lives on the heap and freeing it
            // is legitimate) is a certain fault.
            // Interface dispatch pairs the request as the sole non-receiver argument
            // (the runtime receiver object does not consume a slot).
            if (calleeIsAllocFree && collectPairs)
            {
                const AstNodeRef      reqValueRef = argumentValueRef(sema, arg.argRef);
                bool                  reqWhole    = false;
                const SymbolVariable* reqVar      = reqValueRef.isValid() ? storageRootVariable(sema, reqValueRef, false, reqWhole) : nullptr;
                const SemaEscapeInfo carried = reqVar ? sema.variableEscapeInfoIncludingProjections(*reqVar) : SemaEscapeInfo{};
                if (carried.kind == SemaEscapeKind::Parameter)
                {
                    SymbolFunction* callerFn = sema.currentFunction();
                    if (callerFn)
                        addFreedBorrowOrigins(*callerFn, carried);
                }
                else if (carried.isLocalBorrow() && !hasOwningLifecycle(sema, carried.sourceVar->typeRef()))
                {
                    SemaEscapeDeferredCheck check;
                    check.callee      = fn;
                    check.paramIndex  = static_cast<uint32_t>(thisParam);
                    check.judgeAlways = true;
                    fillDeferredCheckDiag(sema, check, carried);
                    check.diagId = DiagnosticId::sanity_err_free_borrowed;
                    outCapture.checks.push_back(std::move(check));
                }
            }

            // Handing the callee one of the caller's own parameters chains the
            // summaries: judged by fixpoint, not here - the callee's masks are not
            // final yet. The edge kind is chosen by the committer.
            if (info.kind == SemaEscapeKind::Parameter)
            {
                SymbolFunction* callerFn = sema.currentFunction();
                if (!callerFn)
                    continue;

                const uint64_t origins = parameterOriginsMask(*callerFn, info);
                for (size_t callerParamIndex = 0; callerParamIndex < 64; ++callerParamIndex)
                {
                    if (!(origins & (1ULL << callerParamIndex)))
                        continue;

                    SemaEscapeSummaryEdge edge;
                    edge.caller           = callerFn;
                    edge.callee           = fn;
                    edge.callerParamIndex = static_cast<uint32_t>(callerParamIndex);
                    edge.calleeParamIndex = static_cast<uint32_t>(thisParam);
                    outCapture.edges.push_back(edge);
                    parameterMappings.push_back({static_cast<uint32_t>(callerParamIndex), static_cast<uint32_t>(thisParam)});
                }
                continue;
            }

            // A local bound to another opaque call handed onward ('let p = f(&v);
            // g(p)'): compose the two summaries. Each borrow captured at 'f' becomes a
            // GUARDED template - it escapes only if 'f' returns it (the guard) AND
            // this callee keeps or returns its argument (the main judge). Templates
            // every wrapper contributes one guard, so chains have no fixed depth limit.
            if (info.isDeferredCallBorrow())
            {
                for (const auto& snapshot : info.deferredCalls)
                {
                    if (!snapshot)
                        continue;
                    for (const SemaEscapeDeferredCheck& inner : snapshot->checks)
                    {
                        SemaEscapeDeferredCheck check = inner;
                        check.guards.push_back({inner.callee, inner.paramIndex});
                        check.callee                  = fn;
                        check.paramIndex              = static_cast<uint32_t>(thisParam);
                        outCapture.checks.push_back(std::move(check));
                    }
                }

                continue;
            }

            if (!info.isLocalBorrow() && !info.isTemporaryBorrow() && !info.isMaterializedBorrow())
                continue;

            // Site, wording and judged summary are stamped when the borrow provably
            // escapes (commitDeferredCallBorrows).
            SemaEscapeDeferredCheck check;
            check.callee     = fn;
            check.paramIndex = static_cast<uint32_t>(thisParam);
            fillDeferredCheckDiag(sema, check, info);
            outCapture.checks.push_back(std::move(check));
        }

        // Cross-argument pairs: 'g_container.add(&local)' escapes when the callee
        // stores the borrowed argument into storage reachable from the container
        // argument. Only a GLOBAL destination argument provably outlives the borrow;
        // caller-parameter destinations would need pair transitivity (future).
        if (collectPairs)
        {
            for (const auto& [callerInto, calleeInto] : parameterMappings)
            {
                for (const auto& [callerStored, calleeStored] : parameterMappings)
                {
                    if (callerInto == callerStored || calleeInto == calleeStored)
                        continue;

                    SemaEscapeSummaryEdge edge;
                    edge.caller               = sema.currentFunction();
                    edge.callee               = fn;
                    edge.callerParamIndex     = callerStored;
                    edge.calleeParamIndex     = calleeStored;
                    edge.callerIntoParamIndex = callerInto;
                    edge.calleeIntoParamIndex = calleeInto;
                    edge.kind                 = SemaEscapeSummaryEdgeKind::PairToPair;
                    outCapture.edges.push_back(edge);
                }
            }

            for (const auto& [intoParam, intoInfo] : argBorrows)
            {
                if (intoInfo.kind != SemaEscapeKind::Static || intoParam >= 8)
                    continue;

                for (const auto& [storedParam, storedInfo] : argBorrows)
                {
                    if (storedParam == intoParam || storedParam >= 8)
                        continue;
                    if (!storedInfo.isLocalBorrow() && !storedInfo.isTemporaryBorrow() && !storedInfo.isMaterializedBorrow())
                        continue;

                    SemaEscapeDeferredCheck check;
                    check.callee         = fn;
                    check.paramIndex     = storedParam;
                    check.judgePairs     = true;
                    check.intoParamIndex = intoParam;
                    fillDeferredCheckDiag(sema, check, storedInfo);
                    outCapture.checks.push_back(std::move(check));
                }
            }
        }

        return !outCapture.checks.empty() || !outCapture.edges.empty();
    }

    // Stamps the escape site on a capture and hands it to the compiler for the final
    // judgement. 'judgeStores' selects which callee summary the checks are judged
    // against; 'edgeKind' selects how caller-parameter arguments propagate (empty =
    // dropped: the destination does not provably outlive the frame).
    void commitDeferredCallBorrows(Sema& sema, const SemaEscapeDeferredCallSnapshot& capture, AstNodeRef atNodeRef, std::string_view what, bool judgeStores, std::optional<SemaEscapeSummaryEdgeKind> edgeKind)
    {
        if (atNodeRef.isInvalid())
            return;

        const FileRef         fileRef   = sema.srcView(sema.node(atNodeRef).srcViewRef()).fileRef();
        const SourceCodeRange siteRange = sema.node(atNodeRef).codeRange(sema.ctx());

        for (const SemaEscapeDeferredCheck& checkTemplate : capture.checks)
        {
            SemaEscapeDeferredCheck check = checkTemplate;
            check.judgeStores             = judgeStores;
            check.what                    = what;
            check.fileRef                 = fileRef;
            check.siteRange               = siteRange;
            sema.ctx().compiler().addDeferredEscapeCheck(std::move(check));
        }

        if (!edgeKind.has_value())
            return;

        for (const SemaEscapeSummaryEdge& protoEdge : capture.edges)
        {
            SemaEscapeSummaryEdge edge = protoEdge;
            if (edge.kind != SemaEscapeSummaryEdgeKind::PairToPair)
                edge.kind = edgeKind.value();
            sema.ctx().compiler().addEscapeSummaryEdge(edge);
        }
    }

    void recordDeferredCallBorrow(Sema& sema, AstNodeRef exprRef, AstNodeRef atNodeRef, std::string_view what, DeferredCallUse use, bool durableDest)
    {
        SemaEscapeDeferredCallSnapshot capture;
        if (!captureOpaqueCallBorrows(sema, exprRef, use == DeferredCallUse::Argument, capture))
            return;

        switch (use)
        {
            case DeferredCallUse::Return:
                commitDeferredCallBorrows(sema, capture, atNodeRef, what, false, SemaEscapeSummaryEdgeKind::ReturnToReturn);
                break;

            case DeferredCallUse::Store:
            {
                std::optional<SemaEscapeSummaryEdgeKind> edgeKind;
                if (durableDest)
                    edgeKind = SemaEscapeSummaryEdgeKind::ReturnToStores;
                commitDeferredCallBorrows(sema, capture, atNodeRef, what, false, edgeKind);
                break;
            }

            case DeferredCallUse::Argument:
                commitDeferredCallBorrows(sema, capture, atNodeRef, what, true, SemaEscapeSummaryEdgeKind::StoresToStores);
                break;
        }
    }

    // Binding an opaque call result to a local: capture the argument borrows now (the
    // flow state dies with the statement) and judge them only if the local later
    // escapes (return, durable store).
    void bindDeferredCallBorrow(Sema& sema, const SymbolVariable& symVar, AstNodeRef exprRef, const SemaEscapeProjection* projection = nullptr)
    {
        SemaEscapeDeferredCallSnapshot capture;
        if (!captureOpaqueCallBorrows(sema, exprRef, false, capture))
        {
            if (projection)
                sema.clearProjectionEscapeInfo(*projection);
            else
                sema.clearVariableEscapeInfo(symVar);
            return;
        }

        SemaEscapeInfo info;
        info.kind      = SemaEscapeKind::DeferredCall;
        info.sourceRef = exprRef;
        info.deferredCalls.push_back(std::make_shared<const SemaEscapeDeferredCallSnapshot>(std::move(capture)));
        if (projection)
            sema.setProjectionEscapeInfo(*projection, info);
        else
            sema.setVariableEscapeInfo(symVar, info);
    }

    // A DeferredCall borrow provably escaping: judge its captured checks and edges at
    // the escape site.
    void emitDeferredCallEscape(Sema& sema, const SemaEscapeInfo& info, AstNodeRef atNodeRef, std::string_view what, std::optional<SemaEscapeSummaryEdgeKind> edgeKind)
    {
        for (const auto& snapshot : info.deferredCalls)
        {
            if (snapshot)
                commitDeferredCallBorrows(sema, *snapshot, atNodeRef, what, false, edgeKind);
        }
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
                SemaEscapeInfo trackedInfo = sema.variableEscapeInfoIncludingProjections(*symVar);
                if (trackedInfo.hasBorrow())
                    return trackedInfo;

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
                        setParameterOrigin(sema, info, *symVar);
                        return info;
                    }
                }

                // A method body binds 'me' to a body-local symbol distinct from the
                // signature receiver: root it at the receiver parameter so 'g(me)'
                // feeds the summaries like any parameter argument.
                if (symVar->idRef() == sema.idMgr().predefined(IdentifierManager::PredefinedName::Me))
                {
                    const SymbolFunction* currentFn = sema.currentFunction();
                    if (currentFn &&
                        currentFn->hasExtraFlag(SymbolFunctionFlagsE::Method) &&
                        !currentFn->parameters().empty())
                    {
                        SemaEscapeInfo info;
                        info.kind      = SemaEscapeKind::Parameter;
                        info.sourceVar = currentFn->parameters().front();
                        info.sourceRef = resolvedRef;
                        info.typeRef   = symVar->typeRef();
                        setParameterOrigin(sema, info, *info.sourceVar);
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
                SemaEscapeProjection projection;
                if (storageProjection(sema, resolvedRef, projection))
                {
                    SemaEscapeInfo projectedInfo = sema.projectionEscapeInfoIncludingWildcards(projection);
                    if (projectedInfo.hasBorrow())
                        return projectedInfo;
                }

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
            {
                SemaEscapeProjection projection;
                if (storageProjection(sema, resolvedRef, projection))
                {
                    SemaEscapeInfo projectedInfo = sema.projectionEscapeInfoIncludingWildcards(projection);
                    if (projectedInfo.hasBorrow())
                        return projectedInfo;
                }
                return indexEscapeInfo(sema, resolvedRef, node.cast<AstIndexExpr>().nodeExprRef, budget);
            }

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
                    const TypeRef operandTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), castOperandTypeRef(sema, resolvedRef, castNode.nodeExprRef));
                    if (isDirectBorrowCarrier(sema, targetTypeRef) &&
                        operandTypeRef.isValid() &&
                        !isDirectBorrowCarrier(sema, operandTypeRef) &&
                        typeHasBorrowableStorage(sema, operandTypeRef))
                        return storageBorrowInfo(sema, castNode.nodeExprRef, targetTypeRef, true);

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
        const TypeRef      typeRef  = leftView.typeRef();
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        return type.isReference() ? type.payloadTypeRef() : typeRef;
    }

    // The borrow checks are STATIC sanity checks under the Lifecycle flag: when the
    // sanity is disabled, the whole analysis is skipped (no tracking, no reports).
    bool lifecycleSanityEnabled(Sema& sema)
    {
        return sema.frame().currentAttributes().hasSanity(sema.buildCfg().sanityGuards, Runtime::SafetyWhat::Lifecycle);
    }

    Result reportBorrowEscape(Sema& sema, AstNodeRef atNodeRef, const SemaEscapeInfo& info, std::string_view what)
    {
        if (info.isTemporaryBorrow() || info.isMaterializedBorrow())
        {
            const DiagnosticId diagId = info.isTemporaryBorrow() ? DiagnosticId::sanity_err_borrow_temporary : DiagnosticId::sanity_err_borrow_materialized;

            auto diag = SemaError::report(sema, diagId, atNodeRef);
            diag.addArgument(Diagnostic::ARG_WHAT, what);
            if (info.typeRef.isValid())
                diag.addArgument(Diagnostic::ARG_TYPE, info.typeRef);

            if (info.sourceRef.isValid())
            {
                diag.addNote(DiagnosticId::sema_note_borrow_temporary_here);
                diag.last().addSpan(sema.node(info.sourceRef).codeRange(sema.ctx()));
            }

            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!info.isLocalBorrow())
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sanity_err_borrow_escape, atNodeRef);
        diag.addArgument(Diagnostic::ARG_SYM, info.sourceVar->name(sema.ctx()));
        diag.addArgument(Diagnostic::ARG_WHAT, what);
        if (info.typeRef.isValid())
            diag.addArgument(Diagnostic::ARG_TYPE, info.typeRef);

        diag.addNote(DiagnosticId::sema_note_borrow_source_declared_here);
        diag.last().addArgument(Diagnostic::ARG_SYM, info.sourceVar->name(sema.ctx()));
        diag.last().addSpan(info.sourceVar->codeRange(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result reportBorrowScopeEscape(Sema& sema, AstNodeRef atNodeRef, const SemaEscapeInfo& info, const SymbolVariable& dstVar)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sanity_err_borrow_scope_escape, atNodeRef);
        diag.addArgument(Diagnostic::ARG_SYM, info.sourceVar->name(sema.ctx()));
        diag.addArgument(Diagnostic::ARG_VALUE, dstVar.name(sema.ctx()));

        diag.addNote(DiagnosticId::sema_note_borrow_source_declared_here);
        diag.last().addArgument(Diagnostic::ARG_SYM, info.sourceVar->name(sema.ctx()));
        diag.last().addSpan(info.sourceVar->codeRange(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result storeOrReportDestinationInfo(Sema& sema, const SymbolVariable& dstVar, AstNodeRef atNodeRef, const SemaEscapeInfo& info, std::string_view what, const SemaEscapeProjection* projection = nullptr)
    {
        // A borrow of a temporary outlives it as soon as it is bound anywhere.
        if (info.isTemporaryBorrow())
            return reportBorrowEscape(sema, atNodeRef, info, what);

        if (info.sourceVar == &dstVar)
        {
            if (projection && !projection->components.empty())
                sema.clearProjectionEscapeInfo(*projection);
            else
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

            // Materialized cast storage behaves like an anonymous local of the scope it
            // was created in: a shallower destination outlives it. Inline expansions
            // materialize into the enclosing statement and open their own scopes, so
            // their depths do not compare.
            if (info.isMaterializedBorrow() && info.sourceScopeDepth && !SemaHelpers::effectiveInlinePayload(sema))
            {
                const uint32_t dstDepth = sema.variableScopeDepth(dstVar);
                if (dstDepth && info.sourceScopeDepth > dstDepth)
                    return reportBorrowEscape(sema, atNodeRef, info, what);
            }

            if (projection && !projection->components.empty())
                sema.setProjectionEscapeInfo(*projection, info);
            else
                sema.setVariableEscapeInfo(dstVar, info);
            return Result::Continue;
        }

        // A deferred opaque-call borrow reaching storage that outlives the frame:
        // stamp this site and judge against the callee's (final) summaries. Summary
        // edges only propagate for destinations that provably hand the borrow onward:
        // globals (the caller stores it) and retval storage (the caller returns it).
        if (info.isDeferredCallBorrow())
        {
            std::optional<SemaEscapeSummaryEdgeKind> edgeKind;
            if (dstVar.hasExtraFlag(SymbolVariableFlagsE::GlobalStorage))
                edgeKind = SemaEscapeSummaryEdgeKind::ReturnToStores;
            else if (dstVar.hasExtraFlag(SymbolVariableFlagsE::RetVal))
                edgeKind = SemaEscapeSummaryEdgeKind::ReturnToReturn;
            emitDeferredCallEscape(sema, info, atNodeRef, what, edgeKind);
            return Result::Continue;
        }

        if (info.isLocalBorrow() || info.isMaterializedBorrow())
            return reportBorrowEscape(sema, atNodeRef, info, what);

        return Result::Continue;
    }

    Result bindAggregateLiteralProjectionChildren(Sema& sema, const SymbolVariable& dstVar, const SemaEscapeProjection& baseProjection, AstNodeRef exprRef, TypeRef targetTypeRef, std::string_view what)
    {
        SmallVector<AstNodeRef> children;
        if (!aggregateLiteralChildren(sema, children, exprRef))
            return Result::Continue;

        for (const AstNodeRef childRef : children)
        {
            SemaEscapeProjectionComponent component;
            if (!structLikeChildProjectionComponent(sema, component, children.span(), childRef, targetTypeRef))
                continue;

            const TypeRef childTypeRef = structLikeChildTargetType(sema, children.span(), childRef, targetTypeRef);
            if (!childTypeRef.isValid())
                continue;

            SemaEscapeProjection projection = baseProjection;
            projection.components.push_back(component);

            const AstNodeRef childValueRef = argumentValueRef(sema, childRef);
            SmallVector<AstNodeRef> nestedChildren;
            if (aggregateLiteralChildren(sema, nestedChildren, childValueRef))
            {
                SWC_RESULT(bindAggregateLiteralProjectionChildren(sema, dstVar, projection, childValueRef, childTypeRef, what));
                continue;
            }

            uint32_t             budget = K_EXPR_BUDGET;
            const SemaEscapeInfo info   = expressionEscapeInfoWithTarget(sema, childValueRef, childTypeRef, budget);
            if (info.hasBorrow())
                SWC_RESULT(storeOrReportDestinationInfo(sema, dstVar, childRef, info, what, &projection));
            else if (typeCanCarryBorrowImpl(sema, childTypeRef))
                bindDeferredCallBorrow(sema, dstVar, childValueRef, &projection);
        }

        return Result::Continue;
    }

    Result bindAggregateLiteralProjections(Sema& sema, bool& outHandled, const SymbolVariable& dstVar, AstNodeRef exprRef, TypeRef targetTypeRef, std::string_view what)
    {
        SmallVector<AstNodeRef> children;
        if (!aggregateLiteralChildren(sema, children, exprRef))
            return Result::Continue;

        outHandled = true;
        sema.clearVariableEscapeInfo(dstVar);
        SemaEscapeProjection rootProjection;
        rootProjection.root = &dstVar;
        return bindAggregateLiteralProjectionChildren(sema, dstVar, rootProjection, exprRef, targetTypeRef, what);
    }

    bool variableInitializerCanEscape(const SymbolVariable& symVar)
    {
        return symVar.hasExtraFlag(SymbolVariableFlagsE::GlobalStorage) ||
               symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal);
    }

    // The storage variable an expression ultimately designates. Resolves the syntactic
    // root first (identifier, member/index access, cast operand, borrowing dereference);
    // when the root is produced by an implicit carrier conversion (an array decaying to a
    // slice for iteration), falls back to the borrow analysis, which sees through the
    // opCast to the backing variable. Used to match a loop's iterated storage against a
    // mutating call's receiver, so both sides must resolve the same way.
    const SymbolVariable* rootStorageOf(Sema& sema, AstNodeRef exprRef)
    {
        bool whole = false;
        if (const SymbolVariable* var = storageRootVariable(sema, exprRef, false, whole))
        {
            // A whole pointer/reference variable that itself borrows a tracked local
            // designates that local's storage: follow it so a mutation through an alias
            // ('let p = &v; p.add()') roots at the same variable the loop iterates.
            if (whole)
            {
                if (const SemaEscapeInfo* varInfo = sema.variableEscapeInfo(*var); varInfo && varInfo->isLocalBorrow() && varInfo->sourceVar)
                    return varInfo->sourceVar;
            }
            return var;
        }

        uint32_t       budget = K_EXPR_BUDGET;
        SemaEscapeInfo info   = expressionEscapeInfoRec(sema, exprRef, budget);
        if (!info.hasBorrow() && expressionMayExposeStorageBorrow(sema, exprRef))
            info = storageBorrowInfo(sema, exprRef, TypeRef::invalid());
        return info.hasBorrow() ? info.sourceVar : nullptr;
    }

    // The storage designation (root + field/index path) of an expression. Mirrors
    // 'storageRootVariableAt' but records the path, and - unlike the shared
    // 'storageProjection' - it sees through the implicit cast that a mutable-receiver
    // method inserts ('holder.other.add' wraps 'holder.other' in a receiver cast), so the
    // field path survives. 'ok' is false when no whole-storage path applies.
    void iterationProjectionAt(Sema& sema, AstNodeRef resolvedRef, SemaEscapeProjection& out, bool& ok);

    void iterationProjection(Sema& sema, AstNodeRef nodeRef, SemaEscapeProjection& out, bool& ok)
    {
        ok = false;
        if (nodeRef.isInvalid())
            return;
        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isInvalid())
            return;
        iterationProjectionAt(sema, resolvedRef, out, ok);
    }

    void iterationProjectionAt(Sema& sema, AstNodeRef resolvedRef, SemaEscapeProjection& out, bool& ok)
    {
        const AstNode& node = sema.node(resolvedRef);
        switch (node.id())
        {
            case AstNodeId::Identifier:
                out.root = identifierVariable(sema, resolvedRef);
                ok       = out.root != nullptr;
                return;

            case AstNodeId::ParenExpr:
                iterationProjection(sema, node.cast<AstParenExpr>().nodeExprRef, out, ok);
                return;
            case AstNodeId::InitializerExpr:
                iterationProjection(sema, node.cast<AstInitializerExpr>().nodeExprRef, out, ok);
                return;
            case AstNodeId::AutoCastExpr:
                iterationProjection(sema, node.cast<AstAutoCastExpr>().nodeExprRef, out, ok);
                return;
            case AstNodeId::AsCastExpr:
                iterationProjection(sema, node.cast<AstAsCastExpr>().nodeExprRef, out, ok);
                return;

            case AstNodeId::CastExpr:
            {
                const AstNodeRef operandRef = node.cast<AstCastExpr>().nodeExprRef;
                if (castOperandSelfSubstituted(sema, resolvedRef, operandRef))
                    iterationProjectionAt(sema, operandRef, out, ok);
                else
                    iterationProjection(sema, operandRef, out, ok);
                return;
            }

            case AstNodeId::MemberAccessExpr:
            {
                iterationProjection(sema, node.cast<AstMemberAccessExpr>().nodeLeftRef, out, ok);
                if (!ok)
                    return;
                const SymbolVariable* field = identifierVariable(sema, resolvedRef);
                if (!field || field == out.root)
                {
                    ok = false;
                    return;
                }
                out.components.push_back({.kind = SemaEscapeProjectionKind::Field, .field = field});
                return;
            }

            case AstNodeId::IndexExpr:
            {
                const auto& index = node.cast<AstIndexExpr>();
                iterationProjection(sema, index.nodeExprRef, out, ok);
                if (!ok)
                    return;
                const SemaNodeView indexView = sema.viewConstant(index.nodeArgRef);
                if (indexView.hasConstant() && indexView.cst()->isInt() && indexView.cst()->getInt().fits64() && !indexView.cst()->getInt().isNegative())
                    out.components.push_back({.kind = SemaEscapeProjectionKind::ConstantIndex, .index = static_cast<uint64_t>(indexView.cst()->getInt().asI64())});
                else
                    out.components.push_back({.kind = SemaEscapeProjectionKind::AnyIndex});
                return;
            }

            default:
                ok = false;
                return;
        }
    }

    // The storage an expression designates as a root plus a field/index path, following a
    // whole-variable alias at the base ('let p = &v' resolves 'p.x' to 'v.x'). When no
    // syntactic path applies (an array decaying to a slice for iteration), keeps just the
    // storage root with an empty, EXACT-cleared path; 'outExact' says whether the field
    // path is reliable, so an ambiguous empty path is not mistaken for "the whole owner".
    void resolveIterationProjection(Sema& sema, AstNodeRef exprRef, SemaEscapeProjection& out, bool& outExact)
    {
        out.root = nullptr;
        out.components.clear();
        outExact = false;

        iterationProjection(sema, exprRef, out, outExact);
        if (!outExact || !out.root)
        {
            out.components.clear();
            out.root = rootStorageOf(sema, exprRef);
            outExact = false;
            return;
        }

        if (const SemaEscapeInfo* varInfo = sema.variableEscapeInfo(*out.root); varInfo && varInfo->isLocalBorrow() && varInfo->sourceVar)
            out.root = varInfo->sourceVar;
    }

    // True when the mutation 'receiver' targets the iterated 'source' storage itself or
    // something nested inside it: the source path must be a prefix of the receiver path
    // (equal, or the receiver reaches deeper). A broader mutation of a shared owner - the
    // receiver being an ancestor of the source, e.g. a method on the whole struct while
    // one of its fields is iterated - is NOT flagged: such a method usually manages
    // unrelated state, and flagging it would drown the genuine same-collection bugs in
    // false alarms on ordinary code.
    bool iterationMutationHitsSource(const SemaEscapeProjection& source, bool sourceExact, const SemaEscapeProjection& receiver, bool receiverExact)
    {
        if (!source.root || source.root != receiver.root)
            return false;

        // Iterating the whole variable: any mutation that roots at it hits the snapshot,
        // whatever the receiver's exact path (the classic 'for x in arr { arr.add() }').
        if (source.components.empty())
            return true;

        // Iterating a SPECIFIC field: the mutation must provably reach that field or
        // something nested in it. Without a reliable field path on both sides we cannot
        // prove that - and must not guess, or an unrelated call whose receiver merely
        // roots at the same owner ('for v in me.list { me.getApp().setIcon(...) }') would
        // be falsely flagged. Stay silent when either path is unknown.
        if (!sourceExact || !receiverExact)
            return false;

        if (source.components.size() > receiver.components.size())
            return false;

        for (size_t i = 0; i < source.components.size(); ++i)
        {
            const SemaEscapeProjectionComponent& cs = source.components[i];
            const SemaEscapeProjectionComponent& cr = receiver.components[i];
            if (cs.kind == SemaEscapeProjectionKind::AnyIndex || cr.kind == SemaEscapeProjectionKind::AnyIndex)
                continue;
            if (cs != cr)
                return false;
        }
        return true;
    }

    // The syntactic receiver of a method call ('holder.items.add(x)' -> 'holder.items'):
    // the callee is a member access whose left is the receiver. Used for projection
    // matching, since the resolved receiver argument may be a materialized address whose
    // field path is lost. Invalid for a non-method (UFCS/free function) call shape.
    AstNodeRef syntacticMethodReceiverRef(Sema& sema, AstNodeRef callRef)
    {
        // Read the raw AST: resolution attaches symbols/types but keeps the node ids, so
        // the call's callee stays the parsed 'holder.items.add' member access. Following
        // 'viewZero' here would substitute it and lose the receiver's field path.
        const AstNode& callNode = sema.node(callRef);
        if (!callNode.is(AstNodeId::CallExpr))
            return AstNodeRef::invalid();

        const AstNodeRef calleeRef = callNode.cast<AstCallExpr>().nodeExprRef;
        if (calleeRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& calleeNode = sema.node(calleeRef);
        if (calleeNode.is(AstNodeId::MemberAccessExpr))
            return calleeNode.cast<AstMemberAccessExpr>().nodeLeftRef;
        return AstNodeRef::invalid();
    }

    // The common safe pattern: the mutation is followed by an unconditional loop exit, so
    // the loop never reads the collection again after mutating it
    // ('for it in c { if hit { c.removeAt(i); return it } }'). Approximated by a loop-exit
    // statement (return/break/unreachable) placed after the mutation within the loop body.
    // Uses source order rather than AST structure so it survives the opVisit macro
    // expansion, which reparents the body but keeps the user code's source ranges.
    //
    // Walked with an explicit worklist, not recursion: an expanded/substituted body can be
    // deep or self-referential, and a recursive descent would overflow the stack. The
    // budget bounds total work so a substitution cycle terminates instead of spinning.
    bool mutationFollowedByLoopExit(Sema& sema, AstNodeRef bodyRef, AstNodeRef callRef)
    {
        if (bodyRef.isInvalid() || callRef.isInvalid())
            return false;

        const SourceCodeRange callRange = sema.node(callRef).codeRange(sema.ctx());
        if (!callRange.srcView)
            return false;

        SmallVector<AstNodeRef> worklist;
        worklist.push_back(bodyRef);

        uint32_t                budget = 8192;
        SmallVector<AstNodeRef> children;
        while (!worklist.empty() && budget != 0)
        {
            budget--;
            const AstNodeRef nodeRef = worklist.back();
            worklist.pop_back();
            if (nodeRef.isInvalid())
                continue;

            const AstNode& node = sema.node(nodeRef);
            if (node.is(AstNodeId::ReturnStmt) || node.is(AstNodeId::BreakStmt) || node.is(AstNodeId::UnreachableStmt))
            {
                const SourceCodeRange range = node.codeRange(sema.ctx());
                if (range.srcView == callRange.srcView && range.offset > callRange.offset)
                    return true;
            }

            children.clear();
            node.collectChildrenFromAst(children, sema.ast());
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isValid())
                    worklist.push_back(childRef);
            }
        }
        return false;
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
        if (!lifecycleSanityEnabled(sema))
            return Result::Continue;

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

        bool aggregateHandled = false;
        SWC_RESULT(bindAggregateLiteralProjections(sema, aggregateHandled, symVar, initRef, targetTypeRef, "an initializer"));
        if (aggregateHandled)
            return Result::Continue;

        uint32_t             budget = K_EXPR_BUDGET;
        const SemaEscapeInfo info   = expressionEscapeInfoWithTarget(sema, initRef, targetTypeRef, budget);
        if (!info.hasBorrow())
        {
            // A function-valued callback can return a pointer to heap, global, or
            // caller-owned storage. Remember that opaque pointee provenance on the
            // otherwise-local binding so writes through it cannot be mistaken for
            // writes into this frame.
            if (isLocalVariableStorage(sema, symVar) && isDirectBorrowCarrier(sema, targetTypeRef) && isIndirectCallResult(sema, initRef))
            {
                SemaEscapeInfo opaquePointee;
                opaquePointee.kind      = SemaEscapeKind::Unknown;
                opaquePointee.sourceRef = initRef;
                opaquePointee.typeRef   = targetTypeRef;
                sema.setVariableEscapeInfo(symVar, opaquePointee);
                return Result::Continue;
            }

            if (variableInitializerCanEscape(symVar))
            {
                // A retval initializer hands the result back to the caller: RETURN use.
                const DeferredCallUse use = symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal) ? DeferredCallUse::Return : DeferredCallUse::Store;
                recordDeferredCallBorrow(sema, initRef, initRef, "an initializer", use, true);
                sema.clearVariableEscapeInfo(symVar);
            }
            else if (isLocalVariableStorage(sema, symVar))
            {
                // 'let p = f(&v)': the local may borrow the call's arguments - capture
                // them now, judge only if 'p' later escapes.
                bindDeferredCallBorrow(sema, symVar, initRef);
            }
            else
            {
                sema.clearVariableEscapeInfo(symVar);
            }

            return Result::Continue;
        }

        // A borrow of a temporary outlives it as soon as it is bound to a variable.
        // Bindings materialized by an inline expansion live within the enclosing
        // statement, exactly like the temporary itself: nothing escapes there.
        if (info.isTemporaryBorrow())
        {
            auto reportResult = Result::Continue;
            if (!SemaHelpers::effectiveInlinePayload(sema))
                reportResult = reportBorrowEscape(sema, initRef, info, "an initializer");
            sema.clearVariableEscapeInfo(symVar);
            return reportResult;
        }

        // Initializing the RETVAL storage with a parameter borrow hands it back to the
        // caller: feeds the RETURN summary like 'return param'.
        if (info.kind == SemaEscapeKind::Parameter && symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal))
        {
            SymbolFunction* currentFn = sema.currentFunction();
            if (currentFn)
                addReturnBorrowOrigins(*currentFn, info);
        }

        if (info.sourceVar == &symVar)
            sema.clearVariableEscapeInfo(symVar);
        else if (isLocalVariableStorage(sema, symVar))
            sema.setVariableEscapeInfo(symVar, info);
        else if ((info.isLocalBorrow() || info.isMaterializedBorrow()) && variableInitializerCanEscape(symVar))
            return reportBorrowEscape(sema, initRef, info, "an initializer");
        else
            sema.clearVariableEscapeInfo(symVar);
        return Result::Continue;
    }

    Result applyAssignment(Sema& sema, AstNodeRef leftRef, AstNodeRef rightRef)
    {
        if (!lifecycleSanityEnabled(sema))
            return Result::Continue;

        const TypeRef targetTypeRef = destinationTypeRef(sema, leftRef);

        bool                  wholeVariable = false;
        const SymbolVariable* dstVar        = storageRootVariable(sema, leftRef, true, wholeVariable);
        SemaEscapeProjection  projection;
        bool                  hasProjection = dstVar && storageProjection(sema, leftRef, projection) && projection.root == dstVar && !projection.components.empty();
        if (!hasProjection &&
            storageProjection(sema, leftRef, projection) &&
            projection.root &&
            !projection.components.empty() &&
            isLocalVariableStorage(sema, *projection.root) &&
            localProjectionRootCanReceiveLocalStore(sema, *projection.root))
        {
            dstVar        = projection.root;
            wholeVariable = false;
            hasProjection = true;
        }
        if (isDirectBorrowCarrier(sema, targetTypeRef) && (!dstVar || !isLocalVariableStorage(sema, *dstVar)))
        {
            bool                  sourceWhole = false;
            const SymbolVariable* sourceVar   = storageRootVariable(sema, rightRef, false, sourceWhole);
            if (sourceVar && sourceWhole && isLocalVariableStorage(sema, *sourceVar) && typeHasBorrowableStorage(sema, sourceVar->typeRef()))
            {
                SemaEscapeInfo info;
                info.kind      = SemaEscapeKind::Local;
                info.sourceVar = sourceVar;
                info.sourceRef = rightRef;
                info.typeRef   = targetTypeRef;
                return reportBorrowEscape(sema, leftRef, info, "an assignment");
            }
        }
        if (!typeCanCarryBorrowImpl(sema, targetTypeRef))
        {
            if (dstVar)
            {
                if (hasProjection)
                    sema.clearProjectionEscapeInfo(projection);
                else if (wholeVariable)
                    sema.clearVariableEscapeInfo(*dstVar);
            }
            return Result::Continue;
        }

        if (dstVar)
        {
            bool aggregateHandled = false;
            SWC_RESULT(bindAggregateLiteralProjections(sema, aggregateHandled, *dstVar, rightRef, targetTypeRef, "an assignment"));
            if (aggregateHandled)
                return Result::Continue;
        }

        uint32_t             budget = K_EXPR_BUDGET;
        SemaEscapeInfo       info   = expressionEscapeInfoWithTarget(sema, rightRef, targetTypeRef, budget);
        if (!info.hasBorrow())
            info = directTargetStorageBorrowInfo(sema, rightRef, targetTypeRef);
        if (!info.hasBorrow())
        {
            // A destination outside the local frame turns a callee-borrowed argument
            // into an escape: defer the judgement to the per-function summaries. Only a
            // GLOBAL destination provably outlives the frame ('durableDest'): pointer
            // dereferences and parameter-rooted destinations may target caller-frame
            // storage. A RETVAL destination hands the result back to the caller: that
            // is a RETURN use (edges chain into the caller's return summary).
            if (!dstVar || !isLocalVariableStorage(sema, *dstVar))
            {
                const DeferredCallUse use = dstVar && dstVar->hasExtraFlag(SymbolVariableFlagsE::RetVal) ? DeferredCallUse::Return : DeferredCallUse::Store;
                recordDeferredCallBorrow(sema, rightRef, leftRef, "an assignment", use, dstVar && dstVar->hasExtraFlag(SymbolVariableFlagsE::GlobalStorage));
                if (dstVar)
                {
                    if (hasProjection)
                        sema.clearProjectionEscapeInfo(projection);
                    else if (wholeVariable)
                        sema.clearVariableEscapeInfo(*dstVar);
                }
            }
            else if (wholeVariable)
            {
                // 'p = f(&v)' into a local: same deferred capture as an initializer.
                bindDeferredCallBorrow(sema, *dstVar, rightRef);
            }
            else if (hasProjection)
                bindDeferredCallBorrow(sema, *dstVar, rightRef, &projection);

            return Result::Continue;
        }

        // Storing a parameter borrow into a GLOBAL makes this function "store its
        // argument": legal for THIS function (the data is caller-owned), but it feeds
        // the per-function STORES summary judged at every call site against what was
        // really passed in. Only true globals qualify: a destination rooted at a
        // parameter (me.list = x) targets caller-owned storage whose relative
        // lifetime is unknown (the allocator free-lists live in 'me').
        if (info.kind == SemaEscapeKind::Parameter && dstVar && dstVar->hasExtraFlag(SymbolVariableFlagsE::GlobalStorage))
        {
            SymbolFunction* currentFn = sema.currentFunction();
            if (currentFn)
                addStoredBorrowOrigins(*currentFn, info);
        }

        // Storing a parameter borrow into the RETVAL storage hands it back through the
        // return value ('result.field = param; return result'): feeds the RETURN
        // summary exactly like 'return param'.
        if (info.kind == SemaEscapeKind::Parameter && dstVar && dstVar->hasExtraFlag(SymbolVariableFlagsE::RetVal))
        {
            SymbolFunction* currentFn = sema.currentFunction();
            if (currentFn)
                addReturnBorrowOrigins(*currentFn, info);
        }

        // Storing a parameter borrow into storage reachable from ANOTHER parameter
        // ('me.list = item' -> pair item->me): legal here, but judged at call sites
        // where the destination argument provably outlives the stored one. The
        // assignment-mode root above bails on parameter-pointer destinations, so walk
        // the destination in READ mode: it roots member/dref accesses at the signature
        // receiver. A BARE identifier destination is the parameter being rebound: no
        // caller-visible store.
        if (info.kind == SemaEscapeKind::Parameter)
        {
            bool                  pairWhole       = false;
            const SymbolVariable* pairRoot        = storageRootVariable(sema, leftRef, false, pairWhole);
            SymbolFunction*       currentFn       = sema.currentFunction();
            const AstNodeRef      leftResolvedRef = sema.viewZero(leftRef).nodeRef();
            const bool            leftIsBareVar   = leftResolvedRef.isValid() && sema.node(leftResolvedRef).is(AstNodeId::Identifier);
            if (pairRoot && !leftIsBareVar && currentFn)
            {
                const SymbolVariable* dstParam = signatureParameterFor(sema, *pairRoot);
                if (dstParam && !isByValueParameterStorage(sema, *dstParam))
                {
                    size_t intoIndex   = 0;
                    if (findCallerParameterIndex(*currentFn, *dstParam, intoIndex))
                    {
                        const uint64_t origins = parameterOriginsMask(*currentFn, info);
                        for (size_t storedIndex = 0; storedIndex < 64; ++storedIndex)
                        {
                            if ((origins & (1ULL << storedIndex)) && storedIndex != intoIndex)
                                currentFn->addStoresIntoParam(intoIndex, storedIndex);
                        }
                    }
                }
            }
        }

        if (dstVar)
            return storeOrReportDestinationInfo(sema, *dstVar, leftRef, info, "an assignment", hasProjection ? &projection : nullptr);
        if (info.isLocalBorrow() || info.isMaterializedBorrow() || info.isTemporaryBorrow())
            return reportBorrowEscape(sema, leftRef, info, "an assignment");

        return Result::Continue;
    }

    // A 'foreach &it' alias points into the iterated storage: bind the alias to that
    // storage's borrow so uses of 'it' escaping the loop are tracked like any pointer.
    void bindForeachAddressAlias(Sema& sema, const SymbolVariable& symVar, AstNodeRef exprRef)
    {
        if (!lifecycleSanityEnabled(sema))
            return;

        uint32_t       budget = K_EXPR_BUDGET;
        SemaEscapeInfo info   = expressionEscapeInfoRec(sema, exprRef, budget);
        if (!info.hasBorrow() && expressionMayExposeStorageBorrow(sema, exprRef))
            info = storageBorrowInfo(sema, exprRef, symVar.typeRef());

        if (info.hasBorrow())
            sema.setVariableEscapeInfo(symVar, info);
        else
            sema.clearVariableEscapeInfo(symVar);
    }

    const SymbolVariable* iterationSourceRoot(Sema& sema, AstNodeRef exprRef)
    {
        if (!lifecycleSanityEnabled(sema) || exprRef.isInvalid())
            return nullptr;
        return rootStorageOf(sema, exprRef);
    }

    Result checkIterationMutation(Sema& sema, AstNodeRef callRef, const SymbolFunction& calledFn)
    {
        if (!lifecycleSanityEnabled(sema))
            return Result::Continue;

        // Only a method can mutate its receiver, a 'const' method cannot, and operator
        // methods (opIndex/opIndexSet/opSlice/opData/opCount/opCast/opVisit ...) are
        // element or view access rather than a structural change of the collection.
        if (!calledFn.isMethod() || calledFn.isConst())
            return Result::Continue;

        const std::span<const SemaIterationBorrow> activeBorrows = sema.frame().iterationBorrows();
        if (activeBorrows.empty())
            return Result::Continue;

        const Utf8             calleeName = calledFn.name(sema.ctx());
        const std::string_view calleeView{calleeName};
        if (calleeView.starts_with("op"))
            return Result::Continue;

        // The receiver is the first non-interface argument of the resolved call; for the
        // projection match prefer the syntactic method receiver ('holder.items.add' ->
        // 'holder.items'), whose field path survives resolution intact.
        SmallVector<ResolvedCallArgument> args;
        sema.appendResolvedCallArguments(callRef, args);
        AstNodeRef receiverRef = AstNodeRef::invalid();
        for (const ResolvedCallArgument& arg : args)
        {
            if (arg.passKind == CallArgumentPassKind::InterfaceObject)
                continue;
            receiverRef = argumentValueRef(sema, arg.argRef);
            break;
        }
        if (receiverRef.isInvalid())
            return Result::Continue;

        AstNodeRef projectedReceiverRef = syntacticMethodReceiverRef(sema, callRef);
        if (projectedReceiverRef.isInvalid())
            projectedReceiverRef = receiverRef;

        SemaEscapeProjection receiverProj;
        bool                 receiverExact = false;
        resolveIterationProjection(sema, projectedReceiverRef, receiverProj, receiverExact);
        if (!receiverProj.root)
            return Result::Continue;

        for (const SemaIterationBorrow& borrow : activeBorrows)
        {
            if (borrow.root != receiverProj.root)
                continue;

            // Iteration is tracked at the storage level, so mutating a sibling field of a
            // shared owner ('holder.other' while iterating 'holder.items') stays silent.
            SemaEscapeProjection sourceProj;
            bool                 sourceExact = false;
            resolveIterationProjection(sema, borrow.sourceRef, sourceProj, sourceExact);
            if (!iterationMutationHitsSource(sourceProj, sourceExact, receiverProj, receiverExact))
                continue;

            // Spare the find-then-remove-then-exit pattern: the loop does not iterate again
            // after the mutation, so the snapshot is never read stale.
            if (mutationFollowedByLoopExit(sema, borrow.bodyRef, callRef))
                continue;

            auto diag = SemaError::report(sema, DiagnosticId::sanity_err_collection_mutated, callRef);
            diag.addArgument(Diagnostic::ARG_SYM, receiverProj.root->name(sema.ctx()));
            diag.addArgument(Diagnostic::ARG_VALUE, calleeName);
            if (borrow.sourceRef.isValid())
            {
                diag.addNote(DiagnosticId::sema_note_iteration_source_here);
                diag.last().addArgument(Diagnostic::ARG_SYM, receiverProj.root->name(sema.ctx()));
                diag.last().addSpan(sema.node(borrow.sourceRef).codeRange(sema.ctx()));
            }
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Continue;
    }

    Result checkReturn(Sema& sema, AstNodeRef returnRef, AstNodeRef exprRef, TypeRef returnTypeRef, const SymbolFunction* inlineSourceFn)
    {
        if (!lifecycleSanityEnabled(sema))
            return Result::Continue;

        if (!typeCanCarryBorrowImpl(sema, returnTypeRef))
            return Result::Continue;

        uint32_t             budget = K_EXPR_BUDGET;
        const SemaEscapeInfo info   = expressionEscapeInfoWithTarget(sema, exprRef, returnTypeRef, budget);

        // A returned call result may borrow the arguments handed to the callee: defer
        // the judgement to the per-function summaries.
        if (!info.hasBorrow() && !inlineSourceFn)
            recordDeferredCallBorrow(sema, exprRef, returnRef, "a return value", DeferredCallUse::Return, false);

        // A temporary lives until the end of the enclosing statement, and materialized
        // cast storage lives with the frame. An inline-expanded return hands both back
        // within the calling frame, so only a real function return outlives them.
        if (info.isTemporaryBorrow() || info.isMaterializedBorrow())
        {
            if (!inlineSourceFn)
                return reportBorrowEscape(sema, returnRef, info, "a return value");
            return Result::Continue;
        }

        // A local bound to an opaque call result and returned ('let p = f(&v); return
        // p'): judge the captured argument borrows against the callee's summaries.
        if (info.isDeferredCallBorrow())
        {
            if (!inlineSourceFn)
                emitDeferredCallEscape(sema, info, returnRef, "a return value", SemaEscapeSummaryEdgeKind::ReturnToReturn);
            return Result::Continue;
        }

        // Returning a borrow of caller-owned data is fine for THIS function, but feeds
        // the per-function summary consumed at call sites (callResultEscapeInfo).
        if (!inlineSourceFn && info.kind == SemaEscapeKind::Parameter)
        {
            SymbolFunction* currentFn = sema.currentFunction();
            if (currentFn)
                addReturnBorrowOrigins(*currentFn, info);
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

    void noteCallArguments(Sema& sema, AstNodeRef callRef)
    {
        if (!lifecycleSanityEnabled(sema))
            return;

        recordDeferredCallBorrow(sema, callRef, callRef, "a stored call argument", DeferredCallUse::Argument, false);
    }

    void reportDeferredChecks(TaskContext& ctx)
    {
        std::vector<SemaEscapeDeferredCheck>     checks = ctx.compiler().takeDeferredEscapeChecks();
        const std::vector<SemaEscapeSummaryEdge> edges  = ctx.compiler().takeEscapeSummaryEdges();

        // Chain the per-function summaries across opaque calls before judging: a
        // wrapper that returns 'g(p)' borrows whatever 'g' says it borrows, and a
        // function that forwards its parameter to a storing callee stores it too.
        // Masks only grow, so the fixpoint terminates; cycles (mutual recursion) just
        // converge. Sema is fully drained here, so growing the masks is race-free.
        bool changed = !edges.empty();
        while (changed)
        {
            changed = false;
            for (const SemaEscapeSummaryEdge& edge : edges)
            {
                const uint64_t calleeBit = 1ULL << edge.calleeParamIndex;
                const uint64_t callerBit = 1ULL << edge.callerParamIndex;
                switch (edge.kind)
                {
                    case SemaEscapeSummaryEdgeKind::ReturnToReturn:
                        if ((edge.callee->returnBorrowsParamsMask() & calleeBit) && !(edge.caller->returnBorrowsParamsMask() & callerBit))
                        {
                            edge.caller->addReturnBorrowsParam(edge.callerParamIndex);
                            changed = true;
                        }
                        break;

                    case SemaEscapeSummaryEdgeKind::ReturnToStores:
                        if ((edge.callee->returnBorrowsParamsMask() & calleeBit) && !(edge.caller->storesParamsMask() & callerBit))
                        {
                            edge.caller->addStoresParam(edge.callerParamIndex);
                            changed = true;
                        }
                        break;

                    case SemaEscapeSummaryEdgeKind::StoresToStores:
                        if ((edge.callee->storesParamsMask() & calleeBit) && !(edge.caller->storesParamsMask() & callerBit))
                        {
                            edge.caller->addStoresParam(edge.callerParamIndex);
                            changed = true;
                        }
                        // The same forwarding edge chains the FREES summary: a wrapper
                        // handing its parameter to a freeing callee frees it too.
                        if ((edge.callee->freesParamsMask() & calleeBit) && !(edge.caller->freesParamsMask() & callerBit))
                        {
                            edge.caller->addFreesParam(edge.callerParamIndex);
                            changed = true;
                        }
                        break;

                    case SemaEscapeSummaryEdgeKind::PairToPair:
                        if (SymbolFunction::hasStoresIntoPair(edge.callee->storesIntoParamPairs(), edge.calleeIntoParamIndex, edge.calleeParamIndex) &&
                            !SymbolFunction::hasStoresIntoPair(edge.caller->storesIntoParamPairs(), edge.callerIntoParamIndex, edge.callerParamIndex))
                        {
                            edge.caller->addStoresIntoParam(edge.callerIntoParamIndex, edge.callerParamIndex);
                            changed = true;
                        }
                        break;
                }
            }
        }

        if (checks.empty())
            return;

        // Records were appended by concurrently running sema jobs: sort them so the
        // report order is stable whatever thread analyzed what.
        std::ranges::sort(checks, [](const SemaEscapeDeferredCheck& a, const SemaEscapeDeferredCheck& b) {
            if (a.fileRef != b.fileRef)
                return a.fileRef < b.fileRef;
            if (a.siteRange.offset != b.siteRange.offset)
                return a.siteRange.offset < b.siteRange.offset;
            if (a.paramIndex != b.paramIndex)
                return a.paramIndex < b.paramIndex;
            if (a.callee != b.callee)
                return std::less<const SymbolFunction*>{}(a.callee, b.callee);
            if (a.judgeStores != b.judgeStores)
                return a.judgeStores < b.judgeStores;
            if (a.judgePairs != b.judgePairs)
                return a.judgePairs < b.judgePairs;
            if (a.intoParamIndex != b.intoParamIndex)
                return a.intoParamIndex < b.intoParamIndex;
            if (a.guards.size() != b.guards.size())
                return a.guards.size() < b.guards.size();
            return a.symName < b.symName;
        });

        const SemaEscapeDeferredCheck* previous = nullptr;
        for (const SemaEscapeDeferredCheck& check : checks)
        {
            if (!check.callee)
                continue;

            // A site can be recorded once per escape route; a re-run sema node must
            // not report twice.
            if (previous &&
                previous->fileRef == check.fileRef &&
                previous->siteRange.offset == check.siteRange.offset &&
                previous->paramIndex == check.paramIndex &&
                previous->callee == check.callee &&
                previous->judgeStores == check.judgeStores &&
                previous->judgePairs == check.judgePairs &&
                previous->intoParamIndex == check.intoParamIndex &&
                previous->guards.size() == check.guards.size() &&
                std::equal(previous->guards.begin(), previous->guards.end(), check.guards.begin()) &&
                previous->symName == check.symName &&
                previous->diagId == check.diagId)
                continue;
            previous = &check;

            DiagnosticId diagId = check.diagId;
            if (check.judgeAlways)
            {
                // Certain from the callee's identity: no summary to consult.
            }
            else if (check.judgePairs)
            {
                if (!SymbolFunction::hasStoresIntoPair(check.callee->storesIntoParamPairs(), check.intoParamIndex, check.paramIndex))
                    continue;
            }
            else if (check.judgeStores)
            {
                // An argument handed to a callee escapes when the callee KEEPS it
                // (stores summary) or is invalidated when the callee FREES it. An
                // owner's payload lives on the heap: freeing it is legitimate.
                const bool storesHit = (check.callee->storesParamsMask() >> check.paramIndex) & 1;
                const bool freesHit  = (check.callee->freesParamsMask() >> check.paramIndex) & 1;
                if (!storesHit && !freesHit)
                    continue;
                if (!storesHit)
                {
                    if (check.ownerSource)
                        continue;
                    diagId = DiagnosticId::sanity_err_free_borrowed;
                }
            }
            else
            {
                if (!(check.callee->returnBorrowsParamsMask() & (1ULL << check.paramIndex)))
                    continue;
            }

            const bool guardMiss = std::ranges::any_of(check.guards, [](const SemaEscapeDeferredGuard& guard) {
                return !guard.callee || !(guard.callee->returnBorrowsParamsMask() & (1ULL << guard.paramIndex));
            });
            if (guardMiss)
                continue;

            Diagnostic diag = Diagnostic::get(diagId, check.fileRef);
            diag.last().addSpan(check.siteRange);
            if (!check.symName.empty())
                diag.addArgument(Diagnostic::ARG_SYM, check.symName);
            diag.addArgument(Diagnostic::ARG_WHAT, check.what);
            if (check.typeRef.isValid())
                diag.addArgument(Diagnostic::ARG_TYPE, check.typeRef);

            if (check.noteId != DiagnosticId::None)
            {
                diag.addNote(check.noteId);
                if (!check.noteSymName.empty())
                    diag.last().addArgument(Diagnostic::ARG_SYM, check.noteSymName);
                diag.last().addSpan(check.noteRange);
            }

            for (const SemaEscapeDeferredGuard& guard : check.guards)
            {
                if (!guard.callee)
                    continue;
                diag.addNote(DiagnosticId::sema_note_borrow_propagated_through);
                diag.last().addArgument(Diagnostic::ARG_SYM, guard.callee->name(ctx));
                diag.last().addSpan(guard.callee->codeRange(ctx));
            }

            diag.report(ctx);
        }
    }
}

SWC_END_NAMESPACE();
