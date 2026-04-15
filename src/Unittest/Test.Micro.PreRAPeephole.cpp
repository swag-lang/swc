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
        MicroPreRaPeepholePass pass;
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

    const MicroInstr* findNthOpcode(const MicroBuilder& builder, const MicroInstrOpcode opcode, uint32_t nth)
    {
        uint32_t current = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != opcode)
                continue;
            if (current == nth)
                return &inst;
            ++current;
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

SWC_TEST_BEGIN(PreRAPeephole_ForwardsLoadImmIntoAmcStore)
{
    constexpr MicroReg base  = MicroReg::virtualIntReg(1);
    constexpr MicroReg idx   = MicroReg::virtualIntReg(2);
    constexpr MicroReg value = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(base, ApInt(0x1000, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(idx, ApInt(2, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(value, ApInt(7, 64), MicroOpBits::B32);
    builder.emitLoadAmcMemReg(base, idx, 4, 8, MicroOpBits::B64, value, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runPreRaPeepholePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadAmcMemReg) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadAmcMemImm) != 1)
        return Result::Error;

    const MicroInstr* storeInst = findFirstOpcode(builder, MicroInstrOpcode::LoadAmcMemImm);
    if (!storeInst)
        return Result::Error;

    const MicroInstrOperand* ops = storeInst->ops(builder.operands());
    if (!ops || ops[0].reg != base || ops[1].reg != idx || ops[5].valueU64 != 4 || ops[6].valueU64 != 8 || ops[7].valueU64 != 7)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PreRAPeephole_ForwardsClearRegIntoImmediateCompare)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg zero = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(base, ApInt(0x1800, 64), MicroOpBits::B64);
    builder.emitClearReg(zero, MicroOpBits::B64);
    builder.emitCmpMemReg(base, 12, zero, MicroOpBits::B64);
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
    if (!ops || ops[0].reg != base || ops[2].valueU64 != 12 || ops[3].valueU64 != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PreRAPeephole_FoldsExtendOfImmediate)
{
    constexpr MicroReg src = MicroReg::virtualIntReg(1);
    constexpr MicroReg dst = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(src, ApInt(0xFF, 64), MicroOpBits::B8);
    builder.emitLoadSignedExtendRegReg(dst, src, MicroOpBits::B64, MicroOpBits::B8);
    builder.emitRet();

    SWC_RESULT(runPreRaPeepholePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadSignedExtRegReg) != 0)
        return Result::Error;

    const MicroInstr* rewritten = findNthOpcode(builder, MicroInstrOpcode::LoadRegImm, 1);
    if (!rewritten)
        return Result::Error;

    const MicroInstrOperand* ops = rewritten->ops(builder.operands());
    if (!ops || ops[0].reg != dst || ops[1].opBits != MicroOpBits::B64 || ops[2].valueU64 != 0xFFFFFFFFFFFFFFFFULL)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PreRAPeephole_FoldsPointerImmediateIntoAddress)
{
    constexpr MicroReg ptr = MicroReg::virtualIntReg(1);
    constexpr MicroReg dst = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegPtrImm(ptr, 0x4000);
    builder.emitLoadAddressRegMem(dst, ptr, 0x28, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPreRaPeepholePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadAddrRegMem) != 0)
        return Result::Error;

    const MicroInstr* rewritten = findNthOpcode(builder, MicroInstrOpcode::LoadRegPtrImm, 1);
    if (!rewritten)
        return Result::Error;

    const MicroInstrOperand* ops = rewritten->ops(builder.operands());
    if (!ops || ops[0].reg != dst || ops[2].valueU64 != 0x4028)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PreRAPeephole_FoldsAmcIndexImmediateIntoSimpleLoad)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg idx  = MicroReg::virtualIntReg(2);
    constexpr MicroReg dst  = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(base, ApInt(0x5000, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(idx, ApInt(3, 64), MicroOpBits::B64);
    builder.emitLoadAmcRegMem(dst, MicroOpBits::B32, base, idx, 8, 4, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runPreRaPeepholePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadAmcRegMem) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;

    const MicroInstr* loadInst = findFirstOpcode(builder, MicroInstrOpcode::LoadRegMem);
    if (!loadInst)
        return Result::Error;

    const MicroInstrOperand* ops = loadInst->ops(builder.operands());
    if (!ops || ops[0].reg != dst || ops[1].reg != base || ops[2].opBits != MicroOpBits::B32 || ops[3].valueU64 != 28)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PreRAPeephole_FoldsAddressBaseIntoAmcStore)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg idx  = MicroReg::virtualIntReg(2);
    constexpr MicroReg addr = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(base, ApInt(0x6000, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(idx, base, 0, MicroOpBits::B64);
    builder.emitLoadAddressRegMem(addr, base, 16, MicroOpBits::B64);
    builder.emitLoadAmcMemImm(addr, idx, 4, 8, MicroOpBits::B64, ApInt(9, 64), MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runPreRaPeepholePass(builder));

    const MicroInstr* storeInst = findFirstOpcode(builder, MicroInstrOpcode::LoadAmcMemImm);
    if (!storeInst)
        return Result::Error;

    const MicroInstrOperand* ops = storeInst->ops(builder.operands());
    if (!ops || ops[0].reg != base || ops[1].reg != idx || ops[6].valueU64 != 24 || ops[7].valueU64 != 9)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PreRAPeephole_FoldsAmcAddressIntoStore)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(1);
    constexpr MicroReg idx  = MicroReg::virtualIntReg(2);
    constexpr MicroReg src  = MicroReg::virtualIntReg(3);
    constexpr MicroReg addr = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(base, ApInt(0x7000, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(idx, base, 0, MicroOpBits::B64);
    builder.emitLoadRegMem(src, base, 8, MicroOpBits::B64);
    builder.emitLoadAddressAmcRegMem(addr, MicroOpBits::B64, base, idx, 4, 8, MicroOpBits::B64);
    builder.emitLoadMemReg(addr, 16, src, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPreRaPeepholePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadAmcMemReg) != 1)
        return Result::Error;

    const MicroInstr* storeInst = findFirstOpcode(builder, MicroInstrOpcode::LoadAmcMemReg);
    if (!storeInst)
        return Result::Error;

    const MicroInstrOperand* ops = storeInst->ops(builder.operands());
    if (!ops || ops[0].reg != base || ops[1].reg != idx || ops[2].reg != src || ops[5].valueU64 != 4 || ops[6].valueU64 != 24)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
