#include "pch.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void   lowerConstantToBytes(Sema& sema, ByteSpanRW dstBytes, TypeRef dstTypeRef, ConstantRef cstRef);
    Result materializeNativeStaticPayloadInPlace(Sema& sema, DataSegment& segment, TypeRef typeRef, uint32_t baseOffset, ByteSpanRW dstBytes, ByteSpan srcBytes);
    Result resolveSegmentOffset(uint32_t& outOffset, Sema& sema, const DataSegment& segment, const void* sourcePtr);

    Result materializeNativeStaticScalar(ByteSpanRW dstBytes, ByteSpan srcBytes)
    {
        if (!dstBytes.empty())
            std::memcpy(dstBytes.data(), srcBytes.data(), dstBytes.size());
        return Result::Continue;
    }

    Result materializeNativeStaticString(DataSegment& segment, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        if (srcBytes.size() != sizeof(Runtime::String))
            return Result::Error;

        auto* const       dstString = reinterpret_cast<Runtime::String*>(dstBytes.data());
        const auto* const srcString = reinterpret_cast<const Runtime::String*>(srcBytes.data());
        if (!srcString->ptr)
        {
            if (srcString->length != 0)
                return Result::Error;

            dstString->ptr    = nullptr;
            dstString->length = 0;
            return Result::Continue;
        }

        dstString->length = segment.addString(baseOffset, offsetof(Runtime::String, ptr), std::string_view(srcString->ptr, srcString->length));
        return Result::Continue;
    }

    Result materializeNativeStaticAny(Sema& sema, DataSegment& segment, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        TaskContext& ctx = sema.ctx();
        if (srcBytes.size() != sizeof(Runtime::Any))
            return Result::Error;

        auto* const       dstAny = reinterpret_cast<Runtime::Any*>(dstBytes.data());
        const auto* const srcAny = reinterpret_cast<const Runtime::Any*>(srcBytes.data());
        if (!srcAny->type)
        {
            if (srcAny->value != nullptr)
                return Result::Error;

            dstAny->value = nullptr;
            dstAny->type  = nullptr;
            return Result::Continue;
        }

        uint32_t typeOffset = INVALID_REF;
        SWC_RESULT(resolveSegmentOffset(typeOffset, sema, segment, srcAny->type));
        dstAny->type = typeOffset == INVALID_REF ? nullptr : segment.ptr<Runtime::TypeInfo>(typeOffset);
        if (typeOffset != INVALID_REF)
            segment.addRelocation(baseOffset + offsetof(Runtime::Any, type), typeOffset);
        if (!srcAny->value)
            return Result::Continue;

        const TypeRef valueTypeRef = sema.typeGen().getBackTypeRef(srcAny->type);
        if (valueTypeRef.isInvalid())
            return Result::Error;

        const uint64_t valueSize = sema.typeMgr().get(valueTypeRef).sizeOf(ctx);
        SWC_ASSERT(valueSize <= std::numeric_limits<uint32_t>::max());

        uint32_t valueOffset = INVALID_REF;
        SWC_RESULT(ConstantLower::materializeNativeStaticPayload(valueOffset,
                                                                        sema,
                                                                        segment,
                                                                        valueTypeRef,
                                                                        ByteSpan{static_cast<const std::byte*>(srcAny->value), static_cast<size_t>(valueSize)}));
        dstAny->value = segment.ptr<std::byte>(valueOffset);
        segment.addRelocation(baseOffset + offsetof(Runtime::Any, value), valueOffset);
        return Result::Continue;
    }

    Result materializeNativeStaticSlice(Sema& sema, DataSegment& segment, const TypeInfo& typeInfo, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        TaskContext& ctx = sema.ctx();
        if (srcBytes.size() != sizeof(Runtime::Slice<std::byte>))
            return Result::Error;

        auto* const       dstSlice       = reinterpret_cast<Runtime::Slice<std::byte>*>(dstBytes.data());
        const auto* const srcSlice       = reinterpret_cast<const Runtime::Slice<std::byte>*>(srcBytes.data());
        const TypeRef     elementTypeRef = typeInfo.payloadTypeRef();
        const TypeInfo&   elementType    = sema.typeMgr().get(elementTypeRef);
        const uint64_t    elementSize    = elementType.sizeOf(ctx);
        if (!srcSlice->ptr)
        {
            if (srcSlice->count != 0)
                return Result::Error;

            dstSlice->ptr   = nullptr;
            dstSlice->count = 0;
            return Result::Continue;
        }

        if (!elementSize)
            return Result::Error;

        const uint64_t byteCount = srcSlice->count * elementSize;
        SWC_ASSERT(byteCount <= std::numeric_limits<uint32_t>::max());
        const auto [dataOffset, dataStorage] = segment.reserveBytes(static_cast<uint32_t>(byteCount), elementType.alignOf(ctx), true);
        for (uint64_t idx = 0; idx < srcSlice->count; ++idx)
        {
            const uint64_t elementOffset = idx * elementSize;
            SWC_RESULT(materializeNativeStaticPayloadInPlace(sema,
                                                                    segment,
                                                                    elementTypeRef,
                                                                    dataOffset + static_cast<uint32_t>(elementOffset),
                                                                    ByteSpanRW{dataStorage + elementOffset, static_cast<size_t>(elementSize)},
                                                                    ByteSpan{srcSlice->ptr + elementOffset, static_cast<size_t>(elementSize)}));
        }

        dstSlice->ptr   = dataStorage;
        dstSlice->count = srcSlice->count;
        segment.addRelocation(baseOffset + offsetof(Runtime::Slice<std::byte>, ptr), dataOffset);
        return Result::Continue;
    }

    Result materializeNativeStaticArray(Sema& sema, DataSegment& segment, const TypeInfo& typeInfo, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        TaskContext&    ctx            = sema.ctx();
        const TypeRef   elementTypeRef = typeInfo.payloadArrayElemTypeRef();
        const TypeInfo& elementType    = sema.typeMgr().get(elementTypeRef);
        const uint64_t  elementSize    = elementType.sizeOf(ctx);
        if (!elementSize)
            return Result::Error;

        uint64_t totalCount = 1;
        for (const uint64_t dim : typeInfo.payloadArrayDims())
            totalCount *= dim;

        for (uint64_t idx = 0; idx < totalCount; ++idx)
        {
            const uint64_t elementOffset = idx * elementSize;
            SWC_RESULT(materializeNativeStaticPayloadInPlace(sema,
                                                                    segment,
                                                                    elementTypeRef,
                                                                    baseOffset + static_cast<uint32_t>(elementOffset),
                                                                    ByteSpanRW{dstBytes.data() + elementOffset, static_cast<size_t>(elementSize)},
                                                                    ByteSpan{srcBytes.data() + elementOffset, static_cast<size_t>(elementSize)}));
        }

        return Result::Continue;
    }

    Result materializeNativeStaticStruct(Sema& sema, DataSegment& segment, const TypeInfo& typeInfo, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        TaskContext& ctx = sema.ctx();
        for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
        {
            if (!field)
                continue;

            const TypeRef   fieldTypeRef = field->typeRef();
            const TypeInfo& fieldType    = sema.typeMgr().get(fieldTypeRef);
            const uint64_t  fieldSize    = fieldType.sizeOf(ctx);
            const uint64_t  fieldOffset  = field->offset();
            if (fieldOffset + fieldSize > srcBytes.size())
                return Result::Error;

            SWC_RESULT(materializeNativeStaticPayloadInPlace(sema,
                                                                    segment,
                                                                    fieldTypeRef,
                                                                    baseOffset + static_cast<uint32_t>(fieldOffset),
                                                                    ByteSpanRW{dstBytes.data() + fieldOffset, static_cast<size_t>(fieldSize)},
                                                                    ByteSpan{srcBytes.data() + fieldOffset, static_cast<size_t>(fieldSize)}));
        }

        return Result::Continue;
    }

    Result materializeNativeStaticInterface(Sema& sema, DataSegment& segment, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        if (srcBytes.size() != sizeof(Runtime::Interface))
            return Result::Error;

        const auto dstInterface = reinterpret_cast<Runtime::Interface*>(dstBytes.data());
        const auto srcInterface = reinterpret_cast<const Runtime::Interface*>(srcBytes.data());
        uint32_t   objOffset    = INVALID_REF;
        SWC_RESULT(resolveSegmentOffset(objOffset, sema, segment, srcInterface->obj));
        dstInterface->obj = objOffset == INVALID_REF ? nullptr : segment.ptr<std::byte>(objOffset);
        if (objOffset != INVALID_REF)
            segment.addRelocation(baseOffset + offsetof(Runtime::Interface, obj), objOffset);

        uint32_t itableOffset = INVALID_REF;
        SWC_RESULT(resolveSegmentOffset(itableOffset, sema, segment, srcInterface->itable));
        dstInterface->itable = itableOffset == INVALID_REF ? nullptr : segment.ptr<void*>(itableOffset);
        if (itableOffset != INVALID_REF)
            segment.addRelocation(baseOffset + offsetof(Runtime::Interface, itable), itableOffset);
        return Result::Continue;
    }

    Result materializeNativeStaticPointer(Sema& sema, DataSegment& segment, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        if (srcBytes.size() != sizeof(uint64_t))
            return Result::Error;

        auto&      dstPtr    = *reinterpret_cast<uint64_t*>(dstBytes.data());
        const auto srcPtr    = reinterpret_cast<const void*>(*reinterpret_cast<const uint64_t*>(srcBytes.data()));
        uint32_t   ptrOffset = INVALID_REF;
        SWC_RESULT(resolveSegmentOffset(ptrOffset, sema, segment, srcPtr));
        dstPtr = ptrOffset == INVALID_REF ? 0 : reinterpret_cast<uint64_t>(segment.ptr<std::byte>(ptrOffset));
        if (ptrOffset != INVALID_REF)
            segment.addRelocation(baseOffset, ptrOffset);
        return Result::Continue;
    }

    Result resolveSegmentOffset(uint32_t& outOffset, Sema& sema, const DataSegment& segment, const void* sourcePtr)
    {
        outOffset = INVALID_REF;
        if (!sourcePtr)
            return Result::Continue;

        uint32_t  shardIndex = 0;
        const Ref targetRef  = sema.cstMgr().findDataSegmentRef(shardIndex, sourcePtr);
        if (targetRef == INVALID_REF)
            return Result::Error;

        if (&segment != &sema.cstMgr().shardDataSegment(shardIndex))
            return Result::Error;

        outOffset = targetRef;
        return Result::Continue;
    }

    void lowerAggregateArrayToBytesInternal(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values)
    {
        TaskContext&    ctx         = sema.ctx();
        const auto      elemTypeRef = dstType.payloadArrayElemTypeRef();
        const TypeInfo& elemType    = sema.typeMgr().get(elemTypeRef);
        const uint64_t  elemSize    = elemType.sizeOf(ctx);
        uint64_t        totalCount  = 1;
        const auto&     dims        = dstType.payloadArrayDims();

        for (const auto dim : dims)
            totalCount *= dim;

        SWC_ASSERT(!elemSize || elemSize * totalCount <= dstBytes.size());

        const uint64_t maxCount = std::min<uint64_t>(values.size(), totalCount);
        for (uint64_t i = 0; i < maxCount; ++i)
        {
            lowerConstantToBytes(sema, ByteSpanRW{dstBytes.data() + (i * elemSize), elemSize}, elemTypeRef, values[i]);
        }
    }

    void lowerConstantToBytes(Sema& sema, ByteSpanRW dstBytes, TypeRef dstTypeRef, ConstantRef cstRef)
    {
        const ConstantValue& cst = sema.cstMgr().get(cstRef);
        if (cst.isUndefined())
            return;

        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
        if (dstType.isAlias())
        {
            const TypeRef unwrappedTypeRef = dstType.unwrap(sema.ctx(), dstTypeRef, TypeExpandE::Alias);
            SWC_ASSERT(unwrappedTypeRef.isValid());
            lowerConstantToBytes(sema, dstBytes, unwrappedTypeRef, cstRef);
            return;
        }

        if (dstType.isEnum())
        {
            const TypeRef underlyingTypeRef = dstType.payloadSymEnum().underlyingTypeRef();
            ConstantRef   enumValueRef      = cstRef;
            if (cst.isEnumValue())
                enumValueRef = cst.getEnumValue();
            lowerConstantToBytes(sema, dstBytes, underlyingTypeRef, enumValueRef);
            return;
        }

        if (dstType.isStruct())
        {
            if (cst.isStruct())
            {
                const auto bytes = cst.getStruct();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(dstBytes.data(), bytes.data(), dstBytes.size());
                return;
            }

            if (cst.isAggregateStruct())
            {
                ConstantLower::lowerAggregateStructToBytes(sema, dstBytes, dstType, cst.getAggregateStruct());
                return;
            }

            SWC_ASSERT(cst.isStruct() || cst.isAggregateStruct());
            return;
        }

        if (dstType.isArray())
        {
            if (cst.isArray())
            {
                const auto bytes = cst.getArray();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(dstBytes.data(), bytes.data(), dstBytes.size());
                return;
            }

            SWC_ASSERT(cst.isAggregateArray());
            lowerAggregateArrayToBytesInternal(sema, dstBytes, dstType, cst.getAggregateArray());
            return;
        }

        if (dstType.isBool())
        {
            SWC_ASSERT(cst.isBool() && dstBytes.size() == 1);
            const uint8_t v = cst.getBool() ? 1 : 0;
            std::memcpy(dstBytes.data(), &v, sizeof(v));
            return;
        }

        if (dstType.isChar())
        {
            SWC_ASSERT(cst.isChar() && dstBytes.size() == sizeof(char32_t));
            const char32_t v = cst.getChar();
            std::memcpy(dstBytes.data(), &v, sizeof(v));
            return;
        }

        if (dstType.isRune())
        {
            SWC_ASSERT(cst.isRune() && dstBytes.size() == sizeof(char32_t));
            const char32_t v = cst.getRune();
            std::memcpy(dstBytes.data(), &v, sizeof(v));
            return;
        }

        if (dstType.isInt())
        {
            SWC_ASSERT(cst.isInt());
            const uint64_t v = cst.getInt().as64();
            SWC_ASSERT(dstBytes.size() <= sizeof(v));
            std::memcpy(dstBytes.data(), &v, dstBytes.size());
            return;
        }

        if (dstType.isFloat())
        {
            SWC_ASSERT(cst.isFloat());
            if (dstType.payloadFloatBits() == 32)
            {
                const float v = cst.getFloat().asFloat();
                SWC_ASSERT(dstBytes.size() == sizeof(v));
                std::memcpy(dstBytes.data(), &v, sizeof(v));
                return;
            }

            if (dstType.payloadFloatBits() == 64)
            {
                const double v = cst.getFloat().asDouble();
                SWC_ASSERT(dstBytes.size() == sizeof(v));
                std::memcpy(dstBytes.data(), &v, sizeof(v));
                return;
            }

            SWC_ASSERT(dstType.payloadFloatBits() == 32 || dstType.payloadFloatBits() == 64);
            return;
        }

        if (dstType.isString())
        {
            SWC_ASSERT((cst.isNull() || cst.isString() || cst.isStruct(dstTypeRef)) && dstBytes.size() == sizeof(Runtime::String));
            if (cst.isStruct(dstTypeRef))
            {
                const auto bytes = cst.getStruct();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(dstBytes.data(), bytes.data(), dstBytes.size());
                return;
            }

            Runtime::String rt = {};
            if (cst.isString())
            {
                const std::string_view str = cst.getString();
                rt                         = {.ptr = str.data(), .length = str.size()};
            }
            std::memcpy(dstBytes.data(), &rt, sizeof(rt));
            return;
        }

        if (dstType.isSlice())
        {
            SWC_ASSERT((cst.isNull() || cst.isSlice() || cst.isStruct(dstTypeRef)) && dstBytes.size() == sizeof(Runtime::Slice<uint8_t>));
            if (cst.isStruct(dstTypeRef))
            {
                const auto bytes = cst.getStruct();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(dstBytes.data(), bytes.data(), dstBytes.size());
                return;
            }

            Runtime::Slice<uint8_t> rt = {};
            if (cst.isSlice())
            {
                const ByteSpan  bytes       = cst.getSlice();
                const TypeInfo& elementType = sema.typeMgr().get(dstType.payloadTypeRef());
                const uint64_t  elementSize = elementType.sizeOf(sema.ctx());
                rt.ptr                      = const_cast<uint8_t*>(reinterpret_cast<const uint8_t*>(bytes.data()));
                rt.count                    = elementSize ? bytes.size() / elementSize : 0;
            }
            std::memcpy(dstBytes.data(), &rt, sizeof(rt));
            return;
        }

        if (dstType.isInterface())
        {
            SWC_ASSERT(cst.isNull() && dstBytes.size() == sizeof(Runtime::Interface));
            constexpr Runtime::Interface rt = {};
            std::memcpy(dstBytes.data(), &rt, sizeof(rt));
            return;
        }

        if (dstType.isAny())
        {
            SWC_ASSERT(dstBytes.size() == sizeof(Runtime::Any));
            if (cst.isNull())
            {
                if (!dstBytes.empty())
                    std::memset(dstBytes.data(), 0, dstBytes.size());
                return;
            }

            if (cst.isStruct())
            {
                const auto bytes = cst.getStruct();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(dstBytes.data(), bytes.data(), dstBytes.size());
                return;
            }

            Runtime::Any anyValue{};

            const TypeRef valueTypeRef = cst.typeRef();
            SWC_ASSERT(valueTypeRef.isValid());
            SWC_ASSERT(valueTypeRef != dstTypeRef);

            ConstantRef  typeInfoCstRef = ConstantRef::invalid();
            const Result typeInfoRes    = sema.cstMgr().makeTypeInfo(sema, typeInfoCstRef, valueTypeRef, AstNodeRef::invalid());
            SWC_ASSERT(typeInfoRes == Result::Continue);
            SWC_ASSERT(typeInfoCstRef.isValid());
            const ConstantValue& typeInfoCst = sema.cstMgr().get(typeInfoCstRef);
            SWC_ASSERT(typeInfoCst.isValuePointer());
            anyValue.type = reinterpret_cast<const Runtime::TypeInfo*>(typeInfoCst.getValuePointer());

            const uint64_t valueSize = sema.typeMgr().get(valueTypeRef).sizeOf(sema.ctx());
            if (valueSize)
            {
                std::vector valueBytes(valueSize, std::byte{0});
                lowerConstantToBytes(sema, valueBytes, valueTypeRef, cstRef);

                const std::string_view rawValueView(reinterpret_cast<const char*>(valueBytes.data()), valueBytes.size());
                const std::string_view rawValueData = sema.cstMgr().addPayloadBuffer(rawValueView);
                anyValue.value                      = const_cast<char*>(rawValueData.data());
            }

            std::memcpy(dstBytes.data(), &anyValue, sizeof(anyValue));
            return;
        }

        if (dstType.isAnyPointer() || dstType.isReference() || dstType.isTypeInfo() || dstType.isCString() || dstType.isFunction())
        {
            SWC_ASSERT(dstBytes.size() == sizeof(uint64_t));
            uint64_t ptr = 0;
            if (cst.isNull())
                ptr = 0;
            else if (cst.isValuePointer())
                ptr = cst.getValuePointer();
            else if (cst.isBlockPointer())
                ptr = cst.getBlockPointer();
            SWC_ASSERT(cst.isNull() || cst.isValuePointer() || cst.isBlockPointer());
            std::memcpy(dstBytes.data(), &ptr, sizeof(ptr));
            return;
        }

        SWC_ASSERT(dstType.isEnum() || dstType.isStruct() || dstType.isArray() || dstType.isBool() || dstType.isChar() ||
                   dstType.isRune() || dstType.isInt() || dstType.isFloat() || dstType.isString() || dstType.isSlice() ||
                   dstType.isAny() || dstType.isAnyPointer() || dstType.isReference() || dstType.isTypeInfo() || dstType.isCString() || dstType.isFunction());
    }

    Result materializeNativeStaticPayloadInPlace(Sema& sema, DataSegment& segment, TypeRef typeRef, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        if (typeRef.isInvalid())
            return Result::Error;

        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (typeInfo.isAlias())
        {
            const TypeRef unwrappedTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
            return unwrappedTypeRef.isValid() ? materializeNativeStaticPayloadInPlace(sema, segment, unwrappedTypeRef, baseOffset, dstBytes, srcBytes) : Result::Error;
        }

        const uint64_t sizeOf = typeInfo.sizeOf(ctx);
        if (sizeOf != dstBytes.size() || sizeOf != srcBytes.size())
            return Result::Error;

        switch (typeInfo.kind())
        {
            case TypeInfoKind::Enum:
                return materializeNativeStaticPayloadInPlace(sema, segment, typeInfo.payloadSymEnum().underlyingTypeRef(), baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::Bool:
            case TypeInfoKind::Char:
            case TypeInfoKind::Rune:
            case TypeInfoKind::Int:
            case TypeInfoKind::Float:
                return materializeNativeStaticScalar(dstBytes, srcBytes);

            case TypeInfoKind::String:
                return materializeNativeStaticString(segment, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::Any:
                return materializeNativeStaticAny(sema, segment, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::Slice:
                return materializeNativeStaticSlice(sema, segment, typeInfo, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::Array:
                return materializeNativeStaticArray(sema, segment, typeInfo, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::Struct:
                return materializeNativeStaticStruct(sema, segment, typeInfo, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::Interface:
                return materializeNativeStaticInterface(sema, segment, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::ValuePointer:
            case TypeInfoKind::BlockPointer:
            case TypeInfoKind::Reference:
            case TypeInfoKind::MoveReference:
            case TypeInfoKind::CString:
            case TypeInfoKind::Function:
            case TypeInfoKind::TypeInfo:
                return materializeNativeStaticPointer(sema, segment, baseOffset, dstBytes, srcBytes);

            default:
                break;
        }

        return Result::Error;
    }
}

void ConstantLower::lowerToBytes(Sema& sema, ByteSpanRW dstBytes, ConstantRef cstRef, TypeRef dstTypeRef)
{
    lowerConstantToBytes(sema, dstBytes, dstTypeRef, cstRef);
}

void ConstantLower::lowerAggregateArrayToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values)
{
    lowerAggregateArrayToBytesInternal(sema, dstBytes, dstType, values);
}

void ConstantLower::lowerAggregateStructToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values)
{
    const auto& dstFields = dstType.payloadSymStruct().fields();
    size_t      valueIdx  = 0;

    for (const SymbolVariable* field : dstFields)
    {
        if (!field)
            continue;

        const TypeRef   fieldTypeRef = field->typeRef();
        const TypeInfo& fieldType    = sema.typeMgr().get(fieldTypeRef);
        const uint64_t  fieldSize    = fieldType.sizeOf(sema.ctx());
        const uint64_t  fieldOffset  = field->offset();
        SWC_ASSERT(fieldOffset + fieldSize <= dstBytes.size());

        ConstantRef valueRef = ConstantRef::invalid();
        if (valueIdx < values.size())
        {
            valueRef = values[valueIdx];
            ++valueIdx;
        }
        else
        {
            valueRef = field->defaultValueRef();
        }

        if (valueRef.isValid())
            lowerConstantToBytes(sema, ByteSpanRW{dstBytes.data() + fieldOffset, fieldSize}, fieldTypeRef, valueRef);
        else if (fieldSize)
            std::memset(dstBytes.data() + fieldOffset, 0, fieldSize);
    }
}

Result ConstantLower::materializeNativeStaticPayload(uint32_t& outOffset, Sema& sema, DataSegment& segment, TypeRef typeRef, const ByteSpan srcBytes)
{
    outOffset = INVALID_REF;
    if (typeRef.isInvalid())
        return Result::Error;

    const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
    const uint64_t  sizeOf   = typeInfo.sizeOf(sema.ctx());
    const uint32_t  alignOf  = typeInfo.alignOf(sema.ctx());
    SWC_ASSERT(sizeOf <= std::numeric_limits<uint32_t>::max());
    SWC_ASSERT(sizeOf == srcBytes.size());

    const auto [offset, storage] = segment.reserveBytes(static_cast<uint32_t>(sizeOf), alignOf, true);
    outOffset                    = offset;
    return materializeNativeStaticPayloadInPlace(sema, segment, typeRef, offset, ByteSpanRW{storage, static_cast<size_t>(sizeOf)}, srcBytes);
}

SWC_END_NAMESPACE();
