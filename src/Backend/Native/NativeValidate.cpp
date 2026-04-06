#include "pch.h"
#include "Backend/Native/NativeValidate.h"

#if SWC_HAS_NATIVE_VALIDATION

#include "Backend/Runtime.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isZeroFilled(const ByteSpan bytes)
    {
        for (const auto byte : bytes)
        {
            if (byte != std::byte{0})
                return false;
        }

        return true;
    }

    void validateFunctionSymbolRelocation(const NativeBackendBuilder& builder, const SymbolFunction* target)
    {
        SWC_ASSERT(target != nullptr);
        if (target->isForeign())
            return;

        SWC_ASSERT(builder.functionBySymbol.contains(target));
    }
}

NativeValidate::NativeValidate(NativeBackendBuilder& builder) :
    builder_(builder)
{
}

void NativeValidate::validate() const
{
    const auto& compiler = builder_.compiler();

    SWC_ASSERT(compiler.globalZeroSegment().relocations().empty());

    for (const SymbolVariable* symbol : builder_.regularGlobals)
    {
        if (!symbol)
            continue;

        SWC_ASSERT(symbol->globalStorageKind() != DataSegmentKind::Compiler);
        if (symbol->globalStorageKind() != DataSegmentKind::GlobalInit)
            continue;

        if (symbol->hasExtraFlag(SymbolVariableFlagsE::ExplicitUndefined))
            continue;

        if (!symbol->cstRef().isValid())
            continue;

        SWC_ASSERT(isNativeStaticType(symbol->typeRef()));
    }

    for (const auto& info : builder_.functionInfos)
    {
        SWC_ASSERT(info.symbol != nullptr);
        SWC_ASSERT(info.machineCode != nullptr);
        validateRelocations(*info.symbol, *info.machineCode);
    }
}

bool NativeValidate::isNativeStaticType(const TypeRef typeRef) const
{
    if (typeRef.isInvalid())
        return false;

    const TypeInfo& typeInfo = builder_.ctx().typeMgr().get(typeRef);
    if (typeInfo.isAlias())
    {
        const TypeRef unwrapped = typeInfo.unwrap(builder_.ctx(), typeRef, TypeExpandE::Alias);
        return unwrapped.isValid() && isNativeStaticType(unwrapped);
    }

    if (typeInfo.isEnum())
        return isNativeStaticType(typeInfo.payloadSymEnum().underlyingTypeRef());

    if (typeInfo.isBool() || typeInfo.isChar() || typeInfo.isRune() || typeInfo.isInt() || typeInfo.isFloat() || typeInfo.isString())
        return true;

    if (typeInfo.isArray())
        return isNativeStaticType(typeInfo.payloadArrayElemTypeRef());

    if (typeInfo.isAggregate())
    {
        for (const TypeRef child : typeInfo.payloadAggregate().types)
        {
            if (!isNativeStaticType(child))
                return false;
        }

        return true;
    }

    if (typeInfo.isStruct())
    {
        for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
        {
            if (field && !isNativeStaticType(field->typeRef()))
                return false;
        }

        return true;
    }

    if (typeInfo.isFunction() && typeInfo.isLambdaClosure())
        return true;

    if (typeInfo.isPointerLike() || typeInfo.isReference() || typeInfo.isVariadic() || typeInfo.isTypedVariadic())
        return false;

    return false;
}

void NativeValidate::validateRelocations(const SymbolFunction& owner, const MachineCode& code) const
{
    SWC_UNUSED(owner);

    for (const auto& relocation : code.codeRelocations)
    {
        switch (relocation.kind)
        {
            case MicroRelocation::Kind::CompilerAddress:
                SWC_ASSERT(false);
                break;

            case MicroRelocation::Kind::LocalFunctionAddress:
            {
                const auto* target = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
                SWC_ASSERT(target != nullptr);
                SWC_ASSERT(builder_.functionBySymbol.contains(target));
                break;
            }

            case MicroRelocation::Kind::ForeignFunctionAddress:
            {
                const auto* target = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
                SWC_ASSERT(target != nullptr);
                SWC_ASSERT(target->isForeign());
                break;
            }

            case MicroRelocation::Kind::GlobalZeroAddress:
                SWC_ASSERT(builder_.compiler().globalZeroSegment().extentSize() != 0);
                break;

            case MicroRelocation::Kind::GlobalInitAddress:
                SWC_ASSERT(builder_.compiler().globalInitSegment().extentSize() != 0);
                break;

            case MicroRelocation::Kind::ConstantAddress:
                validateConstantRelocation(relocation);
                break;
        }
    }
}

