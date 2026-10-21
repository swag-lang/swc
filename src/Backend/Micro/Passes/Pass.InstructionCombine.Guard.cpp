#include "pch.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroLabelHelpers.h"
#include "Backend/Micro/MicroOptimizationLimits.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/TaskContext.h"

// A runtime guard asked a second time.
//
//     cmp  i, 16                      cmp  i, 16
//     jb   A                          jb   A
//     ...report...                    ...report...
//   A:                              A:
//     ...                     ->      ...
//     cmp  i, 16                      cmp  i, 16
//     jb   B                          jmp  B
//     ...report...                    ...report...
//   B:                              B:
//
// `state[a] = f(state[a], state[b])` indexes the same array with the same
// index three times, and lowering guards each access on its own. The later
// guards test a value the first one already tested, with nothing in between
// but other guards, so they can only fail where the first one did - and that
// fault is already reported. The second jump becomes unconditional; its
// report is then unreachable, and its compare dead.
//
// Both jumps have to be guards. A program's own test of the same condition
// keeps its branch: after a report a hook chose to return from, the program
// still takes the arm the value selects.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        using MicroLabelHelpers::tryGetJumpTargetLabelId;

        // How far back an earlier guard is looked for.
        using MicroOptimizationLimits::InstructionCombineGuard::K_MAX_SCAN;

        struct GuardTest
        {
            MicroInstrOpcode op        = MicroInstrOpcode::Nop;
            MicroOpBits      bits      = MicroOpBits::Zero;
            MicroCond        cond      = MicroCond::Unconditional;
            uint32_t         leftId    = 0;
            uint32_t         rightId   = 0;
            uint64_t         immediate = 0;

            bool operator==(const GuardTest&) const = default;
        };

        bool readGuardTest(GuardTest& out, const Context& ctx, const MicroInstrRef cmpRef, const MicroCond cond)
        {
            const MicroInstr* cmp = ctx.instruction(cmpRef);
            if (!cmp || (cmp->op != MicroInstrOpcode::CmpRegImm && cmp->op != MicroInstrOpcode::CmpRegReg))
                return false;
            const MicroInstrOperand* ops = cmp->ops(*ctx.operands);
            if (!ops || !ops[0].reg.isVirtualInt())
                return false;

            const uint32_t left = ctx.ssa->reachingValueId(ops[0].reg, cmpRef);
            if (left == MicroSsaState::K_INVALID_VALUE)
                return false;

            out.op     = cmp->op;
            out.cond   = cond;
            out.leftId = left;
            if (cmp->op == MicroInstrOpcode::CmpRegImm)
            {
                if (ops[2].hasWideImmediateValue())
                    return false;
                out.bits      = ops[1].opBits;
                out.immediate = ops[2].valueU64;
                return true;
            }

            if (!ops[1].reg.isVirtualInt())
                return false;
            const uint32_t right = ctx.ssa->reachingValueId(ops[1].reg, cmpRef);
            if (right == MicroSsaState::K_INVALID_VALUE)
                return false;
            out.bits    = ops[2].opBits;
            out.rightId = right;
            return true;
        }

        // Whether `jumpRef` skips a straight-line report that ends at the label `joinRef`, either
        // falling into it or stopped by the trap behind a report that never returns.
        bool skipsReport(Context& ctx, const MicroInstrRef jumpRef, const MicroInstrRef joinRef)
        {
            bool hasReport = false;
            bool stopped   = false;
            auto walker    = MicroStorage::Iterator{ctx.storage, jumpRef};
            ++walker;
            for (; walker.current != joinRef; ++walker)
            {
                const MicroInstrRef ref  = walker.current;
                const MicroInstr*   inst = ref.isValid() ? &*walker : nullptr;
                if (!inst || stopped || inst->op == MicroInstrOpcode::Label)
                    return false;
                if (MicroInstrInfo::isTerminatorInstruction(*inst))
                {
                    if (inst->op != MicroInstrOpcode::Trap || !hasReport)
                        return false;
                    stopped = true;
                    continue;
                }
                hasReport = hasReport || ctx.isReportCall(ref);
            }
            return hasReport;
        }
    }

    bool tryDropRepeatedGuard(Context& ctx, MicroInstrRef cmpRef, const MicroInstr&)
    {
        if (!ctx.ssa || !ctx.builder)
            return false;

        const MicroInstrRef jumpRef = ctx.nextRef(cmpRef);
        const MicroInstr*   jump    = jumpRef.isValid() ? ctx.instruction(jumpRef) : nullptr;
        if (!jump || ctx.isClaimed(jumpRef))
            return false;
        const MicroInstrOperand* jumpOps  = jump->ops(*ctx.operands);
        uint32_t                 targetId = 0;
        if (!tryGetJumpTargetLabelId(targetId, *jump, jumpOps) || jumpOps[0].cpuCond == MicroCond::Unconditional)
            return false;

        GuardTest test;
        if (!readGuardTest(test, ctx, cmpRef, jumpOps[0].cpuCond))
            return false;

        // Back over straight-line code and over whole guards, to one that made the same
        // test. Every label crossed is the join of a guard and of nothing else, so the
        // guard found is the only way down to this one.
        const MicroControlFlowGraph& cfg      = ctx.builder->controlFlowGraph();
        bool                         repeated = false;
        uint32_t                     steps    = 0;
        auto                         walker   = MicroStorage::Iterator{ctx.storage, cmpRef};
        --walker;
        for (; walker.current.isValid() && !repeated && steps < K_MAX_SCAN; ++steps)
        {
            const MicroInstrRef ref  = walker.current;
            const MicroInstr*   inst = &*walker;
            if (inst->op != MicroInstrOpcode::Label)
            {
                if (MicroInstrInfo::isTerminatorInstruction(*inst))
                    return false;
                --walker;
                continue;
            }

            const uint32_t joinIndex = cfg.indexOf(ref);
            if (joinIndex == MicroControlFlowGraph::K_NO_INDEX || joinIndex == 0)
                return false;
            // The join is entered by the guard's jump, and by the report falling into it
            // unless the report ends in a trap.
            const auto  addressTaken = cfg.addressTakenLabelIndices();
            const auto& incoming     = cfg.predecessors(joinIndex);
            if (incoming.empty() || incoming.size() > 2 || std::ranges::find(addressTaken, joinIndex) != addressTaken.end())
                return false;
            const uint32_t jumpIndex = incoming[0] == joinIndex - 1 ? incoming.back() : incoming[0];
            if (jumpIndex >= joinIndex - 1 || (incoming.size() == 2 && incoming[0] != joinIndex - 1 && incoming[1] != joinIndex - 1))
                return false;

            const MicroInstrRef      earlierJumpRef = cfg.instructionRefs()[jumpIndex];
            const MicroInstr*        earlierJump    = ctx.instruction(earlierJumpRef);
            const MicroInstrOperand* earlierOps     = earlierJump ? earlierJump->ops(*ctx.operands) : nullptr;
            uint32_t                 earlierTarget  = 0;
            if (!earlierJump || !tryGetJumpTargetLabelId(earlierTarget, *earlierJump, earlierOps) ||
                earlierOps[0].cpuCond == MicroCond::Unconditional || !skipsReport(ctx, earlierJumpRef, ref))
                return false;

            const MicroInstrRef earlierCmpRef = ctx.previousRef(earlierJumpRef);
            GuardTest           earlier;
            repeated = earlierCmpRef.isValid() && readGuardTest(earlier, ctx, earlierCmpRef, earlierOps[0].cpuCond) && earlier == test;
            walker   = MicroStorage::Iterator{ctx.storage, earlierJumpRef};
            --walker;
        }

        if (!repeated)
            return false;

        // The jump being resolved must be a guard as well: see the note above.
        const uint32_t joinIndex = cfg.indexOfLabel(targetId);
        if (joinIndex == MicroControlFlowGraph::K_NO_INDEX || !skipsReport(ctx, jumpRef, cfg.instructionRefs()[joinIndex]))
            return false;

        if (!ctx.claimAll({jumpRef}))
            return false;

        MicroInstrOperand newOps[3] = {jumpOps[0], jumpOps[1], jumpOps[2]};
        newOps[0].cpuCond           = MicroCond::Unconditional;
        ctx.emitRewrite(jumpRef, MicroInstrOpcode::JumpCond, newOps);
        return true;
    }

    namespace
    {
        // What a dominating compare established about a value: `value cond other`, where
        // `other` is a constant when `hasConstant`.
        struct ValueRelation
        {
            MicroCond   cond        = MicroCond::Unconditional;
            MicroOpBits bits        = MicroOpBits::Zero;
            bool        hasConstant = false;
            uint64_t    constant    = 0;
        };

        // The condition seen from the other operand: `a < b` is `b > a`.
        bool swapCondition(MicroCond& outCond, MicroCond cond)
        {
            switch (cond)
            {
                case MicroCond::Less: outCond = MicroCond::Greater; return true;
                case MicroCond::LessOrEqual: outCond = MicroCond::GreaterOrEqual; return true;
                case MicroCond::Greater: outCond = MicroCond::Less; return true;
                case MicroCond::GreaterOrEqual: outCond = MicroCond::LessOrEqual; return true;
                case MicroCond::Below: outCond = MicroCond::Above; return true;
                case MicroCond::BelowOrEqual: outCond = MicroCond::AboveOrEqual; return true;
                case MicroCond::Above: outCond = MicroCond::Below; return true;
                case MicroCond::AboveOrEqual: outCond = MicroCond::BelowOrEqual; return true;
                case MicroCond::Equal:
                case MicroCond::NotEqual:
                case MicroCond::Zero:
                case MicroCond::NotZero: outCond = cond; return true;
                default: return false;
            }
        }

        int64_t signExtend(uint64_t value, MicroOpBits bits)
        {
            const uint32_t width = getNumBits(bits);
            if (width >= 64)
                return static_cast<int64_t>(value);
            const uint64_t sign = 1ull << (width - 1);
            value &= getBitsMask(bits);
            return static_cast<int64_t>((value ^ sign) - sign);
        }

        // Whether `value op k` stays in range, `op` an addition or a subtraction of the positive
        // constant `k`, given the relation. Signed ranges are checked for the overflow flag,
        // unsigned ones for the carry.
        bool relationKeepsInRange(const ValueRelation& rel, bool isAdd, bool isSigned, uint64_t k, MicroOpBits bits)
        {
            const uint32_t width = getNumBits(bits);
            const uint64_t mask  = getBitsMask(bits);
            if (rel.bits != bits || k == 0 || k > (mask >> 1))
                return false;

            MicroCond cond = rel.cond;
            if (cond == MicroCond::Zero)
                cond = MicroCond::Equal;
            else if (cond == MicroCond::NotZero)
                cond = MicroCond::NotEqual;

            if (isSigned)
            {
                const int64_t maxValue = width >= 64 ? INT64_MAX : static_cast<int64_t>((1ull << (width - 1)) - 1);
                const int64_t minValue = -maxValue - 1;
                const int64_t kSigned  = static_cast<int64_t>(k);
                const int64_t c        = signExtend(rel.constant, bits);
                if (isAdd)
                {
                    // Need value <= max - k.
                    if (cond == MicroCond::Less)
                        return rel.hasConstant ? c - 1 <= maxValue - kSigned : k == 1;
                    if (cond == MicroCond::LessOrEqual)
                        return rel.hasConstant && c <= maxValue - kSigned;
                    return false;
                }

                // Need value >= min + k.
                if (cond == MicroCond::Greater)
                    return rel.hasConstant ? c + 1 >= minValue + kSigned : k == 1;
                if (cond == MicroCond::GreaterOrEqual)
                    return rel.hasConstant && c >= minValue + kSigned;
                return false;
            }

            const uint64_t c = rel.constant & mask;
            if (isAdd)
            {
                // Need value <= mask - k.
                if (cond == MicroCond::Below)
                    return rel.hasConstant ? c != 0 && c - 1 <= mask - k : k == 1;
                if (cond == MicroCond::BelowOrEqual)
                    return rel.hasConstant && c <= mask - k;
                return false;
            }

            // Need value >= k.
            if (cond == MicroCond::Above)
                return rel.hasConstant ? c < mask && c + 1 >= k : k == 1;
            if (cond == MicroCond::AboveOrEqual)
                return rel.hasConstant && c >= k;
            if (cond == MicroCond::NotEqual)
                return rel.hasConstant && c == 0 && k == 1;
            return false;
        }

        // Reads `cmp value, other` + `jcc` as the relation its taken edge (or, inverted, its
        // fall-through edge) establishes about `valueId`.
        bool readComparedRelation(ValueRelation& out, const Context& ctx, MicroInstrRef cmpRef, uint32_t valueId, MicroCond jumpCond)
        {
            const MicroInstr* cmp = ctx.instruction(cmpRef);
            if (!cmp || (cmp->op != MicroInstrOpcode::CmpRegImm && cmp->op != MicroInstrOpcode::CmpRegReg))
                return false;
            const MicroInstrOperand* ops = cmp->ops(*ctx.operands);
            if (!ops || !ops[0].reg.isVirtualInt())
                return false;

            out      = {};
            out.cond = jumpCond;
            if (cmp->op == MicroInstrOpcode::CmpRegImm)
            {
                if (ops[2].hasWideImmediateValue() || ctx.ssa->reachingValueId(ops[0].reg, cmpRef) != valueId)
                    return false;
                out.bits        = ops[1].opBits;
                out.hasConstant = true;
                out.constant    = ops[2].valueU64;
                return true;
            }

            if (!ops[1].reg.isVirtualInt())
                return false;
            out.bits                   = ops[2].opBits;
            const uint32_t leftValue   = ctx.ssa->reachingValueId(ops[0].reg, cmpRef);
            const uint32_t rightValue  = ctx.ssa->reachingValueId(ops[1].reg, cmpRef);
            const bool     valueOnLeft = leftValue == valueId;
            if (!valueOnLeft && rightValue != valueId)
                return false;
            if (leftValue == rightValue)
                return false;
            if (!valueOnLeft && !swapCondition(out.cond, out.cond))
                return false;
            out.hasConstant = resolveIntConstant(out.constant, ctx, valueOnLeft ? ops[1].reg : ops[0].reg, cmpRef, out.bits);
            return true;
        }
    }

    // A guard on `value + k` or `value - k` that a dominating test of the same value settles.
    //
    //     cmp  i, j                      cmp  i, j
    //     jge  Exit                      jge  Exit
    //     ...                            ...
    //     add  i, 1                ->    add  i, 1
    //     jno  Next                      jmp  Next
    //     ...report...                   ...report...
    //   Next:                          Next:
    //
    // Every path to the addition took the edge where `i < j` held, and `j` cannot exceed the
    // width's maximum, so `i + 1` cannot overflow. The edge proves the relation only when it is
    // the only way into its target. A program's own branch is never resolved here: only a
    // guard's jump over its report, so a proof that reads a guard's outcome stays a guard's.
    bool tryResolveDominatedOverflowGuard(Context& ctx, MicroInstrRef opRef, const MicroInstr& opInst)
    {
        if (!ctx.ssa || !ctx.builder)
            return false;

        const MicroInstrOperand* ops = opInst.ops(*ctx.operands);
        if (!ops || opInst.op != MicroInstrOpcode::OpBinaryRegImm || !ops[0].reg.isVirtualInt() || ops[3].hasWideImmediateValue())
            return false;
        const bool isAdd = ops[2].microOp == MicroOp::Add;
        if (!isAdd && ops[2].microOp != MicroOp::Subtract)
            return false;
        const MicroOpBits bits = ops[1].opBits;
        if (bits != MicroOpBits::B8 && bits != MicroOpBits::B16 && bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
            return false;

        const MicroInstrRef jumpRef = ctx.nextRef(opRef);
        const MicroInstr*   jump    = jumpRef.isValid() ? ctx.instruction(jumpRef) : nullptr;
        if (!jump || jump->op != MicroInstrOpcode::JumpCond || ctx.isClaimed(jumpRef))
            return false;
        const MicroInstrOperand* jumpOps  = jump->ops(*ctx.operands);
        uint32_t                 targetId = 0;
        if (!tryGetJumpTargetLabelId(targetId, *jump, jumpOps))
            return false;
        const MicroCond guardCond = jumpOps[0].cpuCond;
        if (guardCond != MicroCond::NotOverflow && guardCond != MicroCond::AboveOrEqual)
            return false;
        const bool isSigned = guardCond == MicroCond::NotOverflow;

        const MicroControlFlowGraph& cfg       = ctx.builder->controlFlowGraph();
        const uint32_t               joinIndex = cfg.indexOfLabel(targetId);
        if (joinIndex == MicroControlFlowGraph::K_NO_INDEX || !skipsReport(ctx, jumpRef, cfg.instructionRefs()[joinIndex]))
            return false;

        const uint32_t opIndex = cfg.indexOf(opRef);
        if (opIndex == MicroControlFlowGraph::K_NO_INDEX)
            return false;
        const MicroPassHelpers::MicroDomTree* dom = ctx.guardDominators();
        if (!dom)
            return false;

        // The operand is often a copy of the value the program tested: lowering copies a
        // variable before updating it. Every value of the copy chain holds the same bits.
        SmallVector<uint32_t, 4> valueIds;
        MicroReg                 reg   = ops[0].reg;
        MicroInstrRef            useAt = opRef;
        for (uint32_t depth = 0; depth < 4; ++depth)
        {
            const auto def = ctx.ssa->reachingDef(reg, useAt);
            if (!def.valid())
                break;
            valueIds.push_back(def.valueId);
            if (def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::LoadRegReg)
                break;
            const MicroInstrOperand* copyOps = def.inst->ops(*ctx.operands);
            if (!copyOps || !copyOps[1].reg.isVirtualInt() || getNumBits(copyOps[2].opBits) < getNumBits(bits))
                break;
            reg   = copyOps[1].reg;
            useAt = def.instRef;
        }

        const uint64_t k      = ops[3].valueU64 & getBitsMask(bits);
        bool           proven = false;
        for (const uint32_t valueId : valueIds)
        {
            const auto* info = ctx.ssa->valueInfo(valueId);
            if (!info)
                continue;
            for (const auto& use : info->uses)
            {
                if (proven)
                    break;
                if (use.kind != MicroSsaState::UseSite::Kind::Instruction || use.instRef == opRef)
                    continue;

                const MicroInstrRef      branchRef = ctx.nextRef(use.instRef);
                const MicroInstr*        branch    = branchRef.isValid() ? ctx.instruction(branchRef) : nullptr;
                const MicroInstrOperand* branchOps = branch ? branch->ops(*ctx.operands) : nullptr;
                uint32_t                 branchTo  = 0;
                if (!branch || branch->op != MicroInstrOpcode::JumpCond || !tryGetJumpTargetLabelId(branchTo, *branch, branchOps) ||
                    branchOps[0].cpuCond == MicroCond::Unconditional)
                    continue;
                const uint32_t branchIndex = cfg.indexOf(branchRef);
                if (branchIndex == MicroControlFlowGraph::K_NO_INDEX || cfg.successors(branchIndex).size() != 2)
                    continue;

                // The taken edge establishes the condition, the fall-through its complement.
                const uint32_t edges[2] = {cfg.indexOfLabel(branchTo), branchIndex + 1};
                for (uint32_t edge = 0; edge < 2 && !proven; ++edge)
                {
                    const uint32_t successor = edges[edge];
                    if (successor == MicroControlFlowGraph::K_NO_INDEX || successor >= cfg.instructionRefs().size() || edges[0] == edges[1])
                        continue;
                    const auto& incoming = cfg.predecessors(successor);
                    if (incoming.size() != 1 || incoming[0] != branchIndex || !dom->dominates(successor, opIndex))
                        continue;

                    MicroCond cond = branchOps[0].cpuCond;
                    if (edge == 1 && !MicroPassHelpers::invertCondition(cond, cond))
                        continue;
                    ValueRelation relation;
                    proven = readComparedRelation(relation, ctx, use.instRef, valueId, cond) &&
                             relationKeepsInRange(relation, isAdd, isSigned, k, bits);
                }
            }
        }

        if (!proven || !ctx.claimAll({jumpRef}))
            return false;

        MicroInstrOperand newOps[3] = {jumpOps[0], jumpOps[1], jumpOps[2]};
        newOps[0].cpuCond           = MicroCond::Unconditional;
        ctx.emitRewrite(jumpRef, MicroInstrOpcode::JumpCond, newOps);
        return true;
    }

    namespace
    {
        // A value-borrow runtime call as code generation lays it out: its arguments copied into the
        // convention's first registers just before it, and the whole wrapped in an adjustment of the
        // stack pointer when the call is made at an unaligned depth.
        struct RuntimeCallShape
        {
            static constexpr uint32_t K_MAX_ARGS = 4;

            MicroInstrRef argRefs[K_MAX_ARGS] = {};
            uint32_t      argCount            = 0;
            MicroInstrRef subRef              = MicroInstrRef::invalid();
            MicroInstrRef addRef              = MicroInstrRef::invalid();
        };

        bool readStackAdjust(const Context& ctx, const MicroInstrRef adjustRef, const MicroOp op, uint64_t& outAmount)
        {
            const MicroInstr*        adjust = adjustRef.isValid() ? ctx.instruction(adjustRef) : nullptr;
            const MicroInstrOperand* ops    = adjust ? adjust->ops(*ctx.operands) : nullptr;
            if (!ops || adjust->op != MicroInstrOpcode::OpBinaryRegImm || ops[0].reg != ctx.stackPointer || ops[2].microOp != op || ops[3].hasWideImmediateValue())
                return false;
            outAmount = ops[3].valueU64;
            return true;
        }

        bool readRuntimeCallShape(RuntimeCallShape& out, const Context& ctx, MicroInstrRef callRef, const MicroInstr& callInst, uint32_t argCount)
        {
            SWC_ASSERT(argCount <= RuntimeCallShape::K_MAX_ARGS);
            const MicroInstrOperand* callOps = callInst.ops(*ctx.operands);
            if (!callOps || callInst.op != MicroInstrOpcode::CallLocal || !callInst.compilerSafetyCall)
                return false;
            const CallConv& conv = CallConv::get(callOps[0].callConv);
            if (conv.intArgRegs.size() < argCount)
                return false;

            out                     = {};
            out.argCount            = argCount;
            MicroInstrRef ref       = callRef;
            uint64_t      subAmount = 0;
            uint64_t      addAmount = 0;
            if (readStackAdjust(ctx, ctx.previousRef(callRef), MicroOp::Subtract, subAmount))
            {
                out.subRef = ctx.previousRef(callRef);
                out.addRef = ctx.nextRef(callRef);
                if (!readStackAdjust(ctx, out.addRef, MicroOp::Add, addAmount) || addAmount != subAmount)
                    return false;
                ref = out.subRef;
            }

            for (uint32_t step = 0; step < argCount; ++step)
            {
                ref                          = ctx.previousRef(ref);
                const MicroInstr*        def = ref.isValid() ? ctx.instruction(ref) : nullptr;
                const MicroInstrOperand* ops = def ? def->ops(*ctx.operands) : nullptr;
                if (!ops || def->numOperands == 0)
                    return false;
                if (def->op != MicroInstrOpcode::LoadRegReg && def->op != MicroInstrOpcode::LoadRegImm && def->op != MicroInstrOpcode::LoadRegPtrReloc &&
                    def->op != MicroInstrOpcode::LoadAddrRegMem && def->op != MicroInstrOpcode::LoadAddrAmcRegMem)
                    return false;
                const auto slot = std::ranges::find(conv.intArgRegs.begin(), conv.intArgRegs.begin() + argCount, ops[0].reg);
                if (slot == conv.intArgRegs.begin() + argCount)
                    return false;
                const size_t index = static_cast<size_t>(slot - conv.intArgRegs.begin());
                if (out.argRefs[index].isValid())
                    return false;
                out.argRefs[index] = ref;
            }

            return true;
        }

        void appendRuntimeCall(SmallVector<MicroInstrRef, 8>& refs, MicroInstrRef callRef, const RuntimeCallShape& shape)
        {
            for (uint32_t index = 0; index < shape.argCount; ++index)
                refs.push_back(shape.argRefs[index]);
            refs.push_back(callRef);
            if (shape.subRef.isValid())
            {
                refs.push_back(shape.subRef);
                refs.push_back(shape.addRef);
            }
        }

        // Erases calls with their argument copies, all of them or none; the values the copies
        // took die with them.
        bool eraseAll(Context& ctx, std::span<const MicroInstrRef> refs)
        {
            for (const MicroInstrRef ref : refs)
            {
                if (ctx.isClaimed(ref))
                    return false;
            }
            for (const MicroInstrRef ref : refs)
            {
                ctx.claimed.insert(ref.get());
                ctx.emitErase(ref);
            }
            return true;
        }
    }

    // A value-borrow check of a write into the function's own frame.
    //
    //     rcx = %address          (erased)
    //     rdx = %size             (erased)
    //     r8  = %location         (erased)
    //     r9  = %extentCache      (erased)
    //     call __valueBorrowWrite (erased)
    //
    // Code generation marks a write guard emitted while the function had no borrow of its own
    // open. Only such a borrow could cover this frame, so a fixed-size write whose address is
    // proved to lie in the frame cannot meet one. A write of a computed size keeps its check:
    // nothing bounds it to the frame. The extent test in front of the calls that stay is added
    // later, so nothing of it is left behind.
    bool tryDropFrameWriteGuard(Context& ctx, MicroInstrRef callRef, const MicroInstr& callInst)
    {
        if (!callInst.frameWriteGuard || !ctx.ssa)
            return false;

        // Address, size, source location and the module's extent cache.
        RuntimeCallShape shape;
        if (!readRuntimeCallShape(shape, ctx, callRef, callInst, 4))
            return false;

        const MicroInstr*        addressDef = ctx.instruction(shape.argRefs[0]);
        const MicroInstrOperand* addressOps = addressDef->ops(*ctx.operands);
        if (addressDef->op == MicroInstrOpcode::LoadRegImm || addressDef->op == MicroInstrOpcode::LoadRegPtrReloc ||
            !isFrameDerivedAddress(ctx, addressOps[1].reg, shape.argRefs[0]))
            return false;

        const MicroInstr*        sizeDef = ctx.instruction(shape.argRefs[1]);
        const MicroInstrOperand* sizeOps = sizeDef->ops(*ctx.operands);
        uint64_t                 size    = 0;
        if (sizeDef->op == MicroInstrOpcode::LoadRegReg)
        {
            if (!resolveIntConstant(size, ctx, sizeOps[1].reg, shape.argRefs[1], MicroOpBits::B64))
                return false;
        }
        else if (sizeDef->op != MicroInstrOpcode::LoadRegImm)
            return false;

        SmallVector<MicroInstrRef, 8> refs;
        appendRuntimeCall(refs, callRef, shape);
        return eraseAll(ctx, refs.span());
    }

    // Value borrows nothing can observe.
    //
    // A borrow is only ever judged by a write check, by the runtime's own checks of an allocator
    // release, or by code the borrowing function calls. A function that calls nothing but the
    // borrow registration itself and the panic reports, and keeps no write check, cannot reach any
    // of them while its borrows are open, so it registers none: a function reading the string or
    // the struct it received by value no longer pays for the registry on every call. Writes from
    // other threads are not the guard's to detect.
    void runDropUnobservedBorrows(Context& ctx)
    {
        if (!ctx.builder || ctx.builder->codeRelocations().empty() || !ctx.passContext || !ctx.passContext->taskContext || !ctx.passContext->taskContext->hasCompiler())
            return;

        const IdentifierManager& idMgr   = ctx.passContext->taskContext->idMgr();
        const IdentifierRef      enterId = idMgr.runtimeFunction(IdentifierManager::RuntimeFunctionKind::ValueBorrowEnter);
        const IdentifierRef      leaveId = idMgr.runtimeFunction(IdentifierManager::RuntimeFunctionKind::ValueBorrowLeave);

        struct BorrowCall
        {
            MicroInstrRef ref;
            uint32_t      argCount;
        };
        SmallVector<BorrowCall, 8> borrowCalls;
        FlatKeyMap<uint32_t>       borrowArgs;
        for (const MicroRelocation& relocation : ctx.builder->codeRelocations())
        {
            if (relocation.instructionRef.isInvalid() || !relocation.targetSymbol)
                continue;
            const IdentifierRef idRef = relocation.targetSymbol->idRef();
            // Record, address, size and source location; the release takes the record alone.
            if (idRef == enterId)
                borrowArgs.getOrInsert(relocation.instructionRef.get()) = 4;
            else if (idRef == leaveId)
                borrowArgs.getOrInsert(relocation.instructionRef.get()) = 1;
        }
        if (borrowArgs.empty())
            return;

        for (auto it = ctx.storage->view().begin(), endIt = ctx.storage->view().end(); it != endIt; ++it)
        {
            if (!MicroInstr::info(it->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                continue;
            if (const uint32_t* argCount = borrowArgs.find(it.current.get()); argCount && it->compilerSafetyCall)
                borrowCalls.push_back({it.current, *argCount});
            else if (!ctx.isReportCall(it.current))
                return;
        }

        // A registration left without its release would outlive the frame.
        SmallVector<MicroInstrRef, 8> refs;
        for (const BorrowCall& call : borrowCalls)
        {
            RuntimeCallShape shape;
            if (!readRuntimeCallShape(shape, ctx, call.ref, *ctx.instruction(call.ref), call.argCount))
                return;
            appendRuntimeCall(refs, call.ref, shape);
        }

        eraseAll(ctx, refs.span());
    }
}

SWC_END_NAMESPACE();
