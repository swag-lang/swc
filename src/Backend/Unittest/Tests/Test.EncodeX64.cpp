#include "pch.h"
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/Unittest/BackendUnittest.h"
#include "Backend/Unittest/BackendUnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

#if SWC_DEV_MODE

namespace
{
    using BuilderCaseFn = std::function<void(MicroInstrBuilder&)>;
    using RunCaseFn     = std::function<void(const char*, const char*, const BuilderCaseFn&)>;

    constexpr auto K_EMIT = EncodeFlagsE::Zero;
    constexpr auto K_LOCK = EncodeFlagsE::Lock;
    constexpr auto K_B64  = EncodeFlagsE::B64;

    constexpr auto RAX  = MicroReg::intReg(0);
    constexpr auto RDX  = MicroReg::intReg(3);
    constexpr auto RCX  = MicroReg::intReg(2);
    constexpr auto RSP  = MicroReg::intReg(4);
    constexpr auto RBP  = MicroReg::intReg(5);
    constexpr auto R15  = MicroReg::intReg(15);
    constexpr auto R8   = MicroReg::intReg(8);
    constexpr auto R9   = MicroReg::intReg(9);
    constexpr auto R10  = MicroReg::intReg(10);
    constexpr auto R11  = MicroReg::intReg(11);
    constexpr auto R12  = MicroReg::intReg(12);
    constexpr auto R13  = MicroReg::intReg(13);
    constexpr auto R14  = MicroReg::intReg(14);
    constexpr auto XMM0 = MicroReg::floatReg(0);
    constexpr auto XMM1 = MicroReg::floatReg(1);
    constexpr auto XMM2 = MicroReg::floatReg(2);
    constexpr auto XMM3 = MicroReg::floatReg(3);

