#include "pch.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
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
    Result materializeStaticPayloadInPlace(Sema& sema, DataSegment& segment, TypeRef typeRef, uint32_t baseOffset, ByteSpanRW dstBytes, ByteSpan srcBytes);

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

    Result copyBytes(ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        SWC_ASSERT(dstBytes.size() == srcBytes.size());
        if (dstBytes.size() != srcBytes.size())
            return Result::Error;

        if (!dstBytes.empty())
            std::memcpy(dstBytes.data(), srcBytes.data(), dstBytes.size());
        return Result::Continue;
    }

    Result zeroBytes(ByteSpanRW dstBytes)
    {
        if (!dstBytes.empty())
            std::memset(dstBytes.data(), 0, dstBytes.size());
        return Result::Continue;
    }

    template<typename T>
    Result writeValue(ByteSpanRW dstBytes, const T& value)
    {
        SWC_ASSERT(dstBytes.size() == sizeof(T));
        if (dstBytes.size() != sizeof(T))
            return Result::Error;

        std::memcpy(dstBytes.data(), &value, sizeof(T));
        return Result::Continue;
    }

    template<typename T>
    Result validateRuntimePayloadSize(const ByteSpan bytes)
    {
        SWC_ASSERT(bytes.size() == sizeof(T));
        if (bytes.size() != sizeof(T))
            return Result::Error;
        return Result::Continue;
    }

    Result validateByteRange(const uint64_t offset, const uint64_t size, const uint64_t totalSize)
    {
        const bool inRange = offset <= totalSize && size <= totalSize - offset;
        SWC_ASSERT(inRange);
        if (!inRange)
            return Result::Error;
        return Result::Continue;
    }

    Result materializeStaticSubPayload(Sema&            sema,
                                       DataSegment&     segment,
                                       const TypeRef    typeRef,
                                       const uint32_t   baseOffset,
                                       const ByteSpanRW dstBytes,
                                       const ByteSpan   srcBytes,
                                       const uint64_t   offset,
                                       const uint64_t   size)
    {
        return materializeStaticPayloadInPlace(sema,
                                               segment,
                                               typeRef,
                                               addByteOffset(baseOffset, offset),
                                               subBytes(dstBytes, offset, size),
                                               subBytes(srcBytes, offset, size));
    }

    AstNodeRef fallbackConstantLowerNodeRef(Sema& sema)
    {
        const AstNodeRef stateNodeRef = sema.ctx().state().nodeRef;
        if (stateNodeRef.isValid())
            return stateNodeRef;
        return sema.curNodeRef();
    }

    Result reportConstantLowerFailure(Sema& sema, const std::string_view because)
    {
        TaskContext& ctx = sema.ctx();
        if (ctx.hasError())
            return Result::Error;

        const AstNodeRef nodeRef = fallbackConstantLowerNodeRef(sema);
        if (nodeRef.isValid())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_compiler_error, nodeRef, SemaError::ReportLocation::Token);
            diag.addArgument(Diagnostic::ARG_BECAUSE, because);
            diag.report(ctx);
            return Result::Error;
        }

        if (ctx.state().codeRef.isValid())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_compiler_error, ctx.state().codeRef);
            diag.addArgument(Diagnostic::ARG_BECAUSE, because);
            diag.report(ctx);
            return Result::Error;
        }

        SWC_ASSERT(false && "constant lowering failure without source location");
        ctx.setHasError();
        return Result::Error;
    }

    Result resolveSegmentOffset(uint32_t& outOffset, Sema& sema, const DataSegment& segment, const void* sourcePtr)
    {
        outOffset = INVALID_REF;
        if (!sourcePtr)
            return Result::Continue;

        uint32_t  shardIndex = 0;
        const Ref targetRef  = sema.cstMgr().findDataSegmentRef(shardIndex, sourcePtr);
        if (targetRef == INVALID_REF)
            return reportConstantLowerFailure(sema, "cannot materialize static data from a pointer outside compiler constant storage");

        if (&segment != &sema.cstMgr().shardDataSegment(shardIndex))
            return reportConstantLowerFailure(sema, "cannot materialize static data that spans multiple compiler constant-storage shards");

        outOffset = targetRef;
        return Result::Continue;
    }

    template<typename StorageT, typename PointerT>
    Result relocateSegmentPointer(PointerT*& outPtr, Sema& sema, DataSegment& segment, const uint32_t relocationOffset, const void* sourcePtr)
    {
        uint32_t targetOffset = INVALID_REF;
        SWC_RESULT(resolveSegmentOffset(targetOffset, sema, segment, sourcePtr));

        outPtr = targetOffset == INVALID_REF ? nullptr : static_cast<PointerT*>(segment.ptr<StorageT>(targetOffset));
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
        return copyBytes(dstBytes, srcBytes);
    }

    Result materializeStaticString(Sema& sema, DataSegment& segment, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        SWC_RESULT(validateRuntimePayloadSize<Runtime::String>(srcBytes));

        auto&       dstString = writable<Runtime::String>(dstBytes);
        const auto& srcString = readable<Runtime::String>(srcBytes);
        if (!srcString.ptr)
        {
            SWC_ASSERT(srcString.length == 0);
            if (srcString.length != 0)
                return Result::Error;

            dstString.ptr    = nullptr;
            dstString.length = 0;
            return Result::Continue;
        }

        dstString.length = segment.addString(baseOffset, offsetof(Runtime::String, ptr), std::string_view(srcString.ptr, srcString.length));
        return Result::Continue;
    }

    Result materializeStaticAny(Sema& sema, DataSegment& segment, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        TaskContext& ctx = sema.ctx();
        SWC_RESULT(validateRuntimePayloadSize<Runtime::Any>(srcBytes));

        auto&       dstAny = writable<Runtime::Any>(dstBytes);
        const auto& srcAny = readable<Runtime::Any>(srcBytes);
        if (!srcAny.type)
        {
            SWC_ASSERT(srcAny.value == nullptr);
            if (srcAny.value != nullptr)
                return Result::Error;

            dstAny.value = nullptr;
            dstAny.type  = nullptr;
            return Result::Continue;
        }

        SWC_RESULT(relocateSegmentPointer<Runtime::TypeInfo>(dstAny.type, sema, segment, baseOffset + offsetof(Runtime::Any, type), srcAny.type));
        if (!srcAny.value)
            return Result::Continue;

        const TypeRef valueTypeRef = sema.typeGen().getBackTypeRef(srcAny.type);
        SWC_ASSERT(valueTypeRef.isValid());
        if (valueTypeRef.isInvalid())
            return Result::Error;

        const uint64_t valueSize = sema.typeMgr().get(valueTypeRef).sizeOf(ctx);
        SWC_ASSERT(valueSize <= std::numeric_limits<uint32_t>::max());

        uint32_t valueOffset = INVALID_REF;
        SWC_RESULT(ConstantLower::materializeStaticPayload(valueOffset,
                                                           sema,
                                                           segment,
                                                           valueTypeRef,
                                                           rawBytes(srcAny.value, valueSize)));
        dstAny.value = segment.ptr<std::byte>(valueOffset);
        segment.addRelocation(baseOffset + offsetof(Runtime::Any, value), valueOffset);
        return Result::Continue;
    }

    Result materializeStaticSlice(Sema& sema, DataSegment& segment, const TypeInfo& typeInfo, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        TaskContext& ctx = sema.ctx();
        SWC_RESULT(validateRuntimePayloadSize<Runtime::Slice<std::byte>>(srcBytes));

        auto&           dstSlice       = writable<Runtime::Slice<std::byte>>(dstBytes);
        const auto&     srcSlice       = readable<Runtime::Slice<std::byte>>(srcBytes);
        const TypeRef   elementTypeRef = typeInfo.payloadTypeRef();
        const TypeInfo& elementType    = sema.typeMgr().get(elementTypeRef);
        const uint64_t  elementSize    = elementType.sizeOf(ctx);
        if (srcSlice.count == 0)
        {
            dstSlice.ptr   = nullptr;
            dstSlice.count = 0;
            return Result::Continue;
        }

        SWC_ASSERT(srcSlice.ptr != nullptr);
        if (!srcSlice.ptr)
            return Result::Error;

        SWC_ASSERT(elementSize != 0);
        if (!elementSize)
            return Result::Error;

        const uint64_t byteCount = srcSlice.count * elementSize;
        SWC_ASSERT(byteCount <= std::numeric_limits<uint32_t>::max());
        const auto [dataOffset, dataStorage] = segment.reserveBytes(static_cast<uint32_t>(byteCount), elementType.alignOf(ctx), true);
        const ByteSpanRW dstSliceBytes = rawBytes(dataStorage, byteCount);
        const ByteSpan   srcSliceBytes = rawBytes(srcSlice.ptr, byteCount);
        for (uint64_t idx = 0; idx < srcSlice.count; ++idx)
        {
            const uint64_t elementOffset = idx * elementSize;
            SWC_RESULT(materializeStaticSubPayload(sema, segment, elementTypeRef, dataOffset, dstSliceBytes, srcSliceBytes, elementOffset, elementSize));
        }

        dstSlice.ptr   = dataStorage;
        dstSlice.count = srcSlice.count;
        segment.addRelocation(baseOffset + offsetof(Runtime::Slice<std::byte>, ptr), dataOffset);
        return Result::Continue;
    }

    Result materializeStaticArray(Sema& sema, DataSegment& segment, const TypeInfo& typeInfo, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        TaskContext&    ctx            = sema.ctx();
        const TypeRef   elementTypeRef = typeInfo.payloadArrayElemTypeRef();
        const TypeInfo& elementType    = sema.typeMgr().get(elementTypeRef);
        const uint64_t  elementSize    = elementType.sizeOf(ctx);
        if (!elementSize)
            return reportConstantLowerFailure(sema, "cannot materialize a static array of a zero-sized element type");

        uint64_t totalCount = 1;
        for (const uint64_t dim : typeInfo.payloadArrayDims())
            totalCount *= dim;

        for (uint64_t idx = 0; idx < totalCount; ++idx)
        {
            const uint64_t elementOffset = idx * elementSize;
            SWC_RESULT(materializeStaticSubPayload(sema, segment, elementTypeRef, baseOffset, dstBytes, srcBytes, elementOffset, elementSize));
        }

        return Result::Continue;
    }

    Result materializeStaticStruct(Sema& sema, DataSegment& segment, const TypeInfo& typeInfo, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
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
            SWC_RESULT(validateByteRange(fieldOffset, fieldSize, srcBytes.size()));

            SWC_RESULT(materializeStaticSubPayload(sema, segment, fieldTypeRef, baseOffset, dstBytes, srcBytes, fieldOffset, fieldSize));
        }

        return Result::Continue;
    }

    Result materializeStaticInterface(Sema& sema, DataSegment& segment, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        SWC_RESULT(validateRuntimePayloadSize<Runtime::Interface>(srcBytes));

        auto&       dstInterface = writable<Runtime::Interface>(dstBytes);
        const auto& srcInterface = readable<Runtime::Interface>(srcBytes);
        SWC_RESULT(relocateSegmentPointer<std::byte>(dstInterface.obj, sema, segment, baseOffset + offsetof(Runtime::Interface, obj), srcInterface.obj));
        SWC_RESULT(relocateSegmentPointer<void*>(dstInterface.itable, sema, segment, baseOffset + offsetof(Runtime::Interface, itable), srcInterface.itable));
        return Result::Continue;
    }

    Result materializeStaticClosure(Sema& sema, DataSegment& segment, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        SWC_RESULT(validateRuntimePayloadSize<Runtime::ClosureValue>(srcBytes));

        auto&       dstClosure = writable<Runtime::ClosureValue>(dstBytes);
        const auto& srcClosure = readable<Runtime::ClosureValue>(srcBytes);

        SWC_RESULT(relocateSegmentPointer<std::byte>(dstClosure.invoke, sema, segment, baseOffset + offsetof(Runtime::ClosureValue, invoke), srcClosure.invoke));
        SWC_RESULT(copyBytes(rawBytes(dstClosure.capture, sizeof(dstClosure.capture)), rawBytes(srcClosure.capture, sizeof(srcClosure.capture))));

        const uint64_t capturedTarget = readable<uint64_t>(rawBytes(srcClosure.capture, sizeof(uint64_t)));
        if (capturedTarget)
        {
            uint64_t relocatedTarget = 0;
            SWC_RESULT(relocateSegmentAddress(relocatedTarget,
                                              sema,
                                              segment,
                                              baseOffset + offsetof(Runtime::ClosureValue, capture),
                                              pointerFromRawAddress<const void>(capturedTarget)));
            writable<uint64_t>(rawBytes(dstClosure.capture, sizeof(uint64_t))) = relocatedTarget;
        }

        return Result::Continue;
    }

    Result materializeStaticPointer(Sema& sema, DataSegment& segment, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        SWC_RESULT(validateRuntimePayloadSize<uint64_t>(srcBytes));

        auto&      dstPtr    = writable<uint64_t>(dstBytes);
        const auto srcPtr    = pointerFromRawAddress<const void>(readable<uint64_t>(srcBytes));
        return relocateSegmentAddress(dstPtr, sema, segment, baseOffset, srcPtr);
    }

    // These helpers keep `lowerConstantToBytes` focused on dispatching by runtime shape.
    Result lowerStringConstantToBytes(ByteSpanRW dstBytes, const TypeRef dstTypeRef, const ConstantValue& cst)
    {
        SWC_ASSERT((cst.isNull() || cst.isString() || cst.isStruct(dstTypeRef)) && dstBytes.size() == sizeof(Runtime::String));
        if (cst.isStruct(dstTypeRef))
            return copyBytes(dstBytes, cst.getStruct());

        Runtime::String runtimeValue = {};
        if (cst.isString())
        {
            const std::string_view str = cst.getString();
            runtimeValue.ptr           = str.data();
            runtimeValue.length        = str.size();
        }

        return writeValue(dstBytes, runtimeValue);
    }

    Result lowerSliceConstantToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const TypeRef dstTypeRef, const ConstantValue& cst)
    {
        SWC_ASSERT((cst.isNull() || cst.isSlice() || cst.isStruct(dstTypeRef)) && dstBytes.size() == sizeof(Runtime::Slice<uint8_t>));
        if (cst.isStruct(dstTypeRef))
            return copyBytes(dstBytes, cst.getStruct());

        Runtime::Slice<uint8_t> runtimeValue = {};
        if (cst.isSlice())
        {
            const ByteSpan  bytes       = cst.getSlice();
            const TypeInfo& elementType = sema.typeMgr().get(dstType.payloadTypeRef());
            const uint64_t  elementSize = elementType.sizeOf(sema.ctx());
            runtimeValue.count          = elementSize ? bytes.size() / elementSize : 0;
            runtimeValue.ptr            = runtimeValue.count ? reinterpret_cast<uint8_t*>(const_cast<std::byte*>(bytes.data())) : nullptr;
        }

        return writeValue(dstBytes, runtimeValue);
    }

    Result lowerInterfaceConstantToBytes(ByteSpanRW dstBytes, const TypeRef dstTypeRef, const ConstantValue& cst)
    {
        SWC_ASSERT((cst.isNull() || cst.isStruct(dstTypeRef)) && dstBytes.size() == sizeof(Runtime::Interface));
        if (cst.isStruct(dstTypeRef))
            return copyBytes(dstBytes, cst.getStruct());

        constexpr Runtime::Interface runtimeValue = {};
        return writeValue(dstBytes, runtimeValue);
    }

    Result lowerAnyConstantToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeRef dstTypeRef, ConstantRef cstRef, const ConstantValue& cst)
    {
        SWC_ASSERT(dstBytes.size() == sizeof(Runtime::Any));
        if (cst.isNull())
            return zeroBytes(dstBytes);

        if (cst.isStruct())
            return copyBytes(dstBytes, cst.getStruct());

        Runtime::Any anyValue = {};

        const TypeRef valueTypeRef = cst.typeRef();
        SWC_ASSERT(valueTypeRef.isValid());
        SWC_ASSERT(valueTypeRef != dstTypeRef);

        ConstantRef typeInfoCstRef = ConstantRef::invalid();
        SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, typeInfoCstRef, valueTypeRef, sema.ctx().state().nodeRef));
        SWC_ASSERT(typeInfoCstRef.isValid());

        const ConstantValue& typeInfoCst = sema.cstMgr().get(typeInfoCstRef);
        SWC_ASSERT(typeInfoCst.isValuePointer());
        anyValue.type = pointerFromRawAddress<const Runtime::TypeInfo>(typeInfoCst.getValuePointer());

        const char* loweredValueData = nullptr;
        SWC_RESULT(lowerConstantToPayloadBuffer(loweredValueData, sema, cstRef, valueTypeRef));
        anyValue.value = const_cast<char*>(loweredValueData);
        return writeValue(dstBytes, anyValue);
    }

    Result lowerClosureConstantToBytes(ByteSpanRW dstBytes, const ConstantValue& cst)
    {
        SWC_ASSERT(dstBytes.size() == sizeof(Runtime::ClosureValue));
        if (cst.isNull())
            return zeroBytes(dstBytes);

        if (cst.isStruct())
            return copyBytes(dstBytes, cst.getStruct());

        SWC_ASSERT(cst.isNull() || cst.isStruct());
        return Result::Continue;
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

        SWC_ASSERT(cst.isNull() || cst.isValuePointer() || cst.isBlockPointer() || (dstType.isReference() && ptr != 0) ||
                   (dstType.isReference() && sema.typeMgr().get(dstType.payloadTypeRef()).sizeOf(sema.ctx()) == 0));
        return writeValue(dstBytes, ptr);
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

        SWC_ASSERT(!elemSize || elemSize * totalCount <= dstBytes.size());

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
            SWC_RESULT(validateByteRange(offset, elemSize, dstBytes.size()));

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
                return copyBytes(dstBytes, cst.getStruct());

            if (cst.isAggregateStruct())
            {
                SWC_RESULT(ConstantLower::lowerAggregateStructToBytes(sema, dstBytes, dstType, cst.getAggregateStruct()));
                return Result::Continue;
            }

            SWC_ASSERT(cst.isStruct() || cst.isAggregateStruct());
            return Result::Continue;
        }

        if (dstType.isArray())
        {
            if (cst.isArray())
                return copyBytes(dstBytes, cst.getArray());

            SWC_ASSERT(cst.isAggregateArray());
            return lowerAggregateArrayToBytesInternal(sema, dstBytes, dstType, cst.getAggregateArray());
        }

        if (dstType.isAggregateStruct())
        {
            if (cst.isStruct())
                return copyBytes(dstBytes, cst.getStruct());

            SWC_ASSERT(cst.isAggregateStruct());
            return lowerAggregateTupleToBytesInternal(sema, dstBytes, dstType, cst.getAggregateStruct());
        }

        if (dstType.isAggregateArray())
        {
            if (cst.isStruct())
                return copyBytes(dstBytes, cst.getStruct());

            SWC_ASSERT(cst.isAggregateArray());
            return lowerAggregateTupleToBytesInternal(sema, dstBytes, dstType, cst.getAggregateArray());
        }

        if (dstType.isBool())
        {
            SWC_ASSERT(cst.isBool() && dstBytes.size() == 1);
            const uint8_t v = cst.getBool() ? 1 : 0;
            return writeValue(dstBytes, v);
        }

        if (dstType.isChar())
        {
            SWC_ASSERT(cst.isChar() && dstBytes.size() == sizeof(char32_t));
            const char32_t v = cst.getChar();
            return writeValue(dstBytes, v);
        }

        if (dstType.isRune())
        {
            SWC_ASSERT(cst.isRune() && dstBytes.size() == sizeof(char32_t));
            const char32_t v = cst.getRune();
            return writeValue(dstBytes, v);
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
                return writeValue(dstBytes, v);
            }

            if (dstType.payloadFloatBits() == 64)
            {
                const double v = cst.getFloat().asDouble();
                return writeValue(dstBytes, v);
            }

            SWC_ASSERT(dstType.payloadFloatBits() == 32 || dstType.payloadFloatBits() == 64);
            return Result::Continue;
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

        SWC_ASSERT(dstType.isEnum() || dstType.isStruct() || dstType.isArray() || dstType.isBool() || dstType.isChar() ||
                   dstType.isRune() || dstType.isInt() || dstType.isFloat() || dstType.isString() || dstType.isSlice() ||
                   dstType.isAny() || dstType.isAnyPointer() || dstType.isReference() || dstType.isTypeInfo() || dstType.isCString() || dstType.isFunction());
        return Result::Continue;
    }

    // Aggregate layouts are reconstructed here so nested payloads reuse the same offset rules as lowering.
    Result materializeStaticAggregate(Sema& sema, DataSegment& segment, const TypeInfo& typeInfo, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
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
            SWC_RESULT(validateByteRange(offset, elemSize, dstBytes.size()));
            SWC_RESULT(materializeStaticSubPayload(sema, segment, elemTypeRef, baseOffset, dstBytes, srcBytes, offset, elemSize));
            offset += elemSize;
        }

        return Result::Continue;
    }

    Result materializeStaticPayloadInPlace(Sema& sema, DataSegment& segment, TypeRef typeRef, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        SWC_ASSERT(typeRef.isValid());
        if (typeRef.isInvalid())
            return Result::Error;

        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (typeInfo.isAlias())
        {
            const TypeRef unwrappedTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
            SWC_ASSERT(unwrappedTypeRef.isValid());
            if (unwrappedTypeRef.isInvalid())
                return Result::Error;
            return materializeStaticPayloadInPlace(sema, segment, unwrappedTypeRef, baseOffset, dstBytes, srcBytes);
        }

        const uint64_t sizeOf = typeInfo.sizeOf(ctx);
        SWC_ASSERT(sizeOf == dstBytes.size() && sizeOf == srcBytes.size());
        if (sizeOf != dstBytes.size() || sizeOf != srcBytes.size())
            return Result::Error;

        switch (typeInfo.kind())
        {
            case TypeInfoKind::Enum:
                return materializeStaticPayloadInPlace(sema, segment, typeInfo.payloadSymEnum().underlyingTypeRef(), baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::Bool:
            case TypeInfoKind::Char:
            case TypeInfoKind::Rune:
            case TypeInfoKind::Int:
            case TypeInfoKind::Float:
                return materializeStaticScalar(dstBytes, srcBytes);

            case TypeInfoKind::String:
                return materializeStaticString(sema, segment, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::Any:
                return materializeStaticAny(sema, segment, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::Slice:
                return materializeStaticSlice(sema, segment, typeInfo, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::Array:
                return materializeStaticArray(sema, segment, typeInfo, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::Struct:
                return materializeStaticStruct(sema, segment, typeInfo, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::AggregateStruct:
            case TypeInfoKind::AggregateArray:
                return materializeStaticAggregate(sema, segment, typeInfo, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::Interface:
                return materializeStaticInterface(sema, segment, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::ValuePointer:
            case TypeInfoKind::BlockPointer:
            case TypeInfoKind::Reference:
            case TypeInfoKind::MoveReference:
            case TypeInfoKind::CString:
            case TypeInfoKind::Function:
                if (typeInfo.isLambdaClosure())
                    return materializeStaticClosure(sema, segment, baseOffset, dstBytes, srcBytes);
                return materializeStaticPointer(sema, segment, baseOffset, dstBytes, srcBytes);

            case TypeInfoKind::TypeInfo:
                return materializeStaticPointer(sema, segment, baseOffset, dstBytes, srcBytes);

            default:
                break;
        }

        SWC_ASSERT(false);
        return Result::Error;
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
        SWC_RESULT(validateByteRange(fieldOffset, fieldSize, dstBytes.size()));

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
            SWC_RESULT(zeroBytes(subBytes(dstBytes, fieldOffset, fieldSize)));
    }

    return Result::Continue;
}

Result ConstantLower::materializeStaticPayload(uint32_t& outOffset, Sema& sema, DataSegment& segment, TypeRef typeRef, const ByteSpan srcBytes)
{
    outOffset = INVALID_REF;
    SWC_ASSERT(typeRef.isValid());
    if (typeRef.isInvalid())
        return Result::Error;

    const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
    const uint64_t  sizeOf   = typeInfo.sizeOf(sema.ctx());
    const uint32_t  alignOf  = typeInfo.alignOf(sema.ctx());
    SWC_ASSERT(sizeOf <= std::numeric_limits<uint32_t>::max());
    SWC_ASSERT(sizeOf == srcBytes.size());

    const auto [offset, storage] = segment.reserveBytes(static_cast<uint32_t>(sizeOf), alignOf, true);
    outOffset                    = offset;
    return materializeStaticPayloadInPlace(sema, segment, typeRef, offset, rawBytes(storage, sizeOf), srcBytes);
}

SWC_END_NAMESPACE();
