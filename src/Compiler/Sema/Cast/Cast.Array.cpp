#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Cast/CastAggregateArgs.h"
#include "Compiler/Sema/Cast/CastConstant.h"
#include "Compiler/Sema/Cast/CastElementHelpers.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Core/ByteArray.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ArrayElemLocation
    {
        AstNodeRef    nodeRef = AstNodeRef::invalid();
        SourceCodeRef codeRef = SourceCodeRef::invalid();
    };

    AstNodeRef arrayElemValueNodeRef(const Sema& sema, AstNodeRef nodeRef)
    {
        while (nodeRef.isValid())
        {
            const AstNode& node = sema.node(nodeRef);
            if (node.is(AstNodeId::InitializerExpr))
            {
                nodeRef = node.cast<AstInitializerExpr>().nodeExprRef;
                continue;
            }

            return nodeRef;
        }

        return AstNodeRef::invalid();
    }

    Result failArrayDimCount(const CastAggregateArgs& args, size_t srcCount, size_t dstCount)
    {
        const Result res = args.castRequest->fail(DiagnosticId::sema_err_array_cast_num_dims, args.srcTypeRef, args.dstTypeRef);
        args.castRequest->failure.addArgument(Diagnostic::ARG_COUNT, static_cast<uint64_t>(srcCount));
        args.castRequest->failure.addArgument(Diagnostic::ARG_VALUE, static_cast<uint64_t>(dstCount));
        return res;
    }

    Result failArrayDimMismatch(const CastAggregateArgs& args, size_t, uint64_t srcDim, uint64_t dstDim)
    {
        const Result res = args.castRequest->fail(DiagnosticId::sema_err_array_cast_dim_mismatch, args.srcTypeRef, args.dstTypeRef);
        args.castRequest->failure.addArgument(Diagnostic::ARG_LEFT, srcDim);
        args.castRequest->failure.addArgument(Diagnostic::ARG_RIGHT, dstDim);
        return res;
    }

    bool aggregateArraySourceHasNestedArrays(const CastAggregateArgs& args)
    {
        const auto& srcTypes = args.srcType->payloadAggregate().types;
        for (const TypeRef srcElemTypeRef : srcTypes)
        {
            const TypeInfo& srcElemType = args.sema->typeMgr().get(srcElemTypeRef);
            if (!srcElemType.isAggregateArray() && !srcElemType.isArray())
                return false;
        }

        return true;
    }

    Result failArrayTooManyValues(const CastAggregateArgs& args, size_t srcCount, uint64_t dstCount)
    {
        const Result res = args.castRequest->fail(DiagnosticId::sema_err_array_cast_too_many_values, args.srcTypeRef, args.dstTypeRef);
        args.castRequest->failure.addArgument(Diagnostic::ARG_COUNT, static_cast<uint64_t>(srcCount));
        args.castRequest->failure.addArgument(Diagnostic::ARG_VALUE, dstCount);
        return res;
    }

    Result failArrayConst(const CastAggregateArgs& args, DiagnosticId diagnosticId)
    {
        return args.castRequest->fail(diagnosticId, args.srcTypeRef, args.dstTypeRef);
    }

    Result failArrayMissingRequiredValues(const CastAggregateArgs& args)
    {
        return args.castRequest->fail(DiagnosticId::sema_err_type_requires_init, args.dstTypeRef, args.dstTypeRef);
    }

    ArrayElemLocation arrayElemLocation(const CastAggregateArgs& args, size_t elemIndex)
    {
        if (!args.castRequest->errorNodeRef.isValid())
            return {};

        const AstNode& node = args.sema->node(args.castRequest->errorNodeRef);
        if (node.isNot(AstNodeId::ArrayLiteral))
            return {};

        const auto&      literal = node.cast<AstArrayLiteral>();
        const AstNodeRef nodeRef = args.sema->ast().nthNode(literal.spanChildrenRef, elemIndex);
        if (nodeRef.isInvalid())
            return {};

        return {nodeRef, args.sema->node(nodeRef).codeRef()};
    }

    CastRequest makeElemCastRequest(const CastAggregateArgs& args, const ArrayElemLocation& location)
    {
        CastRequest elemCtx(args.castRequest->kind);
        elemCtx.flags   = args.castRequest->flags;
        elemCtx.probing = args.castRequest->probing;
        if (location.nodeRef.isValid())
        {
            elemCtx.errorNodeRef = location.nodeRef;
            elemCtx.errorCodeRef = SourceCodeRef::invalid();
        }
        else
        {
            elemCtx.errorNodeRef = args.castRequest->errorNodeRef;
            elemCtx.errorCodeRef = location.codeRef.isValid() ? location.codeRef : args.castRequest->errorCodeRef;
        }
        elemCtx.applyAutoCast(*args.sema, arrayElemValueNodeRef(*args.sema, location.nodeRef));
        return elemCtx;
    }

    Result checkElemCast(const CastAggregateArgs& args, TypeRef srcElemType, TypeRef dstElemType, const ArrayElemLocation& location, ConstantRef valueRef = ConstantRef::invalid())
    {
        CastRequest elemCtx = makeElemCastRequest(args, location);
        if (valueRef.isValid())
            elemCtx.setConstantFoldingSrc(valueRef);
        const Result res = CastElementHelpers::allowed(*args.sema, *args.castRequest, elemCtx, srcElemType, dstElemType);
        if (res != Result::Continue)
            return res;

        const AstNodeRef valueNodeRef = arrayElemValueNodeRef(*args.sema, location.nodeRef);
        if (valueNodeRef.isInvalid())
            return Result::Continue;
        if (args.castRequest->probing || srcElemType == dstElemType)
            return Result::Continue;

        SemaNodeView valueView(*args.sema, valueNodeRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        return Cast::castIfNeeded(*args.sema, valueView, dstElemType, elemCtx.kind, elemCtx.flags);
    }

    Result foldElemCast(const CastAggregateArgs& args, TypeRef srcElemType, TypeRef dstElemType, const ArrayElemLocation& location, ConstantRef valueRef, ConstantRef& outRef)
    {
        CastRequest elemCtx = makeElemCastRequest(args, location);
        return CastElementHelpers::foldConstant(*args.sema, *args.castRequest, elemCtx, srcElemType, dstElemType, valueRef, outRef);
    }

    ConstantRef makeArrayConstantFromValues(const CastAggregateArgs& args, const std::vector<ConstantRef>& values)
    {
        TaskContext&   ctx       = args.sema->ctx();
        const uint64_t arraySize = args.dstType->sizeOf(ctx);
        if (ConstantHelpers::typeHasUnionStorage(ctx, *args.dstType))
        {
            const TypeRef                                      elementType = args.dstType->payloadArrayElemTypeRef();
            const uint64_t                                     elementSize = args.sema->typeMgr().get(elementType).sizeOf(ctx);
            SmallVector<ConstantHelpers::ConstantPayloadWrite> writes;
            for (size_t i = 0; i < values.size(); ++i)
                writes.push_back({.offset = i * elementSize, .typeRef = elementType, .valueRef = values[i]});
            return ConstantHelpers::materializeAggregateConstructionConstant(*args.sema, args.dstTypeRef, writes.span());
        }
        ByteArray buffer(arraySize);
        SWC_INTERNAL_CHECK(SymbolStruct::lowerTypeImplicitDefaultBytes(*args.sema, buffer.span(), args.dstTypeRef) == Result::Continue);
        SWC_INTERNAL_CHECK(ConstantLower::lowerAggregateArrayToBytes(*args.sema, buffer.span(), *args.dstType, values) == Result::Continue);
        const ConstantRef result = ConstantHelpers::materializeStaticPayloadConstant(*args.sema, args.dstTypeRef, buffer.span());
        SWC_ASSERT(result.isValid());
        return result;
    }

    Result getAggregateConstantValues(const CastAggregateArgs& args, const std::vector<ConstantRef>*& outValues)
    {
        outValues = nullptr;
        if (!args.castRequest->isConstantFolding())
            return Result::Continue;

        const ConstantValue& cst = args.sema->cstMgr().get(args.castRequest->constantFoldingSrc());
        if (!cst.isAggregateArray())
            return failArrayConst(args, DiagnosticId::sema_err_array_cast_expected_aggregate_constant);

        outValues = &cst.getAggregateArray();
        return Result::Continue;
    }

    Result castArrayToArray(const CastAggregateArgs& args)
    {
        const auto&   dstDims        = args.dstType->payloadArrayDims();
        const TypeRef dstElemTypeRef = args.dstType->payloadArrayElemTypeRef();

        const auto& srcDims = args.srcType->payloadArrayDims();
        if (srcDims.size() != dstDims.size())
            return failArrayDimCount(args, srcDims.size(), dstDims.size());

        for (size_t i = 0; i < srcDims.size(); ++i)
        {
            if (srcDims[i] != dstDims[i])
                return failArrayDimMismatch(args, i, srcDims[i], dstDims[i]);
        }

        if (args.srcType->payloadArrayIndexTypeRefs() != args.dstType->payloadArrayIndexTypeRefs() && args.castRequest->kind != CastKind::Explicit)
            return args.castRequest->fail(DiagnosticId::sema_err_cannot_cast, args.srcTypeRef, args.dstTypeRef);

        const TypeRef srcElemTypeRef = args.srcType->payloadArrayElemTypeRef();
        if (srcElemTypeRef == dstElemTypeRef)
            return Result::Continue;

        if (!args.castRequest->isConstantFolding())
            return failArrayConst(args, DiagnosticId::sema_err_array_cast_requires_const_folding);

        const ConstantValue& cst = args.sema->cstMgr().get(args.castRequest->constantFoldingSrc());
        if (!cst.isAggregateArray())
            return failArrayConst(args, DiagnosticId::sema_err_array_cast_expected_aggregate_constant);

        const auto&              values = cst.getAggregateArray();
        std::vector<ConstantRef> newValues;
        newValues.reserve(values.size());

        for (size_t i = 0; i < values.size(); ++i)
        {
            const ArrayElemLocation location = arrayElemLocation(args, i);
            ConstantRef             castedRef;
            SWC_RESULT(foldElemCast(args, srcElemTypeRef, dstElemTypeRef, location, values[i], castedRef));
            if (castedRef.isInvalid())
            {
                args.castRequest->outConstRef = ConstantRef::invalid();
                return Result::Continue;
            }
            newValues.push_back(castedRef);
        }

        args.castRequest->outConstRef = makeArrayConstantFromValues(args, newValues);
        return Result::Continue;
    }

    Result castAggregateToArray(const CastAggregateArgs& args)
    {
        const AstNodeRef waitNodeRef = args.castRequest->errorNodeRef.isValid() ? args.castRequest->errorNodeRef : args.sema->curNodeRef();
        SWC_RESULT(SymbolStruct::waitTypeImplicitDefaultReady(*args.sema, args.dstTypeRef, waitNodeRef));
        SWC_RESULT(SemaSpecOp::addDefaultInitCallDependencies(*args.sema, args.dstTypeRef));

        const auto&                     dstDims        = args.dstType->payloadArrayDims();
        const TypeRef                   dstElemTypeRef = args.dstType->payloadArrayElemTypeRef();
        const auto&                     srcTypes       = args.srcType->payloadAggregate().types;
        const std::vector<ConstantRef>* srcValues      = nullptr;
        SWC_RESULT(getAggregateConstantValues(args, srcValues));

        const bool hasNestedSource = dstDims.size() > 1 && aggregateArraySourceHasNestedArrays(args);

        if (hasNestedSource)
        {
            const uint64_t dstTopDim = dstDims[0];
            if (srcTypes.size() > dstTopDim)
                return failArrayTooManyValues(args, srcTypes.size(), dstTopDim);

            TypeManager&  typeMgr         = args.sema->typeMgr();
            const TypeRef dstSubArrayType = typeMgr.addType(args.dstType->makeArrayAfterFirstDimension());
            if (srcTypes.size() < dstTopDim && SymbolStruct::typeRequiresExplicitInitialization(*args.sema, dstSubArrayType))
                return failArrayMissingRequiredValues(args);

            for (size_t i = 0; i < srcTypes.size(); ++i)
            {
                const ArrayElemLocation location = arrayElemLocation(args, i);
                const ConstantRef       valueRef = srcValues ? (*srcValues)[i] : ConstantRef::invalid();
                SWC_RESULT(checkElemCast(args, srcTypes[i], dstSubArrayType, location, valueRef));
            }

            if (!args.castRequest->materializeConstantResult())
                return Result::Continue;
            if (srcTypes.size() < dstTopDim && SymbolStruct::typeHasRuntimeImplicitDefault(*args.sema, dstSubArrayType))
            {
                args.castRequest->outConstRef = ConstantRef::invalid();
                return Result::Continue;
            }

            TaskContext&                                       ctx       = args.sema->ctx();
            const uint64_t                                     arraySize = args.dstType->sizeOf(ctx);
            ByteArray                                          buffer(arraySize);
            const std::span<std::byte>                         bytes           = buffer.span();
            const TypeInfo&                                    subArrayType    = typeMgr.get(dstSubArrayType);
            const uint64_t                                     subArraySize    = subArrayType.sizeOf(ctx);
            const bool                                         hasUnionStorage = ConstantHelpers::typeHasUnionStorage(ctx, *args.dstType);
            SmallVector<ConstantHelpers::ConstantPayloadWrite> writes;
            SWC_RESULT(SymbolStruct::lowerTypeImplicitDefaultBytes(*args.sema, bytes, args.dstTypeRef));

            for (size_t i = 0; i < srcValues->size(); ++i)
            {
                const ArrayElemLocation location = arrayElemLocation(args, i);
                ConstantRef             castedRef;
                SWC_RESULT(foldElemCast(args, srcTypes[i], dstSubArrayType, location, (*srcValues)[i], castedRef));
                if (castedRef.isInvalid())
                {
                    args.castRequest->outConstRef = ConstantRef::invalid();
                    return Result::Continue;
                }
                const std::span dstChunk{bytes.data() + (i * subArraySize), subArraySize};
                SWC_RESULT(ConstantLower::lowerToBytes(*args.sema, dstChunk, castedRef, subArrayType));
                if (hasUnionStorage)
                    writes.push_back({.offset = i * subArraySize, .typeRef = dstSubArrayType, .valueRef = castedRef});
            }

            args.castRequest->outConstRef = hasUnionStorage ? ConstantHelpers::materializeAggregateConstructionConstant(*args.sema, args.dstTypeRef, writes.span())
                                                            : ConstantHelpers::materializeStaticPayloadConstant(*args.sema, args.dstTypeRef, buffer.span());
            SWC_ASSERT(args.castRequest->outConstRef.isValid());
            return Result::Continue;
        }

        uint64_t totalCount = 1;
        for (const auto dim : dstDims)
            totalCount *= dim;

        if (srcTypes.size() > totalCount)
            return failArrayTooManyValues(args, srcTypes.size(), totalCount);
        if (srcTypes.size() < totalCount && SymbolStruct::typeRequiresExplicitInitialization(*args.sema, dstElemTypeRef))
            return failArrayMissingRequiredValues(args);

        for (size_t i = 0; i < srcTypes.size(); ++i)
        {
            const ArrayElemLocation location = arrayElemLocation(args, i);
            const ConstantRef       valueRef = srcValues ? (*srcValues)[i] : ConstantRef::invalid();
            SWC_RESULT(checkElemCast(args, srcTypes[i], dstElemTypeRef, location, valueRef));
        }

        if (!args.castRequest->materializeConstantResult())
            return Result::Continue;
        if (srcTypes.size() < totalCount && SymbolStruct::typeHasRuntimeImplicitDefault(*args.sema, dstElemTypeRef))
        {
            args.castRequest->outConstRef = ConstantRef::invalid();
            return Result::Continue;
        }

        std::vector<ConstantRef> newValues;
        newValues.reserve(srcValues->size());

        for (size_t i = 0; i < srcValues->size(); ++i)
        {
            const ArrayElemLocation location = arrayElemLocation(args, i);
            ConstantRef             castedRef;
            SWC_RESULT(foldElemCast(args, srcTypes[i], dstElemTypeRef, location, (*srcValues)[i], castedRef));
            if (castedRef.isInvalid())
            {
                args.castRequest->outConstRef = ConstantRef::invalid();
                return Result::Continue;
            }
            newValues.push_back(castedRef);
        }

        args.castRequest->outConstRef = makeArrayConstantFromValues(args, newValues);
        return Result::Continue;
    }

    // Single value initialization: fill an entire array with one scalar value.
    // Single value initialization: validate that the scalar can be cast to
    // the array's leaf element type, and produce a fill constant.
    Result castScalarToArray(const CastAggregateArgs& args)
    {
        TypeRef leafTypeRef = args.dstType->payloadArrayElemTypeRef();
        while (args.sema->typeMgr().get(leafTypeRef).isArray())
            leafTypeRef = args.sema->typeMgr().get(leafTypeRef).payloadArrayElemTypeRef();

        const ConstantRef valueRef = args.castRequest->isConstantFolding() ? args.castRequest->constantFoldingSrc() : ConstantRef::invalid();
        SWC_RESULT(checkElemCast(args, args.srcTypeRef, leafTypeRef, {}, valueRef));

        if (!args.castRequest->materializeConstantResult())
            return Result::Continue;

        ConstantRef elemRef;
        SWC_RESULT(foldElemCast(args, args.srcTypeRef, leafTypeRef, {}, args.castRequest->constantFoldingSrc(), elemRef));
        if (elemRef.isInvalid())
        {
            args.castRequest->outConstRef = ConstantRef::invalid();
            return Result::Continue;
        }

        uint64_t totalCount = 1;
        for (const auto dim : args.dstType->payloadArrayDims())
            totalCount *= dim;
        {
            const TypeInfo* cur = &args.sema->typeMgr().get(args.dstType->payloadArrayElemTypeRef());
            while (cur->isArray())
            {
                for (const auto dim : cur->payloadArrayDims())
                    totalCount *= dim;
                cur = &args.sema->typeMgr().get(cur->payloadArrayElemTypeRef());
            }
        }

        const std::vector values(totalCount, elemRef);
        args.castRequest->outConstRef = makeArrayConstantFromValues(args, values);
        return Result::Continue;
    }
}

