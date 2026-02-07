#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result failCannotCast(CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        return castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
    }

    void setupElemCtx(CastContext& elemCtx, const CastContext& castCtx)
    {
        elemCtx.flags        = castCtx.flags;
        elemCtx.errorNodeRef = castCtx.errorNodeRef;
    }

    Result checkElemCast(Sema& sema,
                         CastContext& castCtx,
                         TypeRef srcElemType,
                         TypeRef dstElemType)
    {
        CastContext elemCtx(castCtx.kind);
        setupElemCtx(elemCtx, castCtx);
        const Result res = Cast::castAllowed(sema, elemCtx, srcElemType, dstElemType);
        if (res != Result::Continue)
            castCtx.failure = elemCtx.failure;
        return res;
    }

    Result foldElemCast(Sema& sema,
                        CastContext& castCtx,
                        TypeRef srcElemType,
                        TypeRef dstElemType,
                        ConstantRef valueRef,
                        ConstantRef& outRef)
    {
        CastContext elemCtx(castCtx.kind);
        setupElemCtx(elemCtx, castCtx);
        elemCtx.setConstantFoldingSrc(valueRef);
        const Result res = Cast::castAllowed(sema, elemCtx, srcElemType, dstElemType);
        if (res != Result::Continue)
        {
            castCtx.failure = elemCtx.failure;
            return res;
        }

        outRef = elemCtx.constantFoldingResult();
        if (outRef.isInvalid())
            outRef = valueRef;
        return Result::Continue;
    }

    Result castArrayToArray(Sema& sema,
                            CastContext& castCtx,
                            TypeRef srcTypeRef,
                            TypeRef dstTypeRef,
                            const TypeInfo& srcType,
                            const TypeInfo& dstType)
    {
        const auto&   dstDims        = dstType.payloadArrayDims();
        const TypeRef dstElemTypeRef = dstType.payloadArrayElemTypeRef();

        const auto& srcDims = srcType.payloadArrayDims();
        if (srcDims.size() != dstDims.size())
            return failCannotCast(castCtx, srcTypeRef, dstTypeRef);

        for (size_t i = 0; i < srcDims.size(); ++i)
        {
            if (srcDims[i] != dstDims[i])
                return failCannotCast(castCtx, srcTypeRef, dstTypeRef);
        }

        const TypeRef srcElemTypeRef = srcType.payloadArrayElemTypeRef();
        if (srcElemTypeRef == dstElemTypeRef)
            return Result::Continue;

        if (!castCtx.isConstantFolding())
            return failCannotCast(castCtx, srcTypeRef, dstTypeRef);

        const ConstantValue& cst = sema.cstMgr().get(castCtx.constantFoldingSrc());
        if (!cst.isAggregateArray())
            return failCannotCast(castCtx, srcTypeRef, dstTypeRef);

        const auto&              values = cst.getAggregateArray();
        std::vector<ConstantRef> newValues;
        newValues.reserve(values.size());

        for (const auto& valueRef : values)
        {
            ConstantRef castedRef;
            const Result res = foldElemCast(sema, castCtx, srcElemTypeRef, dstElemTypeRef, valueRef, castedRef);
            if (res != Result::Continue)
                return res;
            newValues.push_back(castedRef);
        }

        const ConstantValue result = ConstantValue::makeAggregateArray(sema.ctx(), newValues);
        castCtx.outConstRef        = sema.cstMgr().addConstant(sema.ctx(), result);
        return Result::Continue;
    }

    Result castAggregateToArray(Sema& sema,
                                CastContext& castCtx,
                                TypeRef srcTypeRef,
                                TypeRef dstTypeRef,
                                const TypeInfo& srcType,
                                const TypeInfo& dstType)
    {
        const auto&   dstDims        = dstType.payloadArrayDims();
        const TypeRef dstElemTypeRef = dstType.payloadArrayElemTypeRef();

        const auto& srcTypes = srcType.payloadAggregate().types;

        uint64_t totalCount = 1;
        for (const auto dim : dstDims)
            totalCount *= dim;

        if (srcTypes.size() > totalCount)
            return failCannotCast(castCtx, srcTypeRef, dstTypeRef);

        for (const auto srcElemTypeRef : srcTypes)
        {
            const Result res = checkElemCast(sema, castCtx, srcElemTypeRef, dstElemTypeRef);
            if (res != Result::Continue)
                return res;
        }

        if (!castCtx.isConstantFolding())
            return Result::Continue;

        const ConstantValue& cst = sema.cstMgr().get(castCtx.constantFoldingSrc());
        if (!cst.isAggregateArray())
            return failCannotCast(castCtx, srcTypeRef, dstTypeRef);

        const auto&              values = cst.getAggregateArray();
        std::vector<ConstantRef> newValues;
        newValues.reserve(values.size());

        for (size_t i = 0; i < values.size(); ++i)
        {
            ConstantRef castedRef;
            const Result res = foldElemCast(sema, castCtx, srcTypes[i], dstElemTypeRef, values[i], castedRef);
            if (res != Result::Continue)
                return res;
            newValues.push_back(castedRef);
        }

        const ConstantValue result = ConstantValue::makeAggregateArray(sema.ctx(), newValues);
        castCtx.outConstRef        = sema.cstMgr().addConstant(sema.ctx(), result);
        return Result::Continue;
    }
}

Result Cast::castToArray(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

    if (srcType.isArray())
        return castArrayToArray(sema, castCtx, srcTypeRef, dstTypeRef, srcType, dstType);

    if (srcType.isAggregateArray())
        return castAggregateToArray(sema, castCtx, srcTypeRef, dstTypeRef, srcType, dstType);

    return failCannotCast(castCtx, srcTypeRef, dstTypeRef);
}

SWC_END_NAMESPACE();
