#include "pch.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result makeScalarFieldConstantFromBytes(Sema& sema, TypeRef fieldTypeRef, std::span<const std::byte> bytes, ConstantRef& outCstRef)
    {
        outCstRef = ConstantRef::invalid();
        if (!fieldTypeRef.isValid())
            return Result::Continue;

        TaskContext&    ctx       = sema.ctx();
        const TypeInfo& fieldType = sema.typeMgr().get(fieldTypeRef);
        if (fieldType.isAlias())
        {
            const TypeRef unwrappedTypeRef = fieldType.unwrap(ctx, fieldTypeRef, TypeExpandE::Alias);
            if (!unwrappedTypeRef.isValid())
                return Result::Continue;

            ConstantRef scalarCstRef = ConstantRef::invalid();
            SWC_RESULT(makeScalarFieldConstantFromBytes(sema, unwrappedTypeRef, bytes, scalarCstRef));
            if (!scalarCstRef.isValid())
                return Result::Continue;

            ConstantValue scalarValue = sema.cstMgr().get(scalarCstRef);
            scalarValue.setTypeRef(fieldTypeRef);
            outCstRef = sema.cstMgr().addConstant(ctx, scalarValue);
            return Result::Continue;
        }

        if (fieldType.isEnum())
        {
            ConstantRef underlyingCstRef = ConstantRef::invalid();
            SWC_RESULT(makeScalarFieldConstantFromBytes(sema, fieldType.payloadSymEnum().underlyingTypeRef(), bytes, underlyingCstRef));
            if (!underlyingCstRef.isValid())
                return Result::Continue;

            outCstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeEnumValue(ctx, underlyingCstRef, fieldTypeRef));
            return Result::Continue;
        }

        if (!fieldType.isBool() &&
            !fieldType.isChar() &&
            !fieldType.isRune() &&
            !fieldType.isInt() &&
            !fieldType.isFloat())
            return Result::Continue;

        ConstantValue fieldValue = ConstantValue::make(ctx, bytes.data(), fieldTypeRef, ConstantValue::PayloadOwnership::Borrowed);
        if (!fieldValue.isValid())
            return Result::Continue;

        outCstRef = sema.cstMgr().addConstant(ctx, fieldValue);
        return Result::Continue;
    }

    Result failStructMemberType(Sema& sema, const SymbolVariable& symVar, AstNodeRef nodeMemberRef)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_cst_struct_member_type, nodeMemberRef);
        diag.addArgument(Diagnostic::ARG_TYPE, symVar.typeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result getStructBytesFromConstant(Sema& sema, std::span<const std::byte>& bytes, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeMemberRef)
    {
        if (cst.isStruct())
        {
            bytes = cst.getStruct();
            return Result::Continue;
        }

        if (cst.isValuePointer() || cst.isBlockPointer())
        {
            const TypeInfo& cstType = sema.typeMgr().get(cst.typeRef());
            TypeRef         pointedTypeRef;
            if (cstType.isAnyPointer() || cstType.isReference() || cstType.isMoveReference())
                pointedTypeRef = cstType.payloadTypeRef();
            else if (cstType.isTypeInfo())
            {
                // The constant is typed as *TypeInfo (base), but the actual data
                // may be a derived struct (e.g. TypeInfoArray). Use the field's
                // owner struct to determine the correct data size.
                const SymbolMap* ownerMap = symVar.ownerSymMap();
                if (ownerMap && ownerMap->isStruct())
                    pointedTypeRef = ownerMap->cast<SymbolStruct>().typeRef();
                else
                    pointedTypeRef = sema.typeMgr().structTypeInfo();
            }
            else
                SWC_UNREACHABLE();

            const TypeInfo& pointedType = sema.typeMgr().get(pointedTypeRef);
            SWC_ASSERT(pointedType.isStruct());
            const uint64_t ptr = cst.isValuePointer() ? cst.getValuePointer() : cst.getBlockPointer();
            SWC_ASSERT(ptr);
            bytes = std::span{reinterpret_cast<const std::byte*>(static_cast<uintptr_t>(ptr)), pointedType.sizeOf(sema.ctx())};
            return Result::Continue;
        }

        if (cst.isSlice())
        {
            bytes = cst.getSlice();
            return Result::Continue;
        }

        return failStructMemberType(sema, symVar, nodeMemberRef);
    }

    void extractAggregateStructMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef)
    {
        const auto&      values = cst.getAggregateStruct();
        const SymbolMap* owner  = symVar.ownerSymMap();
        if (!owner || !owner->isStruct())
        {
            failStructMemberType(sema, symVar, nodeMemberRef);
            return;
        }
        const auto& sym = owner->cast<SymbolStruct>();

        size_t fieldIndex = 0;
        if (!sym.tryGetFieldIndex(fieldIndex, symVar))
        {
            failStructMemberType(sema, symVar, nodeMemberRef);
            return;
        }
        if (std::cmp_greater_equal(fieldIndex, values.size()))
        {
            failStructMemberType(sema, symVar, nodeMemberRef);
            return;
        }

        sema.setConstant(nodeRef, values[fieldIndex]);
    }

    Result makeFieldConstantFromBytes(Sema& sema, TypeRef fieldTypeRef, const TypeInfo& typeField, std::span<const std::byte> bytes, ConstantRef& outCstRef, const SymbolVariable& symVar, AstNodeRef nodeMemberRef)
    {
        SWC_RESULT(ConstantHelpers::waitStaticPayloadTypeReady(sema, fieldTypeRef, nodeMemberRef));
        SWC_UNUSED(typeField);
        SWC_RESULT(makeScalarFieldConstantFromBytes(sema, fieldTypeRef, bytes, outCstRef));
        if (outCstRef.isValid())
            return Result::Continue;

        outCstRef = ConstantHelpers::materializeStaticPayloadConstant(sema, fieldTypeRef, bytes);
        if (outCstRef.isInvalid())
            return failStructMemberType(sema, symVar, nodeMemberRef);
        return Result::Continue;
    }
}