void NativeValidate::validateConstantRelocation(const MicroRelocation& relocation) const
{
    SWC_ASSERT(relocation.constantRef.isValid());

    const ConstantValue& constant = builder_.compiler().cstMgr().get(relocation.constantRef);
    if (constant.kind() == ConstantKind::ValuePointer || constant.kind() == ConstantKind::BlockPointer || constant.kind() == ConstantKind::Null)
        return;

    uint32_t  shardIndex = 0;
    const Ref baseOffset = builder_.compiler().cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(relocation.targetAddress));
    SWC_ASSERT(baseOffset != INVALID_REF);

    const DataSegment& segment = builder_.compiler().cstMgr().shardDataSegment(shardIndex);

    if (constant.kind() == ConstantKind::Struct)
    {
        const ByteSpan payload           = constant.getStruct();
        uint32_t       payloadShardIndex = 0;
        const Ref      payloadOffset     = builder_.compiler().cstMgr().findDataSegmentRef(payloadShardIndex, payload.data());
        SWC_ASSERT(payloadOffset != INVALID_REF);
        SWC_ASSERT(payloadShardIndex == shardIndex);

        DataSegmentAllocation allocation;
        SWC_ASSERT(segment.findAllocation(allocation, baseOffset));
        SWC_ASSERT(allocation.offset == payloadOffset);
        SWC_ASSERT(allocation.size >= payload.size());

        validateNativeStaticPayload(constant.typeRef(), shardIndex, payloadOffset, payload);
        return;
    }

    if (constant.kind() == ConstantKind::Array)
    {
        const ByteSpan payload           = constant.getArray();
        uint32_t       payloadShardIndex = 0;
        const Ref      payloadOffset     = builder_.compiler().cstMgr().findDataSegmentRef(payloadShardIndex, payload.data());
        SWC_ASSERT(payloadOffset != INVALID_REF);
        SWC_ASSERT(payloadShardIndex == shardIndex);

        DataSegmentAllocation allocation;
        SWC_ASSERT(segment.findAllocation(allocation, baseOffset));
        SWC_ASSERT(allocation.offset == payloadOffset);
        SWC_ASSERT(allocation.size >= payload.size());

        validateNativeStaticPayload(constant.typeRef(), shardIndex, payloadOffset, payload);
        return;
    }

    SWC_ASSERT(constant.typeRef().isValid());

    const uint64_t sizeOf = builder_.ctx().typeMgr().get(constant.typeRef()).sizeOf(builder_.ctx());
    SWC_ASSERT(sizeOf != 0);
    SWC_ASSERT(baseOffset + sizeOf <= segment.extentSize());

    const auto* payloadBytes = segment.ptr<std::byte>(baseOffset);
    SWC_ASSERT(payloadBytes != nullptr);

    validateNativeStaticPayload(constant.typeRef(), shardIndex, baseOffset, ByteSpan{payloadBytes, static_cast<size_t>(sizeOf)});
}

