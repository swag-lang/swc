#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.PrologEpilog.h"
#include "Backend/Micro/Passes/Pass.RegisterAllocation.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

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
            for (const auto& microLabelRef : refs)
            {
                if (!microLabelRef.reg)
                    return Result::Error;
                const auto reg = *microLabelRef.reg;
                if (reg.isVirtual())
                    return Result::Error;

                if (reg.isInt())
                {
                    if (reg == conv.stackPointer || reg == conv.framePointer)
                        continue;
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
            passes.addStartPass(regAllocPass);

            MicroPassContext passCtx;
            passCtx.callConvKind = callConvKind;
            SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));
            SWC_RESULT(Backend::Unittest::assertNoVirtualRegs(builder));
            SWC_RESULT(verifyCallConvConformity(builder, CallConv::get(passCtx.callConvKind)));
        }

        return Result::Continue;
    }

    void buildPersistentAcross(MicroBuilder& b, CallConvKind callConvKind)
    {
        constexpr MicroReg v0 = MicroReg::virtualIntReg(0);
        constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
        constexpr MicroReg v2 = MicroReg::virtualIntReg(2);

        b.emitLoadRegImm(v0, ApInt(1, 64), MicroOpBits::B64);
        b.emitLoadRegImm(v1, ApInt(2, 64), MicroOpBits::B64);
        b.emitCallReg(MicroReg::intReg(0), callConvKind);
        b.emitOpBinaryRegImm(v0, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        b.emitOpBinaryRegImm(v1, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
        b.emitLoadRegImm(v2, ApInt(4, 64), MicroOpBits::B64);
        b.emitOpBinaryRegImm(v2, ApInt(5, 64), MicroOp::Add, MicroOpBits::B64);
        b.emitCallReg(MicroReg::intReg(0), callConvKind);
        b.emitOpBinaryRegImm(v0, ApInt(7, 64), MicroOp::Add, MicroOpBits::B64);
    }

    void buildNoCalls(MicroBuilder& b, CallConvKind)
    {
        constexpr MicroReg v0 = MicroReg::virtualIntReg(10);
        constexpr MicroReg v1 = MicroReg::virtualIntReg(11);
        constexpr MicroReg v2 = MicroReg::virtualIntReg(12);

        b.emitLoadRegImm(v0, ApInt(1, 64), MicroOpBits::B64);
        b.emitOpBinaryRegImm(v0, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        b.emitLoadRegImm(v1, ApInt(2, 64), MicroOpBits::B64);
        b.emitOpBinaryRegImm(v1, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        b.emitLoadRegImm(v2, ApInt(3, 64), MicroOpBits::B64);
        b.emitOpBinaryRegImm(v2, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    }

    void buildMixedIntFloat(MicroBuilder& b, CallConvKind callConvKind)
    {
        constexpr MicroReg vi  = MicroReg::virtualIntReg(20);
        constexpr MicroReg vf0 = MicroReg::virtualFloatReg(0);
        constexpr MicroReg vf1 = MicroReg::virtualFloatReg(1);
        constexpr MicroReg vf2 = MicroReg::virtualFloatReg(2);
        constexpr MicroReg vf3 = MicroReg::virtualFloatReg(3);

        b.emitLoadRegImm(vi, ApInt(9, 64), MicroOpBits::B64);
        b.emitClearReg(vf0, MicroOpBits::B64);
        b.emitClearReg(vf1, MicroOpBits::B64);
        b.emitOpBinaryRegReg(vf0, vf1, MicroOp::FloatXor, MicroOpBits::B64);
        b.emitCallReg(MicroReg::intReg(0), callConvKind);
        b.emitOpBinaryRegImm(vi, ApInt(2, 64), MicroOp::Add, MicroOpBits::B64);
        b.emitClearReg(vf2, MicroOpBits::B64);
        b.emitClearReg(vf3, MicroOpBits::B64);
        b.emitOpBinaryRegReg(vf2, vf3, MicroOp::FloatXor, MicroOpBits::B64);
    }

    void buildLotsOfVirtualRegs(MicroBuilder& b, CallConvKind callConvKind)
    {
        for (uint32_t i = 0; i < 128; ++i)
        {
            const auto v = MicroReg::virtualIntReg(1000 + i);
            b.emitLoadRegImm(v, ApInt(i + 1, 64), MicroOpBits::B64);
            b.emitOpBinaryRegImm(v, ApInt((i & 7) + 1, 64), MicroOp::Add, MicroOpBits::B64);
            if ((i % 16) == 15)
                b.emitCallReg(MicroReg::intReg(0), callConvKind);
        }

        for (uint32_t i = 0; i < 64; ++i)
        {
            const auto v0 = MicroReg::virtualFloatReg(2000 + i * 2);
            const auto v1 = MicroReg::virtualFloatReg(2000 + i * 2 + 1);
            b.emitClearReg(v0, MicroOpBits::B64);
            b.emitClearReg(v1, MicroOpBits::B64);
            b.emitOpBinaryRegReg(v0, v1, MicroOp::FloatXor, MicroOpBits::B64);
            if ((i % 16) == 15)
                b.emitCallReg(MicroReg::intReg(0), callConvKind);
        }
    }

    void buildPersistentWithReturn(MicroBuilder& b, CallConvKind callConvKind)
    {
        constexpr MicroReg v0 = MicroReg::virtualIntReg(3000);

        b.emitLoadRegImm(v0, ApInt(1, 64), MicroOpBits::B64);
        b.emitCallReg(MicroReg::intReg(0), callConvKind);
        b.emitOpBinaryRegImm(v0, ApInt(2, 64), MicroOp::Add, MicroOpBits::B64);
        b.emitRet();
    }

    void buildNoPersistentWithReturn(MicroBuilder& b, CallConvKind)
    {
        constexpr MicroReg v0 = MicroReg::virtualIntReg(3100);

        b.emitLoadRegImm(v0, ApInt(3, 64), MicroOpBits::B64);
        b.emitRet();
    }

    void buildIntSpillPressureAcrossCall(MicroBuilder& b, CallConvKind callConvKind)
    {
        for (uint32_t i = 0; i < 24; ++i)
        {
            const auto v = MicroReg::virtualIntReg(4000 + i);
            b.emitLoadRegImm(v, ApInt(i + 1, 64), MicroOpBits::B64);
        }

        b.emitCallReg(MicroReg::intReg(0), callConvKind);

        for (uint32_t i = 0; i < 24; ++i)
        {
            const auto v = MicroReg::virtualIntReg(4000 + i);
            b.emitOpBinaryRegImm(v, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
        }

        b.emitRet();
    }

    void buildFloatSpillAcrossCallNoPersistentRegs(MicroBuilder& b, CallConvKind callConvKind)
    {
        for (uint32_t i = 0; i < 16; ++i)
        {
            const auto v = MicroReg::virtualFloatReg(5000 + i);
            b.emitClearReg(v, MicroOpBits::B64);
        }

        b.emitCallReg(MicroReg::intReg(0), callConvKind);

        for (uint32_t i = 0; i < 16; ++i)
        {
            const auto v = MicroReg::virtualFloatReg(5000 + i);
            b.emitOpBinaryRegReg(v, v, MicroOp::FloatXor, MicroOpBits::B64);
        }

        b.emitRet();
    }

    void buildForbiddenIntArgRegs(MicroBuilder& b, CallConvKind callConvKind)
    {
        const CallConv& conv = CallConv::get(callConvKind);

        constexpr MicroReg v0 = MicroReg::virtualIntReg(6000);
        constexpr MicroReg v1 = MicroReg::virtualIntReg(6001);
        b.addVirtualRegForbiddenPhysRegs(v0, conv.intArgRegs);
        b.addVirtualRegForbiddenPhysRegs(v1, conv.intArgRegs);

        b.emitLoadRegImm(v0, ApInt(11, 64), MicroOpBits::B64);
        b.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
        b.emitOpBinaryRegReg(v0, v1, MicroOp::Add, MicroOpBits::B64);
        b.emitRet();
    }

    void buildSpillAcrossBalancedControlFlow(MicroBuilder& b, CallConvKind callConvKind)
    {
        const CallConv&     conv      = CallConv::get(callConvKind);
        const MicroLabelRef elseLabel = b.createLabel();
        const MicroLabelRef doneLabel = b.createLabel();

        for (uint32_t i = 0; i < 20; ++i)
        {
            const auto v = MicroReg::virtualIntReg(7000 + i);
            b.emitLoadRegImm(v, ApInt(i + 3, 64), MicroOpBits::B64);
        }

        constexpr MicroReg cmpL = MicroReg::virtualIntReg(7100);
        constexpr MicroReg cmpR = MicroReg::virtualIntReg(7101);
        b.emitLoadRegImm(cmpL, ApInt(1, 64), MicroOpBits::B64);
        b.emitLoadRegImm(cmpR, ApInt(2, 64), MicroOpBits::B64);
        b.emitCmpRegReg(cmpL, cmpR, MicroOpBits::B64);
        b.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, elseLabel);

        b.emitOpBinaryRegImm(conv.stackPointer, ApInt(16, 64), MicroOp::Subtract, MicroOpBits::B64);
        b.emitCallReg(MicroReg::intReg(0), callConvKind);
        b.emitOpBinaryRegImm(conv.stackPointer, ApInt(16, 64), MicroOp::Add, MicroOpBits::B64);
        b.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

        b.placeLabel(elseLabel);
        b.emitOpBinaryRegImm(conv.stackPointer, ApInt(16, 64), MicroOp::Subtract, MicroOpBits::B64);
        b.emitCallReg(MicroReg::intReg(0), callConvKind);
        b.emitOpBinaryRegImm(conv.stackPointer, ApInt(16, 64), MicroOp::Add, MicroOpBits::B64);

        b.placeLabel(doneLabel);
        for (uint32_t i = 0; i < 20; ++i)
        {
            const auto v = MicroReg::virtualIntReg(7000 + i);
            b.emitOpBinaryRegImm(v, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        }

        b.emitRet();
    }

    void buildLoadBaseAddressAcrossCall(MicroBuilder& b, CallConvKind callConvKind)
    {
        const CallConv& conv = CallConv::get(callConvKind);

        constexpr MicroReg basePtr     = MicroReg::virtualIntReg(7200);
        constexpr MicroReg storedValue = MicroReg::virtualIntReg(7201);
        constexpr MicroReg loadedValue = MicroReg::virtualIntReg(7202);
        constexpr MicroReg reloadValue = MicroReg::virtualIntReg(7203);

        b.emitLoadRegReg(basePtr, conv.stackPointer, MicroOpBits::B64);
        b.emitOpBinaryRegImm(basePtr, ApInt(0x40, 64), MicroOp::Add, MicroOpBits::B64);
        b.emitLoadRegImm(storedValue, ApInt(0x11223344, 64), MicroOpBits::B64);
        b.emitLoadMemReg(basePtr, 0, storedValue, MicroOpBits::B32);
        b.emitLoadRegMem(loadedValue, basePtr, 0, MicroOpBits::B64);
        b.emitLoadRegReg(conv.intArgRegs[0], loadedValue, MicroOpBits::B64);
        b.emitCallReg(MicroReg::intReg(0), callConvKind);
        b.emitLoadRegMem(reloadValue, basePtr, 0, MicroOpBits::B32);
        b.emitRet();
    }

    void buildConcreteLoadDestAcrossCall(MicroBuilder& b, CallConvKind callConvKind)
    {
        const CallConv& conv = CallConv::get(callConvKind);

        constexpr MicroReg basePtr     = MicroReg::virtualIntReg(7300);
        constexpr MicroReg storedValue = MicroReg::virtualIntReg(7301);
        constexpr MicroReg reloadValue = MicroReg::virtualIntReg(7302);

        SWC_ASSERT(!conv.intArgRegs.empty());

        b.emitLoadRegReg(basePtr, conv.stackPointer, MicroOpBits::B64);
        b.emitOpBinaryRegImm(basePtr, ApInt(0x48, 64), MicroOp::Add, MicroOpBits::B64);
        b.emitLoadRegImm(storedValue, ApInt(0x55667788, 64), MicroOpBits::B64);
        b.emitLoadMemReg(basePtr, 0, storedValue, MicroOpBits::B32);
        b.emitLoadRegMem(conv.intArgRegs[0], basePtr, 0, MicroOpBits::B64);
        b.emitCallReg(MicroReg::intReg(0), callConvKind);
        b.emitLoadRegMem(reloadValue, basePtr, 0, MicroOpBits::B32);
        b.emitRet();
    }

    void buildVirtualDefAvoidsLiveConcreteReg(MicroBuilder& b, CallConvKind callConvKind)
    {
        const CallConv& conv = CallConv::get(callConvKind);

        constexpr MicroReg liveAddrReg = MicroReg::intReg(11);
        constexpr MicroReg altReg      = MicroReg::intReg(10);
        constexpr MicroReg srcReg      = MicroReg::intReg(8);
        constexpr MicroReg tmpValue    = MicroReg::virtualIntReg(7400);

        SmallVector<MicroReg> forbiddenRegs;
        for (const auto reg : conv.intRegs)
        {
            if (reg == liveAddrReg || reg == altReg)
                continue;

            forbiddenRegs.push_back(reg);
        }

        b.addVirtualRegForbiddenPhysRegs(tmpValue, forbiddenRegs.span());
        b.emitLoadRegReg(liveAddrReg, conv.stackPointer, MicroOpBits::B64);
        b.emitOpBinaryRegImm(liveAddrReg, ApInt(0x40, 64), MicroOp::Add, MicroOpBits::B64);
        b.emitLoadRegImm(srcReg, ApInt(0x11223344, 64), MicroOpBits::B64);
        b.emitLoadRegReg(tmpValue, srcReg, MicroOpBits::B64);
        b.emitLoadMemReg(conv.stackPointer, 0x20, liveAddrReg, MicroOpBits::B64);
        b.emitLoadRegReg(conv.intReturn, tmpValue, MicroOpBits::B64);
        b.emitRet();
    }

    void buildConcreteCopyUsesPersistentFallback(MicroBuilder& b, CallConvKind callConvKind)
    {
        const CallConv& conv = CallConv::get(callConvKind);
        if (conv.intPersistentRegs.empty())
            return;

        const MicroReg     srcReg     = conv.intArgRegs.empty() ? conv.intTransientRegs[0] : conv.intArgRegs[0];
        constexpr MicroReg savedValue = MicroReg::virtualIntReg(7401);

        SmallVector<MicroReg> forbiddenRegs;
        for (const auto reg : conv.intTransientRegs)
        {
            if (reg == srcReg)
                continue;

            forbiddenRegs.push_back(reg);
        }

        b.addVirtualRegForbiddenPhysRegs(savedValue, forbiddenRegs.span());
        b.emitLoadRegImm(srcReg, ApInt(0x11223344, 64), MicroOpBits::B64);
        b.emitLoadRegReg(savedValue, srcReg, MicroOpBits::B64);
        b.emitLoadRegImm(srcReg, ApInt(0x55667788, 64), MicroOpBits::B64);
        b.emitLoadRegReg(conv.intReturn, savedValue, MicroOpBits::B64);
        b.emitRet();
    }

    void buildVirtualCopyCoalescing(MicroBuilder& b, CallConvKind callConvKind)
    {
        const CallConv& conv = CallConv::get(callConvKind);

        constexpr MicroReg srcValue  = MicroReg::virtualIntReg(7500);
        constexpr MicroReg copiedReg = MicroReg::virtualIntReg(7501);

        b.addVirtualRegForbiddenPhysReg(srcValue, conv.intReturn);
        b.emitLoadRegImm(srcValue, ApInt(0x11223344, 64), MicroOpBits::B64);
        b.emitLoadRegReg(copiedReg, srcValue, MicroOpBits::B64);
        b.emitLoadRegReg(conv.intReturn, copiedReg, MicroOpBits::B64);
        b.emitRet();
    }

    void buildBarrieredVirtualCopyTransfer(MicroBuilder& b, CallConvKind callConvKind)
    {
        const CallConv&     conv         = CallConv::get(callConvKind);
        const MicroLabelRef barrierLabel = b.createLabel();

        constexpr MicroReg srcValue  = MicroReg::virtualIntReg(7550);
        constexpr MicroReg copiedReg = MicroReg::virtualIntReg(7551);

        b.emitLoadRegImm(srcValue, ApInt(0x55667788, 64), MicroOpBits::B64);
        b.emitLoadRegReg(copiedReg, srcValue, MicroOpBits::B64);
        b.placeLabel(barrierLabel);
        b.emitLoadRegReg(conv.intReturn, copiedReg, MicroOpBits::B64);
        b.emitRet();
    }

    void buildImmediateRematerialization(MicroBuilder& b, CallConvKind callConvKind)
    {
        const CallConv& conv = CallConv::get(callConvKind);
        SWC_ASSERT(!conv.intTransientRegs.empty());

        const MicroReg     forcedReg   = conv.intTransientRegs.back();
        constexpr MicroReg rematValue  = MicroReg::virtualIntReg(7600);
        SmallVector<MicroReg> forbiddenRegs;
        forbiddenRegs.reserve(conv.intRegs.size());
        for (const MicroReg reg : conv.intRegs)
        {
            if (reg == forcedReg)
                continue;

            forbiddenRegs.push_back(reg);
        }

        b.addVirtualRegForbiddenPhysRegs(rematValue, forbiddenRegs.span());
        b.emitLoadRegImm(rematValue, ApInt(0x12345678, 64), MicroOpBits::B64);
        b.emitLoadRegImm(forcedReg, ApInt(0x55, 64), MicroOpBits::B64);
        b.emitLoadRegReg(conv.intReturn, rematValue, MicroOpBits::B64);
        b.emitRet();
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

        std::unordered_set<MicroReg> spillBaseRegs;
        spillBaseRegs.insert(conv.stackPointer);

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

            if (inst.op == MicroInstrOpcode::LoadRegReg)
            {
                const MicroInstrOperand* ops = inst.ops(storeOps);
                if (ops[1].reg == conv.stackPointer && ops[2].opBits == MicroOpBits::B64)
                    spillBaseRegs.insert(ops[0].reg);
                continue;
            }

            if (inst.op != MicroInstrOpcode::LoadMemReg && inst.op != MicroInstrOpcode::LoadRegMem)
                continue;

            const MicroInstrOperand* ops = inst.ops(storeOps);
            if (inst.op == MicroInstrOpcode::LoadMemReg)
            {
                if (spillBaseRegs.contains(ops[0].reg))
                    hasStore = true;
            }
            else if (spillBaseRegs.contains(ops[1].reg))
            {
                hasLoad = true;
            }
        }

        return hasSub && hasAdd && hasStore && hasLoad;
    }

    uint32_t countOpcode(MicroBuilder& builder, MicroInstrOpcode opcode)
    {
        uint32_t result = 0;
        for (const auto& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                result++;
        }

        return result;
    }

    uint32_t countLoadRegImmValue(MicroBuilder& builder, uint64_t value)
    {
        uint32_t result = 0;
        auto&    storeOps = builder.operands();
        for (const auto& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::LoadRegImm)
                continue;

            const MicroInstrOperand* ops = inst.ops(storeOps);
            if (ops && ops[2].immediateValue(64).as64() == value)
                result++;
        }

        return result;
    }

    bool containsIntArgRegs(MicroBuilder& builder, const CallConv& conv)
    {
        auto& storeOps = builder.operands();
        for (const auto& inst : builder.instructions().view())
        {
            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(storeOps, refs, nullptr);
            for (const auto& microLabelRef : refs)
            {
                if (!microLabelRef.reg)
                    continue;

                const MicroReg reg = *microLabelRef.reg;
                if (!reg.isInt())
                    continue;

                if (std::ranges::find(conv.intArgRegs, reg) != conv.intArgRegs.end())
                    return true;
            }
        }

        return false;
    }

    bool hasAliasingLoadBase(MicroBuilder& builder)
    {
        auto& storeOps = builder.operands();
        for (const auto& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::LoadRegMem &&
                inst.op != MicroInstrOpcode::LoadSignedExtRegMem &&
                inst.op != MicroInstrOpcode::LoadZeroExtRegMem)
                continue;

            const MicroInstrOperand* ops = inst.ops(storeOps);
            if (!ops)
                continue;

            if (ops[0].reg == ops[1].reg)
                return true;
        }

        return false;
    }

    bool returnUsesReg(MicroBuilder& builder, MicroReg returnReg, MicroReg reg)
    {
        auto& storeOps = builder.operands();
        for (const auto& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::LoadRegReg)
                continue;

            const MicroInstrOperand* ops = inst.ops(storeOps);
            if (!ops)
                continue;

            if (ops[0].reg == returnReg && ops[1].reg == reg)
                return true;
        }

        return false;
    }

    bool returnUsesPersistentReg(MicroBuilder& builder, MicroReg returnReg, const CallConv& conv)
    {
        auto& storeOps = builder.operands();
        for (const auto& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::LoadRegReg)
                continue;

            const MicroInstrOperand* ops = inst.ops(storeOps);
            if (!ops || ops[0].reg != returnReg)
                continue;

            if (std::ranges::find(conv.intPersistentRegs, ops[1].reg) != conv.intPersistentRegs.end())
                return true;
        }

        return false;
    }

}

