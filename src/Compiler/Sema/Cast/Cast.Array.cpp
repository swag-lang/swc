#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct CastArrayContext
    {
        Sema*           sema;
        CastContext*    castCtx;
        TypeRef         srcTypeRef;
        TypeRef         dstTypeRef;
        const TypeInfo* srcType;
        const TypeInfo* dstType;
    };

    Result failArrayDimCount(const CastArrayContext& ctx, size_t srcCount, size_t dstCount)
    {
        const Result res = ctx.castCtx->fail(DiagnosticId::sema_err_array_cast_num_dims, ctx.srcTypeRef, ctx.dstTypeRef);
        ctx.castCtx->failure.addArgument(Diagnostic::ARG_COUNT, static_cast<uint64_t>(srcCount));
        ctx.castCtx->failure.addArgument(Diagnostic::ARG_VALUE, static_cast<uint64_t>(dstCount));
        return res;
    }

    Result failArrayDimMismatch(const CastArrayContext& ctx, size_t dimIndex, uint64_t srcDim, uint64_t dstDim)
    {
        const Result res = ctx.castCtx->fail(DiagnosticId::sema_err_array_cast_dim_mismatch, ctx.srcTypeRef, ctx.dstTypeRef);
        ctx.castCtx->failure.addArgument(Diagnostic::ARG_LEFT, srcDim);
        ctx.castCtx->failure.addArgument(Diagnostic::ARG_RIGHT, dstDim);
        return res;
    }

    Result failArrayTooManyValues(const CastArrayContext& ctx, size_t srcCount, uint64_t dstCount)
    {
        const Result res = ctx.castCtx->fail(DiagnosticId::sema_err_array_cast_too_many_values, ctx.srcTypeRef, ctx.dstTypeRef);
        ctx.castCtx->failure.addArgument(Diagnostic::ARG_COUNT, static_cast<uint64_t>(srcCount));
        ctx.castCtx->failure.addArgument(Diagnostic::ARG_VALUE, dstCount);
        return res;
    }

    Result failArrayConst(const CastArrayContext& ctx, std::string_view reason)
    {
        const Result res = ctx.castCtx->fail(DiagnosticId::sema_err_array_cast_const, ctx.srcTypeRef, ctx.dstTypeRef);
        ctx.castCtx->failure.addArgument(Diagnostic::ARG_VALUE, reason);
        return res;
    }

    Result checkElemCast(const CastArrayContext& ctx, TypeRef srcElemType, TypeRef dstElemType)
    {
        CastContext elemCtx(ctx.castCtx->kind);
        elemCtx.flags        = ctx.castCtx->flags;
        elemCtx.errorNodeRef = ctx.castCtx->errorNodeRef;
        const Result res     = Cast::castAllowed(*ctx.sema, elemCtx, srcElemType, dstElemType);
        if (res != Result::Continue)
            ctx.castCtx->failure = elemCtx.failure;
        return res;
    }

    Result foldElemCast(const CastArrayContext& ctx, TypeRef srcElemType, TypeRef dstElemType, ConstantRef valueRef, ConstantRef& outRef)
    {
        CastContext elemCtx(ctx.castCtx->kind);
        elemCtx.flags        = ctx.castCtx->flags;
        elemCtx.errorNodeRef = ctx.castCtx->errorNodeRef;
        elemCtx.setConstantFoldingSrc(valueRef);
        const Result res = Cast::castAllowed(*ctx.sema, elemCtx, srcElemType, dstElemType);
        if (res != Result::Continue)
        {
            ctx.castCtx->failure = elemCtx.failure;
            return res;
        }

        outRef = elemCtx.constantFoldingResult();
        if (outRef.isInvalid())
            outRef = valueRef;
        return Result::Continue;
    }

    Result castArrayToArray(const CastArrayContext& ctx)
    {
        const auto&   dstDims        = ctx.dstType->payloadArrayDims();
        const TypeRef dstElemTypeRef = ctx.dstType->payloadArrayElemTypeRef();

        const auto& srcDims = ctx.srcType->payloadArrayDims();
        if (srcDims.size() != dstDims.size())
            return failArrayDimCount(ctx, srcDims.size(), dstDims.size());

        for (size_t i = 0; i < srcDims.size(); ++i)
        {
            if (srcDims[i] != dstDims[i])
                return failArrayDimMismatch(ctx, i, srcDims[i], dstDims[i]);
        }

        const TypeRef srcElemTypeRef = ctx.srcType->payloadArrayElemTypeRef();
        if (srcElemTypeRef == dstElemTypeRef)
            return Result::Continue;

        if (!ctx.castCtx->isConstantFolding())
            return failArrayConst(ctx, "array element cast requires constant folding");

        const ConstantValue& cst = ctx.sema->cstMgr().get(ctx.castCtx->constantFoldingSrc());
        if (!cst.isAggregateArray())
            return failArrayConst(ctx, "expected an array constant");

        const auto&              values = cst.getAggregateArray();
        std::vector<ConstantRef> newValues;
        newValues.reserve(values.size());

        for (const auto& valueRef : values)
        {
            ConstantRef  castedRef;
            const Result res = foldElemCast(ctx, srcElemTypeRef, dstElemTypeRef, valueRef, castedRef);
            if (res != Result::Continue)
                return res;
            newValues.push_back(castedRef);
        }

        const ConstantValue result = ConstantValue::makeAggregateArray(ctx.sema->ctx(), newValues);
        ctx.castCtx->outConstRef   = ctx.sema->cstMgr().addConstant(ctx.sema->ctx(), result);
        return Result::Continue;
    }

    Result castAggregateToArray(const CastArrayContext& ctx)
    {
        const auto&   dstDims        = ctx.dstType->payloadArrayDims();
        const TypeRef dstElemTypeRef = ctx.dstType->payloadArrayElemTypeRef();
        const auto&   srcTypes       = ctx.srcType->payloadAggregate().types;

        uint64_t totalCount = 1;
        for (const auto dim : dstDims)
            totalCount *= dim;

        if (srcTypes.size() > totalCount)
            return failArrayTooManyValues(ctx, srcTypes.size(), totalCount);

        for (const auto srcElemTypeRef : srcTypes)
        {
            const Result res = checkElemCast(ctx, srcElemTypeRef, dstElemTypeRef);
            if (res != Result::Continue)
                return res;
        }

        if (!ctx.castCtx->isConstantFolding())
            return Result::Continue;

        const ConstantValue& cst = ctx.sema->cstMgr().get(ctx.castCtx->constantFoldingSrc());
        if (!cst.isAggregateArray())
            return failArrayConst(ctx, "expected an array constant");

        const auto&              values = cst.getAggregateArray();
        std::vector<ConstantRef> newValues;
        newValues.reserve(values.size());

        for (size_t i = 0; i < values.size(); ++i)
        {
            ConstantRef  castedRef;
            const Result res = foldElemCast(ctx, srcTypes[i], dstElemTypeRef, values[i], castedRef);
            if (res != Result::Continue)
                return res;
            newValues.push_back(castedRef);
        }

        const ConstantValue result = ConstantValue::makeAggregateArray(ctx.sema->ctx(), newValues);
        ctx.castCtx->outConstRef   = ctx.sema->cstMgr().addConstant(ctx.sema->ctx(), result);
        return Result::Continue;
    }
}

Result Cast::castToArray(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo&        srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo&        dstType = sema.typeMgr().get(dstTypeRef);
    const CastArrayContext ctx{&sema, &castCtx, srcTypeRef, dstTypeRef, &srcType, &dstType};

    if (srcType.isArray())
        return castArrayToArray(ctx);

    if (srcType.isAggregateArray())
        return castAggregateToArray(ctx);

    return castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

SWC_END_NAMESPACE();
