#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.PrologEpilog.h"
#include "Backend/Micro/Passes/Pass.PrologEpilogSanitize.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runPrologEpilogSanitizePass(MicroBuilder& builder, const bool forceFramePointer = false)
    {
        MicroPrologEpilogSanitizePass pass;
        MicroPassManager              passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind      = CallConvKind::Swag;
        passContext.forceFramePointer = forceFramePointer;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    const MicroInstr* instructionAt(const MicroBuilder& builder, uint32_t index)
    {
        uint32_t currentIndex = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (currentIndex == index)
                return &inst;
            ++currentIndex;
        }

        return nullptr;
    }

    bool isStackAdjust(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg stackPointer, MicroOp expectedOp, uint64_t expectedImmediate)
    {
        if (!ops)
            return false;
        if (inst.op != MicroInstrOpcode::OpBinaryRegImm || inst.numOperands < 4)
            return false;
        if (ops[0].reg != stackPointer || ops[1].opBits != MicroOpBits::B64)
            return false;
        if (ops[2].microOp != expectedOp)
            return false;
        if (ops[3].valueU64 != expectedImmediate)
            return false;
        return true;
    }

    bool isFramePointerSetup(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg framePointer, MicroReg stackPointer)
    {
        if (!ops)
            return false;

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
                if (inst.numOperands < 3)
                    return false;
                return ops[0].reg == framePointer && ops[1].reg == stackPointer && ops[2].opBits == MicroOpBits::B64;

            case MicroInstrOpcode::LoadAddrRegMem:
                if (inst.numOperands < 4)
                    return false;
                return ops[0].reg == framePointer && ops[1].reg == stackPointer && ops[2].opBits == MicroOpBits::B64;

            default:
                return false;
        }
    }

    // The canonical ABI-conformant setup is `mov fp, sp` (so fp == final stack pointer, encodable as
    // UWOP_SET_FPREG FrameOffset 0 for any frame size), emitted after the stack is fully shaped.
    bool isFramePointerMovAfterStackShape(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg framePointer, MicroReg stackPointer)
    {
        if (!ops || inst.op != MicroInstrOpcode::LoadRegReg || inst.numOperands < 3)
            return false;
        return ops[0].reg == framePointer && ops[1].reg == stackPointer && ops[2].opBits == MicroOpBits::B64;
    }

    bool isStackProbeLoad(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg probeReg, MicroReg stackPointer, uint64_t expectedOffset)
    {
        if (!ops)
            return false;
        if (inst.op != MicroInstrOpcode::LoadRegMem || inst.numOperands < 4)
            return false;
        if (ops[0].reg != probeReg)
            return false;
        if (ops[1].reg != stackPointer)
            return false;
        if (ops[2].opBits != MicroOpBits::B64)
            return false;
        if (ops[3].valueU64 != expectedOffset)
            return false;
        return true;
    }
}

