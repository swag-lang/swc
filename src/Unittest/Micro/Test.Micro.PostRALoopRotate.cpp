#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.PostRALoopRotate.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

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

    SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
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

// The value read for a scan's comparison remains live on its exit. Rotation
// must repeat the load with the comparison, so that exit sees the last cell.
SWC_TEST_BEGIN(PostRALoopRotate_KeepsIndexedHeaderLoadOnTheExit)
{
    constexpr MicroReg base  = MicroReg::intReg(8);
    constexpr MicroReg index = MicroReg::intReg(9);
    constexpr MicroReg value = MicroReg::intReg(10);
    constexpr MicroReg pivot = MicroReg::intReg(11);
    MicroBuilder       builder(ctx);
    const auto         top  = builder.createLabel();
    const auto         done = builder.createLabel();
    builder.placeLabel(top);
    builder.emitLoadAmcRegMem(value, MicroOpBits::B64, base, index, 8, 0, MicroOpBits::B64);
    builder.emitCmpRegReg(value, pivot, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B32, done);
    builder.emitOpBinaryRegImm(index, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, top);
    const auto backRef = builder.instructions().lastInstructionRef();
    builder.placeLabel(done);
    builder.emitLoadMemReg(base, 0, value, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
    const auto* back = builder.instructions().ptr(backRef);
    if (!back || back->op != MicroInstrOpcode::JumpCond || back->ops(builder.operands())[0].cpuCond != MicroCond::Below ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAmcRegMem) != 2 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 2)
        return Result::Error;
    const auto  compareRef = builder.instructions().findPreviousInstructionRef(backRef);
    const auto  loadRef    = builder.instructions().findPreviousInstructionRef(compareRef);
    const auto* load       = builder.instructions().ptr(loadRef);
    if (!load || load->op != MicroInstrOpcode::LoadAmcRegMem || load->ops(builder.operands())[0].reg != value)
        return Result::Error;
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

        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
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

        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
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

        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
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

        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
        const MicroInstr* back = builder.instructions().ptr(backRef);
        if (!back || back->op != MicroInstrOpcode::JumpCond)
            return Result::Error;
        const auto* ops     = back->ops(builder.operands());
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

        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
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
        const auto   probe        = builder.createLabel();
        const auto   empty        = builder.createLabel();
        const auto   match        = builder.createLabel();
        const auto   occupied     = builder.createLabel();
        const auto   done         = builder.createLabel();
        const auto   emitUsedTest = [&](const MicroReg cellBase) {
            builder.emitCmpRegImm(value, ApInt(0, 8), MicroOpBits::B8);
            const MicroInstrRef old    = builder.instructions().lastInstructionRef();
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

        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
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

            SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
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

    SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
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

    SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
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

        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
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

        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
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
    SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(nonUnit));
    if (!nonUnit.instructions().ptr(backRef))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_ThreadsIdenticalRegisterComparisonExits)
{
    for (const auto bits : {MicroOpBits::B8, MicroOpBits::B16, MicroOpBits::B32, MicroOpBits::B64})
    {
        for (const auto condition : {MicroCond::Equal, MicroCond::NotEqual, MicroCond::Below, MicroCond::AboveOrEqual, MicroCond::Less, MicroCond::GreaterOrEqual})
        {
            for (const bool opposite : {false, true})
            {
                const auto   left   = MicroReg::intReg(1);
                const auto   right  = MicroReg::intReg(2);
                const auto   output = MicroReg::intReg(3);
                MicroBuilder builder(ctx);
                const auto   join = builder.createLabel();
                const auto   exit = builder.createLabel();
                MicroCond    inverse;
                if (!MicroPassHelpers::invertLayoutBranchCondition(inverse, condition))
                    return Result::Error;
                builder.emitCmpRegReg(left, right, bits);
                builder.emitJumpToLabel(condition, MicroOpBits::B32, join);
                const auto early = builder.instructions().lastInstructionRef();
                builder.emitLoadMemReg(output, 0, left, bits);
                builder.emitOpBinaryRegImm(left, ApInt(1, 64), MicroOp::Add, bits);
                builder.placeLabel(join);
                builder.emitCmpRegReg(left, right, bits);
                builder.emitJumpToLabel(opposite ? inverse : condition, MicroOpBits::B32, exit);
                builder.emitSetCondReg(MicroReg::intReg(10), MicroCond::Below);
                builder.emitLoadMemReg(output, 8, left, bits);
                builder.placeLabel(exit);
                builder.emitLoadMemReg(output, 16, right, bits);
                builder.emitRet();
                SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
                const auto* jump = builder.instructions().ptr(early);
                if (!jump || jump->op != MicroInstrOpcode::JumpCond)
                    return Result::Error;
                const auto target = jump->ops(builder.operands())[2].valueU64;
                if (target == join.get() || (!opposite && target != exit.get()))
                    return Result::Error;
            }
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_RepeatedRegisterExitKeepsDifferentFlags)
{
    for (uint32_t variant = 0; variant < 4; ++variant)
    {
        const auto   left   = MicroReg::intReg(1);
        const auto   right  = MicroReg::intReg(2);
        const auto   output = MicroReg::intReg(3);
        MicroBuilder builder(ctx);
        const auto   join = builder.createLabel();
        const auto   exit = builder.createLabel();
        builder.emitCmpRegReg(left, right, MicroOpBits::B64);
        if (variant == 3)
            builder.emitOpBinaryRegImm(output, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Greater, MicroOpBits::B32, join);
        const auto early = builder.instructions().lastInstructionRef();
        builder.emitLoadMemReg(output, 0, left, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(left, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.placeLabel(join);
        builder.emitCmpRegReg(variant == 1 ? right : left, variant == 1 ? left : right, variant == 0 ? MicroOpBits::B32 : MicroOpBits::B64);
        builder.emitJumpToLabel(variant == 2 ? MicroCond::Below : MicroCond::Greater, MicroOpBits::B32, exit);
        builder.emitLoadMemReg(output, 8, left, MicroOpBits::B64);
        builder.placeLabel(exit);
        builder.emitSetCondReg(MicroReg::intReg(10), MicroCond::Below);
        builder.emitRet();
        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder));
        const auto* jump = builder.instructions().ptr(early);
        if (!jump || jump->op != MicroInstrOpcode::JumpCond || jump->ops(builder.operands())[2].valueU64 != join.get())
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    void emitBoundedByteScan(MicroBuilder& builder, MicroCond condition, uint32_t variant = 0)
    {
        const auto data   = CallConv::get(CallConvKind::C).intArgRegs[0];
        const auto base   = MicroReg::intReg(3);
        const auto index  = MicroReg::intReg(8);
        const auto limit  = MicroReg::intReg(9);
        const auto header = builder.createLabel();
        const auto exit   = builder.createLabel();
        const auto other  = builder.createLabel();
        builder.emitLoadRegMem(base, data, 0, MicroOpBits::B64);
        builder.emitLoadRegMem(index, data, 8, MicroOpBits::B64);
        builder.emitLoadRegMem(limit, data, 16, MicroOpBits::B64);
        if (variant == 9)
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, header);
        builder.placeLabel(header);
        builder.emitCmpRegReg(index, limit, variant == 3 ? MicroOpBits::B32 : MicroOpBits::B64);
        builder.emitJumpToLabel(variant == 2 ? MicroCond::GreaterOrEqual : MicroCond::AboveOrEqual, MicroOpBits::B32, exit);
        builder.emitCmpRegImm(index, ApInt(128, 8), MicroOpBits::B8);
        const auto        old        = builder.instructions().lastInstructionRef();
        MicroInstrOperand compare[7] = {};
        compare[0].reg               = base;
        compare[1].reg               = index;
        compare[2].opBits            = variant == 4 ? MicroOpBits::B16 : MicroOpBits::B8;
        compare[3].opBits            = MicroOpBits::B64;
        compare[4].valueU64          = variant == 5 ? 2 : 1;
        compare[5].valueU64          = variant == 11 ? std::numeric_limits<int32_t>::max() : 0;
        compare[6].setImmediateValue(ApInt(128, 8));
        builder.instructions().insertDerivedBefore(builder.operands(), old, MicroInstrOpcode::CmpAmcImm, compare);
        builder.instructions().erase(old);
        builder.emitJumpToLabel(condition, MicroOpBits::B32, variant == 8 ? other : exit);
        builder.emitOpBinaryRegImm(index, ApInt(variant == 6 ? 2 : 1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, header);
        builder.placeLabel(exit);
        builder.emitSetCondReg(MicroReg::intReg(10), MicroCond::Equal);
        builder.emitLoadMemReg(data, 24, index, MicroOpBits::B64);
        builder.emitLoadMemReg(data, 32, MicroReg::intReg(10), MicroOpBits::B8);
        if (variant == 7)
            for (const auto reg : CallConv::get(CallConvKind::C).intTransientRegs)
                builder.emitLoadMemReg(data, 64 + reg.index() * 8, reg, MicroOpBits::B64);
        builder.placeLabel(other);
        builder.emitClearReg(MicroReg::intReg(0), MicroOpBits::B64);
        builder.emitRet();
    }
}

SWC_TEST_BEGIN(PostRALoopRotate_UnrollsOnlyProvenBoundedByteScans)
{
    for (uint32_t variant = 0; variant < 13; ++variant)
    {
        MicroBuilder             builder(ctx);
        Runtime::BuildCfgBackend config{};
        config.optimLevel                     = variant == 12 ? Runtime::BuildCfgBackendOptimLevel::O1 : Runtime::BuildCfgBackendOptimLevel::O2;
        config.optimizer.unroll.partialFactor = variant == 10 ? 1 : 0;
        builder.setBackendBuildCfg(config);
        emitBoundedByteScan(builder, variant == 1 ? MicroCond::NotEqual : MicroCond::Equal, variant);
        X64Encoder encoder(ctx);
        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder, &encoder, CallConvKind::C));
        const auto expected = variant < 2 ? 5u : 1u;
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpAmcImm) != expected)
            return Result::Error;
        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder, &encoder, CallConvKind::C));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpAmcImm) != expected)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_BoundedByteScanPreservesIndexAndExitFlags)
{
    for (const auto condition : {MicroCond::Equal, MicroCond::NotEqual})
    {
        for (uint64_t length = 0; length <= 17; ++length)
        {
            for (uint64_t start = 0; start <= length + 1; ++start)
            {
                for (uint64_t match = start; match <= length + 1; ++match)
                {
                    for (const bool optimize : {false, true})
                    {
                        std::array<uint8_t, 64> bytes;
                        bytes.fill(condition == MicroCond::Equal ? 127 : 128);
                        const auto offset = length % 7;
                        if (match < length)
                            bytes[offset + match] = condition == MicroCond::Equal ? 128 : 127;
                        uint64_t                 values[5] = {reinterpret_cast<uint64_t>(bytes.data() + offset), start, length, 0, 0xA5A5A5A5A5A5A500};
                        MicroBuilder             builder(ctx);
                        Runtime::BuildCfgBackend config{};
                        config.optimLevel = Runtime::BuildCfgBackendOptimLevel::O2;
                        builder.setBackendBuildCfg(config);
                        emitBoundedByteScan(builder, condition);
                        if (optimize)
                        {
                            X64Encoder encoder(ctx);
                            SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder, &encoder, CallConvKind::C));
                        }
                        SWC_RESULT(Backend::Unittest::executeMicroCase(ctx, builder, values));
                        const auto expected = start > length ? start : std::min(match, length);
                        const auto equal    = expected == length || (expected < length && condition == MicroCond::Equal);
                        if (values[3] != expected || values[4] != (0xA5A5A5A5A5A5A500 | static_cast<uint64_t>(equal)))
                            return Result::Error;
                    }
                }
            }
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    void emitBoundedPairScan(MicroBuilder& builder, MicroCond condition, bool signedBound, bool reuseLoad, uint32_t variant = 0)
    {
        const auto data   = MicroReg::intReg(2);
        const auto left   = MicroReg::intReg(3);
        const auto index  = MicroReg::intReg(8);
        const auto limit  = MicroReg::intReg(9);
        const auto right  = MicroReg::intReg(10);
        const auto value  = MicroReg::intReg(11);
        const auto spare  = MicroReg::intReg(0);
        const auto header = builder.createLabel();
        const auto exit   = builder.createLabel();
        const auto other  = builder.createLabel();
        builder.emitLoadRegMem(left, data, 0, MicroOpBits::B64);
        builder.emitLoadRegMem(right, data, 8, MicroOpBits::B64);
        builder.emitLoadRegMem(index, data, 16, MicroOpBits::B64);
        builder.emitLoadRegMem(limit, data, 24, MicroOpBits::B64);
        builder.emitLoadRegImm(value, ApInt(0x123456780000005A, 64), MicroOpBits::B64);
        builder.emitLoadRegImm(spare, ApInt(0x13579, 64), MicroOpBits::B64);
        if (variant == 1)
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, header);
        builder.placeLabel(header);
        builder.emitCmpRegReg(index, limit, variant == 2 ? MicroOpBits::B32 : MicroOpBits::B64);
        builder.emitJumpToLabel(signedBound ? MicroCond::GreaterOrEqual : MicroCond::AboveOrEqual, MicroOpBits::B32, exit);
        builder.emitLoadAmcRegMem(variant == 3 ? right : value, variant == 4 ? MicroOpBits::B16 : MicroOpBits::B8, variant == 15 ? index : left, index, variant == 5 ? 2 : 1, variant == 6 ? std::numeric_limits<int32_t>::max() : 0, MicroOpBits::B64);
        const auto        loadRef    = builder.instructions().lastInstructionRef();
        MicroInstrOperand compare[7] = {};
        compare[0].reg               = right;
        compare[1].reg               = index;
        compare[2].reg               = value;
        compare[3].opBits            = MicroOpBits::B64;
        compare[4].opBits            = variant == 7 ? MicroOpBits::B16 : MicroOpBits::B8;
        compare[5].valueU64          = variant == 8 ? 2 : 1;
        compare[6].valueU64          = variant == 9 ? std::numeric_limits<int32_t>::max() : 0;
        builder.emitCmpRegReg(value, index, MicroOpBits::B8);
        const auto insert = builder.instructions().lastInstructionRef();
        builder.instructions().insertDerivedBefore(builder.operands(), insert, MicroInstrOpcode::CmpAmcReg, compare);
        builder.instructions().erase(insert);
        builder.emitJumpToLabel(condition, MicroOpBits::B32, variant == 10 ? other : exit);
        builder.emitOpBinaryRegImm(index, ApInt(variant == 11 ? 2 : 1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, header);
        builder.placeLabel(exit);
        builder.emitLoadMemReg(data, 32, index, MicroOpBits::B64);
        builder.emitSetCondReg(index, MicroCond::Equal);
        builder.emitLoadMemReg(data, 40, index, MicroOpBits::B8);
        builder.emitSetCondReg(index, MicroCond::Below);
        builder.emitLoadMemReg(data, 41, index, MicroOpBits::B8);
        builder.emitSetCondReg(index, MicroCond::Less);
        builder.emitLoadMemReg(data, 42, index, MicroOpBits::B8);
        if (!reuseLoad || variant == 12)
            builder.emitLoadMemReg(data, 48, value, MicroOpBits::B64);
        if (reuseLoad)
            builder.emitLoadMemReg(data, 56, spare, MicroOpBits::B64);
        builder.emitLoadMemReg(data, 64, left, MicroOpBits::B64);
        builder.emitLoadMemReg(data, 72, right, MicroOpBits::B64);
        builder.placeLabel(other);
        builder.emitClearReg(spare, MicroOpBits::B64);
        builder.emitRet();
        if (variant == 16)
        {
            std::array<MicroInstrOperand, 7> packed;
            std::copy_n(builder.instructions().ptr(loadRef)->ops(builder.operands()), 7, packed.begin());
            const auto operandsRef   = builder.operands().append(packed);
            auto*      instruction   = builder.instructions().ptr(loadRef);
            instruction->opsRef      = operandsRef;
            instruction->numOperands = 7;
        }
    }
}

