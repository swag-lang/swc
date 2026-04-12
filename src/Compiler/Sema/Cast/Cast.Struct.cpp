#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
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
        if (args.srcType->isAggregateStruct())
            args.castRequest->failure.addArgument(Diagnostic::ARG_WHAT, "struct literal");
        args.castRequest->failure.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(srcCount));
        args.castRequest->failure.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(dstCount));
        return res;
    }

    Result failStructFieldType(const CastStructArgs& ctx, std::string_view fieldName)
    {
        return ctx.castRequest->fail(DiagnosticId::sema_err_struct_cast_field_type, ctx.srcTypeRef, ctx.dstTypeRef, fieldName);
    }

    void setStructFieldFailureNote(CastRequest& castRequest, DiagnosticId noteId, AstNodeRef noteNodeRef, std::string_view fieldName)
    {
        castRequest.failure.noteId      = noteId;
        castRequest.failure.noteNodeRef = noteNodeRef;
        castRequest.failure.addArgument(Diagnostic::ARG_VALUE, fieldName);
    }

    Result failStructMissingFieldNoDefault(const CastStructArgs& ctx, const SymbolVariable& field)
    {
        const std::string_view fieldName = field.name(ctx.sema->ctx());
        const Result           res       = ctx.castRequest->fail(DiagnosticId::sema_err_struct_cast_missing_field_no_default, ctx.srcTypeRef, ctx.dstTypeRef, fieldName);
        if (ctx.srcType->isAggregateStruct())
            ctx.castRequest->failure.addArgument(Diagnostic::ARG_WHAT, "struct literal");
        if (field.decl())
            setStructFieldFailureNote(*ctx.castRequest, DiagnosticId::sema_note_required_struct_field_declared_here, field.decl()->nodeRef(ctx.sema->ast()), fieldName);
        return res;
    }

    AstNodeRef aggregateFieldNodeRef(const CastStructArgs& args, size_t fieldIndex, size_t expectedCount)
    {
        if (!args.castRequest->errorNodeRef.isValid())
            return AstNodeRef::invalid();

        const AstNode& node = args.sema->node(args.castRequest->errorNodeRef);
        if (node.isNot(AstNodeId::StructLiteral))
            return AstNodeRef::invalid();

        const auto& literal = node.cast<AstStructLiteral>();
        if (literal.spanChildrenRef.isInvalid())
            return AstNodeRef::invalid();

        if (args.sema->ast().spanSize(literal.spanChildrenRef) != expectedCount)
            return AstNodeRef::invalid();

        return args.sema->ast().nthNode(literal.spanChildrenRef, fieldIndex);
    }

    SourceCodeRef aggregateFieldRef(const CastStructArgs& args, size_t fieldIndex, size_t expectedCount)
    {
        const AstNodeRef nodeRef = aggregateFieldNodeRef(args, fieldIndex, expectedCount);
        if (nodeRef.isInvalid())
            return SourceCodeRef::invalid();
        return args.sema->node(nodeRef).codeRef();
    }

    Result failStructField(const CastStructArgs& args, size_t fieldIndex, size_t expectedCount, DiagnosticId id, std::string_view value = "")
    {
        const SourceCodeRef previous = args.castRequest->errorCodeRef;
        const SourceCodeRef fieldRef = aggregateFieldRef(args, fieldIndex, expectedCount);
        if (fieldRef.isValid())
            args.castRequest->errorCodeRef = fieldRef;
        const Result res = args.castRequest->fail(id, args.srcTypeRef, args.dstTypeRef, value);
        if (id == DiagnosticId::sema_err_unnamed_parameter && args.srcType->isAggregateStruct())
            args.castRequest->failure.addArgument(Diagnostic::ARG_WHAT, "struct literal");
        if (id == DiagnosticId::sema_err_missing_struct_member)
        {
            const Utf8 availableFields = SemaError::formatStructFieldList(args.sema->ctx(), args.dstType->payloadSymStruct());
            if (!availableFields.empty())
            {
                args.castRequest->failure.noteId = DiagnosticId::sema_note_available_struct_fields;
                args.castRequest->failure.addArgument(Diagnostic::ARG_VALUES, availableFields);
            }
        }
        args.castRequest->errorCodeRef = previous;
        return res;
    }

    Result failStructFieldCountAt(const CastStructArgs& args, size_t fieldIndex, size_t expectedCount, size_t srcCount, size_t dstCount)
    {
        const SourceCodeRef previous = args.castRequest->errorCodeRef;
        const SourceCodeRef fieldRef = aggregateFieldRef(args, fieldIndex, expectedCount);
        if (fieldRef.isValid())
            args.castRequest->errorCodeRef = fieldRef;
        const Result res               = failStructFieldCount(args, srcCount, dstCount);
        args.castRequest->errorCodeRef = previous;
        return res;
    }

    CastRequest makeFieldCastRequest(const CastStructArgs& args, AstNodeRef fieldNodeRef, const SourceCodeRef& fieldRef)
    {
        CastRequest elemCtx(args.castRequest->kind);
        elemCtx.flags        = args.castRequest->flags;
        elemCtx.errorNodeRef = fieldNodeRef.isValid() ? fieldNodeRef : args.castRequest->errorNodeRef;
        elemCtx.errorCodeRef = fieldRef.isValid() ? fieldRef : args.castRequest->errorCodeRef;
        return elemCtx;
    }

    Result checkElemCast(const CastStructArgs& args, TypeRef srcElemType, TypeRef dstElemType, AstNodeRef fieldNodeRef, const SourceCodeRef& fieldRef)
    {
        CastRequest  elemCtx = makeFieldCastRequest(args, fieldNodeRef, fieldRef);
        const Result res     = Cast::castAllowed(*args.sema, elemCtx, srcElemType, dstElemType);
        if (res != Result::Continue)
            args.castRequest->failure = elemCtx.failure;
        return res;
    }

    Result foldElemCast(const CastStructArgs& args, TypeRef srcElemType, TypeRef dstElemType, AstNodeRef fieldNodeRef, const SourceCodeRef& fieldRef, ConstantRef valueRef, ConstantRef& outRef)
    {
        CastRequest elemCtx = makeFieldCastRequest(args, fieldNodeRef, fieldRef);
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

    enum class AffectCastRank : uint8_t
    {
        Bad,
        Standard,
        Exact,
    };

    bool allowsStructAffectCast(const SymbolFunction& calledFn, const CastKind castKind)
    {
        switch (castKind)
        {
            case CastKind::Explicit:
            case CastKind::Initialization:
                return true;

            case CastKind::Implicit:
            case CastKind::Parameter:
            case CastKind::Promotion:
                return calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Implicit);

            default:
                return false;
        }
    }

    AffectCastRank rankStructAffectCandidate(Sema& sema, const SourceCodeRef& codeRef, TypeRef srcTypeRef, TypeRef dstTypeRef, const SymbolFunction& calledFn)
    {
        if (calledFn.parameters().size() < 2)
            return AffectCastRank::Bad;

        const TypeRef paramTypeRef = calledFn.parameters()[1]->typeRef();
        if (!paramTypeRef.isValid())
            return AffectCastRank::Bad;
        if (paramTypeRef == dstTypeRef && srcTypeRef != paramTypeRef)
            return AffectCastRank::Bad;
        if (srcTypeRef == paramTypeRef)
            return AffectCastRank::Exact;

        CastRequest castRequest(CastKind::Parameter);
        castRequest.errorCodeRef = codeRef;
        const Result castResult  = Cast::castAllowed(sema, castRequest, srcTypeRef, paramTypeRef);
        if (castResult != Result::Continue)
            return AffectCastRank::Bad;

        return AffectCastRank::Standard;
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
        const auto& dstFields = args.dstType->payloadSymStruct().fields();

        SWC_ASSERT(srcNames.size() == srcTypes.size());
        srcToDst.assign(srcTypes.size(), static_cast<size_t>(-1));
        std::vector dstUsed(dstFields.size(), false);
        std::vector dstFieldInitRefs(dstFields.size(), AstNodeRef::invalid());

        bool   seenNamed = false;
        size_t nextPos   = 0;
        for (size_t i = 0; i < srcTypes.size(); ++i)
        {
            const IdentifierRef name         = srcNames[i];
            const bool          positional   = name.isInvalid();
            const AstNodeRef    fieldNodeRef = aggregateFieldNodeRef(args, i, srcTypes.size());

            if (positional)
            {
                if (seenNamed)
                    return failStructField(args, i, srcTypes.size(), DiagnosticId::sema_err_unnamed_parameter);

                while (nextPos < dstFields.size() && (dstUsed[nextPos] || !dstFields[nextPos]))
                    ++nextPos;
                if (nextPos >= dstFields.size())
                    return failStructFieldCountAt(args, i, srcTypes.size(), srcTypes.size(), dstFields.size());

                srcToDst[i]               = nextPos;
                dstUsed[nextPos]          = true;
                dstFieldInitRefs[nextPos] = fieldNodeRef;
                ++nextPos;
                continue;
            }

            seenNamed       = true;
            bool   found    = false;
            size_t dstIndex = 0;
            for (size_t j = 0; j < dstFields.size(); ++j)
            {
                const SymbolVariable* symbolVariable = dstFields[j];
                if (symbolVariable->idRef() == name)
                {
                    found    = true;
                    dstIndex = j;
                    break;
                }
            }

            if (!found)
                return failStructField(args, i, srcTypes.size(), DiagnosticId::sema_err_missing_struct_member, args.sema->idMgr().get(name).name);
            if (dstUsed[dstIndex])
            {
                const Result res = failStructField(args, i, srcTypes.size(), DiagnosticId::sema_err_struct_cast_duplicate_field, args.sema->idMgr().get(name).name);
                if (dstFieldInitRefs[dstIndex].isValid())
                    setStructFieldFailureNote(*args.castRequest, DiagnosticId::sema_note_previous_struct_field_initializer, dstFieldInitRefs[dstIndex], args.sema->idMgr().get(name).name);
                return res;
            }

            srcToDst[i]                = dstIndex;
            dstUsed[dstIndex]          = true;
            dstFieldInitRefs[dstIndex] = fieldNodeRef;
        }

        for (size_t i = 0; i < dstFields.size(); ++i)
        {
            if (dstUsed[i])
                continue;
            const SymbolVariable* field = dstFields[i];
            if (!field->hasExtraFlag(SymbolVariableFlagsE::ExplicitUndefined))
                continue;
            return failStructMissingFieldNoDefault(args, *field);
        }

        return Result::Continue;
    }

    Result validateAggregateStructElementCasts(const CastStructArgs& args, const std::vector<TypeRef>& srcTypes, const std::vector<SymbolVariable*>& dstFields, const std::vector<size_t>& srcToDst)
    {
        for (size_t i = 0; i < srcTypes.size(); ++i)
        {
            const size_t        dstIndex  = srcToDst[i];
            const AstNodeRef    fieldNode = aggregateFieldNodeRef(args, i, srcTypes.size());
            const SourceCodeRef fieldRef  = aggregateFieldRef(args, i, srcTypes.size());
            SWC_RESULT(checkElemCast(args, srcTypes[i], dstFields[dstIndex]->typeRef(), fieldNode, fieldRef));
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
        const auto&          dstFields = args.dstType->payloadSymStruct().fields();
        std::vector          castedByDst(dstFields.size(), ConstantRef::invalid());

        for (size_t i = 0; i < values.size(); ++i)
        {
            const size_t        dstIndex = srcToDst[i];
            ConstantRef         castedRef;
            const AstNodeRef    fieldNode = aggregateFieldNodeRef(args, i, values.size());
            const SourceCodeRef fieldRef  = aggregateFieldRef(args, i, values.size());
            SWC_RESULT(foldElemCast(args, srcTypes[i], dstFields[dstIndex]->typeRef(), fieldNode, fieldRef, values[i], castedRef));
            castedByDst[dstIndex] = castedRef;
        }

        for (size_t i = 0; i < dstFields.size(); ++i)
        {
            if (castedByDst[i].isValid())
                continue;
            const SymbolVariable* field = dstFields[i];
            if (!field)
                continue;
            castedByDst[i] = field->defaultValueRef();
        }

        const uint64_t structSize = args.dstType->sizeOf(args.sema->ctx());
        SWC_ASSERT(structSize);

        std::vector<std::byte> buffer(structSize);
        const ByteSpanRW       bytes = asByteSpan(buffer);

        for (size_t i = 0; i < dstFields.size(); ++i)
        {
            if (!castedByDst[i].isValid())
                continue;
            const TypeRef   fieldTypeRef = dstFields[i]->typeRef();
            const TypeInfo& fieldType    = args.sema->typeMgr().get(fieldTypeRef);
            const uint64_t  fieldSize    = fieldType.sizeOf(args.sema->ctx());
            const uint64_t  fieldOffset  = dstFields[i]->offset();
            SWC_ASSERT(fieldOffset + fieldSize <= bytes.size());
            SWC_RESULT(ConstantLower::lowerToBytes(*args.sema, ByteSpanRW{bytes.data() + fieldOffset, fieldSize}, castedByDst[i], fieldTypeRef));
        }

        args.castRequest->outConstRef = ConstantHelpers::materializeStaticPayloadConstant(*args.sema, args.dstTypeRef, ByteSpan{bytes.data(), bytes.size()});
        SWC_ASSERT(args.castRequest->outConstRef.isValid());
        return Result::Continue;
    }

}

