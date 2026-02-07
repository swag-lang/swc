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
            ctx.castCtx->fail(DiagnosticId::sema_err_cannot_cast, ctx.srcTypeRef, ctx.dstTypeRef);
            return Result::Error;
        }

        for (size_t i = 0; i < srcFields.size(); ++i)
        {
            if (srcFields[i]->typeRef() != dstFields[i]->typeRef())
            {
                ctx.castCtx->fail(DiagnosticId::sema_err_cannot_cast, ctx.srcTypeRef, ctx.dstTypeRef);
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
        const auto& dstFields = ctx.dstType->payloadSymStruct().fields();

        if (srcTypes.size() > dstFields.size())
        {
            ctx.castCtx->fail(DiagnosticId::sema_err_cannot_cast, ctx.srcTypeRef, ctx.dstTypeRef);
            return Result::Error;
        }

        SWC_ASSERT(srcNames.size() == srcTypes.size());
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
                {
                    ctx.castCtx->fail(DiagnosticId::sema_err_unnamed_parameter, ctx.srcTypeRef, ctx.dstTypeRef);
                    return Result::Error;
                }

                while (nextPos < dstFields.size() && (dstUsed[nextPos] || !dstFields[nextPos] || dstFields[nextPos]->isIgnored()))
                    ++nextPos;
                if (nextPos >= dstFields.size())
                {
                    ctx.castCtx->fail(DiagnosticId::sema_err_cannot_cast, ctx.srcTypeRef, ctx.dstTypeRef);
                    return Result::Error;
                }

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
            {
                ctx.castCtx->fail(DiagnosticId::sema_err_auto_scope_missing_struct_member, ctx.srcTypeRef, ctx.dstTypeRef, ctx.sema->idMgr().get(name).name);
                return Result::Error;
            }

            if (dstUsed[dstIndex])
            {
                ctx.castCtx->fail(DiagnosticId::sema_err_cannot_cast, ctx.srcTypeRef, ctx.dstTypeRef);
                return Result::Error;
            }

            srcToDst[i]       = dstIndex;
            dstUsed[dstIndex] = true;
        }

        return Result::Continue;
    }

    Result validateAggregateStructElementCasts(const CastStructContext& ctx, const std::vector<TypeRef>& srcTypes, const std::vector<SymbolVariable*>& dstFields, const std::vector<size_t>& srcToDst)
    {
        for (size_t i = 0; i < srcTypes.size(); ++i)
        {
            CastContext elemCtx(ctx.castCtx->kind);
            elemCtx.flags        = ctx.castCtx->flags;
            elemCtx.errorNodeRef = ctx.castCtx->errorNodeRef;

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
        const auto& dstFields = ctx.dstType->payloadSymStruct().fields();
        std::vector castedByDst(dstFields.size(), ConstantRef::invalid());

        for (size_t i = 0; i < values.size(); ++i)
        {
            CastContext elemCtx(ctx.castCtx->kind);
            elemCtx.flags        = ctx.castCtx->flags;
            elemCtx.errorNodeRef = ctx.castCtx->errorNodeRef;
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
                ctx.castCtx->fail(DiagnosticId::sema_err_cannot_cast, ctx.srcTypeRef, ctx.dstTypeRef);
                return Result::Error;
            }

            if (!ConstantHelpers::lowerToBytes(*ctx.sema, ByteSpan{bytes.data() + fieldOffset, fieldSize}, castedByDst[i], fieldTypeRef))
            {
                ctx.castCtx->fail(DiagnosticId::sema_err_cannot_cast, ctx.srcTypeRef, ctx.dstTypeRef);
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