SWC_TEST_BEGIN(PostRALoopRotate_UnrollsOnlyProvenBoundedPairScans)
{
    for (const bool signedBound : {false, true})
        for (const bool reuseLoad : {false, true})
            for (uint32_t variant = 0; variant < 17; ++variant)
            {
                MicroBuilder             builder(ctx);
                Runtime::BuildCfgBackend config{};
                config.optimLevel                     = variant == 13 ? Runtime::BuildCfgBackendOptimLevel::O1 : Runtime::BuildCfgBackendOptimLevel::O2;
                config.optimizer.unroll.partialFactor = variant == 14 ? 1 : 0;
                builder.setBackendBuildCfg(config);
                emitBoundedPairScan(builder, MicroCond::NotEqual, signedBound, reuseLoad, variant);
                X64Encoder encoder(ctx);
                SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder, &encoder, CallConvKind::C));
                const auto expected = variant == 0 || variant == 16 || (variant == 12 && !reuseLoad) ? 5u : 1u;
                if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpAmcReg) != expected)
                    return Result::Error;
                SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder, &encoder, CallConvKind::C));
                if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpAmcReg) != expected)
                    return Result::Error;
            }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_PairScanKeepsAnIndexUsedAsItsLoadBase)
{
    for (const bool reuseLoad : {false, true})
    {
        alignas(16) std::array<uint8_t, 32> left;
        std::array<uint8_t, 32>             right;
        left.fill(127);
        right.fill(128);
        for (size_t index = 0; index < 8; ++index)
            left[2 * index] = 128;
        const auto               first      = reinterpret_cast<uint64_t>(left.data()) / 2;
        uint64_t                 values[10] = {reinterpret_cast<uint64_t>(left.data()), reinterpret_cast<uint64_t>(right.data()) - first, first, first + 8};
        MicroBuilder             builder(ctx);
        Runtime::BuildCfgBackend config{};
        config.optimLevel = Runtime::BuildCfgBackendOptimLevel::O2;
        builder.setBackendBuildCfg(config);
        emitBoundedPairScan(builder, MicroCond::NotEqual, false, reuseLoad, 15);
        X64Encoder encoder(ctx);
        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder, &encoder, CallConvKind::C));
        SWC_RESULT(Backend::Unittest::executeMicroCase(ctx, builder, values));
        if (values[4] != first + 8)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_BoundedPairScanPreservesReadsIndexAndFlags)
{
    for (const bool signedBound : {false, true})
        for (const bool reuseLoad : {false, true})
            for (const auto condition : {MicroCond::Equal, MicroCond::NotEqual})
                for (const uint64_t bias : {0ull, 0x8000000000000000ull, 0x7FFFFFFFFFFFFFE0ull, 0xFFFFFFFFFFFFFFE0ull, 0xFFFFFFFFFFFFFFFCull, 0x7FFFFFFFFFFFFFFCull})
                    for (uint64_t length = 0; length <= 12; ++length)
                        for (uint64_t match = 0; match <= length; ++match)
                        {
                            std::array<uint8_t, 32> left;
                            std::array<uint8_t, 32> right;
                            left.fill(128);
                            right.fill(condition == MicroCond::Equal ? 127 : 128);
                            if (match < length)
                                right[match] = condition == MicroCond::Equal ? 128 : 127;
                            uint64_t reference[10] = {};
                            for (const bool optimize : {false, true})
                            {
                                uint64_t                 values[10] = {reinterpret_cast<uint64_t>(left.data()) - bias, reinterpret_cast<uint64_t>(right.data()) - bias, bias, bias + length};
                                MicroBuilder             builder(ctx);
                                Runtime::BuildCfgBackend config{};
                                config.optimLevel = Runtime::BuildCfgBackendOptimLevel::O2;
                                builder.setBackendBuildCfg(config);
                                emitBoundedPairScan(builder, condition, signedBound, reuseLoad);
                                if (optimize)
                                {
                                    X64Encoder encoder(ctx);
                                    SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder, &encoder, CallConvKind::C));
                                    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpAmcReg) != 5)
                                        return Result::Error;
                                }
                                SWC_RESULT(Backend::Unittest::executeMicroCase(ctx, builder, values));
                                const bool empty = signedBound ? static_cast<int64_t>(bias) >= static_cast<int64_t>(bias + length) : bias >= bias + length;
                                if (values[4] != (empty ? bias : bias + match))
                                    return Result::Error;
                                if (!optimize)
                                    std::copy_n(values, 10, reference);
                                else if (!std::equal(values, values + 10, reference))
                                    return Result::Error;
                            }
                        }
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    void emitScanValueCase(MicroBuilder& builder, uint32_t variant)
    {
        const auto data      = CallConv::get(CallConvKind::C).intArgRegs[0];
        const auto base      = MicroReg::intReg(8);
        const auto index     = MicroReg::intReg(9);
        const auto pivot     = MicroReg::intReg(10);
        const auto value     = variant == 6 ? base : variant == 7 ? index
                                                 : variant == 8   ? pivot
                                                                  : MicroReg::intReg(0);
        const auto flag      = MicroReg::intReg(11);
        const auto threshold = MicroReg::intReg(3);
        const auto header    = builder.createLabel();
        const auto exit      = builder.createLabel();
        const auto skip      = builder.createLabel();
        const auto done      = builder.createLabel();
        const auto other     = builder.createLabel();
        builder.emitLoadRegMem(base, data, 0, MicroOpBits::B64);
        builder.emitLoadRegMem(index, data, 8, MicroOpBits::B64);
        builder.emitLoadRegMem(pivot, data, 16, MicroOpBits::B64);
        builder.emitLoadRegMem(threshold, data, 24, MicroOpBits::B64);
        if (variant == 13)
        {
            builder.emitCmpRegImm(threshold, ApInt(0, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, done);
        }
        builder.placeLabel(header);
        builder.emitLoadAmcRegMem(value, variant == 3 ? MicroOpBits::B32 : MicroOpBits::B64, base, index, 8, 0, variant == 4 ? MicroOpBits::B32 : MicroOpBits::B64);
        builder.emitCmpRegReg(variant == 5 ? pivot : value, variant == 5 ? value : pivot, MicroOpBits::B64);
        builder.emitJumpToLabel((variant == 1 || variant == 18) ? MicroCond::BelowOrEqual : MicroCond::AboveOrEqual, MicroOpBits::B32, exit);
        builder.emitOpBinaryRegImm(index, ApInt(variant == 2 ? 2 : 1, 64), (variant == 1 || variant == 18) ? MicroOp::Subtract : MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, header);
        builder.placeLabel(exit);
        builder.emitSetCondReg(flag, MicroCond::Equal);
        if (variant == 9)
            builder.emitCallReg(flag, CallConvKind::C, 0, 0);
        if (variant == 15)
        {
            builder.emitClearReg(value, MicroOpBits::B64);
            builder.emitRet();
            return;
        }
        builder.emitCmpRegReg(index, threshold, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, skip);
        if (variant == 10)
        {
            builder.emitLoadMemReg(data, 64, value, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, done);
        }
        else if (variant == 11 || variant == 12 || variant == 13)
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, done);
        else
        {
            builder.placeLabel(other);
            builder.emitLoadAmcMemReg(base, index, 8, 0, MicroOpBits::B64, pivot, MicroOpBits::B64);
            if (variant == 14)
                builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, other);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, done);
        }
        builder.placeLabel(skip);
        if (variant == 19)
            builder.emitRet();
        else if (variant == 10)
            builder.emitLoadMemReg(data, 72, value, MicroOpBits::B64);
        else if (variant == 11)
            builder.emitLoadRegImm(value, ApInt(42, 64), MicroOpBits::B64);
        else if (variant == 12)
            builder.emitOpBinaryRegImm(base, ApInt(8, 64), MicroOp::Add, MicroOpBits::B64);
        else if (variant != 13)
            builder.emitClearReg(value, variant >= 17 ? MicroOpBits::B8 : MicroOpBits::B64);
        builder.placeLabel(done);
        builder.emitLoadMemReg(data, 32, value, MicroOpBits::B64);
        builder.emitLoadMemReg(data, 40, index, MicroOpBits::B64);
        builder.emitLoadMemReg(data, 48, flag, MicroOpBits::B8);
        builder.emitRet();
    }
}