Result Cast::castToStruct(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo&      srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo&      dstType = sema.typeMgr().get(dstTypeRef);
    const CastStructArgs ctx{&sema, &castRequest, srcTypeRef, dstTypeRef, &srcType, &dstType};

    SWC_RESULT(sema.waitSemaCompleted(&dstType, castRequest.errorNodeRef));

    if (srcType.isStruct())
    {
        SWC_RESULT(ctx.sema->waitSemaCompleted(ctx.srcType, ctx.castRequest->errorNodeRef));
        return castStructToStruct(ctx);
    }

    if (srcType.isAggregateStruct())
    {
        std::vector<size_t> srcToDst;
        const auto&         srcTypes  = srcType.payloadAggregate().types;
        const auto&         dstFields = dstType.payloadSymStruct().fields();

        SWC_RESULT(mapAggregateStructFields(ctx, srcToDst));
        SWC_RESULT(validateAggregateStructElementCasts(ctx, srcTypes, dstFields, srcToDst));
        SWC_RESULT(foldAggregateStructConstant(ctx, srcToDst));
        return Result::Continue;
    }

    SymbolFunction*     calledFn     = nullptr;
    TypeRef             paramTypeRef = TypeRef::invalid();
    const SourceCodeRef codeRef      = castRequest.errorCodeRef.isValid() ? castRequest.errorCodeRef : castRequest.errorNodeRef.isValid() ? sema.node(castRequest.errorNodeRef).codeRef()
                                                                                                                                          : sema.node(sema.curNodeRef()).codeRef();
    SWC_RESULT(resolveStructAffectCastCandidate(sema, codeRef, srcTypeRef, dstTypeRef, castRequest.kind, calledFn, paramTypeRef));
    if (calledFn)
        return Result::Continue;

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::resolveStructAffectCastCandidate(Sema& sema, const SourceCodeRef& codeRef, TypeRef srcTypeRef, TypeRef dstTypeRef, const CastKind castKind, SymbolFunction*& outCalledFn, TypeRef& outParamTypeRef)
{
    outCalledFn     = nullptr;
    outParamTypeRef = TypeRef::invalid();

    if (!srcTypeRef.isValid() || !dstTypeRef.isValid())
        return Result::Continue;

    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
    if (srcType.isStruct() || srcType.isAggregateStruct() || !dstType.isStruct())
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(&dstType, sema.curNodeRef()));

    const IdentifierRef opAffectId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpAffect);
    const auto          candidates = dstType.payloadSymStruct().getSpecOp(opAffectId);
    if (candidates.empty())
        return Result::Continue;

    auto            bestRank = AffectCastRank::Bad;
    SymbolFunction* bestFn   = nullptr;
    for (SymbolFunction* calledFn : candidates)
    {
        if (!calledFn || !allowsStructAffectCast(*calledFn, castKind))
            continue;

        const AffectCastRank rank = rankStructAffectCandidate(sema, codeRef, srcTypeRef, dstTypeRef, *calledFn);
        if (rank == AffectCastRank::Bad)
            continue;

        if (bestFn == nullptr || rank > bestRank)
        {
            bestRank = rank;
            bestFn   = calledFn;
        }
    }

    if (!bestFn)
        return Result::Continue;

    outCalledFn     = bestFn;
    outParamTypeRef = bestFn->parameters().size() >= 2 ? bestFn->parameters()[1]->typeRef() : TypeRef::invalid();
    return Result::Continue;
}

SWC_END_NAMESPACE();
