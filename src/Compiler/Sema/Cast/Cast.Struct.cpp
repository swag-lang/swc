#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct CastStructContext
    {
        Sema*           sema;
        CastContext*    castCtx;
        TypeRef         srcTypeRef;
        TypeRef         dstTypeRef;
        const TypeInfo* srcType;
        const TypeInfo* dstType;
    };

    Result failStructFieldCount(const CastStructContext& ctx, size_t srcCount, size_t dstCount)
    {
        const Result res = ctx.castCtx->fail(DiagnosticId::sema_err_struct_cast_field_count, ctx.srcTypeRef, ctx.dstTypeRef);
        ctx.castCtx->failure.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(srcCount));
        ctx.castCtx->failure.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(dstCount));
        return res;
    }

    Result failStructFieldType(const CastStructContext& ctx, std::string_view fieldName)
    {
        return ctx.castCtx->fail(DiagnosticId::sema_err_struct_cast_field_type, ctx.srcTypeRef, ctx.dstTypeRef, fieldName);
    }

    Result failStructField(const CastStructContext& ctx, size_t fieldIndex, DiagnosticId id, std::string_view value = "")
    {
        const auto&         fieldRefs = ctx.srcType->payloadAggregate().fieldRefs;
        const SourceCodeRef previous  = ctx.castCtx->errorCodeRef;
        const SourceCodeRef fieldRef  = fieldRefs[fieldIndex];
        if (fieldRef.isValid())
            ctx.castCtx->errorCodeRef = fieldRef;
        const Result res          = ctx.castCtx->fail(id, ctx.srcTypeRef, ctx.dstTypeRef, value);
        ctx.castCtx->errorCodeRef = previous;
        return res;
    }

    Result failStructFieldCountAt(const CastStructContext& ctx, size_t fieldIndex, size_t srcCount, size_t dstCount)
    {
        const auto&         fieldRefs = ctx.srcType->payloadAggregate().fieldRefs;
        const SourceCodeRef previous  = ctx.castCtx->errorCodeRef;
        const SourceCodeRef fieldRef  = fieldRefs[fieldIndex];
        if (fieldRef.isValid())
            ctx.castCtx->errorCodeRef = fieldRef;
        const Result res          = failStructFieldCount(ctx, srcCount, dstCount);
        ctx.castCtx->errorCodeRef = previous;
        return res;
    }

    Result failStructConst(const CastStructContext& ctx)
    {
        return ctx.castCtx->fail(DiagnosticId::sema_err_struct_cast_const, ctx.srcTypeRef, ctx.dstTypeRef);
    }

    Result checkElemCast(const CastStructContext& ctx, TypeRef srcElemType, TypeRef dstElemType, SourceCodeRef fieldRef)
    {
        CastContext elemCtx(ctx.castCtx->kind);
        elemCtx.flags        = ctx.castCtx->flags;
        elemCtx.errorNodeRef = ctx.castCtx->errorNodeRef;
        elemCtx.errorCodeRef = ctx.castCtx->errorCodeRef;
        if (fieldRef.isValid())
            elemCtx.errorCodeRef = fieldRef;
        const Result res = Cast::castAllowed(*ctx.sema, elemCtx, srcElemType, dstElemType);
        if (res != Result::Continue)
            ctx.castCtx->failure = elemCtx.failure;
        return res;
    }

    Result foldElemCast(const CastStructContext& ctx, TypeRef srcElemType, TypeRef dstElemType, SourceCodeRef fieldRef, ConstantRef valueRef, ConstantRef& outRef)
    {
        CastContext elemCtx(ctx.castCtx->kind);
        elemCtx.flags        = ctx.castCtx->flags;
        elemCtx.errorNodeRef = ctx.castCtx->errorNodeRef;
        elemCtx.errorCodeRef = ctx.castCtx->errorCodeRef;
        if (fieldRef.isValid())
            elemCtx.errorCodeRef = fieldRef;
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

    Result castStructToStruct(const CastStructContext& ctx)
    {
        const auto& srcFields = ctx.srcType->payloadSymStruct().fields();
        const auto& dstFields = ctx.dstType->payloadSymStruct().fields();
        if (srcFields.size() != dstFields.size())
            return failStructFieldCount(ctx, srcFields.size(), dstFields.size());

        for (size_t i = 0; i < srcFields.size(); ++i)
        {
            if (srcFields[i]->typeRef() != dstFields[i]->typeRef())
                return failStructFieldType(ctx, dstFields[i]->name(ctx.sema->ctx()));
        }

        return Result::Continue;
    }

    Result mapAggregateStructFields(const CastStructContext& ctx, std::vector<size_t>& srcToDst)
    {
        const auto& aggregate = ctx.srcType->payloadAggregate();
        const auto& srcTypes   = aggregate.types;
        const auto& srcNames   = aggregate.names;
        const auto& fieldRefs  = aggregate.fieldRefs;
        const auto& autoNames  = aggregate.autoNames;
        const auto& dstFields = ctx.dstType->payloadSymStruct().fields();

        if (srcTypes.size() > dstFields.size())
            return failStructFieldCount(ctx, srcTypes.size(), dstFields.size());

        SWC_ASSERT(srcNames.size() == srcTypes.size());
        SWC_ASSERT(fieldRefs.size() == srcTypes.size());
        srcToDst.assign(srcTypes.size(), static_cast<size_t>(-1));
        std::vector dstUsed(dstFields.size(), false);

        bool   seenNamed = false;
        size_t nextPos   = 0;
        for (size_t i = 0; i < srcTypes.size(); ++i)
        {
            const IdentifierRef name       = srcNames[i];
            const bool          positional = name.isInvalid() || (i < autoNames.size() && autoNames[i]);

            if (positional)
            {
                if (seenNamed)
                    return failStructField(ctx, i, DiagnosticId::sema_err_unnamed_parameter);

                while (nextPos < dstFields.size() && (dstUsed[nextPos] || !dstFields[nextPos] || dstFields[nextPos]->isIgnored()))
                    ++nextPos;
                if (nextPos >= dstFields.size())
                    return failStructFieldCountAt(ctx, i, srcTypes.size(), dstFields.size());

                srcToDst[i]      = nextPos;
                dstUsed[nextPos] = true;
                ++nextPos;
                continue;
            }

            seenNamed       = true;
            bool   found    = false;
            size_t dstIndex = 0;
            for (size_t j = 0; j < dstFields.size(); ++j)
            {
                const SymbolVariable* symbolVariable = dstFields[j];
                if (!symbolVariable || symbolVariable->isIgnored())
                    continue;
                if (symbolVariable->idRef() == name)
                {
                    found    = true;
                    dstIndex = j;
                    break;
                }
            }

            if (!found)
                return failStructField(ctx, i, DiagnosticId::sema_err_missing_struct_member, ctx.sema->idMgr().get(name).name);
            if (dstUsed[dstIndex])
                return failStructField(ctx, i, DiagnosticId::sema_err_struct_cast_duplicate_field, ctx.sema->idMgr().get(name).name);

            srcToDst[i]       = dstIndex;
            dstUsed[dstIndex] = true;
        }

        return Result::Continue;
    }

    Result validateAggregateStructElementCasts(const CastStructContext& ctx, const std::vector<TypeRef>& srcTypes, const std::vector<SymbolVariable*>& dstFields, const std::vector<size_t>& srcToDst)
    {
        const auto& fieldRefs = ctx.srcType->payloadAggregate().fieldRefs;
        for (size_t i = 0; i < srcTypes.size(); ++i)
        {
            const size_t dstIndex = srcToDst[i];
            RESULT_VERIFY(checkElemCast(ctx, srcTypes[i], dstFields[dstIndex]->typeRef(), fieldRefs[i]));
        }

        return Result::Continue;
    }

    Result foldAggregateStructConstant(const CastStructContext& ctx, const std::vector<size_t>& srcToDst)
    {
        const ConstantValue& cst       = ctx.sema->cstMgr().get(ctx.castCtx->constantFoldingSrc());
        const auto&          values    = cst.getAggregateStruct();
        const auto&          srcTypes  = ctx.srcType->payloadAggregate().types;
        const auto&          fieldRefs = ctx.srcType->payloadAggregate().fieldRefs;
        const auto&          dstFields = ctx.dstType->payloadSymStruct().fields();
        std::vector          castedByDst(dstFields.size(), ConstantRef::invalid());

        for (size_t i = 0; i < values.size(); ++i)
        {
            const size_t dstIndex = srcToDst[i];
            ConstantRef  castedRef;
            RESULT_VERIFY(foldElemCast(ctx, srcTypes[i], dstFields[dstIndex]->typeRef(), fieldRefs[i], values[i], castedRef));
            castedByDst[dstIndex] = castedRef;
        }

        const uint64_t         structSize = ctx.dstType->sizeOf(ctx.sema->ctx());
        std::vector<std::byte> buffer(structSize);
        if (structSize)
            std::ranges::fill(buffer, std::byte{0});

        const auto bytes = ByteSpan{buffer.data(), buffer.size()};
        for (size_t i = 0; i < dstFields.size(); ++i)
        {
            if (!castedByDst[i].isValid())
                continue;

            const auto* field = dstFields[i];
            if (!field || field->isIgnored())
                continue;

            const TypeRef   fieldTypeRef = field->typeRef();
            const TypeInfo& fieldType    = ctx.sema->typeMgr().get(fieldTypeRef);
            const uint64_t  fieldSize    = fieldType.sizeOf(ctx.sema->ctx());
            const uint64_t  fieldOffset  = field->offset();
            if (fieldOffset + fieldSize > bytes.size())
                return failStructConst(ctx);

            if (!ConstantHelpers::lowerToBytes(*ctx.sema, ByteSpan{bytes.data() + fieldOffset, fieldSize}, castedByDst[i], fieldTypeRef))
                return failStructConst(ctx);
        }

        const auto result        = ConstantValue::makeStruct(ctx.sema->ctx(), ctx.dstTypeRef, bytes);
        ctx.castCtx->outConstRef = ctx.sema->cstMgr().addConstant(ctx.sema->ctx(), result);
        return Result::Continue;
    }
}

Result Cast::castToStruct(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo&         srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo&         dstType = sema.typeMgr().get(dstTypeRef);
    const CastStructContext ctx{&sema, &castCtx, srcTypeRef, dstTypeRef, &srcType, &dstType};

    RESULT_VERIFY(sema.waitCompleted(&dstType, castCtx.errorNodeRef));

    if (srcType.isStruct())
    {
        RESULT_VERIFY(ctx.sema->waitCompleted(ctx.srcType, ctx.castCtx->errorNodeRef));
        return castStructToStruct(ctx);
    }

    if (srcType.isAggregateStruct())
    {
        std::vector<size_t> srcToDst;
        const auto&         srcTypes  = srcType.payloadAggregate().types;
        const auto&         dstFields = dstType.payloadSymStruct().fields();

        RESULT_VERIFY(mapAggregateStructFields(ctx, srcToDst));
        RESULT_VERIFY(validateAggregateStructElementCasts(ctx, srcTypes, dstFields, srcToDst));
        if (castCtx.isConstantFolding())
            RESULT_VERIFY(foldAggregateStructConstant(ctx, srcToDst));

        return Result::Continue;
    }

    return castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

SWC_END_NAMESPACE();
