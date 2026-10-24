#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenExprView.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Compiler/CodeGen/Core/CodeGenStructHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Symbol* recoverMemberAccessRightSymbol(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (!nodeRef.isValid())
            return nullptr;

        if (Symbol* symbol = codeGen.sema().viewStored(nodeRef, SemaNodeViewPartE::Symbol).sym())
            return symbol;

        const AstNodeRef resolvedRef = codeGen.resolvedNodeRef(nodeRef);
        if (resolvedRef.isValid() && resolvedRef != nodeRef)
            return codeGen.sema().viewStored(resolvedRef, SemaNodeViewPartE::Symbol).sym();

        return nullptr;
    }

    struct StructUsingPathStep
    {
        const SymbolVariable* field     = nullptr;
        bool                  isPointer = false;
    };

    bool resolveUsingMemberPathRec(CodeGen& codeGen, const SymbolStruct& currentStruct, const SymbolStruct& targetStruct, SmallVector<StructUsingPathStep>& outSteps, PointerSet<const SymbolStruct>& visited)
    {
        SWC_ASSERT(&currentStruct != &targetStruct);
        if (!visited.insert(&currentStruct))
            return false;

        for (const SymbolVariable* field : currentStruct.fields())
        {
            SWC_ASSERT(field != nullptr);
            if (!field->isUsingField())
                continue;

            bool                usingFieldIsPointer = false;
            const SymbolStruct* usingTargetStruct   = field->usingTargetStruct(codeGen.ctx(), usingFieldIsPointer);
            if (!usingTargetStruct)
                continue;

            // Follow nested `using` fields until we reach the struct that actually owns the member.
            outSteps.push_back({.field = field, .isPointer = usingFieldIsPointer});
            if (usingTargetStruct == &targetStruct || resolveUsingMemberPathRec(codeGen, *usingTargetStruct, targetStruct, outSteps, visited))
                return true;

            outSteps.pop_back();
        }

        return false;
    }

    bool resolveStructMemberPath(CodeGen& codeGen, TypeRef leftTypeRef, const SymbolVariable& memberSym, SmallVector<StructUsingPathStep>& outSteps)
    {
        const SymbolMap* ownerSymMap = memberSym.ownerSymMap();
        const auto*      ownerStruct = ownerSymMap ? ownerSymMap->safeCast<SymbolStruct>() : nullptr;
        if (!ownerStruct)
            return false;

        const SymbolStruct* baseStruct = CodeGenStructHelpers::resolveRuntimeStructType(codeGen, leftTypeRef);
        if (!baseStruct)
            return false;
        if (baseStruct == ownerStruct)
            return true;

        PointerSet<const SymbolStruct> visited;
        return resolveUsingMemberPathRec(codeGen, *baseStruct, *ownerStruct, outSteps, visited);
    }

    struct AggregateMemberInfo
    {
        uint32_t offset        = 0;
        TypeRef  memberTypeRef = TypeRef::invalid();
    };

    // Match sema: peel all reference layers, then at most one pointer. A value
    // of type '*T' or '&T' needs one step; a reference to a pointer slot
    // ('&*T', as returned by opIndex) needs two.
    uint32_t memberAccessDerefDepth(CodeGen& codeGen, const TypeInfo& leftTypeInfo)
    {
        uint32_t        depth = 0;
        const TypeInfo* walk  = &leftTypeInfo;
        while (walk->isReference())
        {
            ++depth;
            walk = &codeGen.typeMgr().unwrapAliasEnumTypeOrSelf(codeGen.ctx(), walk->payloadTypeRef());
        }

        if (walk->isAnyPointer())
            ++depth;

        return depth;
    }

    bool resolveAggregateMemberInfo(CodeGen& codeGen, const TypeInfo& aggregateType, AstNodeRef memberRef, AggregateMemberInfo& outInfo)
    {
        if (!aggregateType.isAggregateStruct())
            return false;

        const auto& aggregate = aggregateType.payloadAggregate();
        const auto& types     = aggregate.types;
        SWC_ASSERT(aggregate.names.size() == types.size());

        const IdentifierRef idRef       = codeGen.sema().idMgr().addIdentifier(codeGen.ctx(), codeGen.node(memberRef).codeRef());
        size_t              memberIndex = 0;
        if (!aggregateType.tryGetAggregateMemberIndexByName(memberIndex, codeGen.ctx(), idRef) || memberIndex >= types.size())
            return false;

        uint64_t offset = 0;
        for (size_t i = 0; i <= memberIndex; ++i)
        {
            const TypeInfo& memberType  = codeGen.typeMgr().get(types[i]);
            const uint32_t  memberAlign = std::max<uint32_t>(memberType.alignOf(codeGen.ctx()), 1);
            const uint64_t  memberSize  = memberType.sizeOf(codeGen.ctx());
            if (memberSize)
                offset = ((offset + static_cast<uint64_t>(memberAlign) - 1) / static_cast<uint64_t>(memberAlign)) * static_cast<uint64_t>(memberAlign);

            if (i == memberIndex)
            {
                outInfo.offset        = static_cast<uint32_t>(offset);
                outInfo.memberTypeRef = types[i];
                return true;
            }

            offset += memberSize;
        }

        return false;
    }

    const TypeInfo* resolveAggregateMemberOwnerType(CodeGen& codeGen, const TypeInfo& leftType)
    {
        const TypeInfo* leftTypeInfo = &leftType;
        if (leftTypeInfo->isPointerOrReference())
            leftTypeInfo = &codeGen.typeMgr().unwrapAliasEnumTypeOrSelf(codeGen.ctx(), leftTypeInfo->payloadTypeRef());

        return leftTypeInfo->isAggregateStruct() ? leftTypeInfo : nullptr;
    }

    MicroReg resolveAggregateMemberBaseAddress(CodeGen& codeGen, const TypeInfo& leftTypeInfo, const CodeGenNodePayload& leftPayload)
    {
        MicroBuilder& builder = codeGen.builder();

        if (leftTypeInfo.isPointerOrReference() || leftTypeInfo.isTypeInfo())
        {
            if (leftPayload.isAddress())
            {
                const MicroReg baseAddressReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(baseAddressReg, leftPayload.reg, 0, MicroOpBits::B64);
                return baseAddressReg;
            }

            return leftPayload.reg;
        }

        if (leftPayload.isAddress())
            return leftPayload.reg;

        const uint64_t leftSize = leftTypeInfo.sizeOf(codeGen.ctx());
        SWC_ASSERT(leftSize > 0);
        if (leftSize == 1 || leftSize == 2 || leftSize == 4 || leftSize == 8)
        {
            const MicroReg spillAddrReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
            builder.emitLoadMemReg(spillAddrReg, 0, leftPayload.reg, CodeGenTypeHelpers::bitsFromStorageSize(leftSize));
            return spillAddrReg;
        }

        return leftPayload.reg;
    }

    bool shouldTreatStructMemberLeftAsValue(CodeGen& codeGen, AstNodeRef leftRef, const CodeGenNodePayload& leftPayload)
    {
        const SemaNodeView leftTypeView = codeGen.viewType(leftRef);
        if (leftTypeView.type() && SemaHelpers::aliasEnumType(codeGen.sema(), leftTypeView).isReference())
            return false;

        return leftPayload.isValue();
    }

    Result codeGenStructMemberAccess(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        const CodeGenNodePayload& leftPayload        = codeGen.payload(node.nodeLeftRef);
        const TypeRef             preOverrideTypeRef = CodeGenExprView::payloadTypeRef(codeGen, leftPayload, node.nodeLeftRef);

        const SemaNodeView rightView = codeGen.viewSymbol(node.nodeRightRef);
        const Symbol*      rightSym  = rightView.sym();
        if (!rightSym)
            rightSym = recoverMemberAccessRightSymbol(codeGen, node.nodeRightRef);
        SWC_ASSERT(rightSym != nullptr);
        if (!rightSym)
            return Result::Error;

        const auto& semaSymVar  = rightSym->cast<SymbolVariable>();
        TypeRef     leftTypeRef = CodeGenStructHelpers::resolveRuntimeLeftTypeRef(codeGen, node.nodeLeftRef, preOverrideTypeRef);
        SWC_ASSERT(leftTypeRef.isValid());
        const TypeInfo& leftTypeInfo = codeGen.typeMgr().unwrapAliasEnumTypeOrSelf(codeGen.ctx(), leftTypeRef);

        // Concrete receiver overrides select the field layout but retain the payload's
        // original indirection. Pointer receivers still need a dereference.
        const TypeInfo& indirectionInfo = leftTypeInfo.isPointerOrReference() ? leftTypeInfo : codeGen.typeMgr().unwrapAliasEnumTypeOrSelf(codeGen.ctx(), preOverrideTypeRef);

        // Resolve fields in the active generic specialization. Root generic symbols
        // retain offsets and types that can be wrong for the runtime layout.
        const SymbolVariable* concreteSymVar = CodeGenStructHelpers::tryResolveConcreteStructMemberSymbol(codeGen, leftTypeRef, semaSymVar);
        const SymbolVariable& symVar         = concreteSymVar ? *concreteSymVar : semaSymVar;

        const TypeRef             memberTypeRef = symVar.typeRef();
        const CodeGenNodePayload& payload       = codeGen.setPayloadAddress(codeGen.curNodeRef(), memberTypeRef);
        MicroBuilder&             builder       = codeGen.builder();
        const ScopedDebugSource   debugSource(builder, leftPayload.sourceCodeRef);

        SmallVector<StructUsingPathStep> usingPath;
        if (leftTypeRef.isValid())
            resolveStructMemberPath(codeGen, leftTypeRef, symVar, usingPath);

        MicroReg baseAddressReg = leftPayload.reg;
        if (indirectionInfo.isPointerOrReference() || leftTypeInfo.isTypeInfo())
        {
            // Use the pointee object as the member base. Address-backed pointer
            // values must first be loaded from their storage.
            if (leftPayload.isAddress())
            {
                baseAddressReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(baseAddressReg, leftPayload.reg, 0, MicroOpBits::B64);
            }

            // One indirection per layer beyond the first: a reference bound to a pointer
            // slot yields the slot address, and the slot yields the object.
            for (uint32_t remaining = memberAccessDerefDepth(codeGen, indirectionInfo); remaining > 1; --remaining)
            {
                const MicroReg nextReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(nextReg, baseAddressReg, 0, MicroOpBits::B64);
                baseAddressReg = nextReg;
            }
        }
        else if (!shouldTreatStructMemberLeftAsValue(codeGen, node.nodeLeftRef, leftPayload))
        {
            baseAddressReg = leftPayload.reg;
        }
        else
        {
            const uint64_t leftSize = leftTypeInfo.sizeOf(codeGen.ctx());
            SWC_ASSERT(leftSize > 0);

            if (leftSize == 1 || leftSize == 2 || leftSize == 4 || leftSize == 8)
            {
                // Spill small by-value aggregates so field offsets have an address base.
                const MicroReg spillAddrReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
                builder.emitLoadMemReg(spillAddrReg, 0, leftPayload.reg, CodeGenTypeHelpers::bitsFromStorageSize(leftSize));
                baseAddressReg = spillAddrReg;
            }
        }

        // Replay the using chain to compute offsets from the field's owning subobject.
        for (const auto& step : usingPath)
        {
            SWC_ASSERT(step.field != nullptr);
            if (step.isPointer)
            {
                const MicroReg nextAddressReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(nextAddressReg, baseAddressReg, step.field->offset(), MicroOpBits::B64);
                baseAddressReg = nextAddressReg;
            }
            else
            {
                baseAddressReg = codeGen.offsetAddressReg(baseAddressReg, step.field->offset());
            }
        }

        // A payload member sits after the tag, so the union starts at the member's owning base.
        const auto* lowering = codeGen.loweringPayload(codeGen.curNodeRef());
        if (lowering && lowering->taggedCaseAsserted)
            SWC_RESULT(CodeGenSafety::emitTaggedCaseCheck(codeGen, node, baseAddressReg, symVar));

        builder.emitLoadAddressRegMem(payload.reg, baseAddressReg, symVar.offset(), MicroOpBits::B64);

        // 'late' field: reading a value that was never assigned is a guarded
        // fault. Consumers that never read (pure store target, address-of,
        // null comparison) cleared the safety payload during sema.
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::LateInit))
            SWC_RESULT(CodeGenSafety::emitLateReadCheck(codeGen, node, payload.reg, memberTypeRef));

        return Result::Continue;
    }

    Result codeGenAggregateStructMemberAccess(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        const CodeGenNodePayload& leftPayload = codeGen.payload(node.nodeLeftRef);
        const TypeRef             leftTypeRef = CodeGenExprView::payloadTypeRef(codeGen, leftPayload, node.nodeLeftRef);
        SWC_ASSERT(leftTypeRef.isValid());
        const TypeInfo& leftType      = codeGen.typeMgr().unwrapAliasEnumTypeOrSelf(codeGen.ctx(), leftTypeRef);
        const TypeInfo* aggregateType = resolveAggregateMemberOwnerType(codeGen, leftType);
        SWC_ASSERT(aggregateType != nullptr);

        AggregateMemberInfo memberInfo;
        if (!resolveAggregateMemberInfo(codeGen, *aggregateType, node.nodeRightRef, memberInfo))
            SWC_UNREACHABLE();

        const CodeGenNodePayload& payload = codeGen.setPayloadAddress(codeGen.curNodeRef(), memberInfo.memberTypeRef);
        MicroBuilder&             builder = codeGen.builder();
        const ScopedDebugSource   debugSource(builder, leftPayload.sourceCodeRef);
        const MicroReg            baseReg = resolveAggregateMemberBaseAddress(codeGen, leftType, leftPayload);
        builder.emitLoadAddressRegMem(payload.reg, baseReg, memberInfo.offset, MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenInterfaceMethodMemberAccess(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        MicroBuilder&             builder     = codeGen.builder();
        const CodeGenNodePayload& leftPayload = codeGen.payload(node.nodeLeftRef);
        const ScopedDebugSource   debugSource(builder, leftPayload.sourceCodeRef);

        // Prefer the method selected on the enclosing call: the right identifier
        // can still name the first homonym of an overloaded '#fwd' method.
        const Symbol* methodSym = nullptr;

        const AstNodeRef parentRef = codeGen.visit().parentNodeRef(0);
        if (parentRef.isValid())
        {
            const SemaNodeView parentStored = codeGen.sema().viewStored(parentRef, SemaNodeViewPartE::Symbol);
            if (parentStored.sym() && parentStored.sym()->isFunction() && parentStored.sym()->cast<SymbolFunction>().hasInterfaceMethodSlot())
                methodSym = parentStored.sym();
        }

        if (!methodSym)
        {
            const SemaNodeView rightView = codeGen.viewSymbol(node.nodeRightRef);
            methodSym                    = rightView.sym();
        }

        if (!methodSym)
            methodSym = recoverMemberAccessRightSymbol(codeGen, node.nodeRightRef);
        SWC_ASSERT(methodSym != nullptr);
        if (!methodSym)
            return Result::Error;

        const auto& methodFunc = methodSym->cast<SymbolFunction>();
        SWC_ASSERT(methodFunc.hasInterfaceMethodSlot());

        const CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef());
        const MicroReg            leftReg = leftPayload.reg;
        const MicroReg            dstReg  = payload.reg;
        builder.emitLoadRegMem(dstReg, leftReg, offsetof(Runtime::Interface, itable), MicroOpBits::B64);
        builder.emitLoadRegMem(dstReg, dstReg, (methodFunc.interfaceMethodSlot() + 1) * sizeof(void*), MicroOpBits::B64);
        return Result::Continue;
    }

    bool isRuntimeMemberAccessLeft(const SemaNodeView& leftView)
    {
        if (!leftView.sym())
            return true;

        return !leftView.sym()->isType() &&
               !leftView.sym()->isNamespace() &&
               !leftView.sym()->isModule() &&
               !leftView.sym()->isImpl();
    }

    bool isCompileTimeMemberAccessLeftNode(const AstNode& node)
    {
        return node.is(AstNodeId::Identifier) || node.is(AstNodeId::NamedType) || node.is(AstNodeId::SuffixLiteral);
    }

    bool canSkipCompileTimeMemberAccessLeft(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        const SemaNodeView leftView = codeGen.viewTypeSymbol(node.nodeLeftRef);
        if (!isRuntimeMemberAccessLeft(leftView))
            return true;

        if (leftView.sym() || !leftView.typeRef().isValid())
            return false;
        if (!isCompileTimeMemberAccessLeftNode(codeGen.node(node.nodeLeftRef)))
            return false;

        const SemaNodeView rightView = codeGen.viewSymbol(node.nodeRightRef);
        if (!rightView.sym())
            return false;

        return rightView.sym()->isFunction() ||
               rightView.sym()->isType() ||
               rightView.sym()->isNamespace() ||
               rightView.sym()->isModule() ||
               rightView.sym()->isImpl();
    }

    bool canMaterializeScopedRightSymbol(const Symbol& symbol)
    {
        if (!symbol.isVariable())
            return false;

        return symbol.cast<SymbolVariable>().hasGlobalStorage();
    }

    Result finalizeRuntimeMemberAccess(CodeGen& codeGen, const Result result)
    {
        if (result != Result::Continue)
            return result;

        const CodeGenNodePayload* payload = codeGen.safePayload(codeGen.curNodeRef());
        SWC_ASSERT(payload != nullptr);
        SWC_ASSERT(payload->reg.isValid());
        return result;
    }
}

