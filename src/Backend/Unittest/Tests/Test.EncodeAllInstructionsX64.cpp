#include "pch.h"
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Backend/Unittest/BackendUnittest.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

#if SWC_DEV_MODE

namespace
{
    struct ExpectedByte
    {
        uint8_t value    = 0;
        bool    wildcard = false;
    };

    std::vector<ExpectedByte> parseExpected(const char* text)
    {
        std::vector<ExpectedByte> result;
        if (!text || !*text)
            return result;

        std::string token;
        for (const char* p = text;; ++p)
        {
            const char c = *p;
            if (c && c != ' ' && c != '\t' && c != '\n' && c != '\r')
            {
                token.push_back(c);
                continue;
            }

            if (token.empty())
            {
                if (!c)
                    break;
                continue;
            }

            if (token == "??")
            {
                result.push_back(ExpectedByte{0, true});
            }
            else
            {
                SWC_ASSERT(token.size() == 2);
                uint32_t value = 0;
                for (const auto tc : token)
                {
                    uint32_t nibble = 0;
                    if (tc >= '0' && tc <= '9')
                        nibble = static_cast<uint32_t>(tc - '0');
                    else if (tc >= 'a' && tc <= 'f')
                        nibble = static_cast<uint32_t>(10 + tc - 'a');
                    else if (tc >= 'A' && tc <= 'F')
                        nibble = static_cast<uint32_t>(10 + tc - 'A');
                    else
                        SWC_ASSERT(false);
                    value = (value << 4) | nibble;
                }

                result.push_back(ExpectedByte{static_cast<uint8_t>(value), false});
            }

            token.clear();
            if (!c)
                break;
        }

        return result;
    }

    template<typename F>
    void runEncodeCase(TaskContext& ctx, const char* name, const char* expectedHex, F&& fn)
    {
        MicroInstrBuilder builder(ctx);
        fn(builder);

        X64Encoder       encoder(ctx);
        MicroEncodePass  encodePass;
        MicroPassManager passes;
        passes.add(encodePass);

        MicroPassContext passCtx;
        builder.runPasses(passes, &encoder, passCtx);

        SWC_ASSERT(encoder.size() > 0);
        const auto size     = encoder.size();
        const auto expected = parseExpected(expectedHex);
        SWC_ASSERT(size == expected.size());
        for (uint32_t i = 0; i < size; ++i)
        {
            if (!expected[i].wildcard)
            {
                const auto got = encoder.byteAt(i);
                if (got != expected[i].value)
                {
                    Logger::print(ctx, std::format("EncodeAllInstructionsX64 mismatch: case={} byte={} expected={:02X} got={:02X}\n", name, i, expected[i].value, got));

                    std::string encoded = "Encoded bytes: ";
                    for (uint32_t j = 0; j < size; ++j)
                    {
                        encoded += std::format("{:02X}", encoder.byteAt(j));
                        if (j + 1 < size)
                            encoded += " ";
                    }
                    encoded += "\n";
                    Logger::print(ctx, encoded);

                    Logger::print(ctx, std::format("Expected: {}\n", expectedHex));
                    SWC_ASSERT(false);
                }
            }
        }
    }
}

