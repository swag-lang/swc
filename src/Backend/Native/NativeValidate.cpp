#include "pch.h"
#include "Backend/Native/NativeValidate.h"

#if SWC_HAS_VALIDATE_NATIVE

#include "Backend/Runtime.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

NativeValidate::NativeValidate(NativeBackendBuilder& builder) :
    builder_(&builder)
{
}

void NativeValidate::validate() const
{
    SWC_ASSERT(builder_ != nullptr);
    const auto& compiler = builder_->compiler();

    SWC_ASSERT(compiler.globalZeroSegment().copyRelocations().empty());

    for (const SymbolVariable* symbol : builder_->regularGlobals)
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

    for (const auto& info : builder_->functionInfos)
    {
        SWC_ASSERT(info.machineCode != nullptr);
        validateRelocations(*info.machineCode);
    }
}

bool NativeValidate::isNativeStaticType(const TypeRef typeRef) const
{
    if (typeRef.isInvalid())
        return false;

    SWC_ASSERT(builder_ != nullptr);
    const TypeInfo& typeInfo = builder_->ctx().typeMgr().get(typeRef);
    if (typeInfo.isAlias())
    {
        const TypeRef unwrapped = typeInfo.unwrap(builder_->ctx(), typeRef, TypeExpandE::Alias);
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

void NativeValidate::validateRelocations(const MachineCode& code) const
{
    for (const auto& relocation : code.codeRelocations)
    {
        switch (relocation.kind)
        {
            case MicroRelocation::Kind::CompilerAddress:
                SWC_UNREACHABLE();

            case MicroRelocation::Kind::LocalFunctionAddress:
            {
                const auto* target = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
                SWC_ASSERT(target != nullptr);
                SWC_ASSERT(builder_->tryFindFunctionInfo(*target) != nullptr);
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
                SWC_ASSERT(builder_->compiler().globalZeroSegment().extentSize() != 0);
                break;

            case MicroRelocation::Kind::GlobalInitAddress:
                SWC_ASSERT(builder_->compiler().globalInitSegment().extentSize() != 0);
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

    SWC_ASSERT(builder_ != nullptr);
    const ConstantValue& constant = builder_->compiler().cstMgr().get(relocation.constantRef);
    if (constant.kind() == ConstantKind::ValuePointer || constant.kind() == ConstantKind::BlockPointer || constant.kind() == ConstantKind::Null)
        return;

    uint32_t shardIndex = relocation.constantShard;
    Ref      baseOffset = relocation.constantOffset;
    if (!relocation.hasConstantSource())
    {
        DataSegmentRef sourceRef;
        const bool     hasSourceRef = builder_->tryResolveConstantSourceRef(sourceRef, relocation);
        SWC_ASSERT(hasSourceRef);
        if (!hasSourceRef)
            return;
        shardIndex = sourceRef.shardIndex;
        baseOffset = sourceRef.offset;
    }
    SWC_ASSERT(baseOffset != INVALID_REF);
    SWC_ASSERT(shardIndex < ConstantManager::SHARD_COUNT);

    const DataSegment& segment = builder_->compiler().cstMgr().shardDataSegment(shardIndex);

    if (constant.kind() == ConstantKind::Struct)
    {
        const ByteSpan payload = constant.getStruct();
        DataSegmentRef payloadRef;
        const bool     hasPayloadRef = builder_->compiler().cstMgr().resolveConstantDataSegmentRef(payloadRef, relocation.constantRef, payload.data());
        SWC_ASSERT(hasPayloadRef);
        SWC_ASSERT(payloadRef.shardIndex == shardIndex);
        if (!hasPayloadRef)
            return;

        DataSegmentAllocation allocation;
        SWC_ASSERT(segment.findAllocation(allocation, baseOffset));
        SWC_ASSERT(allocation.offset == payloadRef.offset);
        SWC_ASSERT(allocation.size >= payload.size());

        validateNativeStaticPayload(constant.typeRef(), shardIndex, payloadRef.offset, payload);
        return;
    }

    if (constant.kind() == ConstantKind::Array)
    {
        const ByteSpan payload = constant.getArray();
        DataSegmentRef payloadRef;
        const bool     hasPayloadRef = builder_->compiler().cstMgr().resolveConstantDataSegmentRef(payloadRef, relocation.constantRef, payload.data());
        SWC_ASSERT(hasPayloadRef);
        SWC_ASSERT(payloadRef.shardIndex == shardIndex);
        if (!hasPayloadRef)
            return;

        DataSegmentAllocation allocation;
        SWC_ASSERT(segment.findAllocation(allocation, baseOffset));
        SWC_ASSERT(allocation.offset == payloadRef.offset);
        SWC_ASSERT(allocation.size >= payload.size());

        validateNativeStaticPayload(constant.typeRef(), shardIndex, payloadRef.offset, payload);
        return;
    }

    SWC_ASSERT(constant.typeRef().isValid());

    const uint64_t sizeOf = builder_->ctx().typeMgr().get(constant.typeRef()).sizeOf(builder_->ctx());
    SWC_ASSERT(sizeOf != 0);
    SWC_ASSERT(baseOffset + sizeOf <= segment.extentSize());

    const auto* payloadBytes = segment.ptr<std::byte>(baseOffset);
    SWC_ASSERT(payloadBytes != nullptr);

    const ByteSpan payloadSpan = asByteSpan(payloadBytes, sizeOf);
    validateNativeStaticPayload(constant.typeRef(), shardIndex, baseOffset, payloadSpan);
}

void NativeValidate::validateNativeStaticPayload(const TypeRef typeRef, const uint32_t shardIndex, const Ref baseOffset, const ByteSpan bytes) const
{
    SWC_ASSERT(typeRef.isValid());

    SWC_ASSERT(builder_ != nullptr);
    const TypeInfo& typeInfo = builder_->ctx().typeMgr().get(typeRef);
    if (typeInfo.isAlias())
    {
        const TypeRef unwrapped = typeInfo.unwrap(builder_->ctx(), typeRef, TypeExpandE::Alias);
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
        SWC_ASSERT(allZeroBytes(bytes));
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

        DataSegmentRef typeInfoRef;
        SWC_ASSERT(findDataSegmentRelocation(typeInfoRef, shardIndex, baseOffset + offsetof(Runtime::Any, type)));
        const DataSegment& typeInfoSegment = builder_->compiler().cstMgr().shardDataSegment(typeInfoRef.shardIndex);
        SWC_ASSERT(typeInfoRef.offset < typeInfoSegment.extentSize());

        const auto* runtimeType = typeInfoSegment.ptr<Runtime::TypeInfo>(typeInfoRef.offset);
        SWC_ASSERT(runtimeType != nullptr);

        const TypeRef valueTypeRef = builder_->ctx().typeGen().getBackTypeRef(runtimeType);
        SWC_ASSERT(valueTypeRef.isValid());

        if (!value->value)
            return;

        DataSegmentRef valueRef;
        SWC_ASSERT(findDataSegmentRelocation(valueRef, shardIndex, baseOffset + offsetof(Runtime::Any, value)));
        const DataSegment& valueSegment = builder_->compiler().cstMgr().shardDataSegment(valueRef.shardIndex);
        SWC_ASSERT(valueRef.offset < valueSegment.extentSize());

        const uint64_t valueSize = builder_->ctx().typeMgr().get(valueTypeRef).sizeOf(builder_->ctx());
        SWC_ASSERT(valueSize != 0);
        SWC_ASSERT(valueRef.offset + valueSize <= valueSegment.extentSize());

        const auto* payloadBytes = valueSegment.ptr<std::byte>(valueRef.offset);
        SWC_ASSERT(payloadBytes != nullptr);

        const ByteSpan payloadSpan = asByteSpan(payloadBytes, valueSize);
        validateNativeStaticPayload(valueTypeRef, valueRef.shardIndex, valueRef.offset, payloadSpan);
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

        DataSegmentRef targetRef;
        SWC_ASSERT(findDataSegmentRelocation(targetRef, shardIndex, baseOffset + offsetof(Runtime::String, ptr)));
        const DataSegment& targetSegment = builder_->compiler().cstMgr().shardDataSegment(targetRef.shardIndex);
        SWC_ASSERT(targetRef.offset < targetSegment.extentSize());
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
        const TypeInfo& elementType    = builder_->ctx().typeMgr().get(elementTypeRef);
        const uint64_t  elementSize    = elementType.sizeOf(builder_->ctx());
        SWC_ASSERT(elementSize != 0);

        DataSegmentRef targetRef;
        SWC_ASSERT(findDataSegmentRelocation(targetRef, shardIndex, baseOffset + offsetof(Runtime::Slice<uint8_t>, ptr)));
        const DataSegment& targetSegment = builder_->compiler().cstMgr().shardDataSegment(targetRef.shardIndex);

        const uint64_t byteCount = slice->count * elementSize;
        SWC_ASSERT(targetRef.offset + byteCount <= targetSegment.extentSize());

        if (elementType.isBool() || elementType.isChar() || elementType.isRune() || elementType.isInt() || elementType.isFloat())
            return;

        const auto* segmentBytes = targetSegment.ptr<std::byte>(targetRef.offset);
        SWC_ASSERT(segmentBytes != nullptr);

        for (uint64_t offset = 0; offset < byteCount; offset += elementSize)
        {
            const auto elementBytes = ByteSpan{segmentBytes + offset, static_cast<size_t>(elementSize)};
            validateNativeStaticPayload(elementTypeRef, targetRef.shardIndex, targetRef.offset + static_cast<uint32_t>(offset), elementBytes);
        }

        return;
    }

    if (typeInfo.isArray())
    {
        const TypeRef   elementTypeRef = typeInfo.payloadArrayElemTypeRef();
        const TypeInfo& elementType    = builder_->ctx().typeMgr().get(elementTypeRef);
        const uint64_t  elementSize    = elementType.sizeOf(builder_->ctx());
        SWC_ASSERT(elementSize != 0);

        uint64_t totalCount = 1;
        for (const uint64_t dim : typeInfo.payloadArrayDims())
            totalCount *= dim;

        for (uint64_t idx = 0; idx < totalCount; ++idx)
        {
            const uint64_t elementOffset = idx * elementSize;
            SWC_ASSERT(elementOffset + elementSize <= bytes.size());
            const auto elementBytes = ByteSpan{bytes.data() + elementOffset, static_cast<size_t>(elementSize)};
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
            const TypeInfo& fieldType    = builder_->ctx().typeMgr().get(fieldTypeRef);
            const uint64_t  fieldSize    = fieldType.sizeOf(builder_->ctx());
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
            const TypeInfo& fieldType = builder_->ctx().typeMgr().get(fieldTypeRef);
            uint32_t        align     = fieldType.alignOf(builder_->ctx());
            const uint64_t  fieldSize = fieldType.sizeOf(builder_->ctx());
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
            SWC_ASSERT(allZeroBytes(bytes));
            return;
        }

        DataSegmentRef invokeRef;
        SWC_ASSERT(findDataSegmentRelocation(invokeRef, shardIndex, baseOffset + offsetof(Runtime::ClosureValue, invoke)));
        const DataSegment& invokeSegment = builder_->compiler().cstMgr().shardDataSegment(invokeRef.shardIndex);
        SWC_ASSERT(invokeRef.offset < invokeSegment.extentSize());

        const auto capturedPtr = *reinterpret_cast<const uint64_t*>(value->capture);
        if (!capturedPtr)
            return;

        DataSegmentRef captureRef;
        SWC_ASSERT(findDataSegmentRelocation(captureRef, shardIndex, baseOffset + offsetof(Runtime::ClosureValue, capture)));
        const DataSegment& captureSegment = builder_->compiler().cstMgr().shardDataSegment(captureRef.shardIndex);
        SWC_ASSERT(captureRef.offset < captureSegment.extentSize());
        return;
    }

    if (typeInfo.isPointerLike() || typeInfo.isReference() || typeInfo.isTypeInfo() || typeInfo.isCString() || typeInfo.isFunction())
    {
        SWC_ASSERT(bytes.size() == sizeof(uint64_t));

        const uint64_t ptr = *reinterpret_cast<const uint64_t*>(bytes.data());
        if (!ptr)
            return;

        DataSegmentRef targetRef;
        if (findDataSegmentRelocation(targetRef, shardIndex, baseOffset))
        {
            const DataSegment& targetSegment = builder_->compiler().cstMgr().shardDataSegment(targetRef.shardIndex);
            SWC_ASSERT(targetRef.offset < targetSegment.extentSize());
            return;
        }

        const SymbolFunction* targetFunction = nullptr;
        SWC_ASSERT(findFunctionSymbolRelocation(targetFunction, shardIndex, baseOffset));
        SWC_ASSERT(targetFunction != nullptr);
        if (!targetFunction->isForeign())
            SWC_ASSERT(builder_->tryFindFunctionInfo(*targetFunction) != nullptr);
        return;
    }

    SWC_UNREACHABLE();
}

bool NativeValidate::findDataSegmentRelocation(DataSegmentRef& outTargetRef, const uint32_t shardIndex, const uint32_t offset) const
{
    outTargetRef = {};
    SWC_ASSERT(builder_ != nullptr);
    const DataSegment& segment = builder_->compiler().cstMgr().shardDataSegment(shardIndex);
    DataSegmentRelocation relocation;
    if (!segment.findRelocation(relocation, offset, DataSegmentRelocationKind::DataSegmentOffset))
        return false;

    outTargetRef = {
        .shardIndex = relocation.targetShardIndex == INVALID_REF ? shardIndex : relocation.targetShardIndex,
        .offset     = relocation.targetOffset,
    };
    return true;
}

bool NativeValidate::findFunctionSymbolRelocation(const SymbolFunction*& outTargetSymbol, const uint32_t shardIndex, const uint32_t offset) const
{
    outTargetSymbol = nullptr;
    SWC_ASSERT(builder_ != nullptr);
    const DataSegment& segment = builder_->compiler().cstMgr().shardDataSegment(shardIndex);
    DataSegmentRelocation relocation;
    if (!segment.findRelocation(relocation, offset, DataSegmentRelocationKind::FunctionSymbol))
        return false;

    outTargetSymbol = relocation.targetSymbol;
    return true;
}

SWC_END_NAMESPACE();

#endif
