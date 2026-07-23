#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct AggregateElementLayout
    {
        AstNodeRef valueRef = AstNodeRef::invalid();
        TypeRef    typeRef  = TypeRef::invalid();
        uint32_t   offset   = 0;
    };

    uint64_t sliceCountFromArrayCast(CodeGen& codeGen, const TypeInfo& srcArrayType, const TypeInfo& dstElementType)
    {
        const uint64_t dstElementSize = dstElementType.sizeOf(codeGen.ctx());
        if (dstElementSize)
            return srcArrayType.sizeOf(codeGen.ctx()) / dstElementSize;

        uint64_t totalCount = 1;
        for (const uint64_t dim : srcArrayType.payloadArrayDims())
            totalCount *= dim;
        return totalCount;
    }

    uint64_t alignUpTo(uint64_t value, uint32_t alignment)
    {
        SWC_ASSERT(alignment != 0);
        const uint64_t align = alignment;
        return ((value + align - 1) / align) * align;
    }

    TypeRef topLevelArrayElementTypeRef(CodeGen& codeGen, const TypeInfo& arrayType)
    {
        SWC_ASSERT(arrayType.isArray());
        const auto& dims = arrayType.payloadArrayDims();
        SWC_ASSERT(!dims.empty());

        if (dims.size() == 1)
            return arrayType.payloadArrayElemTypeRef();

        SmallVector<uint64_t> remainingDims;
        remainingDims.reserve(dims.size() - 1);
        for (size_t i = 1; i < dims.size(); ++i)
            remainingDims.push_back(dims[i]);

        return codeGen.typeMgr().addType(TypeInfo::makeArray(remainingDims.span(), arrayType.payloadArrayElemTypeRef(), arrayType.flags()));
    }

    AstNodeRef codeGenErrorNodeRef(CodeGen& codeGen)
    {
        const AstNodeRef currentNodeRef = codeGen.viewZero(codeGen.curNodeRef()).nodeRef();
        if (currentNodeRef.isValid())
            return currentNodeRef;

        const AstNodeRef functionDeclRef = codeGen.viewZero(codeGen.function().declNodeRef()).nodeRef();
        SWC_ASSERT(functionDeclRef.isValid());
        return functionDeclRef;
    }

    Result raiseConstantMaterializationError(CodeGen& codeGen, std::string_view because)
    {
        auto diag = SemaError::report(codeGen.sema(), DiagnosticId::misc_err_internal_codegen_failure, codeGenErrorNodeRef(codeGen));
        diag.addArgument(Diagnostic::ARG_WHAT, codeGen.function().getFullScopedName(codeGen.ctx()));
        diag.addArgument(Diagnostic::ARG_BECAUSE, because);
        diag.report(codeGen.ctx());
        return Result::Error;
    }

    void emitPayloadBytesToAddress(CodeGen& codeGen, MicroReg dstReg, std::span<const std::byte> bytes)
    {
        MicroBuilder& builder = codeGen.builder();
        uint32_t      offset  = 0;
        while (offset < bytes.size())
        {
            const uint32_t remaining = static_cast<uint32_t>(bytes.size() - offset);
            uint32_t       chunkSize = 1;
            auto           storeBits = MicroOpBits::B8;
            if (remaining >= 8)
            {
                chunkSize = 8;
                storeBits = MicroOpBits::B64;
            }
            else if (remaining >= 4)
            {
                chunkSize = 4;
                storeBits = MicroOpBits::B32;
            }
            else if (remaining >= 2)
            {
                chunkSize = 2;
                storeBits = MicroOpBits::B16;
            }

            uint64_t value = 0;
            for (uint32_t i = 0; i < chunkSize; ++i)
                value |= static_cast<uint64_t>(static_cast<uint8_t>(bytes[offset + i])) << (i * 8);
            builder.emitLoadMemImm(dstReg, offset, ApInt(value, 64), storeBits);
            offset += chunkSize;
        }
    }

    bool tryRuntimeStorageAddressReg(CodeGen& codeGen, const SymbolVariable& storageSym, MicroReg& outStorageReg)
    {
        outStorageReg = MicroReg::invalid();

        if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, storageSym))
        {
            const CodeGenNodePayload storagePayload = CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(codeGen, storageSym);
            SWC_ASSERT(storagePayload.isAddress());
            outStorageReg = storagePayload.reg;
            return outStorageReg.isValid();
        }

        if (storageSym.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            const CodeGenNodePayload storagePayload = CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, codeGen.function(), storageSym);
            if (!storagePayload.isAddress())
                return false;

            outStorageReg = storagePayload.reg;
            return outStorageReg.isValid();
        }

        if (codeGen.localStackBaseReg().isValid() && (storageSym.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) || storageSym.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal)))
        {
            const CodeGenNodePayload storagePayload = codeGen.resolveLocalStackPayload(storageSym);
            SWC_ASSERT(storagePayload.isAddress());
            outStorageReg = storagePayload.reg;
            return outStorageReg.isValid();
        }

        if (storageSym.hasGlobalStorage())
        {
            outStorageReg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegDataSegmentReloc(outStorageReg, storageSym.globalStorageKind(), storageSym.offset());
            return outStorageReg.isValid();
        }

        return false;
    }

    Result tryEmitRuntimeStorageConstant(CodeGen& codeGen, CodeGenNodePayload& payload, AstNodeRef storageNodeRef, ConstantRef cstRef, TypeRef targetTypeRef, bool& outHandled)
    {
        outHandled = false;
        if (storageNodeRef.isInvalid() || payload.runtimeStorageSym == nullptr || cstRef.isInvalid())
            return Result::Continue;

        TypeRef storageTypeRef = payload.runtimeStorageSym->typeRef();
        if (storageTypeRef.isInvalid())
            storageTypeRef = targetTypeRef;
        if (storageTypeRef.isInvalid())
            return Result::Continue;

        const TypeInfo& storageType = codeGen.typeMgr().get(storageTypeRef);
        if (!storageType.isArray() && !storageType.isStruct())
            return Result::Continue;

        const uint64_t storageSize = storageType.sizeOf(codeGen.ctx());
        SWC_ASSERT(storageSize <= std::numeric_limits<uint32_t>::max());
        if (storageSize > std::numeric_limits<uint32_t>::max())
            return raiseConstantMaterializationError(codeGen, "constant runtime storage is too large");

        MicroReg storageReg = MicroReg::invalid();
        if (!tryRuntimeStorageAddressReg(codeGen, *payload.runtimeStorageSym, storageReg))
            return Result::Continue;

        const ConstantRef staticCstRef = CodeGenConstantHelpers::ensureStaticPayloadConstant(codeGen, cstRef, storageTypeRef);
        if (staticCstRef.isValid())
        {
            const ConstantValue&             staticCst   = codeGen.cstMgr().get(staticCstRef);
            const std::span<const std::byte> staticBytes = staticCst.isArray() ? staticCst.getArray() : staticCst.getStruct();
            SWC_ASSERT(staticBytes.size() == storageSize);
            if (!staticBytes.empty())
            {
                const MicroReg staticReg = codeGen.nextVirtualIntRegister();
                codeGen.builder().emitLoadRegPtrReloc(staticReg, reinterpret_cast<uint64_t>(staticBytes.data()), staticCstRef);
                CodeGenMemoryHelpers::emitMemCopy(codeGen, storageReg, staticReg, static_cast<uint32_t>(storageSize));
            }

            payload.reg     = storageReg;
            payload.typeRef = storageTypeRef;
            payload.setIsAddress();
            outHandled = true;
            return Result::Continue;
        }

        SmallVector<std::byte> storageBytes;
        storageBytes.resize(storageSize);
        if (storageSize)
            SWC_RESULT(ConstantLower::lowerToBytes(codeGen.sema(), std::span{storageBytes.data(), storageBytes.size()}, cstRef, storageTypeRef));

        emitPayloadBytesToAddress(codeGen, storageReg, std::span{storageBytes.data(), storageBytes.size()});
        payload.reg     = storageReg;
        payload.typeRef = storageTypeRef;
        payload.setIsAddress();
        outHandled = true;
        return Result::Continue;
    }

    bool computeLiteralLayout(CodeGen& codeGen, TypeRef storageTypeRef, std::span<const AstNodeRef> elementRefs, SmallVector<AggregateElementLayout>& outLayout, uint32_t& outTotalSize)
    {
        outLayout.clear();
        outTotalSize = 0;
        if (storageTypeRef.isInvalid())
            return false;

        const TypeInfo& storageType = codeGen.typeMgr().get(storageTypeRef);
        if (storageType.isAggregateStruct() || storageType.isAggregateArray())
        {
            const auto& elementTypes = storageType.payloadAggregate().types;
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
                AggregateElementLayout elem;
                elem.valueRef = elementRefs[i];
                elem.typeRef  = elementTypeRef;
                elem.offset   = static_cast<uint32_t>(offset);
                outLayout.push_back(elem);
                offset += elementSize;
                maxAlignment = std::max(maxAlignment, alignment);
            }

            offset = alignUpTo(offset, maxAlignment);
            SWC_ASSERT(offset <= std::numeric_limits<uint32_t>::max());
            outTotalSize = static_cast<uint32_t>(offset);
            return true;
        }

        if (storageType.isArray())
        {
            const auto& dims = storageType.payloadArrayDims();
            if (dims.empty())
                return false;
            if (elementRefs.size() > dims[0])
                return false;

            const TypeRef   elementTypeRef = topLevelArrayElementTypeRef(codeGen, storageType);
            const TypeInfo& elementType    = codeGen.typeMgr().get(elementTypeRef);
            const uint64_t  elementSize    = elementType.sizeOf(codeGen.ctx());
            SWC_ASSERT(elementSize <= std::numeric_limits<uint32_t>::max());

            outLayout.reserve(elementRefs.size());
            for (size_t i = 0; i < elementRefs.size(); ++i)
            {
                const uint64_t elementOffset = i * elementSize;
                SWC_ASSERT(elementOffset <= std::numeric_limits<uint32_t>::max());
                AggregateElementLayout elem;
                elem.valueRef = elementRefs[i];
                elem.typeRef  = elementTypeRef;
                elem.offset   = static_cast<uint32_t>(elementOffset);
                outLayout.push_back(elem);
            }

            const uint64_t totalSize = storageType.sizeOf(codeGen.ctx());
            SWC_ASSERT(totalSize <= std::numeric_limits<uint32_t>::max());
            outTotalSize = static_cast<uint32_t>(totalSize);
            return true;
        }

        if (!storageType.isStruct())
            return false;

        const auto& fields = storageType.payloadSymStruct().fields();
        if (elementRefs.size() > fields.size())
            return false;

        outLayout.reserve(elementRefs.size());
        std::vector fieldUsed(fields.size(), false);
        bool        seenNamed = false;
        size_t      nextPos   = 0;
        for (const auto elementRef : elementRefs)
        {
            AstNodeRef     valueRef  = elementRef;
            IdentifierRef  fieldName = IdentifierRef::invalid();
            const AstNode& valueNode = codeGen.node(elementRef);
            if (valueNode.is(AstNodeId::NamedArgument))
            {
                seenNamed = true;
                fieldName = codeGen.idMgr().addIdentifier(codeGen.ctx(), valueNode.codeRef());
                valueRef  = valueNode.cast<AstNamedArgument>().nodeArgRef;
            }
            else if (seenNamed)
            {
                return false;
            }

            size_t fieldIndex = static_cast<size_t>(-1);
            if (fieldName.isValid())
            {
                for (size_t j = 0; j < fields.size(); ++j)
                {
                    const SymbolVariable* field = fields[j];
                    if (!field)
                        continue;
                    if (field->idRef() == fieldName)
                    {
                        fieldIndex = j;
                        break;
                    }
                }
            }
            else
            {
                while (nextPos < fields.size() && (!fields[nextPos] || fieldUsed[nextPos]))
                    ++nextPos;
                fieldIndex = nextPos;
            }

            if (fieldIndex >= fields.size())
                return false;
            if (fieldUsed[fieldIndex])
                return false;

            const SymbolVariable* field = fields[fieldIndex];
            if (!field)
                return false;
            fieldUsed[fieldIndex] = true;
            if (!fieldName.isValid())
                ++nextPos;

            const TypeRef   fieldTypeRef = field->typeRef();
            const TypeInfo& fieldType    = codeGen.typeMgr().get(fieldTypeRef);
            const uint64_t  fieldSize    = fieldType.sizeOf(codeGen.ctx());
            if (!fieldSize)
                continue;

            AggregateElementLayout elem;
            elem.valueRef = valueRef;
            elem.typeRef  = fieldTypeRef;
            elem.offset   = field->offset();
            outLayout.push_back(elem);
        }

        const uint64_t totalSize = storageType.sizeOf(codeGen.ctx());
        SWC_ASSERT(totalSize <= std::numeric_limits<uint32_t>::max());
        outTotalSize = static_cast<uint32_t>(totalSize);
        return true;
    }

    Result emitConcreteLiteralStorageInit(CodeGen& codeGen, TypeRef storageTypeRef, MicroReg dstBaseReg)
    {
        if (storageTypeRef.isInvalid())
            return Result::Continue;

        const TypeInfo& storageType = codeGen.typeMgr().get(storageTypeRef);
        if (!storageType.isArray() && !storageType.isStruct())
            return Result::Continue;
        return CodeGenFunctionHelpers::emitTypeDefaultValue(codeGen, storageTypeRef, dstBaseReg);
    }

    bool tryResolveExistingAggregateElementPayload(CodeGenNodePayload& outPayload, CodeGen& codeGen, AstNodeRef valueRef, TypeRef targetTypeRef)
    {
        const CodeGenNodePayload* existingPayload = codeGen.safePayload(valueRef);
        if (!existingPayload)
            return false;

        if (existingPayload->reg.isValid())
        {
            outPayload = *existingPayload;
            return true;
        }

        const SymbolVariable* storageSym = codeGen.runtimeStorageSymbol(valueRef);
        if (storageSym == nullptr)
            return false;

        outPayload                   = *existingPayload;
        outPayload.runtimeStorageSym = const_cast<SymbolVariable*>(storageSym);
        outPayload.reg               = codeGen.runtimeStorageAddressReg(valueRef);
        outPayload.setIsAddress();
        if (!outPayload.typeRef.isValid())
            outPayload.typeRef = targetTypeRef;
        return true;
    }

    MicroReg aggregateElementAddressReg(CodeGen& codeGen, MicroReg dstBaseReg, uint32_t offset)
    {
        if (!offset)
            return dstBaseReg;

        const MicroReg dstElementReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegReg(dstElementReg, dstBaseReg, MicroOpBits::B64);
        codeGen.builder().emitOpBinaryRegImm(dstElementReg, ApInt(offset, 64), MicroOp::Add, MicroOpBits::B64);
        return dstElementReg;
    }

    void emitAggregateElementStore(CodeGen& codeGen, MicroReg dstElementReg, const CodeGenNodePayload& elementPayload, TypeRef sourceTypeRef, TypeRef targetTypeRef, uint32_t elementSize)
    {
        const MicroOpBits scalarStoreBits = CodeGenTypeHelpers::scalarStoreBits(codeGen.typeMgr().get(targetTypeRef), codeGen.ctx());
        if (scalarStoreBits != MicroOpBits::Zero)
        {
            const MicroReg valueReg = CodeGenMemoryHelpers::materializeScalarPayloadForStore(codeGen, elementPayload, sourceTypeRef, targetTypeRef);
            codeGen.builder().emitLoadMemReg(dstElementReg, 0, valueReg, scalarStoreBits);
            return;
        }

        const MicroOpBits storeBits = CodeGenTypeHelpers::bitsFromStorageSize(elementSize);
        if (elementPayload.isAddress() || storeBits == MicroOpBits::Zero)
        {
            CodeGenMemoryHelpers::emitMemCopy(codeGen, dstElementReg, elementPayload.reg, elementSize);
            return;
        }

        codeGen.builder().emitLoadMemReg(dstElementReg, 0, elementPayload.reg, storeBits);
    }

    TypeRef resolvedLiteralStorageTypeRef(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (const SymbolVariable* storageSym = codeGen.runtimeStorageSymbol(nodeRef); storageSym != nullptr)
        {
            const TypeRef runtimeStorageTypeRef = storageSym->typeRef();
            if (runtimeStorageTypeRef.isValid())
            {
                const TypeInfo& runtimeStorageType = codeGen.typeMgr().get(runtimeStorageTypeRef);
                if (runtimeStorageType.isArray() || runtimeStorageType.isStruct())
                    return runtimeStorageTypeRef;
            }
        }

        const TypeRef storedTypeRef = codeGen.sema().viewStored(nodeRef, SemaNodeViewPartE::Type).typeRef();
        if (storedTypeRef.isValid())
        {
            const TypeInfo& storedType = codeGen.typeMgr().get(storedTypeRef);
            if (storedType.isArray() || storedType.isStruct())
                return storedTypeRef;
        }

        const TypeRef currentTypeRef = codeGen.viewType(nodeRef).typeRef();
        if (currentTypeRef.isValid())
        {
            const TypeInfo& currentType = codeGen.typeMgr().get(currentTypeRef);
            if (currentType.isArray() || currentType.isStruct() || currentType.isAggregateArray() || currentType.isAggregateStruct())
                return currentTypeRef;
        }

        if (storedTypeRef.isValid())
            return storedTypeRef;
        return currentTypeRef;
    }

    ConstantRef materializeBorrowedStorageConstant(CodeGen& codeGen, ConstantRef cstRef, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return ConstantRef::invalid();

        const TypeInfo& typeInfo       = codeGen.typeMgr().get(typeRef);
        TypeRef         storageTypeRef = typeInfo.unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
        if (storageTypeRef.isInvalid())
            storageTypeRef = typeRef;
        if (cstRef.isValid())
            storageTypeRef = SemaHelpers::deduceConcretizedAggregateLiteralType(codeGen.sema(), storageTypeRef, cstRef);

        const TypeInfo& storageType = codeGen.typeMgr().get(storageTypeRef);
        if (!storageType.isStruct() && !storageType.isArray() && !storageType.isAggregateStruct() && !storageType.isAggregateArray())
            return ConstantRef::invalid();

        const uint64_t storageSize = storageType.sizeOf(codeGen.ctx());
        SWC_ASSERT(storageSize <= std::numeric_limits<uint32_t>::max());

        SmallVector<std::byte> storageBytes;
        storageBytes.resize(storageSize);
        if (storageSize)
            SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(codeGen.sema(), std::span{storageBytes.data(), storageBytes.size()}, cstRef, storageTypeRef) == Result::Continue);

        return CodeGenConstantHelpers::materializeStaticPayloadConstant(codeGen, storageTypeRef, std::span{storageBytes.data(), storageBytes.size()});
    }

    void emitPointerConstant(CodeGen& codeGen, MicroReg reg, const uint64_t value, ConstantRef cstRef)
    {
        if (!value)
        {
            codeGen.builder().emitLoadRegImm(reg, ApInt(0, 64), MicroOpBits::B64);
            return;
        }

        DataSegmentRef sourceRef;
        if (codeGen.cstMgr().resolveConstantDataSegmentRef(sourceRef, cstRef, reinterpret_cast<const void*>(value)))
            codeGen.builder().emitLoadRegPtrReloc(reg, value, cstRef);
        else
            codeGen.builder().emitLoadRegPtrImm(reg, value);
    }

    Result emitConstantToPayload(CodeGen& codeGen, CodeGenNodePayload& payload, ConstantRef cstRef, const ConstantValue& cst, TypeRef targetTypeRef, AstNodeRef storageNodeRef = AstNodeRef::invalid())
    {
        MicroBuilder& builder = codeGen.builder();

        switch (cst.kind())
        {
            case ConstantKind::Bool:
            {
                builder.emitLoadRegImm(payload.reg, ApInt(cst.getBool() ? 1 : 0, 64), MicroOpBits::B64);
                payload.setIsValue();
                return Result::Continue;
            }

            case ConstantKind::Char:
            {
                builder.emitLoadRegImm(payload.reg, ApInt(cst.getChar(), 64), MicroOpBits::B64);
                payload.setIsValue();
                return Result::Continue;
            }

            case ConstantKind::Rune:
            {
                builder.emitLoadRegImm(payload.reg, ApInt(cst.getRune(), 64), MicroOpBits::B64);
                payload.setIsValue();
                return Result::Continue;
            }

            case ConstantKind::Int:
            {
                const ApsInt& val = cst.getInt();
                SWC_ASSERT(val.fits64());
                builder.emitLoadRegImm(payload.reg, ApInt(static_cast<uint64_t>(val.asI64()), 64), MicroOpBits::B64);
                payload.setIsValue();
                return Result::Continue;
            }

            case ConstantKind::Float:
            {
                const ApFloat& value = cst.getFloat();
                payload.reg          = codeGen.nextVirtualFloatRegister();
                if (value.bitWidth() == 32)
                {
                    const double   widenedValue = value.asFloat();
                    const uint64_t widenedBits  = std::bit_cast<uint64_t>(widenedValue);
                    const MicroReg widenedReg   = codeGen.nextVirtualFloatRegister();
                    builder.emitLoadRegImm(widenedReg, ApInt(widenedBits, 64), MicroOpBits::B64);
                    builder.emitClearReg(payload.reg, MicroOpBits::B32);
                    builder.emitOpBinaryRegReg(payload.reg, widenedReg, MicroOp::ConvertFloatToFloat, MicroOpBits::B64);
                    payload.setIsValue();
                    return Result::Continue;
                }

                if (value.bitWidth() == 64)
                {
                    const auto bits = std::bit_cast<uint64_t>(value.asDouble());
                    builder.emitLoadRegImm(payload.reg, ApInt(bits, 64), MicroOpBits::B64);
                    payload.setIsValue();
                    return Result::Continue;
                }

                SWC_UNREACHABLE();
            }

            case ConstantKind::String:
            {
                const std::string_view value               = cst.getString();
                const ConstantRef      runtimeStringCstRef = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, codeGen.typeMgr().typeString(), value.data(), value.size());
                SWC_ASSERT(runtimeStringCstRef.isValid());
                const ConstantValue& runtimeStringCst = codeGen.cstMgr().get(runtimeStringCstRef);
                builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(runtimeStringCst.getStruct().data()), runtimeStringCstRef);
                payload.setIsValue();
                return Result::Continue;
            }

            case ConstantKind::ValuePointer:
            {
                emitPointerConstant(codeGen, payload.reg, cst.getValuePointer(), cstRef);
                payload.setIsValue();
                return Result::Continue;
            }

            case ConstantKind::BlockPointer:
            {
                emitPointerConstant(codeGen, payload.reg, cst.getBlockPointer(), cstRef);
                payload.setIsValue();
                return Result::Continue;
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
                        SWC_RESULT(ConstantLower::lowerToBytes(codeGen.sema(), std::span{typedNullBytes.data(), typedNullBytes.size()}, cstRef, targetTypeRef));

                        const ConstantRef    typedNullCstRef = CodeGenConstantHelpers::materializeStaticPayloadConstant(codeGen, targetTypeRef, std::span{typedNullBytes.data(), typedNullBytes.size()});
                        const ConstantValue& typedNullCst    = codeGen.cstMgr().get(typedNullCstRef);
                        builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(typedNullCst.getStruct().data()), typedNullCstRef);
                        payload.setIsValue();
                        return Result::Continue;
                    }
                }

                builder.emitLoadRegImm(payload.reg, ApInt(0, 64), MicroOpBits::B64);
                payload.setIsValue();
                return Result::Continue;
            }

            case ConstantKind::TypeValue:
            {
                ConstantRef typeInfoCstRef = ConstantRef::invalid();
                SWC_RESULT(codeGen.cstMgr().makeTypeInfo(codeGen.sema(), typeInfoCstRef, cst.getTypeValue(), codeGen.curNodeRef()));
                SWC_ASSERT(typeInfoCstRef.isValid());

                const ConstantValue& typeInfoCst = codeGen.cstMgr().get(typeInfoCstRef);
                SWC_ASSERT(typeInfoCst.isValuePointer());

                builder.emitLoadRegPtrReloc(payload.reg, typeInfoCst.getValuePointer(), typeInfoCstRef);
                payload.typeRef = codeGen.typeMgr().typeTypeInfo();
                payload.setIsValue();
                return Result::Continue;
            }

            case ConstantKind::EnumValue:
                return emitConstantToPayload(codeGen, payload, cst.getEnumValue(), codeGen.cstMgr().get(cst.getEnumValue()), targetTypeRef);

            case ConstantKind::Struct:
            {
                bool handled = false;
                SWC_RESULT(tryEmitRuntimeStorageConstant(codeGen, payload, storageNodeRef, cstRef, cst.typeRef(), handled));
                if (handled)
                    return Result::Continue;

                ConstantRef safeCstRef = CodeGenConstantHelpers::ensureStaticPayloadConstant(codeGen, cstRef, cst.typeRef());
                if (safeCstRef.isInvalid())
                    safeCstRef = materializeBorrowedStorageConstant(codeGen, cstRef, cst.typeRef());
                if (safeCstRef.isInvalid())
                    return raiseConstantMaterializationError(codeGen, "cannot materialize a struct constant payload");
                const ConstantValue&             safeCst     = codeGen.cstMgr().get(safeCstRef);
                const std::span<const std::byte> structBytes = safeCst.getStruct();
                if (targetTypeRef.isValid())
                {
                    const TypeInfo& targetType = codeGen.typeMgr().get(targetTypeRef);
                    if (targetType.isReference())
                    {
                        builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(structBytes.data()), safeCstRef);
                        payload.setIsValue();
                        return Result::Continue;
                    }
                }

                const uint64_t storageSize = cst.type(codeGen.ctx()).sizeOf(codeGen.ctx());
                SWC_ASSERT(structBytes.size() == storageSize);
                builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(structBytes.data()), safeCstRef);
                payload.setIsAddress();
                return Result::Continue;
            }

            case ConstantKind::Array:
            {
                bool handled = false;
                SWC_RESULT(tryEmitRuntimeStorageConstant(codeGen, payload, storageNodeRef, cstRef, cst.typeRef(), handled));
                if (handled)
                    return Result::Continue;

                const std::span<const std::byte> arrayBytes = cst.getArray();
                if (targetTypeRef.isValid())
                {
                    const TypeInfo& targetType = codeGen.typeMgr().get(targetTypeRef);
                    if (targetType.isString())
                    {
                        const ConstantRef runtimeStringCstRef = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, targetTypeRef, arrayBytes.data(), arrayBytes.size());
                        SWC_ASSERT(runtimeStringCstRef.isValid());
                        const ConstantValue& runtimeStringCst = codeGen.cstMgr().get(runtimeStringCstRef);
                        builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(runtimeStringCst.getStruct().data()), runtimeStringCstRef);
                        payload.setIsValue();
                        return Result::Continue;
                    }

                    if (targetType.isSlice())
                    {
                        const TypeInfo&   elementType     = codeGen.typeMgr().get(targetType.payloadTypeRef());
                        const TypeInfo&   sourceArrayType = cst.type(codeGen.ctx());
                        const ConstantRef safeArrayCstRef = CodeGenConstantHelpers::ensureStaticPayloadConstant(codeGen, cstRef, cst.typeRef());
                        if (safeArrayCstRef.isInvalid())
                            return raiseConstantMaterializationError(codeGen, "cannot materialize an array constant payload");
                        const ConstantValue& safeArrayCst       = codeGen.cstMgr().get(safeArrayCstRef);
                        const ConstantRef    runtimeSliceCstRef = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, targetTypeRef, safeArrayCst.getArray().data(), sliceCountFromArrayCast(codeGen, sourceArrayType, elementType));
                        SWC_ASSERT(runtimeSliceCstRef.isValid());
                        const ConstantValue& runtimeSliceCst = codeGen.cstMgr().get(runtimeSliceCstRef);
                        builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(runtimeSliceCst.getStruct().data()), runtimeSliceCstRef);
                        payload.setIsValue();
                        return Result::Continue;
                    }
                }

                const ConstantRef safeCstRef = materializeBorrowedStorageConstant(codeGen, cstRef, cst.typeRef());
                if (safeCstRef.isInvalid())
                    return raiseConstantMaterializationError(codeGen, "cannot materialize an array constant payload");
                const ConstantValue& safeCst = codeGen.cstMgr().get(safeCstRef);

                const uint64_t storageSize = cst.type(codeGen.ctx()).sizeOf(codeGen.ctx());
                SWC_ASSERT(safeCst.getArray().size() == storageSize);
                builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(safeCst.getArray().data()), safeCstRef);
                payload.setIsAddress();
                return Result::Continue;
            }

            case ConstantKind::Slice:
            {
                const std::span<const std::byte> sliceBytes = cst.getSlice();
                const TypeInfo&                  sliceType  = cst.type(codeGen.ctx());
                SWC_ASSERT(sliceType.isSlice());
                const uint64_t    elementCount    = cst.getSliceCount();
                const ConstantRef safeArrayCstRef = CodeGenConstantHelpers::materializeStaticArrayBufferConstant(codeGen, sliceType.payloadTypeRef(), sliceBytes, elementCount);
                if (safeArrayCstRef.isInvalid())
                    return raiseConstantMaterializationError(codeGen, "cannot materialize a slice constant payload");
                const ConstantValue& safeArrayCst       = codeGen.cstMgr().get(safeArrayCstRef);
                const void*          targetPtr          = sliceBytes.empty() ? sliceBytes.data() : safeArrayCst.getArray().data();
                const ConstantRef    runtimeSliceCstRef = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, cst.typeRef(), targetPtr, elementCount);
                SWC_ASSERT(runtimeSliceCstRef.isValid());
                const ConstantValue& runtimeSliceCst = codeGen.cstMgr().get(runtimeSliceCstRef);
                builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(runtimeSliceCst.getStruct().data()), runtimeSliceCstRef);
                payload.setIsValue();
                return Result::Continue;
            }

            case ConstantKind::AggregateStruct:
            case ConstantKind::AggregateArray:
            {
                bool handled = false;
                SWC_RESULT(tryEmitRuntimeStorageConstant(codeGen, payload, storageNodeRef, cstRef, targetTypeRef, handled));
                if (handled)
                    return Result::Continue;

                const ConstantRef storageCstRef = materializeBorrowedStorageConstant(codeGen, cstRef, targetTypeRef);
                if (storageCstRef.isInvalid())
                    return raiseConstantMaterializationError(codeGen, "cannot materialize an aggregate constant payload");
                const ConstantValue& storageCst = codeGen.cstMgr().get(storageCstRef);

                if (storageCst.isArray())
                {
                    builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(storageCst.getArray().data()), storageCstRef);
                    payload.setIsAddress();
                    return Result::Continue;
                }

                SWC_ASSERT(storageCst.isStruct());
                builder.emitLoadRegPtrReloc(payload.reg, reinterpret_cast<uint64_t>(storageCst.getStruct().data()), storageCstRef);
                payload.setIsAddress();
                return Result::Continue;
            }

            default:
                SWC_UNREACHABLE();
        }
    }

    Result resolveConstantAggregateElementPayload(CodeGenNodePayload& outPayload, CodeGen& codeGen, AstNodeRef valueRef, TypeRef targetTypeRef)
    {
        const SemaNodeView valueView = codeGen.viewTypeConstant(valueRef);
        if (!valueView.cstRef().isValid())
            SWC_INTERNAL_CHECK(false);

        outPayload         = {};
        outPayload.reg     = codeGen.nextVirtualRegisterForType(targetTypeRef);
        outPayload.typeRef = targetTypeRef;
        outPayload.setIsValue();
        return emitConstantToPayload(codeGen, outPayload, valueView.cstRef(), codeGen.cstMgr().get(valueView.cstRef()), targetTypeRef);
    }

    Result resolveAggregateElementPayload(CodeGenNodePayload& outPayload, CodeGen& codeGen, AstNodeRef valueRef, TypeRef targetTypeRef)
    {
        if (tryResolveExistingAggregateElementPayload(outPayload, codeGen, valueRef, targetTypeRef))
            return Result::Continue;

        return resolveConstantAggregateElementPayload(outPayload, codeGen, valueRef, targetTypeRef);
    }

    Result emitAggregateLiteralPayload(CodeGen& codeGen, AstNodeRef nodeRef, std::span<const AstNodeRef> elementRefs, TypeRef aggregateTypeRef)
    {
        SmallVector<AggregateElementLayout> layout;
        uint32_t                            totalSize = 0;
        const bool                          hasLayout = computeLiteralLayout(codeGen, aggregateTypeRef, elementRefs, layout, totalSize);
        SWC_INTERNAL_CHECK(hasLayout);
        SWC_INTERNAL_CHECK(totalSize == codeGen.typeMgr().get(aggregateTypeRef).sizeOf(codeGen.ctx()));

        const MicroReg  dstBaseReg  = codeGen.runtimeStorageAddressReg(nodeRef);
        const TypeInfo& storageType = codeGen.typeMgr().get(aggregateTypeRef);
        // Concrete arrays/structs start from their default storage so omitted literal elements keep the
        // correct zeroed or default-initialized bytes.
        if (storageType.isArray() || storageType.isStruct())
            SWC_RESULT(emitConcreteLiteralStorageInit(codeGen, aggregateTypeRef, dstBaseReg));

        for (const AggregateElementLayout& entry : layout)
        {
            CodeGenNodePayload elementPayload;
            SWC_RESULT(resolveAggregateElementPayload(elementPayload, codeGen, entry.valueRef, entry.typeRef));
            const uint64_t elementSize = codeGen.typeMgr().get(entry.typeRef).sizeOf(codeGen.ctx());
            if (!elementSize)
                continue;

            SWC_ASSERT(elementSize <= std::numeric_limits<uint32_t>::max());
            const MicroReg dstElementReg = aggregateElementAddressReg(codeGen, dstBaseReg, entry.offset);
            const TypeRef  sourceTypeRef = elementPayload.effectiveTypeRef(entry.typeRef);
            emitAggregateElementStore(codeGen, dstElementReg, elementPayload, sourceTypeRef, entry.typeRef, static_cast<uint32_t>(elementSize));
        }

        codeGen.setPayloadAddressReg(nodeRef, dstBaseReg, aggregateTypeRef);
        return Result::Continue;
    }

    bool resolveRuntimeArrayFillLayout(uint32_t& outElementSize, uint32_t& outElementCount, CodeGen& codeGen, TypeRef arrayTypeRef, TypeRef elementTypeRef)
    {
        outElementSize  = 0;
        outElementCount = 0;
        if (!arrayTypeRef.isValid() || !elementTypeRef.isValid())
            return false;

        const TypeInfo& arrayType = codeGen.typeMgr().get(arrayTypeRef);
        if (!arrayType.isArray())
            return false;

        const uint64_t elementSize = codeGen.typeMgr().get(elementTypeRef).sizeOf(codeGen.ctx());
        const uint64_t totalSize   = arrayType.sizeOf(codeGen.ctx());
        if (!elementSize || !totalSize)
            return false;
        if (totalSize % elementSize)
            return false;

        const uint64_t elementCount = totalSize / elementSize;
        SWC_ASSERT(elementSize <= std::numeric_limits<uint32_t>::max());
        SWC_ASSERT(elementCount <= std::numeric_limits<uint32_t>::max());
        outElementSize  = static_cast<uint32_t>(elementSize);
        outElementCount = static_cast<uint32_t>(elementCount);
        return true;
    }

    Result tryEmitRuntimeArrayFill(CodeGen& codeGen, AstNodeRef nodeRef, const CodeGenNodePayload& payload, TypeRef targetTypeRef, bool& outHandled)
    {
        outHandled = false;
        if (!payload.hasRuntimeArrayFill() || payload.runtimeStorageSym == nullptr)
            return Result::Continue;

        uint32_t elementSize  = 0;
        uint32_t elementCount = 0;
        if (!resolveRuntimeArrayFillLayout(elementSize, elementCount, codeGen, targetTypeRef, payload.runtimeArrayFillTypeRef))
            return Result::Continue;

        CodeGenNodePayload fillPayload;
        fillPayload.reg = payload.reg;
        SWC_RESULT(emitConstantToPayload(codeGen, fillPayload, payload.runtimeArrayFillCstRef, codeGen.cstMgr().get(payload.runtimeArrayFillCstRef), payload.runtimeArrayFillTypeRef));

        const MicroReg dstReg = codeGen.runtimeStorageAddressReg(nodeRef);
        if (fillPayload.isValue() && (elementSize == 1 || elementSize == 2 || elementSize == 4 || elementSize == 8))
            CodeGenMemoryHelpers::emitMemFill(codeGen, dstReg, fillPayload.reg, elementSize, elementCount);
        else
            CodeGenMemoryHelpers::emitMemRepeatCopy(codeGen, dstReg, fillPayload.reg, elementSize, elementCount);

        codeGen.setPayloadAddressReg(nodeRef, dstReg, targetTypeRef);
        outHandled = true;
        return Result::Continue;
    }
}