SWC_TEST_BEGIN(MicroPrologEpilog_FirstDefinitionsPreserveSaveOrderAcrossRegisterClasses)
{
    const CallConv& conv = CallConv::get(CallConvKind::WindowsX64);
    MicroBuilder    builder(ctx);

    // A call keeps the leaf-remapping stage out of this saved-register plan.
    builder.emitCallReg(conv.intReturn, CallConvKind::WindowsX64);
    builder.emitLoadRegReg(conv.intReturn, MicroReg::intReg(7), MicroOpBits::B64);
    builder.emitLoadRegReg(conv.floatReturn, MicroReg::floatReg(7), MicroOpBits::B64);
    builder.emitLoadRegReg(conv.intReturn, MicroReg::intReg(12), MicroOpBits::B64);
    builder.emitLoadRegReg(conv.intReturn, conv.framePointer, MicroOpBits::B64);
    for (uint32_t repetition = 0; repetition < 3; ++repetition)
    {
        for (uint32_t index = 6; index <= 7; ++index)
        {
            builder.emitLoadRegMem(MicroReg::intReg(index), conv.stackPointer, 64, MicroOpBits::B64);
            builder.emitLoadRegMem(MicroReg::floatReg(index), conv.stackPointer, 64, MicroOpBits::B64);
        }
    }
    builder.emitRet();

    MicroPrologEpilogPass pass;
    MicroPassManager      passManager;
    passManager.addStartPass(pass);
    MicroPassContext passContext;
    passContext.callConvKind           = CallConvKind::WindowsX64;
    passContext.preservePersistentRegs = true;
    SWC_RESULT(builder.runPasses(passManager, nullptr, passContext));

    const std::array expectedPushes = {conv.framePointer, MicroReg::intReg(6), MicroReg::intReg(7)};
    uint32_t         pushes         = 0;
    uint32_t         pops           = 0;
    uint32_t         floatSaves     = 0;
    uint32_t         floatRestores  = 0;
    uint32_t         frameSetups    = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::Push)
        {
            if (pushes >= expectedPushes.size() || ops[0].reg != expectedPushes[pushes++])
                return Result::Error;
        }
        else if (inst.op == MicroInstrOpcode::Pop)
        {
            if (pops >= expectedPushes.size() || ops[0].reg != expectedPushes[expectedPushes.size() - 1 - pops++])
                return Result::Error;
        }
        else if (inst.op == MicroInstrOpcode::LoadMemReg && ops[2].opBits == MicroOpBits::B128)
        {
            if (floatSaves >= 2 || ops[0].reg != conv.stackPointer || ops[1].reg != MicroReg::floatReg(6 + floatSaves) || ops[3].valueU64 != floatSaves * 16)
                return Result::Error;
            ++floatSaves;
        }
        else if (inst.op == MicroInstrOpcode::LoadRegMem && ops[2].opBits == MicroOpBits::B128)
        {
            if (floatRestores >= 2 || ops[0].reg != MicroReg::floatReg(6 + floatRestores) || ops[1].reg != conv.stackPointer || ops[3].valueU64 != floatRestores * 16)
                return Result::Error;
            ++floatRestores;
        }
        else if (isFramePointerSetup(inst, ops, conv.framePointer, conv.stackPointer))
            ++frameSetups;
    }
    if (pushes != 3 || pops != 3 || floatSaves != 2 || floatRestores != 2 || frameSetups != 1)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilog_RestoresEveryReturnFromOriginalAnchors)
{
    const CallConv& conv  = CallConv::get(CallConvKind::WindowsX64);
    constexpr auto  saved = MicroReg::intReg(7);
    MicroBuilder    builder(ctx);
    const auto      alternate = builder.createLabel();
    // A call prevents leaf remapping from removing the persistent register.
    builder.emitCallReg(conv.intReturn, CallConvKind::WindowsX64);
    const auto originalFirst = builder.instructions().lastInstructionRef();
    builder.emitLoadRegImm(saved, ApInt(17, 64), MicroOpBits::B64);
    builder.emitCmpRegImm(conv.intReturn, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, alternate);
    builder.emitRet();
    const auto firstRet = builder.instructions().lastInstructionRef();
    builder.placeLabel(alternate);
    builder.emitRet();
    const auto secondRet = builder.instructions().lastInstructionRef();

    MicroPrologEpilogPass pass;
    MicroPassManager      manager;
    manager.addStartPass(pass);
    MicroPassContext context;
    context.callConvKind           = CallConvKind::WindowsX64;
    context.preservePersistentRegs = true;
    SWC_RESULT(builder.runPasses(manager, nullptr, context));
    if (builder.instructions().count() != 13)
        return Result::Error;

    const auto& operands = builder.operands();
    const auto  first    = builder.instructions().view().begin();
    if (first->op != MicroInstrOpcode::Push || first->ops(operands)[0].reg != saved)
        return Result::Error;
    const auto  subtractRef = builder.instructions().findNextInstructionRef(first.current);
    const auto* subtract    = builder.instructions().ptr(subtractRef);
    if (!subtract || !isStackAdjust(*subtract, subtract->ops(operands), conv.stackPointer, MicroOp::Subtract, 8) ||
        builder.instructions().findNextInstructionRef(subtractRef) != originalFirst)
        return Result::Error;

    uint32_t returns = 0;
    for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
    {
        if (it->op != MicroInstrOpcode::Ret)
            continue;
        if (returns >= 2 || it.current != (returns ? secondRet : firstRet))
            return Result::Error;
        const auto  popRef = builder.instructions().findPreviousInstructionRef(it.current);
        const auto* pop    = builder.instructions().ptr(popRef);
        if (!pop || pop->op != MicroInstrOpcode::Pop || pop->ops(operands)[0].reg != saved)
            return Result::Error;
        const auto* add = builder.instructions().ptr(builder.instructions().findPreviousInstructionRef(popRef));
        if (!add || !isStackAdjust(*add, add->ops(operands), conv.stackPointer, MicroOp::Add, 8))
            return Result::Error;
        ++returns;
    }
    return returns == 2 ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_MergesAdjacentStackAdjustments)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rbp = MicroReg::intReg(5);
    MicroBuilder       builder(ctx);

    builder.emitPush(rbp);
    builder.emitLoadRegReg(rbp, rsp, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rsp, ApInt(16, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rsp, ApInt(32, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitNop();
    builder.emitOpBinaryRegImm(rsp, ApInt(24, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rsp, ApInt(8, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPrologEpilogSanitizePass(builder));

    if (builder.instructions().count() != 6)
        return Result::Error;

    // Prologue is shaped first (`sub sp, 48`), then the frame pointer is established
    // with `mov rbp, rsp` so it equals the final stack pointer (UWOP_SET_FPREG FrameOffset 0).
    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          subInst  = instructionAt(builder, 1);
    const MicroInstr*          fpInst   = instructionAt(builder, 2);
    const MicroInstr*          addInst  = instructionAt(builder, 4);
    if (!subInst || !fpInst || !addInst)
        return Result::Error;

    if (!isStackAdjust(*subInst, subInst->ops(operands), rsp, MicroOp::Subtract, 48))
        return Result::Error;
    if (!isFramePointerMovAfterStackShape(*fpInst, fpInst->ops(operands), rbp, rsp))
        return Result::Error;
    if (!isStackAdjust(*addInst, addInst->ops(operands), rsp, MicroOp::Add, 32))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_DoesNotMergeOutsideEntryExitRegions)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rbp = MicroReg::intReg(5);
    MicroBuilder       builder(ctx);

    builder.emitPush(rbp);
    builder.emitLoadRegReg(rbp, rsp, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rsp, ApInt(16, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitNop();
    builder.emitOpBinaryRegImm(rsp, ApInt(32, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rsp, ApInt(32, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPrologEpilogSanitizePass(builder));

    if (builder.instructions().count() != 7)
        return Result::Error;

    // Only the entry-region `sub sp, 16` is part of the prologue; the frame pointer is established
    // right after it. The second `sub sp, 32` sits past the body start and is left untouched.
    const MicroOperandStorage& operands       = builder.operands();
    const MicroInstr*          firstSubInst   = instructionAt(builder, 1);
    const MicroInstr*          fpInst         = instructionAt(builder, 2);
    const MicroInstr*          secondSubInst  = instructionAt(builder, 4);
    const MicroInstr*          epilogueAddIns = instructionAt(builder, 5);
    if (!firstSubInst || !fpInst || !secondSubInst || !epilogueAddIns)
        return Result::Error;

    if (!isStackAdjust(*firstSubInst, firstSubInst->ops(operands), rsp, MicroOp::Subtract, 16))
        return Result::Error;
    if (!isFramePointerMovAfterStackShape(*fpInst, fpInst->ops(operands), rbp, rsp))
        return Result::Error;
    if (!isStackAdjust(*secondSubInst, secondSubInst->ops(operands), rsp, MicroOp::Subtract, 32))
        return Result::Error;
    if (!isStackAdjust(*epilogueAddIns, epilogueAddIns->ops(operands), rsp, MicroOp::Add, 32))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_ExpandsLargeWindowsStackAdjustIntoPageProbes)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rax = MicroReg::intReg(0);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(rsp, ApInt(12 * 1024, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPrologEpilogSanitizePass(builder));

    if (builder.instructions().count() != 5)
        return Result::Error;

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          subInst  = instructionAt(builder, 0);
    const MicroInstr*          probe0   = instructionAt(builder, 1);
    const MicroInstr*          probe1   = instructionAt(builder, 2);
    const MicroInstr*          probe2   = instructionAt(builder, 3);
    const MicroInstr*          retInst  = instructionAt(builder, 4);
    if (!subInst || !probe0 || !probe1 || !probe2 || !retInst)
        return Result::Error;

    if (!isStackAdjust(*subInst, subInst->ops(operands), rsp, MicroOp::Subtract, 12 * 1024ull))
        return Result::Error;
    if (!isStackProbeLoad(*probe0, probe0->ops(operands), rax, rsp, 8 * 1024ull))
        return Result::Error;
    if (!isStackProbeLoad(*probe1, probe1->ops(operands), rax, rsp, 4 * 1024ull))
        return Result::Error;
    if (!isStackProbeLoad(*probe2, probe2->ops(operands), rax, rsp, 0))
        return Result::Error;
    if (retInst->op != MicroInstrOpcode::Ret)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_KeepsOnlyLastFramePointerSetupInEntryProlog)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rbp = MicroReg::intReg(5);
    MicroBuilder       builder(ctx);

    builder.emitPush(rbp);
    builder.emitLoadRegReg(rbp, rsp, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rsp, ApInt(32, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitLoadRegReg(rbp, rsp, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPrologEpilogSanitizePass(builder));

    if (builder.instructions().count() != 4)
        return Result::Error;

    // Both setups collapse into a single `mov rbp, rsp` placed after the `sub sp, 32`.
    const MicroOperandStorage& operands   = builder.operands();
    const MicroInstr*          firstInst  = instructionAt(builder, 0);
    const MicroInstr*          secondInst = instructionAt(builder, 1);
    const MicroInstr*          thirdInst  = instructionAt(builder, 2);
    const MicroInstr*          fourthInst = instructionAt(builder, 3);
    if (!firstInst || !secondInst || !thirdInst || !fourthInst)
        return Result::Error;

    if (firstInst->op != MicroInstrOpcode::Push)
        return Result::Error;
    if (!isStackAdjust(*secondInst, secondInst->ops(operands), rsp, MicroOp::Subtract, 32))
        return Result::Error;
    if (!isFramePointerMovAfterStackShape(*thirdInst, thirdInst->ops(operands), rbp, rsp))
        return Result::Error;
    if (fourthInst->op != MicroInstrOpcode::Ret)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_ReinsertsForcedFramePointerSetupWhenMissing)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rbp = MicroReg::intReg(5);
    MicroBuilder       builder(ctx);

    builder.emitPush(rbp);
    builder.emitOpBinaryRegImm(rsp, ApInt(32, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPrologEpilogSanitizePass(builder, true));

    if (builder.instructions().count() != 4)
        return Result::Error;

    // A forced frame pointer with no existing setup is synthesized as `mov rbp, rsp`
    // after the `sub sp, 32` (fp == final stack pointer), not as a `mov rbp, rsp` at the top.
    const MicroOperandStorage& operands   = builder.operands();
    const MicroInstr*          firstInst  = instructionAt(builder, 0);
    const MicroInstr*          secondInst = instructionAt(builder, 1);
    const MicroInstr*          thirdInst  = instructionAt(builder, 2);
    const MicroInstr*          fourthInst = instructionAt(builder, 3);
    if (!firstInst || !secondInst || !thirdInst || !fourthInst)
        return Result::Error;

    if (firstInst->op != MicroInstrOpcode::Push)
        return Result::Error;
    if (!isStackAdjust(*secondInst, secondInst->ops(operands), rsp, MicroOp::Subtract, 32))
        return Result::Error;
    if (!isFramePointerMovAfterStackShape(*thirdInst, thirdInst->ops(operands), rbp, rsp))
        return Result::Error;
    if (fourthInst->op != MicroInstrOpcode::Ret)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_DoesNotTouchFramePointerSetupAfterBodyStarts)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rbp = MicroReg::intReg(5);
    MicroBuilder       builder(ctx);

    builder.emitPush(rbp);
    builder.emitLoadRegReg(rbp, rsp, MicroOpBits::B64);
    builder.emitNop();
    builder.emitLoadRegReg(rbp, rsp, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPrologEpilogSanitizePass(builder));

    if (builder.instructions().count() != 5)
        return Result::Error;

    const MicroOperandStorage& operands    = builder.operands();
    const MicroInstr*          firstSetup  = instructionAt(builder, 1);
    const MicroInstr*          secondSetup = instructionAt(builder, 3);
    if (!firstSetup || !secondSetup)
        return Result::Error;

    if (!isFramePointerSetup(*firstSetup, firstSetup->ops(operands), rbp, rsp))
        return Result::Error;
    if (!isFramePointerSetup(*secondSetup, secondSetup->ops(operands), rbp, rsp))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_MergesMultipleReturnSuffixesAfterRejectedPairs)
{
    constexpr auto     rsp = MicroReg::intReg(4);
    constexpr auto     rbx = MicroReg::intReg(3);
    constexpr uint64_t max = std::numeric_limits<uint64_t>::max();
    MicroBuilder       builder(ctx);
    builder.emitNop();
    std::array<MicroInstrRef, 5>      firstAdjusts;
    constexpr std::array<uint64_t, 5> firstAmounts = {8, 16, 32, 4, 4};
    for (uint32_t i = 0; i < firstAmounts.size(); ++i)
    {
        if (i == 3)
            builder.emitPop(rbx);
        builder.emitOpBinaryRegImm(rsp, ApInt(firstAmounts[i], 64), MicroOp::Add, MicroOpBits::B64);
        firstAdjusts[i] = builder.instructions().lastInstructionRef();
    }
    builder.emitRet();
    const auto firstRet = builder.instructions().lastInstructionRef();

    // The overflowing first pair is rejected, then the later pair merges.
    // Restarting must preserve that prefix and its original first reference.
    builder.emitNop();
    builder.emitOpBinaryRegImm(rsp, ApInt(max, 64), MicroOp::Add, MicroOpBits::B64);
    const auto overflow = builder.instructions().lastInstructionRef();
    builder.emitOpBinaryRegImm(rsp, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    const auto combined = builder.instructions().lastInstructionRef();
    builder.emitOpBinaryRegImm(rsp, ApInt(2, 64), MicroOp::Add, MicroOpBits::B64);
    const auto erased = builder.instructions().lastInstructionRef();
    builder.emitRet();
    const auto secondRet = builder.instructions().lastInstructionRef();
    builder.emitRet();
    const auto emptyRet = builder.instructions().lastInstructionRef();

    SWC_RESULT(runPrologEpilogSanitizePass(builder));
    if (builder.instructions().count() != 10 || builder.instructions().ptr(firstAdjusts[1]) ||
        builder.instructions().ptr(firstAdjusts[2]) || builder.instructions().ptr(firstAdjusts[4]) || builder.instructions().ptr(erased))
        return Result::Error;

    const std::array<MicroInstrRef, 4> survivors = {firstAdjusts[0], firstAdjusts[3], overflow, combined};
    constexpr std::array<uint64_t, 4>  amounts   = {56, 8, max, 3};
    for (uint32_t i = 0; i < survivors.size(); ++i)
    {
        const auto* inst = builder.instructions().ptr(survivors[i]);
        if (!inst || !isStackAdjust(*inst, inst->ops(builder.operands()), rsp, MicroOp::Add, amounts[i]))
            return Result::Error;
    }
    const std::array<MicroInstrRef, 3> returns     = {firstRet, secondRet, emptyRet};
    uint32_t                           returnIndex = 0;
    for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
    {
        if (it->op != MicroInstrOpcode::Ret)
            continue;
        if (returnIndex >= returns.size() || it.current != returns[returnIndex++])
            return Result::Error;
    }
    return returnIndex == returns.size() ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
