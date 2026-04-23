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
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result lowerConstantToBytes(Sema& sema, ByteSpanRW dstBytes, TypeRef dstTypeRef, ConstantRef cstRef);
    Result materializeStaticPayloadInPlace(Sema& sema, DataSegment& segment, TypeRef typeRef, const struct StaticPayload& payload);

    struct StaticPayload
    {
        uint32_t   baseOffset = 0;
        ByteSpanRW dstBytes;
        ByteSpan   srcBytes;
    };

    size_t narrowByteCount(const uint64_t value)
    {
        SWC_ASSERT(value <= std::numeric_limits<size_t>::max());
        return value;
    }

    uint32_t narrowByteOffset(const uint64_t value)
    {
        SWC_ASSERT(value <= std::numeric_limits<uint32_t>::max());
        return static_cast<uint32_t>(value);
    }

    uint32_t addByteOffset(const uint32_t baseOffset, const uint64_t relOffset)
    {
        const uint32_t offset = narrowByteOffset(relOffset);
        SWC_ASSERT(baseOffset <= std::numeric_limits<uint32_t>::max() - offset);
        return baseOffset + offset;
    }

    ByteSpanRW rawBytes(void* data, const uint64_t size)
    {
        return {static_cast<std::byte*>(data), narrowByteCount(size)};
    }

    ByteSpan rawBytes(const void* data, const uint64_t size)
    {
        return {static_cast<const std::byte*>(data), narrowByteCount(size)};
    }

    ByteSpanRW subBytes(const ByteSpanRW bytes, const uint64_t offset, const uint64_t size)
    {
        return bytes.subspan(narrowByteCount(offset), narrowByteCount(size));
    }

    ByteSpan subBytes(const ByteSpan bytes, const uint64_t offset, const uint64_t size)
    {
        return bytes.subspan(narrowByteCount(offset), narrowByteCount(size));
    }

    template<typename T>
    T& writable(ByteSpanRW bytes)
    {
        SWC_ASSERT(bytes.size() == sizeof(T));
        return *reinterpret_cast<T*>(bytes.data());
    }

    template<typename T>
    const T& readable(const ByteSpan bytes)
    {
        SWC_ASSERT(bytes.size() == sizeof(T));
        return *reinterpret_cast<const T*>(bytes.data());
    }

    uint64_t rawAddress(const void* ptr)
    {
        return reinterpret_cast<uint64_t>(ptr);
    }

    template<typename T>
    T* pointerFromRawAddress(const uint64_t value)
    {
        return reinterpret_cast<T*>(value);
    }

    void copyBytes(ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        SWC_ASSERT(dstBytes.size() == srcBytes.size());
        if (!dstBytes.empty())
            std::memcpy(dstBytes.data(), srcBytes.data(), dstBytes.size());
    }

    void zeroBytes(ByteSpanRW dstBytes)
    {
        if (!dstBytes.empty())
            std::memset(dstBytes.data(), 0, dstBytes.size());
    }

    template<typename T>
    void writeValue(ByteSpanRW dstBytes, const T& value)
    {
        SWC_ASSERT(dstBytes.size() == sizeof(T));
        std::memcpy(dstBytes.data(), &value, sizeof(T));
    }

    template<typename T>
    void assertRuntimePayloadSize(const ByteSpan bytes)
    {
        SWC_ASSERT(bytes.size() == sizeof(T));
    }

    template<typename TString>
    void assignStoredString(DataSegment& segment, TString& dstString, const uint32_t relocationOffset, const Utf8& value)
    {
        const auto [storedValue, targetOffset] = segment.addString(value);
        dstString.ptr                          = storedValue.data();
        dstString.length                       = static_cast<decltype(dstString.length)>(storedValue.size());
        segment.addRelocation(relocationOffset, targetOffset);
    }

    void assertByteRange(const uint64_t offset, const uint64_t size, const uint64_t totalSize)
    {
        SWC_ASSERT(offset <= totalSize && size <= totalSize - offset);
    }

    StaticPayload subPayload(const StaticPayload& payload, const uint64_t offset, const uint64_t size)
    {
        assertByteRange(offset, size, payload.dstBytes.size());
        assertByteRange(offset, size, payload.srcBytes.size());

        return {
            .baseOffset = addByteOffset(payload.baseOffset, offset),
            .dstBytes   = subBytes(payload.dstBytes, offset, size),
            .srcBytes   = subBytes(payload.srcBytes, offset, size),
        };
    }

    Result materializeStaticSubPayload(Sema& sema, DataSegment& segment, const TypeRef typeRef, const StaticPayload& payload, const uint64_t offset, const uint64_t size)
    {
        return materializeStaticPayloadInPlace(sema, segment, typeRef, subPayload(payload, offset, size));
    }

    // Static fixups only make sense for addresses already backed by compiler constant storage.
    Result resolveSegmentOffset(uint32_t& outOffset, Sema& sema, const DataSegment& segment, const void* sourcePtr)
    {
        outOffset = INVALID_REF;
        if (!sourcePtr)
            return Result::Continue;

        DataSegmentRef targetRef;
        SWC_INTERNAL_CHECK(sema.cstMgr().resolveDataSegmentRef(targetRef, sourcePtr));
        SWC_INTERNAL_CHECK(&segment == &sema.cstMgr().shardDataSegment(targetRef.shardIndex));

        outOffset = targetRef.offset;
        return Result::Continue;
    }

    template<typename ST, typename PT>
    Result relocateSegmentPointer(PT*& outPtr, Sema& sema, DataSegment& segment, const uint32_t relocationOffset, const void* sourcePtr)
    {
        uint32_t targetOffset = INVALID_REF;
        SWC_RESULT(resolveSegmentOffset(targetOffset, sema, segment, sourcePtr));

        outPtr = targetOffset == INVALID_REF ? nullptr : static_cast<PT*>(segment.ptr<ST>(targetOffset));
        if (targetOffset != INVALID_REF)
            segment.addRelocation(relocationOffset, targetOffset);
        return Result::Continue;
    }

    Result relocateSegmentAddress(uint64_t& outAddress, Sema& sema, DataSegment& segment, const uint32_t relocationOffset, const void* sourcePtr)
    {
        uint32_t targetOffset = INVALID_REF;
        SWC_RESULT(resolveSegmentOffset(targetOffset, sema, segment, sourcePtr));

        outAddress = targetOffset == INVALID_REF ? 0 : rawAddress(segment.ptr<std::byte>(targetOffset));
        if (targetOffset != INVALID_REF)
            segment.addRelocation(relocationOffset, targetOffset);
        return Result::Continue;
    }

    // Lowering first builds raw runtime payloads in compiler-owned storage. Static materialization
    // then copies that payload into a segment and rewrites embedded pointers as relocations.
    Result lowerConstantToPayloadBuffer(const char*& outData, Sema& sema, ConstantRef cstRef, const TypeRef valueTypeRef)
    {
        outData = nullptr;

        const uint64_t valueSize = sema.typeMgr().get(valueTypeRef).sizeOf(sema.ctx());
        if (!valueSize)
            return Result::Continue;

        std::vector valueBytes(valueSize, std::byte{0});
        SWC_RESULT(lowerConstantToBytes(sema, asByteSpan(valueBytes), valueTypeRef, cstRef));

        const std::string_view rawValueData = sema.cstMgr().addPayloadBuffer(asStringView(asByteSpan(valueBytes)));
        outData                             = rawValueData.data();
        return Result::Continue;
    }

    Result materializeStaticScalar(ByteSpanRW dstBytes, ByteSpan srcBytes)
    {
        copyBytes(dstBytes, srcBytes);
        return Result::Continue;
    }

    Result materializeStaticString(const Sema& sema, DataSegment& segment, const StaticPayload& payload)
    {
        SWC_UNUSED(sema);
        assertRuntimePayloadSize<Runtime::String>(payload.srcBytes);

        auto&       dstString = writable<Runtime::String>(payload.dstBytes);
        const auto& srcString = readable<Runtime::String>(payload.srcBytes);
        if (!srcString.ptr)
        {
            SWC_INTERNAL_CHECK(srcString.length == 0);
            dstString.ptr    = nullptr;
            dstString.length = 0;
            return Result::Continue;
        }

        assignStoredString(segment, dstString, payload.baseOffset + offsetof(Runtime::String, ptr), Utf8{std::string_view(srcString.ptr, srcString.length)});
        return Result::Continue;
    }

    Result materializeStaticAny(Sema& sema, DataSegment& segment, const StaticPayload& payload)
    {
        TaskContext& ctx = sema.ctx();
        assertRuntimePayloadSize<Runtime::Any>(payload.srcBytes);

        auto&       dstAny = writable<Runtime::Any>(payload.dstBytes);
        const auto& srcAny = readable<Runtime::Any>(payload.srcBytes);
        if (!srcAny.type)
        {
            SWC_INTERNAL_CHECK(srcAny.value == nullptr);
            dstAny.value = nullptr;
            dstAny.type  = nullptr;
            return Result::Continue;
        }

        SWC_RESULT(relocateSegmentPointer<Runtime::TypeInfo>(dstAny.type, sema, segment, payload.baseOffset + offsetof(Runtime::Any, type), srcAny.type));
        if (!srcAny.value)
            return Result::Continue;

        const TypeRef valueTypeRef = sema.typeGen().getBackTypeRef(srcAny.type);
        SWC_INTERNAL_CHECK(valueTypeRef.isValid());
        const uint64_t valueSize = sema.typeMgr().get(valueTypeRef).sizeOf(ctx);
        SWC_ASSERT(valueSize <= std::numeric_limits<uint32_t>::max());

        ConstantLower::MaterializedPayloadResult valuePayload;
        // Nested `any` values get their own static storage so relocations can target them.
        SWC_RESULT(ConstantLower::materializeStaticPayload(valuePayload,
                                                           sema,
                                                           segment,
                                                           valueTypeRef,
                                                           rawBytes(srcAny.value, valueSize)));
        dstAny.value = valuePayload.bytes.data();
        segment.addRelocation(payload.baseOffset + offsetof(Runtime::Any, value), valuePayload.offset);
        return Result::Continue;
    }

    Result materializeStaticSlice(Sema& sema, DataSegment& segment, const TypeInfo& typeInfo, const StaticPayload& payload)
    {
        TaskContext& ctx = sema.ctx();
        assertRuntimePayloadSize<Runtime::Slice<std::byte>>(payload.srcBytes);

        auto&           dstSlice       = writable<Runtime::Slice<std::byte>>(payload.dstBytes);
        const auto&     srcSlice       = readable<Runtime::Slice<std::byte>>(payload.srcBytes);
        const TypeRef   elementTypeRef = typeInfo.payloadTypeRef();
        const TypeInfo& elementType    = sema.typeMgr().get(elementTypeRef);
        const uint64_t  elementSize    = elementType.sizeOf(ctx);
        if (srcSlice.count == 0)
        {
            dstSlice.ptr   = nullptr;
            dstSlice.count = 0;
            return Result::Continue;
        }

        if (elementSize == 0)
        {
            // Zero-sized slice elements carry length without backing storage.
            dstSlice.ptr   = nullptr;
            dstSlice.count = srcSlice.count;
            return Result::Continue;
        }

        SWC_INTERNAL_CHECK(srcSlice.ptr != nullptr);

        SWC_ASSERT(srcSlice.count <= std::numeric_limits<uint64_t>::max() / elementSize);
        const uint64_t byteCount = srcSlice.count * elementSize;
        SWC_ASSERT(byteCount <= std::numeric_limits<uint32_t>::max());
        const auto [dataOffset, dataStorage] = segment.reserveBytes(static_cast<uint32_t>(byteCount), elementType.alignOf(ctx), true);
        const StaticPayload slicePayload{
            .baseOffset = dataOffset,
            .dstBytes   = rawBytes(dataStorage, byteCount),
            .srcBytes   = rawBytes(srcSlice.ptr, byteCount),
        };

        // Each element is materialized separately so nested pointers are fixed up recursively.
        for (uint64_t idx = 0; idx < srcSlice.count; ++idx)
        {
            const uint64_t elementOffset = idx * elementSize;
            SWC_RESULT(materializeStaticSubPayload(sema, segment, elementTypeRef, slicePayload, elementOffset, elementSize));
        }

        dstSlice.ptr   = dataStorage;
        dstSlice.count = srcSlice.count;
        segment.addRelocation(payload.baseOffset + offsetof(Runtime::Slice<std::byte>, ptr), dataOffset);
        return Result::Continue;
    }

    Result materializeStaticArray(Sema& sema, DataSegment& segment, const TypeInfo& typeInfo, const StaticPayload& payload)
    {
        TaskContext&    ctx            = sema.ctx();
        const TypeRef   elementTypeRef = typeInfo.payloadArrayElemTypeRef();
        const TypeInfo& elementType    = sema.typeMgr().get(elementTypeRef);
        const uint64_t  elementSize    = elementType.sizeOf(ctx);
        if (!elementSize)
            return Result::Continue;

        uint64_t totalCount = 1;
        for (const uint64_t dim : typeInfo.payloadArrayDims())
            totalCount *= dim;

        for (uint64_t idx = 0; idx < totalCount; ++idx)
        {
            const uint64_t elementOffset = idx * elementSize;
            SWC_RESULT(materializeStaticSubPayload(sema, segment, elementTypeRef, payload, elementOffset, elementSize));
        }

        return Result::Continue;
    }

    Result materializeStaticStruct(Sema& sema, DataSegment& segment, const TypeInfo& typeInfo, const StaticPayload& payload)
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
            assertByteRange(fieldOffset, fieldSize, payload.srcBytes.size());

            SWC_RESULT(materializeStaticSubPayload(sema, segment, fieldTypeRef, payload, fieldOffset, fieldSize));
        }

        return Result::Continue;
    }

    Result materializeStaticInterface(Sema& sema, DataSegment& segment, const StaticPayload& payload)
    {
        assertRuntimePayloadSize<Runtime::Interface>(payload.srcBytes);

        auto&       dstInterface = writable<Runtime::Interface>(payload.dstBytes);
        const auto& srcInterface = readable<Runtime::Interface>(payload.srcBytes);
        SWC_RESULT(relocateSegmentPointer<std::byte>(dstInterface.obj, sema, segment, payload.baseOffset + offsetof(Runtime::Interface, obj), srcInterface.obj));
        SWC_RESULT(relocateSegmentPointer<void*>(dstInterface.itable, sema, segment, payload.baseOffset + offsetof(Runtime::Interface, itable), srcInterface.itable));
        return Result::Continue;
    }

    Result materializeStaticClosure(Sema& sema, DataSegment& segment, const StaticPayload& payload)
    {
        assertRuntimePayloadSize<Runtime::ClosureValue>(payload.srcBytes);

        auto&       dstClosure = writable<Runtime::ClosureValue>(payload.dstBytes);
        const auto& srcClosure = readable<Runtime::ClosureValue>(payload.srcBytes);

        SWC_RESULT(relocateSegmentPointer<std::byte>(dstClosure.invoke, sema, segment, payload.baseOffset + offsetof(Runtime::ClosureValue, invoke), srcClosure.invoke));
        copyBytes(rawBytes(dstClosure.capture, sizeof(dstClosure.capture)), rawBytes(srcClosure.capture, sizeof(srcClosure.capture)));

        // The first bytes of the capture buffer store the captured object pointer when one exists.
        const uint64_t capturedTarget = readable<uint64_t>(rawBytes(srcClosure.capture, sizeof(uint64_t)));
        if (capturedTarget)
        {
            uint64_t relocatedTarget = 0;
            SWC_RESULT(relocateSegmentAddress(relocatedTarget,
                                              sema,
                                              segment,
                                              payload.baseOffset + offsetof(Runtime::ClosureValue, capture),
                                              pointerFromRawAddress<const void>(capturedTarget)));
            writable<uint64_t>(rawBytes(dstClosure.capture, sizeof(uint64_t))) = relocatedTarget;
        }

        return Result::Continue;
    }

    Result materializeStaticPointer(Sema& sema, DataSegment& segment, const StaticPayload& payload)
    {
        assertRuntimePayloadSize<uint64_t>(payload.srcBytes);

        auto&      dstPtr = writable<uint64_t>(payload.dstBytes);
        const auto srcPtr = pointerFromRawAddress<const void>(readable<uint64_t>(payload.srcBytes));
        return relocateSegmentAddress(dstPtr, sema, segment, payload.baseOffset, srcPtr);
    }

    // These helpers keep `lowerConstantToBytes` focused on dispatching by runtime shape.
    Result lowerStringConstantToBytes(ByteSpanRW dstBytes, const TypeRef dstTypeRef, const ConstantValue& cst)
    {
        SWC_ASSERT((cst.isNull() || cst.isString() || cst.isStruct(dstTypeRef)) && dstBytes.size() == sizeof(Runtime::String));
        if (cst.isStruct(dstTypeRef))
        {
            copyBytes(dstBytes, cst.getStruct());
            return Result::Continue;
        }

        Runtime::String runtimeValue = {};
        if (cst.isString())
        {
            const std::string_view str = cst.getString();
            runtimeValue.ptr           = str.data();
            runtimeValue.length        = str.size();
        }

        writeValue(dstBytes, runtimeValue);
        return Result::Continue;
    }

    Result lowerSliceConstantToBytes(const Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const TypeRef dstTypeRef, const ConstantValue& cst)
    {
        SWC_ASSERT((cst.isNull() || cst.isSlice() || cst.isStruct(dstTypeRef)) && dstBytes.size() == sizeof(Runtime::Slice<uint8_t>));
        SWC_UNUSED(sema);
        SWC_UNUSED(dstType);
        if (cst.isStruct(dstTypeRef))
        {
            copyBytes(dstBytes, cst.getStruct());
            return Result::Continue;
        }

        Runtime::Slice<uint8_t> runtimeValue = {};
        if (cst.isSlice())
        {
            const ByteSpan bytes = cst.getSlice();
            runtimeValue.count   = cst.getSliceCount();
            runtimeValue.ptr     = bytes.empty() ? nullptr : reinterpret_cast<uint8_t*>(const_cast<std::byte*>(bytes.data()));
        }

        writeValue(dstBytes, runtimeValue);
        return Result::Continue;
    }

    Result lowerInterfaceConstantToBytes(ByteSpanRW dstBytes, const TypeRef dstTypeRef, const ConstantValue& cst)
    {
        SWC_ASSERT((cst.isNull() || cst.isStruct(dstTypeRef)) && dstBytes.size() == sizeof(Runtime::Interface));
        if (cst.isStruct(dstTypeRef))
        {
            copyBytes(dstBytes, cst.getStruct());
            return Result::Continue;
        }

        constexpr Runtime::Interface runtimeValue = {};
        writeValue(dstBytes, runtimeValue);
        return Result::Continue;
    }

    Result lowerAnyConstantToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeRef dstTypeRef, ConstantRef cstRef, const ConstantValue& cst)
    {
        SWC_ASSERT(dstBytes.size() == sizeof(Runtime::Any));
        if (cst.isNull())
        {
            zeroBytes(dstBytes);
            return Result::Continue;
        }

        if (cst.isStruct())
        {
            copyBytes(dstBytes, cst.getStruct());
            return Result::Continue;
        }

        Runtime::Any anyValue = {};

        const TypeRef valueTypeRef = cst.typeRef();
        SWC_INTERNAL_CHECK(valueTypeRef.isValid());
        SWC_INTERNAL_CHECK(valueTypeRef != dstTypeRef);

        ConstantRef typeInfoCstRef = ConstantRef::invalid();
        SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, typeInfoCstRef, valueTypeRef, sema.ctx().state().nodeRef));
        SWC_INTERNAL_CHECK(typeInfoCstRef.isValid());

        const ConstantValue& typeInfoCst = sema.cstMgr().get(typeInfoCstRef);
        SWC_INTERNAL_CHECK(typeInfoCst.isValuePointer());
        anyValue.type = pointerFromRawAddress<const Runtime::TypeInfo>(typeInfoCst.getValuePointer());

        const char* loweredValueData = nullptr;
        SWC_RESULT(lowerConstantToPayloadBuffer(loweredValueData, sema, cstRef, valueTypeRef));
        anyValue.value = const_cast<char*>(loweredValueData);
        writeValue(dstBytes, anyValue);
        return Result::Continue;
    }

    Result lowerClosureConstantToBytes(ByteSpanRW dstBytes, const ConstantValue& cst)
    {
        SWC_ASSERT(dstBytes.size() == sizeof(Runtime::ClosureValue));
        if (cst.isNull())
        {
            zeroBytes(dstBytes);
            return Result::Continue;
        }

        if (cst.isStruct())
        {
            copyBytes(dstBytes, cst.getStruct());
            return Result::Continue;
        }

        SWC_UNREACHABLE();
    }

    Result lowerPointerLikeConstantToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, ConstantRef cstRef, const ConstantValue& cst)
    {
        SWC_ASSERT(dstBytes.size() == sizeof(uint64_t));

        uint64_t ptr = 0;
        if (cst.isValuePointer())
        {
            ptr = cst.getValuePointer();
        }
        else if (cst.isBlockPointer())
        {
            ptr = cst.getBlockPointer();
        }
        else if (dstType.isReference())
        {
            const TypeRef pointeeTypeRef = dstType.payloadTypeRef();
            if (pointeeTypeRef.isValid())
            {
                const char* loweredValueData = nullptr;
                SWC_RESULT(lowerConstantToPayloadBuffer(loweredValueData, sema, cstRef, pointeeTypeRef));
                ptr = rawAddress(loweredValueData);
            }
        }

        SWC_INTERNAL_CHECK(cst.isNull() || cst.isValuePointer() || cst.isBlockPointer() || (dstType.isReference() && ptr != 0) ||
                           (dstType.isReference() && sema.typeMgr().get(dstType.payloadTypeRef()).sizeOf(sema.ctx()) == 0));
        writeValue(dstBytes, ptr);
        return Result::Continue;
    }

    Result lowerAggregateArrayToBytesInternal(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values)
    {
        TaskContext&    ctx         = sema.ctx();
        const auto      elemTypeRef = dstType.payloadArrayElemTypeRef();
        const TypeInfo& elemType    = sema.typeMgr().get(elemTypeRef);
        const uint64_t  elemSize    = elemType.sizeOf(ctx);
        uint64_t        totalCount  = 1;
        const auto&     dims        = dstType.payloadArrayDims();

        for (const auto dim : dims)
            totalCount *= dim;

        SWC_ASSERT(!elemSize || totalCount <= dstBytes.size() / elemSize);

        const uint64_t maxCount = std::min<uint64_t>(values.size(), totalCount);
        for (uint64_t i = 0; i < maxCount; ++i)
        {
            SWC_RESULT(lowerConstantToBytes(sema, subBytes(dstBytes, i * elemSize, elemSize), elemTypeRef, values[i]));
        }

        return Result::Continue;
    }

    Result lowerAggregateTupleToBytesInternal(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values)
    {
        TaskContext& ctx    = sema.ctx();
        uint64_t     offset = 0;
        size_t       index  = 0;

        for (const TypeRef elemTypeRef : dstType.payloadAggregate().types)
        {
            const TypeInfo& elemType = sema.typeMgr().get(elemTypeRef);
            uint32_t        align    = elemType.alignOf(ctx);
            const uint64_t  elemSize = elemType.sizeOf(ctx);
            if (!align)
                align = 1;

            if (!elemSize)
                continue;

            offset = Math::alignUpU64(offset, align);
            assertByteRange(offset, elemSize, dstBytes.size());

            if (index < values.size())
                SWC_RESULT(lowerConstantToBytes(sema, subBytes(dstBytes, offset, elemSize), elemTypeRef, values[index]));

            offset += elemSize;
            ++index;
        }

        return Result::Continue;
    }

    Result lowerConstantToBytes(Sema& sema, ByteSpanRW dstBytes, TypeRef dstTypeRef, ConstantRef cstRef)
    {
        const ConstantValue& cst = sema.cstMgr().get(cstRef);
        if (cst.isUndefined())
            return Result::Continue;

        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
        if (dstType.isAlias())
        {
            const TypeRef unwrappedTypeRef = dstType.unwrap(sema.ctx(), dstTypeRef, TypeExpandE::Alias);
            SWC_ASSERT(unwrappedTypeRef.isValid());
            return lowerConstantToBytes(sema, dstBytes, unwrappedTypeRef, cstRef);
        }

        if (dstType.isEnum())
        {
            const TypeRef underlyingTypeRef = dstType.payloadSymEnum().underlyingTypeRef();
            ConstantRef   enumValueRef      = cstRef;
            if (cst.isEnumValue())
                enumValueRef = cst.getEnumValue();
            return lowerConstantToBytes(sema, dstBytes, underlyingTypeRef, enumValueRef);
        }

        if (dstType.isStruct())
        {
            if (cst.isStruct())
            {
                copyBytes(dstBytes, cst.getStruct());
                return Result::Continue;
            }

            if (cst.isAggregateStruct())
            {
                SWC_RESULT(ConstantLower::lowerAggregateStructToBytes(sema, dstBytes, dstType, cst.getAggregateStruct()));
                return Result::Continue;
            }

            SWC_UNREACHABLE();
        }

        if (dstType.isArray())
        {
            if (cst.isArray())
            {
                copyBytes(dstBytes, cst.getArray());
                return Result::Continue;
            }

            SWC_INTERNAL_CHECK(cst.isAggregateArray());
            return lowerAggregateArrayToBytesInternal(sema, dstBytes, dstType, cst.getAggregateArray());
        }

        if (dstType.isAggregateStruct())
        {
            if (cst.isStruct())
            {
                copyBytes(dstBytes, cst.getStruct());
                return Result::Continue;
            }

            SWC_INTERNAL_CHECK(cst.isAggregateStruct());
            return lowerAggregateTupleToBytesInternal(sema, dstBytes, dstType, cst.getAggregateStruct());
        }

        if (dstType.isAggregateArray())
        {
            if (cst.isStruct())
            {
                copyBytes(dstBytes, cst.getStruct());
                return Result::Continue;
            }

            SWC_INTERNAL_CHECK(cst.isAggregateArray());
            return lowerAggregateTupleToBytesInternal(sema, dstBytes, dstType, cst.getAggregateArray());
        }

        if (dstType.isBool())
        {
            SWC_ASSERT(cst.isBool() && dstBytes.size() == 1);
            const uint8_t v = cst.getBool() ? 1 : 0;
            writeValue(dstBytes, v);
            return Result::Continue;
        }

        if (dstType.isChar())
        {
            SWC_ASSERT(cst.isChar() && dstBytes.size() == sizeof(char32_t));
            const char32_t v = cst.getChar();
            writeValue(dstBytes, v);
            return Result::Continue;
        }

        if (dstType.isRune())
        {
            SWC_ASSERT(cst.isRune() && dstBytes.size() == sizeof(char32_t));
            const char32_t v = cst.getRune();
            writeValue(dstBytes, v);
            return Result::Continue;
        }

        if (dstType.isInt())
        {
            SWC_ASSERT(cst.isInt());
            const uint64_t v = cst.getInt().as64();
            SWC_ASSERT(dstBytes.size() <= sizeof(v));
            std::memcpy(dstBytes.data(), &v, dstBytes.size());
            return Result::Continue;
        }

        if (dstType.isFloat())
        {
            SWC_ASSERT(cst.isFloat());
            if (dstType.payloadFloatBits() == 32)
            {
                const float v = cst.getFloat().asFloat();
                writeValue(dstBytes, v);
                return Result::Continue;
            }

            if (dstType.payloadFloatBits() == 64)
            {
                const double v = cst.getFloat().asDouble();
                writeValue(dstBytes, v);
                return Result::Continue;
            }

            SWC_UNREACHABLE();
        }

        if (dstType.isString())
            return lowerStringConstantToBytes(dstBytes, dstTypeRef, cst);

        if (dstType.isSlice())
            return lowerSliceConstantToBytes(sema, dstBytes, dstType, dstTypeRef, cst);

        if (dstType.isInterface())
            return lowerInterfaceConstantToBytes(dstBytes, dstTypeRef, cst);

        if (dstType.isAny())
            return lowerAnyConstantToBytes(sema, dstBytes, dstTypeRef, cstRef, cst);

        if (dstType.isFunction() && dstType.isLambdaClosure())
            return lowerClosureConstantToBytes(dstBytes, cst);

        if (dstType.isAnyPointer() || dstType.isReference() || dstType.isTypeInfo() || dstType.isCString() || dstType.isFunction())
            return lowerPointerLikeConstantToBytes(sema, dstBytes, dstType, cstRef, cst);

        SWC_UNREACHABLE();
    }

    // Aggregate layouts are reconstructed here, so nested payloads reuse the same offset rules as lowering.
    Result materializeStaticAggregate(Sema& sema, DataSegment& segment, const TypeInfo& typeInfo, const StaticPayload& payload)
    {
        TaskContext& ctx    = sema.ctx();
        uint64_t     offset = 0;

        for (const TypeRef elemTypeRef : typeInfo.payloadAggregate().types)
        {
            const TypeInfo& elemType = sema.typeMgr().get(elemTypeRef);
            uint32_t        align    = elemType.alignOf(ctx);
            const uint64_t  elemSize = elemType.sizeOf(ctx);
            if (!align)
                align = 1;

            if (!elemSize)
                continue;

            offset = Math::alignUpU64(offset, align);
            assertByteRange(offset, elemSize, payload.dstBytes.size());
            SWC_RESULT(materializeStaticSubPayload(sema, segment, elemTypeRef, payload, offset, elemSize));
            offset += elemSize;
        }

        return Result::Continue;
    }

    Result materializeStaticPayloadInPlace(Sema& sema, DataSegment& segment, TypeRef typeRef, const StaticPayload& payload)
    {
        SWC_INTERNAL_CHECK(typeRef.isValid());

        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (typeInfo.isAlias())
        {
            const TypeRef unwrappedTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
            SWC_INTERNAL_CHECK(unwrappedTypeRef.isValid());
            return materializeStaticPayloadInPlace(sema, segment, unwrappedTypeRef, payload);
        }

        const uint64_t sizeOf = typeInfo.sizeOf(ctx);
        SWC_INTERNAL_CHECK(sizeOf == payload.dstBytes.size());
        SWC_INTERNAL_CHECK(sizeOf == payload.srcBytes.size());

        switch (typeInfo.kind())
        {
            case TypeInfoKind::Enum:
                return materializeStaticPayloadInPlace(sema, segment, typeInfo.payloadSymEnum().underlyingTypeRef(), payload);

            case TypeInfoKind::Bool:
            case TypeInfoKind::Char:
            case TypeInfoKind::Rune:
            case TypeInfoKind::Int:
            case TypeInfoKind::Float:
                return materializeStaticScalar(payload.dstBytes, payload.srcBytes);

            case TypeInfoKind::String:
                return materializeStaticString(sema, segment, payload);

            case TypeInfoKind::Any:
                return materializeStaticAny(sema, segment, payload);

            case TypeInfoKind::Slice:
                return materializeStaticSlice(sema, segment, typeInfo, payload);

            case TypeInfoKind::Array:
                return materializeStaticArray(sema, segment, typeInfo, payload);

            case TypeInfoKind::Struct:
                return materializeStaticStruct(sema, segment, typeInfo, payload);

            case TypeInfoKind::AggregateStruct:
            case TypeInfoKind::AggregateArray:
                return materializeStaticAggregate(sema, segment, typeInfo, payload);

            case TypeInfoKind::Interface:
                return materializeStaticInterface(sema, segment, payload);

            case TypeInfoKind::ValuePointer:
            case TypeInfoKind::BlockPointer:
            case TypeInfoKind::Reference:
            case TypeInfoKind::MoveReference:
            case TypeInfoKind::CString:
            case TypeInfoKind::Function:
                if (typeInfo.isLambdaClosure())
                    return materializeStaticClosure(sema, segment, payload);
                return materializeStaticPointer(sema, segment, payload);

            case TypeInfoKind::TypeInfo:
                return materializeStaticPointer(sema, segment, payload);

            default:
                break;
        }

        SWC_UNREACHABLE();
    }
}