void NativeValidate::validateNativeStaticPayload(const TypeRef typeRef, const uint32_t shardIndex, const Ref baseOffset, const ByteSpan bytes) const
{
    SWC_ASSERT(typeRef.isValid());

    const DataSegment& segment  = builder_.compiler().cstMgr().shardDataSegment(shardIndex);
    const TypeInfo&    typeInfo = builder_.ctx().typeMgr().get(typeRef);
    if (typeInfo.isAlias())
    {
        const TypeRef unwrapped = typeInfo.unwrap(builder_.ctx(), typeRef, TypeExpandE::Alias);
        SWC_ASSERT(unwrapped.isValid());
        validateNativeStaticPayload(unwrapped, shardIndex, baseOffset, bytes);
        return;
    }

    if (typeInfo.isEnum())
    {
        validateNativeStaticPayload(typeInfo.payloadSymEnum().underlyingTypeRef(), shardIndex, baseOffset, bytes);
        return;
    }

    if (typeInfo.isBool() || typeInfo.isChar() || typeInfo.isRune() || typeInfo.isInt() || typeInfo.isFloat())
        return;

    if (typeInfo.isInterface())
    {
        SWC_ASSERT(isZeroFilled(bytes));
        return;
    }

    if (typeInfo.isAny())
    {
        SWC_ASSERT(bytes.size() == sizeof(Runtime::Any));

        const auto* value = reinterpret_cast<const Runtime::Any*>(bytes.data());
        if (!value->type)
        {
            SWC_ASSERT(value->value == nullptr);
            return;
        }

        uint32_t typeInfoOffset = 0;
        SWC_ASSERT(findDataSegmentRelocation(typeInfoOffset, shardIndex, baseOffset + offsetof(Runtime::Any, type)));
        SWC_ASSERT(typeInfoOffset < segment.extentSize());

        const auto* runtimeType = segment.ptr<Runtime::TypeInfo>(typeInfoOffset);
        SWC_ASSERT(runtimeType != nullptr);

        const TypeRef valueTypeRef = builder_.ctx().typeGen().getBackTypeRef(runtimeType);
        SWC_ASSERT(valueTypeRef.isValid());

        if (!value->value)
            return;

        uint32_t valueOffset = 0;
        SWC_ASSERT(findDataSegmentRelocation(valueOffset, shardIndex, baseOffset + offsetof(Runtime::Any, value)));
        SWC_ASSERT(valueOffset < segment.extentSize());

        const uint64_t valueSize = builder_.ctx().typeMgr().get(valueTypeRef).sizeOf(builder_.ctx());
        SWC_ASSERT(valueSize != 0);
        SWC_ASSERT(valueOffset + valueSize <= segment.extentSize());

        const auto* payloadBytes = segment.ptr<std::byte>(valueOffset);
        SWC_ASSERT(payloadBytes != nullptr);

        validateNativeStaticPayload(valueTypeRef, shardIndex, valueOffset, ByteSpan{payloadBytes, static_cast<size_t>(valueSize)});
        return;
    }

    if (typeInfo.isString())
    {
        SWC_ASSERT(bytes.size() == sizeof(Runtime::String));

        const auto* value = reinterpret_cast<const Runtime::String*>(bytes.data());
        if (!value->ptr)
        {
            SWC_ASSERT(value->length == 0);
            return;
        }

        uint32_t targetOffset = 0;
        SWC_ASSERT(findDataSegmentRelocation(targetOffset, shardIndex, baseOffset + offsetof(Runtime::String, ptr)));
        SWC_ASSERT(targetOffset < segment.extentSize());
        return;
    }

    if (typeInfo.isSlice())
    {
        SWC_ASSERT(bytes.size() == sizeof(Runtime::Slice<uint8_t>));

        const auto* slice = reinterpret_cast<const Runtime::Slice<uint8_t>*>(bytes.data());
        if (!slice->ptr)
        {
            SWC_ASSERT(slice->count == 0);
            return;
        }

        const TypeRef   elementTypeRef = typeInfo.payloadTypeRef();
        const TypeInfo& elementType    = builder_.ctx().typeMgr().get(elementTypeRef);
        const uint64_t  elementSize    = elementType.sizeOf(builder_.ctx());
        SWC_ASSERT(elementSize != 0);

        uint32_t targetOffset = 0;
        SWC_ASSERT(findDataSegmentRelocation(targetOffset, shardIndex, baseOffset + offsetof(Runtime::Slice<uint8_t>, ptr)));

        const uint64_t byteCount = slice->count * elementSize;
        SWC_ASSERT(targetOffset + byteCount <= segment.extentSize());

        if (elementType.isBool() || elementType.isChar() || elementType.isRune() || elementType.isInt() || elementType.isFloat())
            return;

        const auto* segmentBytes = segment.ptr<std::byte>(targetOffset);
        SWC_ASSERT(segmentBytes != nullptr);

        for (uint64_t offset = 0; offset < byteCount; offset += elementSize)
        {
            const auto elementBytes = ByteSpan{segmentBytes + offset, static_cast<size_t>(elementSize)};
            validateNativeStaticPayload(elementTypeRef, shardIndex, targetOffset + static_cast<uint32_t>(offset), elementBytes);
        }

        return;
    }

    if (typeInfo.isArray())
    {
        const TypeRef   elementTypeRef = typeInfo.payloadArrayElemTypeRef();
        const TypeInfo& elementType    = builder_.ctx().typeMgr().get(elementTypeRef);
        const uint64_t  elementSize    = elementType.sizeOf(builder_.ctx());
        SWC_ASSERT(elementSize != 0);

        uint64_t totalCount = 1;
        for (const uint64_t dim : typeInfo.payloadArrayDims())
            totalCount *= dim;

        for (uint64_t idx = 0; idx < totalCount; ++idx)
        {
            const uint64_t elementOffset = idx * elementSize;
            SWC_ASSERT(elementOffset + elementSize <= bytes.size());
            const auto     elementBytes  = ByteSpan{bytes.data() + elementOffset, static_cast<size_t>(elementSize)};
            validateNativeStaticPayload(elementTypeRef, shardIndex, baseOffset + static_cast<uint32_t>(elementOffset), elementBytes);
        }

        return;
    }

    if (typeInfo.isStruct())
    {
        for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
        {
            if (!field)
                continue;

            const TypeRef   fieldTypeRef = field->typeRef();
            const TypeInfo& fieldType    = builder_.ctx().typeMgr().get(fieldTypeRef);
            const uint64_t  fieldSize    = fieldType.sizeOf(builder_.ctx());
            const uint64_t  fieldOffset  = field->offset();
            SWC_ASSERT(fieldOffset + fieldSize <= bytes.size());

            const auto fieldBytes = ByteSpan{bytes.data() + fieldOffset, static_cast<size_t>(fieldSize)};
            validateNativeStaticPayload(fieldTypeRef, shardIndex, baseOffset + static_cast<uint32_t>(fieldOffset), fieldBytes);
        }

        return;
    }

    if (typeInfo.isAggregateStruct() || typeInfo.isAggregateArray())
    {
        uint64_t offset = 0;
        for (const TypeRef fieldTypeRef : typeInfo.payloadAggregate().types)
        {
            const TypeInfo& fieldType = builder_.ctx().typeMgr().get(fieldTypeRef);
            uint32_t        align     = fieldType.alignOf(builder_.ctx());
            const uint64_t  fieldSize = fieldType.sizeOf(builder_.ctx());
            if (!align)
                align = 1;

            if (!fieldSize)
                continue;

            offset = Math::alignUpU64(offset, align);
            SWC_ASSERT(offset + fieldSize <= bytes.size());

            const auto fieldBytes = ByteSpan{bytes.data() + offset, static_cast<size_t>(fieldSize)};
            validateNativeStaticPayload(fieldTypeRef, shardIndex, baseOffset + static_cast<uint32_t>(offset), fieldBytes);

            offset += fieldSize;
        }

        return;
    }

    if (typeInfo.isFunction() && typeInfo.isLambdaClosure())
    {
        SWC_ASSERT(bytes.size() == sizeof(Runtime::ClosureValue));

        const auto* value = reinterpret_cast<const Runtime::ClosureValue*>(bytes.data());
        if (!value->invoke)
        {
            SWC_ASSERT(isZeroFilled(bytes));
            return;
        }

        uint32_t invokeOffset = 0;
        SWC_ASSERT(findDataSegmentRelocation(invokeOffset, shardIndex, baseOffset + offsetof(Runtime::ClosureValue, invoke)));
        SWC_ASSERT(invokeOffset < segment.extentSize());

        const auto capturedPtr = *reinterpret_cast<const uint64_t*>(value->capture);
        if (!capturedPtr)
            return;

        uint32_t captureOffset = 0;
        SWC_ASSERT(findDataSegmentRelocation(captureOffset, shardIndex, baseOffset + offsetof(Runtime::ClosureValue, capture)));
        SWC_ASSERT(captureOffset < segment.extentSize());
        return;
    }

    if (typeInfo.isPointerLike() || typeInfo.isReference() || typeInfo.isTypeInfo() || typeInfo.isCString() || typeInfo.isFunction())
    {
        SWC_ASSERT(bytes.size() == sizeof(uint64_t));

        const uint64_t ptr = *reinterpret_cast<const uint64_t*>(bytes.data());
        if (!ptr)
            return;

        uint32_t targetOffset = 0;
        if (findDataSegmentRelocation(targetOffset, shardIndex, baseOffset))
        {
            SWC_ASSERT(targetOffset < segment.extentSize());
            return;
        }

        const SymbolFunction* targetFunction = nullptr;
        SWC_ASSERT(findFunctionSymbolRelocation(targetFunction, shardIndex, baseOffset));
        validateFunctionSymbolRelocation(builder_, targetFunction);
        return;
    }

    SWC_ASSERT(false);
}

bool NativeValidate::findDataSegmentRelocation(uint32_t& outTargetOffset, const uint32_t shardIndex, const uint32_t offset) const
{
    outTargetOffset         = 0;
    const auto& relocations = builder_.compiler().cstMgr().shardDataSegment(shardIndex).relocations();
    for (const auto& relocation : relocations)
    {
        if (relocation.offset != offset)
            continue;
        if (relocation.kind != DataSegmentRelocationKind::DataSegmentOffset)
            continue;

        outTargetOffset = relocation.targetOffset;
        return true;
    }

    return false;
}

bool NativeValidate::findFunctionSymbolRelocation(const SymbolFunction*& outTargetSymbol, const uint32_t shardIndex, const uint32_t offset) const
{
    outTargetSymbol         = nullptr;
    const auto& relocations = builder_.compiler().cstMgr().shardDataSegment(shardIndex).relocations();
    for (const auto& relocation : relocations)
    {
        if (relocation.offset != offset)
            continue;
        if (relocation.kind != DataSegmentRelocationKind::FunctionSymbol)
            continue;

        outTargetSymbol = relocation.targetSymbol;
        return true;
    }

    return false;
}

SWC_END_NAMESPACE();

#endif
