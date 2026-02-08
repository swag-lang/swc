#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
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

    Result failArrayConst(const CastArrayArgs& args, std::string_view reason)
    {
        const Result res = args.castRequest->fail(DiagnosticId::sema_err_array_cast_const, args.srcTypeRef, args.dstTypeRef);
        args.castRequest->failure.addArgument(Diagnostic::ARG_VALUE, reason);
        return res;
    }

    Result checkElemCast(const CastArrayArgs& args, TypeRef srcElemType, TypeRef dstElemType)
    {
        CastRequest elemCtx(args.castRequest->kind);
        elemCtx.flags        = args.castRequest->flags;
        elemCtx.errorNodeRef = args.castRequest->errorNodeRef;
        const Result res     = Cast::castAllowed(*args.sema, elemCtx, srcElemType, dstElemType);
        if (res != Result::Continue)
            args.castRequest->failure = elemCtx.failure;
        return res;
    }

    Result foldElemCast(const CastArrayArgs& args, TypeRef srcElemType, TypeRef dstElemType, ConstantRef valueRef, ConstantRef& outRef)
    {
        CastRequest elemCtx(args.castRequest->kind);
        elemCtx.flags        = args.castRequest->flags;
        elemCtx.errorNodeRef = args.castRequest->errorNodeRef;
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
            return failArrayConst(args, "array element cast requires constant folding");

        const ConstantValue& cst = args.sema->cstMgr().get(args.castRequest->constantFoldingSrc());
        if (!cst.isAggregateArray())
            return failArrayConst(args, "expected an array constant");

        const auto&              values = cst.getAggregateArray();
        std::vector<ConstantRef> newValues;
        newValues.reserve(values.size());

        for (const auto& valueRef : values)
        {
            ConstantRef castedRef;
            RESULT_VERIFY(foldElemCast(args, srcElemTypeRef, dstElemTypeRef, valueRef, castedRef));
            newValues.push_back(castedRef);
        }

        const ConstantValue result    = ConstantValue::makeAggregateArray(args.sema->ctx(), newValues);
        args.castRequest->outConstRef = args.sema->cstMgr().addConstant(args.sema->ctx(), result);
        return Result::Continue;
    }

    Result castAggregateToArray(const CastArrayArgs& args)
    {
        const auto&   dstDims        = args.dstType->payloadArrayDims();
        const TypeRef dstElemTypeRef = args.dstType->payloadArrayElemTypeRef();
        const auto&   srcTypes       = args.srcType->payloadAggregate().types;

        uint64_t totalCount = 1;
        for (const auto dim : dstDims)
            totalCount *= dim;

        if (srcTypes.size() > totalCount)
            return failArrayTooManyValues(args, srcTypes.size(), totalCount);

        for (const auto srcElemTypeRef : srcTypes)
        {
            RESULT_VERIFY(checkElemCast(args, srcElemTypeRef, dstElemTypeRef));
        }

        if (!args.castRequest->isConstantFolding())
            return Result::Continue;

        const ConstantValue& cst = args.sema->cstMgr().get(args.castRequest->constantFoldingSrc());
        if (!cst.isAggregateArray())
            return failArrayConst(args, "expected an array constant");

        const auto&              values = cst.getAggregateArray();
        std::vector<ConstantRef> newValues;
        newValues.reserve(values.size());

        for (size_t i = 0; i < values.size(); ++i)
        {
            ConstantRef castedRef;
            RESULT_VERIFY(foldElemCast(args, srcTypes[i], dstElemTypeRef, values[i], castedRef));
            newValues.push_back(castedRef);
        }

        const ConstantValue result    = ConstantValue::makeAggregateArray(args.sema->ctx(), newValues);
        args.castRequest->outConstRef = args.sema->cstMgr().addConstant(args.sema->ctx(), result);
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

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

SWC_END_NAMESPACE();
