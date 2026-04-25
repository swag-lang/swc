#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint64_t sliceCountFromArrayCast(TaskContext& ctx, const TypeInfo& srcArrayType, const TypeInfo& dstElementType)
    {
        const uint64_t dstElementSize = dstElementType.sizeOf(ctx);
        if (dstElementSize)
            return srcArrayType.sizeOf(ctx) / dstElementSize;

        uint64_t totalCount = 1;
        for (const uint64_t dim : srcArrayType.payloadArrayDims())
            totalCount *= dim;
        return totalCount;
    }

    CastRequest makeNestedCastRequest(const CastRequest& parent)
    {
        CastRequest nested(parent.kind);
        nested.flags        = parent.flags;
        nested.errorNodeRef = parent.errorNodeRef;
        nested.errorCodeRef = parent.errorCodeRef;
        return nested;
    }

    TypeRef unwrapCastOverflowTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeRef unwrappedTypeRef = sema.typeMgr().get(typeRef).unwrapAliasEnum(sema.ctx(), typeRef);
        if (unwrappedTypeRef.isValid())
            return unwrappedTypeRef;

        return typeRef;
    }

    TypeRef unwrapAliasEnumTypeRef(const TypeManager& typeMgr, const TaskContext& ctx, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeRef unwrappedTypeRef = typeMgr.get(typeRef).unwrapAliasEnum(ctx, typeRef);
        if (unwrappedTypeRef.isValid())
            return unwrappedTypeRef;

        return typeRef;
    }

    bool isImplicitNullableQualificationCast(const TypeInfo& srcType, const TypeInfo& dstType)
    {
        if (srcType.isNullable() == dstType.isNullable())
            return false;
        if (!srcType.supportsNullableQualifier() || !dstType.supportsNullableQualifier())
            return false;
        if (srcType.kind() != dstType.kind())
            return false;
        if (srcType.isConst() != dstType.isConst())
            return false;

        switch (srcType.kind())
        {
            case TypeInfoKind::ValuePointer:
            case TypeInfoKind::BlockPointer:
            case TypeInfoKind::Slice:
                return srcType.payloadTypeRef() == dstType.payloadTypeRef();

            case TypeInfoKind::String:
            case TypeInfoKind::CString:
            case TypeInfoKind::Any:
            case TypeInfoKind::TypeInfo:
                return true;

            default:
                return false;
        }
    }

    Result castAddNullableQualifier(CastRequest& castRequest)
    {
        if (!castRequest.isConstantFolding())
            return Result::Continue;

        castRequest.setConstantFoldingResult(castRequest.constantFoldingSrc());
        return Result::Continue;
    }

    bool isTruthyBoolCastKind(const CastKind castKind)
    {
        return castKind == CastKind::Condition ||
               castKind == CastKind::BoolExpr ||
               castKind == CastKind::Parameter ||
               castKind == CastKind::Initialization ||
               castKind == CastKind::Assignment;
    }

    bool isImplicitValueBoolCastKind(const CastKind castKind)
    {
        return castKind == CastKind::Parameter ||
               castKind == CastKind::Initialization ||
               castKind == CastKind::Assignment;
    }

    bool isStrictBoolExprCastKind(const CastKind castKind)
    {
        return castKind == CastKind::BoolExpr;
    }

    bool castNeedsOverflowRuntimeSafety(Sema& sema, TypeRef srcTypeRef, TypeRef dstTypeRef, CastFlags castFlags)
    {
        if (castFlags.hasAny({CastFlagsE::BitCast, CastFlagsE::NoOverflow}))
            return false;
        if (!sema.frame().currentAttributes().hasRuntimeSafety(sema.buildCfg().safetyGuards, Runtime::SafetyWhat::Overflow))
            return false;

        srcTypeRef = unwrapCastOverflowTypeRef(sema, srcTypeRef);
        dstTypeRef = unwrapCastOverflowTypeRef(sema, dstTypeRef);
        if (!srcTypeRef.isValid() || !dstTypeRef.isValid() || srcTypeRef == dstTypeRef)
            return false;

        const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

        if (srcType.isNumericIntLike() && dstType.isNumericIntLike())
        {
            if (srcType.isBool() || dstType.isBool())
                return false;

            const bool     srcUnsigned = srcType.isIntLikeUnsigned();
            const bool     dstUnsigned = dstType.isIntLikeUnsigned();
            const uint32_t srcBits     = srcType.payloadIntLikeBits();
            const uint32_t dstBits     = dstType.payloadIntLikeBits();

            if (srcUnsigned == dstUnsigned)
                return srcBits > dstBits;

            if (srcUnsigned && !dstUnsigned)
                return srcBits >= dstBits;

            return true;
        }

        if (srcType.isFloat() && dstType.isNumericIntLike() && !dstType.isBool())
            return true;

        return false;
    }

    Result constantFoldPointerLikeFromValue(Sema& sema, ConstantRef srcCstRef, TypeRef srcTypeRef, TypeRef dstTypeRef, ConstantRef& outCstRef)
    {
        const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
        SWC_ASSERT(dstType.isAnyPointer() || dstType.isReference() || dstType.isMoveReference());

        uint64_t       ptr       = 0;
        const uint64_t valueSize = srcType.sizeOf(sema.ctx());
        if (valueSize)
        {
            std::vector valueBytes(valueSize, std::byte{0});
            SWC_RESULT(ConstantLower::lowerToBytes(sema, asByteSpan(valueBytes), srcCstRef, srcTypeRef));
            const std::string_view rawValueData = sema.cstMgr().addPayloadBuffer(asStringView(asByteSpan(valueBytes)));
            ptr                                 = reinterpret_cast<uint64_t>(rawValueData.data());
        }

        const ConstantValue ptrCst = ConstantValue::makeValuePointer(sema.ctx(), dstType.payloadTypeRef(), ptr, dstType.flags());
        outCstRef                  = sema.cstMgr().addConstant(sema.ctx(), ptrCst);
        return Result::Continue;
    }

    Result foldConstantPointerLikeToBool(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef)
    {
        const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
        const uint64_t  sizeOf  = srcType.sizeOf(sema.ctx());
        if (!sizeOf)
        {
            castRequest.setConstantFoldingResult(sema.cstMgr().cstFalse());
            return Result::Continue;
        }

        std::vector valueBytes(sizeOf, std::byte{0});
        SWC_RESULT(ConstantLower::lowerToBytes(sema, asByteSpan(valueBytes), castRequest.constantFoldingSrc(), srcTypeRef));

        uint64_t rawValue = 0;
        std::memcpy(&rawValue, valueBytes.data(), std::min<uint64_t>(sizeof(rawValue), valueBytes.size()));
        castRequest.setConstantFoldingResult(rawValue ? sema.cstMgr().cstTrue() : sema.cstMgr().cstFalse());
        return Result::Continue;
    }

    ConstantRef readReferenceValueConstant(Sema& sema, ConstantRef refCstRef, TypeRef valueTypeRef)
    {
        if (refCstRef.isInvalid() || !valueTypeRef.isValid())
            return ConstantRef::invalid();

        const ConstantValue& refCst = sema.cstMgr().get(refCstRef);
        if (!refCst.isValuePointer() || !refCst.getValuePointer())
            return ConstantRef::invalid();

        const auto      valuePtr             = reinterpret_cast<const void*>(refCst.getValuePointer());
        const TypeRef   aliasResolvedTypeRef = sema.typeMgr().get(valueTypeRef).unwrap(sema.ctx(), valueTypeRef, TypeExpandE::Alias);
        const TypeRef   valueNoAliasTypeRef  = aliasResolvedTypeRef.isValid() ? aliasResolvedTypeRef : valueTypeRef;
        const TypeInfo& valueNoAliasType     = sema.typeMgr().get(valueNoAliasTypeRef);
        if (valueNoAliasType.isEnum())
        {
            const TypeRef       underlyingTypeRef = valueNoAliasType.payloadSymEnum().underlyingTypeRef();
            const ConstantValue underlyingCst     = ConstantValue::make(sema.ctx(), valuePtr, underlyingTypeRef, ConstantValue::PayloadOwnership::Borrowed);
            if (!underlyingCst.isValid())
                return ConstantRef::invalid();

            const ConstantRef   underlyingCstRef = sema.cstMgr().addConstant(sema.ctx(), underlyingCst);
            const ConstantValue enumCst          = ConstantValue::makeEnumValue(sema.ctx(), underlyingCstRef, valueNoAliasTypeRef);
            return sema.cstMgr().addConstant(sema.ctx(), enumCst);
        }

        const TypeRef       loadTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), valueTypeRef);
        const ConstantValue valueCst    = ConstantValue::make(sema.ctx(), valuePtr, loadTypeRef.isValid() ? loadTypeRef : valueTypeRef, ConstantValue::PayloadOwnership::Borrowed);
        if (!valueCst.isValid())
            return ConstantRef::invalid();

        return sema.cstMgr().addConstant(sema.ctx(), valueCst);
    }

    Result setupCastOverflowRuntimeSafety(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef, CastFlags castFlags)
    {
        if (!castNeedsOverflowRuntimeSafety(sema, srcTypeRef, dstTypeRef, castFlags))
            return Result::Continue;
        return SemaHelpers::setupRuntimeSafetyPanic(sema, nodeRef, Runtime::SafetyWhat::Overflow, sema.node(nodeRef).codeRef());
    }

    Result setupCastFromAnyRuntime(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef, CastFlags castFlags)
    {
        if (castFlags.has(CastFlagsE::BitCast))
            return Result::Continue;
        if (!castFlags.has(CastFlagsE::FromExplicitNode))
            return Result::Continue;
        if (!srcTypeRef.isValid() || !dstTypeRef.isValid())
            return Result::Continue;

        const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
        if (!srcType.isAny())
            return Result::Continue;

        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
        if (dstType.isAny())
            return Result::Continue;

        const bool hasDynCastSafety     = sema.frame().currentAttributes().hasRuntimeSafety(sema.buildCfg().safetyGuards, Runtime::SafetyWhat::DynCast);
        const bool dstUsesTypeInfoMatch = dstType.isStruct() ||
                                          dstType.isAnyPointer() ||
                                          dstType.isReference() ||
                                          dstType.isMoveReference() ||
                                          (!dstType.isInterface() && !dstType.isAnyVariadic());
        if (!dstUsesTypeInfoMatch)
            return Result::Continue;

        auto& payload = SemaHelpers::ensureCodeGenNodePayload(sema, nodeRef);

        if (hasDynCastSafety)
            payload.addRuntimeSafety(Runtime::SafetyWhat::DynCast);

        if (!sema.isCurrentFunction())
            return Result::Continue;

        const auto& codeRef = sema.node(nodeRef).codeRef();
        SWC_RESULT(SemaHelpers::attachRuntimeFunctionToNode(sema, nodeRef, IdentifierManager::RuntimeFunctionKind::As, codeRef));

        // Resolve panic function when DynCast safety is enabled
        if (hasDynCastSafety)
            SWC_RESULT(SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::SafetyPanic, codeRef));

        return Result::Continue;
    }

    AstNodeRef sourceArgRefForStructSpecCast(const Sema& sema, const SemaNodeView& view, const CastFlags castFlags)
    {
        SWC_UNUSED(sema);

        if (!castFlags.has(CastFlagsE::FromExplicitNode))
            return view.nodeRef();

        if (!view.node())
            return AstNodeRef::invalid();

        if (view.node()->is(AstNodeId::CastExpr))
            return view.node()->cast<AstCastExpr>().nodeExprRef;
        if (view.node()->is(AstNodeId::AutoCastExpr))
            return view.node()->cast<AstAutoCastExpr>().nodeExprRef;

        return AstNodeRef::invalid();
    }

    struct StructOpCastData
    {
        SymbolFunction* calledFn     = nullptr;
        AstNodeRef      sourceArgRef = AstNodeRef::invalid();
    };

    bool structOpCastBindsReferenceToValue(Sema& sema, const SymbolFunction& calledFn, AstNodeRef sourceArgRef)
    {
        if (sourceArgRef.isInvalid() || calledFn.parameters().empty())
            return false;

        const TypeRef receiverTypeRef = calledFn.parameters().front()->typeRef();
        if (!receiverTypeRef.isValid())
            return false;

        const TypeInfo& receiverType = sema.typeMgr().get(receiverTypeRef);
        if (!receiverType.isReference())
            return false;

        const TypeRef sourceTypeRef = sema.viewStored(sourceArgRef, SemaNodeViewPartE::Type).typeRef();
        if (!sourceTypeRef.isValid())
            return true;

        const TypeRef unwrappedSourceTypeRef = sema.typeMgr().get(sourceTypeRef).unwrap(sema.ctx(), sourceTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeRef resolvedSourceTypeRef  = unwrappedSourceTypeRef.isValid() ? unwrappedSourceTypeRef : sourceTypeRef;
        return !sema.typeMgr().get(resolvedSourceTypeRef).isPointerOrReference();
    }

    void buildStructOpCastResolvedArgs(Sema& sema, SmallVector<ResolvedCallArgument>& outResolvedArgs, AstNodeRef sourceArgRef, const SymbolFunction& calledFn)
    {
        ResolvedCallArgument resolvedArg;
        resolvedArg.argRef                = sourceArgRef;
        resolvedArg.bindsReferenceToValue = structOpCastBindsReferenceToValue(sema, calledFn, sourceArgRef);
        outResolvedArgs.push_back(resolvedArg);
    }

    Result prepareStructOpCast(Sema& sema, StructOpCastData& outData, const SemaNodeView& view, const CastRequest& castRequest, CastFlags castFlags)
    {
        outData.calledFn     = castRequest.selectedStructOpCast;
        outData.sourceArgRef = sourceArgRefForStructSpecCast(sema, view, castFlags);
        if (!outData.calledFn || outData.sourceArgRef.isInvalid())
            return Result::Continue;

        SWC_RESULT(sema.waitSemaCompleted(outData.calledFn, sema.node(outData.sourceArgRef).codeRef()));
        return Result::Continue;
    }

    Result tryConstantFoldStructOpCast(Sema& sema, AstNodeRef callRef, const StructOpCastData& castData, ConstantRef& outConstRef)
    {
        outConstRef = ConstantRef::invalid();
        if (!castData.calledFn || castData.sourceArgRef.isInvalid())
            return Result::Continue;

        SmallVector<ResolvedCallArgument> resolvedArgs;
        buildStructOpCastResolvedArgs(sema, resolvedArgs, castData.sourceArgRef, *castData.calledFn);

        SWC_RESULT(SemaJIT::tryRunConstCall(sema, *castData.calledFn, callRef, resolvedArgs.span()));
        const SemaNodeView callView(sema, callRef, SemaNodeViewPartE::Constant);
        if (callView.cstRef().isValid())
            outConstRef = callView.cstRef();
        return Result::Continue;
    }

    Result finalizeRuntimeStructOpCast(Sema& sema, AstNodeRef castNodeRef, const StructOpCastData& castData)
    {
        if (castNodeRef.isInvalid() || castData.sourceArgRef.isInvalid() || !castData.calledFn || sema.isGlobalScope())
            return Result::Continue;

        SmallVector<ResolvedCallArgument> resolvedArgs;
        buildStructOpCastResolvedArgs(sema, resolvedArgs, castData.sourceArgRef, *castData.calledFn);

        sema.setResolvedCallArguments(castNodeRef, resolvedArgs);
        sema.setIsValue(castNodeRef);
        sema.unsetIsLValue(castNodeRef);

        auto* payload = sema.semaPayload<CastSpecOpPayload>(castNodeRef);
        if (!payload)
        {
            payload = sema.compiler().allocate<CastSpecOpPayload>();
            sema.setSemaPayload(castNodeRef, payload);
        }

        payload->kind     = CastSpecialOpPayloadKind::OpCast;
        payload->calledFn = castData.calledFn;
        SemaHelpers::addCurrentFunctionCallDependency(sema, castData.calledFn);
        return SemaHelpers::attachIndirectReturnRuntimeStorageIfNeeded(sema, sema.node(castNodeRef), *castData.calledFn, "__cast_runtime_storage");
    }

    Result computeStructSetReceiverInit(Sema& sema, TypeRef dstTypeRef, const SymbolFunction& calledFn, ConstantRef& outInitCstRef)
    {
        outInitCstRef = ConstantRef::invalid();
        if (calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Complete))
            return Result::Continue;

        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
        SWC_RESULT(sema.waitSemaCompleted(&dstType, sema.curNodeRef()));
        outInitCstRef = dstType.payloadSymStruct().computeDefaultValue(sema, dstTypeRef);
        return Result::Continue;
    }

    struct StructSetCastData
    {
        SymbolFunction* calledFn           = nullptr;
        ConstantRef     receiverInitCstRef = ConstantRef::invalid();
        AstNodeRef      sourceArgRef       = AstNodeRef::invalid();
    };

    CastFlags structSetParamCastFlags(const Sema& sema, AstNodeRef sourceArgRef)
    {
        UserDefinedLiteralSuffixInfo suffixInfo;
        if (!Cast::resolveUserDefinedLiteralSuffix(sema, sourceArgRef, suffixInfo))
            return CastFlagsE::Zero;

        CastFlags castFlags = CastFlagsE::Zero;
        castFlags.add(CastFlagsE::LiteralSuffixConsume);
        return castFlags;
    }

    AstNodeRef makeStructSetReceiverRef(Sema& sema, TypeRef dstTypeRef, AstNodeRef sourceArgRef, SymbolVariable* storageSym, ConstantRef initCstRef)
    {
        const TokenRef tokRef            = sourceArgRef.isValid() ? Cast::userDefinedLiteralValueTokRef(sema, sourceArgRef) : sema.curNode().tokRef();
        auto [receiverRef, receiverNode] = sema.ast().makeNode<AstNodeId::Identifier>(tokRef);
        if (storageSym)
            sema.setSymbol(receiverRef, storageSym);
        else if (initCstRef.isValid())
            sema.setConstant(receiverRef, initCstRef);
        else
            sema.setType(receiverRef, dstTypeRef);
        sema.setIsValue(*receiverNode);
        sema.setIsLValue(*receiverNode);
        return receiverRef;
    }

    void buildStructSetResolvedArgs(Sema& sema, SmallVector<ResolvedCallArgument>& outResolvedArgs, TypeRef dstTypeRef, AstNodeRef sourceArgRef, SymbolVariable* storageSym, ConstantRef receiverInitCstRef)
    {
        const AstNodeRef receiverRef = makeStructSetReceiverRef(sema, dstTypeRef, sourceArgRef, storageSym, receiverInitCstRef);
        outResolvedArgs.push_back({.argRef = receiverRef, .bindsReferenceToValue = true});
        outResolvedArgs.push_back({.argRef = sourceArgRef});
    }

    Result prepareStructSetCast(Sema& sema, StructSetCastData& outData, SemaNodeView& view, TypeRef dstTypeRef, CastKind castKind, CastFlags castFlags)
    {
        outData              = {};
        outData.sourceArgRef = sourceArgRefForStructSpecCast(sema, view, castFlags);
        if (outData.sourceArgRef.isInvalid())
            return Result::Continue;

        const SourceCodeRef codeRef = sema.node(outData.sourceArgRef).codeRef();
        TypeRef             paramTypeRef;
        SWC_RESULT(Cast::resolveStructSetCastCandidate(sema, codeRef, view.typeRef(), dstTypeRef, castKind, outData.calledFn, paramTypeRef, outData.sourceArgRef));
        if (!outData.calledFn)
            return Result::Continue;

        if (paramTypeRef.isValid() && view.typeRef() != paramTypeRef)
        {
            SemaNodeView    sourceView(sema, outData.sourceArgRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            const CastFlags paramCastFlags = structSetParamCastFlags(sema, outData.sourceArgRef);
            SWC_RESULT(Cast::cast(sema, sourceView, paramTypeRef, CastKind::Parameter, paramCastFlags));
            outData.sourceArgRef = sourceView.nodeRef();
            if (!castFlags.has(CastFlagsE::FromExplicitNode))
                view = sourceView;
        }

        return computeStructSetReceiverInit(sema, dstTypeRef, *outData.calledFn, outData.receiverInitCstRef);
    }

    Result tryConstantFoldStructSetCast(Sema& sema, AstNodeRef callRef, const StructSetCastData& castData, TypeRef dstTypeRef, ConstantRef& outConstRef)
    {
        outConstRef = ConstantRef::invalid();
        if (castData.sourceArgRef.isInvalid())
            return Result::Continue;

        SmallVector<ResolvedCallArgument> resolvedArgs;
        buildStructSetResolvedArgs(sema, resolvedArgs, dstTypeRef, castData.sourceArgRef, nullptr, castData.receiverInitCstRef);

        SWC_ASSERT(castData.calledFn != nullptr);
        SWC_RESULT(SemaJIT::tryRunConstSetCall(sema, *castData.calledFn, callRef, resolvedArgs.span(), dstTypeRef, castData.receiverInitCstRef, true));
        const SemaNodeView callView(sema, callRef, SemaNodeViewPartE::Constant);
        if (callView.cstRef().isValid() &&
            sema.cstMgr().get(callView.cstRef()).typeRef() == dstTypeRef)
            outConstRef = callView.cstRef();
        return Result::Continue;
    }

    Result finalizeRuntimeStructSetCast(Sema& sema, AstNodeRef castNodeRef, const StructSetCastData& castData, TypeRef dstTypeRef)
    {
        if (castNodeRef.isInvalid() || castData.sourceArgRef.isInvalid() || sema.isGlobalScope())
            return Result::Continue;

        auto& storageSym = SemaHelpers::getOrCreateRuntimeStorageSymbol(sema, castNodeRef, sema.node(castNodeRef), "__cast_runtime_storage");
        SWC_RESULT(SemaHelpers::ensureRuntimeStorageDeclaredAndCompleted(sema, storageSym, dstTypeRef));

        SmallVector<ResolvedCallArgument> resolvedArgs;
        buildStructSetResolvedArgs(sema, resolvedArgs, dstTypeRef, castData.sourceArgRef, &storageSym, ConstantRef::invalid());

        sema.setResolvedCallArguments(castNodeRef, resolvedArgs);
        sema.setIsValue(castNodeRef);
        sema.unsetIsLValue(castNodeRef);

        auto* payload = sema.semaPayload<CastSetPayload>(castNodeRef);
        if (!payload)
        {
            payload = sema.compiler().allocate<CastSetPayload>();
            sema.setSemaPayload(castNodeRef, payload);
        }

        payload->kind               = CastSpecialOpPayloadKind::Set;
        payload->calledFn           = castData.calledFn;
        payload->receiverInitCstRef = castData.receiverInitCstRef;
        SWC_ASSERT(castData.calledFn != nullptr);
        SemaHelpers::addCurrentFunctionCallDependency(sema, castData.calledFn);
        return Result::Continue;
    }

    void setEnumUnderlyingCastNote(CastRequest& castRequest, TypeRef enumTypeRef, TypeRef underlyingTypeRef)
    {
        castRequest.failure.srcTypeRef = enumTypeRef;
        castRequest.failure.noteId     = DiagnosticId::sema_note_enum_underlying_cast;
        castRequest.failure.optTypeRef = underlyingTypeRef;
    }

    bool shouldRouteEnumViaUnderlying(const CastRequest& castRequest, const TypeInfo& srcType, const TypeInfo& dstType)
    {
        if (!srcType.isEnum())
            return false;
        if (dstType.isEnum() && castRequest.kind != CastKind::Explicit)
            return false;
        if (dstType.isAny())
            return false;

        if (dstType.isBool() && isTruthyBoolCastKind(castRequest.kind))
            return false;

        return true;
    }

    bool sameFunctionTypeRecursive(Sema& sema, TypeRef leftTypeRef, TypeRef rightTypeRef);

    TypeRef arrayFillLeafTypeRef(Sema& sema, TypeRef arrayTypeRef)
    {
        if (!arrayTypeRef.isValid())
            return TypeRef::invalid();

        TypeRef leafTypeRef = arrayTypeRef;
        while (leafTypeRef.isValid())
        {
            const TypeInfo& typeInfo = sema.typeMgr().get(leafTypeRef);
            if (!typeInfo.isArray())
                return leafTypeRef;
            leafTypeRef = typeInfo.payloadArrayElemTypeRef();
        }

        return TypeRef::invalid();
    }

    Result setupRuntimeArrayScalarFillIfNeeded(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef, ConstantRef srcConstRef, CastKind castKind, bool& outNeedsRuntimeStorage)
    {
        outNeedsRuntimeStorage = false;
        if (castKind != CastKind::Initialization)
            return Result::Continue;
        if (!srcTypeRef.isValid() || !dstTypeRef.isValid() || !srcConstRef.isValid())
            return Result::Continue;

        const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
        if (!dstType.isArray())
            return Result::Continue;
        if (srcType.isAggregate() || srcType.isArray())
            return Result::Continue;

        const TypeRef fillTypeRef = arrayFillLeafTypeRef(sema, dstTypeRef);
        if (!fillTypeRef.isValid())
            return Result::Continue;

        CastRequest fillRequest(castKind);
        fillRequest.errorNodeRef = nodeRef;
        fillRequest.setConstantFoldingSrc(srcConstRef);
        SWC_RESULT(Cast::castAllowed(sema, fillRequest, srcTypeRef, fillTypeRef));

        ConstantRef fillCstRef = fillRequest.constantFoldingResult();
        if (fillCstRef.isInvalid())
            fillCstRef = srcConstRef;
        if (fillCstRef.isInvalid())
            return Result::Continue;

        auto& payload                   = SemaHelpers::ensureCodeGenNodePayload(sema, nodeRef);
        payload.runtimeArrayFillTypeRef = fillTypeRef;
        payload.runtimeArrayFillCstRef  = fillCstRef;
        outNeedsRuntimeStorage          = true;
        return Result::Continue;
    }

    bool usingPathHasPointerStep(const SmallVector<SymbolStructUsingPathStep>& usingPath)
    {
        for (const auto& step : usingPath)
        {
            if (step.isPointer)
                return true;
        }

        return false;
    }

    Result resolveUsingStructCastPath(Sema&                                   sema,
                                      const CastRequest&                      castRequest,
                                      TypeRef                                 srcStructTypeRef,
                                      TypeRef                                 dstStructTypeRef,
                                      SmallVector<SymbolStructUsingPathStep>& outSteps,
                                      bool&                                   outFound)
    {
        outFound = false;
        outSteps.clear();

        srcStructTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), srcStructTypeRef);
        dstStructTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), dstStructTypeRef);
        if (!srcStructTypeRef.isValid() || !dstStructTypeRef.isValid())
            return Result::Continue;

        const TypeInfo& srcStructType = sema.typeMgr().get(srcStructTypeRef);
        const TypeInfo& dstStructType = sema.typeMgr().get(dstStructTypeRef);
        if (!srcStructType.isStruct() || !dstStructType.isStruct())
            return Result::Continue;

        SWC_RESULT(sema.waitSemaCompleted(&srcStructType, castRequest.errorNodeRef));
        SWC_RESULT(sema.waitSemaCompleted(&dstStructType, castRequest.errorNodeRef));

        outFound = srcStructType.payloadSymStruct().resolveUsingFieldPath(sema.ctx(), dstStructType.payloadSymStruct(), outSteps);
        return Result::Continue;
    }

    bool pointerKindsCompatible(const TypeInfo& srcType, const TypeInfo& dstType, const CastKind castKind)
    {
        if (srcType.kind() == dstType.kind())
            return true;
        if (srcType.isBlockPointer() && dstType.isValuePointer())
            return true;
        if (srcType.isValuePointer() && dstType.isBlockPointer() && castKind == CastKind::Explicit)
            return true;
        return false;
    }

    bool sameFunctionSignatureRecursive(Sema& sema, const SymbolFunction& leftFunc, const SymbolFunction& rightFunc, const bool ignoreTopLevelClosure)
    {
        if (&leftFunc == &rightFunc)
            return true;

        if (!sameFunctionTypeRecursive(sema, leftFunc.returnTypeRef(), rightFunc.returnTypeRef()))
            return false;
        if (leftFunc.callConvKind() != rightFunc.callConvKind())
            return false;
        if (!ignoreTopLevelClosure && leftFunc.isClosure() != rightFunc.isClosure())
            return false;
        if (leftFunc.isMethod() != rightFunc.isMethod())
            return false;
        if (leftFunc.isThrowable() != rightFunc.isThrowable())
            return false;
        if (leftFunc.isConst() != rightFunc.isConst())
            return false;
        if (leftFunc.hasVariadicParam() != rightFunc.hasVariadicParam())
            return false;

        const auto& leftParams  = leftFunc.parameters();
        const auto& rightParams = rightFunc.parameters();
        if (leftParams.size() != rightParams.size())
            return false;

        for (uint32_t i = 0; i < leftParams.size(); ++i)
        {
            SWC_ASSERT(leftParams[i] != nullptr);
            SWC_ASSERT(rightParams[i] != nullptr);
            if (!sameFunctionTypeRecursive(sema, leftParams[i]->typeRef(), rightParams[i]->typeRef()))
                return false;
        }

        return true;
    }

    bool sameFunctionTypeRecursive(Sema& sema, TypeRef leftTypeRef, TypeRef rightTypeRef)
    {
        if (leftTypeRef == rightTypeRef)
            return true;
        if (!leftTypeRef.isValid() || !rightTypeRef.isValid())
            return false;

        const TypeInfo& leftType  = sema.typeMgr().get(leftTypeRef);
        const TypeInfo& rightType = sema.typeMgr().get(rightTypeRef);
        if (!leftType.isFunction() || !rightType.isFunction())
            return false;

        return sameFunctionSignatureRecursive(sema, leftType.payloadSymFunction(), rightType.payloadSymFunction(), false);
    }
}

