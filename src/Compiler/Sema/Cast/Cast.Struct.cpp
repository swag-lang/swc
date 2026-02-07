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
    Result castStructToStruct(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef, const TypeInfo& srcType, const TypeInfo& dstType)
    {
        RESULT_VERIFY(sema.waitCompleted(&srcType, castCtx.errorNodeRef));
        RESULT_VERIFY(sema.waitCompleted(&dstType, castCtx.errorNodeRef));

        const auto& srcFields = srcType.payloadSymStruct().fields();
        const auto& dstFields = dstType.payloadSymStruct().fields();
        if (srcFields.size() != dstFields.size())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return Result::Error;
        }

        for (size_t i = 0; i < srcFields.size(); ++i)
        {
            if (srcFields[i]->typeRef() != dstFields[i]->typeRef())
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
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

    Result mapAggregateStructFields(Sema&                sema,
                                    CastContext&         castCtx,
                                    const TypeInfo&      srcType,
                                    const TypeInfo&      dstType,
                                    TypeRef              srcTypeRef,
                                    TypeRef              dstTypeRef,
                                    std::vector<size_t>& srcToDst)
    {
        const auto& srcTypes  = srcType.payloadAggregateTypes();
        const auto& srcNames  = srcType.payloadAggregateNames();
        const auto& dstFields = dstType.payloadSymStruct().fields();

        if (srcTypes.size() > dstFields.size())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return Result::Error;
        }

        const bool hasNames = srcNames.size() == srcTypes.size();
        srcToDst.assign(srcTypes.size(), static_cast<size_t>(-1));
        std::vector<bool> dstUsed(dstFields.size(), false);

        bool   seenNamed = false;
        size_t nextPos   = 0;
        for (size_t i = 0; i < srcTypes.size(); ++i)
        {
            const IdentifierRef name       = hasNames ? srcNames[i] : IdentifierRef::invalid();
            const bool          positional = !name.isValid() || isAutoName(sema, name, i);

            if (positional)
            {
                if (seenNamed)
                {
                    castCtx.fail(DiagnosticId::sema_err_unnamed_parameter, srcTypeRef, dstTypeRef);
                    return Result::Error;
                }

                while (nextPos < dstFields.size() && (dstUsed[nextPos] || !dstFields[nextPos] || dstFields[nextPos]->isIgnored()))
                    ++nextPos;
                if (nextPos >= dstFields.size())
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                    return Result::Error;
                }

                srcToDst[i]      = nextPos;
                dstUsed[nextPos] = true;
                ++nextPos;
                continue;
            }

            seenNamed       = true;
            size_t dstIndex = static_cast<size_t>(-1);
            for (size_t j = 0; j < dstFields.size(); ++j)
            {
                if (dstFields[j] && !dstFields[j]->isIgnored() && dstFields[j]->idRef() == name)
                {
                    dstIndex = j;
                    break;
                }
            }

            if (dstIndex == static_cast<size_t>(-1))
            {
                castCtx.fail(DiagnosticId::sema_err_auto_scope_missing_struct_member, srcTypeRef, dstTypeRef, sema.idMgr().get(name).name);
                return Result::Error;
            }

            if (dstUsed[dstIndex])
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                return Result::Error;
            }

            srcToDst[i]       = dstIndex;
            dstUsed[dstIndex] = true;
        }

        return Result::Continue;
    }

    Result validateAggregateStructElementCasts(Sema&                               sema,
                                               CastContext&                        castCtx,
                                               const std::vector<TypeRef>&         srcTypes,
                                               const std::vector<SymbolVariable*>& dstFields,
                                               const std::vector<size_t>&          srcToDst)
    {
        for (size_t i = 0; i < srcTypes.size(); ++i)
        {
            CastContext elemCtx(castCtx.kind);
            elemCtx.flags        = castCtx.flags;
            elemCtx.errorNodeRef = castCtx.errorNodeRef;

            const size_t dstIndex = srcToDst[i];
            const Result res      = Cast::castAllowed(sema, elemCtx, srcTypes[i], dstFields[dstIndex]->typeRef());
            if (res != Result::Continue)
            {
                castCtx.failure = elemCtx.failure;
                return res;
            }
        }

        return Result::Continue;
    }

    Result foldAggregateStructConstant(Sema&                      sema,
                                       CastContext&               castCtx,
                                       TypeRef                    srcTypeRef,
                                       TypeRef                    dstTypeRef,
                                       const TypeInfo&            srcType,
                                       const TypeInfo&            dstType,
                                       const std::vector<size_t>& srcToDst)
    {
        const ConstantValue& cst = sema.cstMgr().get(castCtx.constantFoldingSrc());
        if (!cst.isAggregateStruct())
            return Result::Continue;

        const auto&              values    = cst.getAggregateStruct();
        const auto&              srcTypes  = srcType.payloadAggregateTypes();
        const auto&              dstFields = dstType.payloadSymStruct().fields();
        std::vector<ConstantRef> castedByDst(dstFields.size(), ConstantRef::invalid());

        for (size_t i = 0; i < values.size(); ++i)
        {
            CastContext elemCtx(castCtx.kind);
            elemCtx.flags        = castCtx.flags;
            elemCtx.errorNodeRef = castCtx.errorNodeRef;
            elemCtx.setConstantFoldingSrc(values[i]);

            const size_t dstIndex = srcToDst[i];
            const Result res      = Cast::castAllowed(sema, elemCtx, srcTypes[i], dstFields[dstIndex]->typeRef());
            if (res != Result::Continue)
            {
                castCtx.failure = elemCtx.failure;
                return res;
            }

            ConstantRef castedRef = elemCtx.constantFoldingResult();
            if (castedRef.isInvalid())
                castedRef = values[i];
            castedByDst[dstIndex] = castedRef;
        }

        const uint64_t         structSize = dstType.sizeOf(sema.ctx());
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
            const TypeInfo& fieldType    = sema.typeMgr().get(fieldTypeRef);
            const uint64_t  fieldSize    = fieldType.sizeOf(sema.ctx());
            const uint64_t  fieldOffset  = field->offset();
            if (fieldOffset + fieldSize > bytes.size())
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                return Result::Error;
            }

            if (!ConstantHelpers::lowerToBytes(sema, ByteSpan{bytes.data() + fieldOffset, fieldSize}, castedByDst[i], fieldTypeRef))
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                return Result::Error;
            }
        }

        const auto result   = ConstantValue::makeStruct(sema.ctx(), dstTypeRef, bytes);
        castCtx.outConstRef = sema.cstMgr().addConstant(sema.ctx(), result);
        return Result::Continue;
    }
}

Result Cast::castToStruct(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

    if (srcType.isStruct())
        return castStructToStruct(sema, castCtx, srcTypeRef, dstTypeRef, srcType, dstType);

    if (srcType.isAggregateStruct())
    {
        RESULT_VERIFY(sema.waitCompleted(&dstType, castCtx.errorNodeRef));

        std::vector<size_t> srcToDst;
        Result              res = mapAggregateStructFields(sema, castCtx, srcType, dstType, srcTypeRef, dstTypeRef, srcToDst);
        if (res != Result::Continue)
            return res;

        const auto& srcTypes  = srcType.payloadAggregateTypes();
        const auto& dstFields = dstType.payloadSymStruct().fields();

        res = validateAggregateStructElementCasts(sema, castCtx, srcTypes, dstFields, srcToDst);
        if (res != Result::Continue)
            return res;

        if (castCtx.isConstantFolding())
        {
            res = foldAggregateStructConstant(sema, castCtx, srcTypeRef, dstTypeRef, srcType, dstType, srcToDst);
            if (res != Result::Continue)
                return res;
        }

        return Result::Continue;
    }

    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
    return Result::Error;
}

SWC_END_NAMESPACE();