Result Cast::castToArray(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo&         srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo&         dstType = sema.typeMgr().get(dstTypeRef);
    const CastAggregateArgs args{&sema, &castRequest, srcTypeRef, dstTypeRef, &srcType, &dstType};

    if (srcType.isArray())
        return castArrayToArray(args);
    if (srcType.isAggregateArray())
        return castAggregateToArray(args);

    // Single value initialization (e.g. var arr: [4] s32 = 0).
    if (castRequest.kind == CastKind::Initialization && !srcType.isAggregate())
        return castScalarToArray(args);

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToSimd(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    TypeManager&            typeMgr = sema.typeMgr();
    const TypeInfo&         srcType = typeMgr.get(srcTypeRef);
    const TypeInfo&         dstType = typeMgr.get(dstTypeRef);
    const CastAggregateArgs args{&sema, &castRequest, srcTypeRef, dstTypeRef, &srcType, &dstType};

    const TypeRef  laneTypeRef = dstType.payloadSimdLaneTypeRef();
    const uint32_t laneCount   = dstType.payloadSimdLaneCount();
    const uint64_t laneBytes   = 16 / laneCount;

    // Only a qualifier change converts between simd types here; a different
    // shape needs an explicit '#bit' reinterpretation.
    if (srcType.isSimd())
    {
        if (srcType.payloadSimdLaneTypeRef() == laneTypeRef && srcType.payloadSimdLaneCount() == laneCount)
            return castIdentity(sema, castRequest, srcTypeRef, dstTypeRef);
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
    }

    // An array literal builds the lanes: the count must match exactly, and
    // each element must convert to the lane type.
    if (srcType.isAggregateArray())
    {
        const auto& srcTypes = srcType.payloadAggregate().types;
        if (srcTypes.size() != laneCount)
        {
            const Result res = castRequest.fail(DiagnosticId::sema_err_simd_lane_count, srcTypeRef, dstTypeRef);
            castRequest.failure.addArgument(Diagnostic::ARG_VALUE, static_cast<uint64_t>(laneCount));
            castRequest.failure.addArgument(Diagnostic::ARG_COUNT, static_cast<uint64_t>(srcTypes.size()));
            return res;
        }

        const std::vector<ConstantRef>* srcValues = nullptr;
        SWC_RESULT(getAggregateConstantValues(args, srcValues));

        for (size_t i = 0; i < srcTypes.size(); ++i)
        {
            const ArrayElemLocation location = arrayElemLocation(args, i);
            const ConstantRef       valueRef = srcValues ? (*srcValues)[i] : ConstantRef::invalid();
            SWC_RESULT(checkElemCast(args, srcTypes[i], laneTypeRef, location, valueRef));
        }

        if (!castRequest.materializeConstantResult())
            return Result::Continue;

        ByteArray                  buffer(16);
        const std::span<std::byte> bytes = buffer.span();
        for (size_t i = 0; i < srcValues->size(); ++i)
        {
            const ArrayElemLocation location = arrayElemLocation(args, i);
            ConstantRef             castedRef;
            SWC_RESULT(foldElemCast(args, srcTypes[i], laneTypeRef, location, (*srcValues)[i], castedRef));
            if (castedRef.isInvalid())
            {
                castRequest.outConstRef = ConstantRef::invalid();
                return Result::Continue;
            }
            const std::span dstChunk{bytes.data() + (i * laneBytes), laneBytes};
            SWC_RESULT(ConstantLower::lowerToBytes(sema, dstChunk, castedRef, typeMgr.get(laneTypeRef)));
        }

        castRequest.outConstRef = ConstantHelpers::materializeStaticPayloadConstant(sema, dstTypeRef, bytes);
        SWC_ASSERT(castRequest.outConstRef.isValid());
        return Result::Continue;
    }

    if (castRequest.kind != CastKind::Explicit)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    // A fixed-size array of the exact shape reinterprets bit for bit.
    if (srcType.isArray())
    {
        const auto&   dims           = srcType.payloadArrayDims();
        const TypeRef srcElemTypeRef = typeMgr.unwrapAliasEnumOrSelf(sema.ctx(), srcType.payloadArrayElemTypeRef());
        if (dims.size() != 1 || dims[0] != laneCount || srcElemTypeRef != laneTypeRef)
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        CastConstant::materializeArrayPayload(sema, castRequest, dstTypeRef);
        return Result::Continue;
    }

    // A scalar filling every lane is a broadcast, not a conversion, and 'Swag.vecsplat' is
    // the operation that says so.
    if (typeMgr.get(typeMgr.unwrapAliasEnumOrSelf(sema.ctx(), srcTypeRef)).isScalarNumeric())
        return castRequest.fail(DiagnosticId::sema_err_simd_scalar_cast, srcTypeRef, dstTypeRef);

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castFromSimd(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    TypeManager&    typeMgr = sema.typeMgr();
    const TypeInfo& srcType = typeMgr.get(srcTypeRef);
    const TypeInfo& dstType = typeMgr.get(dstTypeRef);

    // The only value route out of a vector is the explicit reinterpretation
    // into the fixed-size array of the exact same shape.
    if (castRequest.kind != CastKind::Explicit || !dstType.isArray())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    const auto&   dims           = dstType.payloadArrayDims();
    const TypeRef dstElemTypeRef = typeMgr.unwrapAliasEnumOrSelf(sema.ctx(), dstType.payloadArrayElemTypeRef());
    if (dims.size() != 1 || dims[0] != srcType.payloadSimdLaneCount() || dstElemTypeRef != srcType.payloadSimdLaneTypeRef())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    CastConstant::materializeArrayPayload(sema, castRequest, dstTypeRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
