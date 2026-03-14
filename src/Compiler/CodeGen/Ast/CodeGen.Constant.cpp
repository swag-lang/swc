#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct AggregateElementLayout
    {
        AstNodeRef valueRef = AstNodeRef::invalid();
        TypeRef    typeRef  = TypeRef::invalid();
        uint32_t   offset   = 0;
    };

    uint64_t alignUpTo(uint64_t value, uint32_t alignment)
    {
        SWC_ASSERT(alignment != 0);
        const uint64_t align = alignment;
        return ((value + align - 1) / align) * align;
    }

    bool computeAggregateLayout(CodeGen& codeGen, TypeRef aggregateTypeRef, std::span<const AstNodeRef> elementRefs, SmallVector<AggregateElementLayout>& outLayout, uint32_t& outTotalSize)
    {
        outLayout.clear();
        outTotalSize = 0;
        if (aggregateTypeRef.isInvalid())
            return false;

        const TypeInfo& aggregateType = codeGen.typeMgr().get(aggregateTypeRef);
        if (!aggregateType.isAggregateStruct() && !aggregateType.isAggregateArray())
            return false;

        const auto& elementTypes = aggregateType.payloadAggregate().types;
        if (elementTypes.size() != elementRefs.size())
            return false;

        outLayout.reserve(elementRefs.size());

        uint32_t maxAlignment = 1;
        uint64_t offset       = 0;
        for (size_t i = 0; i < elementRefs.size(); ++i)
        {
            const TypeRef   elementTypeRef = elementTypes[i];
            const TypeInfo& elementType    = codeGen.typeMgr().get(elementTypeRef);
            uint32_t        alignment      = elementType.alignOf(codeGen.ctx());
            if (!alignment)
                alignment = 1;

            const uint64_t elementSize = elementType.sizeOf(codeGen.ctx());
            if (!elementSize)
                continue;

            SWC_ASSERT(elementSize <= std::numeric_limits<uint32_t>::max());
            offset = alignUpTo(offset, alignment);
            outLayout.push_back({
                .valueRef = elementRefs[i],
                .typeRef  = elementTypeRef,
                .offset   = static_cast<uint32_t>(offset),
            });
            offset += elementSize;
            maxAlignment = std::max(maxAlignment, alignment);
        }

        offset = alignUpTo(offset, maxAlignment);
        SWC_ASSERT(offset <= std::numeric_limits<uint32_t>::max());
        outTotalSize = static_cast<uint32_t>(offset);
        return true;
    }

    Result emitAggregateLiteralPayload(CodeGen& codeGen, AstNodeRef nodeRef, std::span<const AstNodeRef> elementRefs, TypeRef aggregateTypeRef)
    {
        SmallVector<AggregateElementLayout> layout;
        uint32_t                            totalSize = 0;
        const bool                          hasLayout = computeAggregateLayout(codeGen, aggregateTypeRef, elementRefs, layout, totalSize);
        SWC_INTERNAL_CHECK(hasLayout);
        SWC_INTERNAL_CHECK(totalSize == codeGen.typeMgr().get(aggregateTypeRef).sizeOf(codeGen.ctx()));

        const MicroReg dstBaseReg = codeGen.runtimeStorageAddressReg(nodeRef);
        for (const AggregateElementLayout& entry : layout)
        {
            const CodeGenNodePayload& elementPayload = codeGen.payload(entry.valueRef);
            const uint64_t            elementSize    = codeGen.typeMgr().get(entry.typeRef).sizeOf(codeGen.ctx());
            if (!elementSize)
                continue;

            SWC_ASSERT(elementSize <= std::numeric_limits<uint32_t>::max());

            if (elementPayload.isAddress())
            {
                MicroReg dstElementReg = dstBaseReg;
                if (entry.offset != 0)
                {
                    dstElementReg = codeGen.nextVirtualIntRegister();
                    codeGen.builder().emitLoadRegReg(dstElementReg, dstBaseReg, MicroOpBits::B64);
                    codeGen.builder().emitOpBinaryRegImm(dstElementReg, ApInt(entry.offset, 64), MicroOp::Add, MicroOpBits::B64);
                }

                CodeGenMemoryHelpers::emitMemCopy(codeGen, dstElementReg, elementPayload.reg, static_cast<uint32_t>(elementSize));
                continue;
            }

            const MicroOpBits storeBits = microOpBitsFromChunkSize(static_cast<uint32_t>(elementSize));
            SWC_ASSERT(storeBits != MicroOpBits::Zero);
            codeGen.builder().emitLoadMemReg(dstBaseReg, entry.offset, elementPayload.reg, storeBits);
        }

        CodeGenNodePayload& nodePayload = codeGen.setPayloadAddress(nodeRef, aggregateTypeRef);
        nodePayload.reg                 = dstBaseReg;
        return Result::Continue;
    }

    TypeRef storedLiteralTypeRef(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        const TypeRef storedTypeRef = codeGen.sema().viewStored(nodeRef, SemaNodeViewPartE::Type).typeRef();
        if (storedTypeRef.isValid())
            return storedTypeRef;
        return codeGen.viewType(nodeRef).typeRef();
    }

    ConstantRef materializeBorrowedStorageConstant(CodeGen& codeGen, ConstantRef cstRef, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return ConstantRef::invalid();

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        if (!typeInfo.isStruct() && !typeInfo.isArray())
            return ConstantRef::invalid();

        const uint64_t storageSize = typeInfo.sizeOf(codeGen.ctx());
        SWC_ASSERT(storageSize <= std::numeric_limits<uint32_t>::max());

        SmallVector<std::byte> storageBytes;
        storageBytes.resize(storageSize);
        if (storageSize)
            ConstantLower::lowerToBytes(codeGen.sema(), ByteSpanRW{storageBytes.data(), storageBytes.size()}, cstRef, typeRef);

        return CodeGenFunctionHelpers::materializeStaticPayloadConstant(codeGen, typeRef, ByteSpan{storageBytes.data(), storageBytes.size()});
    }

    void emitPointerConstant(CodeGen& codeGen, MicroReg reg, const uint64_t value, ConstantRef cstRef)
    {
        if (!value)
        {
            codeGen.builder().emitLoadRegImm(reg, ApInt(0, 64), MicroOpBits::B64);
            return;
        }

        uint32_t  shardIndex = 0;
        const Ref ref        = codeGen.cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(value));
        if (ref != INVALID_REF)
            codeGen.builder().emitLoadRegPtrReloc(reg, value, cstRef);
        else
            codeGen.builder().emitLoadRegPtrImm(reg, value);
    }

    void emitConstantToPayload(CodeGen& codeGen, CodeGenNodePayload& payload, ConstantRef cstRef, const ConstantValue& cst, TypeRef targetTypeRef)
    {
        MicroBuilder& builder = codeGen.builder();

        switch (cst.kind())
        {
            case ConstantKind::Bool:
            {
                builder.emitLoadRegImm(payload.reg, ApInt(cst.getBool() ? 1 : 0, 64), MicroOpBits::B64);
                payload.setIsValue();
                return;
            }

            case ConstantKind::Char:
            {
                builder.emitLoadRegImm(payload.reg, ApInt(cst.getChar(), 64), MicroOpBits::B64);
                payload.setIsValue();
                return;
            }

            case ConstantKind::Rune:
            {
                builder.emitLoadRegImm(payload.reg, ApInt(cst.getRune(), 64), MicroOpBits::B64);
                payload.setIsValue();
                return;
            }

            case ConstantKind::Int:
            {
                const ApsInt& val = cst.getInt();
                SWC_ASSERT(val.fits64());
                builder.emitLoadRegImm(payload.reg, ApInt(static_cast<uint64_t>(val.asI64()), 64), MicroOpBits::B64);
                payload.setIsValue();
                return;
            }

            case ConstantKind::Float:
            {
                const ApFloat& value = cst.getFloat();
                if (value.bitWidth() == 32)
                {
                    const auto bits = std::bit_cast<uint32_t>(value.asFloat());
                    builder.emitLoadRegImm(payload.reg, ApInt(bits, 64), MicroOpBits::B32);
                    payload.setIsValue();
                    return;
                }

                if (value.bitWidth() == 64)
                {
                    const auto bits = std::bit_cast<uint64_t>(value.asDouble());
                    builder.emitLoadRegImm(payload.reg, ApInt(bits, 64), MicroOpBits::B64);
                    payload.setIsValue();
                    return;
                }

                SWC_UNREACHABLE();
            }

            case ConstantKind::String:
            {
                const std::string_view value               = cst.getString();
                const ConstantRef      runtimeStringCstRef = CodeGenFunctionHelpers::materializeRuntimeBufferConstant(codeGen, codeGen.typeMgr().typeString(), value.data(), value.size());
                SWC_ASSERT(runtimeStringCstRef.isValid());
                const ConstantValue& runtimeStringCst = codeGen.cstMgr().get(runtimeStringCstRef);
                builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(runtimeStringCst.getStruct().data()), runtimeStringCstRef);
                payload.setIsValue();
                return;
            }

            case ConstantKind::ValuePointer:
            {
                emitPointerConstant(codeGen, payload.reg, cst.getValuePointer(), cstRef);
                payload.setIsValue();
                return;
            }

            case ConstantKind::BlockPointer:
            {
                emitPointerConstant(codeGen, payload.reg, cst.getBlockPointer(), cstRef);
                payload.setIsValue();
                return;
            }

            case ConstantKind::Null:
            {
                if (targetTypeRef.isValid())
                {
                    const TypeInfo& targetType = codeGen.typeMgr().get(targetTypeRef);
                    const uint64_t  sizeOfType = targetType.sizeOf(codeGen.ctx());
                    if (sizeOfType > sizeof(uint64_t))
                    {
                        SWC_ASSERT(sizeOfType <= std::numeric_limits<uint32_t>::max());
                        SmallVector<std::byte> typedNullBytes;
                        typedNullBytes.resize(sizeOfType);
                        std::memset(typedNullBytes.data(), 0, typedNullBytes.size());
                        ConstantLower::lowerToBytes(codeGen.sema(), ByteSpanRW{typedNullBytes.data(), typedNullBytes.size()}, cstRef, targetTypeRef);

                        const ConstantRef    typedNullCstRef = CodeGenFunctionHelpers::materializeStaticPayloadConstant(codeGen, targetTypeRef, ByteSpan{typedNullBytes.data(), typedNullBytes.size()});
                        const ConstantValue& typedNullCst    = codeGen.cstMgr().get(typedNullCstRef);
                        builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(typedNullCst.getStruct().data()), typedNullCstRef);
                        payload.setIsValue();
                        return;
                    }
                }

                builder.emitLoadRegImm(payload.reg, ApInt(0, 64), MicroOpBits::B64);
                payload.setIsValue();
                return;
            }

            case ConstantKind::TypeValue:
            {
                ConstantRef  typeInfoCstRef = ConstantRef::invalid();
                const Result typeInfoRes    = codeGen.cstMgr().makeTypeInfo(codeGen.sema(), typeInfoCstRef, cst.getTypeValue(), codeGen.curNodeRef());
                SWC_ASSERT(typeInfoRes == Result::Continue);
                SWC_ASSERT(typeInfoCstRef.isValid());

                const ConstantValue& typeInfoCst = codeGen.cstMgr().get(typeInfoCstRef);
                SWC_ASSERT(typeInfoCst.isValuePointer());

                builder.emitLoadRegPtrReloc(payload.reg, typeInfoCst.getValuePointer(), typeInfoCstRef);
                payload.typeRef = codeGen.typeMgr().typeTypeInfo();
                payload.setIsValue();
                return;
            }

            case ConstantKind::EnumValue:
                emitConstantToPayload(codeGen, payload, cst.getEnumValue(), codeGen.cstMgr().get(cst.getEnumValue()), targetTypeRef);
                return;

            case ConstantKind::Struct:
            {
                const ByteSpan structBytes = cst.getStruct();
                if (targetTypeRef.isValid())
                {
                    const TypeInfo& targetType = codeGen.typeMgr().get(targetTypeRef);
                    if (targetType.isReference())
                    {
                        builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(structBytes.data()), cstRef);
                        payload.setIsValue();
                        return;
                    }
                }

                const uint64_t storageSize = cst.type(codeGen.ctx()).sizeOf(codeGen.ctx());
                SWC_ASSERT(structBytes.size() == storageSize);
                builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(structBytes.data()), cstRef);
                payload.setIsAddress();
                return;
            }

            case ConstantKind::Array:
            {
                const ByteSpan arrayBytes = cst.getArray();
                if (targetTypeRef.isValid())
                {
                    const TypeInfo& targetType = codeGen.typeMgr().get(targetTypeRef);
                    if (targetType.isString())
                    {
                        const ConstantRef runtimeStringCstRef = CodeGenFunctionHelpers::materializeRuntimeBufferConstant(codeGen, targetTypeRef, arrayBytes.data(), arrayBytes.size());
                        SWC_ASSERT(runtimeStringCstRef.isValid());
                        const ConstantValue& runtimeStringCst = codeGen.cstMgr().get(runtimeStringCstRef);
                        builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(runtimeStringCst.getStruct().data()), runtimeStringCstRef);
                        payload.setIsValue();
                        return;
                    }

                    if (targetType.isSlice())
                    {
                        const TypeInfo&   elementType        = codeGen.typeMgr().get(targetType.payloadTypeRef());
                        const uint64_t    elementSize        = elementType.sizeOf(codeGen.ctx());
                        const ConstantRef runtimeSliceCstRef = CodeGenFunctionHelpers::materializeRuntimeBufferConstant(codeGen, targetTypeRef, arrayBytes.data(), elementSize ? arrayBytes.size() / elementSize : 0);
                        SWC_ASSERT(runtimeSliceCstRef.isValid());
                        const ConstantValue& runtimeSliceCst = codeGen.cstMgr().get(runtimeSliceCstRef);
                        builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(runtimeSliceCst.getStruct().data()), runtimeSliceCstRef);
                        payload.setIsValue();
                        return;
                    }
                }

                const uint64_t storageSize = cst.type(codeGen.ctx()).sizeOf(codeGen.ctx());
                SWC_ASSERT(arrayBytes.size() == storageSize);
                builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(arrayBytes.data()), cstRef);
                payload.setIsAddress();
                return;
            }

            case ConstantKind::Slice:
            {
                const ByteSpan  sliceBytes = cst.getSlice();
                const TypeInfo& sliceType  = cst.type(codeGen.ctx());
                SWC_ASSERT(sliceType.isSlice());
                const TypeInfo&   elementType        = codeGen.typeMgr().get(sliceType.payloadTypeRef());
                const uint64_t    elementSize        = elementType.sizeOf(codeGen.ctx());
                const ConstantRef runtimeSliceCstRef = CodeGenFunctionHelpers::materializeRuntimeBufferConstant(codeGen, cst.typeRef(), sliceBytes.data(), elementSize ? sliceBytes.size() / elementSize : 0);
                SWC_ASSERT(runtimeSliceCstRef.isValid());
                const ConstantValue& runtimeSliceCst = codeGen.cstMgr().get(runtimeSliceCstRef);
                builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(runtimeSliceCst.getStruct().data()), runtimeSliceCstRef);
                payload.setIsValue();
                return;
            }

            case ConstantKind::AggregateStruct:
            case ConstantKind::AggregateArray:
            {
                const ConstantRef storageCstRef = materializeBorrowedStorageConstant(codeGen, cstRef, targetTypeRef);
                SWC_ASSERT(storageCstRef.isValid());
                const ConstantValue& storageCst = codeGen.cstMgr().get(storageCstRef);

                if (storageCst.isArray())
                {
                    builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(storageCst.getArray().data()), storageCstRef);
                    payload.setIsAddress();
                    return;
                }

                SWC_ASSERT(storageCst.isStruct());
                builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(storageCst.getStruct().data()), storageCstRef);
                payload.setIsAddress();
                return;
            }

            default:
                SWC_UNREACHABLE();
        }
    }
}

