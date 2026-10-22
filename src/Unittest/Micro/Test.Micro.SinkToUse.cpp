#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/Passes/Pass.SinkToUse.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

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

    SWC_RESULT(Backend::Unittest::runMicroPass<MicroSinkToUsePass>(builder));
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

    SWC_RESULT(Backend::Unittest::runMicroPass<MicroSinkToUsePass>(builder));
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

    SWC_RESULT(Backend::Unittest::runMicroPass<MicroSinkToUsePass>(builder));
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

    SWC_RESULT(Backend::Unittest::runMicroPass<MicroSinkToUsePass>(builder));
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
    SWC_RESULT(Backend::Unittest::runMicroPass<MicroSinkToUsePass>(builder));
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

        SWC_RESULT(Backend::Unittest::runMicroPass<MicroSinkToUsePass>(builder));
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

        SWC_RESULT(Backend::Unittest::runMicroPass<MicroSinkToUsePass>(builder));
        if (builder.instructions().findPreviousInstructionRef(consumer) != rightRef || builder.instructions().findPreviousInstructionRef(rightRef) != leftRef)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SinkToUse_CopiesCrossOnlyIndependentCalls)
{
    for (uint32_t variant = 0; variant < 8; ++variant)
    {
        MicroBuilder   builder(ctx);
        const MicroReg source      = variant == 3 ? MicroReg::intReg(0) : MicroReg::virtualIntReg(1);
        const MicroReg destination = variant == 4 ? MicroReg::intReg(8) : MicroReg::virtualIntReg(2);
        const MicroReg target      = variant == 1 ? source : variant == 2 ? destination
                                                                          : MicroReg::virtualIntReg(3);
        const MicroReg argument    = CallConv::get(CallConvKind::C).intArgRegs[0];
        builder.emitLoadRegImm(source, ApInt(7, 64), MicroOpBits::B64);
        builder.emitLoadRegImm(destination, ApInt(11, 64), MicroOpBits::B64);
        if (variant != 1 && variant != 2)
            builder.emitLoadRegReg(target, MicroReg::intReg(11), MicroOpBits::B64);
        builder.emitLoadRegReg(CallConv::get(CallConvKind::C).intArgRegs[1], source, MicroOpBits::B64);
        builder.emitLoadRegReg(argument, destination, MicroOpBits::B64);
        const auto staging = builder.instructions().lastInstructionRef();
        builder.emitCallReg(target, CallConvKind::C, 3, 0);
        const auto call = builder.instructions().lastInstructionRef();
        if (variant == 6)
            builder.placeLabel(builder.createLabel());
        builder.emitLoadRegReg(destination, source, variant == 5 ? MicroOpBits::B32 : MicroOpBits::B64);
        const auto copy = builder.instructions().lastInstructionRef();
        builder.emitLoadMemReg(MicroReg::intReg(1), 0, destination, MicroOpBits::B64);
        if (variant == 7)
            builder.emitLoadMemReg(MicroReg::intReg(1), 8, source, MicroOpBits::B64);
        builder.emitRet();
        SWC_RESULT(Backend::Unittest::runMicroPass<MicroSinkToUsePass>(builder));
        if (variant)
        {
            if (!builder.instructions().ptr(copy))
                return Result::Error;
            continue;
        }
        if (builder.instructions().ptr(copy))
            return Result::Error;
        const auto  preceding   = builder.instructions().findPreviousInstructionRef(call);
        const auto* instruction = builder.instructions().ptr(preceding);
        if (!instruction || instruction->op != MicroInstrOpcode::LoadRegReg)
            return Result::Error;
        const auto* ops = instruction->ops(builder.operands());
        if (ops[0].reg != destination || ops[1].reg != source)
            return Result::Error;
        bool staged = false;
        for (auto it = builder.instructions().view().begin(); it.current != preceding; ++it)
            staged |= it.current == staging;
        if (!staged)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