Result Cast::castIdentity(const Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    SWC_UNUSED(sema);
    SWC_UNUSED(srcTypeRef);
    SWC_UNUSED(dstTypeRef);
    if (castRequest.isConstantFolding())
        foldConstantIdentity(castRequest);
    return Result::Continue;
}

Result Cast::castBit(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    SWC_ASSERT(castRequest.kind == CastKind::Explicit);

    TaskContext&       ctx     = sema.ctx();
    const TypeManager& typeMgr = ctx.typeMgr();
    const TypeInfo*    srcType = &typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

    // In the case of an enum, we must take the underlying type
    const bool    isEnum        = srcType->isEnum();
    const TypeRef orgSrcTypeRef = srcTypeRef;
    if (isEnum)
    {
        srcTypeRef = srcType->payloadSymEnum().underlyingTypeRef();
        srcType    = &typeMgr.get(srcTypeRef);
        if (castRequest.isConstantFolding())
        {
            const ConstantValue& cst = sema.cstMgr().get(castRequest.srcConstRef);
            castRequest.srcConstRef  = cst.getEnumValue();
        }
    }

    const bool srcScalar = srcType->isScalarNumeric();
    const bool dstScalar = dstType.isScalarNumeric();
    if (!srcScalar || !dstScalar)
    {
        const Result res = castRequest.fail(DiagnosticId::sema_err_bit_cast_invalid_type, orgSrcTypeRef, dstTypeRef);
        if (isEnum)
            setEnumUnderlyingCastNote(castRequest, orgSrcTypeRef, srcTypeRef);

        return res;
    }

    const uint32_t sb          = srcType->payloadScalarNumericBits();
    const uint32_t db          = dstType.payloadScalarNumericBits();
    const bool     bothIntLike = srcType->isIntLike() && dstType.isIntLike();
    if (!(sb == db || !sb || bothIntLike))
    {
        const Result res = castRequest.fail(DiagnosticId::sema_err_bit_cast_size, orgSrcTypeRef, dstTypeRef);
        castRequest.failure.addArgument(Diagnostic::ARG_LEFT, sb);
        castRequest.failure.addArgument(Diagnostic::ARG_RIGHT, db);
        if (isEnum)
            setEnumUnderlyingCastNote(castRequest, orgSrcTypeRef, srcTypeRef);

        return res;
    }

    if (castRequest.isConstantFolding())
    {
        if (!foldConstantBitCast(sema, castRequest, dstTypeRef, dstType, *srcType))
            return Result::Error;
    }

    return Result::Continue;
}