Result CodeGen::emitConstant(AstNodeRef nodeRef)
{
    const CodeGenNodePayload* existingPayload = safePayload(nodeRef);
    if (existingPayload && existingPayload->reg.isValid())
        return Result::Continue;

    const SemaNodeView view = viewTypeConstant(nodeRef);
    if (view.cstRef().isInvalid())
        return Result::Continue;

    const ConstantValue& cst = cstMgr().get(view.cstRef());
    if (cst.kind() == ConstantKind::Undefined)
        return Result::Continue;

    CodeGenNodePayload& payload = setPayload(nodeRef, view.typeRef());
    bool                handled = false;
    SWC_RESULT(tryEmitRuntimeArrayFill(*this, nodeRef, payload, view.typeRef(), handled));
    if (handled)
        return Result::SkipChildren;

    SWC_RESULT(emitConstantToPayload(*this, payload, view.cstRef(), cst, view.typeRef(), nodeRef));
    return Result::SkipChildren;
}

Result AstNullLiteral::codeGenPostNode(CodeGen& codeGen)
{
    const CodeGenNodePayload* existingPayload = codeGen.safePayload(codeGen.curNodeRef());
    if (existingPayload && existingPayload->reg.isValid())
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
            SWC_RESULT(ConstantLower::lowerToBytes(codeGen.sema(), std::span{typedNullBytes.data(), typedNullBytes.size()}, codeGen.cstMgr().cstNull(), targetTypeRef));

            const ConstantRef         typedNullCstRef = CodeGenConstantHelpers::materializeStaticPayloadConstant(codeGen, targetTypeRef, std::span{typedNullBytes.data(), typedNullBytes.size()});
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
    CodeGenNodePayload& payload   = codeGen.inheritPayload(codeGen.curNodeRef(), nodeExprRef, codeGen.transparentPayloadTypeRef());
    const SemaNodeView  view      = codeGen.curViewType();
    const SemaNodeView  childView = codeGen.viewType(nodeExprRef);
    if (view.type() && view.type()->isReference() && payload.isAddress() && childView.type() && !childView.type()->isReference())
        payload.setIsValue();
    return Result::Continue;
}