Result ConstantExtract::structMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef)
{
    TaskContext& ctx = sema.ctx();

    if (cst.isAggregateStruct())
    {
        extractAggregateStructMember(sema, cst, symVar, nodeRef, nodeMemberRef);
        return Result::Continue;
    }

    std::span<const std::byte> bytes;
    SWC_RESULT(getStructBytesFromConstant(sema, bytes, cst, symVar, nodeMemberRef));

    const TypeInfo& typeVar   = symVar.typeInfo(ctx);
    const TypeInfo* typeField = &typeVar;
    SWC_ASSERT(symVar.offset() + typeField->sizeOf(ctx) <= bytes.size());
    const auto fieldBytes = std::span{bytes.data() + symVar.offset(), typeField->sizeOf(ctx)};

    ConstantRef cstRef = ConstantRef::invalid();
    SWC_RESULT(makeFieldConstantFromBytes(sema, symVar.typeRef(), *typeField, fieldBytes, cstRef, symVar, nodeMemberRef));

    sema.setConstant(nodeRef, cstRef);
    return Result::Continue;
}

namespace
{
    TypeRef unwrapAliasTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& typeInfo         = sema.typeMgr().get(typeRef);
        const TypeRef   unwrappedTypeRef = typeInfo.unwrap(sema.ctx(), typeRef, TypeExpandE::Alias);
        return unwrappedTypeRef.isValid() ? unwrappedTypeRef : typeRef;
    }

    Result extractAtIndexAggregateArray(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        outCstRef          = ConstantRef::invalid();
        const auto& values = cst.getAggregateArray();
        if (std::cmp_greater_equal(constIndex, values.size()))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, values.size());
        outCstRef = values[constIndex];
        return Result::Continue;
    }

    Result extractAtIndexString(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        outCstRef                = ConstantRef::invalid();
        const std::string_view s = cst.getString();
        if (std::cmp_greater_equal(constIndex, s.size()))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, s.size());
        const ConstantValue cstInt = ConstantValue::makeIntSized(sema.ctx(), static_cast<uint8_t>(s[constIndex]));
        outCstRef                  = sema.cstMgr().addConstant(sema.ctx(), cstInt);
        return Result::Continue;
    }

    Result extractAtIndexBytes(Sema& sema, std::span<const std::byte> bytes, TypeRef elemTypeRef, int64_t constIndex, uint64_t count, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        outCstRef                = ConstantRef::invalid();
        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& elemType = sema.typeMgr().get(elemTypeRef);
        SWC_RESULT(ConstantHelpers::waitStaticPayloadTypeReady(sema, elemTypeRef, nodeArgRef));
        const uint64_t elemSize = elemType.sizeOf(ctx);
        SWC_ASSERT(elemSize);

        if (std::cmp_greater_equal(constIndex, count))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, count);

        const auto        elemBytes  = std::span{bytes.data() + (constIndex * elemSize), elemSize};
        const ConstantRef elemCstRef = ConstantHelpers::materializeStaticPayloadConstant(sema, elemTypeRef, elemBytes);

        if (elemCstRef.isInvalid())
            return Result::Continue;

        outCstRef = elemCstRef;
        return Result::Continue;
    }

    Result extractAtIndexArray(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        outCstRef                = ConstantRef::invalid();
        TaskContext&    ctx      = sema.ctx();
        const TypeRef   typeRef  = unwrapAliasTypeRef(sema, cst.typeRef());
        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        SWC_ASSERT(typeInfo.isArray());
        const auto&    dims  = typeInfo.payloadArrayDims();
        const uint64_t count = dims.empty() ? 0 : dims[0];
        if (std::cmp_greater_equal(constIndex, count))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, count);

        if (dims.size() > 1)
        {
            const TypeRef nextTypeRef = sema.typeMgr().addType(typeInfo.makeArrayAfterFirstDimension());
            SWC_RESULT(ConstantHelpers::waitStaticPayloadTypeReady(sema, nextTypeRef, nodeArgRef));
            const uint64_t    nextSize   = sema.typeMgr().get(nextTypeRef).sizeOf(ctx);
            const std::span   nextBytes  = {cst.getArray().data() + (constIndex * nextSize), nextSize};
            const ConstantRef nextCstRef = ConstantHelpers::materializeStaticPayloadConstant(sema, nextTypeRef, nextBytes);
            if (nextCstRef.isInvalid())
                return Result::Continue;

            outCstRef = nextCstRef;
            return Result::Continue;
        }

        return extractAtIndexBytes(sema, cst.getArray(), typeInfo.payloadArrayElemTypeRef(), constIndex, count, nodeArgRef, outCstRef);
    }

    Result extractAtIndexSlice(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        const TypeRef   typeRef  = unwrapAliasTypeRef(sema, cst.typeRef());
        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        SWC_ASSERT(typeInfo.isSlice());
        const std::span<const std::byte> bytes     = cst.getSlice();
        const uint64_t                   elemCount = cst.getSliceCount();
        return extractAtIndexBytes(sema, bytes, typeInfo.payloadTypeRef(), constIndex, elemCount, nodeArgRef, outCstRef);
    }

    Result extractAtIndexBlockPointer(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        TaskContext&    ctx      = sema.ctx();
        const TypeRef   typeRef  = unwrapAliasTypeRef(sema, cst.typeRef());
        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        const uint64_t  ptrValue = cst.getBlockPointer();
        SWC_ASSERT(ptrValue);

        if (typeInfo.isCString())
        {
            const auto*     ptr   = reinterpret_cast<const char*>(ptrValue);
            const uint64_t  count = std::strlen(ptr);
            const std::span bytes{reinterpret_cast<const std::byte*>(ptr), count};
            return extractAtIndexBytes(sema, bytes, sema.typeMgr().typeU8(), constIndex, count, nodeArgRef, outCstRef);
        }

        SWC_ASSERT(typeInfo.isBlockPointer());
        const TypeRef  elemType = typeInfo.payloadTypeRef();
        const uint64_t elemSize = sema.typeMgr().get(elemType).sizeOf(ctx);
        SWC_ASSERT(elemSize);

        const uint64_t  byteOffset = static_cast<uint64_t>(constIndex) * elemSize;
        const auto*     elemPtr    = reinterpret_cast<const std::byte*>(ptrValue + byteOffset);
        const std::span elemBytes{elemPtr, elemSize};
        return extractAtIndexBytes(sema, elemBytes, elemType, 0, 1, nodeArgRef, outCstRef);
    }
}

