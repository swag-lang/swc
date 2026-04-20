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

SWC_BEGIN_NAMESPACE();

namespace
{
    Result makeScalarFieldConstantFromBytes(Sema& sema, TypeRef fieldTypeRef, ByteSpan bytes, ConstantRef& outCstRef)
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

    Result getStructBytesFromConstant(Sema& sema, ByteSpan& bytes, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeMemberRef)
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
            if (cstType.isAnyPointer())
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
            bytes = ByteSpan{reinterpret_cast<const std::byte*>(static_cast<uintptr_t>(ptr)), pointedType.sizeOf(sema.ctx())};
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

        const auto& fields = sym.fields();
        const auto  it     = std::ranges::find(fields, &symVar);
        if (it == fields.end())
        {
            failStructMemberType(sema, symVar, nodeMemberRef);
            return;
        }

        const auto fieldIndex = static_cast<size_t>(std::distance(fields.begin(), it));
        if (std::cmp_greater_equal(fieldIndex, values.size()))
        {
            failStructMemberType(sema, symVar, nodeMemberRef);
            return;
        }

        sema.setConstant(nodeRef, values[fieldIndex]);
    }

    Result makeFieldConstantFromBytes(Sema& sema, TypeRef fieldTypeRef, const TypeInfo& typeField, ByteSpan bytes, ConstantRef& outCstRef, const SymbolVariable& symVar, AstNodeRef nodeMemberRef)
    {
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

    ByteSpan bytes;
    SWC_RESULT(getStructBytesFromConstant(sema, bytes, cst, symVar, nodeMemberRef));

    const TypeInfo& typeVar   = symVar.typeInfo(ctx);
    const TypeInfo* typeField = &typeVar;
    SWC_ASSERT(symVar.offset() + typeField->sizeOf(ctx) <= bytes.size());
    const auto fieldBytes = ByteSpan{bytes.data() + symVar.offset(), typeField->sizeOf(ctx)};

    ConstantRef cstRef = ConstantRef::invalid();
    SWC_RESULT(makeFieldConstantFromBytes(sema, symVar.typeRef(), *typeField, fieldBytes, cstRef, symVar, nodeMemberRef));

    sema.setConstant(nodeRef, cstRef);
    return Result::Continue;
}

namespace
{
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

    Result extractAtIndexBytes(Sema& sema, ByteSpan bytes, TypeRef elemTypeRef, int64_t constIndex, uint64_t count, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        outCstRef                = ConstantRef::invalid();
        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& elemType = sema.typeMgr().get(elemTypeRef);
        SWC_RESULT(sema.waitSemaCompleted(&elemType, nodeArgRef));
        const uint64_t elemSize = elemType.sizeOf(ctx);
        SWC_ASSERT(elemSize);

        if (std::cmp_greater_equal(constIndex, count))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, count);

        const auto        elemBytes  = ByteSpan{bytes.data() + (constIndex * elemSize), elemSize};
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
        const TypeInfo& typeInfo = sema.typeMgr().get(cst.typeRef());
        const auto&     dims     = typeInfo.payloadArrayDims();
        const uint64_t  count    = dims.empty() ? 0 : dims[0];
        if (std::cmp_greater_equal(constIndex, count))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, count);

        if (dims.size() > 1)
        {
            SmallVector<uint64_t> remainingDims;
            for (size_t i = 1; i < dims.size(); ++i)
                remainingDims.push_back(dims[i]);

            const TypeRef     nextTypeRef = sema.typeMgr().addType(TypeInfo::makeArray(remainingDims.span(), typeInfo.payloadArrayElemTypeRef(), typeInfo.flags()));
            const uint64_t    nextSize    = sema.typeMgr().get(nextTypeRef).sizeOf(ctx);
            const ByteSpan    nextBytes   = {cst.getArray().data() + (constIndex * nextSize), nextSize};
            const ConstantRef nextCstRef  = ConstantHelpers::materializeStaticPayloadConstant(sema, nextTypeRef, nextBytes);
            if (nextCstRef.isInvalid())
                return Result::Continue;

            outCstRef = nextCstRef;
            return Result::Continue;
        }

        return extractAtIndexBytes(sema, cst.getArray(), typeInfo.payloadArrayElemTypeRef(), constIndex, count, nodeArgRef, outCstRef);
    }

    Result extractAtIndexSlice(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        const TypeInfo& typeInfo  = sema.typeMgr().get(cst.typeRef());
        const ByteSpan  bytes     = cst.getSlice();
        const uint64_t  elemCount = cst.getSliceCount();
        return extractAtIndexBytes(sema, bytes, typeInfo.payloadTypeRef(), constIndex, elemCount, nodeArgRef, outCstRef);
    }

    Result extractAtIndexBlockPointer(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& typeInfo = sema.typeMgr().get(cst.typeRef());
        const TypeRef   elemType = typeInfo.payloadTypeRef();
        const uint64_t  elemSize = sema.typeMgr().get(elemType).sizeOf(ctx);
        SWC_ASSERT(elemSize);

        const uint64_t ptrValue = cst.getBlockPointer();
        SWC_ASSERT(ptrValue);

        const uint64_t byteOffset = static_cast<uint64_t>(constIndex) * elemSize;
        const auto*    elemPtr    = reinterpret_cast<const std::byte*>(ptrValue + byteOffset);
        const ByteSpan elemBytes{elemPtr, elemSize};
        return extractAtIndexBytes(sema, elemBytes, elemType, 0, 1, nodeArgRef, outCstRef);
    }
}

Result ConstantExtract::atIndexRef(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
{
    SWC_ASSERT(cst.isValid());
    outCstRef = ConstantRef::invalid();

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
