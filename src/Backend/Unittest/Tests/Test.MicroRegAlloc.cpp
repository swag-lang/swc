#include "pch.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Backend/MachineCode/Micro/Passes/MicroRegAllocPass.h"
#include "Backend/Unittest/BackendUnittest.h"
#include "Backend/Unittest/BackendUnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

#if SWC_DEV_MODE

namespace
{
    using BuildCaseFn = std::function<void(MicroInstrBuilder&, CallConvKind)>;

    std::span<const CallConvKind> testedCallConvs()
    {
        static constexpr std::array CALL_CONVS = {CallConvKind::C};
        return CALL_CONVS;
    }

    void verifyCallConvConformity(MicroInstrBuilder& builder, const CallConv& conv)
    {
        auto& storeOps = builder.operands().store();

        for (const auto& inst : builder.instructions().view())
        {
            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(storeOps, refs, nullptr);
            for (const auto& ref : refs)
            {
                const auto reg = *ref.reg;
                SWC_ASSERT(!reg.isVirtual());

                if (reg.isInt())
                {
                    SWC_ASSERT(std::ranges::find(conv.intRegs, reg) != conv.intRegs.end());
                }
                else if (reg.isFloat())
                {
                    SWC_ASSERT(std::ranges::find(conv.floatRegs, reg) != conv.floatRegs.end());
                }
                else
                {
                    SWC_ASSERT(false);
                }
            }
        }
    }

    void executeCase(TaskContext& ctx, const BuildCaseFn& buildFn)
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
            Backend::Unittest::assertNoVirtualRegs(builder);
            verifyCallConvConformity(builder, CallConv::get(passCtx.callConvKind));
        }
    }

    void buildPersistentAcrossCallsInt(MicroInstrBuilder& b, CallConvKind callConvKind)
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

SWC_BACKEND_TEST_BEGIN(MicroRegAlloc)
{
    executeCase(ctx, buildPersistentAcrossCallsInt);
    executeCase(ctx, buildNoCalls);
    executeCase(ctx, buildMixedIntFloat);
    executeCase(ctx, buildLotsOfVirtualRegs);
}
SWC_BACKEND_TEST_END()

#endif

SWC_END_NAMESPACE();
