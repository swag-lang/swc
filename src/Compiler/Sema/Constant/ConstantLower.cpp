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

    Result materializeStaticScalar(ByteSpanRW dstBytes, ByteSpan srcBytes)
    {
        if (!dstBytes.empty())
            std::memcpy(dstBytes.data(), srcBytes.data(), dstBytes.size());
        return Result::Continue;
    }

    Result materializeStaticString(Sema& sema, DataSegment& segment, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        if (srcBytes.size() != sizeof(Runtime::String))
            return reportConstantLowerFailure(sema, "cannot materialize a static string from an invalid runtime payload size");

        auto&       dstString = writable<Runtime::String>(dstBytes);
        const auto& srcString = readable<Runtime::String>(srcBytes);
        if (!srcString.ptr)
        {
            if (srcString.length != 0)
                return reportConstantLowerFailure(sema, "cannot materialize a static string with a null pointer and a non-zero length");

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
        if (srcBytes.size() != sizeof(Runtime::Any))
            return reportConstantLowerFailure(sema, "cannot materialize a static any from an invalid runtime payload size");

        auto&       dstAny = writable<Runtime::Any>(dstBytes);
        const auto& srcAny = readable<Runtime::Any>(srcBytes);
        if (!srcAny.type)
        {
            if (srcAny.value != nullptr)
                return reportConstantLowerFailure(sema, "cannot materialize a static any with a value but no runtime type");

            dstAny.value = nullptr;
            dstAny.type  = nullptr;
            return Result::Continue;
        }

        uint32_t typeOffset = INVALID_REF;
        SWC_RESULT(resolveSegmentOffset(typeOffset, sema, segment, srcAny.type));
        dstAny.type = typeOffset == INVALID_REF ? nullptr : segment.ptr<Runtime::TypeInfo>(typeOffset);
        if (typeOffset != INVALID_REF)
            segment.addRelocation(baseOffset + offsetof(Runtime::Any, type), typeOffset);
        if (!srcAny.value)
            return Result::Continue;

        const TypeRef valueTypeRef = sema.typeGen().getBackTypeRef(srcAny.type);
        if (valueTypeRef.isInvalid())
            return reportConstantLowerFailure(sema, "cannot materialize a static any with an unknown runtime type");

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
        if (srcBytes.size() != sizeof(Runtime::Slice<std::byte>))
            return reportConstantLowerFailure(sema, "cannot materialize a static slice from an invalid runtime payload size");

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

        if (!srcSlice.ptr)
            return reportConstantLowerFailure(sema, "cannot materialize a non-empty static slice without backing data");
        if (!elementSize)
            return reportConstantLowerFailure(sema, "cannot materialize a static slice of a zero-sized element type");

        const uint64_t byteCount = srcSlice.count * elementSize;
        SWC_ASSERT(byteCount <= std::numeric_limits<uint32_t>::max());
        const auto [dataOffset, dataStorage] = segment.reserveBytes(static_cast<uint32_t>(byteCount), elementType.alignOf(ctx), true);
        for (uint64_t idx = 0; idx < srcSlice.count; ++idx)
        {
            const uint64_t elementOffset = idx * elementSize;
            SWC_RESULT(materializeStaticSubPayload(sema, segment, elementTypeRef, dataOffset, rawBytes(dataStorage, byteCount), rawBytes(srcSlice.ptr, byteCount), elementOffset, elementSize));
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
            if (fieldOffset + fieldSize > srcBytes.size())
                return reportConstantLowerFailure(sema, "cannot materialize a static struct because a field extends past the payload buffer");

            SWC_RESULT(materializeStaticSubPayload(sema, segment, fieldTypeRef, baseOffset, dstBytes, srcBytes, fieldOffset, fieldSize));
        }

        return Result::Continue;
    }

    Result materializeStaticInterface(Sema& sema, DataSegment& segment, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        if (srcBytes.size() != sizeof(Runtime::Interface))
            return reportConstantLowerFailure(sema, "cannot materialize a static interface from an invalid runtime payload size");

        auto&       dstInterface = writable<Runtime::Interface>(dstBytes);
        const auto& srcInterface = readable<Runtime::Interface>(srcBytes);
        uint32_t    objOffset    = INVALID_REF;
        SWC_RESULT(resolveSegmentOffset(objOffset, sema, segment, srcInterface.obj));
        dstInterface.obj = objOffset == INVALID_REF ? nullptr : segment.ptr<std::byte>(objOffset);
        if (objOffset != INVALID_REF)
            segment.addRelocation(baseOffset + offsetof(Runtime::Interface, obj), objOffset);

        uint32_t itableOffset = INVALID_REF;
        SWC_RESULT(resolveSegmentOffset(itableOffset, sema, segment, srcInterface.itable));
        dstInterface.itable = itableOffset == INVALID_REF ? nullptr : segment.ptr<void*>(itableOffset);
        if (itableOffset != INVALID_REF)
            segment.addRelocation(baseOffset + offsetof(Runtime::Interface, itable), itableOffset);
        return Result::Continue;
    }

    Result materializeStaticClosure(Sema& sema, DataSegment& segment, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        if (srcBytes.size() != sizeof(Runtime::ClosureValue))
            return reportConstantLowerFailure(sema, "cannot materialize a static closure from an invalid runtime payload size");

        auto&       dstClosure = writable<Runtime::ClosureValue>(dstBytes);
        const auto& srcClosure = readable<Runtime::ClosureValue>(srcBytes);

        uint32_t invokeOffset = INVALID_REF;
        SWC_RESULT(resolveSegmentOffset(invokeOffset, sema, segment, srcClosure.invoke));
        dstClosure.invoke = invokeOffset == INVALID_REF ? nullptr : segment.ptr<std::byte>(invokeOffset);
        if (invokeOffset != INVALID_REF)
            segment.addRelocation(baseOffset + offsetof(Runtime::ClosureValue, invoke), invokeOffset);

        std::memcpy(dstClosure.capture, srcClosure.capture, sizeof(dstClosure.capture));

        const uint64_t capturedTarget = readable<uint64_t>(rawBytes(srcClosure.capture, sizeof(uint64_t)));
        if (capturedTarget)
        {
            uint32_t targetOffset = INVALID_REF;
            SWC_RESULT(resolveSegmentOffset(targetOffset, sema, segment, pointerFromRawAddress<const void>(capturedTarget)));
            writable<uint64_t>(rawBytes(dstClosure.capture, sizeof(uint64_t))) = targetOffset == INVALID_REF ? 0 : rawAddress(segment.ptr<std::byte>(targetOffset));
            if (targetOffset != INVALID_REF)
                segment.addRelocation(baseOffset + offsetof(Runtime::ClosureValue, capture), targetOffset);
        }

        return Result::Continue;
    }

    Result materializeStaticPointer(Sema& sema, DataSegment& segment, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        if (srcBytes.size() != sizeof(uint64_t))
            return reportConstantLowerFailure(sema, "cannot materialize a static pointer from an invalid runtime payload size");

        auto&      dstPtr    = writable<uint64_t>(dstBytes);
        const auto srcPtr    = pointerFromRawAddress<const void>(readable<uint64_t>(srcBytes));
        uint32_t   ptrOffset = INVALID_REF;
        SWC_RESULT(resolveSegmentOffset(ptrOffset, sema, segment, srcPtr));
        dstPtr = ptrOffset == INVALID_REF ? 0 : rawAddress(segment.ptr<std::byte>(ptrOffset));
        if (ptrOffset != INVALID_REF)
            segment.addRelocation(baseOffset, ptrOffset);
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
            SWC_ASSERT(offset + elemSize <= dstBytes.size());

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
                const auto bytes = cst.getStruct();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(dstBytes.data(), bytes.data(), dstBytes.size());
                return Result::Continue;
            }

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
            {
                const auto bytes = cst.getArray();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(dstBytes.data(), bytes.data(), dstBytes.size());
                return Result::Continue;
            }

            SWC_ASSERT(cst.isAggregateArray());
            return lowerAggregateArrayToBytesInternal(sema, dstBytes, dstType, cst.getAggregateArray());
        }

        if (dstType.isAggregateStruct())
        {
            if (cst.isStruct())
            {
                const auto bytes = cst.getStruct();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(dstBytes.data(), bytes.data(), dstBytes.size());
                return Result::Continue;
            }

            SWC_ASSERT(cst.isAggregateStruct());
            return lowerAggregateTupleToBytesInternal(sema, dstBytes, dstType, cst.getAggregateStruct());
        }

        if (dstType.isAggregateArray())
        {
            if (cst.isStruct())
            {
                const auto bytes = cst.getStruct();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(dstBytes.data(), bytes.data(), dstBytes.size());
                return Result::Continue;
            }

            SWC_ASSERT(cst.isAggregateArray());
            return lowerAggregateTupleToBytesInternal(sema, dstBytes, dstType, cst.getAggregateArray());
        }

        if (dstType.isBool())
        {
            SWC_ASSERT(cst.isBool() && dstBytes.size() == 1);
            const uint8_t v = cst.getBool() ? 1 : 0;
            std::memcpy(dstBytes.data(), &v, sizeof(v));
            return Result::Continue;
        }

        if (dstType.isChar())
        {
            SWC_ASSERT(cst.isChar() && dstBytes.size() == sizeof(char32_t));
            const char32_t v = cst.getChar();
            std::memcpy(dstBytes.data(), &v, sizeof(v));
            return Result::Continue;
        }

        if (dstType.isRune())
        {
            SWC_ASSERT(cst.isRune() && dstBytes.size() == sizeof(char32_t));
            const char32_t v = cst.getRune();
            std::memcpy(dstBytes.data(), &v, sizeof(v));
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
                SWC_ASSERT(dstBytes.size() == sizeof(v));
                std::memcpy(dstBytes.data(), &v, sizeof(v));
                return Result::Continue;
            }

            if (dstType.payloadFloatBits() == 64)
            {
                const double v = cst.getFloat().asDouble();
                SWC_ASSERT(dstBytes.size() == sizeof(v));
                std::memcpy(dstBytes.data(), &v, sizeof(v));
                return Result::Continue;
            }

            SWC_ASSERT(dstType.payloadFloatBits() == 32 || dstType.payloadFloatBits() == 64);
            return Result::Continue;
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
                return Result::Continue;
            }

            Runtime::String rt = {};
            if (cst.isString())
            {
                const std::string_view str = cst.getString();
                rt                         = {.ptr = str.data(), .length = str.size()};
            }
            std::memcpy(dstBytes.data(), &rt, sizeof(rt));
            return Result::Continue;
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
                return Result::Continue;
            }

            Runtime::Slice<uint8_t> rt = {};
            if (cst.isSlice())
            {
                const ByteSpan  bytes       = cst.getSlice();
                const TypeInfo& elementType = sema.typeMgr().get(dstType.payloadTypeRef());
                const uint64_t  elementSize = elementType.sizeOf(sema.ctx());
                rt.count                    = elementSize ? bytes.size() / elementSize : 0;
                rt.ptr                      = rt.count ? reinterpret_cast<uint8_t*>(const_cast<std::byte*>(bytes.data())) : nullptr;
            }
            std::memcpy(dstBytes.data(), &rt, sizeof(rt));
            return Result::Continue;
        }

        if (dstType.isInterface())
        {
            SWC_ASSERT((cst.isNull() || cst.isStruct(dstTypeRef)) && dstBytes.size() == sizeof(Runtime::Interface));
            if (cst.isStruct(dstTypeRef))
            {
                const auto bytes = cst.getStruct();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(dstBytes.data(), bytes.data(), dstBytes.size());
                return Result::Continue;
            }

            constexpr Runtime::Interface rt = {};
            std::memcpy(dstBytes.data(), &rt, sizeof(rt));
            return Result::Continue;
        }

        if (dstType.isAny())
        {
            SWC_ASSERT(dstBytes.size() == sizeof(Runtime::Any));
            if (cst.isNull())
            {
                if (!dstBytes.empty())
                    std::memset(dstBytes.data(), 0, dstBytes.size());
                return Result::Continue;
            }

            if (cst.isStruct())
            {
                const auto bytes = cst.getStruct();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(dstBytes.data(), bytes.data(), dstBytes.size());
                return Result::Continue;
            }

            Runtime::Any anyValue{};

            const TypeRef valueTypeRef = cst.typeRef();
            SWC_ASSERT(valueTypeRef.isValid());
            SWC_ASSERT(valueTypeRef != dstTypeRef);

            ConstantRef typeInfoCstRef = ConstantRef::invalid();
            SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, typeInfoCstRef, valueTypeRef, sema.ctx().state().nodeRef));
            SWC_ASSERT(typeInfoCstRef.isValid());
            const ConstantValue& typeInfoCst = sema.cstMgr().get(typeInfoCstRef);
            SWC_ASSERT(typeInfoCst.isValuePointer());
            anyValue.type = pointerFromRawAddress<const Runtime::TypeInfo>(typeInfoCst.getValuePointer());

            const uint64_t valueSize = sema.typeMgr().get(valueTypeRef).sizeOf(sema.ctx());
            if (valueSize)
            {
                std::vector valueBytes(valueSize, std::byte{0});
                SWC_RESULT(lowerConstantToBytes(sema, asByteSpan(valueBytes), valueTypeRef, cstRef));

                const std::string_view rawValueData = sema.cstMgr().addPayloadBuffer(asStringView(asByteSpan(valueBytes)));
                anyValue.value                      = const_cast<char*>(rawValueData.data());
            }

            std::memcpy(dstBytes.data(), &anyValue, sizeof(anyValue));
            return Result::Continue;
        }

        if (dstType.isFunction() && dstType.isLambdaClosure())
        {
            SWC_ASSERT(dstBytes.size() == sizeof(Runtime::ClosureValue));
            if (cst.isNull())
            {
                if (!dstBytes.empty())
                    std::memset(dstBytes.data(), 0, dstBytes.size());
                return Result::Continue;
            }

            if (cst.isStruct())
            {
                const auto bytes = cst.getStruct();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(dstBytes.data(), bytes.data(), dstBytes.size());
                return Result::Continue;
            }

            SWC_ASSERT(cst.isNull() || cst.isStruct());
            return Result::Continue;
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
            else if (dstType.isReference())
            {
                const TypeRef pointeeTypeRef = dstType.payloadTypeRef();
                if (pointeeTypeRef.isValid())
                {
                    const uint64_t valueSize = sema.typeMgr().get(pointeeTypeRef).sizeOf(sema.ctx());
                    if (valueSize)
                    {
                        std::vector valueBytes(valueSize, std::byte{0});
                        SWC_RESULT(lowerConstantToBytes(sema, asByteSpan(valueBytes), pointeeTypeRef, cstRef));

                        const std::string_view rawValueData = sema.cstMgr().addPayloadBuffer(asStringView(asByteSpan(valueBytes)));
                        ptr                                 = rawAddress(rawValueData.data());
                    }
                }
            }
            SWC_ASSERT(cst.isNull() || cst.isValuePointer() || cst.isBlockPointer() || (dstType.isReference() && ptr != 0) || (dstType.isReference() && sema.typeMgr().get(dstType.payloadTypeRef()).sizeOf(sema.ctx()) == 0));
            std::memcpy(dstBytes.data(), &ptr, sizeof(ptr));
            return Result::Continue;
        }

        SWC_ASSERT(dstType.isEnum() || dstType.isStruct() || dstType.isArray() || dstType.isBool() || dstType.isChar() ||
                   dstType.isRune() || dstType.isInt() || dstType.isFloat() || dstType.isString() || dstType.isSlice() ||
                   dstType.isAny() || dstType.isAnyPointer() || dstType.isReference() || dstType.isTypeInfo() || dstType.isCString() || dstType.isFunction());
        return Result::Continue;
    }

    Result materializeStaticPayloadInPlace(Sema& sema, DataSegment& segment, TypeRef typeRef, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        if (typeRef.isInvalid())
            return reportConstantLowerFailure(sema, "cannot materialize static data for an invalid type");

        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (typeInfo.isAlias())
        {
            const TypeRef unwrappedTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
            if (unwrappedTypeRef.isInvalid())
                return reportConstantLowerFailure(sema, "cannot materialize static data for an alias with no storage type");
            return materializeStaticPayloadInPlace(sema, segment, unwrappedTypeRef, baseOffset, dstBytes, srcBytes);
        }

        const uint64_t sizeOf = typeInfo.sizeOf(ctx);
        if (sizeOf != dstBytes.size() || sizeOf != srcBytes.size())
            return reportConstantLowerFailure(sema, "cannot materialize static data because the payload size does not match the target storage size");

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
            {
                TaskContext& semaCtx = sema.ctx();
                uint64_t     offset  = 0;

                for (const TypeRef elemTypeRef : typeInfo.payloadAggregate().types)
                {
                    const TypeInfo& elemType = sema.typeMgr().get(elemTypeRef);
                    uint32_t        align    = elemType.alignOf(semaCtx);
                    const uint64_t  elemSize = elemType.sizeOf(semaCtx);
                    if (!align)
                        align = 1;

                    if (!elemSize)
                        continue;

                    offset = Math::alignUpU64(offset, align);
                    if (offset + elemSize > dstBytes.size())
                        return reportConstantLowerFailure(sema, "cannot materialize aggregate static data because an element extends past the payload buffer");

                    SWC_RESULT(materializeStaticSubPayload(sema, segment, elemTypeRef, baseOffset, dstBytes, srcBytes, offset, elemSize));
                    offset += elemSize;
                }

                return Result::Continue;
            }

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

        return reportConstantLowerFailure(sema, "cannot materialize static data for an unsupported runtime type");
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
            SWC_RESULT(lowerConstantToBytes(sema, subBytes(dstBytes, fieldOffset, fieldSize), fieldTypeRef, valueRef));
        else if (fieldSize)
            std::memset(dstBytes.data() + fieldOffset, 0, fieldSize);
    }

    return Result::Continue;
}

Result ConstantLower::materializeStaticPayload(uint32_t& outOffset, Sema& sema, DataSegment& segment, TypeRef typeRef, const ByteSpan srcBytes)
{
    outOffset = INVALID_REF;
    if (typeRef.isInvalid())
        return reportConstantLowerFailure(sema, "cannot allocate static payload storage for an invalid type");

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
