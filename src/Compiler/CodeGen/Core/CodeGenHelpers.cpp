#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Compiler/CodeGen/Core/CodeGen.h"

SWC_BEGIN_NAMESPACE();

void CodeGenHelpers::emitMemCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes)
{
    if (!sizeInBytes)
        return;

    auto& builder = codeGen.builder();

    const auto srcReg   = codeGen.nextVirtualIntRegister();
    const auto tmpReg   = codeGen.nextVirtualIntRegister();
    const auto countReg = codeGen.nextVirtualIntRegister();

    const auto loopLabel = builder.createLabel();
    const auto doneLabel = builder.createLabel();

    builder.encodeLoadRegReg(srcReg, srcAddressReg, MicroOpBits::B64);
    builder.encodeLoadRegImm(countReg, sizeInBytes, MicroOpBits::B64);

    builder.placeLabel(loopLabel);
    builder.encodeCmpRegImm(countReg, 0, MicroOpBits::B64);
    builder.encodeJumpToLabel(MicroCond::Zero, MicroOpBits::B32, doneLabel);

    builder.encodeLoadRegMem(tmpReg, srcReg, 0, MicroOpBits::B8);
    builder.encodeLoadMemReg(dstReg, 0, tmpReg, MicroOpBits::B8);
    builder.encodeOpBinaryRegImm(srcReg, 1, MicroOp::Add, MicroOpBits::B64);
    builder.encodeOpBinaryRegImm(dstReg, 1, MicroOp::Add, MicroOpBits::B64);
    builder.encodeOpBinaryRegImm(countReg, 1, MicroOp::Subtract, MicroOpBits::B64);
    builder.encodeJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopLabel);
    builder.placeLabel(doneLabel);
}

SWC_END_NAMESPACE();
