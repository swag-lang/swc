#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
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

    bool isNumericIntLike(const TypeInfo& typeInfo)
    {
        return typeInfo.isIntLike() || typeInfo.isBool();
    }

    bool isNumericSigned(const TypeInfo& typeInfo)
    {
        if (typeInfo.isBool())
            return false;
        return typeInfo.isIntSigned();
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
            dstType.isReference() ||
            dstType.isMoveReference() ||
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
                const ByteSpan        arrayBytes    = srcConst.getArray();
                const Runtime::String runtimeString = {
                    .ptr    = reinterpret_cast<const char*>(arrayBytes.data()),
                    .length = arrayBytes.size(),
                };
                const ByteSpan runtimeStringBytes = asByteSpan(reinterpret_cast<const std::byte*>(&runtimeString), sizeof(runtimeString));
                const uint64_t storageAddress     = addPayloadToConstantManagerAndGetAddress(codeGen, runtimeStringBytes);

                const CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
                builder.emitLoadRegPtrImm(dstPayload.reg, storageAddress, srcConstView.cstRef());
                return Result::Continue;
            }
        }

        const uint64_t length       = srcType.sizeOf(codeGen.ctx());
        auto*          runtimeValue = codeGen.compiler().allocate<Runtime::String>();
        runtimeValue->ptr           = nullptr;
        runtimeValue->length        = 0;
        const auto runtimeValueAddr = reinterpret_cast<uint64_t>(runtimeValue);

        const MicroReg runtimeValueReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegPtrImm(runtimeValueReg, runtimeValueAddr);

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

        MicroOpBits valueBits = MicroOpBits::Zero;
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
        if (dstType.isString() && srcType.isArray())
            return emitArrayToStringCast(codeGen, srcNodeRef, dstTypeRef, srcType);
        const bool srcFloatType   = srcType.isFloat();
        const bool srcIntLikeType = isNumericIntLike(srcType);
        const bool dstFloatType   = dstType.isFloat();
        const bool dstIntLikeType = isNumericIntLike(dstType);

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

            if (isNumericSigned(srcType))
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
