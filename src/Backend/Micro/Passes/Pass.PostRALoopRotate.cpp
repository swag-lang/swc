#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRALoopRotate.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/SmallVector.h"
#include "Support/Report/Assert.h"

// Post-RA loop layout. See the header for why it runs here.
//
//   H:                            H:
//     cmp  A, B                     cmp  A, B          ; now entry only
//     jcc  EXIT               ->    jcc  EXIT
//     ...body...                  H2:
//     jmp  H                        ...body...
//   EXIT:                           cmp  A, B
//                                   jcc(~cc) H2
//                                 EXIT:
//
// The header test stays where it is and a fresh label opens behind it; only the
// back edge moves, from the top of the test to the top of the body. What each
// iteration executes is unchanged - [cmp][body][jmp][cmp] becomes
// [cmp][body][cmp] - so a test reading memory the body writes still reads it at
// the same point, and the flags each jump consumes are still defined
// immediately above it. A `continue` aimed at H keeps working too: it re-runs
// the test and falls into H2, exactly as before.
//
// The allocator may leave register moves and frame traffic between the label
// and the jump: split connectors before the compare, exit-edge connectors
// between the compare and the jump. They are part of the test. The whole run
// from the label to the jump is what gets copied to the back edge, so each
// iteration still executes it once, at the same point.

SWC_BEGIN_NAMESPACE();

namespace
{
    bool tryGetLabelId(uint32_t& outLabelId, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        outLabelId = 0;
        if (inst.op != MicroInstrOpcode::Label || !ops || ops[0].valueU64 > std::numeric_limits<uint32_t>::max())
            return false;

        outLabelId = static_cast<uint32_t>(ops[0].valueU64);
        return true;
    }

    bool tryGetJumpTargetLabelId(uint32_t& outLabelId, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        outLabelId = 0;
        if (inst.op != MicroInstrOpcode::JumpCond || !ops || ops[2].valueU64 > std::numeric_limits<uint32_t>::max())
            return false;

        outLabelId = static_cast<uint32_t>(ops[2].valueU64);
        return true;
    }

