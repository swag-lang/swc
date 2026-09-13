#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.SinkToUse.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runSinkToUsePass(MicroBuilder& builder)
    {
        MicroSinkToUsePass pass;
        MicroPassManager   passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }
}

SWC_TEST_BEGIN(SinkToUse_MovesDefinitionToItsConsumer)
{
    constexpr MicroReg value  = MicroReg::virtualIntReg(1);
    constexpr MicroReg other  = MicroReg::virtualIntReg(2);
    constexpr MicroReg result = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(value, ApInt(7, 64), MicroOpBits::B64);
    const auto original = builder.instructions().lastInstructionRef();
    builder.emitLoadRegImm(other, ApInt(2, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(other, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegReg(result, value, MicroOpBits::B64);
    const auto consumer = builder.instructions().lastInstructionRef();
    builder.emitRet();

    SWC_RESULT(runSinkToUsePass(builder));
    if (builder.instructions().ptr(original))
        return Result::Error;
    const auto  precedingRef = builder.instructions().findPreviousInstructionRef(consumer);
    const auto* preceding    = builder.instructions().ptr(precedingRef);
    if (!preceding || preceding->op != MicroInstrOpcode::LoadRegImm || preceding->ops(builder.operands())[0].reg != value)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SinkToUse_LoadCannotCrossBaseRedefinition)
{
    constexpr MicroReg base   = MicroReg::virtualIntReg(1);
    constexpr MicroReg value  = MicroReg::virtualIntReg(2);
    constexpr MicroReg result = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(base, ApInt(4096, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(value, base, 0, MicroOpBits::B64);
    const auto load = builder.instructions().lastInstructionRef();
    builder.emitLoadRegImm(base, ApInt(8192, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(result, value, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runSinkToUsePass(builder));
    if (!builder.instructions().ptr(load))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SinkToUse_LoadCannotCrossMemoryWrite)
{
    constexpr MicroReg base   = MicroReg::virtualIntReg(1);
    constexpr MicroReg value  = MicroReg::virtualIntReg(2);
    constexpr MicroReg result = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(base, ApInt(4096, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(value, base, 0, MicroOpBits::B64);
    const auto load = builder.instructions().lastInstructionRef();
    builder.emitLoadMemReg(base, 0, base, MicroOpBits::B64);
    builder.emitLoadRegReg(result, value, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runSinkToUsePass(builder));
    if (!builder.instructions().ptr(load))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SinkToUse_ChainKeepsProducerOrderAcrossRounds)
{
    constexpr MicroReg first  = MicroReg::virtualIntReg(1);
    constexpr MicroReg second = MicroReg::virtualIntReg(2);
    constexpr MicroReg third  = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);
    builder.emitLoadRegImm(first, ApInt(7, 64), MicroOpBits::B64);
    builder.emitNop();
    builder.emitLoadRegReg(second, first, MicroOpBits::B64);
    builder.emitNop();
    builder.emitLoadRegReg(third, second, MicroOpBits::B64);
    builder.emitNop();
    builder.emitLoadMemReg(MicroReg::intReg(2), 0, third, MicroOpBits::B64);
    const auto store = builder.instructions().lastInstructionRef();
    builder.emitRet();

    SWC_RESULT(runSinkToUsePass(builder));
    auto previousRef = store;
    for (const auto reg : {third, second, first})
    {
        previousRef      = builder.instructions().findPreviousInstructionRef(previousRef);
        const auto* inst = builder.instructions().ptr(previousRef);
        if (!inst)
            return Result::Error;
        const auto* ops = inst->ops(builder.operands());
        if (!ops || ops[0].reg != reg)
            return Result::Error;
        if (reg == first)
        {
            if (inst->op != MicroInstrOpcode::LoadRegImm || ops[2].valueU64 != 7)
                return Result::Error;
        }
        else if (inst->op != MicroInstrOpcode::LoadRegReg || ops[1].reg != (reg == third ? second : first))
            return Result::Error;
    }

    std::vector<MicroInstrRef> settledRefs;
    for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
        settledRefs.push_back(it.current);
    SWC_RESULT(runSinkToUsePass(builder));
    size_t index = 0;
    for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
    {
        if (index >= settledRefs.size() || it.current != settledRefs[index++])
            return Result::Error;
    }
    return index == settledRefs.size() ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SinkToUse_OperandClusterKeepsStableOrder)
{
    constexpr MicroReg left  = MicroReg::virtualIntReg(1);
    constexpr MicroReg right = MicroReg::virtualIntReg(2);
    for (const bool hasGap : {false, true})
    {
        MicroBuilder builder(ctx);
        builder.emitLoadRegImm(left, ApInt(7, 64), MicroOpBits::B64);
        const auto originalLeft = builder.instructions().lastInstructionRef();
        builder.emitLoadRegImm(right, ApInt(8, 64), MicroOpBits::B64);
        const auto originalRight = builder.instructions().lastInstructionRef();
        if (hasGap)
            builder.emitNop();
        builder.emitCmpRegReg(left, right, MicroOpBits::B64);
        const auto consumer = builder.instructions().lastInstructionRef();
        builder.emitRet();

        SWC_RESULT(runSinkToUsePass(builder));
        const auto  rightRef  = builder.instructions().findPreviousInstructionRef(consumer);
        const auto  leftRef   = builder.instructions().findPreviousInstructionRef(rightRef);
        const auto* leftInst  = builder.instructions().ptr(leftRef);
        const auto* rightInst = builder.instructions().ptr(rightRef);
        if (!leftInst || !rightInst || leftInst->op != MicroInstrOpcode::LoadRegImm || rightInst->op != MicroInstrOpcode::LoadRegImm)
            return Result::Error;
        if (leftInst->ops(builder.operands())[0].reg != left || rightInst->ops(builder.operands())[0].reg != right)
            return Result::Error;
        if (!hasGap && (leftRef != originalLeft || rightRef != originalRight))
            return Result::Error;

        SWC_RESULT(runSinkToUsePass(builder));
        if (builder.instructions().findPreviousInstructionRef(consumer) != rightRef || builder.instructions().findPreviousInstructionRef(rightRef) != leftRef)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
