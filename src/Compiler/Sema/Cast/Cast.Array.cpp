#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

Result Cast::castToArray(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

    const auto&   dstDims        = dstType.payloadArrayDims();
    const TypeRef dstElemTypeRef = dstType.payloadArrayElemTypeRef();

    if (srcType.isArray())
    {
        const auto& srcDims = srcType.payloadArrayDims();
        if (srcDims.size() != dstDims.size())
            return castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        for (size_t i = 0; i < srcDims.size(); ++i)
        {
            if (srcDims[i] != dstDims[i])
                return castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        }

        const TypeRef srcElemTypeRef = srcType.payloadArrayElemTypeRef();
        if (srcElemTypeRef == dstElemTypeRef)
            return Result::Continue;

        if (!castCtx.isConstantFolding())
            return castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        const ConstantValue& cst = sema.cstMgr().get(castCtx.constantFoldingSrc());
        if (!cst.isAggregateArray())
            return castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        const auto&              values = cst.getAggregateArray();
        std::vector<ConstantRef> newValues;
        newValues.reserve(values.size());

        for (const auto& valueRef : values)
        {
            CastContext elemCtx(castCtx.kind);
            elemCtx.flags        = castCtx.flags;
            elemCtx.errorNodeRef = castCtx.errorNodeRef;
            elemCtx.setConstantFoldingSrc(valueRef);

            const Result res = castAllowed(sema, elemCtx, srcElemTypeRef, dstElemTypeRef);
            if (res != Result::Continue)
            {
                castCtx.failure = elemCtx.failure;
                return res;
            }

            ConstantRef castedRef = elemCtx.constantFoldingResult();
            if (castedRef.isInvalid())
                castedRef = valueRef;
            newValues.push_back(castedRef);
        }

        const ConstantValue result = ConstantValue::makeAggregateArray(sema.ctx(), newValues);
        castCtx.outConstRef        = sema.cstMgr().addConstant(sema.ctx(), result);
        return Result::Continue;
    }

    if (srcType.isAggregateArray())
    {
        const auto& srcTypes = srcType.payloadAggregate().types;

        uint64_t totalCount = 1;
        for (const auto dim : dstDims)
            totalCount *= dim;

        if (srcTypes.size() > totalCount)
            return castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        for (const auto srcElemTypeRef : srcTypes)
        {
            CastContext elemCtx(castCtx.kind);
            elemCtx.flags        = castCtx.flags;
            elemCtx.errorNodeRef = castCtx.errorNodeRef;

            const Result res = castAllowed(sema, elemCtx, srcElemTypeRef, dstElemTypeRef);
            if (res != Result::Continue)
            {
                castCtx.failure = elemCtx.failure;
                return res;
            }
        }

        if (castCtx.isConstantFolding())
        {
            const ConstantValue& cst = sema.cstMgr().get(castCtx.constantFoldingSrc());
            if (!cst.isAggregateArray())
                return castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

            const auto&              values = cst.getAggregateArray();
            std::vector<ConstantRef> newValues;
            newValues.reserve(values.size());

            for (size_t i = 0; i < values.size(); ++i)
            {
                CastContext elemCtx(castCtx.kind);
                elemCtx.flags        = castCtx.flags;
                elemCtx.errorNodeRef = castCtx.errorNodeRef;
                elemCtx.setConstantFoldingSrc(values[i]);

                const Result res = castAllowed(sema, elemCtx, srcTypes[i], dstElemTypeRef);
                if (res != Result::Continue)
                {
                    castCtx.failure = elemCtx.failure;
                    return res;
                }

                ConstantRef castedRef = elemCtx.constantFoldingResult();
                if (castedRef.isInvalid())
                    castedRef = values[i];
                newValues.push_back(castedRef);
            }

            const ConstantValue result = ConstantValue::makeAggregateArray(sema.ctx(), newValues);
            castCtx.outConstRef        = sema.cstMgr().addConstant(sema.ctx(), result);
        }

        return Result::Continue;
    }

    return castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

SWC_END_NAMESPACE();

