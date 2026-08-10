#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRALoopRotate.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/SmallVector.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/Assert.h"

// Post-RA rotation of top-tested loops. See the header for why it runs here.
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

    // Only a compare qualifies as a duplicable test: anything else that sets
    // flags also produces a value, and copying it would copy that definition.
    bool isDuplicableTest(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::CmpRegReg:
            case MicroInstrOpcode::CmpRegImm:
            case MicroInstrOpcode::CmpMemImm:
            case MicroInstrOpcode::CmpMemReg:
            case MicroInstrOpcode::CmpAmcImm:
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

    struct Rotation
    {
        MicroInstrRef cmpRef       = MicroInstrRef::invalid();
        MicroInstrRef jccRef       = MicroInstrRef::invalid();
        MicroInstrRef bodyFirstRef = MicroInstrRef::invalid();
        MicroInstrRef backRef      = MicroInstrRef::invalid();
        MicroCond     inverted     = MicroCond::Unconditional;
    };
}

Result MicroPostRaLoopRotatePass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/PostRaLoopRotate");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    if (!context.builder)
        return Result::Continue;

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;

    std::vector<MicroInstrRef> order;
    order.reserve(storage.count());
    for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        order.push_back(it.current);

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

        const MicroInstrRef cmpRef  = order[ordinal + 1];
        const MicroInstr*   cmpInst = storage.ptr(cmpRef);
        if (!cmpInst || !isDuplicableTest(*cmpInst) || relocatedInstructions.contains(cmpRef.get()))
            continue;

        const MicroInstrRef      jccRef  = order[ordinal + 2];
        const MicroInstr*        jccInst = storage.ptr(jccRef);
        const MicroInstrOperand* jccOps  = jccInst ? jccInst->ops(operands) : nullptr;
        if (!jccInst || jccInst->op != MicroInstrOpcode::JumpCond || !jccOps || jccInst->numOperands < 3)
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
        MicroInstrRef backRef      = MicroInstrRef::invalid();
        uint32_t      backOrdinal  = 0;
        uint32_t      jumpsToLabel = 0;
        for (uint32_t scan = 0; scan < order.size(); ++scan)
        {
            const MicroInstr* cand = storage.ptr(order[scan]);
            if (!cand)
                continue;
            uint32_t target = 0;
            if (!tryGetJumpTargetLabelId(target, *cand, cand->ops(operands)) || target != labelId)
                continue;
            ++jumpsToLabel;
            const MicroInstrOperand* candOps = cand->ops(operands);
            if (scan > ordinal + 2 && candOps && candOps[0].cpuCond == MicroCond::Unconditional)
            {
                backRef     = order[scan];
                backOrdinal = scan;
            }
        }
        if (!backRef.isValid() || jumpsToLabel != 1)
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

        rotations.push_back({.cmpRef = cmpRef, .jccRef = jccRef, .bodyFirstRef = order[ordinal + 3], .backRef = backRef, .inverted = inverted});
    }

    if (rotations.empty())
        return Result::Continue;

    for (const Rotation& rotation : rotations)
    {
        const MicroInstr* cmpInst = storage.ptr(rotation.cmpRef);
        const MicroInstr* jccInst = storage.ptr(rotation.jccRef);
        if (!cmpInst || !jccInst)
            continue;
        const MicroInstrOperand* cmpOps = cmpInst->ops(operands);
        const MicroInstrOperand* jccOps = jccInst->ops(operands);
        if (!cmpOps || !jccOps)
            continue;

        SmallVector<MicroInstrOperand, 8> cmpCopy;
        for (uint32_t i = 0; i < cmpInst->numOperands; ++i)
            cmpCopy.push_back(cmpOps[i]);
        const MicroInstrOperand jccOpBits = jccOps[1];
        const MicroInstrOpcode  cmpOp     = cmpInst->op;

        const uint64_t bodyLabelId = context.builder->createLabel().get();

        MicroInstrOperand bodyLabelOps[1];
        bodyLabelOps[0].valueU64 = bodyLabelId;
        storage.insertDerivedBefore(operands, rotation.bodyFirstRef, MicroInstrOpcode::Label, bodyLabelOps);

        storage.insertDerivedBefore(operands, rotation.backRef, cmpOp, {cmpCopy.data(), cmpCopy.size()});

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
