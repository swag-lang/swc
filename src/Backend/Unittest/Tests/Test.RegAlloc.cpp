#include "pch.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/Passes/MicroPass.h"
#include "Backend/CodeGen/Micro/Passes/MicroPrologEpilogPass.h"
#include "Backend/CodeGen/Micro/Passes/MicroRegisterAllocationPass.h"
#include "Backend/Unittest/BackendUnittestHelpers.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    using BuildCaseFn = std::function<void(MicroBuilder&, CallConvKind)>;

    std::span<const CallConvKind> testedCallConvs()
    {
        static constexpr std::array CALL_CONVS = {
            CallConvKind::C,
            CallConvKind::WindowsX64,
            CallConvKind::Host,
        };
        return CALL_CONVS;
    }

    Result verifyCallConvConformity(MicroBuilder& builder, const CallConv& conv)
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
            MicroBuilder builder(ctx);
            buildFn(builder, callConvKind);

            MicroRegisterAllocationPass regAllocPass;
            MicroPassManager            passes;
            passes.add(regAllocPass);

            MicroPassContext passCtx;
            passCtx.callConvKind = callConvKind;
            builder.runPasses(passes, nullptr, passCtx);
            RESULT_VERIFY(Backend::Unittest::assertNoVirtualRegs(builder));
            RESULT_VERIFY(verifyCallConvConformity(builder, CallConv::get(passCtx.callConvKind)));
        }

        return Result::Continue;
    }

    void buildPersistentAcross(MicroBuilder& b, CallConvKind callConvKind)
    {
        constexpr auto v0 = MicroReg::virtualIntReg(0);
        constexpr auto v1 = MicroReg::virtualIntReg(1);
        constexpr auto v2 = MicroReg::virtualIntReg(2);

        b.encodeLoadRegImm(v0, 1, MicroOpBits::B64);
        b.encodeLoadRegImm(v1, 2, MicroOpBits::B64);
        b.encodeCallReg(MicroReg::intReg(0), callConvKind);
        b.encodeOpBinaryRegImm(v0, 1, MicroOp::Add, MicroOpBits::B64);
        b.encodeOpBinaryRegImm(v1, 3, MicroOp::Add, MicroOpBits::B64);
        b.encodeLoadRegImm(v2, 4, MicroOpBits::B64);
        b.encodeOpBinaryRegImm(v2, 5, MicroOp::Add, MicroOpBits::B64);
        b.encodeCallReg(MicroReg::intReg(0), callConvKind);
        b.encodeOpBinaryRegImm(v0, 7, MicroOp::Add, MicroOpBits::B64);
    }

    void buildNoCalls(MicroBuilder& b, CallConvKind)
    {
        constexpr auto v0 = MicroReg::virtualIntReg(10);
        constexpr auto v1 = MicroReg::virtualIntReg(11);
        constexpr auto v2 = MicroReg::virtualIntReg(12);

        b.encodeLoadRegImm(v0, 1, MicroOpBits::B64);
        b.encodeOpBinaryRegImm(v0, 1, MicroOp::Add, MicroOpBits::B64);
        b.encodeLoadRegImm(v1, 2, MicroOpBits::B64);
        b.encodeOpBinaryRegImm(v1, 1, MicroOp::Add, MicroOpBits::B64);
        b.encodeLoadRegImm(v2, 3, MicroOpBits::B64);
        b.encodeOpBinaryRegImm(v2, 1, MicroOp::Add, MicroOpBits::B64);
    }

    void buildMixedIntFloat(MicroBuilder& b, CallConvKind callConvKind)
    {
        constexpr auto vi  = MicroReg::virtualIntReg(20);
        constexpr auto vf0 = MicroReg::virtualFloatReg(0);
        constexpr auto vf1 = MicroReg::virtualFloatReg(1);
        constexpr auto vf2 = MicroReg::virtualFloatReg(2);
        constexpr auto vf3 = MicroReg::virtualFloatReg(3);

        b.encodeLoadRegImm(vi, 9, MicroOpBits::B64);
        b.encodeClearReg(vf0, MicroOpBits::B64);
        b.encodeClearReg(vf1, MicroOpBits::B64);
        b.encodeOpBinaryRegReg(vf0, vf1, MicroOp::FloatXor, MicroOpBits::B64);
        b.encodeCallReg(MicroReg::intReg(0), callConvKind);
        b.encodeOpBinaryRegImm(vi, 2, MicroOp::Add, MicroOpBits::B64);
        b.encodeClearReg(vf2, MicroOpBits::B64);
        b.encodeClearReg(vf3, MicroOpBits::B64);
        b.encodeOpBinaryRegReg(vf2, vf3, MicroOp::FloatXor, MicroOpBits::B64);
    }

    void buildLotsOfVirtualRegs(MicroBuilder& b, CallConvKind callConvKind)
    {
        for (uint32_t i = 0; i < 128; ++i)
        {
            const auto v = MicroReg::virtualIntReg(1000 + i);
            b.encodeLoadRegImm(v, i + 1, MicroOpBits::B64);
            b.encodeOpBinaryRegImm(v, (i & 7) + 1, MicroOp::Add, MicroOpBits::B64);
            if ((i % 16) == 15)
                b.encodeCallReg(MicroReg::intReg(0), callConvKind);
        }

        for (uint32_t i = 0; i < 64; ++i)
        {
            const auto v0 = MicroReg::virtualFloatReg(2000 + i * 2);
            const auto v1 = MicroReg::virtualFloatReg(2000 + i * 2 + 1);
            b.encodeClearReg(v0, MicroOpBits::B64);
            b.encodeClearReg(v1, MicroOpBits::B64);
            b.encodeOpBinaryRegReg(v0, v1, MicroOp::FloatXor, MicroOpBits::B64);
            if ((i % 16) == 15)
                b.encodeCallReg(MicroReg::intReg(0), callConvKind);
        }
    }

    void buildPersistentWithReturn(MicroBuilder& b, CallConvKind callConvKind)
    {
        constexpr auto v0 = MicroReg::virtualIntReg(3000);

        b.encodeLoadRegImm(v0, 1, MicroOpBits::B64);
        b.encodeCallReg(MicroReg::intReg(0), callConvKind);
        b.encodeOpBinaryRegImm(v0, 2, MicroOp::Add, MicroOpBits::B64);
        b.encodeRet();
    }

    void buildNoPersistentWithReturn(MicroBuilder& b, CallConvKind)
    {
        constexpr auto v0 = MicroReg::virtualIntReg(3100);

        b.encodeLoadRegImm(v0, 3, MicroOpBits::B64);
        b.encodeRet();
    }

    void buildIntSpillPressureAcrossCall(MicroBuilder& b, CallConvKind callConvKind)
    {
        for (uint32_t i = 0; i < 24; ++i)
        {
            const auto v = MicroReg::virtualIntReg(4000 + i);
            b.encodeLoadRegImm(v, i + 1, MicroOpBits::B64);
        }

        b.encodeCallReg(MicroReg::intReg(0), callConvKind);

        for (uint32_t i = 0; i < 24; ++i)
        {
            const auto v = MicroReg::virtualIntReg(4000 + i);
            b.encodeOpBinaryRegImm(v, 3, MicroOp::Add, MicroOpBits::B64);
        }

        b.encodeRet();
    }

    void buildFloatSpillAcrossCallNoPersistentRegs(MicroBuilder& b, CallConvKind callConvKind)
    {
        for (uint32_t i = 0; i < 16; ++i)
        {
            const auto v = MicroReg::virtualFloatReg(5000 + i);
            b.encodeClearReg(v, MicroOpBits::B64);
        }

        b.encodeCallReg(MicroReg::intReg(0), callConvKind);

        for (uint32_t i = 0; i < 16; ++i)
        {
            const auto v = MicroReg::virtualFloatReg(5000 + i);
            b.encodeOpBinaryRegReg(v, v, MicroOp::FloatXor, MicroOpBits::B64);
        }

        b.encodeRet();
    }

    void buildForbiddenIntArgRegs(MicroBuilder& b, CallConvKind callConvKind)
    {
        const auto& conv = CallConv::get(callConvKind);

        constexpr auto v0 = MicroReg::virtualIntReg(6000);
        constexpr auto v1 = MicroReg::virtualIntReg(6001);
        b.addVirtualRegForbiddenPhysRegs(v0, conv.intArgRegs);
        b.addVirtualRegForbiddenPhysRegs(v1, conv.intArgRegs);

        b.encodeLoadRegImm(v0, 11, MicroOpBits::B64);
        b.encodeLoadRegImm(v1, 7, MicroOpBits::B64);
        b.encodeOpBinaryRegReg(v0, v1, MicroOp::Add, MicroOpBits::B64);
        b.encodeRet();
    }

    bool isStackAdjust(const MicroInstr& inst, MicroOperandStorage& operands, MicroReg stackPtr, MicroOp op)
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
            return false;

        const MicroInstrOperand* ops = inst.ops(operands);
        return ops[0].reg == stackPtr && ops[1].opBits == MicroOpBits::B64 && ops[2].microOp == op;
    }

    bool hasPersistentFrameOps(MicroBuilder& builder, const CallConv& conv)
    {
        auto& storeOps = builder.operands();
        bool  hasSub   = false;
        bool  hasAdd   = false;
        bool  hasStore = false;
        bool  hasLoad  = false;
        bool  hasPush  = false;
        bool  hasPop   = false;

        for (const auto& inst : builder.instructions().view())
        {
            if (isStackAdjust(inst, storeOps, conv.stackPointer, MicroOp::Subtract))
                hasSub = true;
            else if (isStackAdjust(inst, storeOps, conv.stackPointer, MicroOp::Add))
                hasAdd = true;
            else if (inst.op == MicroInstrOpcode::Push)
                hasPush = true;
            else if (inst.op == MicroInstrOpcode::Pop)
                hasPop = true;
            else if (inst.op == MicroInstrOpcode::LoadMemReg)
            {
                const MicroInstrOperand* ops = inst.ops(storeOps);
                if (ops[0].reg == conv.stackPointer)
                    hasStore = true;
            }
            else if (inst.op == MicroInstrOpcode::LoadRegMem)
            {
                const MicroInstrOperand* ops = inst.ops(storeOps);
                if (ops[1].reg == conv.stackPointer)
                    hasLoad = true;
            }
        }

        const bool hasPushPopFrame = hasPush && hasPop;
        const bool hasStackFrame   = hasSub && hasAdd && hasStore && hasLoad;
        return hasPushPopFrame || hasStackFrame;
    }

    bool hasSpillFrameOps(MicroBuilder& builder, const CallConv& conv)
    {
        auto& storeOps = builder.operands();
        bool  hasSub   = false;
        bool  hasAdd   = false;
        bool  hasStore = false;
        bool  hasLoad  = false;

        for (const auto& inst : builder.instructions().view())
        {
            if (isStackAdjust(inst, storeOps, conv.stackPointer, MicroOp::Subtract))
            {
                hasSub = true;
                continue;
            }

            if (isStackAdjust(inst, storeOps, conv.stackPointer, MicroOp::Add))
            {
                hasAdd = true;
                continue;
            }

            if (inst.op != MicroInstrOpcode::LoadMemReg && inst.op != MicroInstrOpcode::LoadRegMem)
                continue;

            const MicroInstrOperand* ops = inst.ops(storeOps);
            if (inst.op == MicroInstrOpcode::LoadMemReg && ops[0].reg == conv.stackPointer)
                hasStore = true;
            else if (inst.op == MicroInstrOpcode::LoadRegMem && ops[1].reg == conv.stackPointer)
                hasLoad = true;
        }

        return hasSub && hasAdd && hasStore && hasLoad;
    }

    bool containsIntArgRegs(MicroBuilder& builder, const CallConv& conv)
    {
        auto& storeOps = builder.operands();
        for (const auto& inst : builder.instructions().view())
        {
            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(storeOps, refs, nullptr);
            for (const auto& ref : refs)
            {
                if (!ref.reg)
                    continue;

                const MicroReg reg = *ref.reg;
                if (!reg.isInt())
                    continue;

                if (std::ranges::find(conv.intArgRegs, reg) != conv.intArgRegs.end())
                    return true;
            }
        }

        return false;
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
        MicroBuilder builder(ctx);
        buildPersistentWithReturn(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPrologEpilogPass       persistentRegsPass;
        MicroPassManager            passes;
        passes.add(regAllocPass);
        passes.add(persistentRegsPass);

        MicroPassContext passCtx;
        passCtx.callConvKind           = callConvKind;
        passCtx.preservePersistentRegs = true;
        builder.runPasses(passes, nullptr, passCtx);

        const bool hasFrameOps = hasPersistentFrameOps(builder, CallConv::get(callConvKind));
        if (!hasFrameOps)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_PreservePersistentRegs_Disabled)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroBuilder builder(ctx);
        buildPersistentWithReturn(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPrologEpilogPass       persistentRegsPass;
        MicroPassManager            passes;
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
        MicroBuilder builder(ctx);
        buildNoPersistentWithReturn(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPrologEpilogPass       persistentRegsPass;
        MicroPassManager            passes;
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

SWC_TEST_BEGIN(RegAlloc_Spill_IntPressureAcrossCall)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroBuilder builder(ctx);
        buildIntSpillPressureAcrossCall(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPassManager            passes;
        passes.add(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        builder.runPasses(passes, nullptr, passCtx);

        RESULT_VERIFY(Backend::Unittest::assertNoVirtualRegs(builder));

        if (!hasSpillFrameOps(builder, CallConv::get(callConvKind)))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_Spill_FloatAcrossCall_NoPersistent)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroBuilder builder(ctx);
        buildFloatSpillAcrossCallNoPersistentRegs(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPassManager            passes;
        passes.add(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        builder.runPasses(passes, nullptr, passCtx);

        RESULT_VERIFY(Backend::Unittest::assertNoVirtualRegs(builder));

        if (!hasSpillFrameOps(builder, CallConv::get(callConvKind)))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_VirtualRegForbiddenPhysRegs)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroBuilder builder(ctx);
        buildForbiddenIntArgRegs(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPassManager            passes;
        passes.add(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        builder.runPasses(passes, nullptr, passCtx);

        RESULT_VERIFY(Backend::Unittest::assertNoVirtualRegs(builder));
        if (containsIntArgRegs(builder, CallConv::get(callConvKind)))
            return Result::Error;
    }
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