Result CodeGen::emitConstant(AstNodeRef nodeRef)
{
    if (safePayload(nodeRef))
        return Result::Continue;

    const SemaNodeView view = viewTypeConstant(nodeRef);
    if (view.cstRef().isInvalid())
        return Result::Continue;

    const ConstantValue& cst = cstMgr().get(view.cstRef());
    if (cst.kind() == ConstantKind::Undefined)
        return Result::Continue;

    CodeGenNodePayload& payload = setPayload(nodeRef, view.typeRef());
    emitConstantToPayload(*this, payload, view.cstRef(), cst, view.typeRef());
    return Result::SkipChildren;
}

Result AstNullLiteral::codeGenPostNode(CodeGen& codeGen)
{
    if (codeGen.safePayload(codeGen.curNodeRef()))
        return Result::Continue;

    const TypeRef targetTypeRef = codeGen.curViewType().typeRef();
    if (targetTypeRef.isValid())
    {
        const TypeInfo& targetType = codeGen.typeMgr().get(targetTypeRef);
        const uint64_t  sizeOfType = targetType.sizeOf(codeGen.ctx());
        if (sizeOfType > sizeof(uint64_t))
        {
            SWC_ASSERT(sizeOfType <= std::numeric_limits<uint32_t>::max());

            // ABI-direct address-backed values still need a typed zero storage, not a raw null pointer.
            SmallVector<std::byte> typedNullBytes;
            typedNullBytes.resize(sizeOfType);
            std::memset(typedNullBytes.data(), 0, typedNullBytes.size());
            ConstantLower::lowerToBytes(codeGen.sema(), ByteSpanRW{typedNullBytes.data(), typedNullBytes.size()}, codeGen.cstMgr().cstNull(), targetTypeRef);

            const ConstantRef         typedNullCstRef = CodeGenFunctionHelpers::materializeStaticPayloadConstant(codeGen, targetTypeRef, ByteSpan{typedNullBytes.data(), typedNullBytes.size()});
            const ConstantValue&      typedNullCst    = codeGen.cstMgr().get(typedNullCstRef);
            const CodeGenNodePayload& payload         = codeGen.setPayloadValue(codeGen.curNodeRef(), targetTypeRef);
            codeGen.builder().emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(typedNullCst.getStruct().data()), typedNullCstRef);
            return Result::Continue;
        }
    }

    const CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef(), targetTypeRef);
    codeGen.builder().emitLoadRegImm(payload.reg, ApInt(0, 64), MicroOpBits::B64);
    return Result::Continue;
}