Result Cast::castBoolToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castRequest.kind != CastKind::Explicit)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (castRequest.isConstantFolding())
    {
        if (!foldConstantBoolToIntLike(sema, castRequest, dstTypeRef))
            return Result::Error;
    }

    return Result::Continue;
}

Result Cast::castToBool(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castRequest.kind != CastKind::Explicit && !isTruthyBoolCastKind(castRequest.kind))
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
    if (!srcType.isConvertibleToBool())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (isImplicitValueBoolCastKind(castRequest.kind) && !srcType.isBool() && !srcType.isIntLike() && !srcType.isEnumFlags())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (castRequest.isConstantFolding())
    {
        const ConstantValue* cv = &sema.cstMgr().get(castRequest.constantFoldingSrc());
        if (srcType.isEnumFlags())
        {
            castRequest.setConstantFoldingSrc(cv->getEnumValue());
            cv = &sema.cstMgr().get(castRequest.constantFoldingSrc());
        }

        if (isStrictBoolExprCastKind(castRequest.kind) && srcType.isAnyString() && !cv->isNull())
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        if (cv->isNull())
            castRequest.setConstantFoldingResult(sema.cstMgr().cstFalse());
        else if (srcType.isIntLike())
        {
            if (!foldConstantIntLikeToBool(sema, castRequest))
                return Result::Error;
        }
        else if (srcType.isEnumFlags())
        {
            if (!foldConstantIntLikeToBool(sema, castRequest))
                return Result::Error;
        }
        else if (srcType.isPointerLike())
        {
            SWC_RESULT(foldConstantPointerLikeToBool(sema, castRequest, srcTypeRef));
        }
        else
            SWC_UNREACHABLE();
    }

    return Result::Continue;
}

