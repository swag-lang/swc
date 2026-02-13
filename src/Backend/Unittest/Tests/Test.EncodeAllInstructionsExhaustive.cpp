#include "pch.h"
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Backend/Unittest/BackendUnittest.h"
#include "Backend/Unittest/BackendUnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

#if SWC_DEV_MODE

SWC_BACKEND_TEST_BEGIN(EncodeAllInstructionsExhaustive)
{
    MicroInstrBuilder builder(ctx);
    constexpr EncodeFlags kEmit    = EncodeFlagsE::Zero;
    constexpr EncodeFlags kCan     = EncodeFlagsE::CanEncode;
    constexpr EncodeFlags kLock    = EncodeFlagsE::Lock;
    constexpr EncodeFlags kEmitB64 = EncodeFlagsE::B64;

    constexpr auto rax  = MicroReg::intReg(0);
    constexpr auto rcx  = MicroReg::intReg(2);
    constexpr auto rdx  = MicroReg::intReg(3);
    constexpr auto rsp  = MicroReg::intReg(4);
    constexpr auto rbp  = MicroReg::intReg(5);
    constexpr auto r8   = MicroReg::intReg(8);
    constexpr auto r9   = MicroReg::intReg(9);
    constexpr auto r10  = MicroReg::intReg(10);
    constexpr auto r11  = MicroReg::intReg(11);
    constexpr auto r12  = MicroReg::intReg(12);
    constexpr auto r13  = MicroReg::intReg(13);
    constexpr auto xmm0 = MicroReg::floatReg(0);
    constexpr auto xmm1 = MicroReg::floatReg(1);
    constexpr auto xmm2 = MicroReg::floatReg(2);
    constexpr auto xmm3 = MicroReg::floatReg(3);

    builder.encodeNop(kEmit);
    builder.encodePush(r12, kEmit);
    builder.encodePop(r12, kEmit);
    builder.encodeLoadSymbolRelocAddress(r10, 1, 0x10, kEmit);
    builder.encodeLoadSymRelocValue(r11, 2, 0x20, MicroOpBits::B64, kEmit);
    builder.encodeLoadSymRelocValue(r8, 3, 0x30, MicroOpBits::B64, kEmitB64);
    builder.encodeLoadSymRelocValue(xmm0, 4, 0x40, MicroOpBits::B32, kEmit);
    builder.encodeCallLocal({}, CallConvKind::C, kEmit);
    builder.encodeCallExtern({}, CallConvKind::C, kEmit);
    builder.encodeCallReg(r9, CallConvKind::C, kEmit);

    constexpr MicroCondJump jumpKinds[] = {
        MicroCondJump::Above,
        MicroCondJump::AboveOrEqual,
        MicroCondJump::Below,
        MicroCondJump::BelowOrEqual,
        MicroCondJump::Greater,
        MicroCondJump::GreaterOrEqual,
        MicroCondJump::Less,
        MicroCondJump::LessOrEqual,
        MicroCondJump::NotOverflow,
        MicroCondJump::NotParity,
        MicroCondJump::NotZero,
        MicroCondJump::Parity,
        MicroCondJump::Sign,
        MicroCondJump::Unconditional,
        MicroCondJump::Zero,
    };

    for (const auto jumpKind : jumpKinds)
    {
        MicroJump jump8;
        builder.encodeJump(jump8, jumpKind, MicroOpBits::B8, kEmit);
        builder.encodePatchJump(jump8, kEmit);

        MicroJump jump32;
        builder.encodeJump(jump32, jumpKind, MicroOpBits::B32, kEmit);
        builder.encodePatchJump(jump32, 0x80, kEmit);
    }

    builder.encodeJumpReg(r13, kEmit);

    builder.encodeLoadRegImm(rax, 0x12, MicroOpBits::B8, kEmit);
    builder.encodeLoadRegImm(r8, 0x1234, MicroOpBits::B16, kEmit);
    builder.encodeLoadRegImm(r9, 0x12345678, MicroOpBits::B32, kEmit);
    builder.encodeLoadRegImm(r10, 0x123456789ABCDEF0, MicroOpBits::B64, kEmit);

    builder.encodeLoadRegReg(r11, r8, MicroOpBits::B64, kEmit);
    builder.encodeLoadRegReg(xmm0, xmm1, MicroOpBits::B32, kEmit);
    builder.encodeLoadRegReg(xmm2, r9, MicroOpBits::B32, kEmit);
    builder.encodeLoadRegReg(r10, xmm3, MicroOpBits::B32, kEmit);

    builder.encodeLoadRegMem(r8, r12, 0, MicroOpBits::B64, kEmit);
    builder.encodeLoadRegMem(r9, rbp, 0x7F, MicroOpBits::B32, kEmit);
    builder.encodeLoadRegMem(xmm0, rsp, 0x1234, MicroOpBits::B64, kEmit);
    builder.encodeLoadRegMem(r10, r13, 0x40, MicroOpBits::B16, kEmit);

    builder.encodeLoadSignedExtendRegMem(r11, r12, 0x10, MicroOpBits::B64, MicroOpBits::B8, kEmit);
    builder.encodeLoadSignedExtendRegMem(r10, r13, 0x20, MicroOpBits::B64, MicroOpBits::B16, kEmit);
    builder.encodeLoadSignedExtendRegMem(r9, rsp, 0x30, MicroOpBits::B64, MicroOpBits::B32, kEmit);
    builder.encodeLoadSignedExtendRegReg(r8, r11, MicroOpBits::B64, MicroOpBits::B8, kEmit);
    builder.encodeLoadSignedExtendRegReg(r9, r10, MicroOpBits::B64, MicroOpBits::B16, kEmit);
    builder.encodeLoadSignedExtendRegReg(r10, r9, MicroOpBits::B64, MicroOpBits::B32, kEmit);

    builder.encodeLoadZeroExtendRegMem(r11, r12, 0x44, MicroOpBits::B64, MicroOpBits::B8, kEmit);
    builder.encodeLoadZeroExtendRegMem(r10, r13, 0x88, MicroOpBits::B64, MicroOpBits::B16, kEmit);
    builder.encodeLoadZeroExtendRegMem(r9, rsp, 0x24, MicroOpBits::B64, MicroOpBits::B32, kEmit);
    builder.encodeLoadZeroExtendRegReg(r8, r11, MicroOpBits::B64, MicroOpBits::B8, kEmit);
    builder.encodeLoadZeroExtendRegReg(r9, r10, MicroOpBits::B64, MicroOpBits::B16, kEmit);
    builder.encodeLoadZeroExtendRegReg(r10, r9, MicroOpBits::B64, MicroOpBits::B32, kEmit);

    builder.encodeLoadAddressRegMem(r11, r12, 0, MicroOpBits::B64, kEmit);
    builder.encodeLoadAddressRegMem(r10, MicroReg::instructionPointer(), 0, MicroOpBits::B64, kEmit);
    builder.encodeLoadAddressRegMem(r9, r13, 0x1234, MicroOpBits::B64, kEmit);

    builder.encodeLoadAmcRegMem(r10, MicroOpBits::B64, r13, r8, 4, 0x20, MicroOpBits::B64, kEmit);
    builder.encodeLoadAmcRegMem(xmm2, MicroOpBits::B64, r12, r9, 2, 0x7F, MicroOpBits::B64, kEmit);
    builder.encodeLoadAmcMemReg(r13, r8, 8, 0x100, MicroOpBits::B64, r10, MicroOpBits::B32, kEmit);
    builder.encodeLoadAmcMemReg(r12, r9, 1, 0x40, MicroOpBits::B64, xmm3, MicroOpBits::B64, kEmit);
    builder.encodeLoadAmcMemImm(r13, r8, 4, 0x24, MicroOpBits::B64, 0x1234, MicroOpBits::B32, kEmit);
    builder.encodeLoadAddressAmcRegMem(r11, MicroOpBits::B64, r13, r9, 2, 0x40, MicroOpBits::B64, kEmit);

    builder.encodeLoadMemReg(r12, 0, r8, MicroOpBits::B64, kEmit);
    builder.encodeLoadMemReg(r13, 0x7F, xmm0, MicroOpBits::B64, kEmit);
    builder.encodeLoadMemReg(rsp, 0x120, r9, MicroOpBits::B32, kEmit);

    builder.encodeLoadMemImm(r12, 0, 0x7F, MicroOpBits::B8, kEmit);
    builder.encodeLoadMemImm(r13, 0x7F, 0x1234, MicroOpBits::B16, kEmit);
    builder.encodeLoadMemImm(rsp, 0x40, 0x12345678, MicroOpBits::B32, kEmit);
    builder.encodeLoadMemImm(rbp, 0x20, 0xFFFFFFFFFFFFFF80, MicroOpBits::B64, kEmit);

    builder.encodeCmpRegReg(r8, r9, MicroOpBits::B64, kEmit);
    builder.encodeCmpRegReg(xmm0, xmm1, MicroOpBits::B64, kEmit);
    builder.encodeCmpRegImm(r10, 0x1234, MicroOpBits::B32, kEmit);
    builder.encodeCmpMemReg(r12, 0x40, r11, MicroOpBits::B64, kEmit);
    builder.encodeCmpMemImm(r13, 0x44, 0x55, MicroOpBits::B8, kEmit);

    constexpr MicroCond setConds[] = {
        MicroCond::Above,
        MicroCond::AboveOrEqual,
        MicroCond::Below,
        MicroCond::BelowOrEqual,
        MicroCond::Equal,
        MicroCond::EvenParity,
        MicroCond::Greater,
        MicroCond::GreaterOrEqual,
        MicroCond::Less,
        MicroCond::LessOrEqual,
        MicroCond::NotAbove,
        MicroCond::NotEqual,
        MicroCond::NotEvenParity,
        MicroCond::NotParity,
        MicroCond::Overflow,
        MicroCond::Parity,
    };

    for (const auto cond : setConds)
    {
        const bool isNative = cond != MicroCond::EvenParity && cond != MicroCond::NotEvenParity;
        builder.encodeSetCondReg(r8, cond, isNative ? kEmit : kCan);
    }

    for (const auto cond : setConds)
    {
        const bool isNative = cond == MicroCond::Below || cond == MicroCond::Equal || cond == MicroCond::Greater ||
                              cond == MicroCond::Less || cond == MicroCond::BelowOrEqual || cond == MicroCond::GreaterOrEqual;
        builder.encodeLoadCondRegReg(r9, r10, cond, MicroOpBits::B64, isNative ? kEmit : kCan);
    }

    builder.encodeClearReg(r11, MicroOpBits::B64, kEmit);
    builder.encodeClearReg(xmm1, MicroOpBits::B64, kEmit);

    builder.encodeOpUnaryReg(r8, MicroOp::BitwiseNot, MicroOpBits::B64, kEmit);
    builder.encodeOpUnaryReg(r9, MicroOp::Negate, MicroOpBits::B32, kEmit);
    builder.encodeOpUnaryReg(r10, MicroOp::ByteSwap, MicroOpBits::B16, kEmit);
    builder.encodeOpUnaryReg(r11, MicroOp::ByteSwap, MicroOpBits::B64, kEmit);
    builder.encodeOpUnaryMem(r12, 0x20, MicroOp::BitwiseNot, MicroOpBits::B32, kEmit);
    builder.encodeOpUnaryMem(r13, 0x40, MicroOp::Negate, MicroOpBits::B64, kEmit);

    constexpr MicroOp regRegSimpleOps[] = {
        MicroOp::Add,
        MicroOp::Subtract,
        MicroOp::And,
        MicroOp::Or,
        MicroOp::Xor,
        MicroOp::Exchange,
        MicroOp::BitScanForward,
        MicroOp::BitScanReverse,
        MicroOp::PopCount,
        MicroOp::MultiplySigned,
    };

    for (const auto op : regRegSimpleOps)
        builder.encodeOpBinaryRegReg(r8, r9, op, MicroOpBits::B64, kEmit);

    constexpr MicroOp regRegShiftOps[] = {
        MicroOp::RotateLeft,
        MicroOp::RotateRight,
        MicroOp::ShiftArithmeticLeft,
        MicroOp::ShiftArithmeticRight,
        MicroOp::ShiftLeft,
        MicroOp::ShiftRight,
    };

    for (const auto op : regRegShiftOps)
        builder.encodeOpBinaryRegReg(r10, rcx, op, MicroOpBits::B64, kEmit);

    builder.encodeOpBinaryRegReg(rax, r9, MicroOp::MultiplyUnsigned, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryRegReg(rax, r11, MicroOp::DivideUnsigned, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryRegReg(rax, r8, MicroOp::DivideSigned, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryRegReg(rax, r9, MicroOp::ModuloUnsigned, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryRegReg(rax, r10, MicroOp::ModuloSigned, MicroOpBits::B64, kEmit);

    constexpr MicroOp floatOps[] = {
        MicroOp::FloatAdd,
        MicroOp::FloatAnd,
        MicroOp::FloatDivide,
        MicroOp::FloatMax,
        MicroOp::FloatMin,
        MicroOp::FloatMultiply,
        MicroOp::FloatSqrt,
        MicroOp::FloatSubtract,
        MicroOp::FloatXor,
        MicroOp::ConvertFloatToFloat,
    };

    for (const auto op : floatOps)
        builder.encodeOpBinaryRegReg(xmm0, xmm1, op, MicroOpBits::B64, kEmit);

    builder.encodeOpBinaryRegReg(xmm2, r10, MicroOp::ConvertIntToFloat, MicroOpBits::B64, kEmitB64);
    builder.encodeOpBinaryRegReg(r11, xmm3, MicroOp::ConvertFloatToInt, MicroOpBits::B64, kEmitB64);
    builder.encodeOpBinaryRegReg(xmm0, r8, MicroOp::ConvertUIntToFloat64, MicroOpBits::B64, kCan);

    constexpr MicroOp regMemOps[] = {
        MicroOp::Add,
        MicroOp::Subtract,
        MicroOp::And,
        MicroOp::Or,
        MicroOp::Xor,
        MicroOp::MultiplySigned,
    };

    for (const auto op : regMemOps)
        builder.encodeOpBinaryRegMem(r9, r12, 0x24, op, MicroOpBits::B64, kEmit);

    builder.encodeOpBinaryMemReg(r13, 0x20, r10, MicroOp::Add, MicroOpBits::B64, kLock);
    builder.encodeOpBinaryMemReg(r12, 0x30, r11, MicroOp::Subtract, MicroOpBits::B32, kEmit);
    builder.encodeOpBinaryMemReg(rsp, 0x44, r8, MicroOp::And, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryMemReg(rbp, 0x40, r9, MicroOp::Or, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryMemReg(r12, 0x20, r10, MicroOp::Xor, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryMemReg(r13, 0x18, rcx, MicroOp::ShiftLeft, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryMemReg(r12, 0x28, rcx, MicroOp::ShiftRight, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryMemReg(rsp, 0x38, rcx, MicroOp::ShiftArithmeticRight, MicroOpBits::B64, kEmit);

    builder.encodeOpBinaryRegImm(r8, 2, MicroOp::Add, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryRegImm(r9, 0x7F, MicroOp::Subtract, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryRegImm(r10, 0x7F, MicroOp::And, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryRegImm(r11, 0x7F, MicroOp::Or, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryRegImm(r12, 0x7F, MicroOp::Xor, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryRegImm(r13, 7, MicroOp::MultiplySigned, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryRegImm(r8, 1, MicroOp::ShiftLeft, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryRegImm(r9, 5, MicroOp::ShiftRight, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryRegImm(r10, 9, MicroOp::ShiftArithmeticRight, MicroOpBits::B64, kEmit);

    builder.encodeOpBinaryMemImm(r12, 0x10, 2, MicroOp::Add, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryMemImm(r13, 0x20, 0x7F, MicroOp::Subtract, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryMemImm(rsp, 0x30, 0x7F, MicroOp::And, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryMemImm(rbp, 0x40, 0x7F, MicroOp::Or, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryMemImm(r12, 0x50, 0x7F, MicroOp::Xor, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryMemImm(r13, 0x60, 1, MicroOp::ShiftLeft, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryMemImm(rsp, 0x70, 4, MicroOp::ShiftRight, MicroOpBits::B64, kEmit);
    builder.encodeOpBinaryMemImm(rbp, 0x80, 8, MicroOp::ShiftArithmeticRight, MicroOpBits::B64, kEmit);

    builder.encodeOpTernaryRegRegReg(xmm0, xmm1, xmm2, MicroOp::MultiplyAdd, MicroOpBits::B64, kEmit);
    builder.encodeOpTernaryRegRegReg(rax, r12, r11, MicroOp::CompareExchange, MicroOpBits::B64, kLock);

    builder.encodeRet(kEmit);

    X64Encoder       encoder(ctx);
    MicroEncodePass  encodePass;
    MicroPassManager passes;
    passes.add(encodePass);

    MicroPassContext passCtx;
    builder.runPasses(passes, &encoder, passCtx);

    SWC_ASSERT(builder.instructions().count() > 150);
    SWC_ASSERT(encoder.size() > 512);
    SWC_ASSERT(encoder.data());
}
SWC_BACKEND_TEST_END()

#endif

SWC_END_NAMESPACE();
