#include "pch.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Backend/MachineCode/Micro/Passes/MicroRegAllocPass.h"
#include "Backend/Unittest/BackendUnittestHelpers.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    using BuildCaseFn = std::function<void(MicroInstrBuilder&, CallConvKind)>;

    std::span<const CallConvKind> testedCallConvs()
    {
        static constexpr std::array CALL_CONVS = {
            CallConvKind::C,
            CallConvKind::WindowsX64,
            CallConvKind::Host,
        };
        return CALL_CONVS;
    }

    Result verifyCallConvConformity(MicroInstrBuilder& builder, const CallConv& conv)
    {
        auto& storeOps = builder.operands().store();

        for (const auto& inst : builder.instructions().view())
        {
            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(storeOps, refs, nullptr);
            for (const auto& ref : refs)
            {
                if (!ref.reg)
                    return Result::Error;
                const auto reg = *ref.reg;
                if (reg.isVirtual())
                    return Result::Error;

                if (reg.isInt())
                {
                    if (std::ranges::find(conv.intRegs, reg) == conv.intRegs.end())
                        return Result::Error;
                }
                else if (reg.isFloat())
                {
                    if (std::ranges::find(conv.floatRegs, reg) == conv.floatRegs.end())
                        return Result::Error;
                }
                else
                {
                    return Result::Error;
                }
            }
        }

        return Result::Continue;
    }

    Result runCase(TaskContext& ctx, const BuildCaseFn& buildFn)
    {
        for (const auto callConvKind : testedCallConvs())
        {
            MicroInstrBuilder builder(ctx);
            buildFn(builder, callConvKind);

            MicroRegAllocPass regAllocPass;
            MicroPassManager  passes;
            passes.add(regAllocPass);

            MicroPassContext passCtx;
            passCtx.callConvKind = callConvKind;
            builder.runPasses(passes, nullptr, passCtx);
            RESULT_VERIFY(Backend::Unittest::assertNoVirtualRegs(builder));
            RESULT_VERIFY(verifyCallConvConformity(builder, CallConv::get(passCtx.callConvKind)));
        }

        return Result::Continue;
    }

    void buildPersistentAcross(MicroInstrBuilder& b, CallConvKind callConvKind)
    {
        constexpr auto v0 = MicroReg::virtualIntReg(0);
        constexpr auto v1 = MicroReg::virtualIntReg(1);
        constexpr auto v2 = MicroReg::virtualIntReg(2);

        b.encodeLoadRegImm(v0, 1, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeLoadRegImm(v1, 2, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeCallReg(MicroReg::intReg(0), callConvKind, EncodeFlagsE::Zero);
        b.encodeOpBinaryRegImm(v0, 1, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeOpBinaryRegImm(v1, 3, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeLoadRegImm(v2, 4, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeOpBinaryRegImm(v2, 5, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeCallReg(MicroReg::intReg(0), callConvKind, EncodeFlagsE::Zero);
        b.encodeOpBinaryRegImm(v0, 7, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
    }

    void buildNoCalls(MicroInstrBuilder& b, CallConvKind)
    {
        constexpr auto v0 = MicroReg::virtualIntReg(10);
        constexpr auto v1 = MicroReg::virtualIntReg(11);
        constexpr auto v2 = MicroReg::virtualIntReg(12);

        b.encodeLoadRegImm(v0, 1, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeOpBinaryRegImm(v0, 1, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeLoadRegImm(v1, 2, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeOpBinaryRegImm(v1, 1, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeLoadRegImm(v2, 3, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeOpBinaryRegImm(v2, 1, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
    }

    void buildMixedIntFloat(MicroInstrBuilder& b, CallConvKind callConvKind)
    {
        constexpr auto vi  = MicroReg::virtualIntReg(20);
        constexpr auto vf0 = MicroReg::virtualFloatReg(0);
        constexpr auto vf1 = MicroReg::virtualFloatReg(1);
        constexpr auto vf2 = MicroReg::virtualFloatReg(2);
        constexpr auto vf3 = MicroReg::virtualFloatReg(3);

        b.encodeLoadRegImm(vi, 9, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeClearReg(vf0, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeClearReg(vf1, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeOpBinaryRegReg(vf0, vf1, MicroOp::FloatXor, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeCallReg(MicroReg::intReg(0), callConvKind, EncodeFlagsE::Zero);
        b.encodeOpBinaryRegImm(vi, 2, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeClearReg(vf2, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeClearReg(vf3, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeOpBinaryRegReg(vf2, vf3, MicroOp::FloatXor, MicroOpBits::B64, EncodeFlagsE::Zero);
    }

    void buildLotsOfVirtualRegs(MicroInstrBuilder& b, CallConvKind callConvKind)
    {
        for (uint32_t i = 0; i < 128; ++i)
        {
            const auto v = MicroReg::virtualIntReg(1000 + i);
            b.encodeLoadRegImm(v, i + 1, MicroOpBits::B64, EncodeFlagsE::Zero);
            b.encodeOpBinaryRegImm(v, (i & 7) + 1, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
            if ((i % 16) == 15)
                b.encodeCallReg(MicroReg::intReg(0), callConvKind, EncodeFlagsE::Zero);
        }

        for (uint32_t i = 0; i < 64; ++i)
        {
            const auto v0 = MicroReg::virtualFloatReg(2000 + i * 2);
            const auto v1 = MicroReg::virtualFloatReg(2000 + i * 2 + 1);
            b.encodeClearReg(v0, MicroOpBits::B64, EncodeFlagsE::Zero);
            b.encodeClearReg(v1, MicroOpBits::B64, EncodeFlagsE::Zero);
            b.encodeOpBinaryRegReg(v0, v1, MicroOp::FloatXor, MicroOpBits::B64, EncodeFlagsE::Zero);
            if ((i % 16) == 15)
                b.encodeCallReg(MicroReg::intReg(0), callConvKind, EncodeFlagsE::Zero);
        }
    }
}

SWC_TEST_BEGIN(RegAlloc_PersistentAcross)
{
    RESULT_VERIFY(runCase(ctx, buildPersistentAcross));
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_NoCalls)
{
    RESULT_VERIFY(runCase(ctx, buildNoCalls));
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_MixedIntFloat)
{
    RESULT_VERIFY(runCase(ctx, buildMixedIntFloat));
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_LotsOfVirtualRegs)
{
    RESULT_VERIFY(runCase(ctx, buildLotsOfVirtualRegs));
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroInstr_PrintPretty)
{
    MicroInstrBuilder builder(ctx);

    const IdentifierRef symRef = ctx.idMgr().addIdentifier("micro_print_test");
    builder.encodeLoadRegImm(MicroReg::intReg(8), 0x2A, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeOpBinaryRegImm(MicroReg::intReg(8), 1, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Lock);
    builder.encodeCallLocal(symRef, CallConvKind::Host, EncodeFlagsE::Zero);
    builder.encodeLoadMemImm(MicroReg::intReg(5), 0x18, 0xFF, MicroOpBits::B8, EncodeFlagsE::Zero);

    const std::string text = builder.formatInstructions(false);

    SWC_ASSERT(text.find("micro-instructions: 4") != std::string::npos);
    SWC_ASSERT(text.find("load_reg_imm") != std::string::npos);
    SWC_ASSERT(text.find("op_binary_reg_imm") != std::string::npos);
    SWC_ASSERT(text.find("call_local") != std::string::npos);
    SWC_ASSERT(text.find("load_mem_imm") != std::string::npos);
    SWC_ASSERT(text.find("micro_print_test") != std::string::npos);
    SWC_ASSERT(text.find("r8") != std::string::npos);
    SWC_ASSERT(text.find("0x2A") != std::string::npos);
    SWC_ASSERT(text.find("flags=lock") != std::string::npos);
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
