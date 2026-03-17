#include "pch.h"
#include "Backend/Native/NativeValidate.h"

#if SWC_HAS_NATIVE_VALIDATION

#include "Backend/Runtime.h"
#include "Compiler/Sema/Type/TypeGen.h"

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
                SWC_ASSERT(builder_.functionBySymbol.contains(const_cast<SymbolFunction*>(target)));
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
                SWC_ASSERT(validateConstantRelocation(relocation));
                break;
        }
    }
}

bool NativeValidate::validateConstantRelocation(const MicroRelocation& relocation) const
{
    if (!relocation.constantRef.isValid())
        return false;

    const ConstantValue& constant = builder_.compiler().cstMgr().get(relocation.constantRef);
    if (constant.kind() == ConstantKind::ValuePointer || constant.kind() == ConstantKind::BlockPointer || constant.kind() == ConstantKind::Null)
        return true;

    uint32_t  shardIndex = 0;
    const Ref baseOffset = builder_.compiler().cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(relocation.targetAddress));
    if (baseOffset == INVALID_REF)
        return false;

    if (constant.kind() == ConstantKind::Struct)
    {
        const ByteSpan payload = constant.getStruct();
        if (relocation.targetAddress != reinterpret_cast<uint64_t>(payload.data()))
            return false;
        return validateNativeStaticPayload(constant.typeRef(), shardIndex, baseOffset, payload);
    }

    if (constant.kind() == ConstantKind::Array)
    {
        const ByteSpan payload = constant.getArray();
        if (relocation.targetAddress != reinterpret_cast<uint64_t>(payload.data()))
            return false;
        return validateNativeStaticPayload(constant.typeRef(), shardIndex, baseOffset, payload);
    }
    if (constant.typeRef().isInvalid())
        return false;

    const DataSegment& segment = builder_.compiler().cstMgr().shardDataSegment(shardIndex);
    const uint64_t     sizeOf  = builder_.ctx().typeMgr().get(constant.typeRef()).sizeOf(builder_.ctx());
    if (!sizeOf || baseOffset + sizeOf > segment.extentSize())
        return false;

    const auto* payloadBytes = segment.ptr<std::byte>(baseOffset);
    if (!payloadBytes)
        return false;

    return validateNativeStaticPayload(constant.typeRef(), shardIndex, baseOffset, ByteSpan{payloadBytes, static_cast<size_t>(sizeOf)});
}

