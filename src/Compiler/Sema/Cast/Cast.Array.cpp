#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct CastArrayArgs
    {
        Sema*           sema;
        CastRequest*    castRequest;
        TypeRef         srcTypeRef;
        TypeRef         dstTypeRef;
        const TypeInfo* srcType;
        const TypeInfo* dstType;
    };

    struct ArrayElemLocation
    {
        AstNodeRef    nodeRef = AstNodeRef::invalid();
        SourceCodeRef codeRef = SourceCodeRef::invalid();
    };

    Result failArrayDimCount(const CastArrayArgs& args, size_t srcCount, size_t dstCount)
    {
        const Result res = args.castRequest->fail(DiagnosticId::sema_err_array_cast_num_dims, args.srcTypeRef, args.dstTypeRef);
        args.castRequest->failure.addArgument(Diagnostic::ARG_COUNT, static_cast<uint64_t>(srcCount));
        args.castRequest->failure.addArgument(Diagnostic::ARG_VALUE, static_cast<uint64_t>(dstCount));
        return res;
    }

    Result failArrayDimMismatch(const CastArrayArgs& args, size_t, uint64_t srcDim, uint64_t dstDim)
    {
        const Result res = args.castRequest->fail(DiagnosticId::sema_err_array_cast_dim_mismatch, args.srcTypeRef, args.dstTypeRef);
        args.castRequest->failure.addArgument(Diagnostic::ARG_LEFT, srcDim);
        args.castRequest->failure.addArgument(Diagnostic::ARG_RIGHT, dstDim);
        return res;
    }

    Result failArrayTooManyValues(const CastArrayArgs& args, size_t srcCount, uint64_t dstCount)
    {
        const Result res = args.castRequest->fail(DiagnosticId::sema_err_array_cast_too_many_values, args.srcTypeRef, args.dstTypeRef);
        args.castRequest->failure.addArgument(Diagnostic::ARG_COUNT, static_cast<uint64_t>(srcCount));
        args.castRequest->failure.addArgument(Diagnostic::ARG_VALUE, dstCount);
        return res;
    }

    Result failArrayConst(const CastArrayArgs& args, DiagnosticId diagnosticId)
    {
        return args.castRequest->fail(diagnosticId, args.srcTypeRef, args.dstTypeRef);
    }

    ArrayElemLocation arrayElemLocation(const CastArrayArgs& args, size_t elemIndex)
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

    CastRequest makeElemCastRequest(const CastArrayArgs& args, const ArrayElemLocation& location)
    {
        CastRequest elemCtx(args.castRequest->kind);
        elemCtx.flags        = args.castRequest->flags;
        elemCtx.errorNodeRef = location.nodeRef.isValid() ? location.nodeRef : args.castRequest->errorNodeRef;
        elemCtx.errorCodeRef = location.codeRef.isValid() ? location.codeRef : args.castRequest->errorCodeRef;
        return elemCtx;
    }

    Result checkElemCast(const CastArrayArgs& args, TypeRef srcElemType, TypeRef dstElemType, const ArrayElemLocation& location, ConstantRef valueRef = ConstantRef::invalid())
    {
        CastRequest  elemCtx = makeElemCastRequest(args, location);
        if (valueRef.isValid())
            elemCtx.setConstantFoldingSrc(valueRef);
        const Result res     = Cast::castAllowed(*args.sema, elemCtx, srcElemType, dstElemType);
        if (res != Result::Continue)
            args.castRequest->failure = elemCtx.failure;
        return res;
    }

    Result foldElemCast(const CastArrayArgs& args, TypeRef srcElemType, TypeRef dstElemType, const ArrayElemLocation& location, ConstantRef valueRef, ConstantRef& outRef)
    {
        CastRequest elemCtx = makeElemCastRequest(args, location);
        elemCtx.setConstantFoldingSrc(valueRef);
        const Result res = Cast::castAllowed(*args.sema, elemCtx, srcElemType, dstElemType);
        if (res != Result::Continue)
        {
            args.castRequest->failure = elemCtx.failure;
            return res;
        }

        outRef = elemCtx.constantFoldingResult();
        if (outRef.isInvalid())
            outRef = valueRef;
        return Result::Continue;
    }

    ConstantRef makeArrayConstantFromValues(const CastArrayArgs& args, const std::vector<ConstantRef>& values)
    {
        TaskContext&           ctx       = args.sema->ctx();
        const uint64_t         arraySize = args.dstType->sizeOf(ctx);
        std::vector<std::byte> buffer(arraySize);
        const ByteSpanRW       bytes = asByteSpan(buffer);
        SWC_INTERNAL_CHECK(ConstantLower::lowerAggregateArrayToBytes(*args.sema, bytes, *args.dstType, values) == Result::Continue);
        const ConstantRef result = ConstantHelpers::materializeStaticPayloadConstant(*args.sema, args.dstTypeRef, ByteSpan{bytes.data(), bytes.size()});
        SWC_ASSERT(result.isValid());
        return result;
    }

    Result getAggregateConstantValues(const CastArrayArgs& args, const std::vector<ConstantRef>*& outValues)
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

    Result castArrayToArray(const CastArrayArgs& args)
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

        const TypeRef srcElemTypeRef = args.srcType->payloadArrayElemTypeRef();
        if (srcElemTypeRef == dstElemTypeRef)
            return Result::Continue;

        if (!args.castRequest->isConstantFolding())
            return failArrayConst(args, DiagnosticId::sema_err_array_cast_requires_const_folding);

        const ConstantValue& cst = args.sema->cstMgr().get(args.castRequest->constantFoldingSrc());
        if (!cst.isAggregateArray())
            return failArrayConst(args, DiagnosticId::sema_err_array_cast_expected_aggregate_constant);

        const auto&              values = cst.getAggregateArray();
        SmallVector<ConstantRef> newValues;
        newValues.reserve(values.size());

        for (size_t i = 0; i < values.size(); ++i)
        {
            const ArrayElemLocation location = arrayElemLocation(args, i);
            ConstantRef             castedRef;
            SWC_RESULT(foldElemCast(args, srcElemTypeRef, dstElemTypeRef, location, values[i], castedRef));
            newValues.push_back(castedRef);
        }

        const std::vector valuesForArray(newValues.begin(), newValues.end());
        args.castRequest->outConstRef = makeArrayConstantFromValues(args, valuesForArray);
        return Result::Continue;
    }

    Result castAggregateToArray(const CastArrayArgs& args)
    {
        const auto&   dstDims        = args.dstType->payloadArrayDims();
        const TypeRef dstElemTypeRef = args.dstType->payloadArrayElemTypeRef();
        const auto&   srcTypes       = args.srcType->payloadAggregate().types;
        const std::vector<ConstantRef>* srcValues = nullptr;
        SWC_RESULT(getAggregateConstantValues(args, srcValues));

        const bool hasNestedSource = dstDims.size() > 1 &&
                                     std::ranges::all_of(srcTypes, [&](const TypeRef srcElemTypeRef) {
                                         const TypeInfo& srcElemType = args.sema->typeMgr().get(srcElemTypeRef);
                                         return srcElemType.isAggregateArray() || srcElemType.isArray();
                                     });

        if (hasNestedSource)
        {
            const uint64_t dstTopDim = dstDims[0];
            if (srcTypes.size() > dstTopDim)
                return failArrayTooManyValues(args, srcTypes.size(), dstTopDim);

            SmallVector<uint64_t> subDims;
            subDims.reserve(dstDims.size() - 1);
            for (size_t i = 1; i < dstDims.size(); ++i)
                subDims.push_back(dstDims[i]);

            TypeManager&  typeMgr         = args.sema->typeMgr();
            const TypeRef dstSubArrayType = typeMgr.addType(TypeInfo::makeArray(subDims.span(), dstElemTypeRef, args.dstType->flags()));

            for (size_t i = 0; i < srcTypes.size(); ++i)
            {
                const ArrayElemLocation location = arrayElemLocation(args, i);
                const ConstantRef       valueRef = srcValues ? (*srcValues)[i] : ConstantRef::invalid();
                SWC_RESULT(checkElemCast(args, srcTypes[i], dstSubArrayType, location, valueRef));
            }

            if (!args.castRequest->isConstantFolding())
                return Result::Continue;

            TaskContext&           ctx       = args.sema->ctx();
            const uint64_t         arraySize = args.dstType->sizeOf(ctx);
            std::vector<std::byte> buffer(arraySize);
            const ByteSpanRW       bytes        = asByteSpan(buffer);
            const uint64_t         subArraySize = typeMgr.get(dstSubArrayType).sizeOf(ctx);

            for (size_t i = 0; i < srcValues->size(); ++i)
            {
                const ArrayElemLocation location = arrayElemLocation(args, i);
                ConstantRef             castedRef;
                SWC_RESULT(foldElemCast(args, srcTypes[i], dstSubArrayType, location, (*srcValues)[i], castedRef));
                const ByteSpanRW dstChunk{bytes.data() + (i * subArraySize), subArraySize};
                SWC_RESULT(ConstantLower::lowerToBytes(*args.sema, dstChunk, castedRef, dstSubArrayType));
            }

            args.castRequest->outConstRef = ConstantHelpers::materializeStaticPayloadConstant(*args.sema, args.dstTypeRef, ByteSpan{bytes.data(), bytes.size()});
            SWC_ASSERT(args.castRequest->outConstRef.isValid());
            return Result::Continue;
        }

        uint64_t totalCount = 1;
        for (const auto dim : dstDims)
            totalCount *= dim;

        if (srcTypes.size() > totalCount)
            return failArrayTooManyValues(args, srcTypes.size(), totalCount);

        for (size_t i = 0; i < srcTypes.size(); ++i)
        {
            const ArrayElemLocation location = arrayElemLocation(args, i);
            const ConstantRef       valueRef = srcValues ? (*srcValues)[i] : ConstantRef::invalid();
            SWC_RESULT(checkElemCast(args, srcTypes[i], dstElemTypeRef, location, valueRef));
        }

        if (!args.castRequest->isConstantFolding())
            return Result::Continue;

        SmallVector<ConstantRef> newValues;
        newValues.reserve(srcValues->size());

        for (size_t i = 0; i < srcValues->size(); ++i)
        {
            const ArrayElemLocation location = arrayElemLocation(args, i);
            ConstantRef             castedRef;
            SWC_RESULT(foldElemCast(args, srcTypes[i], dstElemTypeRef, location, (*srcValues)[i], castedRef));
            newValues.push_back(castedRef);
        }

        const std::vector valuesForArray(newValues.begin(), newValues.end());
        args.castRequest->outConstRef = makeArrayConstantFromValues(args, valuesForArray);
        return Result::Continue;
    }

    // Single value initialization: fill an entire array with one scalar value.
    // Single value initialization: validate that the scalar can be cast to
    // the array's leaf element type, and produce a fill constant.
    Result castScalarToArray(const CastArrayArgs& args)
    {
        TypeRef leafTypeRef = args.dstType->payloadArrayElemTypeRef();
        while (args.sema->typeMgr().get(leafTypeRef).isArray())
            leafTypeRef = args.sema->typeMgr().get(leafTypeRef).payloadArrayElemTypeRef();

        const ConstantRef valueRef = args.castRequest->isConstantFolding() ? args.castRequest->constantFoldingSrc() : ConstantRef::invalid();
        SWC_RESULT(checkElemCast(args, args.srcTypeRef, leafTypeRef, {}, valueRef));

        if (!args.castRequest->isConstantFolding())
            return Result::Continue;

        ConstantRef elemRef;
        SWC_RESULT(foldElemCast(args, args.srcTypeRef, leafTypeRef, {}, args.castRequest->constantFoldingSrc(), elemRef));

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
    const TypeInfo&     srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo&     dstType = sema.typeMgr().get(dstTypeRef);
    const CastArrayArgs args{&sema, &castRequest, srcTypeRef, dstTypeRef, &srcType, &dstType};

    if (srcType.isArray())
        return castArrayToArray(args);
    if (srcType.isAggregateArray())
        return castAggregateToArray(args);

    // Single value initialization (e.g. var arr: [4] s32 = 0).
    if (castRequest.kind == CastKind::Initialization && !srcType.isAggregate())
        return castScalarToArray(args);

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

SWC_END_NAMESPACE();