SWC_BACKEND_TEST_BEGIN(EncodeAllInstructionsX64)
{
    constexpr auto kEmit = EncodeFlagsE::Zero;
    constexpr auto kLock = EncodeFlagsE::Lock;
    constexpr auto kB64  = EncodeFlagsE::B64;

    constexpr auto rax  = MicroReg::intReg(0);
    constexpr auto rcx  = MicroReg::intReg(2);
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

    runEncodeCase(ctx, "nop", "90", [&](MicroInstrBuilder& builder) { builder.encodeNop(kEmit); });
    runEncodeCase(ctx, "push_r12", "41 54", [&](MicroInstrBuilder& builder) { builder.encodePush(r12, kEmit); });
    runEncodeCase(ctx, "pop_r12", "41 5C", [&](MicroInstrBuilder& builder) { builder.encodePop(r12, kEmit); });
    runEncodeCase(ctx, "sym_reloc_addr_r10", "4C 8D 15 10 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadSymbolRelocAddress(r10, 1, 0x10, kEmit); });
    runEncodeCase(ctx, "sym_reloc_value_r11_b64", "4C 8B 1D 20 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadSymRelocValue(r11, 2, 0x20, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "sym_reloc_value_xmm0_b32", "F3 0F 10 05 40 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadSymRelocValue(xmm0, 4, 0x40, MicroOpBits::B32, kEmit); });
    runEncodeCase(ctx, "call_local", "E8 00 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeCallLocal({}, CallConvKind::C, kEmit); });
    runEncodeCase(ctx, "call_extern", "FF 15 00 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeCallExtern({}, CallConvKind::C, kEmit); });
    runEncodeCase(ctx, "call_reg_r9", "41 FF D1", [&](MicroInstrBuilder& builder) { builder.encodeCallReg(r9, CallConvKind::C, kEmit); });
    runEncodeCase(ctx, "jump_reg_r13", "41 FF E5", [&](MicroInstrBuilder& builder) { builder.encodeJumpReg(r13, kEmit); });
    runEncodeCase(ctx, "load_reg_imm_rax_b8", "B0 12", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegImm(rax, 0x12, MicroOpBits::B8, kEmit); });
    runEncodeCase(ctx, "load_reg_imm_r10_b64", "49 BA F0 DE BC 9A 78 56 34 12", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegImm(r10, 0x123456789ABCDEF0, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "load_reg_reg_r11_r8_b64", "4D 89 C3", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegReg(r11, r8, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "load_reg_reg_xmm0_xmm1_b32", "F3 0F 10 C1", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegReg(xmm0, xmm1, MicroOpBits::B32, kEmit); });
    runEncodeCase(ctx, "load_reg_mem_r8_r12_0_b64", "4D 8B 04 24", [&](MicroInstrBuilder& builder) { builder.encodeLoadRegMem(r8, r12, 0, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "load_sext_reg_mem_b8", "4D 0F BE 5C 24 10", [&](MicroInstrBuilder& builder) { builder.encodeLoadSignedExtendRegMem(r11, r12, 0x10, MicroOpBits::B64, MicroOpBits::B8, kEmit); });
    runEncodeCase(ctx, "load_sext_reg_reg_b16", "4D 0F BF CA", [&](MicroInstrBuilder& builder) { builder.encodeLoadSignedExtendRegReg(r9, r10, MicroOpBits::B64, MicroOpBits::B16, kEmit); });
    runEncodeCase(ctx, "load_zext_reg_mem_b16", "4D 0F B7 95 88 00 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadZeroExtendRegMem(r10, r13, 0x88, MicroOpBits::B64, MicroOpBits::B16, kEmit); });
    runEncodeCase(ctx, "load_zext_reg_reg_b32", "45 89 CA", [&](MicroInstrBuilder& builder) { builder.encodeLoadZeroExtendRegReg(r10, r9, MicroOpBits::B64, MicroOpBits::B32, kEmit); });
    runEncodeCase(ctx, "lea_reg_mem_rip", "4C 8D 15", [&](MicroInstrBuilder& builder) { builder.encodeLoadAddressRegMem(r10, MicroReg::instructionPointer(), 0, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "load_amc_reg_mem", "4F 8B 54 85 20", [&](MicroInstrBuilder& builder) { builder.encodeLoadAmcRegMem(r10, MicroOpBits::B64, r13, r8, 4, 0x20, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "load_amc_mem_reg", "47 89 94 C5 00 01 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadAmcMemReg(r13, r8, 8, 0x100, MicroOpBits::B64, r10, MicroOpBits::B32, kEmit); });
    runEncodeCase(ctx, "load_amc_mem_imm", "43 C7 44 85 24 34 12 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadAmcMemImm(r13, r8, 4, 0x24, MicroOpBits::B64, 0x1234, MicroOpBits::B32, kEmit); });
    runEncodeCase(ctx, "lea_amc_reg_mem", "4F 8D 5C 4D 40", [&](MicroInstrBuilder& builder) { builder.encodeLoadAddressAmcRegMem(r11, MicroOpBits::B64, r13, r9, 2, 0x40, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "load_mem_reg_rsp_b32", "44 89 8C 24 20 01 00 00", [&](MicroInstrBuilder& builder) { builder.encodeLoadMemReg(rsp, 0x120, r9, MicroOpBits::B32, kEmit); });
    runEncodeCase(ctx, "load_mem_imm_rbp_b64", "48 C7 45 20 80 FF FF FF", [&](MicroInstrBuilder& builder) { builder.encodeLoadMemImm(rbp, 0x20, 0xFFFFFFFFFFFFFF80, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "cmp_reg_reg_r8_r9_b64", "4D 39 C8", [&](MicroInstrBuilder& builder) { builder.encodeCmpRegReg(r8, r9, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "cmp_reg_imm_r10_b32", "41 81 FA 34 12 00 00", [&](MicroInstrBuilder& builder) { builder.encodeCmpRegImm(r10, 0x1234, MicroOpBits::B32, kEmit); });
    runEncodeCase(ctx, "cmp_mem_reg_r12_r11_b64", "4D 39 5C 24 40", [&](MicroInstrBuilder& builder) { builder.encodeCmpMemReg(r12, 0x40, r11, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "cmp_mem_imm_r13_b8", "41 80 7D 44 55", [&](MicroInstrBuilder& builder) { builder.encodeCmpMemImm(r13, 0x44, 0x55, MicroOpBits::B8, kEmit); });
    runEncodeCase(ctx, "set_cond_above_r8", "41 0F 97 C0", [&](MicroInstrBuilder& builder) { builder.encodeSetCondReg(r8, MicroCond::Above, kEmit); });
    runEncodeCase(ctx, "load_cond_reg_reg_gt", "4D 0F 4F CA", [&](MicroInstrBuilder& builder) { builder.encodeLoadCondRegReg(r9, r10, MicroCond::Greater, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "clear_reg_r11_b64", "4D 31 DB", [&](MicroInstrBuilder& builder) { builder.encodeClearReg(r11, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "clear_reg_xmm1_b64", "66 0F 57 C9", [&](MicroInstrBuilder& builder) { builder.encodeClearReg(xmm1, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "op_unary_reg_not_r8", "49 F7 D0", [&](MicroInstrBuilder& builder) { builder.encodeOpUnaryReg(r8, MicroOp::BitwiseNot, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "op_unary_mem_neg_r13", "48 F7 5D 40", [&](MicroInstrBuilder& builder) { builder.encodeOpUnaryMem(r13, 0x40, MicroOp::Negate, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "op_binary_reg_reg_add", "4D 01 C8", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(r8, r9, MicroOp::Add, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "op_binary_reg_reg_shl_rcx", "49 D3 E2", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(r10, rcx, MicroOp::ShiftLeft, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "op_binary_reg_mem_sub", "4D 2B 4C 24 24", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegMem(r9, r12, 0x24, MicroOp::Subtract, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "op_binary_mem_reg_add_lock", "F0 4D 01 55 20", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemReg(r13, 0x20, r10, MicroOp::Add, MicroOpBits::B64, kLock); });
    runEncodeCase(ctx, "op_binary_reg_imm_mul", "4D 6B ED 07", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegImm(r13, 7, MicroOp::MultiplySigned, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "op_binary_mem_imm_sar", "48 C1 BD 80 00 00 00 08", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryMemImm(rbp, 0x80, 8, MicroOp::ShiftArithmeticRight, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "op_ternary_madd", "F2 0F 59 C1 F2 0F 58 C2", [&](MicroInstrBuilder& builder) { builder.encodeOpTernaryRegRegReg(xmm0, xmm1, xmm2, MicroOp::MultiplyAdd, MicroOpBits::B64, kEmit); });
    runEncodeCase(ctx, "op_ternary_cmpxchg_lock", "F0 4D 0F B1 1C 24", [&](MicroInstrBuilder& builder) { builder.encodeOpTernaryRegRegReg(rax, r12, r11, MicroOp::CompareExchange, MicroOpBits::B64, kLock); });
    runEncodeCase(ctx, "convert_i2f_b64", "F2 49 0F 2A D2", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(xmm2, r10, MicroOp::ConvertIntToFloat, MicroOpBits::B64, kB64); });
    runEncodeCase(ctx, "convert_f2i_b64", "F2 4C 0F 2C DB", [&](MicroInstrBuilder& builder) { builder.encodeOpBinaryRegReg(r11, xmm3, MicroOp::ConvertFloatToInt, MicroOpBits::B64, kB64); });
    runEncodeCase(ctx, "ret", "C3", [&](MicroInstrBuilder& builder) { builder.encodeRet(kEmit); });

    runEncodeCase(ctx, "jump_zero_b8_patch_here", "74 00", [&](MicroInstrBuilder& builder) {
        MicroJump jump;
        builder.encodeJump(jump, MicroCondJump::Zero, MicroOpBits::B8, kEmit);
        builder.encodePatchJump(jump, kEmit);
    });
    runEncodeCase(ctx, "jump_less_b32_patch_80", "0F 8C 7A 00 00 00", [&](MicroInstrBuilder& builder) {
        MicroJump jump;
        builder.encodeJump(jump, MicroCondJump::Less, MicroOpBits::B32, kEmit);
        builder.encodePatchJump(jump, 0x80, kEmit);
    });
}
SWC_BACKEND_TEST_END()

#endif

SWC_END_NAMESPACE();