Result ConstantExtract::atIndexRef(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
{
    SWC_ASSERT(cst.isValid());
    outCstRef = ConstantRef::invalid();

    // A `null` constant of an indexable type (e.g. `cast(const [..] s32) null`) carries no
    // element payload to extract. The TYPE is indexable, so this is not a "type does not support
    // indexing" error — leave the index un-folded (outCstRef invalid) so it lowers to a runtime
    // index with the normal bound check. This matters once such an expression becomes constant
    // (e.g. a function inlined with a constant argument that folds a ternary to its `null` branch);
    // without it, const-folding a null-slice index wrongly reports the slice type as non-indexable.
    if (cst.isNull())
        return Result::Continue;

    if (cst.isAggregateArray())
        return extractAtIndexAggregateArray(sema, cst, constIndex, nodeArgRef, outCstRef);
    if (cst.isArray())
        return extractAtIndexArray(sema, cst, constIndex, nodeArgRef, outCstRef);
    if (cst.isString())
        return extractAtIndexString(sema, cst, constIndex, nodeArgRef, outCstRef);
    if (cst.isSlice())
        return extractAtIndexSlice(sema, cst, constIndex, nodeArgRef, outCstRef);
    if (cst.isBlockPointer())
        return extractAtIndexBlockPointer(sema, cst, constIndex, nodeArgRef, outCstRef);

    return SemaError::raiseTypeNotIndexable(sema, sema.curNodeRef(), cst.typeRef());
}

Result ConstantExtract::atIndex(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef)
{
    ConstantRef outCstRef = ConstantRef::invalid();
    SWC_RESULT(atIndexRef(sema, cst, constIndex, nodeArgRef, outCstRef));
    if (outCstRef.isValid())
        sema.setConstant(sema.curNodeRef(), outCstRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
