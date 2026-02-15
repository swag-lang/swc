#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Backend/CodeGen/Micro/MicroInstrHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    auto&              ctx      = codeGen.ctx();
    const auto&        callConv = CallConv::host();
    MicroInstrBuilder& builder  = codeGen.builder();
    const auto         exprView = codeGen.nodeView(nodeExprRef);
    SWC_ASSERT(exprView.type);

    const auto* payload = codeGen.payload(nodeExprRef);
    SWC_ASSERT(payload != nullptr);
    const MicroReg payloadReg = payload->reg;
    const bool     isLValue   = codeGen.sema().isLValue(nodeExprRef);

    SWC_ASSERT(!callConv.intArgRegs.empty());
    const MicroReg outputStorageReg = callConv.intArgRegs[0];
    const TypeRef  exprStorageRef   = exprView.type->unwrap(ctx, exprView.typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    const TypeInfo& exprStorageType = codeGen.ctx().typeMgr().get(exprStorageRef);

    if (exprStorageType.isVoid())
    {
        builder.encodeRet(EncodeFlagsE::Zero);
        return Result::Continue;
    }

    if (exprStorageType.isFloat())
    {
        const MicroOpBits bits = microOpBitsFromBitWidth(exprStorageType.payloadFloatBits());
        SWC_ASSERT(bits == MicroOpBits::B32 || bits == MicroOpBits::B64);
        if (isLValue)
            builder.encodeLoadRegMem(callConv.floatReturn, payloadReg, 0, bits, EncodeFlagsE::Zero);
        else
            builder.encodeLoadRegReg(callConv.floatReturn, payloadReg, bits, EncodeFlagsE::Zero);
        builder.encodeLoadMemReg(outputStorageReg, 0, callConv.floatReturn, bits, EncodeFlagsE::Zero);
        builder.encodeRet(EncodeFlagsE::Zero);
        return Result::Continue;
    }

    if (exprStorageType.isBool() || exprStorageType.isCharRune() || exprStorageType.isIntLike() || exprStorageType.isPointerLike() || exprStorageType.isNull())
    {
        MicroOpBits bits = MicroOpBits::B64;
        if (exprStorageType.isBool())
            bits = MicroOpBits::B8;
        else if (exprStorageType.isCharRune())
            bits = MicroOpBits::B32;
        else if (exprStorageType.isIntLike())
            bits = microOpBitsFromBitWidth(exprStorageType.payloadIntLikeBits());
        SWC_ASSERT(bits != MicroOpBits::Zero);

        if (isLValue)
            builder.encodeLoadRegMem(callConv.intReturn, payloadReg, 0, bits, EncodeFlagsE::Zero);
        else
            builder.encodeLoadRegReg(callConv.intReturn, payloadReg, bits, EncodeFlagsE::Zero);
        builder.encodeLoadMemReg(outputStorageReg, 0, callConv.intReturn, bits, EncodeFlagsE::Zero);
        builder.encodeRet(EncodeFlagsE::Zero);
        return Result::Continue;
    }

    const uint64_t rawSize = exprStorageType.sizeOf(ctx);
    SWC_ASSERT(rawSize <= std::numeric_limits<uint32_t>::max());
    const uint32_t storageSize = static_cast<uint32_t>(rawSize);

    MicroReg srcReg = MicroReg::invalid();
    MicroReg tmpReg = MicroReg::invalid();
    SWC_ASSERT(callConv.tryPickIntScratchRegs(srcReg, tmpReg, std::span{&outputStorageReg, 1}));
    if (isLValue)
        builder.encodeLoadRegReg(srcReg, payloadReg, MicroOpBits::B64, EncodeFlagsE::Zero);
    else
    {
        builder.encodeLoadMemReg(outputStorageReg, 0, payloadReg, MicroOpBits::B64, EncodeFlagsE::Zero);
        builder.encodeRet(EncodeFlagsE::Zero);
        return Result::Continue;
    }
    MicroInstrHelpers::emitMemCopy(builder, outputStorageReg, srcReg, tmpReg, storageSize);

    builder.encodeRet(EncodeFlagsE::Zero);
    return Result::Continue;
}

SWC_END_NAMESPACE();
