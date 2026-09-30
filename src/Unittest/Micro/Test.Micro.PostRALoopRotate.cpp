#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.PostRALoopRotate.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runPostRaLoopRotatePass(MicroBuilder& builder)
    {
        MicroPostRaLoopRotatePass pass;
        MicroPassManager          passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }
}

SWC_TEST_BEGIN(PostRALoopRotate_IndependentHeadersRotate)
{
    MicroBuilder               builder(ctx);
    SmallVector<MicroInstrRef> backEdges;
    SmallVector<MicroLabelRef> headers;
    for (uint32_t i = 0; i < 2; ++i)
    {
        const MicroLabelRef top     = builder.createLabel();
        const MicroLabelRef done    = builder.createLabel();
        const MicroReg      counter = MicroReg::intReg(i);
        headers.push_back(top);
        builder.placeLabel(top);
        builder.emitCmpRegImm(counter, ApInt(10, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
        builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
        backEdges.push_back(builder.instructions().lastInstructionRef());
        builder.placeLabel(done);
    }
    builder.emitRet();

    SWC_RESULT(runPostRaLoopRotatePass(builder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 4)
        return Result::Error;
    for (uint32_t i = 0; i < backEdges.size(); ++i)
    {
        const auto* inst = builder.instructions().ptr(backEdges[i]);
        if (!inst || inst->op != MicroInstrOpcode::JumpCond)
            return Result::Error;
        const auto* ops = inst->ops(builder.operands());
        if (ops[0].cpuCond != MicroCond::Less || ops[2].valueU64 == headers[i].get())
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

// The copied header is bounded: eight instructions ahead of the exit branch
// rotate, nine keep the unconditional back edge.
SWC_TEST_BEGIN(PostRALoopRotate_HeaderRunStopsAtEightInstructions)
{
    constexpr MicroReg counter = MicroReg::intReg(8);
    constexpr MicroReg base    = MicroReg::intReg(9);
    for (const uint32_t connectors : {7u, 8u})
    {
        MicroBuilder        builder(ctx);
        const MicroLabelRef top  = builder.createLabel();
        const MicroLabelRef done = builder.createLabel();
        builder.placeLabel(top);
        for (uint32_t i = 0; i < connectors; ++i)
            builder.emitLoadAddressRegMem(MicroReg::intReg(10 + (i & 3)), base, 8 * i, MicroOpBits::B64);
        builder.emitCmpRegImm(counter, ApInt(10, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
        builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
        const MicroInstrRef backRef = builder.instructions().lastInstructionRef();
        builder.placeLabel(done);
        builder.emitRet();

        SWC_RESULT(runPostRaLoopRotatePass(builder));
        const bool        rotates = connectors == 7;
        const MicroInstr* back    = builder.instructions().ptr(backRef);
        if (!back || back->op != MicroInstrOpcode::JumpCond ||
            back->ops(builder.operands())[0].cpuCond != (rotates ? MicroCond::Less : MicroCond::Unconditional) ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != (rotates ? 2u : 1u) ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAddrRegMem) != (rotates ? 14u : 8u))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_ClonesRelocatedAddressTest)
{
    for (const bool addressConnector : {true, false})
    {
        MicroBuilder        builder(ctx);
        const MicroLabelRef top   = builder.createLabel();
        const MicroLabelRef done  = builder.createLabel();
        constexpr MicroReg  index = MicroReg::intReg(8);
        constexpr MicroReg  next  = MicroReg::intReg(9);
        constexpr MicroReg  bound = MicroReg::intReg(10);
        builder.placeLabel(top);
        if (addressConnector)
            builder.emitLoadAddressAmcRegMem(next, MicroOpBits::B64, index, index, 1, 1, MicroOpBits::B64);
        else
        {
            builder.emitLoadRegReg(next, index, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(next, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        }
        builder.emitLoadRegMem(bound, MicroReg::instructionPointer(), 0, MicroOpBits::B64);
        const MicroInstrRef loadRef = builder.instructions().lastInstructionRef();
        MicroRelocation     relocation;
        relocation.kind           = MicroRelocation::Kind::GlobalZeroAddress;
        relocation.form           = MicroRelocation::Form::Relative32;
        relocation.instructionRef = loadRef;
        relocation.targetAddress  = 0x1000;
        builder.addRelocation(relocation);
        builder.emitCmpRegReg(next, bound, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B64, done);
        builder.emitLoadRegReg(index, next, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
        const MicroInstrRef backRef = builder.instructions().lastInstructionRef();
        builder.placeLabel(done);
        builder.emitRet();

        SWC_RESULT(runPostRaLoopRotatePass(builder));
        const MicroInstr* back = builder.instructions().ptr(backRef);
        if (!back || back->op != MicroInstrOpcode::JumpCond ||
            back->ops(builder.operands())[0].cpuCond != (addressConnector ? MicroCond::Below : MicroCond::Unconditional))
            return Result::Error;
        const auto& relocations = builder.codeRelocations();
        if (relocations.size() != (addressConnector ? 2u : 1u))
            return Result::Error;
        if (addressConnector &&
            (relocations[0].instructionRef == relocations[1].instructionRef ||
             !relocations[0].hasSameTarget(relocations[1]) ||
             Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAddrAmcRegMem) != 2))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_RotatesAcrossAdjacentExitLabelsOnly)
{
    constexpr MicroReg counter = MicroReg::intReg(10);
    constexpr MicroReg value   = MicroReg::intReg(11);
    for (const bool hasInterveningInstruction : {false, true})
    {
        MicroBuilder        builder(ctx);
        const MicroLabelRef top   = builder.createLabel();
        const MicroLabelRef alias = builder.createLabel();
        const MicroLabelRef done  = builder.createLabel();
        builder.placeLabel(top);
        builder.emitCmpRegImm(counter, ApInt(10, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
        builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
        const MicroInstrRef backRef = builder.instructions().lastInstructionRef();
        builder.placeLabel(alias);
        if (hasInterveningInstruction)
            builder.emitLoadRegImm(value, ApInt(7, 64), MicroOpBits::B64);
        builder.placeLabel(done);
        builder.emitRet();

        SWC_RESULT(runPostRaLoopRotatePass(builder));
        const MicroInstr* back = builder.instructions().ptr(backRef);
        if (!back || back->op != MicroInstrOpcode::JumpCond)
            return Result::Error;
        const auto* backOps = back->ops(builder.operands());
        if (backOps[0].cpuCond != (hasInterveningInstruction ? MicroCond::Unconditional : MicroCond::Less) ||
            (backOps[2].valueU64 == top.get()) != hasInterveningInstruction ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != (hasInterveningInstruction ? 1 : 2))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_RotatesThroughExitTrampoline)
{
    constexpr MicroReg counter = MicroReg::intReg(10);
    constexpr MicroReg value   = MicroReg::intReg(11);
    for (const uint32_t kind : {0u, 1u, 2u})
    {
        MicroBuilder        builder(ctx);
        const MicroLabelRef top   = builder.createLabel();
        const MicroLabelRef alias = builder.createLabel();
        const MicroLabelRef other = builder.createLabel();
        const MicroLabelRef done  = builder.createLabel();
        builder.placeLabel(top);
        builder.emitCmpRegImm(counter, ApInt(10, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
        builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
        const MicroInstrRef backRef = builder.instructions().lastInstructionRef();
        builder.placeLabel(alias);
        if (kind == 2)
            builder.emitLoadRegImm(value, ApInt(7, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, kind == 1 ? other : done);
        builder.placeLabel(other);
        builder.emitLoadRegImm(value, ApInt(8, 64), MicroOpBits::B64);
        builder.placeLabel(done);
        builder.emitRet();

        SWC_RESULT(runPostRaLoopRotatePass(builder));
        const MicroInstr* back = builder.instructions().ptr(backRef);
        if (!back || back->op != MicroInstrOpcode::JumpCond)
            return Result::Error;
        const auto* ops = back->ops(builder.operands());
        const bool  rotates = kind == 0;
        if (ops[0].cpuCond != (rotates ? MicroCond::Less : MicroCond::Unconditional) ||
            (ops[2].valueU64 == top.get()) == rotates ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != (rotates ? 2 : 1))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_RotatesLatchConnectors)
{
    constexpr MicroReg counter = MicroReg::intReg(10);
    constexpr MicroReg value   = MicroReg::intReg(8);
    constexpr MicroReg source  = MicroReg::intReg(9);
    for (const uint32_t kind : {0u, 1u, 2u, 3u, 4u})
    {
        MicroBuilder        builder(ctx);
        const MicroLabelRef top  = builder.createLabel();
        const MicroLabelRef done = builder.createLabel();
        builder.placeLabel(top);
        builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitCmpRegImm(counter, ApInt(10, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
        const MicroInstrRef exitRef = builder.instructions().lastInstructionRef();
        if (kind == 3)
            builder.emitOpBinaryRegImm(value, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        else if (kind == 4)
            builder.emitLoadRegMem(value, MicroReg::instructionPointer(), 0, MicroOpBits::B64);
        else if (kind == 2)
            builder.emitLoadRegMem(value, source, 0, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(value, source, MicroOpBits::B64);
        const MicroInstrRef connectorRef = builder.instructions().lastInstructionRef();
        if (kind == 4)
        {
            MicroRelocation relocation;
            relocation.kind           = MicroRelocation::Kind::GlobalInitAddress;
            relocation.form           = MicroRelocation::Form::Relative32;
            relocation.instructionRef = connectorRef;
            relocation.targetAddress  = 0x1000;
            builder.addRelocation(relocation);
        }
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
        const MicroInstrRef backRef = builder.instructions().lastInstructionRef();
        builder.placeLabel(done);
        if (kind == 1)
            builder.emitLoadRegReg(MicroReg::intReg(0), value, MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runPostRaLoopRotatePass(builder));
        const bool backErased = builder.instructions().ptr(backRef) == nullptr;
        if (backErased != (kind != 3))
            return Result::Error;
        const MicroInstr* exit = builder.instructions().ptr(exitRef);
        if (!exit || exit->ops(builder.operands())[0].cpuCond !=
                         (kind == 3 ? MicroCond::GreaterOrEqual : MicroCond::Less))
            return Result::Error;
        const bool stillTargetsExit = exit->ops(builder.operands())[2].valueU64 == done.get();
        if (stillTargetsExit != (kind == 3))
            return Result::Error;
        if (kind == 4 && (builder.codeRelocations().size() != 1 ||
                          builder.codeRelocations()[0].instructionRef == connectorRef ||
                          !builder.instructions().ptr(builder.codeRelocations()[0].instructionRef)))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_ThreadsRepeatedIndexedZeroTestOnlyOnProvenPaths)
{
    constexpr MicroReg base  = MicroReg::intReg(12);
    constexpr MicroReg index = MicroReg::intReg(13);
    constexpr MicroReg other = MicroReg::intReg(14);
    constexpr MicroReg value = MicroReg::intReg(0);
    for (uint32_t mode = 0; mode < 7; ++mode)
    {
        SymbolFunction callee(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        if (mode != 1)
        {
            AttributeList attributes;
            attributes.addRtFlag(RtAttributeFlagsE::ReadOnly);
            callee.setAttributes(ctx, attributes);
        }
        MicroBuilder builder(ctx);
        const auto   probe    = builder.createLabel();
        const auto   empty    = builder.createLabel();
        const auto   match    = builder.createLabel();
        const auto   occupied = builder.createLabel();
        const auto   done     = builder.createLabel();
        const auto emitUsedTest = [&](const MicroReg cellBase) {
            builder.emitCmpRegImm(value, ApInt(0, 8), MicroOpBits::B8);
            const MicroInstrRef old = builder.instructions().lastInstructionRef();
            MicroInstrOperand   ops[7] = {};
            ops[0].reg                 = cellBase;
            ops[1].reg                 = index;
            ops[2].opBits              = MicroOpBits::B8;
            ops[3].opBits              = MicroOpBits::B64;
            ops[4].valueU64            = 1;
            ops[5].valueU64            = 0;
            ops[6].setImmediateValue(ApInt(0, 8));
            const MicroInstrRef result = builder.instructions().insertDerivedBefore(builder.operands(), old, MicroInstrOpcode::CmpAmcImm, ops);
            builder.instructions().erase(old);
            return result;
        };

        emitUsedTest(base);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, empty);
        builder.placeLabel(probe);
        builder.emitCallLocal(&callee, CallConvKind::Swag);
        if (mode == 2)
            builder.emitLoadMemImm(base, 0, ApInt(1, 8), MicroOpBits::B8);
        if (mode == 3)
            builder.emitOpBinaryRegImm(index, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitCmpRegImm(value, ApInt(0, 32), MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, match);
        if (mode == 6)
        {
            const std::array targets{match};
            builder.emitJumpReg(value, targets);
        }
        builder.emitOpBinaryRegImm(index, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        emitUsedTest(base);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, probe);
        builder.placeLabel(empty);
        builder.placeLabel(match);
        const MicroInstrRef repeated = emitUsedTest(mode == 4 ? other : base);
        builder.emitJumpToLabel(mode == 5 ? MicroCond::Equal : MicroCond::NotEqual, MicroOpBits::B32, occupied);
        builder.emitLoadRegImm(value, ApInt(mode == 5 ? 2 : 1, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, done);
        builder.placeLabel(occupied);
        builder.emitLoadRegImm(value, ApInt(mode == 5 ? 1 : 2, 64), MicroOpBits::B64);
        builder.placeLabel(done);
        builder.emitRet();

        SWC_RESULT(runPostRaLoopRotatePass(builder));
        if ((builder.instructions().ptr(repeated) == nullptr) != (mode == 0 || mode == 5))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_FlagOnlyTestsRotateWithUniqueBackEdge)
{
    constexpr MicroReg counter = MicroReg::intReg(0);
    constexpr MicroReg other   = MicroReg::intReg(1);
    for (const MicroInstrOpcode testOp : {MicroInstrOpcode::TestRegReg, MicroInstrOpcode::TestRegImm,
                                          MicroInstrOpcode::TestMemReg, MicroInstrOpcode::TestMemImm})
    {
        for (const bool secondEntry : {false, true})
        {
            MicroBuilder builder(ctx);
            const auto   top  = builder.createLabel();
            const auto   done = builder.createLabel();
            if (secondEntry)
                builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
            builder.placeLabel(top);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B64, done);
            const MicroInstrRef jumpRef    = builder.instructions().lastInstructionRef();
            MicroInstrOperand   testOps[4] = {};
            testOps[0].reg                 = counter;
            switch (testOp)
            {
                case MicroInstrOpcode::TestRegReg:
                    testOps[1].reg    = counter;
                    testOps[2].opBits = MicroOpBits::B64;
                    builder.instructions().insertDerivedBefore(builder.operands(), jumpRef, testOp, std::span(testOps, 3));
                    break;
                case MicroInstrOpcode::TestRegImm:
                    testOps[1].opBits = MicroOpBits::B64;
                    testOps[2].setImmediateValue(ApInt(1, 64));
                    builder.instructions().insertDerivedBefore(builder.operands(), jumpRef, testOp, std::span(testOps, 3));
                    break;
                case MicroInstrOpcode::TestMemReg:
                    testOps[1].reg      = other;
                    testOps[2].opBits   = MicroOpBits::B64;
                    testOps[3].valueU64 = 0;
                    builder.instructions().insertDerivedBefore(builder.operands(), jumpRef, testOp, std::span(testOps, 4));
                    break;
                case MicroInstrOpcode::TestMemImm:
                    testOps[1].opBits   = MicroOpBits::B64;
                    testOps[2].valueU64 = 0;
                    testOps[3].setImmediateValue(ApInt(1, 64));
                    builder.instructions().insertDerivedBefore(builder.operands(), jumpRef, testOp, std::span(testOps, 4));
                    break;
                default:
                    return Result::Error;
            }
            builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
            const MicroInstrRef backRef = builder.instructions().lastInstructionRef();
            builder.placeLabel(done);
            builder.emitRet();

            SWC_RESULT(runPostRaLoopRotatePass(builder));
            if (Backend::Unittest::countOpcode(builder, testOp) != (secondEntry ? 1u : 2u))
                return Result::Error;
            const MicroInstr* back = builder.instructions().ptr(backRef);
            if (!back || back->op != MicroInstrOpcode::JumpCond ||
                back->ops(builder.operands())[0].cpuCond != (secondEntry ? MicroCond::Unconditional : MicroCond::NotEqual))
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_SecondIncomingJumpBlocks)
{
    MicroBuilder        builder(ctx);
    const MicroLabelRef top     = builder.createLabel();
    const MicroLabelRef done    = builder.createLabel();
    constexpr MicroReg  counter = MicroReg::intReg(0);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
    builder.placeLabel(top);
    builder.emitCmpRegImm(counter, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
    builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
    const auto backEdge = builder.instructions().lastInstructionRef();
    builder.placeLabel(done);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopRotatePass(builder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
        return Result::Error;
    const auto* ops = builder.instructions().ptr(backEdge)->ops(builder.operands());
    if (ops[0].cpuCond != MicroCond::Unconditional || ops[2].valueU64 != top.get())
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_ConditionalBackEdgeBlocks)
{
    MicroBuilder        builder(ctx);
    const MicroLabelRef top     = builder.createLabel();
    const MicroLabelRef done    = builder.createLabel();
    constexpr MicroReg  counter = MicroReg::intReg(0);
    builder.placeLabel(top);
    builder.emitCmpRegImm(counter, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
    builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B64, top);
    const auto backEdge = builder.instructions().lastInstructionRef();
    builder.placeLabel(done);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopRotatePass(builder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
        return Result::Error;
    const auto* ops = builder.instructions().ptr(backEdge)->ops(builder.operands());
    if (ops[0].cpuCond != MicroCond::NotZero || ops[2].valueU64 != top.get())
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_PlacesShortComparisonStepOnFallthrough)
{
    for (const uint32_t variant : {0u, 1u, 2u})
    {
        const bool         unitStep = variant != 1;
        MicroBuilder       builder(ctx);
        const auto         header  = builder.createLabel();
        const auto         tie     = builder.createLabel();
        const auto         step    = builder.createLabel();
        const auto         stop    = builder.createLabel();
        constexpr MicroReg counter = MicroReg::intReg(0);
        constexpr MicroReg value   = MicroReg::intReg(1);

        builder.placeLabel(header);
        builder.emitCmpRegReg(counter, value, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B64, tie);
        builder.emitJumpToLabel(MicroCond::Above, MicroOpBits::B64, step);
        const MicroInstrRef secondRef = builder.instructions().lastInstructionRef();
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, stop);
        builder.placeLabel(tie);
        builder.emitCmpRegImm(counter, ApInt(5, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B64, stop);
        if (variant == 2)
        {
            // The cold arm's length does not change the advancing edge.
            for (uint32_t pad = 0; pad < 96; ++pad)
                builder.emitLoadRegImm(MicroReg::intReg(9), ApInt(pad, 64), MicroOpBits::B64);
        }
        builder.placeLabel(step);
        builder.emitOpBinaryRegImm(counter, ApInt(unitStep ? 1 : 2, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, header);
        builder.placeLabel(stop);
        builder.emitRet();

        SWC_RESULT(runPostRaLoopRotatePass(builder));
        const MicroInstr* second = builder.instructions().ptr(secondRef);
        if (!second || second->op != MicroInstrOpcode::JumpCond)
            return Result::Error;
        const auto* secondOps = second->ops(builder.operands());
        if (!secondOps || secondOps[0].cpuCond != (unitStep ? MicroCond::BelowOrEqual : MicroCond::Above) ||
            secondOps[2].valueU64 != (unitStep ? stop.get() : step.get()))
            return Result::Error;

        const auto  nextRef = builder.instructions().findNextInstructionRef(secondRef);
        const auto* next    = builder.instructions().ptr(nextRef);
        if (!next || next->op != (unitStep ? MicroInstrOpcode::Label : MicroInstrOpcode::JumpCond))
            return Result::Error;
        if (unitStep && next->ops(builder.operands())[0].valueU64 != step.get())
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_CountMismatchFallsThroughToNextIteration)
{
    constexpr MicroReg base    = MicroReg::intReg(8);
    constexpr MicroReg counter = MicroReg::intReg(9);
    constexpr MicroReg value   = MicroReg::intReg(10);
    constexpr MicroReg pivot   = MicroReg::intReg(11);
    for (const uint32_t loads : {1u, 2u})
    {
        MicroBuilder        builder(ctx);
        const MicroLabelRef header = builder.createLabel();
        const MicroLabelRef tie    = builder.createLabel();
        const MicroLabelRef step   = builder.createLabel();
        const MicroLabelRef stop   = builder.createLabel();
        builder.placeLabel(header);
        builder.emitLoadAmcRegMem(value, MicroOpBits::B64, base, counter, 8, 0, MicroOpBits::B64);
        if (loads == 2)
            builder.emitLoadAmcRegMem(value, MicroOpBits::B64, base, value, 8, 0, MicroOpBits::B64);
        builder.emitCmpRegReg(value, pivot, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, tie);
        const MicroInstrRef equalRef = builder.instructions().lastInstructionRef();
        builder.emitJumpToLabel(MicroCond::BelowOrEqual, MicroOpBits::B32, stop);
        builder.placeLabel(step);
        builder.emitOpBinaryRegImm(counter, ApInt(1, 64), loads == 1 ? MicroOp::Add : MicroOp::Subtract, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, header);
        const MicroInstrRef backRef = builder.instructions().lastInstructionRef();
        builder.placeLabel(tie);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, step);
        builder.placeLabel(stop);
        builder.emitRet();

        SWC_RESULT(runPostRaLoopRotatePass(builder));
        const MicroInstr*        equal    = builder.instructions().ptr(equalRef);
        const MicroInstrOperand* equalOps = equal ? equal->ops(builder.operands()) : nullptr;
        if (!equal || !equalOps || equalOps[0].cpuCond != MicroCond::NotEqual ||
            equalOps[2].valueU64 == tie.get() || builder.instructions().ptr(backRef))
            return Result::Error;

        uint64_t mismatchId = 0;
        bool     foundEntry = false;
        bool     foundStep  = false;
        for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
        {
            const MicroInstrOperand* ops = it->ops(builder.operands());
            if (it->op == MicroInstrOpcode::JumpCond && ops &&
                ops[0].cpuCond == MicroCond::Unconditional && ops[2].valueU64 == header.get())
                foundEntry = true;
            if (it->op == MicroInstrOpcode::Label && ops && ops[0].valueU64 == equalOps[2].valueU64)
                mismatchId = ops[0].valueU64;
            if (it->op == MicroInstrOpcode::OpBinaryRegImm && ops && ops[0].reg == counter)
                foundStep = true;
        }
        if (!foundEntry || !foundStep || mismatchId == 0)
            return Result::Error;
    }

    MicroBuilder        nonUnit(ctx);
    const MicroLabelRef header = nonUnit.createLabel();
    const MicroLabelRef tie    = nonUnit.createLabel();
    const MicroLabelRef step   = nonUnit.createLabel();
    const MicroLabelRef stop   = nonUnit.createLabel();
    nonUnit.placeLabel(header);
    nonUnit.emitLoadAmcRegMem(value, MicroOpBits::B64, base, counter, 8, 0, MicroOpBits::B64);
    nonUnit.emitCmpRegReg(value, pivot, MicroOpBits::B64);
    nonUnit.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, tie);
    nonUnit.emitJumpToLabel(MicroCond::BelowOrEqual, MicroOpBits::B32, stop);
    nonUnit.placeLabel(step);
    nonUnit.emitOpBinaryRegImm(counter, ApInt(2, 64), MicroOp::Add, MicroOpBits::B64);
    nonUnit.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, header);
    const MicroInstrRef backRef = nonUnit.instructions().lastInstructionRef();
    nonUnit.placeLabel(tie);
    nonUnit.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, step);
    nonUnit.placeLabel(stop);
    nonUnit.emitRet();
    SWC_RESULT(runPostRaLoopRotatePass(nonUnit));
    if (!nonUnit.instructions().ptr(backRef))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
