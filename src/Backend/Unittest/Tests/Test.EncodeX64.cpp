#include "pch.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Unittest/BackendUnittestHelpers.h"
#include "Main/CompilerInstance.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    class TestX64Encoder final : public X64Encoder
    {
    public:
        explicit TestX64Encoder(TaskContext& ctx) :
            X64Encoder(ctx)
        {
        }

        void setupJumpTableState(EncoderFunction& fct, uint32_t symCsIndex = 0, uint32_t textOffset = 0)
        {
            cpuFct_            = &fct;
            symCsIndex_        = symCsIndex;
            textSectionOffset_ = textOffset;
        }
    };

    using BuilderCaseFn = std::function<void(MicroBuilder&)>;
    using RunCaseFn     = std::function<Result(const char*, const char*, const BuilderCaseFn&)>;

    constexpr MicroReg RAX  = MicroReg::intReg(0);
    constexpr MicroReg RCX  = MicroReg::intReg(2);
    constexpr MicroReg RDX  = MicroReg::intReg(3);
    constexpr MicroReg RSP  = MicroReg::intReg(4);
    constexpr MicroReg RBP  = MicroReg::intReg(5);
    constexpr MicroReg R8   = MicroReg::intReg(8);
    constexpr MicroReg R9   = MicroReg::intReg(9);
    constexpr MicroReg R10  = MicroReg::intReg(10);
    constexpr MicroReg R11  = MicroReg::intReg(11);
    constexpr MicroReg R12  = MicroReg::intReg(12);
    constexpr MicroReg R13  = MicroReg::intReg(13);
    constexpr MicroReg R14  = MicroReg::intReg(14);
    constexpr MicroReg R15  = MicroReg::intReg(15);
    constexpr MicroReg XMM0 = MicroReg::floatReg(0);
    constexpr MicroReg XMM1 = MicroReg::floatReg(1);
    constexpr MicroReg XMM2 = MicroReg::floatReg(2);
    constexpr MicroReg XMM3 = MicroReg::floatReg(3);