SWC_TEST_BEGIN(RegAlloc_PersistentAcross)
{
    SWC_RESULT(runCase(ctx, buildPersistentAcross));
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_NoCalls)
{
    SWC_RESULT(runCase(ctx, buildNoCalls));
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_MixedIntFloat)
{
    SWC_RESULT(runCase(ctx, buildMixedIntFloat));
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_LotsOfVirtualRegs)
{
    SWC_RESULT(runCase(ctx, buildLotsOfVirtualRegs));
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
        passes.addStartPass(regAllocPass);
        passes.addStartPass(persistentRegsPass);

        MicroPassContext passCtx;
        passCtx.callConvKind           = callConvKind;
        passCtx.preservePersistentRegs = true;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

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
        passes.addStartPass(regAllocPass);
        passes.addStartPass(persistentRegsPass);

        MicroPassContext passCtx;
        passCtx.callConvKind           = callConvKind;
        passCtx.preservePersistentRegs = false;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

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
        passes.addStartPass(regAllocPass);
        passes.addStartPass(persistentRegsPass);

        MicroPassContext passCtx;
        passCtx.callConvKind           = callConvKind;
        passCtx.preservePersistentRegs = true;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

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
        passes.addStartPass(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

        SWC_RESULT(Backend::Unittest::assertNoVirtualRegs(builder));

        // Either spilling kicked in, or every value was rematerialized at its use
        // site (24 fresh loads). Anything below 24 would mean some use lost its value.
        if (!hasSpillFrameOps(builder, CallConv::get(callConvKind)) &&
            countOpcode(builder, MicroInstrOpcode::LoadRegImm) < 24)
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
        passes.addStartPass(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

        SWC_RESULT(Backend::Unittest::assertNoVirtualRegs(builder));

        if (!hasSpillFrameOps(builder, CallConv::get(callConvKind)) &&
            countOpcode(builder, MicroInstrOpcode::LoadRegImm) == 0)
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
        passes.addStartPass(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

        SWC_RESULT(Backend::Unittest::assertNoVirtualRegs(builder));
        if (containsIntArgRegs(builder, CallConv::get(callConvKind)))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_Spill_BalancedControlFlow)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroBuilder builder(ctx);
        buildSpillAcrossBalancedControlFlow(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPassManager            passes;
        passes.addStartPass(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

        SWC_RESULT(Backend::Unittest::assertNoVirtualRegs(builder));

        if (!hasSpillFrameOps(builder, CallConv::get(callConvKind)))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_LoadBaseAddressAcrossCall)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroBuilder builder(ctx);
        buildLoadBaseAddressAcrossCall(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPassManager            passes;
        passes.addStartPass(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

        SWC_RESULT(Backend::Unittest::assertNoVirtualRegs(builder));

        if (hasAliasingLoadBase(builder))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_ConcreteLoadDestAcrossCall)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroBuilder builder(ctx);
        buildConcreteLoadDestAcrossCall(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPassManager            passes;
        passes.addStartPass(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

        SWC_RESULT(Backend::Unittest::assertNoVirtualRegs(builder));

        if (hasAliasingLoadBase(builder))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_VirtualDefAvoidsLiveConcreteReg)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroBuilder builder(ctx);
        buildVirtualDefAvoidsLiveConcreteReg(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPassManager            passes;
        passes.addStartPass(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

        SWC_RESULT(Backend::Unittest::assertNoVirtualRegs(builder));

        if (returnUsesReg(builder, CallConv::get(callConvKind).intReturn, MicroReg::intReg(11)))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_UsesPersistentFallbackWhenTransientPoolExhausted)
{
    for (const auto callConvKind : testedCallConvs())
    {
        const CallConv& conv = CallConv::get(callConvKind);
        if (conv.intPersistentRegs.empty())
            continue;

        MicroBuilder builder(ctx);
        buildConcreteCopyUsesPersistentFallback(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPassManager            passes;
        passes.addStartPass(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

        SWC_RESULT(Backend::Unittest::assertNoVirtualRegs(builder));

        if (!returnUsesPersistentReg(builder, conv.intReturn, conv))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_CoalescesLinearVirtualCopies)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroBuilder builder(ctx);
        buildVirtualCopyCoalescing(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPassManager            passes;
        passes.addStartPass(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

        SWC_RESULT(Backend::Unittest::assertNoVirtualRegs(builder));
        SWC_RESULT(verifyCallConvConformity(builder, CallConv::get(callConvKind)));

        if (countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_TransfersDeadCopySourcesAcrossBarriers)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroBuilder builder(ctx);
        buildBarrieredVirtualCopyTransfer(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPassManager            passes;
        passes.addStartPass(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

        SWC_RESULT(Backend::Unittest::assertNoVirtualRegs(builder));
        SWC_RESULT(verifyCallConvConformity(builder, CallConv::get(callConvKind)));

        if (countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(RegAlloc_RematerializesImmediateReloads)
{
    for (const auto callConvKind : testedCallConvs())
    {
        MicroBuilder builder(ctx);
        buildImmediateRematerialization(builder, callConvKind);

        MicroRegisterAllocationPass regAllocPass;
        MicroPassManager            passes;
        passes.addStartPass(regAllocPass);

        MicroPassContext passCtx;
        passCtx.callConvKind = callConvKind;
        SWC_RESULT(builder.runPasses(passes, nullptr, passCtx));

        SWC_RESULT(Backend::Unittest::assertNoVirtualRegs(builder));
        SWC_RESULT(verifyCallConvConformity(builder, CallConv::get(callConvKind)));

        // The original LoadRegImm is overwritten before its only use, so RA prunes
        // it after rematerializing the constant at the use site. One load remains.
        if (countLoadRegImmValue(builder, 0x12345678) != 1)
            return Result::Error;
        if (hasSpillFrameOps(builder, CallConv::get(callConvKind)))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
