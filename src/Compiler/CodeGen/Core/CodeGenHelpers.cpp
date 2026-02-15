#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

void CodeGenHelpers::emitMemCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes)
{
    if (!sizeInBytes)
        return;

    auto& builder = codeGen.builder();

    const auto srcReg   = MicroReg::virtualIntReg(codeGen.nextVirtualRegister());
    const auto tmpReg   = MicroReg::virtualIntReg(codeGen.nextVirtualRegister());
    const auto countReg = MicroReg::virtualIntReg(codeGen.nextVirtualRegister());

    const auto loopLabel = builder.createLabel();
    const auto doneLabel = builder.createLabel();

    builder.encodeLoadRegReg(srcReg, srcAddressReg, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeLoadRegImm(countReg, sizeInBytes, MicroOpBits::B64, EncodeFlagsE::Zero);

    builder.placeLabel(loopLabel, EncodeFlagsE::Zero);
    builder.encodeCmpRegImm(countReg, 0, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeJumpToLabel(MicroCond::Zero, MicroOpBits::B32, doneLabel, EncodeFlagsE::Zero);

    builder.encodeLoadRegMem(tmpReg, srcReg, 0, MicroOpBits::B8, EncodeFlagsE::Zero);
    builder.encodeLoadMemReg(dstReg, 0, tmpReg, MicroOpBits::B8, EncodeFlagsE::Zero);
    builder.encodeOpBinaryRegImm(srcReg, 1, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeOpBinaryRegImm(dstReg, 1, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeOpBinaryRegImm(countReg, 1, MicroOp::Subtract, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopLabel, EncodeFlagsE::Zero);
    builder.placeLabel(doneLabel, EncodeFlagsE::Zero);
}

SWC_END_NAMESPACE();
