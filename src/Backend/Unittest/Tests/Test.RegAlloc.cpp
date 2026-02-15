#include "pch.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Backend/MachineCode/Micro/Passes/MicroPersistentRegsPass.h"
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
        auto& storeOps = builder.operands();

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

    void buildPersistentWithReturn(MicroInstrBuilder& b, CallConvKind callConvKind)
    {
        constexpr auto v0 = MicroReg::virtualIntReg(3000);

        b.encodeLoadRegImm(v0, 1, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeCallReg(MicroReg::intReg(0), callConvKind, EncodeFlagsE::Zero);
        b.encodeOpBinaryRegImm(v0, 2, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeRet(EncodeFlagsE::Zero);
    }

    void buildNoPersistentWithReturn(MicroInstrBuilder& b, CallConvKind)
    {
        constexpr auto v0 = MicroReg::virtualIntReg(3100);

        b.encodeLoadRegImm(v0, 3, MicroOpBits::B64, EncodeFlagsE::Zero);
        b.encodeRet(EncodeFlagsE::Zero);
    }

    bool isStackAdjust(const MicroInstr& inst, MicroOperandStorage& operands, MicroReg stackPtr, MicroOp op)
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
            return false;

        const auto* ops = inst.ops(operands);
        return ops[0].reg == stackPtr && ops[1].opBits == MicroOpBits::B64 && ops[2].microOp == op;
    }

    bool hasPersistentFrameOps(MicroInstrBuilder& builder, const CallConv& conv, bool* outHasSub = nullptr, bool* outHasAdd = nullptr)
    {
        auto& storeOps = builder.operands();
        bool  hasSub   = false;
        bool  hasAdd   = false;
        bool  hasStore = false;
        bool  hasLoad  = false;

        for (const auto& inst : builder.instructions().view())
        {
            if (isStackAdjust(inst, storeOps, conv.stackPointer, MicroOp::Subtract))
                hasSub = true;
            else if (isStackAdjust(inst, storeOps, conv.stackPointer, MicroOp::Add))
                hasAdd = true;
            else if (inst.op == MicroInstrOpcode::LoadMemReg)
                hasStore = true;
            else if (inst.op == MicroInstrOpcode::LoadRegMem)
                hasLoad = true;
        }

        if (outHasSub)
            *outHasSub = hasSub;
        if (outHasAdd)
            *outHasAdd = hasAdd;
        return hasSub && hasAdd && hasStore && hasLoad;
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

SWC_TEST_BEGIN(RegAlloc_PreservePersistentRegs_Enabled)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroInstrBuilder builder(ctx);
        buildPersistentWithReturn(builder, callConvKind);

        MicroRegAllocPass       regAllocPass;
        MicroPersistentRegsPass persistentRegsPass;
        MicroPassManager        passes;
        passes.add(regAllocPass);
        passes.add(persistentRegsPass);

        MicroPassContext passCtx;
        passCtx.callConvKind           = callConvKind;
        passCtx.preservePersistentRegs = true;
        builder.runPasses(passes, nullptr, passCtx);

        bool       hasSub      = false;
        bool       hasAdd      = false;
        const bool hasFrameOps = hasPersistentFrameOps(builder, CallConv::get(callConvKind), &hasSub, &hasAdd);
        if (!hasFrameOps || !hasSub || !hasAdd)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_PreservePersistentRegs_Disabled)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroInstrBuilder builder(ctx);
        buildPersistentWithReturn(builder, callConvKind);

        MicroRegAllocPass       regAllocPass;
        MicroPersistentRegsPass persistentRegsPass;
        MicroPassManager        passes;
        passes.add(regAllocPass);
        passes.add(persistentRegsPass);

        MicroPassContext passCtx;
        passCtx.callConvKind           = callConvKind;
        passCtx.preservePersistentRegs = false;
        builder.runPasses(passes, nullptr, passCtx);

        const bool hasFrameOps = hasPersistentFrameOps(builder, CallConv::get(callConvKind));
        if (hasFrameOps)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_PreservePersistentRegs_NoNeed)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroInstrBuilder builder(ctx);
        buildNoPersistentWithReturn(builder, callConvKind);

        MicroRegAllocPass       regAllocPass;
        MicroPersistentRegsPass persistentRegsPass;
        MicroPassManager        passes;
        passes.add(regAllocPass);
        passes.add(persistentRegsPass);

        MicroPassContext passCtx;
        passCtx.callConvKind           = callConvKind;
        passCtx.preservePersistentRegs = true;
        builder.runPasses(passes, nullptr, passCtx);

        const bool hasFrameOps = hasPersistentFrameOps(builder, CallConv::get(callConvKind));
        if (hasFrameOps)
            return Result::Error;
    }
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