bool NativeValidate::validateNativeStaticPayload(const TypeRef typeRef, const uint32_t shardIndex, const Ref baseOffset, const ByteSpan bytes) const
{
    if (typeRef.isInvalid())
        return false;

    const DataSegment& segment  = builder_.compiler().cstMgr().shardDataSegment(shardIndex);
    const TypeInfo&    typeInfo = builder_.ctx().typeMgr().get(typeRef);
    if (typeInfo.isAlias())
    {
        const TypeRef unwrapped = typeInfo.unwrap(builder_.ctx(), typeRef, TypeExpandE::Alias);
        return unwrapped.isValid() && validateNativeStaticPayload(unwrapped, shardIndex, baseOffset, bytes);
    }

    if (typeInfo.isEnum())
        return validateNativeStaticPayload(typeInfo.payloadSymEnum().underlyingTypeRef(), shardIndex, baseOffset, bytes);

    if (typeInfo.isBool() || typeInfo.isChar() || typeInfo.isRune() || typeInfo.isInt() || typeInfo.isFloat())
        return true;

    if (typeInfo.isInterface())
        return isZeroFilled(bytes);

    if (typeInfo.isAny())
    {
        if (bytes.size() != sizeof(Runtime::Any))
            return false;

        const auto* value = reinterpret_cast<const Runtime::Any*>(bytes.data());
        if (!value->type)
            return value->value == nullptr;

        uint32_t typeInfoOffset = 0;
        if (!findDataSegmentRelocation(typeInfoOffset, shardIndex, baseOffset + offsetof(Runtime::Any, type)))
            return false;
        if (typeInfoOffset >= segment.extentSize())
            return false;

        const auto* runtimeType = segment.ptr<Runtime::TypeInfo>(typeInfoOffset);
        if (!runtimeType)
            return false;

        const TypeRef valueTypeRef = builder_.ctx().typeGen().getBackTypeRef(runtimeType);
        if (valueTypeRef.isInvalid())
            return false;

        if (!value->value)
            return true;

        uint32_t valueOffset = 0;
        if (!findDataSegmentRelocation(valueOffset, shardIndex, baseOffset + offsetof(Runtime::Any, value)))
            return false;
        if (valueOffset >= segment.extentSize())
            return false;

        const uint64_t valueSize = builder_.ctx().typeMgr().get(valueTypeRef).sizeOf(builder_.ctx());
        if (!valueSize || valueOffset + valueSize > segment.extentSize())
            return false;

        const auto* payloadBytes = segment.ptr<std::byte>(valueOffset);
        if (!payloadBytes)
            return false;

        return validateNativeStaticPayload(valueTypeRef, shardIndex, valueOffset, ByteSpan{payloadBytes, static_cast<size_t>(valueSize)});
    }

    if (typeInfo.isString())
    {
        if (bytes.size() != sizeof(Runtime::String))
            return false;

        const auto* value = reinterpret_cast<const Runtime::String*>(bytes.data());
        if (!value->ptr)
            return value->length == 0;

        uint32_t targetOffset = 0;
        return findDataSegmentRelocation(targetOffset, shardIndex, baseOffset + offsetof(Runtime::String, ptr)) && targetOffset < segment.extentSize();
    }

    if (typeInfo.isSlice())
    {
        if (bytes.size() != sizeof(Runtime::Slice<uint8_t>))
            return false;

        const auto* slice = reinterpret_cast<const Runtime::Slice<uint8_t>*>(bytes.data());
        if (!slice->ptr)
            return slice->count == 0;

        const TypeRef   elementTypeRef = typeInfo.payloadTypeRef();
        const TypeInfo& elementType    = builder_.ctx().typeMgr().get(elementTypeRef);
        const uint64_t  elementSize    = elementType.sizeOf(builder_.ctx());
        if (!elementSize)
            return false;

        uint32_t targetOffset = 0;
        if (!findDataSegmentRelocation(targetOffset, shardIndex, baseOffset + offsetof(Runtime::Slice<uint8_t>, ptr)))
            return false;

        const uint64_t byteCount = slice->count * elementSize;
        if (targetOffset + byteCount > segment.extentSize())
            return false;

        if (elementType.isBool() || elementType.isChar() || elementType.isRune() || elementType.isInt() || elementType.isFloat())
            return true;

        const auto* segmentBytes = segment.ptr<std::byte>(targetOffset);
        if (!segmentBytes)
            return false;

        for (uint64_t offset = 0; offset < byteCount; offset += elementSize)
        {
            const auto elementBytes = ByteSpan{segmentBytes + offset, static_cast<size_t>(elementSize)};
            if (!validateNativeStaticPayload(elementTypeRef, shardIndex, targetOffset + static_cast<uint32_t>(offset), elementBytes))
                return false;
        }

        return true;
    }

    if (typeInfo.isArray())
    {
        const TypeRef   elementTypeRef = typeInfo.payloadArrayElemTypeRef();
        const TypeInfo& elementType    = builder_.ctx().typeMgr().get(elementTypeRef);
        const uint64_t  elementSize    = elementType.sizeOf(builder_.ctx());
        if (!elementSize)
            return false;

        uint64_t totalCount = 1;
        for (const uint64_t dim : typeInfo.payloadArrayDims())
            totalCount *= dim;

        for (uint64_t idx = 0; idx < totalCount; ++idx)
        {
            const uint64_t elementOffset = idx * elementSize;
            const auto     elementBytes  = ByteSpan{bytes.data() + elementOffset, static_cast<size_t>(elementSize)};
            if (!validateNativeStaticPayload(elementTypeRef, shardIndex, baseOffset + static_cast<uint32_t>(elementOffset), elementBytes))
                return false;
        }

        return true;
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
            if (fieldOffset + fieldSize > bytes.size())
                return false;

            const auto fieldBytes = ByteSpan{bytes.data() + fieldOffset, static_cast<size_t>(fieldSize)};
            if (!validateNativeStaticPayload(fieldTypeRef, shardIndex, baseOffset + static_cast<uint32_t>(fieldOffset), fieldBytes))
                return false;
        }

        return true;
    }

    if (typeInfo.isPointerLike() || typeInfo.isReference() || typeInfo.isTypeInfo() || typeInfo.isCString() || typeInfo.isFunction())
    {
        if (bytes.size() != sizeof(uint64_t))
            return false;

        const uint64_t ptr = *reinterpret_cast<const uint64_t*>(bytes.data());
        if (!ptr)
            return true;

        uint32_t targetOffset = 0;
        return findDataSegmentRelocation(targetOffset, shardIndex, baseOffset) && targetOffset < segment.extentSize();
    }

    return false;
}

bool NativeValidate::findDataSegmentRelocation(uint32_t& outTargetOffset, const uint32_t shardIndex, const uint32_t offset) const
{
    outTargetOffset         = 0;
    const auto& relocations = builder_.compiler().cstMgr().shardDataSegment(shardIndex).relocations();
    for (const auto& relocation : relocations)
    {
        if (relocation.offset != offset)
            continue;

        outTargetOffset = relocation.targetOffset;
        return true;
    }

    return false;
}

SWC_END_NAMESPACE();

#endif
