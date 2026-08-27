#include "pch.h"
#include "Compiler/Sema/Helpers/SemaEscape.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

// The borrow rules in this file are part of the LANGUAGE, not of the sanity tooling, and
// nothing here consults '#[Swag.Sanity]' or 'buildCfg.sanityGuards'. A program that lets a
// view outlive the storage it views is not a Swag program, and whether it is accepted must
// not depend on an attribute: a guarantee a caller can switch off is not a guarantee.
//
// What stays under '.Lifecycle' is the other half - the backend analyses that PROVE a
// runtime fault (use after free, use after move, a read of uninitialized storage). Those
// answer "this run will certainly fault", and how much of that a compiler can prove is a
// property of the compiler, not of the language.

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

    bool designatedStorageHasOwningLifecycle(Sema& sema, TypeRef typeRef)
    {
        typeRef = unwrapAliasEnum(sema, typeRef);
        if (!typeRef.isValid())
            return false;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isAnyPointer() || type.isReference())
            typeRef = unwrapAliasEnum(sema, type.payloadTypeRef());
        return hasOwningLifecycle(sema, typeRef);
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

    // Does a by-value parameter really behave like a local? An OWNING one does not: the
    // callee neither copies nor drops it, so what it owns stays the caller's and only its
    // slot lives in this frame. Rooting such a parameter at the frame would report every
    // accessor of an owner taken by value as an escape; rooting it at the signature moves
    // the judgement to the call site, where the argument's real lifetime is known.
    bool isFrameLocalParameterStorage(Sema& sema, const SymbolVariable& symVar)
    {
        return isByValueParameterStorage(sema, symVar) && !hasOwningLifecycle(sema, symVar.typeRef());
    }

    bool isLocalVariableStorage(Sema& sema, const SymbolVariable& symVar)
    {
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::GlobalStorage) ||
            symVar.hasExtraFlag(SymbolVariableFlagsE::RuntimeStorage) ||
            symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal))
            return false;

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
            return isFrameLocalParameterStorage(sema, symVar);

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
            info.kind = isFrameLocalParameterStorage(sema, symVar) ? SemaEscapeKind::Local : SemaEscapeKind::Parameter;
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

    // Walkers below mix raw operand edges with substitute hops; a reentrant cast chain
    // (an argument re-wrapped across sema revisits) can make that graph cyclic, so every
    // recursive walk carries a depth budget and bails out conservatively when exceeded.
    constexpr uint32_t K_STORAGE_WALK_BUDGET = 64;

    const SymbolVariable* storageRootVariableAt(Sema& sema, AstNodeRef resolvedRef, bool forAssignment, bool& outWholeVariable, uint32_t depth);
    bool                  typeHasBorrowableStorage(Sema& sema, TypeRef typeRef);

    const SymbolVariable* storageRootVariable(Sema& sema, AstNodeRef nodeRef, bool forAssignment, bool& outWholeVariable, uint32_t depth = 0)
    {
        outWholeVariable = false;
        if (nodeRef.isInvalid() || depth > K_STORAGE_WALK_BUDGET)
            return nullptr;

        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isInvalid())
            return nullptr;

        return storageRootVariableAt(sema, resolvedRef, forAssignment, outWholeVariable, depth + 1);
    }

    bool storageProjectionAt(Sema& sema, AstNodeRef resolvedRef, SemaEscapeProjection& outProjection, uint32_t depth);

    bool storageProjection(Sema& sema, AstNodeRef nodeRef, SemaEscapeProjection& outProjection, uint32_t depth = 0)
    {
        if (nodeRef.isInvalid() || depth > K_STORAGE_WALK_BUDGET)
            return false;

        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isInvalid())
            return false;

        return storageProjectionAt(sema, resolvedRef, outProjection, depth + 1);
    }

    bool storageProjectionAt(Sema& sema, AstNodeRef resolvedRef, SemaEscapeProjection& outProjection, uint32_t depth)
    {
        const AstNode& node = sema.node(resolvedRef);
        switch (node.id())
        {
            case AstNodeId::Identifier:
                outProjection.root = identifierVariable(sema, resolvedRef);
                return outProjection.root != nullptr;

            case AstNodeId::ParenExpr:
                return storageProjection(sema, node.cast<AstParenExpr>().nodeExprRef, outProjection, depth + 1);

            case AstNodeId::InitializerExpr:
                return storageProjection(sema, node.cast<AstInitializerExpr>().nodeExprRef, outProjection, depth + 1);

            case AstNodeId::AutoCastExpr:
                return storageProjection(sema, node.cast<AstAutoCastExpr>().nodeExprRef, outProjection, depth + 1);

            case AstNodeId::AsCastExpr:
                return storageProjection(sema, node.cast<AstAsCastExpr>().nodeExprRef, outProjection, depth + 1);

            case AstNodeId::CastExpr:
            {
                // An implicit conversion (e.g. the nullable widening synthesized when a
                // flow-narrowed value meets a nullable target) must stay transparent for
                // field-sensitive borrow tracking.
                const AstNodeRef operandRef = node.cast<AstCastExpr>().nodeExprRef;
                if (castOperandSelfSubstituted(sema, resolvedRef, operandRef))
                    return storageProjectionAt(sema, operandRef, outProjection, depth + 1);
                return storageProjection(sema, operandRef, outProjection, depth + 1);
            }

            case AstNodeId::MemberAccessExpr:
            {
                if (!storageProjection(sema, node.cast<AstMemberAccessExpr>().nodeLeftRef, outProjection, depth + 1))
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
                if (!storageProjection(sema, index.nodeExprRef, outProjection, depth + 1))
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

    // A BLOCK pointer held by a value with an OWNING lifecycle addresses memory that
    // value releases when it dies: '[*] T' is how the language spells "a buffer of
    // elements", which is what an owner allocates and frees.
    //
    // A plain '*T' is deliberately excluded: a single-object pointer inside an owner is
    // just as often a back-reference to something it does not own (a parent window, a
    // callback target), and rooting those at the holder invents borrows that do not
    // exist.
    bool isOwnedPayloadCarrier(Sema& sema, TypeRef typeRef)
    {
        typeRef = unwrapAliasEnum(sema, typeRef);
        if (!typeRef.isValid())
            return false;

        return sema.typeMgr().get(typeRef).isBlockPointer();
    }

    // The variable owning the storage a carrier EXPRESSION addresses, when that carrier
    // was read out of an owning value ('me.table', 'set.buffer'): writing through it
    // writes into the owner, and reading through it borrows the owner. Null when the
    // carrier came from a value that does not free it - its pointee may live anywhere.
    const SymbolVariable* carrierBaseStorageRoot(Sema& sema, AstNodeRef baseRef, bool forAssignment, uint32_t depth);

    const SymbolVariable* ownedPayloadStorageRootAt(Sema& sema, AstNodeRef resolvedRef, bool forAssignment, uint32_t depth);
    const SymbolVariable* signatureParameterFor(Sema& sema, const SymbolVariable& symVar);

    const SymbolVariable* ownedPayloadStorageRoot(Sema& sema, AstNodeRef carrierRef, bool forAssignment, uint32_t depth)
    {
        if (carrierRef.isInvalid() || depth > K_STORAGE_WALK_BUDGET)
            return nullptr;

        const AstNodeRef resolvedRef = sema.viewZero(carrierRef).nodeRef();
        if (resolvedRef.isInvalid())
            return nullptr;

        return ownedPayloadStorageRootAt(sema, resolvedRef, forAssignment, depth);
    }

    // Same walk, entered on a node the caller ALREADY resolved. Re-resolving it would
    // undo that: the operand of a self-substituted cast resolves back to the cast, and
    // the walk would then see a cast where its caller carefully saw the member access.
    const SymbolVariable* ownedPayloadStorageRootAt(Sema& sema, AstNodeRef resolvedRef, bool forAssignment, uint32_t depth)
    {
        if (resolvedRef.isInvalid() || depth > K_STORAGE_WALK_BUDGET)
            return nullptr;

        const AstNode& node = sema.node(resolvedRef);
        switch (node.id())
        {
            case AstNodeId::ParenExpr:
                return ownedPayloadStorageRoot(sema, node.cast<AstParenExpr>().nodeExprRef, forAssignment, depth + 1);
            case AstNodeId::InitializerExpr:
                return ownedPayloadStorageRoot(sema, node.cast<AstInitializerExpr>().nodeExprRef, forAssignment, depth + 1);
            case AstNodeId::AutoCastExpr:
                return ownedPayloadStorageRoot(sema, node.cast<AstAutoCastExpr>().nodeExprRef, forAssignment, depth + 1);
            case AstNodeId::AsCastExpr:
                return ownedPayloadStorageRoot(sema, node.cast<AstAsCastExpr>().nodeExprRef, forAssignment, depth + 1);
            case AstNodeId::ErrorManagementExpr:
                return ownedPayloadStorageRoot(sema, node.cast<AstErrorManagementExpr>().nodeExprRef, forAssignment, depth + 1);
            case AstNodeId::CastExpr:
            {
                const AstNodeRef operandRef = node.cast<AstCastExpr>().nodeExprRef;
                if (castOperandSelfSubstituted(sema, resolvedRef, operandRef))
                    return nullptr;
                return ownedPayloadStorageRoot(sema, operandRef, forAssignment, depth + 1);
            }

            case AstNodeId::MemberAccessExpr:
                break;

            default:
                return nullptr;
        }

        // An implicit conversion SUBSTITUTES the member-access node, so its resolved type
        // is the CONVERTED one: a '[*] u8' payload assigned to an 'AllocatorRequest.address'
        // field reads back as '*void' and stops looking like a payload. Whether a member is
        // storage its owner frees is a property of the FIELD's declaration, so decide on
        // that and fall back to the expression only when the field symbol is unavailable.
        const SymbolVariable* memberField   = identifierVariable(sema, resolvedRef);
        const TypeRef         memberTypeRef = memberField ? memberField->typeRef() : expressionTypeRef(sema, resolvedRef);
        if (!isOwnedPayloadCarrier(sema, memberTypeRef))
            return nullptr;

        // The value the member was read out of, seen through the pointer or reference
        // used to reach it ('me' is a '*Vec', the owning type is 'Vec').
        const AstNodeRef leftRef        = node.cast<AstMemberAccessExpr>().nodeLeftRef;
        const TypeRef    rawLeftTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, leftRef));
        TypeRef          leftTypeRef    = unwrapAliasEnum(sema, rawLeftTypeRef);
        const bool       leftIsCarrier  = isDirectBorrowCarrier(sema, rawLeftTypeRef);
        if (leftTypeRef.isValid())
        {
            const TypeInfo& leftType = sema.typeMgr().get(leftTypeRef);
            if (leftType.isAnyPointer())
                leftTypeRef = unwrapAliasEnum(sema, leftType.payloadTypeRef());
        }

        if (!hasOwningLifecycle(sema, leftTypeRef))
            return nullptr;

        // Reached through a POINTER, the owner is whatever that pointer designates, not
        // the pointer variable: a local '*Array' aimed at caller storage owns nothing,
        // and its payload must not be rooted at the frame.
        if (leftIsCarrier)
            return carrierBaseStorageRoot(sema, leftRef, forAssignment, depth + 1);

        bool leftWhole = false;
        return storageRootVariable(sema, leftRef, forAssignment, leftWhole, depth + 1);
    }

    // The storage root of an expression reached THROUGH a carrier ('p[]', 'p.field',
    // 'p[i]'): the pointee is a root only when the carrier is tracked - a pointer holding
    // a local borrow, a pointer parameter (caller-owned storage), a local bound to either
    // of those, or a payload owned by a known value.
    const SymbolVariable* carrierBaseStorageRoot(Sema& sema, AstNodeRef baseRef, bool forAssignment, uint32_t depth)
    {
        bool                  baseWhole = false;
        const SymbolVariable* baseVar   = storageRootVariable(sema, baseRef, forAssignment, baseWhole, depth + 1);
        if (baseVar && baseWhole)
        {
            const SemaEscapeInfo* baseInfo = sema.variableEscapeInfo(*baseVar);
            if (baseInfo && baseInfo->isLocalBorrow())
                return baseInfo->sourceVar;

            // Data reached through a pointer/reference parameter (including the body 'me'
            // binding) belongs to the caller: root at the parameter so returns feed the
            // borrow summary. Same for a local that was bound to such a pointer.
            if (!forAssignment)
            {
                if (baseInfo && baseInfo->kind == SemaEscapeKind::Parameter && baseInfo->sourceVar)
                    return baseInfo->sourceVar;

                const SemaEscapeInfo baseStorage = variableStorageInfo(sema, *baseVar, baseRef, TypeRef::invalid());
                if (baseStorage.kind == SemaEscapeKind::Parameter && baseStorage.sourceVar)
                    return baseStorage.sourceVar;
            }

            return nullptr;
        }

        return ownedPayloadStorageRoot(sema, baseRef, forAssignment, depth);
    }

    // The storage root of 'base[i]'. Indexing a builtin array or slice stays inside the
    // indexed storage; indexing a raw pointer is a dereference and follows the carrier
    // rules.
    const SymbolVariable* indexedStorageRoot(Sema& sema, AstNodeRef indexedRef, bool forAssignment, uint32_t depth)
    {
        if (isArrayStorageExpr(sema, indexedRef))
        {
            bool indexedWhole = false;
            return storageRootVariable(sema, indexedRef, forAssignment, indexedWhole, depth + 1);
        }

        const TypeRef indexedTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, indexedRef));
        if (!isDirectBorrowCarrier(sema, indexedTypeRef))
            return nullptr;

        return carrierBaseStorageRoot(sema, indexedRef, forAssignment, depth);
    }

    const SymbolVariable* storageRootVariableAt(Sema& sema, AstNodeRef resolvedRef, bool forAssignment, bool& outWholeVariable, uint32_t depth)
    {
        outWholeVariable = false;

        const AstNode& node = sema.node(resolvedRef);
        switch (node.id())
        {
            case AstNodeId::Identifier:
                outWholeVariable = true;
                return identifierVariable(sema, resolvedRef);

            case AstNodeId::ParenExpr:
                return storageRootVariable(sema, node.cast<AstParenExpr>().nodeExprRef, forAssignment, outWholeVariable, depth + 1);

            case AstNodeId::InitializerExpr:
                return storageRootVariable(sema, node.cast<AstInitializerExpr>().nodeExprRef, forAssignment, outWholeVariable, depth + 1);

            case AstNodeId::AutoCastExpr:
                return storageRootVariable(sema, node.cast<AstAutoCastExpr>().nodeExprRef, forAssignment, outWholeVariable, depth + 1);

            case AstNodeId::AsCastExpr:
                return storageRootVariable(sema, node.cast<AstAsCastExpr>().nodeExprRef, forAssignment, outWholeVariable, depth + 1);

            // 'p!' only asserts non-nullness, and 'try'/'catch'/'expect' hand back the
            // value of their operand: none of them changes what storage is designated.
            case AstNodeId::ErrorManagementExpr:
                return storageRootVariable(sema, node.cast<AstErrorManagementExpr>().nodeExprRef, forAssignment, outWholeVariable, depth + 1);

            case AstNodeId::CastExpr:
            {
                const AstNodeRef operandRef = node.cast<AstCastExpr>().nodeExprRef;
                if (castOperandSelfSubstituted(sema, resolvedRef, operandRef))
                    return storageRootVariableAt(sema, operandRef, forAssignment, outWholeVariable, depth + 1);
                return storageRootVariable(sema, operandRef, forAssignment, outWholeVariable, depth + 1);
            }

            case AstNodeId::MemberAccessExpr:
            {
                const AstNodeRef leftRef     = node.cast<AstMemberAccessExpr>().nodeLeftRef;
                const TypeRef    leftTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, leftRef));
                if (isDirectBorrowCarrier(sema, leftTypeRef))
                {
                    outWholeVariable = false;
                    return carrierBaseStorageRoot(sema, leftRef, forAssignment, depth);
                }

                // A member access never designates the WHOLE variable, whatever the
                // recursion reports for the left side.
                bool                  leftWhole = false;
                const SymbolVariable* leftRoot  = storageRootVariable(sema, leftRef, forAssignment, leftWhole, depth + 1);
                outWholeVariable                = false;
                return leftRoot;
            }

            case AstNodeId::IndexExpr:
                outWholeVariable = false;
                return indexedStorageRoot(sema, node.cast<AstIndexExpr>().nodeExprRef, forAssignment, depth);

            case AstNodeId::IndexListExpr:
                outWholeVariable = false;
                return indexedStorageRoot(sema, node.cast<AstIndexListExpr>().nodeExprRef, forAssignment, depth);

            case AstNodeId::UnaryExpr:
            {
                const auto& unary = node.cast<AstUnaryExpr>();

                // A dereference designates the pointee storage, not the pointer variable: it
                // is a borrow root only when the pointer itself borrows a tracked local. A
                // heap or caller-owned pointee is not a borrow root.
                if (Token::isDeref(sema.token(node.codeRef()).id))
                {
                    outWholeVariable = false;
                    return carrierBaseStorageRoot(sema, unary.nodeExprRef, forAssignment, depth);
                }

                return forAssignment ? nullptr : storageRootVariable(sema, unary.nodeExprRef, forAssignment, outWholeVariable, depth + 1);
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

    TypeRef structLikeChildTargetType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef)
    {
        const TypeRef targetRef = SemaHelpers::unwrapBindingType(sema.ctx(), targetTypeRef);
        if (!targetRef.isValid())
            return TypeRef::invalid();

        SemaHelpers::AggregateChildSlot slot;
        if (!SemaHelpers::resolveAggregateChildSlot(sema, slot, sema.typeMgr().get(targetRef), children, childRef))
            return TypeRef::invalid();

        return slot.typeRef;
    }

    bool structLikeChildProjectionComponent(Sema& sema, SemaEscapeProjectionComponent& outComponent, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef)
    {
        const TypeRef targetRef = SemaHelpers::unwrapBindingType(sema.ctx(), targetTypeRef);
        if (!targetRef.isValid())
            return false;

        SemaHelpers::AggregateChildSlot slot;
        if (!SemaHelpers::resolveAggregateChildSlot(sema, slot, sema.typeMgr().get(targetRef), children, childRef))
            return false;

        if (slot.field)
            outComponent = {.kind = SemaEscapeProjectionKind::Field, .field = slot.field};
        else
            outComponent = {.kind = SemaEscapeProjectionKind::ConstantIndex, .index = slot.index};
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

    SemaEscapeInfo anyBoxEscapeInfo(Sema& sema, AstNodeRef castRef, const AstCastExpr& cast, TypeRef resultTypeRef)
    {
        // A constant box is lowered into the compiler data segment. Every runtime box
        // instead points either at the lvalue being boxed or at hidden cast storage in
        // the current frame; the outer 'any' must not outlive that storage even when
        // the boxed value is itself a pointer to longer-lived data.
        if (sema.viewConstant(castRef).hasConstant())
            return {};

        const AstNodeRef      sourceRef     = cast.nodeExprRef;
        bool                  wholeVariable = false;
        const SymbolVariable* sourceVar     = storageRootVariable(sema, sourceRef, false, wholeVariable);

        // Pointer and reference parameters are carried as values. Boxing the parameter
        // therefore points at the cast's local copy, not at the caller-owned pointee that
        // the ordinary borrow provenance describes.
        bool valueBackedParameter = false;
        if (sourceVar && wholeVariable && sourceVar->hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            const TypeRef sourceTypeRef = unwrapAliasEnum(sema, castOperandTypeRef(sema, castRef, sourceRef));
            if (sourceTypeRef.isValid())
            {
                const TypeInfo& sourceType = sema.typeMgr().get(sourceTypeRef);
                valueBackedParameter       = sourceType.isAnyPointer() || sourceType.isReference();
            }
        }

        SemaEscapeInfo info;
        if (!valueBackedParameter)
        {
            info = storageBorrowInfo(sema, sourceRef, resultTypeRef, true);
            if (info.hasBorrow())
                return info;
        }

        const AstNodeRef resolvedSourceRef = sema.viewZero(sourceRef).nodeRef();
        info.kind                          = SemaEscapeKind::Materialized;
        info.sourceRef                     = resolvedSourceRef.isValid() ? resolvedSourceRef : sourceRef;
        info.typeRef                       = resultTypeRef;
        info.sourceScopeDepth              = sema.currentScopeDepth();
        return info;
    }

    SemaEscapeInfo castEscapeInfo(Sema& sema, AstNodeRef castRef, const AstCastExpr& cast, uint32_t& budget)
    {
        const TypeRef  resultTypeRef    = expressionTypeRef(sema, castRef);
        const bool     operandSelfSubst = castOperandSelfSubstituted(sema, castRef, cast.nodeExprRef);

        const TypeRef sourceTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), castOperandTypeRef(sema, castRef, cast.nodeExprRef));
        if (resultTypeRef.isValid() &&
            sourceTypeRef.isValid() &&
            sema.typeMgr().get(unwrapAliasEnum(sema, resultTypeRef)).isAny() &&
            !sema.typeMgr().get(unwrapAliasEnum(sema, sourceTypeRef)).isAny())
            return anyBoxEscapeInfo(sema, castRef, cast, resultTypeRef);

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
        // slice, building an interface from a struct, ...
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

    // The element type of an indexable expression (a builtin array or a slice), or invalid
    // when the expression is neither. Reads the RESOLVED node's type: indexing a struct
    // container decays the operand to a slice through an implicit 'opCast', so the raw
    // identifier still types as the struct while the resolved cast types as the slice.
    TypeRef indexedElementTypeRef(Sema& sema, AstNodeRef indexedRef)
    {
        const AstNodeRef resolvedRef    = sema.viewZero(indexedRef).nodeRef();
        const TypeRef    indexedTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), expressionTypeRef(sema, resolvedRef.isValid() ? resolvedRef : indexedRef));
        if (!indexedTypeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& indexedType = sema.typeMgr().get(indexedTypeRef);
        if (indexedType.isArray())
            return indexedType.payloadArrayElemTypeRef();
        if (indexedType.isSlice())
            return indexedType.payloadTypeRef();
        return TypeRef::invalid();
    }

    SemaEscapeInfo indexEscapeInfo(Sema& sema, AstNodeRef indexRef, AstNodeRef indexedRef, uint32_t& budget)
    {
        const TypeRef resultTypeRef = expressionTypeRef(sema, indexRef);

        // Reading a single ELEMENT by value copies it: the copy aliases neither the
        // container storage nor whatever the indexed expression borrowed to reach it. Run
        // this BEFORE propagating the indexed expression's borrow. A REFERENCE-typed result
        // is kept as an alias and preserves the borrow.
        if (isDirectBorrowCarrier(sema, resultTypeRef))
        {
            const TypeRef unwrappedResult = unwrapAliasEnum(sema, resultTypeRef);
            const bool    resultIsRef     = unwrappedResult.isValid() && sema.typeMgr().get(unwrappedResult).isReference();
            if (!resultIsRef)
            {
                const TypeRef elemTypeRef = indexedElementTypeRef(sema, indexedRef);
                if (elemTypeRef.isValid())
                {
                    // A builtin array or slice: the element VALUE read ('result == element')
                    // copies; a differently typed carrier result is a sub-slice that aliases
                    // the elements and keeps the borrow.
                    if (unwrapAliasEnum(sema, elemTypeRef) == unwrappedResult)
                        return {};
                }
                else
                {
                    // A struct container reached through 'opIndex': a non-reference carrier
                    // result is the element loaded out by value.
                    return {};
                }
            }
        }

        SemaEscapeInfo info = expressionEscapeInfoRec(sema, indexedRef, budget);
        if (info.hasBorrow())
        {
            info.typeRef = resultTypeRef;
            return info;
        }

        if (!isDirectBorrowCarrier(sema, resultTypeRef))
            return {};

        if (!isArrayStorageExpr(sema, indexedRef))
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
            const AstNode& node     = sema.node(resolvedRef);
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

    void normalizeProjectionRoot(Sema& sema, SemaEscapeProjection& projection)
    {
        if (!projection.root)
            return;

        if (const SymbolVariable* parameter = signatureParameterFor(sema, *projection.root))
            projection.root = parameter;
    }

    const SymbolVariable* firstProjectionField(const SemaEscapeProjection& projection)
    {
        for (const SemaEscapeProjectionComponent& component : projection.components)
        {
            if (component.kind == SemaEscapeProjectionKind::Field)
                return component.field;
        }
        return nullptr;
    }

    AstNodeRef syntacticMethodReceiverRef(Sema& sema, AstNodeRef callRef);

    const SymbolVariable* callerArgumentProjectionField(Sema& sema, AstNodeRef callRef, const SymbolFunction& callee, size_t paramIndex, AstNodeRef argRef)
    {
        AstNodeRef projectedRef = AstNodeRef::invalid();
        if (paramIndex == 0 && callee.isMethod())
            projectedRef = syntacticMethodReceiverRef(sema, callRef);
        if (projectedRef.isInvalid())
            projectedRef = argumentValueRef(sema, argRef);

        SemaEscapeProjection projection;
        if (!storageProjection(sema, projectedRef, projection))
            return nullptr;
        normalizeProjectionRoot(sema, projection);
        return firstProjectionField(projection);
    }

    bool projectionComponentsMatch(const SemaEscapeProjectionComponent& left, const SemaEscapeProjectionComponent& right)
    {
        if (left.kind == SemaEscapeProjectionKind::AnyIndex || right.kind == SemaEscapeProjectionKind::AnyIndex)
            return left.kind != SemaEscapeProjectionKind::Field && right.kind != SemaEscapeProjectionKind::Field;
        return left == right;
    }

    bool projectionIsPrefixOf(const SemaEscapeProjection& prefix, const SemaEscapeProjection& value)
    {
        if (!prefix.root || prefix.root != value.root || prefix.components.size() > value.components.size())
            return false;

        for (size_t i = 0; i < prefix.components.size(); ++i)
        {
            if (!projectionComponentsMatch(prefix.components[i], value.components[i]))
                return false;
        }
        return true;
    }

    bool ownedPayloadProjection(Sema& sema, const SemaEscapeInfo& info, SemaEscapeProjection& outProjection)
    {
        if (!info.viaOwnedPayload || info.sourceRef.isInvalid() || !storageProjection(sema, info.sourceRef, outProjection))
            return false;

        normalizeProjectionRoot(sema, outProjection);
        return outProjection.root != nullptr && !outProjection.components.empty();
    }

    // Replacing an owning field disconnects views of its OLD payload from the owner.
    // The view remains usable until that old allocation is explicitly released; a later
    // growth of the owner's NEW payload cannot invalidate it. This is the compiler-
    // inferred version boundary used by collection copy hooks (`old = .buffer;
    // .buffer = null; .realloc(...); copy(old, ...)`).
    void detachReplacedOwnedPayloadViews(Sema& sema, const SemaEscapeProjection& rawProjection, TypeRef targetTypeRef)
    {
        if (!isOwnedPayloadCarrier(sema, targetTypeRef) && !hasOwningLifecycle(sema, targetTypeRef))
            return;

        SemaEscapeProjection replaced = rawProjection;
        normalizeProjectionRoot(sema, replaced);
        if (!replaced.root || replaced.components.empty())
            return;

        SmallVector<const SymbolVariable*> detachedViews;
        for (const auto& [viewVar, info] : sema.variableEscapeInfos())
        {
            if (!viewVar || !info.viaOwnedPayload)
                continue;

            SemaEscapeProjection source;
            if (!ownedPayloadProjection(sema, info, source))
                continue;
            if (projectionIsPrefixOf(replaced, source))
                detachedViews.push_back(viewVar);
        }

        for (const SymbolVariable* viewVar : detachedViews)
            sema.detachVariableOwnedPayload(*viewVar);
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
            if (!(origins & (1ULL << i)))
                continue;
            fn.addReturnBorrowsParam(i);

            // A result read OUT of what the parameter owns is a view the parameter's own
            // reallocation moves. A result that merely reaches the parameter - a fresh
            // object holding a back-reference to it - is not, and only this flag can tell
            // the invalidation check which of the two it is looking at.
            if (info.viaOwnedPayload)
                fn.addReturnsPayloadParam(i);
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
            check.borrowedVar = info.sourceVar;
            return;
        }

        check.diagId = info.isTemporaryBorrow() ? DiagnosticId::sanity_err_borrow_temporary : DiagnosticId::sanity_err_borrow_materialized;
        if (info.sourceRef.isValid())
        {
            check.noteId    = DiagnosticId::sema_note_borrow_temporary_here;
            check.noteRange = sema.node(info.sourceRef).codeRange(sema.ctx());
        }
    }

    // Does the container argument of a stores-into-parameter pair provably outlive the
    // borrowed one? A callee that keeps its argument is only a fault at sites where the
    // keeper is still readable after the borrowed storage is gone.
    //
    // A global container outlives every frame value, so any frame borrow handed to it
    // dangles. Two locals of the same scope die together in reverse declaration order and
    // nothing can observe the container afterwards: only a STRICTLY deeper source (a loop
    // body, an inner block) leaves the container holding freed storage while it is still
    // in use - which is exactly the 'set of views filled from a per-iteration owner'
    // fault.
    //
    // A container reached through one of THIS function's parameters is deliberately NOT
    // judged here. It does outlive the frame, but "an object holds a pointer to a caller
    // buffer for the duration of one operation" is an ordinary design (a codec keeping
    // its input and output spans in its state), and the pair still propagates to this
    // function's own summary, to be judged where the container's real lifetime is known.
    bool intoArgumentOutlivesStored(const Sema& sema, const SemaEscapeInfo& intoInfo, const SemaEscapeInfo& storedInfo)
    {
        if (intoInfo.kind == SemaEscapeKind::Static)
            return true;

        if (!intoInfo.isLocalBorrow())
            return false;

        // Feeding a container from its own storage is not an escape.
        if (storedInfo.sourceVar == intoInfo.sourceVar)
            return false;

        const uint32_t intoDepth = sema.variableScopeDepth(*intoInfo.sourceVar);
        if (!intoDepth)
            return false;

        // A temporary dies with the statement that built it; the named container is
        // still there on the next one.
        if (storedInfo.isTemporaryBorrow())
            return true;

        // Inline expansions open their own scopes: their depths do not compare with the
        // enclosing function's.
        if (SemaHelpers::effectiveInlinePayload(sema))
            return false;

        const uint32_t storedDepth = storedInfo.isMaterializedBorrow() ? storedInfo.sourceScopeDepth : (storedInfo.sourceVar ? sema.variableScopeDepth(*storedInfo.sourceVar) : 0);
        return storedDepth && storedDepth > intoDepth;
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
            else if (node.is(AstNodeId::CastExpr))
            {
                // A cast (e.g. the implicit widening to a #null destination) preserves
                // borrow provenance: look through it to reach the call.
                const AstNodeRef operandRef = node.cast<AstCastExpr>().nodeExprRef;
                if (castOperandSelfSubstituted(sema, resolvedRef, operandRef))
                    resolvedRef = operandRef;
                else
                    resolvedRef = sema.viewZero(operandRef).nodeRef();
            }
            else if (node.is(AstNodeId::AutoCastExpr))
                resolvedRef = sema.viewZero(node.cast<AstAutoCastExpr>().nodeExprRef).nodeRef();
            else if (node.is(AstNodeId::AsCastExpr))
                resolvedRef = sema.viewZero(node.cast<AstAsCastExpr>().nodeExprRef).nodeRef();
            else
                break;
        }

        if (resolvedRef.isInvalid() || !sema.node(resolvedRef).is(AstNodeId::CallExpr))
            return false;

        const auto&           call = sema.node(resolvedRef).cast<AstCallExpr>();
        const SymbolFunction* fn   = resolvedCallFunction(sema, resolvedRef, call.nodeExprRef);
        if (!fn)
            return false;

        // Whether an expansion happened is not a question for the attributes: a call that
        // was expanded no longer resolves to a CallExpr at all, and the walk above would
        // have stopped. Reading '#[Inline]' instead made the verdict depend on whether the
        // build configuration inlines - and an imported '#[Inline]' accessor is never
        // expanded anyway, because its body does not cross the module boundary (the
        // generated API declares it '#[Swag.Foreign]' and keeps the attribute). Both
        // mistakes dropped 'String.toString' and its kind out of the analysis.
        //
        // A macro or a mixin is a different matter: it is expanded from source before this
        // point, and its parameters are code rather than values, so there is no summary to
        // pair them against.
        if (fn->attributes().hasRtFlag(RtAttributeFlagsE::Macro) || fn->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
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
        SmallVector<std::pair<uint32_t, uint32_t>>       parameterMappings;

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

            // A parameter that cannot carry a borrow can neither return nor store one -
            // with one exception. 'typeCanCarryBorrow' refuses to SCAN the fields of an
            // owner, because a bitwise walk of them would confuse ownership with
            // borrowing; that says nothing about the owner being unable to LEND what it
            // holds, which is exactly what an accessor taking it by value hands back.
            // Without this, the pointer spelling of a call errors and the by-value one
            // right next to it is silent.
            const bool paramIsByValueOwner = paramTypeRef.isValid() && typeHasBorrowableStorage(sema, paramTypeRef) && hasOwningLifecycle(sema, paramTypeRef);
            if (paramTypeRef.isValid() && !typeCanCarryBorrowImpl(sema, paramTypeRef) && !paramIsByValueOwner)
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
            // Releasing a payload READ OUT of a parameter ('me.buffer') frees what that
            // object owns, not the pointer the caller handed over: it is the whole point
            // of a 'clear' or a destructor, and must not mark the object itself freed.
            if (calleeIsAllocFree && collectPairs)
            {
                const AstNodeRef      reqValueRef = argumentValueRef(sema, arg.argRef);
                bool                  reqWhole    = false;
                const SymbolVariable* reqVar      = reqValueRef.isValid() ? storageRootVariable(sema, reqValueRef, false, reqWhole) : nullptr;
                const SemaEscapeInfo  carried     = reqVar ? sema.variableEscapeInfoIncludingProjections(*reqVar) : SemaEscapeInfo{};
                if (carried.viaOwnedPayload)
                {
                    // The owner is releasing its own payload: not a free of the pointer
                    // the caller handed over, but every view INTO that payload dies here.
                    // This is what tells 'append', 'reserve' and 'clear' apart from a
                    // method that only reads or assigns fields.
                    if (carried.kind == SemaEscapeKind::Parameter)
                    {
                        if (SymbolFunction* callerFn = sema.currentFunction())
                        {
                            SemaEscapeProjection  carriedProjection;
                            const SymbolVariable* reallocatedField = ownedPayloadProjection(sema, carried, carriedProjection) ? firstProjectionField(carriedProjection) : nullptr;
                            const uint64_t        origins          = parameterOriginsMask(*callerFn, carried);
                            for (size_t i = 0; i < 64; ++i)
                            {
                                if (origins & (1ULL << i))
                                {
                                    if (reallocatedField)
                                        callerFn->addReallocatesParamField(i, *reallocatedField);
                                    else
                                        callerFn->addReallocatesParam(i);
                                }
                            }
                        }
                    }
                }
                else if (carried.kind == SemaEscapeKind::Parameter)
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
                    check.diagId    = DiagnosticId::sanity_err_free_borrowed;
                    check.siteRange = sema.node(arg.argRef).codeRangeWithChildren(sema.ctx(), sema.ast());
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
                    edge.caller                = callerFn;
                    edge.callee                = fn;
                    edge.callerParamIndex      = static_cast<uint32_t>(callerParamIndex);
                    edge.calleeParamIndex      = static_cast<uint32_t>(thisParam);
                    edge.viaOwnedPayload       = info.viaOwnedPayload;
                    edge.viaStoredField        = info.viaStoredField;
                    edge.callerProjectionField = callerArgumentProjectionField(sema, resolvedRef, *fn, thisParam, arg.argRef);
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
                        check.callee     = fn;
                        check.paramIndex = static_cast<uint32_t>(thisParam);
                        outCapture.checks.push_back(std::move(check));
                    }
                }

                continue;
            }

            // A GLOBAL argument makes nothing escape: it outlives every frame, which is
            // why the escape rules ignore it. The ROUTE still has to be recorded, because
            // invalidation is a different fault - a result read out of what the global
            // owns goes stale when that payload moves - and the check has no other way to
            // learn that this call result came from this global. Never judged
            // (commitDeferredCallBorrows drops it), so it costs no diagnostic.
            if (info.kind == SemaEscapeKind::Static && info.sourceVar)
            {
                SemaEscapeDeferredCheck check;
                check.callee       = fn;
                check.paramIndex   = static_cast<uint32_t>(thisParam);
                check.borrowedVar  = info.sourceVar;
                check.staticSource = true;
                outCapture.checks.push_back(std::move(check));
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

        // Cross-argument pairs: 'container.add(&local)' escapes when the callee stores
        // the borrowed argument into storage reachable from the container argument AND
        // that container outlives what was borrowed (see 'intoArgumentOutlivesStored').
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
                if (intoParam >= 8)
                    continue;

                for (const auto& [storedParam, storedInfo] : argBorrows)
                {
                    if (storedParam == intoParam || storedParam >= 8)
                        continue;
                    if (!storedInfo.isLocalBorrow() && !storedInfo.isTemporaryBorrow() && !storedInfo.isMaterializedBorrow())
                        continue;
                    if (!intoArgumentOutlivesStored(sema, intoInfo, storedInfo))
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
        const SourceCodeRange siteRange = sema.node(atNodeRef).codeRangeWithChildren(sema.ctx(), sema.ast());

        for (const SemaEscapeDeferredCheck& checkTemplate : capture.checks)
        {
            // A route back to a global is not an escape route: it is only ever read by
            // the invalidation check, straight off the snapshot.
            if (checkTemplate.staticSource)
                continue;

            SemaEscapeDeferredCheck check = checkTemplate;
            check.judgeStores             = judgeStores;
            check.what                    = what;
            check.fileRef                 = fileRef;
            if (!check.siteRange.srcView)
                check.siteRange = siteRange;
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

    // The variable an assignment destination is ultimately reached through, ignoring what
    // the storage walk can prove about provenance: the innermost identifier of a
    // member/index/dereference chain. 'table[i].key' gives 'table'.
    const SymbolVariable* destinationBaseVariable(Sema& sema, AstNodeRef nodeRef, uint32_t depth = 0)
    {
        if (nodeRef.isInvalid() || depth > K_STORAGE_WALK_BUDGET)
            return nullptr;

        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isInvalid())
            return nullptr;

        const AstNode& node = sema.node(resolvedRef);
        switch (node.id())
        {
            case AstNodeId::Identifier:
                return identifierVariable(sema, resolvedRef);
            case AstNodeId::ParenExpr:
                return destinationBaseVariable(sema, node.cast<AstParenExpr>().nodeExprRef, depth + 1);
            case AstNodeId::InitializerExpr:
                return destinationBaseVariable(sema, node.cast<AstInitializerExpr>().nodeExprRef, depth + 1);
            case AstNodeId::AutoCastExpr:
                return destinationBaseVariable(sema, node.cast<AstAutoCastExpr>().nodeExprRef, depth + 1);
            case AstNodeId::AsCastExpr:
                return destinationBaseVariable(sema, node.cast<AstAsCastExpr>().nodeExprRef, depth + 1);
            case AstNodeId::ErrorManagementExpr:
                return destinationBaseVariable(sema, node.cast<AstErrorManagementExpr>().nodeExprRef, depth + 1);
            case AstNodeId::CastExpr:
            {
                const AstNodeRef operandRef = node.cast<AstCastExpr>().nodeExprRef;
                if (castOperandSelfSubstituted(sema, resolvedRef, operandRef))
                    return nullptr;
                return destinationBaseVariable(sema, operandRef, depth + 1);
            }
            case AstNodeId::MemberAccessExpr:
                return destinationBaseVariable(sema, node.cast<AstMemberAccessExpr>().nodeLeftRef, depth + 1);
            case AstNodeId::IndexExpr:
                return destinationBaseVariable(sema, node.cast<AstIndexExpr>().nodeExprRef, depth + 1);
            case AstNodeId::IndexListExpr:
                return destinationBaseVariable(sema, node.cast<AstIndexListExpr>().nodeExprRef, depth + 1);
            case AstNodeId::UnaryExpr:
                if (Token::isDeref(sema.token(node.codeRef()).id))
                    return destinationBaseVariable(sema, node.cast<AstUnaryExpr>().nodeExprRef, depth + 1);
                return nullptr;
            default:
                return nullptr;
        }
    }

    // A parameter borrow stored through a local that an ACCESSOR call handed back
    // ('let table = .tablePtr(); table[i].key = key'). The store reaches the accessor's
    // receiver exactly when the accessor returns a borrow of it - a fact only the final
    // return summary holds, so record an edge for the fixpoint instead of deciding here.
    void recordAccessorStoreIntoParamPair(Sema& sema, AstNodeRef leftRef, const SemaEscapeInfo& info)
    {
        const SymbolFunction* currentFn = sema.currentFunction();
        if (!currentFn)
            return;

        const SymbolVariable* baseVar = destinationBaseVariable(sema, leftRef);
        if (!baseVar)
            return;

        const SemaEscapeInfo* baseInfo = sema.variableEscapeInfo(*baseVar);
        if (!baseInfo || !baseInfo->isDeferredCallBorrow())
            return;

        const uint64_t origins = parameterOriginsMask(*currentFn, info);
        if (!origins)
            return;

        for (const auto& snapshot : baseInfo->deferredCalls)
        {
            if (!snapshot)
                continue;

            for (const SemaEscapeSummaryEdge& protoEdge : snapshot->edges)
            {
                if (protoEdge.caller != currentFn || !protoEdge.callee)
                    continue;
                if (protoEdge.callerParamIndex >= 8)
                    continue;

                for (size_t storedIndex = 0; storedIndex < 8; ++storedIndex)
                {
                    if (!(origins & (1ULL << storedIndex)) || storedIndex == protoEdge.callerParamIndex)
                        continue;

                    SemaEscapeSummaryEdge edge = protoEdge;
                    edge.kind                  = SemaEscapeSummaryEdgeKind::ReturnToPair;
                    edge.callerIntoParamIndex  = protoEdge.callerParamIndex;
                    edge.callerParamIndex      = static_cast<uint32_t>(storedIndex);
                    sema.ctx().compiler().addEscapeSummaryEdge(edge);
                }
            }
        }
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

            // An inline expansion substitutes the call with its root block; the
            // expansion's value flows out of its return statements, so the walk reads
            // through them to reach the borrow the callee's body hands back.
            case AstNodeId::ReturnStmt:
                return expressionEscapeInfoRec(sema, node.cast<AstReturnStmt>().nodeExprRef, budget);

            case AstNodeId::MemberAccessExpr:
            {
                SemaEscapeProjection projection;
                if (storageProjection(sema, resolvedRef, projection))
                {
                    SemaEscapeInfo projectedInfo = sema.projectionEscapeInfoIncludingWildcards(projection);
                    if (projectedInfo.hasBorrow())
                        return projectedInfo;
                }

                // A payload carrier read out of a value with an owning lifecycle
                // ('set.table', 'string.buffer') addresses memory that value releases
                // when it dies: the read borrows the owner, whatever the left side of
                // the access borrowed to reach it.
                if (const SymbolVariable* ownedRoot = ownedPayloadStorageRootAt(sema, resolvedRef, false, 0))
                {
                    // A method body has TWO 'me' symbols and the one the body reads
                    // carries no Parameter flag, so it matches nothing in the signature:
                    // map it to the receiver, or the borrow names an origin the summary
                    // cannot express and the whole edge is dropped.
                    const SymbolVariable* sigParam = signatureParameterFor(sema, *ownedRoot);
                    const SymbolVariable& ownerVar = sigParam ? *sigParam : *ownedRoot;

                    const TypeRef  memberTypeRef = expressionTypeRef(sema, resolvedRef);
                    SemaEscapeInfo ownedInfo     = variableStorageInfo(sema, ownerVar, resolvedRef, memberTypeRef);
                    if (ownedInfo.hasBorrow())
                    {
                        // A by-value parameter is neither copied nor dropped by the
                        // callee: only its SLOT is frame storage. What it owns stays the
                        // caller's, so the payload is a caller borrow feeding the summary,
                        // not a frame borrow.
                        if (ownedInfo.kind == SemaEscapeKind::Local && ownerVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
                            ownedInfo.kind = SemaEscapeKind::Parameter;
                        if (ownedInfo.kind == SemaEscapeKind::Parameter)
                            setParameterOrigin(sema, ownedInfo, ownerVar);

                        ownedInfo.typeRef         = memberTypeRef;
                        ownedInfo.viaOwnedPayload = true;
                        return ownedInfo;
                    }
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

    bool callerBorrowHandledByInlineSummary(Sema& sema, const SymbolVariable& sourceVar)
    {
        const SemaInlinePayload* inlinePayload = SemaHelpers::effectiveInlinePayload(sema);
        if (!inlinePayload)
            return false;

        for (const SemaInlinePayload* payload = inlinePayload; payload; payload = payload->parentInlinePayload)
        {
            const SymbolFunction* sourceFunction = payload->sourceFunction;
            if (!sourceFunction ||
                sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Macro) ||
                sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Mixin) ||
                sourceVar.isFunctionLocalVariable(*sourceFunction) ||
                sourceFunction->containsLocalVariable(sourceVar))
                return false;
        }

        return true;
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
        if (callerBorrowHandledByInlineSummary(sema, *info.sourceVar))
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
        if (callerBorrowHandledByInlineSummary(sema, *info.sourceVar))
            return Result::Continue;

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

            const AstNodeRef        childValueRef = argumentValueRef(sema, childRef);
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
    void iterationProjectionAt(Sema& sema, AstNodeRef resolvedRef, SemaEscapeProjection& out, bool& ok, uint32_t depth);

    void iterationProjection(Sema& sema, AstNodeRef nodeRef, SemaEscapeProjection& out, bool& ok, uint32_t depth = 0)
    {
        ok = false;
        if (nodeRef.isInvalid() || depth > K_STORAGE_WALK_BUDGET)
            return;
        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isInvalid())
            return;
        iterationProjectionAt(sema, resolvedRef, out, ok, depth + 1);
    }

    void iterationProjectionAt(Sema& sema, AstNodeRef resolvedRef, SemaEscapeProjection& out, bool& ok, uint32_t depth)
    {
        const AstNode& node = sema.node(resolvedRef);
        switch (node.id())
        {
            case AstNodeId::Identifier:
                out.root = identifierVariable(sema, resolvedRef);
                ok       = out.root != nullptr;
                return;

            case AstNodeId::ParenExpr:
                iterationProjection(sema, node.cast<AstParenExpr>().nodeExprRef, out, ok, depth + 1);
                return;
            case AstNodeId::InitializerExpr:
                iterationProjection(sema, node.cast<AstInitializerExpr>().nodeExprRef, out, ok, depth + 1);
                return;
            case AstNodeId::AutoCastExpr:
                iterationProjection(sema, node.cast<AstAutoCastExpr>().nodeExprRef, out, ok, depth + 1);
                return;
            case AstNodeId::AsCastExpr:
                iterationProjection(sema, node.cast<AstAsCastExpr>().nodeExprRef, out, ok, depth + 1);
                return;

            case AstNodeId::CastExpr:
            {
                const AstNodeRef operandRef = node.cast<AstCastExpr>().nodeExprRef;
                if (castOperandSelfSubstituted(sema, resolvedRef, operandRef))
                    iterationProjectionAt(sema, operandRef, out, ok, depth + 1);
                else
                    iterationProjection(sema, operandRef, out, ok, depth + 1);
                return;
            }

            case AstNodeId::MemberAccessExpr:
            {
                iterationProjection(sema, node.cast<AstMemberAccessExpr>().nodeLeftRef, out, ok, depth + 1);
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
                iterationProjection(sema, index.nodeExprRef, out, ok, depth + 1);
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
    // The declaration of the function being analyzed, so a check can look at what comes
    // AFTER the node it fired on. The whole declaration is the scan root rather than the
    // body alone: a '#test' block, an init/drop block and a plain function are all
    // different node kinds, and nothing before a body mentions its locals.
    AstNodeRef currentFunctionDeclRef(Sema& sema)
    {
        const SymbolFunction* fn = sema.currentFunction();
        return fn ? fn->declNodeRef() : AstNodeRef::invalid();
    }

    // The smallest complete body around the node being judged. An inline expansion is
    // materialized below the caller's function declaration, so scanning that declaration
    // depends on how much of its substituted tree happens to exist already. Its inline root
    // is complete by construction. A local function encountered before that root still owns
    // its own lifetime boundary and must win, or a restore/read in its enclosing expansion
    // could hide a fault in the nested function.
    AstNodeRef currentAnalysisBodyRef(Sema& sema)
    {
        const AstNodeRef currentDeclRef = currentFunctionDeclRef(sema);
        const auto*      inlinePayload  = SemaHelpers::effectiveInlinePayload(sema);
        if (!inlinePayload || inlinePayload->inlineRootRef.isInvalid())
            return currentDeclRef;

        for (uint32_t up = 0;; up++)
        {
            const AstNodeRef parentRef = sema.visit().parentNodeRef(up);
            if (parentRef.isInvalid())
                break;
            if (parentRef == currentDeclRef || parentRef == inlinePayload->inlineRootRef)
                return parentRef;
        }

        return inlinePayload->inlineRootRef;
    }

    // Does this call structurally change its receiver? Only a method can, a 'const' one
    // cannot, and the lifecycle hooks the compiler inserts on its own (copy, move, drop)
    // are not a change the program wrote. Every other non-const method is taken as one:
    // 'add', 'clear', 'reserve', 'opSet' and friends can all move or free the storage.
    bool isStructuralMutationCallee(Sema& sema, const SymbolFunction& calledFn)
    {
        if (!calledFn.isMethod() || calledFn.isConst())
            return false;

        const Utf8             calleeName = calledFn.name(sema.ctx());
        const std::string_view view{calleeName};
        return view != "opPostCopy" && view != "opPostMove" && view != "opDrop" && view != "opVisit";
    }

    // Does this view point at the VARIABLE rather than into what the variable owns? An
    // interface object, a pointer or a reference to the value itself keeps addressing
    // the same frame slot however much its payload is reallocated - it is the handle
    // through which the change is made, not something the change invalidates. A view of
    // a different type ('string' of a 'String', '*u8' into an array's buffer) points
    // into the payload, and that is what moves.
    bool viewAliasesVariableItself(Sema& sema, const SymbolVariable& viewVar, const SymbolVariable& sourceVar)
    {
        const TypeRef viewTypeRef = unwrapAliasEnum(sema, viewVar.typeRef());
        if (!viewTypeRef.isValid())
            return false;

        const TypeInfo& viewType = sema.typeMgr().get(viewTypeRef);
        if (viewType.isInterface() || viewType.isAny())
            return true;

        if (!viewType.isAnyPointer() && !viewType.isReference())
            return false;

        const TypeRef pointeeTypeRef = unwrapAliasEnum(sema, viewType.payloadTypeRef());
        const TypeRef sourceTypeRef  = unwrapAliasEnum(sema, sourceVar.typeRef());
        return pointeeTypeRef.isValid() && pointeeTypeRef == sourceTypeRef;
    }

    // Whose payload this body can judge a structural change of. Locals and globals are
    // direct. A parameter is also judgeable for views created INSIDE this body: their
    // precise owned-field projection is known here, so caller ownership is irrelevant.
    // Views held only by the caller are absent from the flow state and cannot be invented.
    bool isInvalidationJudgeableOwner(Sema& sema, const SymbolVariable& symVar)
    {
        return isLocalVariableStorage(sema, symVar) ||
               symVar.hasExtraFlag(SymbolVariableFlagsE::GlobalStorage) ||
               symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter);
    }

    // The storage a method call may change: its normalized signature root plus the
    // syntactic receiver path. Keeping the path is what distinguishes `.left.reserve()`
    // from `.right.reserve()` inside one receiver.
    bool mutatedReceiverProjection(Sema& sema, AstNodeRef callRef, SemaEscapeProjection& outProjection)
    {
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

        AstNodeRef projectedRef = syntacticMethodReceiverRef(sema, callRef);
        if (projectedRef.isInvalid())
            projectedRef = receiverRef;
        if (projectedRef.isInvalid())
            return false;

        if (!storageProjection(sema, projectedRef, outProjection))
        {
            bool whole         = false;
            outProjection.root = storageRootVariable(sema, projectedRef, false, whole);
            outProjection.components.clear();
        }

        normalizeProjectionRoot(sema, outProjection);
        return outProjection.root != nullptr;
    }

    bool isLoopStatement(const AstNode& node)
    {
        return node.is(AstNodeId::WhileStmt) ||
               node.is(AstNodeId::ForStmt) ||
               node.is(AstNodeId::ForCStyleStmt) ||
               node.is(AstNodeId::ForeachStmt) ||
               node.is(AstNodeId::InfiniteLoopStmt);
    }

    // Which alternative of one branch statement holds this position. Arms exclude each
    // other by construction, so at most one can contain it.
    size_t armContaining(std::span<const SourceCodeRange> arms, const SourceCodeRange& site)
    {
        for (size_t i = 0; i < arms.size(); ++i)
        {
            if (arms[i].srcView == site.srcView && site.offset >= arms[i].offset && site.offset < arms[i].offset + arms[i].len)
                return i;
        }

        return arms.size();
    }

    // The whole source extent of a subtree. 'codeRangeWithChildren' cannot answer this:
    // it never leaves the node's own line, because it exists to underline one expression
    // in a diagnostic. Where a block ENDS is a different question, and the only source of
    // truth for it is the furthest token any descendant carries.
    SourceCodeRange subtreeRange(Sema& sema, AstNodeRef nodeRef)
    {
        SourceCodeRange result = sema.node(nodeRef).codeRange(sema.ctx());
        if (!result.srcView)
            return result;

        uint32_t first = result.offset;
        uint32_t last  = result.offset + result.len;

        SmallVector<AstNodeRef> worklist;
        SmallVector<AstNodeRef> children;
        worklist.push_back(nodeRef);

        uint32_t budget = 8192;
        while (!worklist.empty() && budget != 0)
        {
            budget--;
            const AstNodeRef currentRef = worklist.back();
            worklist.pop_back();
            if (currentRef.isInvalid())
                continue;

            const AstNode&        node  = sema.node(currentRef);
            const SourceCodeRange range = node.codeRange(sema.ctx());
            if (range.srcView == result.srcView)
            {
                first = std::min(first, range.offset);
                last  = std::max(last, range.offset + range.len);
            }

            children.clear();
            node.collectChildrenFromAst(children, sema.ast());
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isValid())
                    worklist.push_back(childRef);
            }
        }

        result.offset = first;
        result.len    = last > first ? last - first : result.len;
        return result;
    }

    bool sourceRangeContains(const SourceCodeRange& outer, const SourceCodeRange& inner)
    {
        return outer.srcView == inner.srcView &&
               inner.offset >= outer.offset &&
               inner.offset + inner.len <= outer.offset + outer.len;
    }

    struct BackEdgeLoop
    {
        AstNodeRef      nodeRef;
        SourceCodeRange range;
    };

    void collectBackEdgeLoops(Sema& sema, AstNodeRef bodyRef, const SourceCodeRange& mutationRange, const SymbolVariable& viewVar, SmallVector<BackEdgeLoop>& outLoops)
    {
        outLoops.clear();
        const SourceCodeRange declarationRange = viewVar.codeRange(sema.ctx());

        SmallVector<AstNodeRef> worklist;
        SmallVector<AstNodeRef> children;
        worklist.push_back(bodyRef);

        uint32_t budget = 8192;
        while (!worklist.empty() && budget != 0)
        {
            budget--;
            const AstNodeRef nodeRef = worklist.back();
            worklist.pop_back();
            if (nodeRef.isInvalid())
                continue;

            const AstNode& node = sema.node(nodeRef);
            if (isLoopStatement(node))
            {
                const SourceCodeRange range = subtreeRange(sema, nodeRef);
                if (sourceRangeContains(range, mutationRange) && !sourceRangeContains(range, declarationRange))
                    outLoops.push_back({nodeRef, range});
            }

            children.clear();
            node.collectChildrenFromAst(children, sema.ast());
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isValid())
                    worklist.push_back(childRef);
            }
        }

        // The innermost loop takes its back edge first.
        std::ranges::sort(outLoops, [](const BackEdgeLoop& a, const BackEdgeLoop& b) { return a.range.len < b.range.len; });
    }

    // Collects the alternatives of a branch statement: the two blocks of an 'if', the
    // cases of a 'switch'. The condition is NOT one of them - a position inside it runs
    // before every arm.
    void collectBranchArms(Sema& sema, AstNodeRef nodeRef, SmallVector<SourceCodeRange>& outArms)
    {
        outArms.clear();

        const AstNode& node   = sema.node(nodeRef);
        auto           addArm = [&](AstNodeRef armRef) {
            if (armRef.isValid())
                outArms.push_back(subtreeRange(sema, armRef));
        };

        if (node.is(AstNodeId::IfStmt))
        {
            const auto& stmt = node.cast<AstIfStmt>();
            addArm(stmt.nodeIfBlockRef);
            addArm(stmt.nodeElseBlockRef);
            return;
        }

        if (node.is(AstNodeId::IfVarDecl))
        {
            const auto& stmt = node.cast<AstIfVarDecl>();
            addArm(stmt.nodeIfBlockRef);
            addArm(stmt.nodeElseBlockRef);
            return;
        }

        if (node.is(AstNodeId::SwitchStmt))
        {
            SmallVector<AstNodeRef> children;
            node.collectChildrenFromAst(children, sema.ast());
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isValid() && sema.node(childRef).is(AstNodeId::SwitchCaseStmt))
                    addArm(childRef);
            }
        }
    }

    // Do these two positions sit on paths that exclude each other? The arms of one 'if'
    // and the cases of one 'switch' never both run, so a read standing in one of them is
    // not a read of storage the other one moved - however the source orders the two.
    //
    // A branch INSIDE a loop is deliberately not exempted: there, one iteration takes one
    // arm and the next takes the other, so the read really does follow the change.
    bool positionsExcludeEachOther(Sema& sema, AstNodeRef bodyRef, const SourceCodeRange& mutationRange, const SourceCodeRange& readRange)
    {
        struct Pending
        {
            AstNodeRef nodeRef;
            bool       insideLoop = false;
        };

        SmallVector<Pending> worklist;
        worklist.push_back({bodyRef, false});

        uint32_t                     budget = 8192;
        SmallVector<AstNodeRef>      children;
        SmallVector<SourceCodeRange> arms;
        while (!worklist.empty() && budget != 0)
        {
            budget--;
            const Pending pending = worklist.back();
            worklist.pop_back();
            if (pending.nodeRef.isInvalid())
                continue;

            const AstNode& node = sema.node(pending.nodeRef);
            if (!pending.insideLoop)
            {
                collectBranchArms(sema, pending.nodeRef, arms);
                if (arms.size() > 1)
                {
                    const size_t mutationArm = armContaining(arms.span(), mutationRange);
                    const size_t readArm     = armContaining(arms.span(), readRange);
                    if (mutationArm != arms.size() && readArm != arms.size() && mutationArm != readArm)
                        return true;
                }
            }

            const bool insideLoop = pending.insideLoop || isLoopStatement(node);
            children.clear();
            node.collectChildrenFromAst(children, sema.ast());
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isValid())
                    worklist.push_back({childRef, insideLoop});
            }
        }

        return false;
    }

    // A mutation inside one branch cannot reach code after that branch in the same
    // iteration when the arm unconditionally continues, returns or becomes unreachable.
    // Inspect only direct statements after the statement containing the
    // mutation: an exit nested in another conditional is not unconditional.
    bool mutationArmExitsBeforeRead(Sema& sema, AstNodeRef bodyRef, const SourceCodeRange& mutationRange, const SourceCodeRange& readRange, const SymbolVariable& viewVar)
    {
        SmallVector<AstNodeRef> worklist;
        worklist.push_back(bodyRef);

        uint32_t                     budget = 8192;
        SmallVector<AstNodeRef>      children;
        SmallVector<SourceCodeRange> arms;
        SourceCodeRange              innermostLoop;
        const SourceCodeRange        declarationRange = viewVar.codeRange(sema.ctx());
        while (!worklist.empty() && budget != 0)
        {
            budget--;
            const AstNodeRef nodeRef = worklist.back();
            worklist.pop_back();
            if (nodeRef.isInvalid())
                continue;

            const AstNode& node = sema.node(nodeRef);
            if (isLoopStatement(node))
            {
                const SourceCodeRange range = subtreeRange(sema, nodeRef);
                if (sourceRangeContains(range, mutationRange) && (!innermostLoop.srcView || range.len < innermostLoop.len))
                    innermostLoop = range;
            }

            children.clear();
            node.collectChildrenFromAst(children, sema.ast());
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isValid())
                    worklist.push_back(childRef);
            }
        }

        // An exit only makes the view safe when the targeted loop rebuilds that view.
        // Otherwise the same stale binding can be read on a later iteration.
        if (!innermostLoop.srcView || !sourceRangeContains(innermostLoop, declarationRange))
            return false;

        worklist.clear();
        worklist.push_back(bodyRef);
        budget = 8192;
        while (!worklist.empty() && budget != 0)
        {
            budget--;
            const AstNodeRef nodeRef = worklist.back();
            worklist.pop_back();
            if (nodeRef.isInvalid())
                continue;

            collectBranchArms(sema, nodeRef, arms);
            for (size_t armIndex = 0; armIndex < arms.size(); ++armIndex)
            {
                const SourceCodeRange& armRange = arms[armIndex];
                if (!sourceRangeContains(armRange, mutationRange) || sourceRangeContains(armRange, readRange))
                    continue;

                AstNodeRef              armRef = AstNodeRef::invalid();
                SmallVector<AstNodeRef> branchChildren;
                sema.node(nodeRef).collectChildrenFromAst(branchChildren, sema.ast());
                for (const AstNodeRef childRef : branchChildren)
                {
                    if (childRef.isValid() && sourceRangeContains(armRange, subtreeRange(sema, childRef)))
                    {
                        armRef = childRef;
                        break;
                    }
                }
                if (armRef.isInvalid())
                    continue;

                SmallVector<AstNodeRef> statements;
                sema.node(armRef).collectChildrenFromAst(statements, sema.ast());
                for (const AstNodeRef statementRef : statements)
                {
                    if (statementRef.isInvalid())
                        continue;
                    const SourceCodeRange statementRange = subtreeRange(sema, statementRef);
                    if (statementRange.srcView != mutationRange.srcView || statementRange.offset <= mutationRange.offset)
                        continue;

                    const AstNode& statement = sema.node(statementRef);
                    if (statement.is(AstNodeId::ContinueStmt) ||
                        statement.is(AstNodeId::ReturnStmt) ||
                        statement.is(AstNodeId::UnreachableStmt))
                        return true;
                }
            }

            children.clear();
            sema.node(nodeRef).collectChildrenFromAst(children, sema.ast());
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isValid())
                    worklist.push_back(childRef);
            }
        }

        return false;
    }

    // The first READ of 'symVar' written at or after 'afterOffset', or invalid when the
    // next thing that happens to it is a write - reassigning a view refreshes it, so what
    // follows reads the new one. 'afterRange' only names the file; the offset is separate
    // because the mutation's own arguments run before it and must not count.
    //
    // Source order stands in for execution order within each phase: first the rest of the
    // current iteration, then each enclosing loop's back edge from inner to outer. A view
    // declared inside a loop is rebuilt on each pass, and a loop exited after the mutation
    // takes no back edge. An occurrence standing in a sibling arm of the change is skipped
    // outright when no loop can join the paths on another iteration.
    bool mutationFollowedByLoopExit(Sema& sema, AstNodeRef bodyRef, AstNodeRef callRef);

    AstNodeRef firstReadAfter(Sema& sema, AstNodeRef bodyRef, AstNodeRef mutationRef, const SourceCodeRange& afterRange, uint32_t afterOffset, const SymbolVariable& symVar)
    {
        struct Occurrence
        {
            AstNodeRef      nodeRef;
            uint32_t        offset  = 0;
            bool            isWrite = false;
            uint32_t        phase   = 0;
            SourceCodeRange range;
        };

        SmallVector<BackEdgeLoop> backEdgeLoops;
        collectBackEdgeLoops(sema, bodyRef, afterRange, symVar, backEdgeLoops);

        SmallVector<Occurrence>                        found;
        SmallVector<std::pair<AstNodeRef, AstNodeRef>> worklist;
        worklist.push_back({bodyRef, AstNodeRef::invalid()});

        uint32_t                budget = 16384;
        SmallVector<AstNodeRef> children;
        while (!worklist.empty() && budget != 0)
        {
            budget--;
            const auto [nodeRef, parentRef] = worklist.back();
            worklist.pop_back();
            if (nodeRef.isInvalid())
                continue;

            const AstNode& node = sema.node(nodeRef);
            if (node.is(AstNodeId::Identifier) && identifierVariable(sema, nodeRef) == &symVar)
            {
                const SourceCodeRange range = node.codeRange(sema.ctx());
                if (range.srcView == afterRange.srcView)
                {
                    uint32_t phase     = 0;
                    bool     candidate = range.offset >= afterOffset;
                    if (range.offset < afterRange.offset)
                    {
                        for (uint32_t i = 0; i < backEdgeLoops.size32(); i++)
                        {
                            const BackEdgeLoop& loop = backEdgeLoops[i];
                            if (sourceRangeContains(loop.range, range) && !mutationFollowedByLoopExit(sema, loop.nodeRef, mutationRef))
                            {
                                phase     = i + 1;
                                candidate = true;
                                break;
                            }
                        }
                    }

                    // The destination of an assignment, or the name being declared, is
                    // where the view is refreshed rather than consumed.
                    bool isWrite = false;
                    if (candidate && parentRef.isValid())
                    {
                        const AstNode& parent = sema.node(parentRef);
                        if (parent.is(AstNodeId::AssignStmt))
                            isWrite = sema.viewZero(parent.cast<AstAssignStmt>().nodeLeftRef).nodeRef() == nodeRef;
                        else if (parent.is(AstNodeId::SingleVarDecl) || parent.is(AstNodeId::MultiVarDecl))
                            isWrite = true;
                    }

                    if (candidate)
                        found.push_back({nodeRef, range.offset, isWrite, phase, range});
                }
            }

            children.clear();
            node.collectChildrenFromAst(children, sema.ast());
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isValid())
                    worklist.push_back({childRef, nodeRef});
            }
        }

        if (found.empty())
            return AstNodeRef::invalid();

        std::ranges::sort(found, [](const Occurrence& a, const Occurrence& b) {
            if (a.phase != b.phase)
                return a.phase < b.phase;
            return a.offset < b.offset;
        });

        // An occurrence no path reaches from the change decides nothing - neither that the
        // view is read stale, nor that it was refreshed first.
        for (const Occurrence& occurrence : found)
        {
            if (positionsExcludeEachOther(sema, bodyRef, afterRange, occurrence.range))
                continue;
            if (occurrence.phase == 0 && mutationArmExitsBeforeRead(sema, bodyRef, afterRange, occurrence.range, symVar))
                continue;
            return occurrence.isWrite ? AstNodeRef::invalid() : occurrence.nodeRef;
        }

        return AstNodeRef::invalid();
    }

    // Is this local a view INTO what 'root' owns, and under what condition? A view taken
    // straight out of the storage ('let v = buf.data') is one unconditionally. A view
    // handed back by a call ('let v = buf.view()') is one exactly when that call's result
    // reads the payload of the argument 'root' was passed as - which only the callee's
    // final summary can say, so the condition travels as a guard instead of being decided
    // here. The guard asks the PAYLOAD question, not the weaker "may borrow" one: a
    // factory returning a fresh object that keeps a pointer to its receiver borrows it,
    // but reallocating the receiver's payload leaves that object perfectly valid.
    //
    // Reading the captured call snapshot is what makes the most common spelling of "take
    // a view into a container" a candidate at all: an accessor result is bound as a
    // DeferredCall, never as a plain local borrow.
    bool viewRoutesToStorage(Sema& sema, const SemaEscapeInfo& info, const SemaEscapeProjection& mutation, SmallVector4<SemaEscapeDeferredGuard>& outGuards)
    {
        SWC_ASSERT(mutation.root);
        const SymbolVariable& root = *mutation.root;

        // A local and a global owner are the same fault here: what moves is the payload,
        // and the view is stale from that moment whatever outlives what.
        if (info.kind == SemaEscapeKind::Local || info.kind == SemaEscapeKind::Static)
            return info.sourceVar == &root;

        // A method receiver/parameter is caller-owned, but a view created in this body
        // has a fully inferred path back into it. Match the mutation against that path;
        // this catches `view = .data; .reserve(); use(view)` without treating every field
        // of `me` as the same allocation. A carrier replacement clears viaOwnedPayload,
        // so an old-buffer copy no longer follows the receiver's new allocation.
        if (info.kind == SemaEscapeKind::Parameter)
        {
            if (info.sourceVar != &root || !info.viaOwnedPayload)
                return false;

            SemaEscapeProjection source;
            return ownedPayloadProjection(sema, info, source) && projectionIsPrefixOf(mutation, source);
        }

        if (!info.isDeferredCallBorrow())
            return false;

        for (const auto& snapshot : info.deferredCalls)
        {
            if (!snapshot)
                continue;

            for (const SemaEscapeDeferredCheck& check : snapshot->checks)
            {
                if (check.borrowedVar != &root || !check.callee)
                    continue;

                // Every call the result travelled through has to hand the view on. The
                // check already carries the guards of the calls before it; this one adds
                // the call that produced the value.
                outGuards.clear();
                for (const SemaEscapeDeferredGuard& guard : check.guards)
                    outGuards.push_back({guard.callee, guard.paramIndex, true});
                outGuards.push_back({check.callee, check.paramIndex, true});
                return true;
            }
        }

        return false;
    }

    // Would this '@setcontext' argument install storage belonging to THIS frame? The
    // intrinsic takes a pointer, so the answer is decided by the spelling. A context VALUE
    // is handed over by an implicit address-of, which makes the frame slot the installed
    // address. A POINTER hands over what it already points at, and the pointer local
    // 'let prev = @getcontext()' points at storage the runtime owns - rooting the
    // judgement at the variable instead of at what it addresses would report the restore
    // in every scoped use.
    bool setContextInstallsFrameStorage(Sema& sema, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return false;

        bool                  whole = false;
        const SymbolVariable* root  = storageRootVariable(sema, argRef, false, whole);
        if (!root || !isLocalVariableStorage(sema, *root))
            return false;

        const TypeRef rootTypeRef = unwrapAliasEnum(sema, root->typeRef());
        if (!rootTypeRef.isValid())
            return false;

        const TypeInfo& rootType = sema.typeMgr().get(rootTypeRef);
        return !rootType.isAnyPointer() && !rootType.isReference();
    }

    AstNodeRef intrinsicFirstArgument(Sema& sema, AstNodeRef intrinsicRef)
    {
        SmallVector<AstNodeRef> children;
        sema.node(intrinsicRef).collectChildrenFromAst(children, sema.ast());
        return children.empty() ? AstNodeRef::invalid() : children.front();
    }

    // Does this body put another context back? The scoped idiom spells that as a 'defer'
    // ('Core.withAllocator' is built on exactly that) and the compiler suites spell it as
    // a plain call at the end of the block; both restore something that outlives the
    // frame, and both are correct.
    //
    // The test is deliberately structural rather than a proof that the RIGHT context is
    // restored on every path. What is left to report is the shape that has no answer at
    // all: a body that installs its own stack and then walks away from it. Insisting on
    // more would reject every correct spelling that exists today, and a check that rejects
    // the standard idiom is a check that gets turned off.
    bool functionRestoresContext(Sema& sema, AstNodeRef declRef, AstNodeRef exceptRef)
    {
        if (declRef.isInvalid())
            return false;

        SmallVector<AstNodeRef> worklist;
        worklist.push_back(declRef);

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
            if (nodeRef != exceptRef &&
                node.is(AstNodeId::IntrinsicCallExpr) &&
                sema.token(node.codeRef()).id == TokenId::IntrinsicSetContext &&
                !setContextInstallsFrameStorage(sema, intrinsicFirstArgument(sema, nodeRef)))
                return true;

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

    bool mutationFollowedByLoopExit(Sema& sema, AstNodeRef bodyRef, AstNodeRef callRef)
    {
        if (bodyRef.isInvalid() || callRef.isInvalid())
            return false;

        const SourceCodeRange callRange = sema.node(callRef).codeRange(sema.ctx());
        if (!callRange.srcView)
            return false;

        struct Pending
        {
            AstNodeRef nodeRef;
            bool       insideNestedBreakable = false;
        };

        SmallVector<Pending> worklist;
        worklist.push_back({bodyRef, false});

        uint32_t                budget = 8192;
        SmallVector<AstNodeRef> children;
        while (!worklist.empty() && budget != 0)
        {
            budget--;
            const Pending pending = worklist.back();
            worklist.pop_back();
            const AstNodeRef nodeRef = pending.nodeRef;
            if (nodeRef.isInvalid())
                continue;

            const AstNode& node          = sema.node(nodeRef);
            const bool     exitsFunction = node.is(AstNodeId::ReturnStmt) || node.is(AstNodeId::UnreachableStmt);
            const bool     exitsThisLoop = node.is(AstNodeId::BreakStmt) && !pending.insideNestedBreakable;
            if (exitsFunction || exitsThisLoop)
            {
                const SourceCodeRange range = node.codeRange(sema.ctx());
                if (range.srcView == callRange.srcView && range.offset > callRange.offset)
                    return true;
            }

            children.clear();
            node.collectChildrenFromAst(children, sema.ast());
            const bool insideNestedBreakable = pending.insideNestedBreakable ||
                                               (nodeRef != bodyRef && (isLoopStatement(node) || node.is(AstNodeId::SwitchStmt)));
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isValid())
                    worklist.push_back({childRef, insideNestedBreakable});
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

    namespace
    {
        // Does a deferred-call binding carry anything that can reach this frame? A snapshot
        // holding nothing but routes back to globals does not: it was captured so the
        // invalidation check can follow the payload, and reading it as "derives from local
        // storage" would silence real escapes through a global's buffer.
        bool deferredCallCarriesFrameBorrow(const SemaEscapeInfo& info)
        {
            for (const auto& snapshot : info.deferredCalls)
            {
                if (!snapshot)
                    continue;
                if (!snapshot->edges.empty())
                    return true;
                for (const SemaEscapeDeferredCheck& check : snapshot->checks)
                {
                    if (!check.staticSource)
                        return true;
                }
            }

            return false;
        }

        // Whether the base pointer of an assignment destination provably derives from
        // frame-local storage: a local pointer that borrows a local, or an opaque pointer
        // handed out by a call on local storage ('root.pool.newPtr()'). Storing a frame-local's
        // borrow into such a destination stays within the frame (a self-reference), unlike a
        // parameter/global pointer (caller-visible) or an opaque pointer of unknown origin (a
        // heap block from an external allocator), which must still be reported.
        bool destinationBaseIsFrameLocalPointer(Sema& sema, AstNodeRef leftRef)
        {
            AstNodeRef ref   = sema.viewZero(leftRef).nodeRef();
            uint32_t   guard = 8;
            while (ref.isValid() && guard--)
            {
                const AstNode& node = sema.node(ref);
                if (node.is(AstNodeId::MemberAccessExpr))
                {
                    ref = sema.viewZero(node.cast<AstMemberAccessExpr>().nodeLeftRef).nodeRef();
                    continue;
                }
                if (node.is(AstNodeId::IndexExpr))
                {
                    ref = sema.viewZero(node.cast<AstIndexExpr>().nodeExprRef).nodeRef();
                    continue;
                }
                break;
            }

            const SymbolVariable* baseVar = ref.isValid() ? identifierVariable(sema, ref) : nullptr;
            if (!baseVar)
                return false;

            const SemaEscapeInfo* info = sema.variableEscapeInfo(*baseVar);
            if (!info)
                return false;
            if (info->isLocalBorrow())
                return true;
            return info->isDeferredCallBorrow() && deferredCallCarriesFrameBorrow(*info);
        }
    }

    Result applyAssignment(Sema& sema, AstNodeRef leftRef, AstNodeRef rightRef)
    {
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

        SemaEscapeProjection replacedProjection;
        if (storageProjection(sema, leftRef, replacedProjection) && replacedProjection.root && !replacedProjection.components.empty())
            detachReplacedOwnedPayloadViews(sema, replacedProjection, targetTypeRef);

        // A store through a destination that provably stays in this frame (a self-reference
        // through a local-derived pointer) never escapes, whatever borrow it carries.
        const bool destStaysInFrame = destinationBaseIsFrameLocalPointer(sema, leftRef);

        if (isDirectBorrowCarrier(sema, targetTypeRef) && !destStaysInFrame && (!dstVar || !isLocalVariableStorage(sema, *dstVar)))
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

        uint32_t       budget = K_EXPR_BUDGET;
        SemaEscapeInfo info   = expressionEscapeInfoWithTarget(sema, rightRef, targetTypeRef, budget);
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
        // the destination in READ mode: it roots member/deref accesses at the signature
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
                    size_t intoIndex = 0;
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
            else if (!pairRoot && !leftIsBareVar && currentFn)
            {
                // The store goes through a local bound to an ACCESSOR call
                // ('let table = .tablePtr(); table[i] = key'). Whether it reaches the
                // receiver depends on the accessor's return summary, which is not final
                // yet: record an edge and let the fixpoint decide.
                recordAccessorStoreIntoParamPair(sema, leftRef, info);
            }
        }

        if (dstVar)
            return storeOrReportDestinationInfo(sema, *dstVar, leftRef, info, "an assignment", hasProjection ? &projection : nullptr);

        // A local borrow reaching a destination that provably stays in this frame (a
        // self-reference through a local-derived pointer) does not escape. A temporary or
        // materialized borrow dies with the statement/frame regardless, so it always does.
        if (info.isLocalBorrow())
            return destStaysInFrame ? Result::Continue : reportBorrowEscape(sema, leftRef, info, "an assignment");
        if (info.isMaterializedBorrow() || info.isTemporaryBorrow())
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

    const SymbolVariable* iterationSourceRoot(Sema& sema, AstNodeRef exprRef)
    {
        if (exprRef.isInvalid())
            return nullptr;
        return rootStorageOf(sema, exprRef);
    }

    // A structural change of storage that a local view is reading. The iteration check
    // below is the same rule restricted to loops; this one covers every view:
    // 'let v: string = s' then 's.append("...")' then reading 'v' reads a buffer the
    // append may have moved.
    //
    // Only the RECORDING happens here, where the flow state proves the view is live.
    // Whether the view is read afterwards cannot be answered yet - the statements that
    // follow are not resolved, so their identifiers carry no symbol.
    void noteBorrowInvalidation(Sema& sema, AstNodeRef callRef, const SymbolFunction& calledFn)
    {
        if (!isStructuralMutationCallee(sema, calledFn))
            return;

        SemaEscapeProjection mutationProjection;
        if (!mutatedReceiverProjection(sema, callRef, mutationProjection))
            return;
        const SymbolVariable* root = mutationProjection.root;

        const SourceCodeRange mutationRange = sema.node(callRef).codeRange(sema.ctx());
        if (!mutationRange.srcView)
            return;

        // The whole call expression, arguments included: a view named in them is read
        // before the callee runs, so it is not a read of storage the callee moved.
        const SourceCodeRange evaluationRange   = sema.node(callRef).codeRangeWithChildren(sema.ctx(), sema.ast());
        const uint32_t        evaluationEndSpan = evaluationRange.srcView == mutationRange.srcView ? evaluationRange.offset + evaluationRange.len : mutationRange.offset + mutationRange.len;

        // Only a value that OWNS a heap payload can have that payload moved or freed by
        // a method call. A plain aggregate has nothing to reallocate, so a view into it
        // survives any change to its fields.
        if (!designatedStorageHasOwningLifecycle(sema, root->typeRef()))
            return;

        for (const auto& [viewVar, info] : sema.variableEscapeInfos())
        {
            if (!viewVar || viewVar == root)
                continue;
            if (!isLocalVariableStorage(sema, *viewVar) || !isInvalidationJudgeableOwner(sema, *root))
                continue;
            if (viewAliasesVariableItself(sema, *viewVar, *root))
                continue;

            SmallVector4<SemaEscapeDeferredGuard> guards;
            if (!viewRoutesToStorage(sema, info, mutationProjection, guards))
                continue;

            SemaEscapeProjection   sourceProjection;
            SemaBorrowInvalidation record;
            record.viewVar                 = viewVar;
            record.sourceVar               = root;
            record.callee                  = &calledFn;
            record.bodyRef                 = currentAnalysisBodyRef(sema);
            record.mutationRef             = callRef;
            record.mutationRange           = mutationRange;
            record.evaluationEndOffset     = evaluationEndSpan;
            record.mutationName            = calledFn.name(sema.ctx());
            record.borrowedPayloadField    = ownedPayloadProjection(sema, info, sourceProjection) ? firstProjectionField(sourceProjection) : nullptr;
            record.receiverProjectionField = firstProjectionField(mutationProjection);
            record.guards                  = guards;
            sema.addBorrowInvalidation(record);
        }
    }

    Result reportBorrowInvalidations(Sema& sema, AstNodeRef declRef)
    {
        if (declRef.isInvalid() || sema.borrowInvalidations().empty())
            return Result::Continue;

        const SymbolFunction* currentFn = sema.currentFunction();
        if (!currentFn)
            return Result::Continue;

        // A nested function completes first: it judges only the views declared in it and
        // leaves the enclosing body's records alone. Ownership is decided on the view's
        // symbol rather than on source ranges, because a '#test' or '#init' block spans
        // no more than its own keyword.
        SmallVector<SemaBorrowInvalidation> mine;
        SmallVector<SemaBorrowInvalidation> rest;
        for (const SemaBorrowInvalidation& record : sema.borrowInvalidations())
        {
            const bool inside = record.viewVar &&
                                (record.viewVar->isFunctionLocalVariable(*currentFn) || currentFn->containsLocalVariable(*record.viewVar));
            (inside ? mine : rest).push_back(record);
        }

        sema.setBorrowInvalidations(rest.span());
        if (mine.empty())
            return Result::Continue;

        // Source order, so the report does not depend on the order the calls were
        // analyzed in.
        std::ranges::sort(mine, [](const SemaBorrowInvalidation& a, const SemaBorrowInvalidation& b) {
            if (a.mutationRange.offset != b.mutationRange.offset)
                return a.mutationRange.offset < b.mutationRange.offset;
            return a.viewVar < b.viewVar;
        });

        // Whether the callee can really move the payload is a summary fact, and summaries
        // are only final once the module has no pending sema job: hand the finished
        // wording over and let 'reportDeferredChecks' apply the condition.
        for (const SemaBorrowInvalidation& record : mine)
        {
            const AstNodeRef bodyRef = record.bodyRef.isValid() ? record.bodyRef : declRef;
            const AstNodeRef readRef = firstReadAfter(sema, bodyRef, record.mutationRef, record.mutationRange, record.evaluationEndOffset, *record.viewVar);
            if (readRef.isInvalid())
                continue;

            SemaEscapeDeferredCheck check;
            check.callee                  = record.callee;
            check.paramIndex              = 0; // the receiver
            check.judgeReallocates        = true;
            check.borrowedPayloadField    = record.borrowedPayloadField;
            check.receiverProjectionField = record.receiverProjectionField;
            check.guards                  = record.guards;
            check.diagId                  = DiagnosticId::sanity_err_borrow_invalidated;
            check.fileRef                 = sema.srcView(sema.node(declRef).srcViewRef()).fileRef();
            check.siteRange               = record.mutationRange;
            check.symName                 = record.sourceVar->name(sema.ctx());
            check.valueName               = record.mutationName;
            check.what                    = record.viewVar->name(sema.ctx());

            check.noteId      = DiagnosticId::sema_note_borrow_taken_here;
            check.noteSymName = record.viewVar->name(sema.ctx());
            check.noteRange   = record.viewVar->codeRange(sema.ctx());

            check.note2Id      = DiagnosticId::sema_note_borrow_read_here;
            check.note2SymName = record.viewVar->name(sema.ctx());
            check.note2Range   = sema.node(readRef).codeRange(sema.ctx());

            sema.ctx().compiler().addDeferredEscapeCheck(std::move(check));
        }

        return Result::Continue;
    }

    Result checkIterationMutation(Sema& sema, AstNodeRef callRef, const SymbolFunction& calledFn)
    {
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

            // The mutation is structural only when it targets the ITERATED COLLECTION
            // itself. A non-const method owned by another struct mutates one element's
            // own storage (a String inside an Array'String reached through the loop's
            // address binding), which the iteration snapshot survives.
            if (const SymbolStruct* calleeOwner = calledFn.ownerStruct())
            {
                const TypeRef sourceTypeRef = unwrapAliasEnum(sema, expressionTypeRef(sema, borrow.sourceRef));
                if (sourceTypeRef.isValid())
                {
                    const TypeInfo& sourceType = sema.typeMgr().get(sourceTypeRef);
                    if (sourceType.isStruct() && &sourceType.payloadSymStruct() != calleeOwner)
                        continue;
                }
            }

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

        // Returning a borrow of a parameter feeds this function's per-function summary
        // (consumed at call sites via callResultEscapeInfo). This must also fire from
        // inside an inline expansion sitting in return position: a borrow-returning callee
        // inlined into THIS function's 'return f(me)' still makes THIS function return that
        // parameter's borrow. 'addReturnBorrowOrigins' only records bits for the current
        // function's own parameters, so it is a no-op for any other borrow. Skipping it
        // under inlining was the release-only flakiness: whether the small callee was
        // auto-inlined (racing on its sema completion) decided if the summary was fed.
        if (info.kind == SemaEscapeKind::Parameter)
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
        recordDeferredCallBorrow(sema, callRef, callRef, "a stored call argument", DeferredCallUse::Argument, false);
    }

    Result checkSetContext(Sema& sema, AstNodeRef intrinsicRef, AstNodeRef argRef)
    {
        if (!setContextInstallsFrameStorage(sema, argRef))
            return Result::Continue;

        if (functionRestoresContext(sema, currentAnalysisBodyRef(sema), intrinsicRef))
            return Result::Continue;

        bool                  whole = false;
        const SymbolVariable* root  = storageRootVariable(sema, argRef, false, whole);
        if (!root)
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sanity_err_context_escape, intrinsicRef);
        diag.addArgument(Diagnostic::ARG_SYM, root->name(sema.ctx()));
        diag.addNote(DiagnosticId::sema_note_borrow_source_declared_here);
        diag.last().addArgument(Diagnostic::ARG_SYM, root->name(sema.ctx()));
        diag.last().addSpan(root->codeRange(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
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
        auto propagateReallocation = [](const SemaEscapeSummaryEdge& edge) {
            const uint64_t beforeMask    = edge.caller->reallocatesParamsMask();
            const size_t   beforeFields  = edge.caller->reallocatedParamFields().size();
            const bool     beforeUnknown = edge.caller->reallocatesParamProjectionUnknown(edge.callerParamIndex);

            if (edge.callerProjectionField)
            {
                edge.caller->addReallocatesParamField(edge.callerParamIndex, *edge.callerProjectionField);
            }
            else
            {
                bool copiedField = false;
                for (const SymbolFunction::ReallocatedParamField& entry : edge.callee->reallocatedParamFields())
                {
                    if (entry.paramIndex != edge.calleeParamIndex || !entry.field)
                        continue;
                    edge.caller->addReallocatesParamField(edge.callerParamIndex, *entry.field);
                    copiedField = true;
                }

                // Imported/opaque summaries currently carry only the conservative bit.
                if (!copiedField || edge.callee->reallocatesParamProjectionUnknown(edge.calleeParamIndex))
                    edge.caller->addReallocatesParam(edge.callerParamIndex);
            }

            return beforeMask != edge.caller->reallocatesParamsMask() ||
                   beforeFields != edge.caller->reallocatedParamFields().size() ||
                   beforeUnknown != edge.caller->reallocatesParamProjectionUnknown(edge.callerParamIndex);
        };

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

                        // A wrapper that hands back what an accessor read out of the
                        // payload returns a view into that payload too - but only when the
                        // argument WAS the payload's owner, not when the caller passed
                        // something the callee merely reached through.
                        if ((edge.callee->returnsPayloadParamsMask() & calleeBit) && !(edge.caller->returnsPayloadParamsMask() & callerBit))
                        {
                            edge.caller->addReturnsPayloadParam(edge.callerParamIndex);
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
                        // handing its parameter to a freeing callee frees it too. When
                        // what was handed over is a payload the parameter OWNS, the
                        // conclusion changes rather than disappears: releasing the buffer
                        // does not release the container, but it does move it, and that is
                        // what invalidates the views into it. When the argument merely
                        // CARRIES the parameter in a field, there is no conclusion at all:
                        // the callee frees the carrier, which is not the parameter.
                        if ((edge.callee->freesParamsMask() & calleeBit) && !edge.viaStoredField)
                        {
                            if (edge.viaOwnedPayload)
                            {
                                if (propagateReallocation(edge))
                                    changed = true;
                            }
                            else if (!(edge.caller->freesParamsMask() & callerBit))
                            {
                                edge.caller->addFreesParam(edge.callerParamIndex);
                                changed = true;
                            }
                        }

                        // A method that hands its receiver to one that reallocates the
                        // payload reallocates it too: 'append' through 'reserve'.
                        if ((edge.callee->reallocatesParamsMask() & calleeBit) && propagateReallocation(edge))
                        {
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

                    // 'let table = .tablePtr(); table[i] = key': the store lands in
                    // whatever the accessor handed back. It reaches the receiver exactly
                    // when the accessor returns a borrow of it - which only the (final)
                    // return summary can say.
                    case SemaEscapeSummaryEdgeKind::ReturnToPair:
                        if ((edge.callee->returnBorrowsParamsMask() & calleeBit) &&
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
            if (check.judgeReallocates)
            {
                // A method that cannot move or release what its receiver owns leaves
                // every view into that payload valid.
                if (!((check.callee->reallocatesParamsMask() >> check.paramIndex) & 1))
                    continue;

                if (check.borrowedPayloadField)
                {
                    if (check.receiverProjectionField)
                    {
                        // Calling a mutator on one nested owner can only affect that
                        // first field of the outer receiver.
                        if (check.receiverProjectionField != check.borrowedPayloadField)
                            continue;
                    }
                    else if (!check.callee->reallocatesParamProjectionUnknown(check.paramIndex))
                    {
                        const bool fieldHit = std::ranges::any_of(check.callee->reallocatedParamFields(), [&check](const SymbolFunction::ReallocatedParamField& entry) {
                            return entry.paramIndex == check.paramIndex && entry.field == check.borrowedPayloadField;
                        });
                        if (!fieldHit)
                            continue;
                    }
                }
            }
            else if (check.judgeAlways)
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
                if (!guard.callee)
                    return true;
                const uint64_t mask = guard.requirePayload ? guard.callee->returnsPayloadParamsMask() : guard.callee->returnBorrowsParamsMask();
                return !(mask & (1ULL << guard.paramIndex));
            });
            if (guardMiss)
                continue;

            Diagnostic diag = Diagnostic::get(diagId, check.fileRef);
            diag.last().addSpan(check.siteRange);
            if (!check.symName.empty())
                diag.addArgument(Diagnostic::ARG_SYM, check.symName);
            if (!check.valueName.empty())
                diag.addArgument(Diagnostic::ARG_VALUE, check.valueName);
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

            if (check.note2Id != DiagnosticId::None)
            {
                diag.addNote(check.note2Id);
                if (!check.note2SymName.empty())
                    diag.last().addArgument(Diagnostic::ARG_SYM, check.note2SymName);
                diag.last().addSpan(check.note2Range);
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