#define ENCODE_CASE(__name, __hex, ...)                                        \
    do                                                                         \
    {                                                                          \
        RESULT_VERIFY(runCase(__name, __hex, [&](MicroBuilder& builder) { auto& b = builder; __VA_ARGS__; })); \
    } while (false)

    Result buildFlow(const RunCaseFn& runCase)
    {
        ENCODE_CASE("nop", "90", b.emitNop(););
        ENCODE_CASE("push_r8", "41 50", b.emitPush(R8););
        ENCODE_CASE("push_r12", "41 54", b.emitPush(R12););
        ENCODE_CASE("pop_r15", "41 5F", b.emitPop(R15););
        ENCODE_CASE("pop_r12", "41 5C", b.emitPop(R12););
        ENCODE_CASE("call_local", "48 B8 00 00 00 00 00 00 00 00 FF D0", b.emitCallLocal({}, CallConvKind::C););
        ENCODE_CASE("call_extern", "48 B8 00 00 00 00 00 00 00 00 FF D0", b.emitCallExtern(nullptr, CallConvKind::C););
        ENCODE_CASE("call_local_repeat", "48 B8 00 00 00 00 00 00 00 00 FF D0", b.emitCallLocal({}, CallConvKind::C););
        ENCODE_CASE("call_reg_rax", "FF D0", b.emitCallReg(RAX, CallConvKind::C););
        ENCODE_CASE("call_reg_r9", "41 FF D1", b.emitCallReg(R9, CallConvKind::C););
        ENCODE_CASE("jump_reg_r8", "41 FF E0", b.emitJumpReg(R8););
        ENCODE_CASE("jump_reg_r13", "41 FF E5", b.emitJumpReg(R13););
        ENCODE_CASE("ret", "C3", b.emitRet(););

        ENCODE_CASE("jump_not_zero_b8_patch_here", "75 00",
                    const auto l = b.createLabel();
                    b.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B8, l);
                    b.placeLabel(l););
        ENCODE_CASE("jump_zero_b8_patch_here", "74 00",
                    const auto l = b.createLabel();
                    b.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B8, l);
                    b.placeLabel(l););
        ENCODE_CASE("jump_not_equal_b8_patch_here", "75 00",
                    const auto l = b.createLabel();
                    b.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B8, l);
                    b.placeLabel(l););
        ENCODE_CASE("jump_above_b32_patch_here", "0F 87 00 00 00 00",
                    const auto l = b.createLabel();
                    b.emitJumpToLabel(MicroCond::Above, MicroOpBits::B32, l);
                    b.placeLabel(l););
        ENCODE_CASE("jump_equal_b32_patch_here", "0F 84 00 00 00 00",
                    const auto l = b.createLabel();
                    b.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, l);
                    b.placeLabel(l););
        ENCODE_CASE("jump_less_b32_patch_here", "0F 8C 00 00 00 00",
                    const auto l = b.createLabel();
                    b.emitJumpToLabel(MicroCond::Less, MicroOpBits::B32, l);
                    b.placeLabel(l););
        return Result::Continue;
    }

    Result buildLoad(const RunCaseFn& runCase)
    {
        ENCODE_CASE("load_reg_imm_rax_b8", "B0 12", b.emitLoadRegImm(RAX, 0x12, MicroOpBits::B8););
        ENCODE_CASE("load_reg_imm_r8_b16", "66 41 B8 34 12", b.emitLoadRegImm(R8, 0x1234, MicroOpBits::B16););
        ENCODE_CASE("load_reg_imm_r9_b32", "41 B9 78 56 34 12", b.emitLoadRegImm(R9, 0x12345678, MicroOpBits::B32););
        ENCODE_CASE("load_reg_imm_r10_b64", "49 BA F0 DE BC 9A 78 56 34 12", b.emitLoadRegImm(R10, 0x123456789ABCDEF0, MicroOpBits::B64););

        ENCODE_CASE("load_reg_reg_r11_r8_b64", "4D 89 C3", b.emitLoadRegReg(R11, R8, MicroOpBits::B64););
        ENCODE_CASE("load_reg_reg_r9_r10_b8", "45 88 D1", b.emitLoadRegReg(R9, R10, MicroOpBits::B8););
        ENCODE_CASE("load_reg_reg_rdx_rcx_b8", "88 CA", b.emitLoadRegReg(RDX, RCX, MicroOpBits::B8););
        ENCODE_CASE("load_reg_reg_xmm0_xmm1_b32", "F3 0F 10 C1", b.emitLoadRegReg(XMM0, XMM1, MicroOpBits::B32););
        ENCODE_CASE("load_reg_reg_xmm2_r9_b32", "66 41 0F 6E D1", b.emitLoadRegReg(XMM2, R9, MicroOpBits::B32););
        ENCODE_CASE("load_reg_reg_r10_xmm3_b32", "66 41 0F 7E DA", b.emitLoadRegReg(R10, XMM3, MicroOpBits::B32););
        ENCODE_CASE("load_reg_imm_xmm0_b32_conform", "48 83 EC 08 40 C7 04 24 01 00 00 00 F3 40 0F 10 04 24 48 83 C4 08", b.emitLoadRegImm(XMM0, 1, MicroOpBits::B32););

        ENCODE_CASE("load_reg_mem_r8_rbp_0_b64", "4C 8B 45 00", b.emitLoadRegMem(R8, RBP, 0, MicroOpBits::B64););
        ENCODE_CASE("load_reg_mem_r8_r13_0_b64", "4D 8B 45 00", b.emitLoadRegMem(R8, R13, 0, MicroOpBits::B64););
        ENCODE_CASE("load_reg_mem_r9_r12_80_b64", "4D 8B 8C 24 80 00 00 00", b.emitLoadRegMem(R9, R12, 0x80, MicroOpBits::B64););
        ENCODE_CASE("load_reg_mem_r8_r12_0_b64", "4D 8B 04 24", b.emitLoadRegMem(R8, R12, 0, MicroOpBits::B64););
        ENCODE_CASE("load_reg_mem_r9_rbp_7f_b32", "44 8B 4D 7F", b.emitLoadRegMem(R9, RBP, 0x7F, MicroOpBits::B32););
        ENCODE_CASE("load_reg_mem_r8_rbp_neg80_b64", "4C 8B 45 80", b.emitLoadRegMem(R8, RBP, 0xFFFFFFFFFFFFFF80, MicroOpBits::B64););
        ENCODE_CASE("load_reg_mem_xmm0_rsp_1234_b64", "F2 40 0F 10 84 24 34 12 00 00", b.emitLoadRegMem(XMM0, RSP, 0x1234, MicroOpBits::B64););
        ENCODE_CASE("load_reg_mem_r10_r13_40_b16", "66 45 8B 55 40", b.emitLoadRegMem(R10, R13, 0x40, MicroOpBits::B16););

        ENCODE_CASE("load_sext_reg_mem_b8", "4D 0F BE 5C 24 10", b.emitLoadSignedExtendRegMem(R11, R12, 0x10, MicroOpBits::B64, MicroOpBits::B8););
        ENCODE_CASE("load_sext_reg_mem_b16", "4D 0F BF 55 20", b.emitLoadSignedExtendRegMem(R10, R13, 0x20, MicroOpBits::B64, MicroOpBits::B16););
        ENCODE_CASE("load_sext_reg_mem_b32", "4C 63 4C 24 30", b.emitLoadSignedExtendRegMem(R9, RSP, 0x30, MicroOpBits::B64, MicroOpBits::B32););
        ENCODE_CASE("load_sext_reg_reg_b8", "4D 0F BE C3", b.emitLoadSignedExtendRegReg(R8, R11, MicroOpBits::B64, MicroOpBits::B8););
        ENCODE_CASE("load_sext_reg_reg_b16", "4D 0F BF CA", b.emitLoadSignedExtendRegReg(R9, R10, MicroOpBits::B64, MicroOpBits::B16););
        ENCODE_CASE("load_sext_reg_reg_b32", "4D 63 D1", b.emitLoadSignedExtendRegReg(R10, R9, MicroOpBits::B64, MicroOpBits::B32););

        ENCODE_CASE("load_zext_reg_mem_b8", "4D 0F B6 5C 24 44", b.emitLoadZeroExtendRegMem(R11, R12, 0x44, MicroOpBits::B64, MicroOpBits::B8););
        ENCODE_CASE("load_zext_reg_mem_b16", "4D 0F B7 95 88 00 00 00", b.emitLoadZeroExtendRegMem(R10, R13, 0x88, MicroOpBits::B64, MicroOpBits::B16););
        ENCODE_CASE("load_zext_reg_mem_b32", "44 8B 4C 24 24", b.emitLoadZeroExtendRegMem(R9, RSP, 0x24, MicroOpBits::B64, MicroOpBits::B32););
        ENCODE_CASE("load_zext_reg_reg_b8", "4D 0F B6 C3", b.emitLoadZeroExtendRegReg(R8, R11, MicroOpBits::B64, MicroOpBits::B8););
        ENCODE_CASE("load_zext_reg_reg_b16", "4D 0F B7 CA", b.emitLoadZeroExtendRegReg(R9, R10, MicroOpBits::B64, MicroOpBits::B16););
        ENCODE_CASE("load_zext_reg_reg_b32", "45 89 CA", b.emitLoadZeroExtendRegReg(R10, R9, MicroOpBits::B64, MicroOpBits::B32););

        ENCODE_CASE("lea_reg_mem_rip", "4C 8D 15", b.emitLoadAddressRegMem(R10, MicroReg::instructionPointer(), 0, MicroOpBits::B64););
        ENCODE_CASE("lea_reg_mem_r11_r12_0", "4D 89 E3", b.emitLoadAddressRegMem(R11, R12, 0, MicroOpBits::B64););
        ENCODE_CASE("lea_reg_mem_r10_rsp_0_b64", "49 89 E2", b.emitLoadAddressRegMem(R10, RSP, 0, MicroOpBits::B64););
        ENCODE_CASE("lea_reg_mem_r8_rbp_0_b64", "49 89 E8", b.emitLoadAddressRegMem(R8, RBP, 0, MicroOpBits::B64););
        ENCODE_CASE("lea_reg_mem_r9_r13_1234", "4D 8D 8D 34 12 00 00", b.emitLoadAddressRegMem(R9, R13, 0x1234, MicroOpBits::B64););

        ENCODE_CASE("load_amc_reg_mem", "4F 8B 54 85 20", b.emitLoadAmcRegMem(R10, MicroOpBits::B64, R13, R8, 4, 0x20, MicroOpBits::B64););
        ENCODE_CASE("load_amc_reg_mem_xmm2", "66 4B 0F 6E 54 4C 7F", b.emitLoadAmcRegMem(XMM2, MicroOpBits::B64, R12, R9, 2, 0x7F, MicroOpBits::B64););
        ENCODE_CASE("load_amc_mem_reg", "47 89 94 C5 00 01 00 00", b.emitLoadAmcMemReg(R13, R8, 8, 0x100, MicroOpBits::B64, R10, MicroOpBits::B32););
        ENCODE_CASE("load_amc_mem_reg_xmm3", "66 4B 0F 7E 5C 0C 40", b.emitLoadAmcMemReg(R12, R9, 1, 0x40, MicroOpBits::B64, XMM3, MicroOpBits::B64););
        ENCODE_CASE("load_amc_mem_imm", "43 C7 44 85 24 34 12 00 00", b.emitLoadAmcMemImm(R13, R8, 4, 0x24, MicroOpBits::B64, 0x1234, MicroOpBits::B32););
        ENCODE_CASE("lea_amc_reg_mem", "4F 8D 5C 4D 40", b.emitLoadAddressAmcRegMem(R11, MicroOpBits::B64, R13, R9, 2, 0x40, MicroOpBits::B64););

        ENCODE_CASE("load_mem_reg_rbp_0_r8_b64", "4C 89 45 00", b.emitLoadMemReg(RBP, 0, R8, MicroOpBits::B64););
        ENCODE_CASE("load_mem_reg_r13_0_r8_b64", "4D 89 45 00", b.emitLoadMemReg(R13, 0, R8, MicroOpBits::B64););
        ENCODE_CASE("load_mem_reg_r12_r8_b64", "4D 89 04 24", b.emitLoadMemReg(R12, 0, R8, MicroOpBits::B64););
        ENCODE_CASE("load_mem_reg_r13_xmm0_b64", "F2 41 0F 11 45 7F", b.emitLoadMemReg(R13, 0x7F, XMM0, MicroOpBits::B64););
        ENCODE_CASE("load_mem_reg_r13_neg80_r8_b64", "4D 89 45 80", b.emitLoadMemReg(R13, 0xFFFFFFFFFFFFFF80, R8, MicroOpBits::B64););
        ENCODE_CASE("load_mem_reg_rsp_b32", "44 89 8C 24 20 01 00 00", b.emitLoadMemReg(RSP, 0x120, R9, MicroOpBits::B32););
        ENCODE_CASE("load_mem_imm_r12_b8", "41 C6 04 24 7F", b.emitLoadMemImm(R12, 0, 0x7F, MicroOpBits::B8););
        ENCODE_CASE("load_mem_imm_r13_80_b8", "41 C6 85 80 00 00 00 5A", b.emitLoadMemImm(R13, 0x80, 0x5A, MicroOpBits::B8););
        ENCODE_CASE("load_mem_imm_r13_b16", "66 41 C7 45 7F 34 12", b.emitLoadMemImm(R13, 0x7F, 0x1234, MicroOpBits::B16););
        ENCODE_CASE("load_mem_imm_rsp_b32", "40 C7 44 24 40 78 56 34 12", b.emitLoadMemImm(RSP, 0x40, 0x12345678, MicroOpBits::B32););
        ENCODE_CASE("load_mem_imm_rbp_b64", "48 C7 45 20 80 FF FF FF", b.emitLoadMemImm(RBP, 0x20, 0xFFFFFFFFFFFFFF80, MicroOpBits::B64););
        return Result::Continue;
    }

    Result buildCmpAndCond(const RunCaseFn& runCase)
    {
        ENCODE_CASE("cmp_reg_reg_r8_r9_b64", "4D 39 C8", b.emitCmpRegReg(R8, R9, MicroOpBits::B64););
        ENCODE_CASE("cmp_reg_reg_xmm0_xmm1_b64", "66 0F 2F C1", b.emitCmpRegReg(XMM0, XMM1, MicroOpBits::B64););
        ENCODE_CASE("cmp_reg_zero_r8_b64", "4D 85 C0", b.emitCmpRegZero(R8, MicroOpBits::B64););
        ENCODE_CASE("cmp_reg_imm_r8_7f_b64", "49 83 F8 7F", b.emitCmpRegImm(R8, 0x7F, MicroOpBits::B64););
        ENCODE_CASE("cmp_reg_imm_r8_80_b64", "49 81 F8 80 00 00 00", b.emitCmpRegImm(R8, 0x80, MicroOpBits::B64););
        ENCODE_CASE("cmp_reg_imm_r8_neg2147483648_b64", "49 81 F8 00 00 00 80", b.emitCmpRegImm(R8, 0xFFFFFFFF80000000, MicroOpBits::B64););
        ENCODE_CASE("cmp_reg_imm_r10_b32", "41 81 FA 34 12 00 00", b.emitCmpRegImm(R10, 0x1234, MicroOpBits::B32););
        ENCODE_CASE("cmp_reg_imm_r10_80000000_b32", "41 81 FA 00 00 00 80", b.emitCmpRegImm(R10, 0x80000000, MicroOpBits::B32););
        ENCODE_CASE("cmp_reg_imm_r8_zero_b64", "4D 85 C0", b.emitCmpRegImm(R8, 0, MicroOpBits::B64););
        ENCODE_CASE("cmp_mem_reg_r12_r11_b64", "4D 39 5C 24 40", b.emitCmpMemReg(R12, 0x40, R11, MicroOpBits::B64););
        ENCODE_CASE("cmp_mem_imm_r12_12345678_b8", "41 80 BC 24 78 56 34 12 12", b.emitCmpMemImm(R12, 0x12345678, 0x12, MicroOpBits::B8););
        ENCODE_CASE("cmp_mem_imm_r13_b8", "41 80 7D 44 55", b.emitCmpMemImm(R13, 0x44, 0x55, MicroOpBits::B8););
        ENCODE_CASE("set_cond_above_r8", "41 0F 97 C0", b.emitSetCondReg(R8, MicroCond::Above););
        ENCODE_CASE("set_cond_above_r8_zext", "41 0F 97 C0 45 0F B6 C0", b.emitSetCondRegZeroExtend(R8, MicroCond::Above););
        ENCODE_CASE("load_cond_reg_reg_gt", "4D 0F 4F CA", b.emitLoadCondRegReg(R9, R10, MicroCond::Greater, MicroOpBits::B64););
        ENCODE_CASE("clear_reg_r9_b32", "45 31 C9", b.emitClearReg(R9, MicroOpBits::B32););
        ENCODE_CASE("clear_reg_r11_b64", "4D 31 DB", b.emitClearReg(R11, MicroOpBits::B64););
        ENCODE_CASE("clear_reg_xmm1_b64", "66 0F 57 C9", b.emitClearReg(XMM1, MicroOpBits::B64););
        return Result::Continue;
    }

    Result buildUnaryOps(const RunCaseFn& runCase)
    {
        ENCODE_CASE("op_unary_reg_not_r8", "49 F7 D0", b.emitOpUnaryReg(R8, MicroOp::BitwiseNot, MicroOpBits::B64););
        ENCODE_CASE("op_unary_reg_neg_r9_b32", "41 F7 D9", b.emitOpUnaryReg(R9, MicroOp::Negate, MicroOpBits::B32););
        ENCODE_CASE("op_unary_reg_bswap_r10_b16", "66 41 C1 C0 08", b.emitOpUnaryReg(R10, MicroOp::ByteSwap, MicroOpBits::B16););
        ENCODE_CASE("op_unary_reg_bswap_r11_b64", "49 0F CB", b.emitOpUnaryReg(R11, MicroOp::ByteSwap, MicroOpBits::B64););
        ENCODE_CASE("op_unary_mem_not_r12_b32", "F7 54 24 20", b.emitOpUnaryMem(R12, 0x20, MicroOp::BitwiseNot, MicroOpBits::B32););
        ENCODE_CASE("op_unary_mem_neg_r13", "48 F7 5D 40", b.emitOpUnaryMem(R13, 0x40, MicroOp::Negate, MicroOpBits::B64););
        return Result::Continue;
    }

    Result buildBinaryRegRegOps(const RunCaseFn& runCase)
    {
        ENCODE_CASE("op_binary_reg_reg_add", "4D 01 C8", b.emitOpBinaryRegReg(R8, R9, MicroOp::Add, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_sub", "4D 29 C8", b.emitOpBinaryRegReg(R8, R9, MicroOp::Subtract, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_and", "4D 21 C8", b.emitOpBinaryRegReg(R8, R9, MicroOp::And, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_or", "4D 09 C8", b.emitOpBinaryRegReg(R8, R9, MicroOp::Or, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_xor", "4D 31 C8", b.emitOpBinaryRegReg(R8, R9, MicroOp::Xor, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_xchg", "4D 87 C8", b.emitOpBinaryRegReg(R8, R9, MicroOp::Exchange, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_bsf", "4D 0F BC C1", b.emitOpBinaryRegReg(R8, R9, MicroOp::BitScanForward, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_bsr", "4D 0F BD C1", b.emitOpBinaryRegReg(R8, R9, MicroOp::BitScanReverse, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_popcnt", "F3 4D 0F B8 C1", b.emitOpBinaryRegReg(R8, R9, MicroOp::PopCount, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_mul_signed", "4D 0F AF C1", b.emitOpBinaryRegReg(R8, R9, MicroOp::MultiplySigned, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_shl_rcx", "49 D3 E2", b.emitOpBinaryRegReg(R10, RCX, MicroOp::ShiftLeft, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_rol", "49 D3 C2", b.emitOpBinaryRegReg(R10, RCX, MicroOp::RotateLeft, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_ror", "49 D3 CA", b.emitOpBinaryRegReg(R10, RCX, MicroOp::RotateRight, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_sar", "49 D3 FA", b.emitOpBinaryRegReg(R10, RCX, MicroOp::ShiftArithmeticRight, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_shr", "49 D3 EA", b.emitOpBinaryRegReg(R10, RCX, MicroOp::ShiftRight, MicroOpBits::B64););

        ENCODE_CASE("op_binary_reg_reg_mul_unsigned", "49 F7 E1", b.emitOpBinaryRegReg(RAX, R9, MicroOp::MultiplyUnsigned, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_div_unsigned", "48 31 D2 49 F7 F3", b.emitOpBinaryRegReg(RAX, R11, MicroOp::DivideUnsigned, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_div_signed", "48 99 49 F7 F8", b.emitOpBinaryRegReg(RAX, R8, MicroOp::DivideSigned, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_mod_unsigned", "48 31 D2 49 F7 F1 48 89 D0", b.emitOpBinaryRegReg(RAX, R9, MicroOp::ModuloUnsigned, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_mod_signed", "48 99 49 F7 FA 48 89 D0", b.emitOpBinaryRegReg(RAX, R10, MicroOp::ModuloSigned, MicroOpBits::B64););

        ENCODE_CASE("op_binary_reg_reg_float_and", "66 0F 54 C1", b.emitOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatAnd, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_float_div", "F2 48 0F 5E C1", b.emitOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatDivide, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_float_max", "F2 48 0F 5F C1", b.emitOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatMax, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_float_min", "F2 48 0F 5D C1", b.emitOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatMin, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_float_sqrt", "66 0F 51 C1", b.emitOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatSqrt, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_float_sub", "F2 48 0F 5C C1", b.emitOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatSubtract, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_float_xor", "66 0F 57 C1", b.emitOpBinaryRegReg(XMM0, XMM1, MicroOp::FloatXor, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_reg_cvt_float_float", "F2 48 0F 5A C1", b.emitOpBinaryRegReg(XMM0, XMM1, MicroOp::ConvertFloatToFloat, MicroOpBits::B64););
        return Result::Continue;
    }

    Result buildBinaryRegMemOps(const RunCaseFn& runCase)
    {
        ENCODE_CASE("op_binary_reg_mem_sub", "4D 2B 4C 24 24", b.emitOpBinaryRegMem(R9, R12, 0x24, MicroOp::Subtract, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_mem_and", "4D 23 4C 24 24", b.emitOpBinaryRegMem(R9, R12, 0x24, MicroOp::And, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_mem_or", "4D 0B 4C 24 24", b.emitOpBinaryRegMem(R9, R12, 0x24, MicroOp::Or, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_mem_xor", "4D 33 4C 24 24", b.emitOpBinaryRegMem(R9, R12, 0x24, MicroOp::Xor, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_mem_mul_signed", "4D 0F AF 4C 24 24", b.emitOpBinaryRegMem(R9, R12, 0x24, MicroOp::MultiplySigned, MicroOpBits::B64););
        return Result::Continue;
    }

    Result buildBinaryMemRegOps(const RunCaseFn& runCase)
    {
        ENCODE_CASE("op_binary_mem_reg_add_lock", "4D 01 55 20", b.emitOpBinaryMemReg(R13, 0x20, R10, MicroOp::Add, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_reg_sub_b32", "45 29 5C 24 30", b.emitOpBinaryMemReg(R12, 0x30, R11, MicroOp::Subtract, MicroOpBits::B32););
        ENCODE_CASE("op_binary_mem_reg_and_b64", "4C 21 44 24 44", b.emitOpBinaryMemReg(RSP, 0x44, R8, MicroOp::And, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_reg_or_b64", "4C 09 4D 40", b.emitOpBinaryMemReg(RBP, 0x40, R9, MicroOp::Or, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_reg_or_r13_r14_b64", "4D 09 75 40", b.emitOpBinaryMemReg(R13, 0x40, R14, MicroOp::Or, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_reg_xor_b64", "4D 31 54 24 20", b.emitOpBinaryMemReg(R12, 0x20, R10, MicroOp::Xor, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_reg_shl_rcx", "49 D3 65 18", b.emitOpBinaryMemReg(R13, 0x18, RCX, MicroOp::ShiftLeft, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_reg_shr_rcx", "49 D3 6C 24 28", b.emitOpBinaryMemReg(R12, 0x28, RCX, MicroOp::ShiftRight, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_reg_sar_rcx", "48 D3 7C 24 38", b.emitOpBinaryMemReg(RSP, 0x38, RCX, MicroOp::ShiftArithmeticRight, MicroOpBits::B64););
        return Result::Continue;
    }

    Result buildBinaryImmOps(const RunCaseFn& runCase)
    {
        ENCODE_CASE("op_binary_reg_imm_add_r8", "49 83 C0 02", b.emitOpBinaryRegImm(R8, 2, MicroOp::Add, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_add_r8_7f_b64", "49 83 C0 7F", b.emitOpBinaryRegImm(R8, 0x7F, MicroOp::Add, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_add_r8_80_b64", "49 81 C0 80 00 00 00", b.emitOpBinaryRegImm(R8, 0x80, MicroOp::Add, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_add_r8_neg2147483648_b64", "49 81 C0 00 00 00 80", b.emitOpBinaryRegImm(R8, 0xFFFFFFFF80000000, MicroOp::Add, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_sub_r9", "49 83 E9 7F", b.emitOpBinaryRegImm(R9, 0x7F, MicroOp::Subtract, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_sub_r9_ff_b64", "49 83 E9 FF", b.emitOpBinaryRegImm(R9, 0xFFFFFFFFFFFFFFFF, MicroOp::Subtract, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_and_r10", "49 83 E2 7F", b.emitOpBinaryRegImm(R10, 0x7F, MicroOp::And, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_or_r11", "49 83 CB 7F", b.emitOpBinaryRegImm(R11, 0x7F, MicroOp::Or, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_xor_r12", "49 83 F4 7F", b.emitOpBinaryRegImm(R12, 0x7F, MicroOp::Xor, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_mul", "4D 6B ED 07", b.emitOpBinaryRegImm(R13, 7, MicroOp::MultiplySigned, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_shl_0_b64", "49 C1 E0 00", b.emitOpBinaryRegImm(R8, 0, MicroOp::ShiftLeft, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_shl_1", "49 D1 E0", b.emitOpBinaryRegImm(R8, 1, MicroOp::ShiftLeft, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_shl_80_b64_conform", "49 C1 E0 3F", b.emitOpBinaryRegImm(R8, 0x80, MicroOp::ShiftLeft, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_shr_5", "49 C1 E9 05", b.emitOpBinaryRegImm(R9, 5, MicroOp::ShiftRight, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_shr_63_b64", "49 C1 E9 3F", b.emitOpBinaryRegImm(R9, 63, MicroOp::ShiftRight, MicroOpBits::B64););
        ENCODE_CASE("op_binary_reg_imm_sar_9", "49 C1 FA 09", b.emitOpBinaryRegImm(R10, 9, MicroOp::ShiftArithmeticRight, MicroOpBits::B64););

        ENCODE_CASE("op_binary_mem_imm_add", "49 83 44 24 10 02", b.emitOpBinaryMemImm(R12, 0x10, 2, MicroOp::Add, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_imm_sub", "49 83 6D 20 7F", b.emitOpBinaryMemImm(R13, 0x20, 0x7F, MicroOp::Subtract, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_imm_and_80_b64", "49 81 64 24 20 80 00 00 00", b.emitOpBinaryMemImm(R12, 0x20, 0x80, MicroOp::And, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_imm_and", "48 83 64 24 30 7F", b.emitOpBinaryMemImm(RSP, 0x30, 0x7F, MicroOp::And, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_imm_or", "48 83 4D 40 7F", b.emitOpBinaryMemImm(RBP, 0x40, 0x7F, MicroOp::Or, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_imm_or_neg1", "48 83 4D 40 FF", b.emitOpBinaryMemImm(RBP, 0x40, 0xFFFFFFFFFFFFFFFF, MicroOp::Or, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_imm_xor", "49 83 74 24 50 7F", b.emitOpBinaryMemImm(R12, 0x50, 0x7F, MicroOp::Xor, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_imm_shl_1", "49 D1 65 60", b.emitOpBinaryMemImm(R13, 0x60, 1, MicroOp::ShiftLeft, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_imm_shr_80_b64_conform", "48 C1 AD 80 00 00 00 3F", b.emitOpBinaryMemImm(RBP, 0x80, 0x80, MicroOp::ShiftRight, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_imm_shr_4", "48 C1 6C 24 70 04", b.emitOpBinaryMemImm(RSP, 0x70, 4, MicroOp::ShiftRight, MicroOpBits::B64););
        ENCODE_CASE("op_binary_mem_imm_sar", "48 C1 BD 80 00 00 00 08", b.emitOpBinaryMemImm(RBP, 0x80, 8, MicroOp::ShiftArithmeticRight, MicroOpBits::B64););
        return Result::Continue;
    }

    Result buildTernaryAndConvert(const RunCaseFn& runCase)
    {
        ENCODE_CASE("op_ternary_madd", "F2 0F 59 C1 F2 0F 58 C2", b.emitOpTernaryRegRegReg(XMM0, XMM1, XMM2, MicroOp::MultiplyAdd, MicroOpBits::B64););
        ENCODE_CASE("op_ternary_cmpxchg_lock", "4D 0F B1 1C 24", b.emitOpTernaryRegRegReg(RAX, R12, R11, MicroOp::CompareExchange, MicroOpBits::B64););
        ENCODE_CASE("convert_i2f_b64", "F2 49 0F 2A D2", b.emitOpBinaryRegReg(XMM2, R10, MicroOp::ConvertIntToFloat, MicroOpBits::B64););
        ENCODE_CASE("convert_f2i_b64", "F2 4C 0F 2C DB", b.emitOpBinaryRegReg(R11, XMM3, MicroOp::ConvertFloatToInt, MicroOpBits::B64););
        return Result::Continue;
    }

    Result runCase(TaskContext& ctx, Result (*buildFn)(const RunCaseFn&))
    {
        const RunCaseFn runOneCase = [&](const char* name, const char* expectedHex, const BuilderCaseFn& fn) {
            X64Encoder encoder(ctx);
            return Backend::Unittest::runEncodeCase(ctx, encoder, name, expectedHex, fn);
        };
        return buildFn(runOneCase);
    }

    Result buildJumpTable(const TaskContext& ctx)
    {
        CompilerInstance compiler(ctx.global(), ctx.cmdLine());
        TaskContext      compilerCtx(compiler);
        const RunCaseFn  runCase = [&](const char* name, const char* expectedHex, const BuilderCaseFn& fn) {
            TestX64Encoder  encoder(compilerCtx);
            EncoderFunction testFct{};
            testFct.startAddress = 0;
            testFct.symbolIndex  = 7;
            encoder.setupJumpTableState(testFct);
            return Backend::Unittest::runEncodeCase(compilerCtx, encoder, name, expectedHex, fn);
        };

        auto [tableOffset, tablePtr] = compiler.compilerSegment().reserveSpan<int32_t>(3);
        tablePtr[0]                  = 1;
        tablePtr[1]                  = 2;
        tablePtr[2]                  = 3;

        ENCODE_CASE("jump_table_basic",
                    "48 8D 05 ?? ?? ?? ?? 48 63 04 88 48 8D 0D ?? ?? ?? ?? 48 01 C1 FF E1",
                    b.emitJumpTable(RAX, RCX, 0, tableOffset, 3););
        return Result::Continue;
    }

#undef ENCODE_CASE
}

SWC_TEST_BEGIN(EncodeX64_Flow)
{
    RESULT_VERIFY(runCase(ctx, buildFlow));
}
SWC_TEST_END()

SWC_TEST_BEGIN(EncodeX64_Load)
{
    RESULT_VERIFY(runCase(ctx, buildLoad));
}
SWC_TEST_END()

SWC_TEST_BEGIN(EncodeX64_CmpAndCond)
{
    RESULT_VERIFY(runCase(ctx, buildCmpAndCond));
}
SWC_TEST_END()

SWC_TEST_BEGIN(EncodeX64_UnaryOps)
{
    RESULT_VERIFY(runCase(ctx, buildUnaryOps));
}
SWC_TEST_END()

SWC_TEST_BEGIN(EncodeX64_BinaryRegRegOps)
{
    RESULT_VERIFY(runCase(ctx, buildBinaryRegRegOps));
}
SWC_TEST_END()

SWC_TEST_BEGIN(EncodeX64_BinaryRegMemOps)
{
    RESULT_VERIFY(runCase(ctx, buildBinaryRegMemOps));
}
SWC_TEST_END()

SWC_TEST_BEGIN(EncodeX64_BinaryMemRegOps)
{
    RESULT_VERIFY(runCase(ctx, buildBinaryMemRegOps));
}
SWC_TEST_END()

SWC_TEST_BEGIN(EncodeX64_BinaryImmOps)
{
    RESULT_VERIFY(runCase(ctx, buildBinaryImmOps));
}
SWC_TEST_END()

SWC_TEST_BEGIN(EncodeX64_TernaryAndConvert)
{
    RESULT_VERIFY(runCase(ctx, buildTernaryAndConvert));
}
SWC_TEST_END()

SWC_TEST_BEGIN(EncodeX64_JumpTable)
{
    RESULT_VERIFY(buildJumpTable(ctx));
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