    // Compare and test instructions define only flags. Copying an arithmetic
    // instruction would also copy its value definition.
    bool isDuplicableTest(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::CmpRegReg:
            case MicroInstrOpcode::CmpRegImm:
            case MicroInstrOpcode::CmpMemImm:
            case MicroInstrOpcode::CmpMemReg:
            case MicroInstrOpcode::CmpAmcImm:
            case MicroInstrOpcode::CmpAmcReg:
            case MicroInstrOpcode::TestRegReg:
            case MicroInstrOpcode::TestRegImm:
            case MicroInstrOpcode::TestMemReg:
            case MicroInstrOpcode::TestMemImm:
                return true;
            default:
                return false;
        }
    }

    bool invertCondition(const MicroCond cond, MicroCond& outInverted)
    {
        switch (cond)
        {
            case MicroCond::Equal: outInverted = MicroCond::NotEqual; return true;
            case MicroCond::NotEqual: outInverted = MicroCond::Equal; return true;
            case MicroCond::Zero: outInverted = MicroCond::NotZero; return true;
            case MicroCond::NotZero: outInverted = MicroCond::Zero; return true;
            case MicroCond::Below: outInverted = MicroCond::AboveOrEqual; return true;
            case MicroCond::AboveOrEqual: outInverted = MicroCond::Below; return true;
            case MicroCond::BelowOrEqual: outInverted = MicroCond::Above; return true;
            case MicroCond::Above: outInverted = MicroCond::BelowOrEqual; return true;
            case MicroCond::Less: outInverted = MicroCond::GreaterOrEqual; return true;
            case MicroCond::GreaterOrEqual: outInverted = MicroCond::Less; return true;
            case MicroCond::LessOrEqual: outInverted = MicroCond::Greater; return true;
            case MicroCond::Greater: outInverted = MicroCond::LessOrEqual; return true;
            default: return false;
        }
    }

    // A connector the allocator places around the test: a register move or
    // frame traffic, flag-neutral, so the compare still feeds the jump.
    bool isDuplicableConnector(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadMemReg:
                return true;
            default:
                return false;
        }
    }

    // A header carrying more than this around its compare is not worth
    // duplicating for the one jump the rotation removes.
    constexpr uint32_t K_MAX_TEST_RUN = 8;

    struct Rotation
    {
        // Ordinals into the listing: [testBegin, testEnd) is the test run,
        // the compare and its connectors, copied to the back edge.
        uint32_t      testBegin    = 0;
        uint32_t      testEnd      = 0;
        MicroInstrRef jccRef       = MicroInstrRef::invalid();
        MicroInstrRef bodyFirstRef = MicroInstrRef::invalid();
        MicroInstrRef backRef      = MicroInstrRef::invalid();
        MicroCond     inverted     = MicroCond::Unconditional;
    };

    // Put a short loop step on the fall-through path of a two-way comparison:
    //
    //   je T; ja P; jmp S; T: ...; P: inc i; jmp H; S:
    //       ->
    //   je T; jbe S; P: inc i; jmp H; T: ...; jmp P; S:
    //
    // The unequal advancing path saves one executed jump. Moving the existing
    // step, rather than cloning it, keeps code size and incoming edges stable.
    // This is post-RA so block layout cannot change register assignment.
    bool placeShortLoopStep(MicroPassContext& context, const std::vector<MicroInstrRef>& order)
    {
        MicroStorage& storage = *context.instructions;
        MicroOperandStorage& operands = *context.operands;
        const auto findLabel = [&](const uint64_t id) {
            for (uint32_t index = 0; index < order.size(); ++index)
            {
                const MicroInstr* inst = storage.ptr(order[index]);
                if (inst && inst->op == MicroInstrOpcode::Label && inst->ops(operands)[0].valueU64 == id)
                    return index;
            }
            return static_cast<uint32_t>(order.size());
        };

        for (uint32_t ordinal = 0; ordinal + 4 < order.size(); ++ordinal)
        {
            const MicroInstrRef firstRef = order[ordinal];
            const MicroInstrRef secondRef = order[ordinal + 1];
            const MicroInstrRef skipRef = order[ordinal + 2];
            const MicroInstrRef tieRef = order[ordinal + 3];
            const MicroInstr* first = storage.ptr(firstRef);
            const MicroInstr* second = storage.ptr(secondRef);
            const MicroInstr* skip = storage.ptr(skipRef);
            const MicroInstr* tie = storage.ptr(tieRef);
            if (!first || !second || !skip || !tie ||
                first->op != MicroInstrOpcode::JumpCond || second->op != MicroInstrOpcode::JumpCond ||
                skip->op != MicroInstrOpcode::JumpCond || tie->op != MicroInstrOpcode::Label ||
                first->numOperands < 3 || second->numOperands < 3 || skip->numOperands < 3)
                continue;
            const auto* firstOps = first->ops(operands);
            const auto* secondOps = second->ops(operands);
            const auto* skipOps = skip->ops(operands);
            const auto* tieOps = tie->ops(operands);
            if (!firstOps || !secondOps || !skipOps || !tieOps ||
                firstOps[0].cpuCond == MicroCond::Unconditional ||
                secondOps[0].cpuCond == MicroCond::Unconditional ||
                skipOps[0].cpuCond != MicroCond::Unconditional ||
                firstOps[2].valueU64 != tieOps[0].valueU64)
                continue;
            MicroCond inverted = MicroCond::Unconditional;
            if (!invertCondition(secondOps[0].cpuCond, inverted))
                continue;

            const uint32_t stepOrdinal = findLabel(secondOps[2].valueU64);
            if (stepOrdinal <= ordinal + 4 ||
                stepOrdinal - ordinal > 80 || stepOrdinal + 3 >= order.size())
                continue;
            const MicroInstrRef stepLabelRef = order[stepOrdinal];
            const MicroInstrRef updateRef = order[stepOrdinal + 1];
            const MicroInstrRef backRef = order[stepOrdinal + 2];
            const MicroInstr* update = storage.ptr(updateRef);
            const MicroInstr* back = storage.ptr(backRef);
            const MicroInstr* stop = storage.ptr(order[stepOrdinal + 3]);
            if (!update || !back || !stop ||
                update->op != MicroInstrOpcode::OpBinaryRegImm || back->op != MicroInstrOpcode::JumpCond ||
                stop->op != MicroInstrOpcode::Label || update->numOperands < 4 || back->numOperands < 3)
                continue;
            const auto* updateOps = update->ops(operands);
            const auto* backOps = back->ops(operands);
            const auto* stopOps = stop->ops(operands);
            const MicroInstr* beforeStep = storage.ptr(order[stepOrdinal - 1]);
            if (!updateOps || !backOps || !stopOps || !beforeStep ||
                (updateOps[2].microOp != MicroOp::Add && updateOps[2].microOp != MicroOp::Subtract) ||
                updateOps[1].opBits != MicroOpBits::B64 || updateOps[3].valueU64 != 1 ||
                backOps[0].cpuCond != MicroCond::Unconditional ||
                skipOps[2].valueU64 != stopOps[0].valueU64 ||
                beforeStep->op == MicroInstrOpcode::Ret ||
                (beforeStep->op == MicroInstrOpcode::JumpCond &&
                 beforeStep->ops(operands)[0].cpuCond == MicroCond::Unconditional))
                continue;
            if (findLabel(backOps[2].valueU64) >= ordinal)
                continue;

            // Capture operands before insertions can grow their storage.
            std::array<MicroInstrOperand, 3> rewritten = {secondOps[0], secondOps[1], secondOps[2]};
            rewritten[0].cpuCond = inverted;
            rewritten[2].valueU64 = skipOps[2].valueU64;
            std::array<MicroInstrOperand, 3> jumpToStep = {backOps[0], backOps[1], backOps[2]};
            jumpToStep[2].valueU64 = secondOps[2].valueU64;
            std::array<MicroInstrOperand, 4> updateCopy = {updateOps[0], updateOps[1], updateOps[2], updateOps[3]};
            const MicroInstrOperand stepLabelCopy = storage.ptr(stepLabelRef)->ops(operands)[0];
            std::array<MicroInstrOperand, 3> backCopy = {backOps[0], backOps[1], backOps[2]};
            const MicroInstrOpcode updateOpcode = update->op;
            const MicroInstrOpcode backOpcode = back->op;

            storage.insertDerivedBefore(operands, tieRef, MicroInstrOpcode::Label, std::span(&stepLabelCopy, 1));
            storage.insertDerivedBefore(operands, tieRef, updateOpcode, updateCopy);
            storage.insertDerivedBefore(operands, tieRef, backOpcode, backCopy);
            storage.insertDerivedBefore(operands, order[stepOrdinal + 3], MicroInstrOpcode::JumpCond, jumpToStep);
            MicroInstr* rewrittenSecond = storage.ptr(secondRef);
            MicroInstrOperand* rewrittenOps = rewrittenSecond->ops(operands);
            for (uint32_t i = 0; i < 3; ++i)
                rewrittenOps[i] = rewritten[i];
            storage.erase(skipRef);
            storage.erase(stepLabelRef);
            storage.erase(updateRef);
            storage.erase(backRef);
            context.builder->invalidateControlFlowGraph();
            context.passChanged = true;
            return true;
        }
        return false;
    }
}

Result MicroPostRaLoopRotatePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    if (!context.builder)
        return Result::Continue;

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;

    // Recognition does not mutate the listing. Index all incoming jumps once;
    // every header can then check its unique back edge without rescanning the function.
    struct JumpTarget
    {
        uint32_t count   = 0;
        uint32_t ordinal = 0;
    };
    std::unordered_map<uint32_t, JumpTarget> jumpsByTarget;
    std::vector<MicroInstrRef>               order;
    order.reserve(storage.count());
    for (auto it = storage.view().begin(), endIt = storage.view().end(); it != endIt; ++it)
    {
        const auto ordinal = static_cast<uint32_t>(order.size());
        order.push_back(it.current);
        uint32_t target = 0;
        if (!tryGetJumpTargetLabelId(target, *it, it->ops(operands)))
            continue;
        auto& incoming = jumpsByTarget[target];
        ++incoming.count;
        incoming.ordinal = ordinal;
    }

    if (placeShortLoopStep(context, order))
        return Result::Continue;

    // Every rotation needs an incoming jump to its header.
    if (jumpsByTarget.empty())
        return Result::Continue;

    // Copying an instruction that carries a relocation would need the
    // relocation cloned onto both copies; no test shape observed here does, so
    // such a header is left alone rather than handled.
    std::unordered_set<uint32_t> relocatedInstructions;
    for (const MicroRelocation& reloc : context.builder->codeRelocations())
    {
        if (reloc.instructionRef.isValid())
            relocatedInstructions.insert(reloc.instructionRef.get());
    }

    SmallVector<Rotation> rotations;

    for (uint32_t ordinal = 0; ordinal + 3 < order.size(); ++ordinal)
    {
        const MicroInstr* labelInst = storage.ptr(order[ordinal]);
        if (!labelInst)
            continue;
        uint32_t labelId = 0;
        if (!tryGetLabelId(labelId, *labelInst, labelInst->ops(operands)))
            continue;

        // A header without one incoming jump cannot rotate, regardless of
        // its test run. The incoming-jump index stays fixed during recognition.
        const auto incoming = jumpsByTarget.find(labelId);
        if (incoming == jumpsByTarget.end() || incoming->second.count != 1)
            continue;

        // The test run: one duplicable compare, possibly surrounded by
        // connectors, closed by the conditional jump.
        const uint32_t testBegin = ordinal + 1;
        uint32_t       testEnd   = testBegin;
        bool           haveTest  = false;
        bool           closed    = false;
        for (; testEnd < order.size() && testEnd - testBegin <= K_MAX_TEST_RUN; ++testEnd)
        {
            const MicroInstr* testInst = storage.ptr(order[testEnd]);
            if (!testInst)
                break;
            if (testInst->op == MicroInstrOpcode::JumpCond)
            {
                closed = haveTest;
                break;
            }
            if (relocatedInstructions.contains(order[testEnd].get()))
                break;
            if (isDuplicableTest(*testInst))
            {
                if (haveTest)
                    break;
                haveTest = true;
            }
            else if (!isDuplicableConnector(*testInst))
            {
                break;
            }
        }
        if (!closed || testEnd + 1 >= order.size())
            continue;

        const MicroInstrRef      jccRef  = order[testEnd];
        const MicroInstr*        jccInst = storage.ptr(jccRef);
        const MicroInstrOperand* jccOps  = jccInst->ops(operands);
        if (!jccOps || jccInst->numOperands < 3)
            continue;
        const MicroCond cond = jccOps[0].cpuCond;
        if (cond == MicroCond::Unconditional)
            continue;
        uint32_t exitLabelId = 0;
        if (!tryGetJumpTargetLabelId(exitLabelId, *jccInst, jccOps) || exitLabelId == labelId)
            continue;

        // The back edge must be the only jump aimed at this label, and
        // unconditional. A second one would keep re-entering above the test
        // this rotation stops re-running.
        const uint32_t backOrdinal = incoming->second.ordinal;
        if (backOrdinal <= testEnd)
            continue;
        const MicroInstrRef      backRef  = order[backOrdinal];
        const MicroInstr*        backInst = storage.ptr(backRef);
        const MicroInstrOperand* backOps  = backInst->ops(operands);
        if (backOps[0].cpuCond != MicroCond::Unconditional)
            continue;

        // Falling out of the rotated back edge must land where the header test
        // used to send control, which it does exactly when the exit label is
        // what physically follows the back edge.
        if (backOrdinal + 1 >= order.size())
            continue;
        const MicroInstr* afterBack = storage.ptr(order[backOrdinal + 1]);
        uint32_t          afterId   = 0;
        if (!afterBack || !tryGetLabelId(afterId, *afterBack, afterBack->ops(operands)) || afterId != exitLabelId)
            continue;

        MicroCond inverted = MicroCond::Unconditional;
        if (!invertCondition(cond, inverted))
            continue;

        rotations.push_back({.testBegin = testBegin, .testEnd = testEnd, .jccRef = jccRef, .bodyFirstRef = order[testEnd + 1], .backRef = backRef, .inverted = inverted});
    }

    if (rotations.empty())
        return Result::Continue;

    for (const Rotation& rotation : rotations)
    {
        const MicroInstr* jccInst = storage.ptr(rotation.jccRef);
        if (!jccInst)
            continue;
        const MicroInstrOperand* jccOps = jccInst->ops(operands);
        if (!jccOps)
            continue;
        const MicroInstrOperand jccOpBits = jccOps[1];

        const uint64_t bodyLabelId = context.builder->createLabel().get();

        MicroInstrOperand bodyLabelOps[1];
        bodyLabelOps[0].valueU64 = bodyLabelId;
        storage.insertDerivedBefore(operands, rotation.bodyFirstRef, MicroInstrOpcode::Label, bodyLabelOps);

        // The test run is copied in order; each instruction is captured
        // before the insertion that may move the storage under it.
        for (uint32_t ordinal = rotation.testBegin; ordinal < rotation.testEnd; ++ordinal)
        {
            const MicroInstr* testInst = storage.ptr(order[ordinal]);
            SWC_ASSERT(testInst);
            const MicroInstrOperand* testOps = testInst->ops(operands);
            SWC_ASSERT(testOps);
            SmallVector<MicroInstrOperand, 8> testCopy;
            for (uint32_t i = 0; i < testInst->numOperands; ++i)
                testCopy.push_back(testOps[i]);
            const MicroInstrOpcode testOp = testInst->op;
            storage.insertDerivedBefore(operands, rotation.backRef, testOp, {testCopy.data(), testCopy.size()});
        }

        const MicroInstr* backInst = storage.ptr(rotation.backRef);
        if (!backInst || backInst->numOperands < 3)
            continue;
        MicroInstrOperand* backOps = backInst->ops(operands);
        if (!backOps)
            continue;
        backOps[0].cpuCond  = rotation.inverted;
        backOps[1]          = jccOpBits;
        backOps[2].valueU64 = bodyLabelId;
    }

    context.builder->invalidateControlFlowGraph();
    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
