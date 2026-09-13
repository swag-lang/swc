#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.CopyElimination.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runCopyEliminationPass(MicroBuilder& builder)
    {
        MicroCopyEliminationPass pass;
        MicroPassManager         passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    const MicroInstr* findFirstOpcode(const MicroBuilder& builder, const MicroInstrOpcode opcode)
    {
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                return &inst;
        }

        return nullptr;
    }
}

// mov v1, v1 -> erased.
SWC_TEST_BEGIN(CopyElim_SelfCopy_Erased)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegReg(v1, v1, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runCopyEliminationPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// mov v2, v1 ; mov v3, v2 ; add v3, 1  -> first copy erased, second copy canonicalized to mov v3, v1.
SWC_TEST_BEGIN(CopyElim_ChainedCopies_CanonicalizesSource)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    constexpr MicroReg v2 = MicroReg::virtualIntReg(2);
    constexpr MicroReg v3 = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(5, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(v2, v1, MicroOpBits::B64);
    builder.emitLoadRegReg(v3, v2, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v3, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runCopyEliminationPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;

    const MicroInstr* copyInst = findFirstOpcode(builder, MicroInstrOpcode::LoadRegReg);
    if (!copyInst)
        return Result::Error;

    const MicroInstrOperand* ops = copyInst->ops(builder.operands());
    if (!ops || ops[0].reg != v3 || ops[1].reg != v1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// Two branch-local copies of the same source should fold through the join and drop both copies.
SWC_TEST_BEGIN(CopyElim_RewritesPureUseAcrossJoin)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    constexpr MicroReg v2 = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    const MicroLabelRef labelThen = builder.createLabel();
    const MicroLabelRef labelJoin = builder.createLabel();

    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, labelThen);
    builder.emitLoadRegReg(v2, v1, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, labelJoin);
    builder.placeLabel(labelThen);
    builder.emitLoadRegReg(v2, v1, MicroOpBits::B64);
    builder.placeLabel(labelJoin);
    builder.emitCmpRegImm(v2, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runCopyEliminationPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0)
        return Result::Error;

    const MicroInstr* cmpInst = findFirstOpcode(builder, MicroInstrOpcode::CmpRegImm);
    if (!cmpInst)
        return Result::Error;

    const MicroInstrOperand* ops = cmpInst->ops(builder.operands());
    if (!ops || ops[0].reg != v1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// Source redefinition blocks propagation: mov v2, v1 ; load v1, 9 ; cmp v2, 1 must keep v2 alive.
SWC_TEST_BEGIN(CopyElim_DoesNotPropagatePastSourceRedefinition)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    constexpr MicroReg v2 = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(5, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(v2, v1, MicroOpBits::B64);
    builder.emitLoadRegImm(v1, ApInt(9, 64), MicroOpBits::B64);
    builder.emitCmpRegImm(v2, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runCopyEliminationPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;

    const MicroInstr* cmpInst = findFirstOpcode(builder, MicroInstrOpcode::CmpRegImm);
    if (!cmpInst)
        return Result::Error;

    const MicroInstrOperand* ops = cmpInst->ops(builder.operands());
    if (!ops || ops[0].reg != v2)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// Replacing v2 by v1 must carry v2's forbidden physical-register set onto v1.
SWC_TEST_BEGIN(CopyElim_TransfersForbiddenPhysRegsToCanonicalSource)
{
    const CallConv&    callConv = CallConv::get(CallConvKind::Swag);
    constexpr MicroReg v1       = MicroReg::virtualIntReg(1);
    constexpr MicroReg v2       = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.addVirtualRegForbiddenPhysReg(v2, callConv.intReturn);
    builder.emitLoadRegImm(v1, ApInt(5, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(v2, v1, MicroOpBits::B64);
    builder.emitCmpRegImm(v2, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runCopyEliminationPass(builder));

    if (!builder.isVirtualRegPhysRegForbidden(v1, callConv.intReturn))
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// Destructive uses must keep the destination register name: mov v2, v1 ; add v2, 1 cannot rewrite the add to v1.
SWC_TEST_BEGIN(CopyElim_DoesNotRewriteUseDefOperand)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    constexpr MicroReg v2 = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(5, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(v2, v1, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v2, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegImm(v2, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runCopyEliminationPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(CopyElim_PropagatesInDominatorOrderWithoutPhis)
{
    constexpr MicroReg source = MicroReg::virtualIntReg(1);
    constexpr MicroReg copy1  = MicroReg::virtualIntReg(2);
    constexpr MicroReg copy2  = MicroReg::virtualIntReg(3);
    constexpr MicroReg orphan = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);
    const auto         body  = builder.createLabel();
    const auto         setup = builder.createLabel();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, setup);
    builder.placeLabel(body);
    builder.emitLoadRegReg(copy1, source, MicroOpBits::B64);
    const auto firstCopy = builder.instructions().lastInstructionRef();
    builder.emitLoadRegReg(copy2, copy1, MicroOpBits::B64);
    const auto secondCopy = builder.instructions().lastInstructionRef();
    builder.emitLoadMemReg(MicroReg::intReg(2), 0, copy2, MicroOpBits::B64);
    const auto store = builder.instructions().lastInstructionRef();
    builder.emitRet();
    builder.placeLabel(setup);
    builder.emitLoadRegImm(source, ApInt(42, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, body);
    // This separate root must not inherit the definition from the first one.
    builder.emitLoadRegReg(orphan, source, MicroOpBits::B64);
    const auto orphanCopy = builder.instructions().lastInstructionRef();
    builder.emitLoadMemReg(MicroReg::intReg(2), 8, orphan, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runCopyEliminationPass(builder));
    if (builder.instructions().ptr(firstCopy) || builder.instructions().ptr(secondCopy))
        return Result::Error;
    if (builder.instructions().ptr(store)->ops(builder.operands())[1].reg != source)
        return Result::Error;
    const auto* unresolved = builder.instructions().ptr(orphanCopy);
    if (!unresolved || unresolved->op != MicroInstrOpcode::LoadRegReg || unresolved->ops(builder.operands())[1].reg != source)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