Result Cast::castIntLikeToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType = typeMgr.get(dstTypeRef);
    const uint32_t     srcBits = srcType.payloadIntLikeBits();
    const uint32_t     dstBits = dstType.payloadIntLikeBits();

    switch (castRequest.kind)
    {
        case CastKind::LiteralSuffix:
            if (srcType.isChar())
            {
                if (!(dstType.isIntUnsigned() || dstType.isRune()))
                    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            }
            else
            {
                if (!(srcType.isInt() && (dstType.isInt() || dstType.isRune())))
                    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            }
            break;

        case CastKind::Promotion:
        case CastKind::Implicit:
        case CastKind::Parameter:
        case CastKind::Initialization:
        case CastKind::Assignment:
            if (!castRequest.isConstantFolding() || castRequest.flags.has(CastFlagsE::FoldedTypedConst))
            {
                const bool srcUnsized = srcType.isIntUnsized();
                const bool dstUnsized = dstType.isIntUnsized();
                if (!srcUnsized && !dstUnsized && srcBits && dstBits && dstBits < srcBits)
                    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            }
            break;
        case CastKind::Explicit:
            break;

        default:
            SWC_UNREACHABLE();
    }

    if (castRequest.isConstantFolding())
    {
        if (!foldConstantIntLikeToIntLike(sema, castRequest, srcTypeRef, dstTypeRef))
            return Result::Error;
    }

    return Result::Continue;
}

Result Cast::castIntLikeToFloat(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr     = sema.typeMgr();
    const TypeInfo&    srcType     = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType     = typeMgr.get(dstTypeRef);
    const uint32_t     dstBits     = dstType.payloadFloatBits();
    const uint32_t     srcBits     = srcType.payloadIntLikeBits();
    const bool         srcIsInt    = srcType.isInt();
    const bool         coerceToF32 = srcIsInt && srcBits <= 32;
    const bool         coerceToF64 = srcIsInt;
    const bool         allowCoerce = (dstBits == 32) ? coerceToF32 : coerceToF64;

    switch (castRequest.kind)
    {
        case CastKind::LiteralSuffix:
            if (!srcType.isIntUnsized())
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            break;

        case CastKind::Promotion:
        case CastKind::Implicit:
        case CastKind::Parameter:
        case CastKind::Initialization:
        case CastKind::Assignment:
            if (!allowCoerce)
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            break;
        case CastKind::Explicit:
            break;

        default:
            SWC_UNREACHABLE();
    }

    if (castRequest.isConstantFolding())
    {
        if (!foldConstantIntLikeToFloat(sema, castRequest, srcTypeRef, dstTypeRef))
            return Result::Error;
    }

    return Result::Continue;
}

Result Cast::castFloatToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castRequest.kind != CastKind::Explicit)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (castRequest.isConstantFolding())
    {
        if (!foldConstantFloatToIntLike(sema, castRequest, srcTypeRef, dstTypeRef))
            return Result::Error;
    }

    return Result::Continue;
}

Result Cast::castToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);

    if (srcType.isBool())
        return castBoolToIntLike(sema, castRequest, srcTypeRef, dstTypeRef);
    if (srcType.isIntLike())
        return castIntLikeToIntLike(sema, castRequest, srcTypeRef, dstTypeRef);
    if (srcType.isFloat())
        return castFloatToIntLike(sema, castRequest, srcTypeRef, dstTypeRef);

    if (castRequest.kind == CastKind::Explicit)
    {
        // From pointer
        if (srcType.isAnyPointer() && dstTypeRef == sema.typeMgr().typeU64())
        {
            if (castRequest.isConstantFolding())
            {
                if (!foldConstantPointerToIntLike(sema, castRequest, dstTypeRef))
                    return Result::Error;
            }
            return Result::Continue;
        }
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castFloatToFloat(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

    const uint32_t sb        = srcType.payloadFloatBits();
    const uint32_t db        = dstType.payloadFloatBits();
    const bool     narrowing = db < sb;

    switch (castRequest.kind)
    {
        case CastKind::LiteralSuffix:
            break;

        case CastKind::Promotion:
            break;

        case CastKind::Implicit:
        case CastKind::Parameter:
        case CastKind::Initialization:
        case CastKind::Assignment:
            if (narrowing && castRequest.kind != CastKind::Parameter)
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            break;

        case CastKind::Explicit:
            break;

        default:
            SWC_UNREACHABLE();
    }

    if (castRequest.isConstantFolding())
    {
        if (!foldConstantFloatToFloat(sema, castRequest, srcTypeRef, dstTypeRef))
            return Result::Error;
    }

    return Result::Continue;
}

Result Cast::castToFloat(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);

    if (srcType.isFloat())
        return castFloatToFloat(sema, castRequest, srcTypeRef, dstTypeRef);
    if (srcType.isIntLike())
        return castIntLikeToFloat(sema, castRequest, srcTypeRef, dstTypeRef);

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToEnum(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castRequest.kind != CastKind::Explicit)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    const TypeInfo& dstType           = sema.typeMgr().get(dstTypeRef);
    const TypeRef   underlyingTypeRef = dstType.payloadSymEnum().underlyingTypeRef();

    CastRequest underlyingRequest(castRequest.kind);
    underlyingRequest.flags        = castRequest.flags;
    underlyingRequest.errorNodeRef = castRequest.errorNodeRef;
    underlyingRequest.errorCodeRef = castRequest.errorCodeRef;
    underlyingRequest.setConstantFoldingSrc(castRequest.constantFoldingSrc());

    const Result res = castAllowed(sema, underlyingRequest, srcTypeRef, underlyingTypeRef);
    if (res != Result::Continue)
    {
        castRequest.failure = underlyingRequest.failure;
        setEnumUnderlyingCastNote(castRequest, dstTypeRef, underlyingTypeRef);
        return res;
    }

    if (underlyingRequest.constantFoldingResult().isValid())
    {
        const ConstantValue enumCst = ConstantValue::makeEnumValue(sema.ctx(), underlyingRequest.constantFoldingResult(), dstTypeRef);
        castRequest.setConstantFoldingResult(sema.cstMgr().addConstant(sema.ctx(), enumCst));
    }

    return Result::Continue;
}

Result Cast::castFromEnum(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castRequest.kind != CastKind::Explicit)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    const TypeInfo&   srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo&   dstType = sema.typeMgr().get(dstTypeRef);
    const SymbolEnum& enumSym = srcType.payloadSymEnum();

    // Only enum flags (or enums already backed by bool) can be cast to bool.
    if (dstType.isBool() && !srcType.isEnumFlags() && enumSym.underlyingTypeRef() != dstTypeRef)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (castRequest.isConstantFolding())
    {
        const ConstantValue& cst = sema.cstMgr().get(castRequest.srcConstRef);
        if (cst.isEnumValue())
            castRequest.srcConstRef = cst.getEnumValue();
    }

    const TypeRef dstUnderlyingTypeRef = dstType.isEnum() ? dstType.payloadSymEnum().underlyingTypeRef() : dstTypeRef;
    const auto    res                  = castAllowed(sema, castRequest, enumSym.underlyingTypeRef(), dstUnderlyingTypeRef);
    if (res != Result::Continue)
    {
        setEnumUnderlyingCastNote(castRequest, srcTypeRef, enumSym.underlyingTypeRef());
        return res;
    }

    return Result::Continue;
}