Result AstMemberAccessExpr::codeGenPreNodeChild(const CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef == nodeLeftRef)
    {
        // A '?.' left side must always be materialized: its null test guards the rest
        // of the chain, even when the member itself resolves to a function and the
        // receiver would otherwise only be produced by the call machinery.
        if (!hasFlag(AstMemberAccessExprFlagsE::OptionalAccess) &&
            canSkipCompileTimeMemberAccessLeft(const_cast<CodeGen&>(codeGen), *this))
            return Result::SkipChildren;
    }

    if (childRef == nodeRightRef)
        return Result::SkipChildren;

    return Result::Continue;
}

Result AstMemberAccessExpr::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (!hasFlag(AstMemberAccessExprFlagsE::OptionalAccess))
        return Result::Continue;

    // Child callbacks use resolved references: qualification casts, including
    // UFCS receiver binds, can replace the direct left node.
    const AstNodeRef resolvedLeftRef = codeGen.resolvedNodeRef(nodeLeftRef);
    SWC_ASSERT(resolvedLeftRef.isValid());
    if (codeGen.resolvedNodeRef(childRef) != resolvedLeftRef)
        return Result::Continue;

    // Exit the enclosing optional chain on null so the remaining member access
    // runs with a proven non-null receiver.
    const auto* chainState = codeGen.findEnclosingNodePayload<OptionalChainCodeGenPayload>(AstNodeId::OptionalChainExpr);
    SWC_ASSERT(chainState != nullptr && chainState->falseLabel.isValid());

    const CodeGenNodePayload& leftPayload = codeGen.payload(resolvedLeftRef);
    const TypeRef             leftTypeRef = CodeGenExprView::payloadTypeRef(codeGen, leftPayload, resolvedLeftRef);
    const ScopedDebugSource   debugSource(codeGen.builder(), leftPayload.sourceCodeRef);
    CodeGenCompareHelpers::emitConditionFalseJump(codeGen, leftPayload, leftTypeRef, chainState->falseLabel);
    return Result::Continue;
}