Result ConstantLower::lowerToBytes(Sema& sema, ByteSpanRW dstBytes, ConstantRef cstRef, TypeRef dstTypeRef)
{
    return lowerConstantToBytes(sema, dstBytes, dstTypeRef, cstRef);
}

Result ConstantLower::lowerAggregateArrayToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values)
{
    return lowerAggregateArrayToBytesInternal(sema, dstBytes, dstType, values);
}

Result ConstantLower::lowerAggregateStructToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values)
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
        assertByteRange(fieldOffset, fieldSize, dstBytes.size());

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
            SWC_RESULT(lowerConstantToBytes(sema, subBytes(dstBytes, fieldOffset, fieldSize), fieldTypeRef, valueRef));
        else if (fieldSize)
            zeroBytes(subBytes(dstBytes, fieldOffset, fieldSize));
    }

    return Result::Continue;
}

Result ConstantLower::materializeStaticPayload(MaterializedPayloadResult& outPayload, Sema& sema, DataSegment& segment, TypeRef typeRef, const ByteSpan srcBytes)
{
    outPayload = {};
    SWC_INTERNAL_CHECK(typeRef.isValid());

    const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
    const uint64_t  sizeOf   = typeInfo.sizeOf(sema.ctx());
    const uint32_t  alignOf  = typeInfo.alignOf(sema.ctx());
    SWC_ASSERT(sizeOf <= std::numeric_limits<uint32_t>::max());
    SWC_INTERNAL_CHECK(sizeOf == srcBytes.size());

    const auto [offset, storage] = segment.reserveBytes(static_cast<uint32_t>(sizeOf), alignOf, true);
    outPayload.offset            = offset;
    outPayload.bytes             = rawBytes(storage, sizeOf);
    return materializeStaticPayloadInPlace(sema, segment, typeRef, {.baseOffset = offset, .dstBytes = outPayload.bytes, .srcBytes = srcBytes});
}

Result ConstantLower::materializeStaticPayload(uint32_t& outOffset, Sema& sema, DataSegment& segment, TypeRef typeRef, const ByteSpan srcBytes)
{
    MaterializedPayloadResult outPayload;
    const Result              result = materializeStaticPayload(outPayload, sema, segment, typeRef, srcBytes);
    outOffset                        = outPayload.offset;
    return result;
}

SWC_END_NAMESPACE();