Result Cast::castFromNull(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
    if (dstType.isPointerLike())
        return Result::Continue;

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castFromUndefined(const Sema& sema, const CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    SWC_UNUSED(sema);
    SWC_UNUSED(castRequest);
    SWC_UNUSED(srcTypeRef);
    SWC_UNUSED(dstTypeRef);
    return Result::Continue;
}

Result Cast::castFromReference(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeRef valueTypeRef = referenceValueCastTypeRef(sema, srcTypeRef, dstTypeRef);
    if (!valueTypeRef.isValid())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (!castRequest.isConstantFolding())
        return Result::Continue;

    const ConstantRef valueCstRef = readReferenceValueConstant(sema, castRequest.constantFoldingSrc(), valueTypeRef);
    if (!valueCstRef.isValid())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    castRequest.setConstantFoldingResult(valueCstRef);
    return Result::Continue;
}

Result Cast::castToReference(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    TypeManager&    typeMgr = sema.typeMgr();
    const TypeInfo& srcType = typeMgr.get(srcTypeRef);
    const TypeInfo& dstType = typeMgr.get(dstTypeRef);

    const auto      dstPointeeTypeRef = dstType.payloadTypeRef();
    const TypeInfo& dstPointeeType    = typeMgr.get(dstPointeeTypeRef);

    // Ref to ref
    if (srcType.isReference())
    {
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        const auto      srcPointeeTypeRef = srcType.payloadTypeRef();
        const TypeInfo& srcPointeeType    = typeMgr.get(srcPointeeTypeRef);

        if (srcPointeeTypeRef == dstPointeeTypeRef)
            return Result::Continue;

        // Struct ref to interface ref
        if (srcPointeeType.isStruct() && dstPointeeType.isInterface())
        {
            const auto& fromStruct = srcPointeeType.payloadSymStruct();
            const auto& toItf      = dstPointeeType.payloadSymInterface();
            if (fromStruct.implementsInterfaceOrUsingFields(sema, toItf))
                return Result::Continue;
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_to_interface, srcTypeRef, dstTypeRef);
        }

        SmallVector<SymbolStructUsingPathStep> usingPath;
        bool                                   hasUsingPath = false;
        SWC_RESULT(resolveUsingStructCastPath(sema, castRequest, srcPointeeTypeRef, dstPointeeTypeRef, usingPath, hasUsingPath));
        if (hasUsingPath && !usingPathHasPointerStep(usingPath))
            return Result::Continue;
    }

    // Pointer to ref
    if (srcType.isAnyPointer())
    {
        if (srcType.isNullable())
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        if (srcType.payloadTypeRef() == dstPointeeTypeRef)
            return Result::Continue;

        SmallVector<SymbolStructUsingPathStep> usingPath;
        bool                                   hasUsingPath = false;
        SWC_RESULT(resolveUsingStructCastPath(sema, castRequest, srcType.payloadTypeRef(), dstPointeeTypeRef, usingPath, hasUsingPath));
        if (hasUsingPath && !usingPathHasPointerStep(usingPath))
            return Result::Continue;
    }

    // Value to const ref
    if (srcType.isStruct() && dstType.isConst())
    {
        if (dstPointeeTypeRef == srcTypeRef)
        {
            if (castRequest.isConstantFolding())
            {
                const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
                SWC_ASSERT(srcCst.isStruct());
                const uint64_t      ptr    = reinterpret_cast<uint64_t>(srcCst.getStruct().data());
                const ConstantValue refCst = ConstantValue::makeValuePointer(sema.ctx(), dstPointeeTypeRef, ptr, dstType.flags());
                castRequest.setConstantFoldingResult(sema.cstMgr().addConstant(sema.ctx(), refCst));
            }

            return Result::Continue;
        }

        SmallVector<SymbolStructUsingPathStep> usingPath;
        bool                                   hasUsingPath = false;
        SWC_RESULT(resolveUsingStructCastPath(sema, castRequest, srcTypeRef, dstPointeeTypeRef, usingPath, hasUsingPath));
        if (hasUsingPath && !usingPathHasPointerStep(usingPath))
            return Result::Continue;
    }

    // UFCS receiver: allow taking the address to bind a value to a reference.
    // Whether the value is actually addressable (lvalue) is validated later by `Cast::cast`.
    if (castRequest.flags.has(CastFlagsE::UfcsArgument) && srcType.isStruct())
    {
        bool receiverMatches = dstPointeeTypeRef == srcTypeRef;
        if (!receiverMatches)
        {
            SmallVector<SymbolStructUsingPathStep> usingPath;
            bool                                   hasUsingPath = false;
            SWC_RESULT(resolveUsingStructCastPath(sema, castRequest, srcTypeRef, dstPointeeTypeRef, usingPath, hasUsingPath));
            receiverMatches = hasUsingPath && !usingPathHasPointerStep(usingPath);
        }
        if (!receiverMatches)
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        const bool sourceIsConst = srcType.isConst() || castRequest.isConstantFolding();
        if (sourceIsConst && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        if (castRequest.isConstantFolding())
        {
            const uint64_t valueSize = srcType.sizeOf(sema.ctx());
            uint64_t       ptr       = 0;
            if (valueSize)
            {
                std::vector valueBytes(valueSize, std::byte{0});
                SWC_RESULT(ConstantLower::lowerToBytes(sema, asByteSpan(valueBytes), castRequest.constantFoldingSrc(), srcTypeRef));
                const std::string_view rawValueData = sema.cstMgr().addPayloadBuffer(asStringView(asByteSpan(valueBytes)));
                ptr                                 = reinterpret_cast<uint64_t>(rawValueData.data());
            }

            const ConstantValue refCst = ConstantValue::makeValuePointer(sema.ctx(), dstPointeeTypeRef, ptr, dstType.flags());
            castRequest.setConstantFoldingResult(sema.cstMgr().addConstant(sema.ctx(), refCst));
        }

        return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castPointerToPointer(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

    const bool sameUnderlying = srcType.payloadTypeRef() == dstType.payloadTypeRef();
    const bool srcIsVoid      = srcType.payloadTypeRef() == typeMgr.typeVoid();
    const bool dstIsVoid      = dstType.payloadTypeRef() == typeMgr.typeVoid();
    if (sameUnderlying || srcIsVoid || dstIsVoid || castRequest.kind == CastKind::Explicit)
    {
        bool ok = pointerKindsCompatible(srcType, dstType, castRequest.kind);
        // TODO @legacy
        if (!ok && (sameUnderlying || srcIsVoid || dstIsVoid))
            ok = true;

        if (ok)
        {
            // TODO @legacy
            if (dstType.unwrap(sema.ctx(), TypeRef::invalid(), TypeExpandE::Pointer) == typeMgr.typeVoid())
            {
            }
            else if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            {
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);
            }

            return Result::Continue;
        }
    }

    if (pointerKindsCompatible(srcType, dstType, castRequest.kind))
    {
        SmallVector<SymbolStructUsingPathStep> usingPath;
        bool                                   hasUsingPath = false;
        SWC_RESULT(resolveUsingStructCastPath(sema, castRequest, srcType.payloadTypeRef(), dstType.payloadTypeRef(), usingPath, hasUsingPath));
        if (hasUsingPath && !usingPathHasPointerStep(usingPath))
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            return Result::Continue;
        }
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToPointer(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    TaskContext&       ctx     = sema.ctx();
    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

    // UFCS receiver: allow taking the address to get a pointer.
    // Whether the value is actually addressable (lvalue) is validated later by `Cast::cast`.
    if (castRequest.flags.has(CastFlagsE::UfcsArgument) && dstType.payloadTypeRef() == srcTypeRef && !dstType.isNullable())
    {
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        return Result::Continue;
    }

    if (srcType.isReference())
    {
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        const TypeRef dstPointeeTypeRef = dstType.payloadTypeRef();
        if (srcType.payloadTypeRef() == dstPointeeTypeRef || dstPointeeTypeRef == typeMgr.typeVoid())
            return Result::Continue;

        SmallVector<SymbolStructUsingPathStep> usingPath;
        bool                                   hasUsingPath = false;
        SWC_RESULT(resolveUsingStructCastPath(sema, castRequest, srcType.payloadTypeRef(), dstPointeeTypeRef, usingPath, hasUsingPath));
        if (hasUsingPath && !usingPathHasPointerStep(usingPath))
            return Result::Continue;
    }

    if (srcType.isAnyPointer())
    {
        const TypeInfo& srcPointeeType = typeMgr.get(srcType.payloadTypeRef());
        if (srcPointeeType.isArray() && srcPointeeType.payloadArrayElemTypeRef() == dstType.payloadTypeRef())
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            return Result::Continue;
        }

        if (srcPointeeType.isReference() && srcPointeeType.payloadTypeRef() == dstType.payloadTypeRef())
        {
            bool ok = false;
            if (srcType.kind() == dstType.kind())
                ok = true;
            else if (srcType.isBlockPointer() && dstType.isValuePointer())
                ok = true;
            else if (srcType.isValuePointer() && dstType.isBlockPointer() && castRequest.kind == CastKind::Explicit)
                ok = true;

            if (ok)
            {
                if ((srcType.isConst() || srcPointeeType.isConst()) && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                    return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

                return Result::Continue;
            }
        }

        return castPointerToPointer(sema, castRequest, srcTypeRef, dstTypeRef);
    }

    if (srcType.isString())
    {
        const TypeRef dstPointeeTypeRef = dstType.payloadTypeRef();
        if (castRequest.kind == CastKind::Explicit &&
            dstType.isConst() &&
            (dstPointeeTypeRef == typeMgr.typeU8() || dstPointeeTypeRef == typeMgr.typeVoid()))
        {
            if (castRequest.isConstantFolding())
            {
                const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
                SWC_ASSERT(srcCst.isString());
                const uint64_t ptrValue = reinterpret_cast<uint64_t>(srcCst.getString().data());

                ConstantValue ptrCst;
                if (dstType.isBlockPointer())
                    ptrCst = ConstantValue::makeBlockPointer(ctx, dstPointeeTypeRef, ptrValue, dstType.flags());
                else
                    ptrCst = ConstantValue::makeValuePointer(ctx, dstPointeeTypeRef, ptrValue, dstType.flags());

                castRequest.setConstantFoldingResult(sema.cstMgr().addConstant(ctx, ptrCst));
            }

            return Result::Continue;
        }
    }

    if (srcType.isTypeInfo())
    {
        if (castRequest.kind == CastKind::Explicit)
        {
            if (dstTypeRef == sema.typeMgr().typeConstValuePtrU8() ||
                dstTypeRef == sema.typeMgr().typeConstValuePtrVoid())
            {
                return Result::Continue;
            }
        }
    }

    if (srcTypeRef == sema.typeMgr().typeU64())
    {
        if (castRequest.kind == CastKind::Explicit)
        {
            if (castRequest.isConstantFolding())
            {
                if (!foldConstantIntLikeToPointer(sema, castRequest, dstTypeRef))
                    return Result::Error;
            }
            return Result::Continue;
        }
    }

    if (srcType.isArray())
    {
        const auto srcElemTypeRef = srcType.payloadArrayElemTypeRef();
        const auto dstElemTypeRef = dstType.payloadTypeRef();

        if (castRequest.kind == CastKind::Explicit ||
            srcElemTypeRef == dstElemTypeRef ||
            dstElemTypeRef == sema.typeMgr().typeVoid())
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            return Result::Continue;
        }
    }

    // TODO @legacy (for parameters of type struct, which in fact are references)
    if (srcType.isStruct())
    {
        const auto dstElemTypeRef = dstType.payloadTypeRef();
        if (srcTypeRef == dstElemTypeRef || dstElemTypeRef == typeMgr.typeVoid())
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            return Result::Continue;
        }
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToSlice(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    TaskContext&    ctx     = sema.ctx();
    TypeManager&    typeMgr = sema.typeMgr();
    const TypeInfo& srcType = typeMgr.get(srcTypeRef);
    const TypeInfo& dstType = typeMgr.get(dstTypeRef);

    // String -> const [..] u8
    if (srcType.isString())
    {
        if (dstType.isConst() && dstType.payloadTypeRef() == typeMgr.typeU8())
        {
            if (castRequest.isConstantFolding())
            {
                const ConstantValue&   cst  = sema.cstMgr().get(castRequest.srcConstRef);
                const std::string_view str  = cst.getString();
                const ByteSpan         span = asByteSpan(str);
                const ConstantValue    cv   = ConstantValue::makeSlice(ctx, dstType.payloadTypeRef(), span, TypeInfoFlagsE::Const);
                castRequest.outConstRef     = sema.cstMgr().addConstant(sema.ctx(), cv);
            }

            return Result::Continue;
        }
    }

    if (srcType.isArray())
    {
        const auto srcElemTypeRef = srcType.payloadArrayElemTypeRef();
        const auto dstElemTypeRef = dstType.payloadTypeRef();

        if (castRequest.kind == CastKind::Explicit || srcElemTypeRef == dstElemTypeRef)
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            if (srcElemTypeRef != dstElemTypeRef)
            {
                const TypeInfo& dstElemType = sema.typeMgr().get(dstElemTypeRef);
                const uint64_t  s           = dstElemType.sizeOf(ctx);
                const uint64_t  d           = srcType.sizeOf(ctx);
                const bool      match       = s == 0 || (d / s * s == d);
                if (!match)
                    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            }

            if (castRequest.isConstantFolding())
            {
                const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
                SWC_ASSERT(srcCst.isArray());
                const TypeInfo&     dstElemType = sema.typeMgr().get(dstElemTypeRef);
                const uint64_t      sliceCount  = sliceCountFromArrayCast(ctx, srcType, dstElemType);
                const ConstantValue sliceCst    = ConstantValue::makeSliceCounted(ctx, dstElemTypeRef, srcCst.getArray(), sliceCount, dstType.flags());
                castRequest.outConstRef         = sema.cstMgr().addConstant(sema.ctx(), sliceCst);
            }

            return Result::Continue;
        }
    }

    if (srcType.isAggregateArray())
    {
        const auto dstElemTypeRef = dstType.payloadTypeRef();
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        const auto& srcElemTypes = srcType.payloadAggregate().types;
        for (const TypeRef srcElemTypeRef : srcElemTypes)
        {
            CastRequest  elemRequest = makeNestedCastRequest(castRequest);
            const Result res         = castAllowed(sema, elemRequest, srcElemTypeRef, dstElemTypeRef);
            if (res != Result::Continue)
            {
                castRequest.failure = elemRequest.failure;
                return res;
            }
        }

        if (!castRequest.isConstantFolding())
            return Result::Continue;

        const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
        SWC_ASSERT(srcCst.isAggregateArray());

        const auto& srcValues = srcCst.getAggregateArray();
        SWC_ASSERT(srcValues.size() == srcElemTypes.size());

        std::vector<ConstantRef> castedValues;
        castedValues.reserve(srcValues.size());
        for (size_t i = 0; i < srcValues.size(); ++i)
        {
            CastRequest elemRequest = makeNestedCastRequest(castRequest);
            elemRequest.setConstantFoldingSrc(srcValues[i]);
            const Result res = castAllowed(sema, elemRequest, srcElemTypes[i], dstElemTypeRef);
            if (res != Result::Continue)
            {
                castRequest.failure = elemRequest.failure;
                return res;
            }

            ConstantRef castedRef = elemRequest.constantFoldingResult();
            if (castedRef.isInvalid())
                castedRef = srcValues[i];
            castedValues.push_back(castedRef);
        }

        SmallVector4<uint64_t> arrayDims;
        arrayDims.push_back(srcValues.size());
        const TypeRef   arrayTypeRef = sema.typeMgr().addType(TypeInfo::makeArray(arrayDims, dstElemTypeRef));
        const TypeInfo& arrayType    = sema.typeMgr().get(arrayTypeRef);

        const uint64_t         arraySize = arrayType.sizeOf(ctx);
        std::vector<std::byte> arrayData(arraySize);
        const ByteSpanRW       arraySpan = asByteSpan(arrayData);
        SWC_RESULT(ConstantLower::lowerAggregateArrayToBytes(sema, arraySpan, arrayType, castedValues));

        const ConstantValue sliceCst = ConstantValue::makeSliceCounted(ctx, dstElemTypeRef, arraySpan, srcValues.size(), dstType.flags());
        castRequest.outConstRef      = sema.cstMgr().addConstant(sema.ctx(), sliceCst);
        return Result::Continue;
    }

    // void* -> slice (explicit only)
    if (srcType.isAnyPointer() && srcType.payloadTypeRef() == sema.typeMgr().typeVoid())
    {
        if (castRequest.kind == CastKind::Explicit)
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            return Result::Continue;
        }
    }

    // slice -> slice
    if (srcType.isSlice())
    {
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        if (castRequest.kind == CastKind::Explicit || srcType.payloadTypeRef() == dstType.payloadTypeRef())
            return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castFromTypeValue(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
    if (dstType.isAnyTypeInfo(sema.ctx()))
    {
        if (castRequest.isConstantFolding())
        {
            const auto cst = sema.cstMgr().get(castRequest.srcConstRef);
            SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, castRequest.outConstRef, cst.getTypeValue(), castRequest.errorNodeRef));
        }

        return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToFromTypeInfo(const Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    SWC_UNUSED(sema);
    SWC_UNUSED(srcTypeRef);
    SWC_UNUSED(dstTypeRef);

    if (castRequest.isConstantFolding())
        castRequest.outConstRef = castRequest.srcConstRef;

    return Result::Continue;
}

Result Cast::castToFunction(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

    if (srcType.isFunction())
    {
        const SymbolFunction& srcFunc = srcType.payloadSymFunction();
        const SymbolFunction& dstFunc = dstType.payloadSymFunction();
        if (sameFunctionSignatureRecursive(sema, srcFunc, dstFunc, false))
            return Result::Continue;
        if (!srcFunc.isClosure() && dstFunc.isClosure() && sameFunctionSignatureRecursive(sema, srcFunc, dstFunc, true))
            return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToString(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const auto&        srcType = typeMgr.get(srcTypeRef);
    if (srcType.isSlice())
    {
        if (castRequest.kind != CastKind::Explicit)
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        if (srcType.payloadTypeRef() != typeMgr.typeU8())
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        return Result::Continue;
    }

    if (srcType.isArray())
    {
        if (srcType.payloadArrayElemTypeRef() == typeMgr.typeU8() && srcType.payloadArrayDims().size() == 1)
            return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToCString(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const auto&        srcType = typeMgr.get(srcTypeRef);

    if (srcType.isBlockPointer())
    {
        if (srcType.payloadTypeRef() == sema.typeMgr().typeU8())
            return Result::Continue;
    }

    if (srcType.isArray())
    {
        if (srcType.payloadArrayElemTypeRef() == typeMgr.typeU8() && srcType.payloadArrayDims().size() == 1)
            return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToAny(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (!castRequest.isConstantFolding())
        return Result::Continue;

    TaskContext&       ctx        = sema.ctx();
    const TypeManager& typeMgr    = sema.typeMgr();
    ConstantRef        srcCstRef  = castRequest.srcConstRef;
    TypeRef            anyTypeRef = srcTypeRef;
    const TypeInfo*    srcType    = &typeMgr.get(anyTypeRef);

    if (srcType->isIntUnsized() || srcType->isFloatUnsized())
    {
        ConstantRef          concreteCstRef;
        const TypeInfo::Sign hintSign = srcType->isIntUnsized() ? TypeInfo::Sign::Signed : TypeInfo::Sign::Unknown;
        if (!concretizeConstant(sema, concreteCstRef, srcCstRef, hintSign))
        {
            castRequest.fail(DiagnosticId::sema_err_literal_too_big, sema.cstMgr().get(srcCstRef).typeRef(), TypeRef::invalid());
            return Result::Error;
        }

        srcCstRef  = concreteCstRef;
        anyTypeRef = sema.cstMgr().get(concreteCstRef).typeRef();
        srcType    = &typeMgr.get(anyTypeRef);
        castRequest.setConstantFoldingSrc(concreteCstRef);
    }

    if (srcType->isChar())
    {
        const ConstantValue runeCst = ConstantValue::makeRune(ctx, sema.cstMgr().get(srcCstRef).getChar());
        srcCstRef                   = sema.cstMgr().addConstant(ctx, runeCst);
        anyTypeRef                  = typeMgr.typeRune();
        srcType                     = &typeMgr.get(anyTypeRef);
        castRequest.setConstantFoldingSrc(srcCstRef);
    }

    const ConstantValue& srcCst = sema.cstMgr().get(srcCstRef);

    ConstantRef typeInfoCstRef = ConstantRef::invalid();
    SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, typeInfoCstRef, anyTypeRef, castRequest.errorNodeRef));
    const ConstantValue& typeInfoCst = sema.cstMgr().get(typeInfoCstRef);
    SWC_ASSERT(typeInfoCst.isValuePointer());
    DataSegmentRef typeInfoRef;
    const bool     hasTypeInfoRef = sema.cstMgr().resolveConstantDataSegmentRef(typeInfoRef, typeInfoCstRef, reinterpret_cast<const void*>(typeInfoCst.getValuePointer()));
    SWC_ASSERT(hasTypeInfoRef);
    if (!hasTypeInfoRef)
        return Result::Error;

    DataSegment& segment            = sema.cstMgr().shardDataSegment(typeInfoRef.shardIndex);
    const auto [anyOffset, storage] = segment.reserveBytes(sizeof(Runtime::Any), alignof(Runtime::Any), true);
    auto* const runtimeAny          = reinterpret_cast<Runtime::Any*>(storage);
    runtimeAny->type                = segment.ptr<Runtime::TypeInfo>(typeInfoRef.offset);
    segment.addRelocation(anyOffset + offsetof(Runtime::Any, type), typeInfoRef.offset);

    if (!srcCst.isNull())
    {
        const uint64_t valueSize = srcType->sizeOf(ctx);
        SWC_ASSERT(valueSize <= std::numeric_limits<uint32_t>::max());

        if (valueSize)
        {
            std::vector valueBytes(valueSize, std::byte{0});
            SWC_RESULT(ConstantLower::lowerToBytes(sema, valueBytes, srcCstRef, anyTypeRef));

            uint32_t valueOffset = INVALID_REF;
            SWC_RESULT(ConstantLower::materializeStaticPayload(valueOffset, sema, segment, anyTypeRef, ByteSpan{valueBytes.data(), valueBytes.size()}));
            runtimeAny->value = segment.ptr<std::byte>(valueOffset);
            segment.addRelocation(anyOffset + offsetof(Runtime::Any, value), valueOffset);
        }
    }

    ConstantValue anyCst = ConstantValue::makeStructBorrowed(ctx, dstTypeRef, ByteSpan{storage, sizeof(Runtime::Any)});
    anyCst.setDataSegmentRef({.shardIndex = typeInfoRef.shardIndex, .offset = anyOffset});
    castRequest.setConstantFoldingResult(sema.cstMgr().addMaterializedPayloadConstant(anyCst));
    return Result::Continue;
}

Result Cast::castToVariadic(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const auto&        dstType = typeMgr.get(dstTypeRef);

    if (dstType.isVariadic())
        return Result::Continue;

    if (dstType.isTypedVariadic())
        return castAllowed(sema, castRequest, srcTypeRef, dstType.payloadTypeRef());

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToInterface(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

    if (srcType.isStruct())
    {
        const SymbolStruct& fromStruct = srcType.payloadSymStruct();
        SWC_RESULT(sema.waitSemaCompleted(&srcType, castRequest.errorNodeRef));
        const SymbolInterface& toItf = dstType.payloadSymInterface();
        if (fromStruct.implementsInterfaceOrUsingFields(sema, toItf))
            return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast_to_interface, srcTypeRef, dstTypeRef);
}

Result Cast::castFromAny(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castRequest.kind != CastKind::Explicit)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (!castRequest.isConstantFolding())
        return Result::Continue;

    TaskContext&         ctx    = sema.ctx();
    const ConstantValue& anyCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
    if (!anyCst.isStruct())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    const ByteSpan anyBytes = anyCst.getStruct();
    if (anyBytes.size() != sizeof(Runtime::Any))
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    Runtime::Any runtimeAny{};
    std::memcpy(&runtimeAny, anyBytes.data(), sizeof(runtimeAny));

    const TypeRef valueTypeRef = sema.typeGen().getBackTypeRef(runtimeAny.type);
    if (!valueTypeRef.isValid())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    ConstantRef valueCstRef = ConstantRef::invalid();
    if (!runtimeAny.value)
    {
        valueCstRef = sema.cstMgr().cstNull();
    }
    else
    {
        const TypeInfo& valueType = sema.typeMgr().get(valueTypeRef);

        if (valueType.isEnum())
        {
            const TypeRef       underlyingTypeRef = valueType.payloadSymEnum().underlyingTypeRef();
            const ConstantValue underlyingCst     = ConstantValue::make(ctx, runtimeAny.value, underlyingTypeRef, ConstantValue::PayloadOwnership::Borrowed);
            if (!underlyingCst.isValid())
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

            const ConstantRef   underlyingCstRef = sema.cstMgr().addConstant(ctx, underlyingCst);
            const ConstantValue enumCst          = ConstantValue::makeEnumValue(ctx, underlyingCstRef, valueTypeRef);
            valueCstRef                          = sema.cstMgr().addConstant(ctx, enumCst);
        }
        else if (valueType.isAnyTypeInfo(ctx))
        {
            const uint64_t ptrValue = reinterpret_cast<uint64_t>(runtimeAny.value);
            ConstantValue  typeCst  = ConstantValue::makeValuePointer(ctx, sema.typeMgr().structTypeInfo(), ptrValue, TypeInfoFlagsE::Const);
            typeCst.setTypeRef(valueTypeRef);
            valueCstRef = sema.cstMgr().addConstant(ctx, typeCst);
        }
        else
        {
            const ConstantValue valueCst = ConstantValue::make(ctx, runtimeAny.value, valueTypeRef, ConstantValue::PayloadOwnership::Borrowed);
            if (!valueCst.isValid())
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            valueCstRef = sema.cstMgr().addConstant(ctx, valueCst);
        }
    }

    CastRequest castFromAnyRequest(CastKind::Explicit);
    castFromAnyRequest.flags        = castRequest.flags;
    castFromAnyRequest.errorNodeRef = castRequest.errorNodeRef;
    castFromAnyRequest.errorCodeRef = castRequest.errorCodeRef;
    castFromAnyRequest.setConstantFoldingSrc(valueCstRef);

    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
    if ((dstType.isReference() || dstType.isMoveReference() || dstType.isAnyPointer()) &&
        dstType.isConst() &&
        dstType.payloadTypeRef() == valueTypeRef)
    {
        SWC_RESULT(constantFoldPointerLikeFromValue(sema, valueCstRef, valueTypeRef, dstTypeRef, castRequest.outConstRef));
        return Result::Continue;
    }

    const Result result = castAllowed(sema, castFromAnyRequest, valueTypeRef, dstTypeRef);
    if (result != Result::Continue)
    {
        if (result == Result::Error)
            castRequest.failure = castFromAnyRequest.failure;
        return result;
    }

    castRequest.setConstantFoldingResult(castFromAnyRequest.constantFoldingResult());
    return Result::Continue;
}

Result Cast::castAllowed(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    castRequest.selectedStructOpCast = nullptr;

    UserDefinedLiteralSuffixInfo suffixInfo;
    const bool                   hasUserDefinedLiteralSuffix = dstTypeRef.isValid() && resolveUserDefinedLiteralSuffix(sema, castRequest.errorNodeRef, suffixInfo);
    TypeRef                      literalSuffixDstTypeRef     = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), dstTypeRef);
    if (!literalSuffixDstTypeRef.isValid())
        literalSuffixDstTypeRef = dstTypeRef;
    if (hasUserDefinedLiteralSuffix &&
        !castRequest.flags.has(CastFlagsE::LiteralSuffixConsume) &&
        !sema.typeMgr().get(literalSuffixDstTypeRef).isStruct())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (srcTypeRef == dstTypeRef)
        return castIdentity(sema, castRequest, srcTypeRef, dstTypeRef);

    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

    if (isImplicitNullableQualificationCast(srcType, dstType))
        return castAddNullableQualifier(castRequest);

    if (srcType.isAlias() || dstType.isAlias())
    {
        const TypeRef   resolvedSrcTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), srcTypeRef);
        const TypeRef   resolvedDstTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), dstTypeRef);
        const TypeInfo& resolvedSrcType    = sema.typeMgr().get(resolvedSrcTypeRef);
        const TypeInfo& resolvedDstType    = sema.typeMgr().get(resolvedDstTypeRef);

        const bool allowAliasBoolCast = isTruthyBoolCastKind(castRequest.kind) && dstType.isBool();
        const bool allowAliasNullCast = resolvedSrcType.isNull() && resolvedDstType.isPointerLike();
        if (castRequest.kind != CastKind::Explicit && !allowAliasBoolCast && !allowAliasNullCast)
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
    }

    auto res = Result::Error;
    if (srcType.isAlias())
        res = castAllowed(sema, castRequest, srcType.payloadSymAlias().underlyingTypeRef(), dstTypeRef);
    else if (srcType.isAny())
        res = castFromAny(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isAlias())
        res = castAllowed(sema, castRequest, srcTypeRef, dstType.payloadSymAlias().underlyingTypeRef());
    else if (referenceValueCastTypeRef(sema, srcTypeRef, dstTypeRef).isValid())
        res = castFromReference(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (castRequest.flags.has(CastFlagsE::BitCast))
        res = castBit(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (shouldRouteEnumViaUnderlying(castRequest, srcType, dstType))
        res = castFromEnum(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (srcType.isNull())
        res = castFromNull(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (srcType.isUndefined())
        res = castFromUndefined(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isEnum())
        res = castToEnum(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isBool())
        res = castToBool(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isIntLike())
        res = castToIntLike(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isFloat())
        res = castToFloat(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (srcType.isTypeValue())
        res = castFromTypeValue(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (srcType.isAnyTypeInfo(sema.ctx()) && dstType.isAnyTypeInfo(sema.ctx()))
        res = castToFromTypeInfo(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isFunction())
        res = castToFunction(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isArray())
        res = castToArray(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isSlice())
        res = castToSlice(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isAnyPointer())
        res = castToPointer(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isAny())
        res = castToAny(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isReference())
        res = castToReference(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isInterface())
        res = castToInterface(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isAnyVariadic())
        res = castToVariadic(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isString())
        res = castToString(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isCString())
        res = castToCString(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isStruct())
        res = castToStruct(sema, castRequest, srcTypeRef, dstTypeRef);
    else
    {
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
    }

    if (res != Result::Continue && srcType.isStruct())
    {
        SymbolFunction*     calledFn = nullptr;
        const SourceCodeRef codeRef  = castRequest.errorCodeRef.isValid() ? castRequest.errorCodeRef : castRequest.errorNodeRef.isValid() ? sema.node(castRequest.errorNodeRef).codeRef()
                                                                                                                                          : sema.node(sema.curNodeRef()).codeRef();
        SWC_RESULT(resolveStructOpCastCandidate(sema, codeRef, srcTypeRef, dstTypeRef, castRequest.kind, calledFn, castRequest.errorNodeRef));
        if (calledFn)
        {
            castRequest.selectedStructOpCast = calledFn;
            return Result::Continue;
        }
    }

    if (res == Result::Continue &&
        castRequest.isConstantFolding() &&
        castRequest.outConstRef.isValid())
    {
        ConstantValue resCst = sema.cstMgr().get(castRequest.outConstRef);
        if (resCst.typeRef() != dstTypeRef)
        {
            resCst.setTypeRef(dstTypeRef);
            castRequest.outConstRef = sema.cstMgr().addConstant(sema.ctx(), resCst);
        }
    }

    return res;
}

TypeRef Cast::castAllowedBothWays(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castAllowed(sema, castRequest, srcTypeRef, dstTypeRef) == Result::Continue)
        return dstTypeRef;
    if (castAllowed(sema, castRequest, dstTypeRef, srcTypeRef) == Result::Continue)
        return srcTypeRef;
    return TypeRef::invalid();
}

TypeRef Cast::castAllowedBothWays(Sema& sema, TypeRef srcTypeRef, TypeRef dstTypeRef, CastKind castKind)
{
    CastRequest castRequest(castKind);
    return castAllowedBothWays(sema, castRequest, srcTypeRef, dstTypeRef);
}

Result Cast::cast(Sema& sema, SemaNodeView& view, TypeRef dstTypeRef, CastKind castKind, CastFlags castFlags, const DiagnosticArguments* errorArguments)
{
    CastKind      effectiveKind  = castKind;
    CastFlags     effectiveFlags = castFlags;
    const TypeRef srcTypeRef     = view.typeRef();
    const auto    srcCstRef      = view.cstRef();

    // `cast()` is an explicit user request to allow explicit casts later when the destination type becomes known.
    // Therefore, when we are about to apply a contextual cast on an `AutoCastExpr`, force the cast to be explicit
    // and apply its modifiers.
    SWC_ASSERT(view.node() != nullptr);
    if (view.node()->is(AstNodeId::AutoCastExpr))
    {
        const auto& autoCast = view.node()->cast<AstAutoCastExpr>();
        effectiveKind        = CastKind::Explicit;
        if (autoCast.modifierFlags.has(AstModifierFlagsE::Bit))
            effectiveFlags.add(CastFlagsE::BitCast);
        if (autoCast.modifierFlags.has(AstModifierFlagsE::UnConst))
            effectiveFlags.add(CastFlagsE::UnConst);
        if (autoCast.modifierFlags.has(AstModifierFlagsE::Wrap))
            effectiveFlags.add(CastFlagsE::NoOverflow);
    }

    if (view.cstRef().isValid() && sema.isFoldedTypedConst(view.nodeRef()))
        effectiveFlags.add(CastFlagsE::FoldedTypedConst);

    UserDefinedLiteralSuffixInfo suffixInfo;
    const bool                   hasUserDefinedLiteralSuffix = resolveUserDefinedLiteralSuffix(sema, view.nodeRef(), suffixInfo);
    if (srcTypeRef == dstTypeRef && effectiveFlags == CastFlagsE::Zero && !hasUserDefinedLiteralSuffix)
        return Result::Continue;

    CastRequest castRequest(effectiveKind);
    castRequest.flags        = effectiveFlags;
    castRequest.errorNodeRef = view.nodeRef();
    castRequest.setConstantFoldingSrc(view.cstRef());

    const Result result = castAllowed(sema, castRequest, view.typeRef(), dstTypeRef);
    if (result == Result::Pause)
        return result;

    // Success !
    if (result == Result::Continue)
    {
        StructOpCastData structOpCastData;
        SWC_RESULT(prepareStructOpCast(sema, structOpCastData, view, castRequest, effectiveFlags));
        StructSetCastData structSetData;
        if (!structOpCastData.calledFn)
            SWC_RESULT(prepareStructSetCast(sema, structSetData, view, dstTypeRef, effectiveKind, effectiveFlags));
        if (structOpCastData.calledFn && castRequest.constantFoldingResult().isInvalid())
        {
            ConstantRef structOpCastConstRef = ConstantRef::invalid();
            SWC_RESULT(tryConstantFoldStructOpCast(sema, view.nodeRef(), structOpCastData, structOpCastConstRef));
            if (structOpCastConstRef.isValid())
                castRequest.setConstantFoldingResult(structOpCastConstRef);
        }

        if (structSetData.calledFn && srcCstRef.isValid())
            castRequest.setConstantFoldingResult(ConstantRef::invalid());

        if (structSetData.calledFn && castRequest.constantFoldingResult().isInvalid())
        {
            ConstantRef structSetConstRef = ConstantRef::invalid();
            SWC_RESULT(tryConstantFoldStructSetCast(sema, view.nodeRef(), structSetData, dstTypeRef, structSetConstRef));
            if (structSetConstRef.isValid())
                castRequest.setConstantFoldingResult(structSetConstRef);
        }

        if (castRequest.constantFoldingResult().isInvalid())
        {
            AstNodeRef runtimeCastNodeRef = view.nodeRef();
            // A contextual cast can carry flags like `UfcsArgument` even when the
            // source is already of the requested type. Re-wrapping the same node
            // in that case causes reentrant cast growth on revisits.
            if (srcTypeRef == dstTypeRef)
            {
                if (castFlags.has(CastFlagsE::FromExplicitNode))
                    sema.setType(view.nodeRef(), dstTypeRef);
            }
            else if (castFlags.has(CastFlagsE::FromExplicitNode))
                sema.setType(view.nodeRef(), dstTypeRef);
            else
            {
                const ConstantRef constRef   = view.cstRef();
                const AstNodeRef  srcNodeRef = view.nodeRef();
                SWC_RESULT(Cast::retargetLiteralRuntimeStorageIfNeeded(sema, srcNodeRef, srcTypeRef, dstTypeRef));
                view.nodeRef() = createCast(sema, dstTypeRef, srcNodeRef);
                SWC_RESULT(attachCastRuntimeStorageIfNeeded(sema, view.nodeRef(), srcTypeRef, dstTypeRef, constRef));
                runtimeCastNodeRef = view.nodeRef();
            }

            SWC_RESULT(setupCastOverflowRuntimeSafety(sema, runtimeCastNodeRef, srcTypeRef, dstTypeRef, effectiveFlags));
            SWC_RESULT(setupCastFromAnyRuntime(sema, runtimeCastNodeRef, srcTypeRef, dstTypeRef, effectiveFlags));
            if (structOpCastData.calledFn)
                SWC_RESULT(finalizeRuntimeStructOpCast(sema, runtimeCastNodeRef, structOpCastData));
            else if (structSetData.calledFn)
                SWC_RESULT(finalizeRuntimeStructSetCast(sema, runtimeCastNodeRef, structSetData, dstTypeRef));
        }
        else
        {
            sema.setType(view.nodeRef(), dstTypeRef);
            sema.setConstant(view.nodeRef(), castRequest.constantFoldingResult());
            bool needsRuntimeStorage = false;
            SWC_RESULT(setupRuntimeArrayScalarFillIfNeeded(sema, view.nodeRef(), srcTypeRef, dstTypeRef, srcCstRef, effectiveKind, needsRuntimeStorage));
            if (needsRuntimeStorage)
                SWC_RESULT(attachCastRuntimeStorageIfNeeded(sema, view.nodeRef(), srcTypeRef, dstTypeRef, srcCstRef));
        }

        view.recompute(sema);
        return Result::Continue;
    }

    if (effectiveKind != CastKind::Explicit)
    {
        CastRequest explicitCtx(CastKind::Explicit);
        explicitCtx.errorNodeRef = view.nodeRef();
        if (castAllowed(sema, explicitCtx, view.typeRef(), dstTypeRef) == Result::Continue)
            castRequest.failure.noteId = DiagnosticId::sema_note_cast_explicit;
    }

    if (errorArguments)
        castRequest.failure.mergeArguments(*errorArguments);

    return emitCastFailure(sema, castRequest.failure);
}

Result Cast::castIfNeeded(Sema& sema, SemaNodeView& view, TypeRef dstTypeRef, CastKind castKind, CastFlags castFlags, const DiagnosticArguments* errorArguments)
{
    if (view.typeRef() == dstTypeRef)
        return Result::Continue;

    return cast(sema, view, dstTypeRef, castKind, castFlags, errorArguments);
}

Result Cast::castPromote(Sema& sema, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView, CastKind castKind)
{
    if (!nodeLeftView.type() || !nodeRightView.type())
        return Result::Continue;

    if (!nodeLeftView.type()->isScalarNumeric() || !nodeRightView.type()->isScalarNumeric())
        return Result::Continue;

    const TypeRef promotedTypeRef = sema.typeMgr().promote(nodeLeftView.typeRef(), nodeRightView.typeRef(), false);
    SWC_RESULT(castIfNeeded(sema, nodeLeftView, promotedTypeRef, castKind));
    SWC_RESULT(castIfNeeded(sema, nodeRightView, promotedTypeRef, castKind));
    return Result::Continue;
}

SWC_END_NAMESPACE();
