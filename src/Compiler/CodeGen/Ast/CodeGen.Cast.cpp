#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint64_t addPayloadToConstantManagerAndGetAddress(CodeGen& codeGen, ByteSpan payload)
    {
        const std::string_view payloadView(reinterpret_cast<const char*>(payload.data()), payload.size());
        const std::string_view storedPayload = codeGen.cstMgr().addPayloadBuffer(payloadView);
        return reinterpret_cast<uint64_t>(storedPayload.data());
    }

    ConstantRef makeBorrowedStructConstant(CodeGen& codeGen, TypeRef typeRef, ByteSpan payload)
    {
        const std::string_view storedPayload = codeGen.cstMgr().addPayloadBuffer(asStringView(payload));
        const ByteSpan         storedBytes   = asByteSpan(storedPayload);
        const ConstantValue    cst           = ConstantValue::makeStructBorrowed(codeGen.ctx(), typeRef, storedBytes);
        return codeGen.cstMgr().addConstant(codeGen.ctx(), cst);
    }

    ConstantRef makeBorrowedRuntimeBufferConstant(CodeGen& codeGen, TypeRef typeRef, const void* targetPtr, uint64_t count)
    {
        uint32_t targetShardIndex = 0;
        Ref      targetOffset     = INVALID_REF;
        if (targetPtr)
            targetOffset = codeGen.cstMgr().findDataSegmentRef(targetShardIndex, targetPtr);

        if (targetPtr && targetOffset == INVALID_REF)
            return ConstantRef::invalid();

        DataSegment& segment         = codeGen.cstMgr().shardDataSegment(targetOffset == INVALID_REF ? 0 : targetShardIndex);
        const auto [offset, storage] = segment.reserveBytes(sizeof(Runtime::Slice<std::byte>), alignof(Runtime::Slice<std::byte>), true);
        auto* const runtimeValue     = reinterpret_cast<Runtime::Slice<std::byte>*>(storage);
        runtimeValue->ptr            = const_cast<std::byte*>(reinterpret_cast<const std::byte*>(targetPtr));
        runtimeValue->count          = count;

        if (targetOffset != INVALID_REF)
            segment.addRelocation(offset + offsetof(Runtime::Slice<std::byte>, ptr), targetOffset);

        const ConstantValue runtimeValueCst = ConstantValue::makeStructBorrowed(codeGen.ctx(), typeRef, ByteSpan{storage, sizeof(Runtime::Slice<std::byte>)});
        return codeGen.cstMgr().addConstant(codeGen.ctx(), runtimeValueCst);
    }

    CodeGenNodePayload resolveCastRuntimeStoragePayload(CodeGen& codeGen, const SymbolVariable& storageSym)
    {
        if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(storageSym))
            return *symbolPayload;

        SWC_ASSERT(storageSym.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack));
        SWC_ASSERT(codeGen.localStackBaseReg().isValid());

        CodeGenNodePayload localPayload;
        localPayload.typeRef = storageSym.typeRef();
        localPayload.setIsAddress();
        if (!storageSym.offset())
        {
            localPayload.reg = codeGen.localStackBaseReg();
        }
        else
        {
            MicroBuilder& builder = codeGen.builder();
            localPayload.reg      = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(localPayload.reg, codeGen.localStackBaseReg(), MicroOpBits::B64);
            builder.emitOpBinaryRegImm(localPayload.reg, ApInt(storageSym.offset(), 64), MicroOp::Add, MicroOpBits::B64);
        }

        codeGen.setVariablePayload(storageSym, localPayload);
        return localPayload;
    }

    MicroReg castRuntimeStorageAddressReg(CodeGen& codeGen)
    {
        const auto* payload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
        SWC_ASSERT(payload != nullptr);
        SWC_ASSERT(payload->runtimeStorageSym != nullptr);
        const CodeGenNodePayload storagePayload = resolveCastRuntimeStoragePayload(codeGen, *(payload->runtimeStorageSym));
        SWC_ASSERT(storagePayload.isAddress());
        return storagePayload.reg;
    }

    MicroOpBits castPayloadBits(const TypeInfo& typeInfo)
    {
        if (typeInfo.isFloat())
        {
            const uint32_t floatBits = typeInfo.payloadFloatBits() ? typeInfo.payloadFloatBits() : 64;
            return microOpBitsFromBitWidth(floatBits);
        }

        if (typeInfo.isBool())
            return MicroOpBits::B8;

        if (typeInfo.isIntLike())
        {
            const uint32_t intBits = typeInfo.payloadIntLikeBits() ? typeInfo.payloadIntLikeBits() : 64;
            return microOpBitsFromBitWidth(intBits);
        }

        return MicroOpBits::Zero;
    }

    bool anyCastAsValueBits(CodeGen& codeGen, const TypeInfo& dstType, MicroOpBits& outBits)
    {
        outBits = MicroOpBits::Zero;

        if (dstType.isFloat() || dstType.isIntLike() || dstType.isBool())
        {
            outBits = castPayloadBits(dstType);
            return outBits != MicroOpBits::Zero;
        }

        const bool pointerLikeValue =
            dstType.isAnyPointer() ||
            dstType.isEnum() ||
            dstType.isTypeInfo() ||
            dstType.isFunction() ||
            dstType.isCString();
        if (!pointerLikeValue)
            return false;

        const uint64_t dstSize = dstType.sizeOf(codeGen.ctx());
        if (dstSize != 1 && dstSize != 2 && dstSize != 4 && dstSize != 8)
            return false;

        outBits = microOpBitsFromChunkSize(static_cast<uint32_t>(dstSize));
        return true;
    }

    Result emitArrayToStringCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef, const TypeInfo& srcType)
    {
        MicroBuilder&             builder    = codeGen.builder();
        const CodeGenNodePayload& srcPayload = codeGen.payload(srcNodeRef);

        const SemaNodeView srcConstView = codeGen.viewConstant(srcNodeRef);
        if (srcConstView.hasConstant())
        {
            const ConstantValue& srcConst = codeGen.cstMgr().get(srcConstView.cstRef());
            if (srcConst.isArray())
            {
                const ByteSpan    arrayBytes       = srcConst.getArray();
                const ConstantRef runtimeStringRef = makeBorrowedRuntimeBufferConstant(codeGen, dstTypeRef, arrayBytes.data(), arrayBytes.size());
                SWC_ASSERT(runtimeStringRef.isValid());
                const ConstantValue&      runtimeStringCst = codeGen.cstMgr().get(runtimeStringRef);
                const CodeGenNodePayload& dstPayload       = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
                builder.emitLoadRegPtrReloc(dstPayload.reg, reinterpret_cast<uint64_t>(runtimeStringCst.getStruct().data()), runtimeStringRef);
                return Result::Continue;
            }
        }

        const uint64_t length          = srcType.sizeOf(codeGen.ctx());
        const MicroReg runtimeValueReg = castRuntimeStorageAddressReg(codeGen);

        MicroReg srcDataReg = srcPayload.reg;
        if (!srcPayload.isAddress())
        {
            srcDataReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(srcDataReg, srcPayload.reg, MicroOpBits::B64);
        }

        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::String, ptr), srcDataReg, MicroOpBits::B64);

        const MicroReg lengthReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(lengthReg, ApInt(length, 64), MicroOpBits::B64);
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::String, length), lengthReg, MicroOpBits::B64);

        const CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        builder.emitLoadRegReg(dstPayload.reg, runtimeValueReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitArrayToSliceCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef, const TypeInfo& srcType, const TypeInfo& dstType)
    {
        SWC_ASSERT(dstType.isSlice());

        const TypeInfo& dstElementType = codeGen.typeMgr().get(dstType.payloadTypeRef());
        const uint64_t  totalSize      = srcType.sizeOf(codeGen.ctx());
        const uint64_t  elementSize    = dstElementType.sizeOf(codeGen.ctx());
        const uint64_t  elementCount   = elementSize ? totalSize / elementSize : 0;

        MicroBuilder&             builder    = codeGen.builder();
        const CodeGenNodePayload& srcPayload = codeGen.payload(srcNodeRef);

        const SemaNodeView srcConstView = codeGen.viewConstant(srcNodeRef);
        if (srcConstView.hasConstant())
        {
            const ConstantValue& srcConst = codeGen.cstMgr().get(srcConstView.cstRef());
            if (srcConst.isArray())
            {
                const ByteSpan    arrayBytes      = srcConst.getArray();
                const ConstantRef runtimeSliceRef = makeBorrowedRuntimeBufferConstant(codeGen, dstTypeRef, arrayBytes.data(), elementCount);
                SWC_ASSERT(runtimeSliceRef.isValid());
                const ConstantValue&      runtimeSliceCst = codeGen.cstMgr().get(runtimeSliceRef);
                const CodeGenNodePayload& dstPayload      = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
                builder.emitLoadRegPtrReloc(dstPayload.reg, reinterpret_cast<uint64_t>(runtimeSliceCst.getStruct().data()), runtimeSliceRef);
                return Result::Continue;
            }
        }

        const MicroReg runtimeValueReg = castRuntimeStorageAddressReg(codeGen);

        MicroReg srcDataReg = srcPayload.reg;
        if (!srcPayload.isAddress())
        {
            srcDataReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(srcDataReg, srcPayload.reg, MicroOpBits::B64);
        }

        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::Slice<std::byte>, ptr), srcDataReg, MicroOpBits::B64);

        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(countReg, ApInt(elementCount, 64), MicroOpBits::B64);
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::Slice<std::byte>, count), countReg, MicroOpBits::B64);

        const CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        builder.emitLoadRegReg(dstPayload.reg, runtimeValueReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitAnyCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef)
    {
        if (dstTypeRef.isInvalid())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef);
            return Result::Continue;
        }

        const CodeGenNodePayload& srcPayload = codeGen.payload(srcNodeRef);

        const SemaNodeView srcView = codeGen.viewType(srcNodeRef);
        SWC_ASSERT(srcView.type());
        if (!srcView.type()->isAny())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        const TypeInfo& dstType = codeGen.typeMgr().get(dstTypeRef);
        if (dstType.isAny())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        SWC_ASSERT(srcPayload.isAddress());

        MicroBuilder&  builder      = codeGen.builder();
        const MicroReg valueAddrReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(valueAddrReg, srcPayload.reg, offsetof(Runtime::Any, value), MicroOpBits::B64);

        if (dstType.isString() || dstType.isSlice() || dstType.isInterface() || dstType.isAnyVariadic())
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(dstPayload.reg, valueAddrReg, MicroOpBits::B64);
            return Result::Continue;
        }

        if (dstType.isReference() || dstType.isMoveReference())
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(dstPayload.reg, valueAddrReg, MicroOpBits::B64);
            return Result::Continue;
        }

        auto valueBits = MicroOpBits::Zero;
        if (anyCastAsValueBits(codeGen, dstType, valueBits))
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitLoadRegMem(dstPayload.reg, valueAddrReg, 0, valueBits);
            return Result::Continue;
        }

        CodeGenNodePayload& dstPayload = codeGen.setPayloadAddress(codeGen.curNodeRef(), dstTypeRef);
        dstPayload.reg                 = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(dstPayload.reg, valueAddrReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitNumericCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef)
    {
        MicroBuilder&             builder    = codeGen.builder();
        const CodeGenNodePayload& srcPayload = codeGen.payload(srcNodeRef);

        TypeRef sourceTypeRef = codeGen.sema().viewStored(srcNodeRef, SemaNodeViewPartE::Type).typeRef();
        if (!sourceTypeRef.isValid())
            sourceTypeRef = srcPayload.typeRef;

        if (dstTypeRef.isInvalid())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef);
            return Result::Continue;
        }

        if (!sourceTypeRef.isValid())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        if (codeGen.typeMgr().get(sourceTypeRef).isAny())
            return emitAnyCast(codeGen, srcNodeRef, dstTypeRef);

        const TypeInfo& srcType = codeGen.typeMgr().get(sourceTypeRef);
        const TypeInfo& dstType = codeGen.typeMgr().get(dstTypeRef);
        if (srcType.isNull() && dstType.isPointerLike())
        {
            const uint64_t dstSize = dstType.sizeOf(codeGen.ctx());
            if (dstSize <= sizeof(uint64_t))
            {
                codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
                return Result::Continue;
            }

            SWC_ASSERT(dstSize <= std::numeric_limits<uint32_t>::max());
            SmallVector<std::byte> typedNullBytes;
            typedNullBytes.resize(dstSize);
            std::memset(typedNullBytes.data(), 0, typedNullBytes.size());

            const SemaNodeView srcConstView = codeGen.viewTypeConstant(srcNodeRef);
            const ConstantRef  nullCstRef   = srcConstView.cstRef().isValid() ? srcConstView.cstRef() : codeGen.cstMgr().cstNull();
            ConstantLower::lowerToBytes(codeGen.sema(), ByteSpanRW{typedNullBytes.data(), typedNullBytes.size()}, nullCstRef, dstTypeRef);

            const ConstantRef         typedNullCstRef = makeBorrowedStructConstant(codeGen, dstTypeRef, ByteSpan{typedNullBytes.data(), typedNullBytes.size()});
            const ConstantValue&      typedNullCst    = codeGen.cstMgr().get(typedNullCstRef);
            const CodeGenNodePayload& dstPayload      = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            builder.emitLoadRegPtrReloc(dstPayload.reg, reinterpret_cast<uint64_t>(typedNullCst.getStruct().data()), typedNullCstRef);
            return Result::Continue;
        }

        if (dstType.isString() && srcType.isArray())
            return emitArrayToStringCast(codeGen, srcNodeRef, dstTypeRef, srcType);
        if (dstType.isSlice() && srcType.isArray())
            return emitArrayToSliceCast(codeGen, srcNodeRef, dstTypeRef, srcType, dstType);

        if (dstType.isAny() && !srcType.isAny())
        {
            const auto* castPayload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
            if (!castPayload || castPayload->runtimeStorageSym == nullptr)
            {
                codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
                return Result::Continue;
            }

            const MicroReg runtimeAnyReg = castRuntimeStorageAddressReg(codeGen);

            MicroReg valuePtrReg = srcPayload.reg;
            if (!srcPayload.isAddress())
            {
                auto srcValueBits = MicroOpBits::Zero;
                if (!anyCastAsValueBits(codeGen, srcType, srcValueBits))
                {
                    codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
                    return Result::Continue;
                }

                valuePtrReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(valuePtrReg, runtimeAnyReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(valuePtrReg, ApInt(sizeof(Runtime::Any), 64), MicroOp::Add, MicroOpBits::B64);
                builder.emitLoadMemReg(valuePtrReg, 0, srcPayload.reg, srcValueBits);
            }

            builder.emitLoadMemReg(runtimeAnyReg, offsetof(Runtime::Any, value), valuePtrReg, MicroOpBits::B64);

            ConstantRef typeInfoCstRef = ConstantRef::invalid();
            SWC_RESULT(codeGen.cstMgr().makeTypeInfo(codeGen.sema(), typeInfoCstRef, sourceTypeRef, codeGen.curNodeRef()));
            const ConstantValue& typeInfoCst = codeGen.cstMgr().get(typeInfoCstRef);
            SWC_ASSERT(typeInfoCst.isValuePointer());

            const MicroReg typeInfoReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegPtrReloc(typeInfoReg, typeInfoCst.getValuePointer(), typeInfoCstRef);
            builder.emitLoadMemReg(runtimeAnyReg, offsetof(Runtime::Any, type), typeInfoReg, MicroOpBits::B64);

            CodeGenNodePayload& dstPayload = codeGen.setPayloadAddress(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = runtimeAnyReg;
            return Result::Continue;
        }

        const bool srcFloatType   = srcType.isFloat();
        const bool srcIntLikeType = srcType.isNumericIntLike();
        const bool dstFloatType   = dstType.isFloat();
        const bool dstIntLikeType = dstType.isNumericIntLike();

        if (dstType.isBool() && (srcType.isPointerLike() || srcType.isReference() || srcType.isMoveReference() || srcType.isNull()))
        {
            MicroReg srcReg = srcPayload.reg;
            if (srcPayload.isAddress())
            {
                srcReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, MicroOpBits::B64);
            }

            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            builder.emitCmpRegImm(srcReg, ApInt(0, 64), MicroOpBits::B64);
            builder.emitSetCondReg(dstPayload.reg, MicroCond::NotEqual);
            return Result::Continue;
        }

        if (srcIntLikeType && dstIntLikeType)
        {
            const MicroOpBits srcOpBits = castPayloadBits(srcType);
            const MicroOpBits dstOpBits = castPayloadBits(dstType);
            SWC_ASSERT(srcOpBits != MicroOpBits::Zero);
            SWC_ASSERT(dstOpBits != MicroOpBits::Zero);

            MicroReg srcReg = srcPayload.reg;
            if (srcPayload.isAddress())
            {
                srcReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, srcOpBits);
            }

            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();

            if (dstType.isBool())
            {
                builder.emitCmpRegImm(srcReg, ApInt(0, 64), srcOpBits);
                builder.emitSetCondReg(dstPayload.reg, MicroCond::NotEqual);
                return Result::Continue;
            }

            const uint32_t srcWidth = getNumBits(srcOpBits);
            const uint32_t dstWidth = getNumBits(dstOpBits);
            if (srcWidth == dstWidth)
            {
                builder.emitLoadRegReg(dstPayload.reg, srcReg, dstOpBits);
                return Result::Continue;
            }

            if (srcWidth > dstWidth)
            {
                builder.emitLoadRegReg(dstPayload.reg, srcReg, dstOpBits);
                return Result::Continue;
            }

            if (srcType.isNumericSigned())
            {
                builder.emitLoadSignedExtendRegReg(dstPayload.reg, srcReg, dstOpBits, srcOpBits);
                return Result::Continue;
            }

            builder.emitLoadZeroExtendRegReg(dstPayload.reg, srcReg, dstOpBits, srcOpBits);
            return Result::Continue;
        }

        if (sourceTypeRef == dstTypeRef)
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        if (!((srcIntLikeType && dstFloatType) || (srcFloatType && dstFloatType) || (srcFloatType && dstIntLikeType)))
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        const MicroOpBits srcOpBits = castPayloadBits(srcType);
        const MicroOpBits dstOpBits = castPayloadBits(dstType);
        if (srcOpBits == MicroOpBits::Zero || dstOpBits == MicroOpBits::Zero)
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        MicroReg srcReg = srcPayload.reg;
        if (srcPayload.isAddress())
        {
            srcReg = codeGen.nextVirtualRegisterForType(sourceTypeRef);
            builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, srcOpBits);
        }

        if (srcIntLikeType && dstFloatType)
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstPayload.reg, dstOpBits);
            builder.emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertIntToFloat, dstOpBits);
            return Result::Continue;
        }

        if (srcFloatType && dstFloatType)
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = srcReg;
            builder.emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertFloatToFloat, srcOpBits);
            return Result::Continue;
        }

        CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        dstPayload.reg                 = codeGen.nextVirtualRegisterForType(dstTypeRef);
        builder.emitClearReg(dstPayload.reg, dstOpBits);
        builder.emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertFloatToInt, srcOpBits);

        return Result::Continue;
    }
}

Result AstAutoCastExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return emitNumericCast(codeGen, nodeExprRef, codeGen.curViewType().typeRef());
}

Result AstCastExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return emitNumericCast(codeGen, nodeExprRef, codeGen.curViewType().typeRef());
}

SWC_END_NAMESPACE();