Result AstMemberAccessExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView leftView           = codeGen.viewTypeSymbol(nodeLeftRef);
    const bool         leftIsRuntimeValue = isRuntimeMemberAccessLeft(leftView);

    if (leftIsRuntimeValue && leftView.type() && leftView.type()->isInterface())
        return finalizeRuntimeMemberAccess(codeGen, codeGenInterfaceMethodMemberAccess(codeGen, *this));
    if (leftIsRuntimeValue && leftView.type() && resolveAggregateMemberOwnerType(codeGen, SemaHelpers::aliasEnumType(codeGen.sema(), leftView)))
        return finalizeRuntimeMemberAccess(codeGen, codeGenAggregateStructMemberAccess(codeGen, *this));

    const SemaNodeView rightView = codeGen.viewSymbol(nodeRightRef);
    const Symbol*      rightSym  = rightView.sym();
    if (!rightSym)
        rightSym = recoverMemberAccessRightSymbol(codeGen, nodeRightRef);

    if (rightSym)
    {
        // Static impl members always use global storage, even through an instance.
        // Only instance fields use base-relative offsets; let statics fall through
        // to scoped-symbol materialization.
        if (leftIsRuntimeValue && rightSym->isVariable() && !rightSym->cast<SymbolVariable>().hasGlobalStorage())
            return finalizeRuntimeMemberAccess(codeGen, codeGenStructMemberAccess(codeGen, *this));

        if (rightSym->isFunction() || rightSym->isType() || rightSym->isNamespace() || rightSym->isModule() || rightSym->isImpl())
            return Result::Continue;
    }

    const CodeGenNodePayload* rightPayload = codeGen.safePayload(nodeRightRef);
    if ((!rightPayload || !rightPayload->reg.isValid()) && rightSym && canMaterializeScopedRightSymbol(*rightSym))
    {
        // Member access does not visit the RHS child during the normal walk. Scoped values such as
        // `Namespace.globalVar` still need the same payload materialization as a standalone identifier.
        SWC_RESULT(codeGen.emitNodeNow(nodeRightRef));
        rightPayload = codeGen.safePayload(nodeRightRef);
    }

    if (!rightPayload || !rightPayload->reg.isValid())
    {
        // Member access skips visiting the RHS at codegen time. If semantic analysis already rejected
        // that member, there may be no materialized payload to inherit, and codegen must not hard-assert.
        return Result::Continue;
    }

    codeGen.inheritPayload(codeGen.curNodeRef(), nodeRightRef, codeGen.transparentPayloadTypeRef());

    // A qualified 'late' global ('Namespace.global') carries its read guard on this node.
    if (rightSym && rightSym->isVariable() && rightSym->cast<SymbolVariable>().hasExtraFlag(SymbolVariableFlagsE::LateInit))
    {
        const CodeGenNodePayload* payload = codeGen.safePayload(codeGen.curNodeRef());
        if (payload && payload->isAddress())
            SWC_RESULT(CodeGenSafety::emitLateReadCheck(codeGen, *this, payload->reg, rightSym->cast<SymbolVariable>().typeRef()));
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
