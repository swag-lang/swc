#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.PreRAPeephole.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runPreRaPeepholePass(MicroBuilder& builder)
    {
        MicroPreRAPeepholePass pass;
        MicroPassManager       passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Host;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    uint32_t countOpcode(const MicroBuilder& builder, const MicroInstrOpcode opcode)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                ++count;
        }

        return count;
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

SWC_TEST_BEGIN(PreRAPeephole_ForwardsLoadImmIntoStore)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg imm  = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(base, ApInt(0x1000, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(imm, ApInt(7, 64), MicroOpBits::B32);
    builder.emitLoadMemReg(base, 8, imm, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runPreRaPeepholePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadMemImm) != 1)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 2)
        return Result::Error;

    const MicroInstr* storeInst = findFirstOpcode(builder, MicroInstrOpcode::LoadMemImm);
    if (!storeInst)
        return Result::Error;

    const MicroInstrOperand* ops = storeInst->ops(builder.operands());
    if (!ops || ops[0].reg != base || ops[2].valueU64 != 8 || ops[3].valueU64 != 7)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PreRAPeephole_ForwardsLoadImmIntoCmpMem)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg imm  = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(base, ApInt(0x2000, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(imm, ApInt(42, 64), MicroOpBits::B64);
    builder.emitCmpMemReg(base, 16, imm, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPreRaPeepholePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::CmpMemReg) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::CmpMemImm) != 1)
        return Result::Error;

    const MicroInstr* cmpInst = findFirstOpcode(builder, MicroInstrOpcode::CmpMemImm);
    if (!cmpInst)
        return Result::Error;

    const MicroInstrOperand* ops = cmpInst->ops(builder.operands());
    if (!ops || ops[0].reg != base || ops[2].valueU64 != 16 || ops[3].valueU64 != 42)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PreRAPeephole_ForwardsLoadImmIntoMemBinary)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg imm  = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(base, ApInt(0x3000, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(imm, ApInt(3, 64), MicroOpBits::B64);
    builder.emitOpBinaryMemReg(base, 24, imm, MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPreRaPeepholePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryMemReg) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::OpBinaryMemImm) != 1)
        return Result::Error;

    const MicroInstr* memOp = findFirstOpcode(builder, MicroInstrOpcode::OpBinaryMemImm);
    if (!memOp)
        return Result::Error;

    const MicroInstrOperand* ops = memOp->ops(builder.operands());
    if (!ops || ops[0].reg != base || ops[2].microOp != MicroOp::Add || ops[3].valueU64 != 24 || ops[4].valueU64 != 3)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PreRAPeephole_ForwardsCopyIntoNextUseOnlySlots)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg src  = MicroReg::virtualIntReg(2);
    constexpr MicroReg tmp  = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(base, ApInt(0x4000, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(src, base, 32, MicroOpBits::B64);
    builder.emitLoadRegReg(tmp, src, MicroOpBits::B64);
    builder.emitCmpMemReg(base, 0, tmp, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPreRaPeepholePass(builder));

    const MicroInstr* cmpInst = findFirstOpcode(builder, MicroInstrOpcode::CmpMemReg);
    if (!cmpInst)
        return Result::Error;

    const MicroInstrOperand* ops = cmpInst->ops(builder.operands());
    if (!ops || ops[1].reg != src)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PreRAPeephole_DoesNotRewriteExchangeUseDefConsumer)
{
    constexpr MicroReg left = MicroReg::virtualIntReg(1);
    constexpr MicroReg src  = MicroReg::virtualIntReg(2);
    constexpr MicroReg tmp  = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(left, ApInt(1, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(src, ApInt(2, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(tmp, src, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(left, tmp, MicroOp::Exchange, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPreRaPeepholePass(builder));

    const MicroInstr* exchangeInst = findFirstOpcode(builder, MicroInstrOpcode::OpBinaryRegReg);
    if (!exchangeInst)
        return Result::Error;

    const MicroInstrOperand* ops = exchangeInst->ops(builder.operands());
    if (!ops || ops[1].reg != tmp || ops[3].microOp != MicroOp::Exchange)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
