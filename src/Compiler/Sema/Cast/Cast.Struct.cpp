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

    Result castStructToStruct(const CastStructContext& ctx)
    {
        RESULT_VERIFY(ctx.sema->waitCompleted(ctx.srcType, ctx.castCtx->errorNodeRef));
        RESULT_VERIFY(ctx.sema->waitCompleted(ctx.dstType, ctx.castCtx->errorNodeRef));

        const auto& srcFields = ctx.srcType->payloadSymStruct().fields();
        const auto& dstFields = ctx.dstType->payloadSymStruct().fields();
        if (srcFields.size() != dstFields.size())
        {
            const std::string value = "src=" + std::to_string(srcFields.size()) + " dst=" + std::to_string(dstFields.size());
            ctx.castCtx->fail(DiagnosticId::sema_err_struct_cast_field_count, ctx.srcTypeRef, ctx.dstTypeRef, value);
            return Result::Error;
        }

        for (size_t i = 0; i < srcFields.size(); ++i)
        {
            if (srcFields[i]->typeRef() != dstFields[i]->typeRef())
            {
                ctx.castCtx->fail(DiagnosticId::sema_err_struct_cast_field_type, ctx.srcTypeRef, ctx.dstTypeRef, dstFields[i]->name(ctx.sema->ctx()));
                return Result::Error;
            }
        }

        return Result::Continue;
    }

    bool isAutoName(const Sema& sema, IdentifierRef name, size_t index)
    {
        if (!name.isValid())
            return true;
        const std::string_view nameStr  = sema.idMgr().get(name).name;
        const std::string      expected = "item" + std::to_string(index);
        return nameStr == expected;
    }

    Result mapAggregateStructFields(const CastStructContext& ctx, std::vector<size_t>& srcToDst)
    {
        const auto& aggregate = ctx.srcType->payloadAggregate();
        const auto& srcTypes  = aggregate.types;
        const auto& srcNames  = aggregate.names;
        const auto& fieldRefs = aggregate.fieldRefs;
        const auto& dstFields = ctx.dstType->payloadSymStruct().fields();

        auto failAtField = [&](size_t fieldIndex, DiagnosticId id, std::string_view value = "") {
            const AstNodeRef previousRef = ctx.castCtx->errorNodeRef;
            const AstNodeRef fieldRef    = fieldRefs[fieldIndex];
            if (fieldRef.isValid())
                ctx.castCtx->errorNodeRef = fieldRef;
            ctx.castCtx->fail(id, ctx.srcTypeRef, ctx.dstTypeRef, value);
            ctx.castCtx->errorNodeRef = previousRef;
            return Result::Error;
        };

        if (srcTypes.size() > dstFields.size())
        {
            const std::string value = "src=" + std::to_string(srcTypes.size()) + " dst=" + std::to_string(dstFields.size());
            ctx.castCtx->fail(DiagnosticId::sema_err_struct_cast_field_count, ctx.srcTypeRef, ctx.dstTypeRef, value);
            return Result::Error;
        }

        SWC_ASSERT(srcNames.size() == srcTypes.size());
        SWC_ASSERT(fieldRefs.size() == srcTypes.size());
        srcToDst.assign(srcTypes.size(), static_cast<size_t>(-1));
        std::vector dstUsed(dstFields.size(), false);

        bool   seenNamed = false;
        size_t nextPos   = 0;
        for (size_t i = 0; i < srcTypes.size(); ++i)
        {
            const IdentifierRef name       = srcNames[i];
            const bool          positional = name.isInvalid() || isAutoName(*ctx.sema, name, i);

            if (positional)
            {
                if (seenNamed)
                    return failAtField(i, DiagnosticId::sema_err_unnamed_parameter);

                while (nextPos < dstFields.size() && (dstUsed[nextPos] || !dstFields[nextPos] || dstFields[nextPos]->isIgnored()))
                    ++nextPos;
                if (nextPos >= dstFields.size())
                    return failAtField(i, DiagnosticId::sema_err_struct_cast_field_count);

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
                return failAtField(i, DiagnosticId::sema_err_missing_struct_member, ctx.sema->idMgr().get(name).name);

            if (dstUsed[dstIndex])
                return failAtField(i, DiagnosticId::sema_err_struct_cast_duplicate_field, ctx.sema->idMgr().get(name).name);

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
            CastContext elemCtx(ctx.castCtx->kind);
            elemCtx.flags        = ctx.castCtx->flags;
            elemCtx.errorNodeRef = ctx.castCtx->errorNodeRef;
            if (fieldRefs[i].isValid())
                elemCtx.errorNodeRef = fieldRefs[i];

            const size_t dstIndex = srcToDst[i];
            const Result res      = Cast::castAllowed(*ctx.sema, elemCtx, srcTypes[i], dstFields[dstIndex]->typeRef());
            if (res != Result::Continue)
            {
                ctx.castCtx->failure = elemCtx.failure;
                return res;
            }
        }

        return Result::Continue;
    }

    Result foldAggregateStructConstant(const CastStructContext& ctx, const std::vector<size_t>& srcToDst)
    {
        const ConstantValue& cst = ctx.sema->cstMgr().get(ctx.castCtx->constantFoldingSrc());
        if (!cst.isAggregateStruct())
            return Result::Continue;

        const auto& values    = cst.getAggregateStruct();
        const auto& srcTypes  = ctx.srcType->payloadAggregate().types;
        const auto& fieldRefs = ctx.srcType->payloadAggregate().fieldRefs;
        const auto& dstFields = ctx.dstType->payloadSymStruct().fields();
        std::vector castedByDst(dstFields.size(), ConstantRef::invalid());

        for (size_t i = 0; i < values.size(); ++i)
        {
            CastContext elemCtx(ctx.castCtx->kind);
            elemCtx.flags        = ctx.castCtx->flags;
            elemCtx.errorNodeRef = ctx.castCtx->errorNodeRef;
            if (fieldRefs[i].isValid())
                elemCtx.errorNodeRef = fieldRefs[i];
            elemCtx.setConstantFoldingSrc(values[i]);

            const size_t dstIndex = srcToDst[i];
            const Result res      = Cast::castAllowed(*ctx.sema, elemCtx, srcTypes[i], dstFields[dstIndex]->typeRef());
            if (res != Result::Continue)
            {
                ctx.castCtx->failure = elemCtx.failure;
                return res;
            }

            ConstantRef castedRef = elemCtx.constantFoldingResult();
            if (castedRef.isInvalid())
                castedRef = values[i];
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
            {
                ctx.castCtx->fail(DiagnosticId::sema_err_struct_cast_const, ctx.srcTypeRef, ctx.dstTypeRef);
                return Result::Error;
            }

            if (!ConstantHelpers::lowerToBytes(*ctx.sema, ByteSpan{bytes.data() + fieldOffset, fieldSize}, castedByDst[i], fieldTypeRef))
            {
                ctx.castCtx->fail(DiagnosticId::sema_err_struct_cast_const, ctx.srcTypeRef, ctx.dstTypeRef);
                return Result::Error;
            }
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

    if (srcType.isStruct())
        return castStructToStruct(ctx);

    if (srcType.isAggregateStruct())
    {
        RESULT_VERIFY(sema.waitCompleted(&dstType, castCtx.errorNodeRef));

        std::vector<size_t> srcToDst;
        RESULT_VERIFY(mapAggregateStructFields(ctx, srcToDst));

        const auto& srcTypes  = srcType.payloadAggregate().types;
        const auto& dstFields = dstType.payloadSymStruct().fields();
        RESULT_VERIFY(validateAggregateStructElementCasts(ctx, srcTypes, dstFields, srcToDst));

        if (castCtx.isConstantFolding())
            RESULT_VERIFY(foldAggregateStructConstant(ctx, srcToDst));

        return Result::Continue;
    }

    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
    return Result::Error;
}

SWC_END_NAMESPACE();