SWC_TEST_BEGIN(PostRALoopRotate_SinksOnlyEquivalentScanValues)
{
    for (uint32_t variant = 0; variant < 20; ++variant)
    {
        MicroBuilder             builder(ctx);
        X64Encoder               encoder(ctx);
        Runtime::BuildCfgBackend config{};
        config.optimLevel = variant == 16 ? Runtime::BuildCfgBackendOptimLevel::O1 : Runtime::BuildCfgBackendOptimLevel::O2;
        builder.setBackendBuildCfg(config);
        emitScanValueCase(builder, variant);
        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder, &encoder, CallConvKind::C));
        const bool changed = Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpAmcReg) != 0;
        if (changed != (variant <= 1))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_PartialScanValueKillRetainsUpperBits)
{
    for (const bool optimize : {false, true})
    {
        std::array<uint64_t, 2>  items     = {0, std::numeric_limits<uint64_t>::max()};
        uint64_t                 values[7] = {reinterpret_cast<uint64_t>(items.data()), 0, 50, 1, 0, 0, 0};
        MicroBuilder             builder(ctx);
        Runtime::BuildCfgBackend config{};
        config.optimLevel = Runtime::BuildCfgBackendOptimLevel::O2;
        builder.setBackendBuildCfg(config);
        emitScanValueCase(builder, 17);
        if (optimize)
        {
            X64Encoder encoder(ctx);
            SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder, &encoder, CallConvKind::C));
            if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpAmcReg))
                return Result::Error;
        }
        SWC_RESULT(Backend::Unittest::executeMicroCase(ctx, builder, values));
        if (values[4] != 0xFFFFFFFFFFFFFF00 || values[5] != 1 || values[6] != 0 || items[1] != std::numeric_limits<uint64_t>::max())
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_ScanValuePreservesFlagsAndAliasedStores)
{
    for (uint64_t length = 1; length <= 9; ++length)
    {
        for (uint64_t start = 0; start < length; ++start)
        {
            for (const uint64_t pivot : {uint64_t{0}, uint64_t{1}, uint64_t{25}, uint64_t{50}, uint64_t{96}, uint64_t{100}, std::numeric_limits<uint64_t>::max()})
            {
                for (const bool descending : {false, true})
                {
                    for (const bool skip : {false, true})
                    {
                        for (const bool optimize : {false, true})
                        {
                            std::array<uint64_t, 12> items;
                            for (uint64_t i = 0; i < items.size(); ++i)
                                items[i] = (i * 73 + 11) % 97;
                            items[descending ? 0 : length - 1] = descending ? 0 : std::numeric_limits<uint64_t>::max();
                            auto     expected                  = items;
                            uint64_t stop                      = start;
                            while (descending ? items[stop] > pivot : items[stop] < pivot)
                                stop = descending ? stop - 1 : stop + 1;
                            const auto observed = items[stop];
                            if (!skip)
                                expected[stop] = pivot;
                            uint64_t                 values[7] = {reinterpret_cast<uint64_t>(items.data()), start, pivot, skip ? stop : std::numeric_limits<uint64_t>::max(), 0xBAD, 0xBAD, 0xA5A5A5A5A5A5A500};
                            MicroBuilder             builder(ctx);
                            Runtime::BuildCfgBackend config{};
                            config.optimLevel = Runtime::BuildCfgBackendOptimLevel::O2;
                            builder.setBackendBuildCfg(config);
                            emitScanValueCase(builder, descending ? 1 : 0);
                            if (optimize)
                            {
                                X64Encoder encoder(ctx);
                                SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaLoopRotatePass>(builder, &encoder, CallConvKind::C));
                                if (!Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpAmcReg))
                                    return Result::Error;
                            }
                            SWC_RESULT(Backend::Unittest::executeMicroCase(ctx, builder, values));
                            if (items != expected || values[4] != (skip ? 0 : observed) || values[5] != stop || values[6] != (0xA5A5A5A5A5A5A500 | static_cast<uint64_t>(observed == pivot)))
                                return Result::Error;
                        }
                    }
                }
            }
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
