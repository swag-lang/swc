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
    struct CastStructArgs
    {
        Sema*           sema;
        CastRequest*    castRequest;
        TypeRef         srcTypeRef;
        TypeRef         dstTypeRef;
        const TypeInfo* srcType;
        const TypeInfo* dstType;
    };

    Result failStructFieldCount(const CastStructArgs& args, size_t srcCount, size_t dstCount)
    {
        const Result res = args.castRequest->fail(DiagnosticId::sema_err_struct_cast_field_count, args.srcTypeRef, args.dstTypeRef);
        args.castRequest->failure.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(srcCount));
        args.castRequest->failure.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(dstCount));
        return res;
    }

    Result failStructFieldType(const CastStructArgs& ctx, std::string_view fieldName)
    {
        return ctx.castRequest->fail(DiagnosticId::sema_err_struct_cast_field_type, ctx.srcTypeRef, ctx.dstTypeRef, fieldName);
    }

    Result failStructField(const CastStructArgs& args, size_t fieldIndex, DiagnosticId id, std::string_view value = "")
    {
        const auto&         fieldRefs = args.srcType->payloadAggregate().fieldRefs;
        const SourceCodeRef previous  = args.castRequest->errorCodeRef;
        const SourceCodeRef fieldRef  = fieldRefs[fieldIndex];
        if (fieldRef.isValid())
            args.castRequest->errorCodeRef = fieldRef;
        const Result res               = args.castRequest->fail(id, args.srcTypeRef, args.dstTypeRef, value);
        args.castRequest->errorCodeRef = previous;
        return res;
    }

    Result failStructFieldCountAt(const CastStructArgs& args, size_t fieldIndex, size_t srcCount, size_t dstCount)
    {
        const auto&         fieldRefs = args.srcType->payloadAggregate().fieldRefs;
        const SourceCodeRef previous  = args.castRequest->errorCodeRef;
        const SourceCodeRef fieldRef  = fieldRefs[fieldIndex];
        if (fieldRef.isValid())
            args.castRequest->errorCodeRef = fieldRef;
        const Result res               = failStructFieldCount(args, srcCount, dstCount);
        args.castRequest->errorCodeRef = previous;
        return res;
    }

    Result failStructConst(const CastStructArgs& args)
    {
        return args.castRequest->fail(DiagnosticId::sema_err_struct_cast_const, args.srcTypeRef, args.dstTypeRef);
    }

    Result checkElemCast(const CastStructArgs& args, TypeRef srcElemType, TypeRef dstElemType, SourceCodeRef fieldRef)
    {
        CastRequest elemCtx(args.castRequest->kind);
        elemCtx.flags        = args.castRequest->flags;
        elemCtx.errorNodeRef = args.castRequest->errorNodeRef;
        elemCtx.errorCodeRef = args.castRequest->errorCodeRef;
        if (fieldRef.isValid())
            elemCtx.errorCodeRef = fieldRef;
        const Result res = Cast::castAllowed(*args.sema, elemCtx, srcElemType, dstElemType);
        if (res != Result::Continue)
            args.castRequest->failure = elemCtx.failure;
        return res;
    }

    Result foldElemCast(const CastStructArgs& args, TypeRef srcElemType, TypeRef dstElemType, SourceCodeRef fieldRef, ConstantRef valueRef, ConstantRef& outRef)
    {
        CastRequest elemCtx(args.castRequest->kind);
        elemCtx.flags        = args.castRequest->flags;
        elemCtx.errorNodeRef = args.castRequest->errorNodeRef;
        elemCtx.errorCodeRef = args.castRequest->errorCodeRef;
        if (fieldRef.isValid())
            elemCtx.errorCodeRef = fieldRef;
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

    Result castStructToStruct(const CastStructArgs& args)
    {
        const auto& srcFields = args.srcType->payloadSymStruct().fields();
        const auto& dstFields = args.dstType->payloadSymStruct().fields();
        if (srcFields.size() != dstFields.size())
            return failStructFieldCount(args, srcFields.size(), dstFields.size());

        for (size_t i = 0; i < srcFields.size(); ++i)
        {
            if (srcFields[i]->typeRef() != dstFields[i]->typeRef())
                return failStructFieldType(args, dstFields[i]->name(args.sema->ctx()));
        }

        return Result::Continue;
    }

    Result mapAggregateStructFields(const CastStructArgs& args, std::vector<size_t>& srcToDst)
    {
        const auto& aggregate = args.srcType->payloadAggregate();
        const auto& srcTypes  = aggregate.types;
        const auto& srcNames  = aggregate.names;
        const auto& fieldRefs = aggregate.fieldRefs;
        const auto& dstFields = args.dstType->payloadSymStruct().fields();

        if (srcTypes.size() > dstFields.size())
            return failStructFieldCount(args, srcTypes.size(), dstFields.size());

        SWC_ASSERT(srcNames.size() == srcTypes.size());
        SWC_ASSERT(fieldRefs.size() == srcTypes.size());
        srcToDst.assign(srcTypes.size(), static_cast<size_t>(-1));
        std::vector dstUsed(dstFields.size(), false);

        bool   seenNamed = false;
        size_t nextPos   = 0;
        for (size_t i = 0; i < srcTypes.size(); ++i)
        {
            const IdentifierRef name       = srcNames[i];
            const bool          positional = name.isInvalid();

            if (positional)
            {
                if (seenNamed)
                    return failStructField(args, i, DiagnosticId::sema_err_unnamed_parameter);

                while (nextPos < dstFields.size() && (dstUsed[nextPos] || !dstFields[nextPos] || dstFields[nextPos]->isIgnored()))
                    ++nextPos;
                if (nextPos >= dstFields.size())
                    return failStructFieldCountAt(args, i, srcTypes.size(), dstFields.size());

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
                return failStructField(args, i, DiagnosticId::sema_err_missing_struct_member, args.sema->idMgr().get(name).name);
            if (dstUsed[dstIndex])
                return failStructField(args, i, DiagnosticId::sema_err_struct_cast_duplicate_field, args.sema->idMgr().get(name).name);

            srcToDst[i]       = dstIndex;
            dstUsed[dstIndex] = true;
        }

        return Result::Continue;
    }

    Result validateAggregateStructElementCasts(const CastStructArgs& args, const std::vector<TypeRef>& srcTypes, const std::vector<SymbolVariable*>& dstFields, const std::vector<size_t>& srcToDst)
    {
        const auto& fieldRefs = args.srcType->payloadAggregate().fieldRefs;
        for (size_t i = 0; i < srcTypes.size(); ++i)
        {
            const size_t dstIndex = srcToDst[i];
            RESULT_VERIFY(checkElemCast(args, srcTypes[i], dstFields[dstIndex]->typeRef(), fieldRefs[i]));
        }

        return Result::Continue;
    }

    Result foldAggregateStructConstant(const CastStructArgs& args, const std::vector<size_t>& srcToDst)
    {
        if (!args.castRequest->isConstantFolding())
            return Result::Continue;

        const ConstantValue& cst       = args.sema->cstMgr().get(args.castRequest->constantFoldingSrc());
        const auto&          values    = cst.getAggregateStruct();
        const auto&          srcTypes  = args.srcType->payloadAggregate().types;
        const auto&          fieldRefs = args.srcType->payloadAggregate().fieldRefs;
        const auto&          dstFields = args.dstType->payloadSymStruct().fields();
        std::vector          castedByDst(dstFields.size(), ConstantRef::invalid());

        for (size_t i = 0; i < values.size(); ++i)
        {
            const size_t dstIndex = srcToDst[i];
            ConstantRef  castedRef;
            RESULT_VERIFY(foldElemCast(args, srcTypes[i], dstFields[dstIndex]->typeRef(), fieldRefs[i], values[i], castedRef));
            castedByDst[dstIndex] = castedRef;
        }

        for (size_t i = 0; i < dstFields.size(); ++i)
        {
            if (castedByDst[i].isValid())
                continue;
            const auto* field = dstFields[i];
            if (!field || field->isIgnored())
                continue;
            castedByDst[i] = field->defaultValueRef();
        }

        const uint64_t structSize = args.dstType->sizeOf(args.sema->ctx());
        SWC_ASSERT(structSize);

        const std::vector<std::byte> buffer(structSize);
        const auto                   bytes = asByteSpan(buffer);

        for (size_t i = 0; i < dstFields.size(); ++i)
        {
            if (!castedByDst[i].isValid())
                continue;

            const auto* field = dstFields[i];
            if (!field || field->isIgnored())
                continue;

            const TypeRef   fieldTypeRef = field->typeRef();
            const TypeInfo& fieldType    = args.sema->typeMgr().get(fieldTypeRef);
            const uint64_t  fieldSize    = fieldType.sizeOf(args.sema->ctx());
            const uint64_t  fieldOffset  = field->offset();
            if (fieldOffset + fieldSize > bytes.size())
                return failStructConst(args);

            ConstantHelpers::lowerToBytes(*args.sema, ByteSpan{bytes.data() + fieldOffset, fieldSize}, castedByDst[i], fieldTypeRef);
        }

        const auto result             = ConstantValue::makeStruct(args.sema->ctx(), args.dstTypeRef, bytes);
        args.castRequest->outConstRef = args.sema->cstMgr().addConstant(args.sema->ctx(), result);
        return Result::Continue;
    }
}

Result Cast::castToStruct(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo&      srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo&      dstType = sema.typeMgr().get(dstTypeRef);
    const CastStructArgs ctx{&sema, &castRequest, srcTypeRef, dstTypeRef, &srcType, &dstType};

    RESULT_VERIFY(sema.waitCompleted(&dstType, castRequest.errorNodeRef));

    if (srcType.isStruct())
    {
        RESULT_VERIFY(ctx.sema->waitCompleted(ctx.srcType, ctx.castRequest->errorNodeRef));
        return castStructToStruct(ctx);
    }

    if (srcType.isAggregateStruct())
    {
        std::vector<size_t> srcToDst;
        const auto&         srcTypes  = srcType.payloadAggregate().types;
        const auto&         dstFields = dstType.payloadSymStruct().fields();

        RESULT_VERIFY(mapAggregateStructFields(ctx, srcToDst));
        RESULT_VERIFY(validateAggregateStructElementCasts(ctx, srcTypes, dstFields, srcToDst));
        RESULT_VERIFY(foldAggregateStructConstant(ctx, srcToDst));
        return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

SWC_END_NAMESPACE();