Result AstArrayLiteral::codeGenPostNode(CodeGen& codeGen) const
{
    SmallVector<AstNodeRef> elementRefs;
    collectChildren(elementRefs, codeGen.ast());

    const TypeRef aggregateTypeRef = resolvedLiteralStorageTypeRef(codeGen, codeGen.curNodeRef());
    return emitAggregateLiteralPayload(codeGen, codeGen.curNodeRef(), elementRefs.span(), aggregateTypeRef);
}

Result AstStructLiteral::codeGenPostNode(CodeGen& codeGen) const
{
    SmallVector<AstNodeRef> elementRefs;
    collectChildren(elementRefs, codeGen.ast());

    const TypeRef aggregateTypeRef = resolvedLiteralStorageTypeRef(codeGen, codeGen.curNodeRef());
    return emitAggregateLiteralPayload(codeGen, codeGen.curNodeRef(), elementRefs.span(), aggregateTypeRef);
}

Result AstStructInitializerList::codeGenPostNode(CodeGen& codeGen) const
{
    SmallVector<AstNodeRef> elementRefs;
    codeGen.ast().appendNodes(elementRefs, spanArgsRef);

    const TypeRef aggregateTypeRef = resolvedLiteralStorageTypeRef(codeGen, codeGen.curNodeRef());
    return emitAggregateLiteralPayload(codeGen, codeGen.curNodeRef(), elementRefs.span(), aggregateTypeRef);
}

SWC_END_NAMESPACE();
