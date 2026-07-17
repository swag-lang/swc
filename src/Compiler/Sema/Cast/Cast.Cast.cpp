#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    AstNodeRef unwrapStructSpecCastSourceArgRef(const Sema& sema, AstNodeRef nodeRef)
    {
        while (nodeRef.isValid())
        {
            const AstNode& node = sema.node(nodeRef);
            if (node.is(AstNodeId::NamedArgument))
            {
                nodeRef = node.cast<AstNamedArgument>().nodeArgRef;
                continue;
            }

            if (node.is(AstNodeId::InitializerExpr))
            {
                nodeRef = node.cast<AstInitializerExpr>().nodeExprRef;
                continue;
            }

            return nodeRef;
        }

        return AstNodeRef::invalid();
    }

    ConstantRef addValuePointerConstant(Sema& sema, TypeRef dstPointeeTypeRef, TypeInfoFlags dstFlags, uint64_t ptrValue)
    {
        const ConstantValue ptrCst = ConstantValue::makeValuePointer(sema.ctx(), dstPointeeTypeRef, ptrValue, dstFlags);
        return sema.cstMgr().addConstant(sema.ctx(), ptrCst);
    }

    bool isProvablyNullPointerLikeConstant(const ConstantValue& cst)
    {
        if (cst.isNull())
            return true;
        if (cst.isValuePointer())
            return !cst.getValuePointer();
        if (cst.isBlockPointer())
            return !cst.getBlockPointer();
        if (cst.isSlice())
            return !cst.getSlice().data();
        if (cst.isString())
            return !cst.getString().data();
        if (cst.isInt())
            return cst.getInt().isZero();

        return false;
    }

    CastRequest makeNestedCastRequest(const CastRequest& parent)
    {
        CastRequest nested(parent.kind);
        nested.flags        = parent.flags;
        nested.errorNodeRef = parent.errorNodeRef;
        nested.errorCodeRef = parent.errorCodeRef;
        nested.probing      = parent.probing;
        return nested;
    }

    Result waitEnumCompletion(Sema& sema, const CastRequest& castRequest, const TypeInfo& typeInfo)
    {
        if (!typeInfo.isEnum())
            return Result::Continue;

        const AstNodeRef waitNodeRef = castRequest.errorNodeRef.isValid() ? castRequest.errorNodeRef : sema.curNodeRef();
        return sema.waitSemaCompleted(&typeInfo, waitNodeRef);
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

    Result collectAggregateStructConstantFieldValues(Sema& sema, SmallVector<ConstantRef>& outValues, ConstantRef srcCstRef, const TypeInfo& srcType)
    {
        const auto&          srcTypes = srcType.payloadAggregate().types;
        const ConstantValue& srcCst   = sema.cstMgr().get(srcCstRef);
        if (srcCst.isAggregateStruct())
        {
            for (const ConstantRef valueRef : srcCst.getAggregateStruct())
                outValues.push_back(valueRef);
            return Result::Continue;
        }

        SWC_ASSERT(srcCst.isStruct());
        const std::span<const std::byte> srcBytes = srcCst.getStruct();
        uint64_t                         offset   = 0;
        outValues.reserve(srcTypes.size());

        for (const TypeRef elemTypeRef : srcTypes)
        {
            const TypeInfo& elemType = sema.typeMgr().get(elemTypeRef);
            uint32_t        align    = elemType.alignOf(sema.ctx());
            const uint64_t  elemSize = elemType.sizeOf(sema.ctx());
            if (!align)
                align = 1;

            offset = Math::alignUpU64(offset, align);
            if (!elemSize)
            {
                outValues.push_back(sema.cstMgr().addZeroPayloadConstant(sema.ctx(), elemTypeRef));
                continue;
            }

            SWC_ASSERT(offset + elemSize <= srcBytes.size());
            const std::span   elemBytes{srcBytes.data() + offset, elemSize};
            const ConstantRef el = ConstantHelpers::materializeStaticPayloadConstant(sema, elemTypeRef, elemBytes);
            SWC_INTERNAL_CHECK(el.isValid());
            outValues.push_back(el);
            offset += elemSize;
        }

        return Result::Continue;
    }

    Result castAggregateStructToAggregateStruct(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef, const TypeInfo& srcType, const TypeInfo& dstType)
    {
        const auto& srcAggregate = srcType.payloadAggregate();
        const auto& dstAggregate = dstType.payloadAggregate();
        if (srcAggregate.types.size() != dstAggregate.types.size() ||
            srcAggregate.names.size() != dstAggregate.names.size())
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        for (size_t i = 0; i < srcAggregate.types.size(); ++i)
        {
            const IdentifierRef srcName = srcAggregate.names[i];
            const IdentifierRef dstName = dstAggregate.names[i];
            if (srcName.isValid() && (!dstName.isValid() || srcName != dstName))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

            CastRequest  elemRequest = makeNestedCastRequest(castRequest);
            const Result res         = Cast::castAllowed(sema, elemRequest, srcAggregate.types[i], dstAggregate.types[i]);
            if (res != Result::Continue)
            {
                castRequest.failure = elemRequest.failure;
                return res;
            }
        }

        if (!castRequest.materializeConstantResult())
            return Result::Continue;

        SmallVector<ConstantRef> srcValues;
        SWC_RESULT(collectAggregateStructConstantFieldValues(sema, srcValues, castRequest.constantFoldingSrc(), srcType));
        SWC_ASSERT(srcValues.size() == srcAggregate.types.size());

        SmallVector<ConstantRef> castedValues;
        castedValues.reserve(srcValues.size());
        for (size_t i = 0; i < srcValues.size(); ++i)
        {
            CastRequest elemRequest = makeNestedCastRequest(castRequest);
            elemRequest.setConstantFoldingSrc(srcValues[i]);
            const Result res = Cast::castAllowed(sema, elemRequest, srcAggregate.types[i], dstAggregate.types[i]);
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

        const ConstantValue result = ConstantValue::makeAggregateStruct(sema.ctx(), dstAggregate.names, castedValues);
        castRequest.setConstantFoldingResult(sema.cstMgr().addConstant(sema.ctx(), result));
        return Result::Continue;
    }

    bool isImplicitNullableQualificationCast(const TypeInfo& srcType, const TypeInfo& dstType)
    {
        if (srcType.isNullable() == dstType.isNullable() && srcType.isExplicitNonNull() == dstType.isExplicitNonNull())
            return false;
        if (!srcType.isSupportsNullableQualifier() || !dstType.isSupportsNullableQualifier())
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

    bool isImplicitNullableAnyStringCast(const TypeInfo& srcType, const TypeInfo& dstType)
    {
        return srcType.isAny() && srcType.isNullable() && dstType.isString() && dstType.isNullable();
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

    bool isConstSourceBinding(Sema& sema, const SemaNodeView& view, ConstantRef cstRef)
    {
        if (view.sym())
            return view.sym()->isConstant();

        if (SemaCheck::isConstAssignmentTarget(sema, view.nodeRef(), view))
            return true;

        return cstRef.isValid() && !view.hasSymbol();
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
        SWC_RESULT(ConstantLower::lowerToBytes(sema, std::span{valueBytes.data(), valueBytes.size()}, castRequest.constantFoldingSrc(), srcTypeRef));

        uint64_t rawValue = 0;
        std::memcpy(&rawValue, valueBytes.data(), std::min<uint64_t>(sizeof(rawValue), valueBytes.size()));
        castRequest.setConstantFoldingResult(rawValue ? sema.cstMgr().cstTrue() : sema.cstMgr().cstFalse());
        return Result::Continue;
    }

    ConstantRef readIndirectValueConstant(Sema& sema, ConstantRef refCstRef, TypeRef valueTypeRef)
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
        if (!srcTypeRef.isValid() || !dstTypeRef.isValid())
            return Result::Continue;

        const TypeRef   resolvedSrcTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), srcTypeRef);
        const TypeInfo& srcType            = sema.typeMgr().get(resolvedSrcTypeRef);
        if (!srcType.isAny())
            return Result::Continue;

        const TypeRef   resolvedDstTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), dstTypeRef);
        const TypeInfo& dstType            = sema.typeMgr().get(resolvedDstTypeRef);
        if (dstType.isAny())
            return Result::Continue;

        const bool fromExplicitNode = castFlags.has(CastFlagsE::FromExplicitNode);
        if (!fromExplicitNode && !isImplicitNullableAnyStringCast(srcType, dstType))
            return Result::Continue;

        const bool hasDynCastSafety     = sema.frame().currentAttributes().hasRuntimeSafety(sema.buildCfg().safetyGuards, Runtime::SafetyWhat::DynCast);
        const bool dstUsesTypeInfoMatch = dstType.isStruct() ||
                                          dstType.isAnyPointer() ||
                                          dstType.isReference() ||
                                          dstType.isMoveReference() ||
                                          (!dstType.isInterface() && !dstType.isAnyVariadic());
        if (!dstUsesTypeInfoMatch)
            return Result::Continue;

        auto& payload = SemaHelpers::ensureCodeGenLoweringPayload(sema, nodeRef);

        if (hasDynCastSafety)
            payload.addRuntimeSafety(Runtime::SafetyWhat::DynCast);

        if (!sema.isCurrentFunction())
            return Result::Continue;

        const auto& codeRef = sema.node(nodeRef).codeRef();
        SWC_RESULT(SemaHelpers::attachRuntimeAsFunctionToNode(sema, nodeRef, codeRef));

        // Resolve panic function when DynCast safety is enabled
        if (hasDynCastSafety)
            SWC_RESULT(SemaHelpers::requireRuntimeSafetyPanicDependency(sema, codeRef));

        return Result::Continue;
    }

    Result setupExplicitInterfaceToStructPointerCastRuntime(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef, CastFlags castFlags)
    {
        if (castFlags.has(CastFlagsE::BitCast))
            return Result::Continue;
        if (!castFlags.has(CastFlagsE::FromExplicitNode))
            return Result::Continue;
        if (!srcTypeRef.isValid() || !dstTypeRef.isValid())
            return Result::Continue;

        const TypeRef   resolvedSrcTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), srcTypeRef);
        const TypeInfo& srcType            = sema.typeMgr().get(resolvedSrcTypeRef);
        if (!srcType.isInterface())
            return Result::Continue;

        const TypeRef   resolvedDstTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), dstTypeRef);
        const TypeInfo& dstType            = sema.typeMgr().get(resolvedDstTypeRef);
        if (!dstType.isAnyPointer())
            return Result::Continue;

        const TypeRef dstPointeeTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), dstType.payloadTypeRef());
        if (!dstPointeeTypeRef.isValid() || !sema.typeMgr().get(dstPointeeTypeRef).isStruct())
            return Result::Continue;

        return SemaHelpers::attachRuntimeAsFunctionToNode(sema, nodeRef, sema.node(nodeRef).codeRef());
    }

    AstNodeRef sourceArgRefForStructSpecCast(const Sema& sema, const SemaNodeView& view, const CastFlags castFlags)
    {
        AstNodeRef sourceRef = view.nodeRef();
        if (!castFlags.has(CastFlagsE::FromExplicitNode))
            return unwrapStructSpecCastSourceArgRef(sema, sourceRef);

        if (!view.node())
            return AstNodeRef::invalid();

        if (view.node()->is(AstNodeId::CastExpr))
            sourceRef = view.node()->cast<AstCastExpr>().nodeExprRef;
        else if (view.node()->is(AstNodeId::AutoCastExpr))
            sourceRef = view.node()->cast<AstAutoCastExpr>().nodeExprRef;
        else
            return AstNodeRef::invalid();

        return unwrapStructSpecCastSourceArgRef(sema, sourceRef);
    }

    struct StructOpCastData
    {
        SymbolFunction* calledFn       = nullptr;
        AstNodeRef      sourceArgRef   = AstNodeRef::invalid();
        bool            forceConstEval = false;
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

    Result buildStructOpCastResolvedArgs(Sema& sema, SmallVector<ResolvedCallArgument>& outResolvedArgs, AstNodeRef sourceArgRef, const SymbolFunction& calledFn)
    {
        ResolvedCallArgument resolvedArg;
        resolvedArg.argRef                = sourceArgRef;
        resolvedArg.bindsReferenceToValue = structOpCastBindsReferenceToValue(sema, calledFn, sourceArgRef);
        if (!calledFn.parameters().empty())
            SWC_RESULT(SemaHelpers::attachBorrowedAggregateArgumentRuntimeStorageIfNeeded(sema, calledFn, calledFn.parameters().front()->typeRef(), sourceArgRef));

        outResolvedArgs.push_back(resolvedArg);
        return Result::Continue;
    }

    Result prepareStructOpCast(Sema& sema, StructOpCastData& outData, const SemaNodeView& view, const CastRequest& castRequest, CastFlags castFlags)
    {
        outData.calledFn       = castRequest.selectedStructOpCast;
        outData.sourceArgRef   = sourceArgRefForStructSpecCast(sema, view, castFlags);
        outData.forceConstEval = castFlags.has(CastFlagsE::ForceConstEval);
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
        SWC_RESULT(buildStructOpCastResolvedArgs(sema, resolvedArgs, castData.sourceArgRef, *castData.calledFn));

        SWC_RESULT(SemaJIT::tryRunConstCall(sema, *castData.calledFn, callRef, resolvedArgs.span(), castData.forceConstEval));
        const SemaNodeView callView(sema, callRef, SemaNodeViewPartE::Constant);
        if (callView.cstRef().isValid() &&
            sema.cstMgr().get(callView.cstRef()).typeRef() == castData.calledFn->returnTypeRef())
            outConstRef = callView.cstRef();
        return Result::Continue;
    }

    Result finalizeRuntimeStructOpCast(Sema& sema, AstNodeRef castNodeRef, const StructOpCastData& castData)
    {
        if (castNodeRef.isInvalid() || castData.sourceArgRef.isInvalid() || !castData.calledFn || sema.isGlobalScope())
            return Result::Continue;

        SmallVector<ResolvedCallArgument> resolvedArgs;
        SWC_RESULT(buildStructOpCastResolvedArgs(sema, resolvedArgs, castData.sourceArgRef, *castData.calledFn));

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
        return SemaHelpers::attachIndirectReturnRuntimeStorageIfNeeded(sema, castNodeRef, sema.node(castNodeRef), *castData.calledFn, "__cast_runtime_storage");
    }

    Result computeStructSetReceiverInit(Sema& sema, TypeRef dstTypeRef, const SymbolFunction& calledFn, ConstantRef& outInitCstRef)
    {
        outInitCstRef = ConstantRef::invalid();
        if (calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Complete))
            return Result::Continue;

        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
        SWC_RESULT(sema.waitSemaCompleted(&dstType, sema.curNodeRef()));
        if (SymbolStruct::typeRequiresExplicitInitialization(sema, dstTypeRef))
            return SemaError::raiseTypeArgumentError(sema, DiagnosticId::sema_err_type_requires_init, sema.curNode().codeRef(), dstTypeRef);
        outInitCstRef = dstType.payloadSymStruct().resolveImplicitDefaultValueRef(sema, dstTypeRef);
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

    Result buildStructSetResolvedArgs(Sema& sema, SmallVector<ResolvedCallArgument>& outResolvedArgs, const SymbolFunction& calledFn, TypeRef dstTypeRef, AstNodeRef sourceArgRef, SymbolVariable* storageSym, ConstantRef receiverInitCstRef)
    {
        const AstNodeRef receiverRef = makeStructSetReceiverRef(sema, dstTypeRef, sourceArgRef, storageSym, receiverInitCstRef);
        outResolvedArgs.push_back({.argRef = receiverRef, .bindsReferenceToValue = true});
        outResolvedArgs.push_back({.argRef = sourceArgRef});
        if (calledFn.parameters().size() > 1)
            SWC_RESULT(SemaHelpers::attachBorrowedAggregateArgumentRuntimeStorageIfNeeded(sema, calledFn, calledFn.parameters()[1]->typeRef(), sourceArgRef));
        return Result::Continue;
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
        SWC_ASSERT(castData.calledFn != nullptr);
        SWC_RESULT(buildStructSetResolvedArgs(sema, resolvedArgs, *castData.calledFn, dstTypeRef, castData.sourceArgRef, nullptr, castData.receiverInitCstRef));

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
        SWC_ASSERT(castData.calledFn != nullptr);
        SWC_RESULT(buildStructSetResolvedArgs(sema, resolvedArgs, *castData.calledFn, dstTypeRef, castData.sourceArgRef, &storageSym, ConstantRef::invalid()));

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
        if (dstType.isStruct())
            return false;
        if (dstType.isEnum() && castRequest.kind != CastKind::Explicit)
            return false;
        if (dstType.isReference())
            return false;
        if (dstType.isAny())
            return false;

        if (dstType.isBool() && isTruthyBoolCastKind(castRequest.kind))
            return false;

        return true;
    }

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

        auto& payload                   = SemaHelpers::ensureCodeGenLoweringPayload(sema, nodeRef);
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

    Result resolveUsingStructCastPath(Sema& sema, const CastRequest& castRequest, TypeRef srcStructTypeRef, TypeRef dstStructTypeRef, SmallVector<SymbolStructUsingPathStep>& outSteps, bool& outFound)
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

    Result resolveUsingStructCastPathWithoutPointerStep(Sema& sema, const CastRequest& castRequest, TypeRef srcStructTypeRef, TypeRef dstStructTypeRef, bool& outFound)
    {
        SmallVector<SymbolStructUsingPathStep> usingPath;
        bool                                   hasUsingPath = false;
        SWC_RESULT(resolveUsingStructCastPath(sema, castRequest, srcStructTypeRef, dstStructTypeRef, usingPath, hasUsingPath));
        outFound = hasUsingPath && !usingPathHasPointerStep(usingPath);
        return Result::Continue;
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
        SWC_RESULT(waitEnumCompletion(sema, castRequest, *srcType));
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

Result Cast::castBoolToFloat(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castRequest.kind != CastKind::Explicit)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (castRequest.isConstantFolding())
    {
        if (!foldConstantBoolToFloat(sema, castRequest, dstTypeRef))
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

    if (isImplicitValueBoolCastKind(castRequest.kind) && !srcType.isBool() && !srcType.isIntLike() && !srcType.isFloat() && !srcType.isEnumFlags())
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
        else if (srcType.isFloat())
        {
            if (!foldConstantFloatToBool(sema, castRequest))
                return Result::Error;
        }
        else if (srcType.isPointerLike())
        {
            if (castRequest.materializeConstantResult())
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

    if (srcType.isBool())
        return castBoolToFloat(sema, castRequest, srcTypeRef, dstTypeRef);
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

    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
    SWC_RESULT(waitEnumCompletion(sema, castRequest, dstType));
    const TypeRef underlyingTypeRef = dstType.payloadSymEnum().underlyingTypeRef();

    CastRequest underlyingRequest(castRequest.kind);
    underlyingRequest.flags        = castRequest.flags;
    underlyingRequest.errorNodeRef = castRequest.errorNodeRef;
    underlyingRequest.errorCodeRef = castRequest.errorCodeRef;
    underlyingRequest.probing      = castRequest.probing;
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
    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
    SWC_RESULT(waitEnumCompletion(sema, castRequest, srcType));
    SWC_RESULT(waitEnumCompletion(sema, castRequest, dstType));

    const SymbolEnum& enumSym                    = srcType.payloadSymEnum();
    const bool        allowEnumIndexImplicitCast = enumSym.attributes().hasRtFlag(RtAttributeFlagsE::EnumIndex) && dstType.isIntLike();
    if (castRequest.kind != CastKind::Explicit && !allowEnumIndexImplicitCast)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

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
    if (dstType.isPointerLike() && !dstType.isExplicitNonNull())
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

Result Cast::castFromIndirectValue(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeRef valueTypeRef = indirectValueCastTypeRef(sema, srcTypeRef, dstTypeRef);
    if (!valueTypeRef.isValid())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (!castRequest.isConstantFolding())
        return Result::Continue;

    const ConstantRef valueCstRef = readIndirectValueConstant(sema, castRequest.constantFoldingSrc(), valueTypeRef);
    if (!valueCstRef.isValid())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    castRequest.setConstantFoldingResult(valueCstRef);
    return Result::Continue;
}

Result Cast::castToReference(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

    const auto      dstPointeeTypeRef = dstType.payloadTypeRef();
    const TypeInfo& dstPointeeType    = typeMgr.get(dstPointeeTypeRef);

    // A move reference normally binds only another move reference, formed explicitly with
    // '#move'. As a call argument, a plain copyable value is also accepted: the caller
    // materializes a temporary copy and passes it as the move reference, so a single
    // '#move' function serves both the copy and the move call styles. Structs go through
    // the copy-to-move materializer; scalar-like values go through the scalar reference
    // binding, so pointer sources stay rejected (moving the pointer or the pointee would
    // be ambiguous, like '#move' on a raw pointer).
    if (dstType.isMoveReference() && !srcType.isMoveReference())
    {
        if (!castRequest.flags.has(CastFlagsE::AllowCopyToMoveRef))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        const TypeRef resolvedSrcTypeRef     = typeMgr.unwrapAliasEnum(sema.ctx(), srcTypeRef);
        const TypeRef srcToCheck             = resolvedSrcTypeRef.isValid() ? resolvedSrcTypeRef : srcTypeRef;
        const TypeRef resolvedPointeeTypeRef = typeMgr.unwrapAliasEnum(sema.ctx(), dstPointeeTypeRef);
        const TypeRef pointeeToCheck         = resolvedPointeeTypeRef.isValid() ? resolvedPointeeTypeRef : dstPointeeTypeRef;
        if (srcToCheck != pointeeToCheck)
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        const TypeInfo& srcCheckType = typeMgr.get(srcToCheck);
        if (!srcCheckType.isStruct() && !srcCheckType.isScalarNumeric() && !srcCheckType.isBool() && !srcCheckType.isRune())
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        if (!TypeGen::lifecycleFlagsOfTypeRef(sema.ctx(), srcToCheck).canCopy)
            return castRequest.fail(DiagnosticId::sema_err_move_arg_not_copyable, srcTypeRef, dstTypeRef);

        castRequest.usedCopyToMoveRef = true;

        if (castRequest.materializeConstantResult())
        {
            const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
            if (!srcCst.isStruct())
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            const uint64_t ptr = reinterpret_cast<uint64_t>(srcCst.getStruct().data());
            castRequest.setConstantFoldingResult(addValuePointerConstant(sema, dstPointeeTypeRef, dstType.flags(), ptr));
        }

        return Result::Continue;
    }

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

        bool hasCompatibleUsingPath = false;
        SWC_RESULT(resolveUsingStructCastPathWithoutPointerStep(sema, castRequest, srcPointeeTypeRef, dstPointeeTypeRef, hasCompatibleUsingPath));
        if (hasCompatibleUsingPath)
            return Result::Continue;
    }

    // Pointer to ref
    if (srcType.isAnyPointer())
    {
        // A nullable pointer cannot silently bind to a non-null reference (e.g. `var q: &T = nullableP`).
        // The only exception is a UFCS receiver: calling a method on a `#null` pointer just dereferences it
        // (C-like, may fault at runtime if actually null), so it is allowed without a guard.
        if (srcType.isNullable() && !castRequest.flags.has(CastFlagsE::UfcsArgument))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        if (srcType.payloadTypeRef() == dstPointeeTypeRef)
            return Result::Continue;

        bool hasCompatibleUsingPath = false;
        SWC_RESULT(resolveUsingStructCastPathWithoutPointerStep(sema, castRequest, srcType.payloadTypeRef(), dstPointeeTypeRef, hasCompatibleUsingPath));
        if (hasCompatibleUsingPath)
            return Result::Continue;
    }

    // Value to const ref
    if (srcType.isStruct() && dstType.isConst())
    {
        if (dstPointeeTypeRef == srcTypeRef)
        {
            if (castRequest.materializeConstantResult())
            {
                const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
                SWC_ASSERT(srcCst.isStruct());
                const uint64_t ptr = reinterpret_cast<uint64_t>(srcCst.getStruct().data());
                castRequest.setConstantFoldingResult(addValuePointerConstant(sema, dstPointeeTypeRef, dstType.flags(), ptr));
            }

            return Result::Continue;
        }

        bool hasCompatibleUsingPath = false;
        SWC_RESULT(resolveUsingStructCastPathWithoutPointerStep(sema, castRequest, srcTypeRef, dstPointeeTypeRef, hasCompatibleUsingPath));
        if (hasCompatibleUsingPath)
            return Result::Continue;
    }

    // UFCS receiver: allow taking the address to bind a value to a reference.
    // Whether the value is actually addressable (lvalue) is validated later by `Cast::cast`.
    if (castRequest.flags.has(CastFlagsE::UfcsArgument) && !srcType.isPointerOrReference())
    {
        bool receiverMatches = dstPointeeTypeRef == srcTypeRef;
        if (!receiverMatches && srcType.isStruct())
        {
            SWC_RESULT(resolveUsingStructCastPathWithoutPointerStep(sema, castRequest, srcTypeRef, dstPointeeTypeRef, receiverMatches));
        }
        if (!receiverMatches)
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        const bool sourceIsConst = srcType.isConst() || castRequest.flags.has(CastFlagsE::ConstSource) || castRequest.isConstantFolding();
        if (sourceIsConst && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        if (castRequest.materializeConstantResult())
        {
            const uint64_t valueSize = srcType.sizeOf(sema.ctx());
            uint64_t       ptr       = 0;
            if (valueSize)
            {
                std::vector valueBytes(valueSize, std::byte{0});
                SWC_RESULT(ConstantLower::lowerToBytes(sema, std::span{valueBytes.data(), valueBytes.size()}, castRequest.constantFoldingSrc(), srcTypeRef));
                const std::string_view rawValueData = sema.cstMgr().addPayloadBuffer(std::string_view{reinterpret_cast<const char*>(valueBytes.data()), valueBytes.size()});
                ptr                                 = reinterpret_cast<uint64_t>(rawValueData.data());
            }

            castRequest.setConstantFoldingResult(addValuePointerConstant(sema, dstPointeeTypeRef, dstType.flags(), ptr));
        }

        return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
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

    const TypeManager& typeMgr              = sema.typeMgr();
    const TypeInfo&    srcType              = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType              = typeMgr.get(dstTypeRef);
    const TypeRef      indirectValueTypeRef = indirectValueCastTypeRef(sema, srcTypeRef, dstTypeRef);

    if (dstType.isExplicitNonNull() &&
        castRequest.isConstantFolding() &&
        isProvablyNullPointerLikeConstant(sema.cstMgr().get(castRequest.constantFoldingSrc())))
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (srcType.isNullable() && dstType.isExplicitNonNull())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (isImplicitNullableQualificationCast(srcType, dstType))
        return castAddNullableQualifier(castRequest);

    if (isImplicitNullableAnyStringCast(srcType, dstType))
        return castFromAny(sema, castRequest, srcTypeRef, dstTypeRef);

    if (srcType.isAlias() || dstType.isAlias())
    {
        const TypeRef   resolvedSrcTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), srcTypeRef);
        const TypeRef   resolvedDstTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), dstTypeRef);
        const TypeInfo& resolvedSrcType    = sema.typeMgr().get(resolvedSrcTypeRef);
        const TypeInfo& resolvedDstType    = sema.typeMgr().get(resolvedDstTypeRef);

        const bool allowAliasBoolCast               = isTruthyBoolCastKind(castRequest.kind) && dstType.isBool();
        const bool allowAliasNullCast               = resolvedSrcType.isNull() && resolvedDstType.isPointerLike();
        const bool allowAliasAnyCast                = dstType.isAny();
        const bool allowAliasNullableCast           = isImplicitNullableQualificationCast(resolvedSrcType, resolvedDstType);
        const bool allowAliasUfcsReceiverCast       = castRequest.flags.has(CastFlagsE::UfcsArgument) && resolvedSrcType.isAnyPointer() && resolvedDstType.isReference();
        const bool allowAliasIndirectValueCast      = indirectValueTypeRef.isValid();
        const bool allowAliasUnderlyingToStrictCast = !srcType.isAlias() && dstType.isAlias() && resolvedSrcTypeRef == resolvedDstTypeRef;
        if (castRequest.kind != CastKind::Explicit && !allowAliasBoolCast && !allowAliasNullCast && !allowAliasAnyCast && !allowAliasNullableCast && !allowAliasUfcsReceiverCast && !allowAliasIndirectValueCast && !allowAliasUnderlyingToStrictCast)
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
    }

    auto res = Result::Error;
    if (srcType.isAny() && dstType.isAny())
    {
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);
        res = castIdentity(sema, castRequest, srcTypeRef, dstTypeRef);
    }
    else if (dstType.isAny())
    {
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);
        res = castToAny(sema, castRequest, srcTypeRef, dstTypeRef);
    }
    else if (indirectValueTypeRef.isValid())
        res = castFromIndirectValue(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (srcType.isAlias())
        res = castAllowed(sema, castRequest, srcType.payloadSymAlias().underlyingTypeRef(), dstTypeRef);
    else if (srcType.isAny())
        res = castFromAny(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isAlias())
        res = castAllowed(sema, castRequest, srcTypeRef, dstType.payloadSymAlias().underlyingTypeRef());
    else if (srcType.isAggregateStruct() && dstType.isAggregateStruct())
        res = castAggregateStructToAggregateStruct(sema, castRequest, srcTypeRef, dstTypeRef, srcType, dstType);
    else if (castRequest.flags.has(CastFlagsE::BitCast))
        res = castBit(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (shouldRouteEnumViaUnderlying(castRequest, srcType, dstType))
        res = castFromEnum(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (srcType.isNull())
        res = castFromNull(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (srcType.isUndefined())
        res = castFromUndefined(sema, castRequest, srcTypeRef, dstTypeRef);
    // A reference reads as its pointee for scalar conversions: dereference first,
    // then convert (the codegen numeric path already unwraps reference payloads).
    else if (srcType.isReference() && (dstType.isEnum() || dstType.isBool() || dstType.isIntLike() || dstType.isFloat()))
        res = castAllowed(sema, castRequest, srcType.payloadTypeRef(), dstTypeRef);
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

    if (res != Result::Continue)
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
    const SemaNodeView sourceBindingView(sema, view.nodeRef(), SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
    if (isConstSourceBinding(sema, sourceBindingView, view.cstRef()))
        effectiveFlags.add(CastFlagsE::ConstSource);

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
        if (structOpCastData.calledFn && castRequest.constantFoldingResult() == srcCstRef)
            castRequest.setConstantFoldingResult(ConstantRef::invalid());
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
            if (effectiveFlags.has(CastFlagsE::ForceConstEval))
                return Result::Continue;

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
                SWC_RESULT(Cast::retargetLiteralRuntimeStorageIfNeeded(sema, srcNodeRef, srcTypeRef, dstTypeRef, constRef.isValid()));
                view.nodeRef() = createCast(sema, dstTypeRef, srcNodeRef);
                SWC_RESULT(attachCastRuntimeStorageIfNeeded(sema, view.nodeRef(), srcTypeRef, dstTypeRef, constRef));
                runtimeCastNodeRef = view.nodeRef();
            }

            SWC_RESULT(setupCastOverflowRuntimeSafety(sema, runtimeCastNodeRef, srcTypeRef, dstTypeRef, effectiveFlags));
            SWC_RESULT(setupCastFromAnyRuntime(sema, runtimeCastNodeRef, srcTypeRef, dstTypeRef, effectiveFlags));
            SWC_RESULT(setupExplicitInterfaceToStructPointerCastRuntime(sema, runtimeCastNodeRef, srcTypeRef, dstTypeRef, effectiveFlags));
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
            else
            {
                // A cast that folds to a constant needs no runtime storage buffer. When this cast was
                // materialized by an inline clone of a callee whose source was a runtime value (e.g. a
                // value-to-`any` box), the clone carried over the callee's runtime storage symbol (a
                // `[sizeof(Any) + sizeof(value)]` buffer). Now that the inlined argument is constant the
                // box folds to a self-contained constant `any`, so that stale, oversized buffer must be
                // dropped — otherwise codegen tries to fill it with the smaller constant and asserts.
                if (auto* payload = sema.loweringPayload<CodeGenLoweringPayload>(view.nodeRef()))
                    payload->runtimeStorageSym = nullptr;
            }
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