    void runCasesFlow(const RunCaseFn& runCase)
    {
        runCase("nop", "90", [&](MicroInstrBuilder& builder) { builder.encodeNop(K_EMIT); });
        runCase("push_r12", "41 54", [&](MicroInstrBuilder& builder) { builder.encodePush(R12, K_EMIT); });
        runCase("pop_r12", "41 5C", [&](MicroInstrBuilder& builder) { builder.encodePop(R12, K_EMIT); });
        runCase("call_local", "E8 00 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeCallLocal({}, CallConvKind::C, K_EMIT); });
        runCase("call_extern", "FF 15 00 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeCallExtern({}, CallConvKind::C, K_EMIT); });
        runCase("call_reg_r9", "41 FF D1", [&](MicroInstrBuilder& builder) { builder.encodeCallReg(R9, CallConvKind::C, K_EMIT); });
        runCase("jump_reg_r13", "41 FF E5", [&](MicroInstrBuilder& builder) { builder.encodeJumpReg(R13, K_EMIT); });
        runCase("ret", "C3", [&](MicroInstrBuilder& builder) { builder.encodeRet(K_EMIT); });

        runCase("jump_zero_b8_patch_here", "74 00", [&](MicroInstrBuilder& builder) {
            MicroJump jump;
            builder.encodeJump(jump, MicroCondJump::Zero, MicroOpBits::B8, K_EMIT);
            builder.encodePatchJump(jump, K_EMIT);
        });
        runCase("jump_less_b32_patch_80", "0F 8C 7A 00 00 00", [&](MicroInstrBuilder& builder) {
            MicroJump jump;
            builder.encodeJump(jump, MicroCondJump::Less, MicroOpBits::B32, K_EMIT);
            builder.encodePatchJump(jump, 0x80, K_EMIT);
        });
    }

    void runCasesLoad(const RunCaseFn& runCase)
    {
        runCase("sym_reloc_addr_r10", "4C 8D 15 10 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadSymbolRelocAddress(R10, 1, 0x10, K_EMIT); });
        runCase("sym_reloc_value_r11_b64", "4C 8B 1D 20 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadSymRelocValue(R11, 2, 0x20, MicroOpBits::B64, K_EMIT); });
        runCase("sym_reloc_value_xmm0_b32", "F3 0F 10 05 40 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadSymRelocValue(XMM0, 4, 0x40, MicroOpBits::B32, K_EMIT); });
        runCase("sym_reloc_value_r8_b64_abs", "49 B8 30 00 00 00 00 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadSymRelocValue(R8, 3, 0x30, MicroOpBits::B64, K_B64); });

        runCase("load_reg_imm_rax_b8", "B0 12", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegImm(RAX, 0x12, MicroOpBits::B8, K_EMIT); });
        runCase("load_reg_imm_r8_b16", "66 41 B8 34 12", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegImm(R8, 0x1234, MicroOpBits::B16, K_EMIT); });
        runCase("load_reg_imm_r9_b32", "41 B9 78 56 34 12", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegImm(R9, 0x12345678, MicroOpBits::B32, K_EMIT); });
        runCase("load_reg_imm_r10_b64", "49 BA F0 DE BC 9A 78 56 34 12", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegImm(R10, 0x123456789ABCDEF0, MicroOpBits::B64, K_EMIT); });

        runCase("load_reg_reg_r11_r8_b64", "4D 89 C3", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegReg(R11, R8, MicroOpBits::B64, K_EMIT); });
        runCase("load_reg_reg_xmm0_xmm1_b32", "F3 0F 10 C1", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegReg(XMM0, XMM1, MicroOpBits::B32, K_EMIT); });
        runCase("load_reg_reg_xmm2_r9_b32", "66 41 0F 6E D1", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegReg(XMM2, R9, MicroOpBits::B32, K_EMIT); });
        runCase("load_reg_reg_r10_xmm3_b32", "66 41 0F 7E DA", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegReg(R10, XMM3, MicroOpBits::B32, K_EMIT); });

        runCase("load_reg_mem_r8_r12_0_b64", "4D 8B 04 24", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegMem(R8, R12, 0, MicroOpBits::B64, K_EMIT); });
        runCase("load_reg_mem_r9_rbp_7f_b32", "44 8B 4D 7F", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegMem(R9, RBP, 0x7F, MicroOpBits::B32, K_EMIT); });
        runCase("load_reg_mem_xmm0_rsp_1234_b64", "F2 40 0F 10 84 24 34 12 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegMem(XMM0, RSP, 0x1234, MicroOpBits::B64, K_EMIT); });
        runCase("load_reg_mem_r10_r13_40_b16", "66 45 8B 55 40", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegMem(R10, R13, 0x40, MicroOpBits::B16, K_EMIT); });

        runCase("load_sext_reg_mem_b8", "4D 0F BE 5C 24 10", [&](MicroInstrBuilder& builder) { builder.encodeLoadSignedExtendRegMem(R11, R12, 0x10, MicroOpBits::B64, MicroOpBits::B8, K_EMIT); });
        runCase("load_sext_reg_mem_b16", "4D 0F BF 55 20", [&](MicroInstrBuilder& builder) { builder.encodeLoadSignedExtendRegMem(R10, R13, 0x20, MicroOpBits::B64, MicroOpBits::B16, K_EMIT); });
        runCase("load_sext_reg_mem_b32", "4C 63 4C 24 30", [&](MicroInstrBuilder& builder) { builder.encodeLoadSignedExtendRegMem(R9, RSP, 0x30, MicroOpBits::B64, MicroOpBits::B32, K_EMIT); });
        runCase("load_sext_reg_reg_b8", "4D 0F BE C3", [&](MicroInstrBuilder& builder) { builder.encodeLoadSignedExtendRegReg(R8, R11, MicroOpBits::B64, MicroOpBits::B8, K_EMIT); });
        runCase("load_sext_reg_reg_b16", "4D 0F BF CA", [&](MicroInstrBuilder& builder) { builder.encodeLoadSignedExtendRegReg(R9, R10, MicroOpBits::B64, MicroOpBits::B16, K_EMIT); });
        runCase("load_sext_reg_reg_b32", "4D 63 D1", [&](MicroInstrBuilder& builder) { builder.encodeLoadSignedExtendRegReg(R10, R9, MicroOpBits::B64, MicroOpBits::B32, K_EMIT); });

        runCase("load_zext_reg_mem_b8", "4D 0F B6 5C 24 44", [&](MicroInstrBuilder& builder) { builder.encodeLoadZeroExtendRegMem(R11, R12, 0x44, MicroOpBits::B64, MicroOpBits::B8, K_EMIT); });
        runCase("load_zext_reg_mem_b16", "4D 0F B7 95 88 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadZeroExtendRegMem(R10, R13, 0x88, MicroOpBits::B64, MicroOpBits::B16, K_EMIT); });
        runCase("load_zext_reg_mem_b32", "44 8B 4C 24 24", [&](MicroInstrBuilder& builder) { builder.encodeLoadZeroExtendRegMem(R9, RSP, 0x24, MicroOpBits::B64, MicroOpBits::B32, K_EMIT); });
        runCase("load_zext_reg_reg_b8", "4D 0F B6 C3", [&](MicroInstrBuilder& builder) { builder.encodeLoadZeroExtendRegReg(R8, R11, MicroOpBits::B64, MicroOpBits::B8, K_EMIT); });
        runCase("load_zext_reg_reg_b16", "4D 0F B7 CA", [&](MicroInstrBuilder& builder) { builder.encodeLoadZeroExtendRegReg(R9, R10, MicroOpBits::B64, MicroOpBits::B16, K_EMIT); });
        runCase("load_zext_reg_reg_b32", "45 89 CA", [&](MicroInstrBuilder& builder) { builder.encodeLoadZeroExtendRegReg(R10, R9, MicroOpBits::B64, MicroOpBits::B32, K_EMIT); });

        runCase("lea_reg_mem_rip", "4C 8D 15", [&](MicroInstrBuilder& builder) { builder.encodeLoadAddressRegMem(R10, MicroReg::instructionPointer(), 0, MicroOpBits::B64, K_EMIT); });
        runCase("lea_reg_mem_r11_r12_0", "4D 89 E3", [&](MicroInstrBuilder& builder) { builder.encodeLoadAddressRegMem(R11, R12, 0, MicroOpBits::B64, K_EMIT); });
        runCase("lea_reg_mem_r9_r13_1234", "4D 8D 8D 34 12 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadAddressRegMem(R9, R13, 0x1234, MicroOpBits::B64, K_EMIT); });

        runCase("load_amc_reg_mem", "4F 8B 54 85 20", [&](MicroInstrBuilder& builder) { builder.encodeLoadAmcRegMem(R10, MicroOpBits::B64, R13, R8, 4, 0x20, MicroOpBits::B64, K_EMIT); });
        runCase("load_amc_reg_mem_xmm2", "66 4B 0F 6E 54 4C 7F", [&](MicroInstrBuilder& builder) { builder.encodeLoadAmcRegMem(XMM2, MicroOpBits::B64, R12, R9, 2, 0x7F, MicroOpBits::B64, K_EMIT); });
        runCase("load_amc_mem_reg", "47 89 94 C5 00 01 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadAmcMemReg(R13, R8, 8, 0x100, MicroOpBits::B64, R10, MicroOpBits::B32, K_EMIT); });
        runCase("load_amc_mem_reg_xmm3", "66 4B 0F 7E 5C 0C 40", [&](MicroInstrBuilder& builder) { builder.encodeLoadAmcMemReg(R12, R9, 1, 0x40, MicroOpBits::B64, XMM3, MicroOpBits::B64, K_EMIT); });
        runCase("load_amc_mem_imm", "43 C7 44 85 24 34 12 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadAmcMemImm(R13, R8, 4, 0x24, MicroOpBits::B64, 0x1234, MicroOpBits::B32, K_EMIT); });
        runCase("lea_amc_reg_mem", "4F 8D 5C 4D 40", [&](MicroInstrBuilder& builder) { builder.encodeLoadAddressAmcRegMem(R11, MicroOpBits::B64, R13, R9, 2, 0x40, MicroOpBits::B64, K_EMIT); });

        runCase("load_mem_reg_r12_r8_b64", "4D 89 04 24", [&](MicroInstrBuilder& builder) { builder.encodeLoadMemReg(R12, 0, R8, MicroOpBits::B64, K_EMIT); });
        runCase("load_mem_reg_r13_xmm0_b64", "F2 41 0F 11 45 7F", [&](MicroInstrBuilder& builder) { builder.encodeLoadMemReg(R13, 0x7F, XMM0, MicroOpBits::B64, K_EMIT); });
        runCase("load_mem_reg_rsp_b32", "44 89 8C 24 20 01 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadMemReg(RSP, 0x120, R9, MicroOpBits::B32, K_EMIT); });
        runCase("load_mem_imm_r12_b8", "41 C6 04 24 7F", [&](MicroInstrBuilder& builder) { builder.encodeLoadMemImm(R12, 0, 0x7F, MicroOpBits::B8, K_EMIT); });
        runCase("load_mem_imm_r13_b16", "66 41 C7 45 7F 34 12", [&](MicroInstrBuilder& builder) { builder.encodeLoadMemImm(R13, 0x7F, 0x1234, MicroOpBits::B16, K_EMIT); });
        runCase("load_mem_imm_rsp_b32", "40 C7 44 24 40 78 56 34 12", [&](MicroInstrBuilder& builder) { builder.encodeLoadMemImm(RSP, 0x40, 0x12345678, MicroOpBits::B32, K_EMIT); });
        runCase("load_mem_imm_rbp_b64", "48 C7 45 20 80 FF FF FF", [&](MicroInstrBuilder& builder) { builder.encodeLoadMemImm(RBP, 0x20, 0xFFFFFFFFFFFFFF80, MicroOpBits::B64, K_EMIT); });
    }

    void runCasesCmpAndCond(const RunCaseFn& runCase)
    {
        runCase("cmp_reg_reg_r8_r9_b64", "4D 39 C8", [&](MicroInstrBuilder& builder) { builder.encodeCmpRegReg(R8, R9, MicroOpBits::B64, K_EMIT); });
        runCase("cmp_reg_reg_xmm0_xmm1_b64", "66 0F 2F C1", [&](MicroInstrBuilder& builder) { builder.encodeCmpRegReg(XMM0, XMM1, MicroOpBits::B64, K_EMIT); });
        runCase("cmp_reg_imm_r10_b32", "41 81 FA 34 12 00 00", [&](MicroInstrBuilder& builder) { builder.encodeCmpRegImm(R10, 0x1234, MicroOpBits::B32, K_EMIT); });
        runCase("cmp_mem_reg_r12_r11_b64", "4D 39 5C 24 40", [&](MicroInstrBuilder& builder) { builder.encodeCmpMemReg(R12, 0x40, R11, MicroOpBits::B64, K_EMIT); });
        runCase("cmp_mem_imm_r13_b8", "41 80 7D 44 55", [&](MicroInstrBuilder& builder) { builder.encodeCmpMemImm(R13, 0x44, 0x55, MicroOpBits::B8, K_EMIT); });
        runCase("set_cond_above_r8", "41 0F 97 C0", [&](MicroInstrBuilder& builder) { builder.encodeSetCondReg(R8, MicroCond::Above, K_EMIT); });
        runCase("load_cond_reg_reg_gt", "4D 0F 4F CA", [&](MicroInstrBuilder& builder) { builder.encodeLoadCondRegReg(R9, R10, MicroCond::Greater, MicroOpBits::B64, K_EMIT); });
        runCase("clear_reg_r11_b64", "4D 31 DB", [&](MicroInstrBuilder& builder) { builder.encodeClearReg(R11, MicroOpBits::B64, K_EMIT); });
        runCase("clear_reg_xmm1_b64", "66 0F 57 C9", [&](MicroInstrBuilder& builder) { builder.encodeClearReg(XMM1, MicroOpBits::B64, K_EMIT); });
    }

    void runCasesUnaryOps(const RunCaseFn& runCase)
    {
        runCase("op_unary_reg_not_r8", "49 F7 D0", [&](MicroInstrBuilder& builder) { builder.encodeOpUnaryReg(R8, MicroOp::BitwiseNot, MicroOpBits::B64, K_EMIT); });
        runCase("op_unary_reg_neg_r9_b32", "41 F7 D9", [&](MicroInstrBuilder& builder) { builder.encodeOpUnaryReg(R9, MicroOp::Negate, MicroOpBits::B32, K_EMIT); });
        runCase("op_unary_reg_bswap_r10_b16", "66 41 C1 C0 08", [&](MicroInstrBuilder& builder) { builder.encodeOpUnaryReg(R10, MicroOp::ByteSwap, MicroOpBits::B16, K_EMIT); });
        runCase("op_unary_reg_bswap_r11_b64", "49 0F CB", [&](MicroInstrBuilder& builder) { builder.encodeOpUnaryReg(R11, MicroOp::ByteSwap, MicroOpBits::B64, K_EMIT); });
        runCase("op_unary_mem_not_r12_b32", "F7 54 24 20", [&](MicroInstrBuilder& builder) { builder.encodeOpUnaryMem(R12, 0x20, MicroOp::BitwiseNot, MicroOpBits::B32, K_EMIT); });
        runCase("op_unary_mem_neg_r13", "48 F7 5D 40", [&](MicroInstrBuilder& builder) { builder.encodeOpUnaryMem(R13, 0x40, MicroOp::Negate, MicroOpBits::B64, K_EMIT); });
    }

    void runCasesBinaryRegRegOps(const RunCaseFn& runCase)
    {
        runCase("op_binary_reg_reg_add", "4D 01 C8", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R8, R9, MicroOp::Add, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_sub", "4D 29 C8", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R8, R9, MicroOp::Subtract, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_and", "4D 21 C8", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R8, R9, MicroOp::And, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_or", "4D 09 C8", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R8, R9, MicroOp::Or, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_xor", "4D 31 C8", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R8, R9, MicroOp::Xor, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_xchg", "4D 87 C8", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R8, R9, MicroOp::Exchange, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_bsf", "4D 0F BC C1", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R8, R9, MicroOp::BitScanForward, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_bsr", "4D 0F BD C1", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R8, R9, MicroOp::BitScanReverse, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_popcnt", "F3 4D 0F B8 C1", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R8, R9, MicroOp::PopCount, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_mul_signed", "4D 0F AF C1", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R8, R9, MicroOp::MultiplySigned, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_shl_rcx", "49 D3 E2", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R10, RCX, MicroOp::ShiftLeft, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_rol", "49 D3 C2", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R10, RCX, MicroOp::RotateLeft, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_ror", "49 D3 CA", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R10, RCX, MicroOp::RotateRight, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_sar", "49 D3 FA", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R10, RCX, MicroOp::ShiftArithmeticRight, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_shr", "49 D3 EA", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R10, RCX, MicroOp::ShiftRight, MicroOpBits::B64, K_EMIT); });

        runCase("op_binary_reg_reg_mul_unsigned", "49 F7 E1", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(RAX, R9, MicroOp::MultiplyUnsigned, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_div_unsigned", "48 31 D2 49 F7 F3", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(RAX, R11, MicroOp::DivideUnsigned, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_div_signed", "48 99 49 F7 F8", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(RAX, R8, MicroOp::DivideSigned, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_mod_unsigned", "48 31 D2 49 F7 F1 48 89 D0", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(RAX, R9, MicroOp::ModuloUnsigned, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_mod_signed", "48 99 49 F7 FA 48 89 D0", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(RAX, R10, MicroOp::ModuloSigned, MicroOpBits::B64, K_EMIT); });

        runCase("op_binary_reg_reg_float_and", "66 0F 54 C1", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatAnd, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_float_div", "F2 0F 5E C1", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatDivide, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_float_max", "F2 0F 5F C1", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatMax, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_float_min", "F2 0F 5D C1", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatMin, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_float_sqrt", "66 0F 51 C1", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatSqrt, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_float_sub", "F2 0F 5C C1", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatSubtract, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_float_xor", "66 0F 57 C1", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatXor, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_reg_cvt_float_float", "F2 0F 5A C1", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(XMM0, XMM1, MicroOp::ConvertFloatToFloat, MicroOpBits::B64, K_EMIT); });
    }

    void runCasesBinaryRegMemOps(const RunCaseFn& runCase)
    {
        runCase("op_binary_reg_mem_sub", "4D 2B 4C 24 24", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegMem(R9, R12, 0x24, MicroOp::Subtract, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_mem_and", "4D 23 4C 24 24", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegMem(R9, R12, 0x24, MicroOp::And, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_mem_or", "4D 0B 4C 24 24", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegMem(R9, R12, 0x24, MicroOp::Or, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_mem_xor", "4D 33 4C 24 24", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegMem(R9, R12, 0x24, MicroOp::Xor, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_mem_mul_signed", "4D 0F AF 4C 24 24", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegMem(R9, R12, 0x24, MicroOp::MultiplySigned, MicroOpBits::B64, K_EMIT); });
    }

    void runCasesBinaryMemRegOps(const RunCaseFn& runCase)
    {
        runCase("op_binary_mem_reg_add_lock", "F0 4D 01 55 20", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemReg(R13, 0x20, R10, MicroOp::Add, MicroOpBits::B64, K_LOCK); });
        runCase("op_binary_mem_reg_sub_b32", "45 29 5C 24 30", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemReg(R12, 0x30, R11, MicroOp::Subtract, MicroOpBits::B32, K_EMIT); });
        runCase("op_binary_mem_reg_and_b64", "4C 21 44 24 44", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemReg(RSP, 0x44, R8, MicroOp::And, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_reg_or_b64", "4C 09 4D 40", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemReg(RBP, 0x40, R9, MicroOp::Or, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_reg_xor_b64", "4D 31 54 24 20", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemReg(R12, 0x20, R10, MicroOp::Xor, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_reg_shl_rcx", "49 D3 65 18", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemReg(R13, 0x18, RCX, MicroOp::ShiftLeft, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_reg_shr_rcx", "49 D3 6C 24 28", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemReg(R12, 0x28, RCX, MicroOp::ShiftRight, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_reg_sar_rcx", "48 D3 7C 24 38", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemReg(RSP, 0x38, RCX, MicroOp::ShiftArithmeticRight, MicroOpBits::B64, K_EMIT); });
    }

    void runCasesBinaryImmOps(const RunCaseFn& runCase)
    {
        runCase("op_binary_reg_imm_add_r8", "49 83 C0 02", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R8, 2, MicroOp::Add, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_imm_sub_r9", "49 83 E9 7F", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R9, 0x7F, MicroOp::Subtract, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_imm_and_r10", "49 83 E2 7F", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R10, 0x7F, MicroOp::And, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_imm_or_r11", "49 83 CB 7F", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R11, 0x7F, MicroOp::Or, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_imm_xor_r12", "49 83 F4 7F", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R12, 0x7F, MicroOp::Xor, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_imm_mul", "4D 6B ED 07", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R13, 7, MicroOp::MultiplySigned, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_imm_shl_1", "49 D1 E0", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R8, 1, MicroOp::ShiftLeft, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_imm_shr_5", "49 C1 E9 05", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R9, 5, MicroOp::ShiftRight, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_imm_sar_9", "49 C1 FA 09", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R10, 9, MicroOp::ShiftArithmeticRight, MicroOpBits::B64, K_EMIT); });

        runCase("op_binary_mem_imm_add", "49 83 44 24 10 02", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemImm(R12, 0x10, 2, MicroOp::Add, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_imm_sub", "49 83 6D 20 7F", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemImm(R13, 0x20, 0x7F, MicroOp::Subtract, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_imm_and", "48 83 64 24 30 7F", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemImm(RSP, 0x30, 0x7F, MicroOp::And, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_imm_or", "48 83 4D 40 7F", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemImm(RBP, 0x40, 0x7F, MicroOp::Or, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_imm_xor", "49 83 74 24 50 7F", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemImm(R12, 0x50, 0x7F, MicroOp::Xor, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_imm_shl_1", "49 D1 65 60", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemImm(R13, 0x60, 1, MicroOp::ShiftLeft, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_imm_shr_4", "48 C1 6C 24 70 04", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemImm(RSP, 0x70, 4, MicroOp::ShiftRight, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_imm_sar", "48 C1 BD 80 00 00 00 08", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemImm(RBP, 0x80, 8, MicroOp::ShiftArithmeticRight, MicroOpBits::B64, K_EMIT); });
    }

    void runCasesTernaryAndConvert(const RunCaseFn& runCase)
    {
        runCase("op_ternary_madd", "F2 0F 59 C1 F2 0F 58 C2", [&](MicroInstrBuilder& builder) { builder.encodeOpTernaryRegRegReg(XMM0, XMM1, XMM2, MicroOp::MultiplyAdd, MicroOpBits::B64, K_EMIT); });
        runCase("op_ternary_cmpxchg_lock", "F0 4D 0F B1 1C 24", [&](MicroInstrBuilder& builder) { builder.encodeOpTernaryRegRegReg(RAX, R12, R11, MicroOp::CompareExchange, MicroOpBits::B64, K_LOCK); });
        runCase("convert_i2f_b64", "F2 49 0F 2A D2", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(XMM2, R10, MicroOp::ConvertIntToFloat, MicroOpBits::B64, K_B64); });
        runCase("convert_f2i_b64", "F2 4C 0F 2C DB", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(R11, XMM3, MicroOp::ConvertFloatToInt, MicroOpBits::B64, K_B64); });
    }

    void runCasesEdgeAndCombinations(const RunCaseFn& runCase)
    {
        runCase("push_r8", "41 50", [&](MicroInstrBuilder& builder) { builder.encodePush(R8, K_EMIT); });
        runCase("pop_r15", "41 5F", [&](MicroInstrBuilder& builder) { builder.encodePop(R15, K_EMIT); });
        runCase("call_reg_rax", "FF D0", [&](MicroInstrBuilder& builder) { builder.encodeCallReg(RAX, CallConvKind::C, K_EMIT); });
        runCase("jump_reg_r8", "41 FF E0", [&](MicroInstrBuilder& builder) { builder.encodeJumpReg(R8, K_EMIT); });
        runCase("jump_not_zero_b8_patch_here", "75 00", [&](MicroInstrBuilder& builder) {
            MicroJump jump;
            builder.encodeJump(jump, MicroCondJump::NotZero, MicroOpBits::B8, K_EMIT);
            builder.encodePatchJump(jump, K_EMIT);
        });
        runCase("jump_above_b32_patch_here", "0F 87 00 00 00 00", [&](MicroInstrBuilder& builder) {
            MicroJump jump;
            builder.encodeJump(jump, MicroCondJump::Above, MicroOpBits::B32, K_EMIT);
            builder.encodePatchJump(jump, K_EMIT);
        });

        runCase("load_reg_mem_r8_rbp_0_b64", "4C 8B 45 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegMem(R8, RBP, 0, MicroOpBits::B64, K_EMIT); });
        runCase("load_reg_mem_r8_r13_0_b64", "4D 8B 45 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegMem(R8, R13, 0, MicroOpBits::B64, K_EMIT); });
        runCase("load_reg_mem_r9_r12_80_b64", "4D 8B 8C 24 80 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegMem(R9, R12, 0x80, MicroOpBits::B64, K_EMIT); });
        runCase("load_mem_reg_rbp_0_r8_b64", "4C 89 45 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadMemReg(RBP, 0, R8, MicroOpBits::B64, K_EMIT); });
        runCase("load_mem_reg_r13_0_r8_b64", "4D 89 45 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadMemReg(R13, 0, R8, MicroOpBits::B64, K_EMIT); });
        runCase("load_mem_imm_r13_80_b8", "41 C6 85 80 00 00 00 5A", [&](MicroInstrBuilder& builder) { builder.encodeLoadMemImm(R13, 0x80, 0x5A, MicroOpBits::B8, K_EMIT); });
        runCase("lea_reg_mem_r10_rsp_0_b64", "49 89 E2", [&](MicroInstrBuilder& builder) { builder.encodeLoadAddressRegMem(R10, RSP, 0, MicroOpBits::B64, K_EMIT); });
        runCase("lea_reg_mem_r8_rbp_0_b64", "49 89 E8", [&](MicroInstrBuilder& builder) { builder.encodeLoadAddressRegMem(R8, RBP, 0, MicroOpBits::B64, K_EMIT); });

        runCase("load_reg_reg_r9_r10_b8", "45 88 D1", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegReg(R9, R10, MicroOpBits::B8, K_EMIT); });
        runCase("load_reg_reg_rdx_rcx_b8", "88 CA", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegReg(RDX, RCX, MicroOpBits::B8, K_EMIT); });
        runCase("clear_reg_r9_b32", "45 31 C9", [&](MicroInstrBuilder& builder) { builder.encodeClearReg(R9, MicroOpBits::B32, K_EMIT); });
        runCase("cmp_reg_imm_r8_7f_b64", "49 83 F8 7F", [&](MicroInstrBuilder& builder) { builder.encodeCmpRegImm(R8, 0x7F, MicroOpBits::B64, K_EMIT); });
        runCase("cmp_reg_imm_r8_80_b64", "49 81 F8 80 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeCmpRegImm(R8, 0x80, MicroOpBits::B64, K_EMIT); });
        runCase("cmp_mem_imm_r12_12345678_b8", "41 80 BC 24 78 56 34 12 12", [&](MicroInstrBuilder& builder) { builder.encodeCmpMemImm(R12, 0x12345678, 0x12, MicroOpBits::B8, K_EMIT); });

        runCase("op_binary_reg_imm_add_r8_7f_b64", "49 83 C0 7F", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R8, 0x7F, MicroOp::Add, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_imm_add_r8_80_b64", "49 81 C0 80 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R8, 0x80, MicroOp::Add, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_imm_sub_r9_ff_b64", "49 83 E9 FF", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R9, 0xFFFFFFFFFFFFFFFF, MicroOp::Subtract, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_imm_and_80_b64", "49 81 64 24 20 80 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemImm(R12, 0x20, 0x80, MicroOp::And, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_imm_shl_0_b64", "49 C1 E0 00", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R8, 0, MicroOp::ShiftLeft, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_reg_imm_shr_63_b64", "49 C1 E9 3F", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(R9, 63, MicroOp::ShiftRight, MicroOpBits::B64, K_EMIT); });
        runCase("op_binary_mem_reg_or_r13_r14_b64", "4D 09 75 40", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemReg(R13, 0x40, R14, MicroOp::Or, MicroOpBits::B64, K_EMIT); });
    }
}

SWC_BACKEND_TEST_BEGIN(EncodeX64)
{
    const RunCaseFn runCase = [&](const char* name, const char* expectedHex, const BuilderCaseFn& fn) {
        X64Encoder encoder(ctx);
        Backend::Unittest::runEncodeCase(ctx, encoder, name, expectedHex, fn);
    };

    runCasesFlow(runCase);
    runCasesLoad(runCase);
    runCasesCmpAndCond(runCase);
    runCasesUnaryOps(runCase);
    runCasesBinaryRegRegOps(runCase);
    runCasesBinaryRegMemOps(runCase);
    runCasesBinaryMemRegOps(runCase);
    runCasesBinaryImmOps(runCase);
    runCasesTernaryAndConvert(runCase);
    runCasesEdgeAndCombinations(runCase);
}
SWC_BACKEND_TEST_END()

#endif

SWC_END_NAMESPACE();
