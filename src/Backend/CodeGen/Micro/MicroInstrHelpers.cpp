#include "pch.h"
#include "Backend/CodeGen/Micro/MicroInstrHelpers.h"
#include "Backend/CodeGen/ABI/CallConv.h"

SWC_BEGIN_NAMESPACE();

bool MicroInstrHelpers::containsReg(std::span<const MicroReg> regs, MicroReg reg)
{
    for (const auto value : regs)
    {
        if (value == reg)
            return true;
    }

    return false;
}

void MicroInstrHelpers::emitMemCopy(MicroInstrBuilder& builder, MicroReg dstReg, MicroReg srcReg, MicroReg tmpReg, uint32_t sizeInBytes)
{
    if (!sizeInBytes)
        return;

    const auto stackPointer = CallConv::host().stackPointer;

    builder.encodePush(tmpReg, EncodeFlagsE::Zero);
    builder.encodeLoadMemImm(stackPointer, 0, sizeInBytes, MicroOpBits::B64, EncodeFlagsE::Zero);

    const auto loopLabelRef = builder.createLabel();
    const auto doneLabelRef = builder.createLabel();
    builder.placeLabel(loopLabelRef, EncodeFlagsE::Zero);

    builder.encodeCmpMemImm(stackPointer, 0, 0, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeJumpToLabel(MicroCondJump::Zero, MicroOpBits::B32, doneLabelRef, EncodeFlagsE::Zero);

    builder.encodeLoadRegMem(tmpReg, srcReg, 0, MicroOpBits::B8, EncodeFlagsE::Zero);
    builder.encodeLoadMemReg(dstReg, 0, tmpReg, MicroOpBits::B8, EncodeFlagsE::Zero);
    builder.encodeOpBinaryRegImm(srcReg, 1, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeOpBinaryRegImm(dstReg, 1, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeOpBinaryMemImm(stackPointer, 0, 1, MicroOp::Subtract, MicroOpBits::B64, EncodeFlagsE::Zero);

    builder.encodeJumpToLabel(MicroCondJump::Unconditional, MicroOpBits::B32, loopLabelRef, EncodeFlagsE::Zero);
    builder.placeLabel(doneLabelRef, EncodeFlagsE::Zero);
    builder.encodePop(tmpReg, EncodeFlagsE::Zero);
}

SWC_END_NAMESPACE();