Result AstInitializerExpr::codeGenPostNode(CodeGen& codeGen) const
{
    codeGen.inheritPayload(codeGen.curNodeRef(), nodeExprRef, codeGen.curViewType().typeRef());
    return Result::Continue;
}

Result AstArrayLiteral::codeGenPostNode(CodeGen& codeGen) const
{
    SmallVector<AstNodeRef> elementRefs;
    collectChildren(elementRefs, codeGen.ast());

    const TypeRef aggregateTypeRef = storedLiteralTypeRef(codeGen, codeGen.curNodeRef());
    return emitAggregateLiteralPayload(codeGen, codeGen.curNodeRef(), elementRefs.span(), aggregateTypeRef);
}

Result AstStructLiteral::codeGenPostNode(CodeGen& codeGen) const
{
    SmallVector<AstNodeRef> elementRefs;
    collectChildren(elementRefs, codeGen.ast());

    const TypeRef aggregateTypeRef = storedLiteralTypeRef(codeGen, codeGen.curNodeRef());
    return emitAggregateLiteralPayload(codeGen, codeGen.curNodeRef(), elementRefs.span(), aggregateTypeRef);
}

Result AstStructInitializerList::codeGenPostNode(CodeGen& codeGen) const
{
    SmallVector<AstNodeRef> elementRefs;
    codeGen.ast().appendNodes(elementRefs, spanArgsRef);

    const TypeRef aggregateTypeRef = storedLiteralTypeRef(codeGen, codeGen.curNodeRef());
    return emitAggregateLiteralPayload(codeGen, codeGen.curNodeRef(), elementRefs.span(), aggregateTypeRef);
}

SWC_END_NAMESPACE();
