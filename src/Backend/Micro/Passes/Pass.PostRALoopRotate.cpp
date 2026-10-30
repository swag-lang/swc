#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRALoopRotate.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroLabelHelpers.h"
#include "Backend/Micro/MicroOptimizationLimits.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
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
    using MicroLabelHelpers::tryGetJumpTargetLabelId;
    using MicroLabelHelpers::tryGetLabelId;

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

    // Address calculations in a header can be copied with its test: the
    // next iteration sees the updated index before entering the body.
    bool isDuplicableHeaderConnector(const MicroInstr& inst)
    {
        return isDuplicableConnector(inst) || inst.op == MicroInstrOpcode::LoadAmcRegMem ||
               inst.op == MicroInstrOpcode::LoadAddrRegMem || inst.op == MicroInstrOpcode::LoadAddrAmcRegMem;
    }

    // A header carrying more than this around its compare is not worth
    // duplicating for the one jump the rotation removes.
    using MicroOptimizationLimits::PostRALoopRotate::K_MAX_TEST_RUN;

    // Prove that every path into a peeled prefix still carries its first value.
    // Start at its fallthrough predecessor, excluding the old scalar back edge.
    // Only fixed, disjoint stores through that same base may cross the proof.
    bool hasEntryLoadedValue(const MicroPassContext& context, const MicroControlFlowGraph& cfg, uint32_t start, MicroReg base, MicroReg value, int64_t offset)
    {
        constexpr uint32_t                         K_ENTRY_VALUE_LOOKBACK = 32;
        SmallVector<std::pair<uint32_t, uint32_t>> pending;
        pending.push_back({start, 0});
        std::vector<uint8_t> visited(cfg.instructionCount(), 0);
        while (!pending.empty())
        {
            const auto [index, distance] = pending.back();
            pending.pop_back();
            if (index >= visited.size() || visited[index] || distance >= K_ENTRY_VALUE_LOOKBACK)
                return false;
            visited[index]   = 1;
            const auto* inst = context.instructions->ptr(cfg.instructionRefs()[index]);
            const auto* ops  = inst->ops(*context.operands);
            if (inst->op == MicroInstrOpcode::LoadRegMem && ops[0].reg == value && ops[1].reg == base && ops[2].opBits == MicroOpBits::B64 && ops[3].valueU64 == static_cast<uint64_t>(offset))
                continue;
            if (inst->op == MicroInstrOpcode::LoadMemReg && ops[0].reg == base)
            {
                const auto writeOffset = static_cast<int64_t>(ops[3].valueU64);
                if (ops[1].reg == value && ops[2].opBits == MicroOpBits::B64 && writeOffset == offset)
                    continue;
                if (writeOffset < INT32_MIN || writeOffset > INT32_MAX ||
                    (writeOffset < offset + 8 && writeOffset + getNumBytes(ops[2].opBits) > offset))
                    return false;
            }
            else if (MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::WritesMemory))
                return false;
            const auto flags = MicroInstr::info(inst->op).flags;
            if (flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                MicroPassHelpers::regTouch(*inst, *context.operands, value, context.encoder).def ||
                MicroPassHelpers::regTouch(*inst, *context.operands, base, context.encoder).def)
                return false;
            const auto& predecessors = cfg.predecessors(index);
            if (predecessors.empty())
                return false;
            for (const auto predecessor : predecessors)
                pending.push_back({predecessor, distance + 1});
        }
        return true;
    }

    // Peel a swap loop whose indices converge by one element per iteration.
    // A constant left seed gives the prefix direct addresses without extending
    // any register lifetime. Live indices or exit flags keep the original loop.
    bool peelOpposingIndexSwaps(MicroPassContext& context, const std::vector<MicroInstrRef>& order)
    {
        auto& builder = *context.builder;
        if (!context.encoder || !builder.backendBuildCfg().runsCostlyOptimizations())
            return false;
        const auto         limits                          = MicroOptimizationLimits::resolveUnroll(context.optimizer().unroll);
        const auto         factor                          = limits.partialFactor;
        constexpr uint64_t K_PREFIX_ITERATION_INSTRUCTIONS = 7; // four memory accesses, a step and a compare/branch pair
        if (factor < 2 || factor > limits.maxOrdinaryTotalInstructions / K_PREFIX_ITERATION_INSTRUCTIONS)
            return false;
        auto&                               storage  = *context.instructions;
        auto&                               operands = *context.operands;
        MicroPassHelpers::MicroPhysLiveness liveness;
        FlatKeyMap<uint32_t>                jumpCounts;
        bool                                analyzed = false;
        for (uint32_t at = 1; at + 10 < order.size(); ++at)
        {
            const auto* header = storage.ptr(order[at]);
            if (header->op != MicroInstrOpcode::Label)
                continue;
            const auto* bound     = storage.ptr(order[at + 1]);
            const auto* leave     = storage.ptr(order[at + 2]);
            const auto* first     = storage.ptr(order[at + 3]);
            const auto* second    = storage.ptr(order[at + 4]);
            const auto* putFirst  = storage.ptr(order[at + 5]);
            const auto* putSecond = storage.ptr(order[at + 6]);
            const auto* advance   = storage.ptr(order[at + 7]);
            const auto* retreat   = storage.ptr(order[at + 8]);
            const auto* back      = storage.ptr(order[at + 9]);
            const auto* exit      = storage.ptr(order[at + 10]);
            if (bound->op != MicroInstrOpcode::CmpRegReg || leave->op != MicroInstrOpcode::JumpCond ||
                first->op != MicroInstrOpcode::LoadAmcRegMem || second->op != MicroInstrOpcode::LoadAmcRegMem ||
                putFirst->op != MicroInstrOpcode::LoadAmcMemReg || putSecond->op != MicroInstrOpcode::LoadAmcMemReg ||
                advance->op != MicroInstrOpcode::OpUnaryReg || retreat->op != MicroInstrOpcode::OpUnaryReg ||
                back->op != MicroInstrOpcode::JumpCond || exit->op != MicroInstrOpcode::Label)
                continue;
            const auto* h           = header->ops(operands);
            const auto* b           = bound->ops(operands);
            const auto* j           = leave->ops(operands);
            const auto* a           = first->ops(operands);
            const auto* c           = second->ops(operands);
            const auto* s           = putFirst->ops(operands);
            const auto* t           = putSecond->ops(operands);
            const auto* p           = advance->ops(operands);
            const auto* q           = retreat->ops(operands);
            const auto* k           = back->ops(operands);
            const auto* e           = exit->ops(operands);
            const auto  left        = b[0].reg;
            const auto  right       = b[1].reg;
            const bool  signedBound = j[0].cpuCond == MicroCond::GreaterOrEqual;
            if ((!signedBound && j[0].cpuCond != MicroCond::AboveOrEqual) || b[2].opBits != MicroOpBits::B64 ||
                !left.isInt() || !right.isInt() || left == right || left == CallConv::get(context.callConvKind).stackPointer || right == CallConv::get(context.callConvKind).stackPointer ||
                j[2].valueU64 != e[0].valueU64 || k[0].cpuCond != MicroCond::Unconditional || k[2].valueU64 != h[0].valueU64 ||
                p[0].reg != left || p[1].opBits != MicroOpBits::B64 || p[2].microOp != MicroOp::Add ||
                q[0].reg != right || q[1].opBits != MicroOpBits::B64 || q[2].microOp != MicroOp::Subtract)
                continue;
            if (!a[0].reg.isInt() || !c[0].reg.isInt() || a[0].reg == c[0].reg ||
                !a[1].reg.isInt() || !c[1].reg.isInt() || a[2].reg != left || c[2].reg != right ||
                a[3].opBits != c[3].opBits || a[4].opBits != MicroOpBits::B64 || c[4].opBits != MicroOpBits::B64 ||
                s[0].reg != a[1].reg || s[1].reg != left || s[2].reg != c[0].reg || s[3].opBits != MicroOpBits::B64 || s[4].opBits != a[3].opBits || s[5].valueU64 != a[5].valueU64 || s[6].valueU64 != a[6].valueU64 ||
                t[0].reg != c[1].reg || t[1].reg != right || t[2].reg != a[0].reg || t[3].opBits != MicroOpBits::B64 || t[4].opBits != c[3].opBits || t[5].valueU64 != c[5].valueU64 || t[6].valueU64 != c[6].valueU64)
                continue;
            const auto& conv = CallConv::get(context.callConvKind);
            if (a[1].reg == conv.stackPointer || c[1].reg == conv.stackPointer)
                continue;
            bool aliasesIndex = false;
            for (const auto reg : {a[0].reg, c[0].reg, a[1].reg, c[1].reg})
                aliasesIndex |= reg == left || reg == right;
            if (aliasesIndex || a[0].reg == a[1].reg || a[0].reg == c[1].reg || c[0].reg == a[1].reg || c[0].reg == c[1].reg ||
                (a[5].valueU64 != 1 && a[5].valueU64 != 2 && a[5].valueU64 != 4 && a[5].valueU64 != 8))
                continue;

            std::optional<uint64_t> seed;
            for (uint32_t distance = 1; distance <= limits.initializerLookback && distance <= at; ++distance)
            {
                const auto* previous = storage.ptr(order[at - distance]);
                const auto  flags    = MicroInstr::info(previous->op).flags;
                if (previous->op == MicroInstrOpcode::Label || flags.has(MicroInstrFlagsE::JumpInstruction) || flags.has(MicroInstrFlagsE::IsCallInstruction) || flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    break;
                if (!MicroPassHelpers::regTouch(*previous, operands, left, context.encoder).def)
                    continue;
                const auto* init = previous->ops(operands);
                if (previous->op == MicroInstrOpcode::ClearReg && (init[1].opBits == MicroOpBits::B32 || init[1].opBits == MicroOpBits::B64))
                    seed = 0;
                else if (previous->op == MicroInstrOpcode::LoadRegImm && !init[2].hasWideImmediateValue() && (init[1].opBits == MicroOpBits::B32 || init[1].opBits == MicroOpBits::B64))
                    seed = init[2].valueU64 & getBitsMask(init[1].opBits);
                break;
            }
            if (!seed || (!signedBound && *seed > UINT64_MAX - factor))
                continue;
            const auto initial      = static_cast<int64_t>(*seed);
            const auto displacement = static_cast<int64_t>(a[6].valueU64);
            const auto stride       = a[5].valueU64;
            if (initial < INT32_MIN || initial > INT32_MAX - static_cast<int64_t>(factor) || displacement < INT32_MIN || displacement > INT32_MAX)
                continue;
            const auto firstOffset = displacement + initial * static_cast<int64_t>(stride);
            const auto lastOffset  = firstOffset + static_cast<int64_t>((factor - 1) * stride);
            if (firstOffset < INT32_MIN || lastOffset > INT32_MAX)
                continue;

            const auto& cfg = builder.controlFlowGraph();
            if (cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness() ||
                !MicroPassHelpers::areCpuFlagsDeadAfterInCfg(builder, order[at + 10]))
                continue;
            bool addressTaken = false;
            for (const auto target : cfg.addressTakenLabelIndices())
                addressTaken |= target >= at && target <= at + 10;
            if (addressTaken)
                continue;
            if (!analyzed)
            {
                MicroPassHelpers::computePhysicalLiveness(liveness, context, MicroPassHelpers::MicroPhysLivenessMode::LiveOutOnly);
                if (!liveness.valid)
                    return false;
                for (const auto ref : order)
                {
                    const auto* instruction = storage.ptr(ref);
                    uint32_t    target;
                    if (tryGetJumpTargetLabelId(target, *instruction, instruction->ops(operands)))
                        ++jumpCounts.getOrInsert(target);
                }
                analyzed = true;
            }
            const auto* incoming = jumpCounts.find(static_cast<uint32_t>(h[0].valueU64));
            if (!incoming || *incoming != 1)
                continue;
            if (liveness.isLiveOut(at + 10, left) || liveness.isLiveOut(at + 10, right))
                continue;

            const bool reuseFirstValue = a[3].opBits == MicroOpBits::B64 &&
                                         !liveness.isLiveOut(at + 10, a[0].reg) &&
                                         hasEntryLoadedValue(context, cfg, cfg.indexOf(order[at - 1]), a[1].reg, right, firstOffset);
            const auto                       before    = order[at];
            const auto                       exitId    = e[0].valueU64;
            const auto                       bodyId    = builder.createLabel().get();
            const auto                       leaveCond = signedBound ? MicroCond::LessOrEqual : MicroCond::BelowOrEqual;
            std::array<MicroInstrOperand, 7> upperRead;
            std::copy_n(c, 7, upperRead.begin());
            std::array<MicroInstrOperand, 7> upperWrite;
            std::copy_n(t, 7, upperWrite.begin());
            std::array<MicroInstrOperand, 3> upperStep    = {q[0], q[1], q[2]};
            std::array<MicroInstrOperand, 3> scalarBounds = {b[0], b[1], b[2]};
            MicroInstrOperand                lowerRead[4] = {};
            lowerRead[0].reg                              = a[0].reg;
            lowerRead[1].reg                              = a[1].reg;
            lowerRead[2].opBits                           = a[3].opBits;
            MicroInstrOperand lowerWrite[4]               = {};
            lowerWrite[0].reg                             = s[0].reg;
            lowerWrite[1].reg                             = s[2].reg;
            lowerWrite[2].opBits                          = s[4].opBits;
            MicroInstrOperand test[3]                     = {};
            test[0].reg                                   = right;
            test[1].opBits                                = MicroOpBits::B64;
            test[2].setImmediateValue(ApInt(*seed, 64));
            MicroInstrOperand stop[3] = {};
            stop[0].cpuCond           = leaveCond;
            stop[1].opBits            = MicroOpBits::B32;
            stop[2].valueU64          = exitId;
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::CmpRegImm, test);
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::JumpCond, stop);
            for (uint64_t lane = 0; lane < factor; ++lane)
            {
                lowerRead[3].valueU64  = static_cast<uint64_t>(firstOffset + static_cast<int64_t>(lane * stride));
                lowerWrite[3].valueU64 = lowerRead[3].valueU64;
                if (lane || !reuseFirstValue)
                    storage.insertDerivedBefore(operands, before, MicroInstrOpcode::LoadRegMem, lowerRead);
                upperWrite[2].reg = !lane && reuseFirstValue ? right : lowerRead[0].reg;
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::LoadAmcRegMem, upperRead);
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::LoadMemReg, lowerWrite);
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::LoadAmcMemReg, upperWrite);
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::OpUnaryReg, upperStep);
                test[2].setImmediateValue(ApInt(*seed + lane + 1, 64));
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::CmpRegImm, test);
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::JumpCond, stop);
            }
            MicroInstrOperand resume[3] = {};
            resume[0].reg               = left;
            resume[1].opBits            = MicroOpBits::B64;
            resume[2].setImmediateValue(ApInt(*seed + factor, 64));
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::LoadRegImm, resume);
            stop[0].cpuCond  = MicroCond::Unconditional;
            stop[2].valueU64 = bodyId;
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::JumpCond, stop);
            MicroInstrOperand label[1] = {};
            label[0].valueU64          = bodyId;
            storage.insertDerivedBefore(operands, order[at + 3], MicroInstrOpcode::Label, label);
            storage.insertDerivedBefore(operands, order[at + 9], MicroInstrOpcode::CmpRegReg, scalarBounds);
            auto* backOps       = storage.ptr(order[at + 9])->ops(operands);
            backOps[0].cpuCond  = signedBound ? MicroCond::Less : MicroCond::Below;
            backOps[2].valueU64 = bodyId;
            builder.invalidateControlFlowGraph();
            context.passChanged = true;
            return true;
        }
        return false;
    }

    // Probe each byte in source order, but amortize the bound test across a group.
    // Exit stubs advance the index with LEA so the original byte-comparison flags
    // survive. The original loop remains the short tail and receives extra incoming
    // edges, which prevents unrolling that same tail again on a later sweep.
    bool unrollBoundedByteScan(MicroPassContext& context, const std::vector<MicroInstrRef>& order)
    {
        auto& builder = *context.builder;
        if (!builder.backendBuildCfg().runsCostlyOptimizations())
            return false;
        const auto factor = MicroOptimizationLimits::resolveUnroll(context.optimizer().unroll).partialFactor;
        if (factor < 2)
            return false;
        auto&                               storage  = *context.instructions;
        auto&                               operands = *context.operands;
        const auto&                         conv     = CallConv::get(context.callConvKind);
        MicroPassHelpers::MicroPhysLiveness liveness;
        FlatKeyMap<uint32_t>                jumpCounts;
        bool                                analyzed = false;
        for (uint32_t at = 0; at + 7 < order.size(); ++at)
        {
            const auto* header = storage.ptr(order[at]);
            const auto* bound  = storage.ptr(order[at + 1]);
            const auto* leave  = storage.ptr(order[at + 2]);
            const auto* load   = storage.ptr(order[at + 3]);
            const bool  paired = load->op == MicroInstrOpcode::LoadAmcRegMem;
            if (at + 7 + paired >= order.size())
                continue;
            const auto* compare = storage.ptr(order[at + 3 + paired]);
            const auto* found   = storage.ptr(order[at + 4 + paired]);
            const auto* step    = storage.ptr(order[at + 5 + paired]);
            const auto* back    = storage.ptr(order[at + 6 + paired]);
            const auto* exit    = storage.ptr(order[at + 7 + paired]);
            if (header->op != MicroInstrOpcode::Label || bound->op != MicroInstrOpcode::CmpRegReg ||
                leave->op != MicroInstrOpcode::JumpCond || compare->op != (paired ? MicroInstrOpcode::CmpAmcReg : MicroInstrOpcode::CmpAmcImm) ||
                found->op != MicroInstrOpcode::JumpCond || back->op != MicroInstrOpcode::JumpCond || exit->op != MicroInstrOpcode::Label)
                continue;
            const auto* h           = header->ops(operands);
            const auto* b           = bound->ops(operands);
            const auto* l           = leave->ops(operands);
            const auto* c           = compare->ops(operands);
            const auto* f           = found->ops(operands);
            const auto* s           = step->ops(operands);
            const auto* k           = back->ops(operands);
            const auto* e           = exit->ops(operands);
            const auto* a           = paired ? load->ops(operands) : nullptr;
            const auto  index       = b[0].reg;
            const auto  limit       = b[1].reg;
            const bool  signedBound = paired && l[0].cpuCond == MicroCond::GreaterOrEqual;
            if (!index.isInt() || !limit.isInt() || index == limit || !c[0].reg.isInt() || c[0].reg == index ||
                b[2].opBits != MicroOpBits::B64 || (!signedBound && l[0].cpuCond != MicroCond::AboveOrEqual) ||
                c[1].reg != index ||
                (f[0].cpuCond != MicroCond::Equal && f[0].cpuCond != MicroCond::NotEqual) ||
                l[2].valueU64 != e[0].valueU64 || f[2].valueU64 != e[0].valueU64 ||
                k[0].cpuCond != MicroCond::Unconditional || k[2].valueU64 != h[0].valueU64)
                continue;
            const uint32_t compareOffset = paired ? 6 : 5;
            if (paired)
            {
                if (c[3].opBits != MicroOpBits::B64 || c[4].opBits != MicroOpBits::B8 || c[5].valueU64 != 1 ||
                    !a[0].reg.isInt() || !a[1].reg.isInt() || a[1].reg == index || a[2].reg != index ||
                    a[3].opBits != MicroOpBits::B8 || a[4].opBits != MicroOpBits::B64 || a[5].valueU64 != 1 ||
                    c[2].reg != a[0].reg || a[0].reg == index || a[0].reg == limit ||
                    a[0].reg == a[1].reg || a[0].reg == c[0].reg)
                    continue;
            }
            else if (c[2].opBits != MicroOpBits::B8 || c[3].opBits != MicroOpBits::B64 || c[4].valueU64 != 1)
                continue;
            bool unitStep = false;
            if (step->op == MicroInstrOpcode::OpUnaryReg)
                unitStep = s[0].reg == index && s[1].opBits == MicroOpBits::B64 && s[2].microOp == MicroOp::Add;
            else if (step->op == MicroInstrOpcode::OpBinaryRegImm)
                unitStep = s[0].reg == index && s[1].opBits == MicroOpBits::B64 && s[2].microOp == MicroOp::Add &&
                           !s[3].hasWideImmediateValue() && s[3].valueU64 == 1;
            else if (step->op == MicroInstrOpcode::LoadAddrRegMem)
                unitStep = s[0].reg == index && s[1].reg == index && s[2].opBits == MicroOpBits::B64 && s[3].valueU64 == 1;
            const auto displacement     = static_cast<int64_t>(c[compareOffset].valueU64);
            const auto loadDisplacement = paired ? static_cast<int64_t>(a[6].valueU64) : 0;
            if (!unitStep || displacement < std::numeric_limits<int32_t>::min() ||
                displacement > std::numeric_limits<int32_t>::max() - static_cast<int64_t>(factor - 1) ||
                loadDisplacement < std::numeric_limits<int32_t>::min() ||
                loadDisplacement > std::numeric_limits<int32_t>::max() - static_cast<int64_t>(factor - 1))
                continue;
            if (!analyzed)
            {
                const auto& cfg = builder.controlFlowGraph();
                if (cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness())
                    return false;
                MicroPassHelpers::computePhysicalLiveness(liveness, context, MicroPassHelpers::MicroPhysLivenessMode::LiveOutOnly);
                if (!liveness.valid)
                    return false;
                for (const auto ref : order)
                {
                    const auto* inst = storage.ptr(ref);
                    uint32_t    target;
                    if (tryGetJumpTargetLabelId(target, *inst, inst->ops(operands)))
                        ++jumpCounts.getOrInsert(target);
                }
                analyzed = true;
            }
            const auto* incoming = jumpCounts.find(static_cast<uint32_t>(h[0].valueU64));
            if (!incoming || *incoming != 1)
                continue;
            MicroReg scratch;
            for (const auto reg : conv.intTransientRegs)
            {
                if (paired && reg == a[0].reg)
                    continue;
                const auto bit = MicroPassHelpers::MicroPhysLiveness::bitOf(reg);
                if (bit < MicroPassHelpers::MicroPhysLiveness::K_INVALID_BIT && !(liveness.liveIn[at] & (1ull << bit)))
                {
                    scratch = reg;
                    break;
                }
            }
            // A scan-local byte temporary can carry the remaining distance between
            // groups when pressure leaves no spare register. Its full value must be
            // dead at the common exit: a byte load alone does not kill upper bits.
            const bool reuseLoad = !scratch.isValid() && paired && !liveness.isLiveOut(at + 7 + paired, a[0].reg);
            if (reuseLoad)
                scratch = a[0].reg;
            if (!scratch.isValid())
                continue;

            const auto            before   = order[at];
            const auto            after    = order[at + 7 + paired];
            const auto            headerId = h[0].valueU64;
            const auto            exitId   = e[0].valueU64;
            const auto            fastId   = builder.createLabel().get();
            SmallVector<uint64_t> exits;
            for (uint64_t lane = 1; lane < factor; ++lane)
                exits.push_back(builder.createLabel().get());
            std::array<MicroInstrOperand, 3> bounds       = {b[0], b[1], b[2]};
            const auto                       scalarBounds = bounds;
            std::array<MicroInstrOperand, 3> boundsExit   = {l[0], l[1], l[2]};
            std::array<MicroInstrOperand, 3> byteExit     = {f[0], f[1], f[2]};
            std::array<MicroInstrOperand, 7> byteCompare;
            std::copy_n(c, 7, byteCompare.begin());
            std::array<MicroInstrOperand, 7> byteLoad;
            if (paired)
                std::copy_n(a, 7, byteLoad.begin());
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::CmpRegReg, bounds);
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::JumpCond, boundsExit);
            MicroInstrOperand label[1] = {};
            label[0].valueU64          = fastId;
            if (reuseLoad)
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::Label, label);
            MicroInstrOperand copy[3] = {};
            copy[0].reg               = scratch;
            copy[1].reg               = limit;
            copy[2].opBits            = MicroOpBits::B64;
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::LoadRegReg, copy);
            // With index < limit, the unsigned distance is exact even when signed
            // endpoints straddle zero. A complete group cannot wrap the index.
            MicroInstrOperand distance[4] = {};
            distance[0].reg               = scratch;
            distance[1].reg               = index;
            distance[2].opBits            = MicroOpBits::B64;
            distance[3].microOp           = MicroOp::Subtract;
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::OpBinaryRegReg, distance);
            MicroInstrOperand minimum[3] = {};
            minimum[0].reg               = scratch;
            minimum[1].opBits            = MicroOpBits::B64;
            minimum[2].setImmediateValue(ApInt(factor, 64));
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::CmpRegImm, minimum);
            MicroInstrOperand tail[3] = {boundsExit[0], boundsExit[1], boundsExit[2]};
            tail[0].cpuCond           = MicroCond::Below;
            tail[2].valueU64          = headerId;
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::JumpCond, tail);
            if (!reuseLoad)
            {
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::LoadRegReg, copy);
                MicroInstrOperand limitAdjust[4] = {};
                limitAdjust[0].reg               = scratch;
                limitAdjust[1].opBits            = MicroOpBits::B64;
                limitAdjust[2].microOp           = MicroOp::Subtract;
                limitAdjust[3].setImmediateValue(ApInt(factor - 1, 64));
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::OpBinaryRegImm, limitAdjust);
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::Label, label);
                bounds[1].reg = scratch;
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::CmpRegReg, bounds);
                tail[0].cpuCond = boundsExit[0].cpuCond;
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::JumpCond, tail);
            }
            for (uint64_t lane = 0; lane < factor; ++lane)
            {
                if (paired)
                {
                    byteLoad[6].valueU64 = static_cast<uint64_t>(loadDisplacement) + lane;
                    storage.insertDerivedBefore(operands, before, MicroInstrOpcode::LoadAmcRegMem, byteLoad);
                }
                byteCompare[compareOffset].valueU64 = static_cast<uint64_t>(displacement) + lane;
                byteExit[2].valueU64                = lane ? exits[lane - 1] : exitId;
                storage.insertDerivedBefore(operands, before, paired ? MicroInstrOpcode::CmpAmcReg : MicroInstrOpcode::CmpAmcImm, byteCompare);
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::JumpCond, byteExit);
            }
            MicroInstrOperand advance[4] = {};
            advance[0].reg               = index;
            advance[1].reg               = index;
            advance[2].opBits            = MicroOpBits::B64;
            advance[3].valueU64          = factor;
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::LoadAddrRegMem, advance);
            tail[0].cpuCond  = MicroCond::Unconditional;
            tail[2].valueU64 = fastId;
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::JumpCond, tail);
            if (paired)
            {
                // Keep the short tail rotated too. Its extra entries prevent the
                // ordinary unique-backedge rotation from handling it later.
                const auto bodyId = builder.createLabel().get();
                label[0].valueU64 = bodyId;
                storage.insertDerivedBefore(operands, order[at + 3], MicroInstrOpcode::Label, label);
                storage.insertDerivedBefore(operands, order[at + 6 + paired], MicroInstrOpcode::CmpRegReg, scalarBounds);
                auto* backOps       = storage.ptr(order[at + 6 + paired])->ops(operands);
                backOps[0].cpuCond  = signedBound ? MicroCond::Less : MicroCond::Below;
                backOps[2].valueU64 = bodyId;
                tail[2].valueU64    = exitId;
                storage.insertDerivedBefore(operands, after, MicroInstrOpcode::JumpCond, tail);
            }
            for (uint64_t lane = 1; lane < factor; ++lane)
            {
                label[0].valueU64 = exits[lane - 1];
                storage.insertDerivedBefore(operands, after, MicroInstrOpcode::Label, label);
                advance[3].valueU64 = lane;
                storage.insertDerivedBefore(operands, after, MicroInstrOpcode::LoadAddrRegMem, advance);
                tail[2].valueU64 = exitId;
                storage.insertDerivedBefore(operands, after, MicroInstrOpcode::JumpCond, tail);
            }
            builder.invalidateControlFlowGraph();
            context.passChanged = true;
            return true;
        }
        return false;
    }

    // On the taken edge, neither operand changes before the repeated comparison.
    // Keeping its ordered operands and width also keeps every arithmetic flag.
    bool threadRepeatedCompareExits(MicroPassContext& context, const std::vector<MicroInstrRef>& order)
    {
        auto&                builder  = *context.builder;
        auto&                storage  = builder.instructions();
        auto&                operands = builder.operands();
        bool                 changed  = false;
        FlatKeyMap<uint32_t> continuations;
        FlatKeyMap<uint32_t> labelOrdinals;
        for (uint32_t index = 0; index < order.size(); ++index)
        {
            const auto* inst = storage.ptr(order[index]);
            uint32_t    label;
            if (tryGetLabelId(label, *inst, inst->ops(operands)))
                labelOrdinals.emplace(label, index);
        }
        for (size_t ordinal = 1; ordinal < order.size(); ++ordinal)
        {
            const auto  jumpRef = order[ordinal];
            const auto* jump    = storage.ptr(jumpRef);
            const auto* cmp     = storage.ptr(order[ordinal - 1]);
            if (!jump || jump->op != MicroInstrOpcode::JumpCond || !cmp || cmp->op != MicroInstrOpcode::CmpRegReg)
                continue;
            const auto* jumpOps = jump->ops(operands);
            const auto* cmpOps  = cmp->ops(operands);
            MicroCond   inverse;
            if (!cmpOps[0].reg.isAnyInt() || !cmpOps[1].reg.isAnyInt() ||
                !MicroPassHelpers::invertLayoutBranchCondition(inverse, jumpOps[0].cpuCond))
                continue;
            uint32_t joinId;
            if (!tryGetJumpTargetLabelId(joinId, *jump, jumpOps))
                continue;
            const auto* join = labelOrdinals.find(joinId);
            if (!join || *join <= ordinal)
                continue;
            size_t next = *join + 1;
            while (next < order.size() && storage.ptr(order[next])->op == MicroInstrOpcode::Label)
                ++next;
            if (next + 2 >= order.size())
                continue;
            const auto* repeated = storage.ptr(order[next]);
            const auto* branch   = storage.ptr(order[next + 1]);
            if (!repeated || repeated->op != MicroInstrOpcode::CmpRegReg || !branch || branch->op != MicroInstrOpcode::JumpCond)
                continue;
            const auto* repeatedOps = repeated->ops(operands);
            const auto* branchOps   = branch->ops(operands);
            if (repeatedOps[0].reg != cmpOps[0].reg || repeatedOps[1].reg != cmpOps[1].reg || repeatedOps[2].opBits != cmpOps[2].opBits)
                continue;
            uint32_t targetId;
            if (branchOps[0].cpuCond == jumpOps[0].cpuCond)
            {
                if (!tryGetJumpTargetLabelId(targetId, *branch, branchOps) || targetId == joinId)
                    continue;
            }
            else if (branchOps[0].cpuCond == inverse)
            {
                const auto  pastRef = order[next + 2];
                const auto* known   = continuations.find(pastRef.get());
                if (known)
                    targetId = *known;
                else
                {
                    const auto* past = storage.ptr(pastRef);
                    if (!tryGetLabelId(targetId, *past, past->ops(operands)))
                    {
                        targetId = builder.createLabel().get();
                        MicroInstrOperand label[1];
                        label[0].valueU64 = targetId;
                        storage.insertDerivedBefore(operands, pastRef, MicroInstrOpcode::Label, label);
                    }
                    continuations.emplace(pastRef.get(), targetId);
                }
            }
            else
                continue;
            storage.ptr(jumpRef)->ops(operands)[2].valueU64 = targetId;
            changed                                         = true;
        }
        if (changed)
        {
            builder.invalidateControlFlowGraph();
            context.passChanged = true;
        }
        return changed;
    }

    // Thread a repeated indexed zero test when the two returns of an inlined
    // search already establish its result. A path through a read-only call is
    // admissible, but a write to the cell or either address register is not.
    bool threadRepeatedIndexedZeroTest(MicroPassContext& context, const std::vector<MicroInstrRef>& order)
    {
        MicroStorage&        storage    = *context.instructions;
        MicroOperandStorage& operands   = *context.operands;
        uint32_t             firstShape = 0;
        for (uint32_t at = 2; at + 3 < order.size(); ++at)
        {
            const MicroInstr* first = storage.ptr(order[at - 2]);
            if (!first || first->op != MicroInstrOpcode::Label)
                continue;
            const MicroInstr* second = storage.ptr(order[at - 1]);
            const MicroInstr* cmp    = storage.ptr(order[at]);
            const MicroInstr* jump   = storage.ptr(order[at + 1]);
            if (second && second->op == MicroInstrOpcode::Label &&
                cmp && cmp->op == MicroInstrOpcode::CmpAmcImm && jump && jump->op == MicroInstrOpcode::JumpCond)
            {
                firstShape = at;
                break;
            }
        }
        if (!firstShape)
            return false;
        const auto& cfg = context.builder->controlFlowGraph();
        if (cfg.hasUnsupportedControlFlowForCfgLiveness() || cfg.instructionCount() != order.size())
            return false;

        const auto isZeroCellCompare = [&](const MicroInstr* inst) {
            if (!inst || inst->op != MicroInstrOpcode::CmpAmcImm)
                return false;
            const auto* ops = inst->ops(operands);
            return ops && ops[2].opBits == MicroOpBits::B8 && ops[3].opBits == MicroOpBits::B64 &&
                   !ops[6].hasWideImmediateValue() && ops[6].valueU64 == 0 &&
                   ops[0].reg.isInt() && ops[1].reg.isInt();
        };
        const auto sameCell = [&](const MicroInstr* left, const MicroInstr* right) {
            if (!isZeroCellCompare(left) || !isZeroCellCompare(right))
                return false;
            const auto* a = left->ops(operands);
            const auto* b = right->ops(operands);
            return a[0].reg == b[0].reg && a[1].reg == b[1].reg &&
                   a[4].valueU64 == b[4].valueU64 && a[5].valueU64 == b[5].valueU64;
        };

        const auto readOnlyCallRefs = MicroPassHelpers::collectReadOnlyCallRefs(*context.builder);
        const auto isReadOnlyCall   = [&](const MicroInstrRef ref, const MicroInstr& inst) {
            return (inst.op == MicroInstrOpcode::CallLocal || inst.op == MicroInstrOpcode::CallExtern) && readOnlyCallRefs.contains(ref.get());
        };

        // The prefix before the first shape cannot match the detailed checks.
        for (uint32_t at = firstShape; at + 3 < order.size(); ++at)
        {
            const MicroInstr* emptyLabel = storage.ptr(order[at - 2]);
            if (!emptyLabel || emptyLabel->op != MicroInstrOpcode::Label)
                continue;
            const MicroInstr* matchLabel = storage.ptr(order[at - 1]);
            const MicroInstr* compare    = storage.ptr(order[at]);
            const MicroInstr* branch     = storage.ptr(order[at + 1]);
            uint32_t          emptyId    = 0;
            uint32_t          matchId    = 0;
            if (!matchLabel || matchLabel->op != MicroInstrOpcode::Label ||
                !tryGetLabelId(emptyId, *emptyLabel, emptyLabel->ops(operands)) ||
                !tryGetLabelId(matchId, *matchLabel, matchLabel->ops(operands)) ||
                !isZeroCellCompare(compare) || !branch || branch->op != MicroInstrOpcode::JumpCond)
                continue;
            const auto* branchOps = branch->ops(operands);
            if (!branchOps || (branchOps[0].cpuCond != MicroCond::Equal && branchOps[0].cpuCond != MicroCond::NotEqual) ||
                !MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*context.builder, order[at + 1]))
                continue;
            uint32_t branchTarget = 0;
            if (!tryGetJumpTargetLabelId(branchTarget, *branch, branchOps) ||
                branchTarget == emptyId || branchTarget == matchId)
                continue;
            const auto addressTaken = cfg.addressTakenLabelIndices();
            if (std::ranges::find(addressTaken, at - 2) != addressTaken.end() ||
                std::ranges::find(addressTaken, at - 1) != addressTaken.end())
                continue;

            // This rewrite removes matchLabel. Every explicit edge to it
            // must be a direct jump that the retargeting below can update.
            bool directMatchEdges = true;
            for (const uint32_t predecessor : cfg.predecessors(at - 1))
            {
                if (predecessor == at - 2)
                    continue;
                const MicroInstr* incoming = storage.ptr(order[predecessor]);
                uint32_t          target   = 0;
                if (!incoming || incoming->op != MicroInstrOpcode::JumpCond ||
                    !tryGetJumpTargetLabelId(target, *incoming, incoming->ops(operands)) || target != matchId)
                {
                    directMatchEdges = false;
                    break;
                }
            }
            if (!directMatchEdges)
                continue;

            const auto*                  cellOps = compare->ops(operands);
            uint32_t                     visits  = 0;
            std::unordered_set<uint64_t> visiting;
            const auto                   provesEdge = [&](auto&& self, const uint32_t predecessor, const uint32_t successor, const bool wantZero) -> bool {
                if (++visits > MicroOptimizationLimits::PostRALoopRotate::K_MAX_EDGE_PROOF_VISITS || predecessor >= order.size() || successor >= order.size())
                    return false;
                const uint64_t edge = (static_cast<uint64_t>(predecessor) << 32) | successor;
                if (!visiting.insert(edge).second)
                    return false;
                const MicroInstrRef ref  = order[predecessor];
                const MicroInstr*   inst = storage.ptr(ref);
                if (!inst)
                    return false;
                if (inst->op == MicroInstrOpcode::JumpCond && predecessor != 0)
                {
                    const MicroInstr* guard = storage.ptr(order[predecessor - 1]);
                    if (sameCell(guard, compare))
                    {
                        const auto* jumpOps = inst->ops(operands);
                        uint32_t    target  = 0;
                        if (jumpOps && tryGetJumpTargetLabelId(target, *inst, jumpOps) &&
                            (jumpOps[0].cpuCond == MicroCond::Equal || jumpOps[0].cpuCond == MicroCond::NotEqual))
                        {
                            const bool taken = cfg.indexOfLabel(target) == successor;
                            if (taken != (successor == predecessor + 1))
                            {
                                const bool zero = taken == (jumpOps[0].cpuCond == MicroCond::Equal);
                                visiting.erase(edge);
                                return zero == wantZero;
                            }
                        }
                    }
                }

                const auto flags = MicroInstr::info(inst->op).flags;
                if (flags.has(MicroInstrFlagsE::WritesMemory) ||
                    (flags.has(MicroInstrFlagsE::IsCallInstruction) && !isReadOnlyCall(ref, *inst)))
                    return false;
                const MicroInstrUseDef useDef = inst->collectUseDef(operands, context.encoder);
                for (const MicroReg def : useDef.defs)
                {
                    if (def == cellOps[0].reg || def == cellOps[1].reg)
                        return false;
                }
                const auto& incoming = cfg.predecessors(predecessor);
                if (incoming.empty())
                    return false;
                for (const uint32_t prior : incoming)
                {
                    if (!self(self, prior, predecessor, wantZero))
                        return false;
                }
                visiting.erase(edge);
                return true;
            };

            bool safe = !cfg.predecessors(at - 2).empty() && !cfg.predecessors(at - 1).empty();
            for (const uint32_t predecessor : cfg.predecessors(at - 2))
            {
                visits = 0;
                visiting.clear();
                safe &= provesEdge(provesEdge, predecessor, at - 2, true);
            }
            bool hasMatchJump = false;
            for (const uint32_t predecessor : cfg.predecessors(at - 1))
            {
                if (predecessor == at - 2)
                    continue; // the empty fallthrough is removed by this rewrite
                hasMatchJump = true;
                visits       = 0;
                visiting.clear();
                safe &= provesEdge(provesEdge, predecessor, at - 1, false);
            }
            if (!safe || !hasMatchJump)
                continue;

            const MicroInstr* afterBranch = storage.ptr(order[at + 2]);
            uint32_t          fallthrough = 0;
            const bool        needsLabel  = afterBranch->op != MicroInstrOpcode::Label || !tryGetLabelId(fallthrough, *afterBranch, afterBranch->ops(operands));
            if (needsLabel)
                fallthrough = context.builder->createLabel().get();
            const uint32_t          zeroTarget    = branchOps[0].cpuCond == MicroCond::Equal ? branchTarget : fallthrough;
            const uint32_t          nonzeroTarget = branchOps[0].cpuCond == MicroCond::Equal ? fallthrough : branchTarget;
            const MicroInstrOperand branchSize    = branchOps[1];

            // Every incoming jump was proved above. The empty edge that falls
            // out of the probe's last comparison still arrives at emptyLabel.
            for (const MicroInstrRef ref : order)
            {
                MicroInstr* inst = storage.ptr(ref);
                if (!inst || inst->op != MicroInstrOpcode::JumpCond)
                    continue;
                MicroInstrOperand* ops    = inst->ops(operands);
                uint32_t           target = 0;
                if (!tryGetJumpTargetLabelId(target, *inst, ops))
                    continue;
                if (target == emptyId)
                    ops[2].valueU64 = zeroTarget;
                else if (target == matchId)
                    ops[2].valueU64 = nonzeroTarget;
            }
            if (needsLabel)
            {
                MicroInstrOperand labelOps[1];
                labelOps[0].valueU64 = fallthrough;
                storage.insertDerivedBefore(operands, order[at + 2], MicroInstrOpcode::Label, labelOps);
            }
            if (zeroTarget != fallthrough)
            {
                MicroInstrOperand jumpOps[3] = {};
                jumpOps[0].cpuCond           = MicroCond::Unconditional;
                jumpOps[1]                   = branchSize;
                jumpOps[2].valueU64          = zeroTarget;
                storage.insertDerivedBefore(operands, order[at - 1], MicroInstrOpcode::JumpCond, jumpOps);
            }
            storage.erase(order[at - 1]);
            storage.erase(order[at]);
            storage.erase(order[at + 1]);
            context.builder->invalidateControlFlowGraph();
            context.passChanged = true;
            return true;
        }
        return false;
    }

    // Move flag-neutral preparations behind the latch's taken back edge. An
    // entry jump skips them on the first iteration; later iterations execute
    // them at the same point as before, then fall into the body. The exit path
    // still skips them, even when their results are live beyond the loop.
    bool rotateLatchConnectors(MicroPassContext& context, const std::vector<MicroInstrRef>& order)
    {
        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;

        std::optional<std::unordered_map<uint32_t, uint32_t>> labels;

        for (uint32_t i = 0; i + 3 < order.size(); ++i)
        {
            const MicroInstr* cmp = storage.ptr(order[i]);
            if (!cmp || cmp->op != MicroInstrOpcode::CmpRegImm)
                continue;
            const MicroInstr* jcc = storage.ptr(order[i + 1]);
            if (!jcc || jcc->op != MicroInstrOpcode::JumpCond)
                continue;
            const auto* jccOps = jcc->ops(operands);
            if (!jccOps || jcc->numOperands < 3 || jccOps[0].cpuCond == MicroCond::Unconditional)
                continue;
            MicroCond inverted = MicroCond::Unconditional;
            if (!MicroPassHelpers::invertLayoutBranchCondition(inverted, jccOps[0].cpuCond))
                continue;

            uint32_t exitId = 0;
            if (!tryGetJumpTargetLabelId(exitId, *jcc, jccOps))
                continue;

            if (!labels)
            {
                auto& labelOrdinals = labels.emplace();
                for (uint32_t labelOrdinal = 0; labelOrdinal < order.size(); ++labelOrdinal)
                {
                    const MicroInstr* inst = storage.ptr(order[labelOrdinal]);
                    if (!inst || inst->op != MicroInstrOpcode::Label)
                        continue;
                    uint32_t id = 0;
                    if (tryGetLabelId(id, *inst, inst->ops(operands)))
                        labelOrdinals[id] = labelOrdinal;
                }
            }

            const auto exitIt = labels->find(exitId);
            if (exitIt == labels->end() || exitIt->second <= i + 2)
                continue;
            const uint32_t    backIndex = exitIt->second - 1;
            const MicroInstr* back      = storage.ptr(order[backIndex]);
            if (!back || back->op != MicroInstrOpcode::JumpCond || back->numOperands < 3)
                continue;
            const auto* backOps = back->ops(operands);
            if (!backOps || backOps[0].cpuCond != MicroCond::Unconditional ||
                backOps[2].valueU64 > std::numeric_limits<uint32_t>::max())
                continue;
            const auto bodyIt = labels->find(static_cast<uint32_t>(backOps[2].valueU64));
            if (bodyIt == labels->end() || bodyIt->second >= i)
                continue;

            bool safe = true;
            for (uint32_t connectorIndex = i + 2; connectorIndex < backIndex; ++connectorIndex)
            {
                const MicroInstr* connector = storage.ptr(order[connectorIndex]);
                if (!connector || !isDuplicableConnector(*connector))
                {
                    safe = false;
                    break;
                }
            }
            if (!safe)
                continue;

            const MicroInstrRef bodyRef     = order[bodyIt->second];
            const uint64_t      prepId      = context.builder->createLabel().get();
            MicroInstrOperand   entryOps[3] = {backOps[0], backOps[1], backOps[2]};
            MicroInstrOperand   prepOps[1];
            prepOps[0].valueU64 = prepId;
            storage.insertDerivedBefore(operands, bodyRef, MicroInstrOpcode::JumpCond, entryOps);
            storage.insertDerivedBefore(operands, bodyRef, MicroInstrOpcode::Label, prepOps);
            for (uint32_t connectorIndex = i + 2; connectorIndex < backIndex; ++connectorIndex)
            {
                const MicroInstrRef               oldRef  = order[connectorIndex];
                const MicroInstr*                 oldInst = storage.ptr(oldRef);
                SmallVector<MicroInstrOperand, 8> copy;
                for (uint32_t op = 0; op < oldInst->numOperands; ++op)
                    copy.push_back(oldInst->ops(operands)[op]);
                const MicroInstrRef newRef = storage.insertDerivedBefore(operands, bodyRef, oldInst->op, {copy.data(), copy.size()});
                for (auto& relocation : context.builder->codeRelocations())
                {
                    if (relocation.instructionRef == oldRef)
                        relocation.instructionRef = newRef;
                }
                storage.erase(oldRef);
            }
            MicroInstrOperand* rewrittenOps = storage.ptr(order[i + 1])->ops(operands);
            rewrittenOps[0].cpuCond         = inverted;
            rewrittenOps[2].valueU64        = prepId;
            storage.erase(order[backIndex]);
            context.builder->invalidateControlFlowGraph();
            context.passChanged = true;
            return true;
        }
        return false;
    }

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
        MicroStorage&                                         storage  = *context.instructions;
        MicroOperandStorage&                                  operands = *context.operands;
        std::optional<std::unordered_map<uint64_t, uint32_t>> labelOrdinals;
        const auto                                            findLabel = [&](const uint64_t id, const uint32_t endOrdinal) {
            if (!labelOrdinals)
            {
                auto& labels = labelOrdinals.emplace();
                for (uint32_t index = 0; index < order.size(); ++index)
                {
                    const MicroInstr* inst = storage.ptr(order[index]);
                    if (inst && inst->op == MicroInstrOpcode::Label)
                        labels.try_emplace(inst->ops(operands)[0].valueU64, index);
                }
            }
            const auto it = labelOrdinals->find(id);
            if (it != labelOrdinals->end() && it->second < endOrdinal)
                return it->second;
            return static_cast<uint32_t>(order.size());
        };

        for (uint32_t ordinal = 0; ordinal + 4 < order.size(); ++ordinal)
        {
            const MicroInstrRef firstRef  = order[ordinal];
            const MicroInstrRef secondRef = order[ordinal + 1];
            const MicroInstrRef skipRef   = order[ordinal + 2];
            const MicroInstrRef tieRef    = order[ordinal + 3];
            const MicroInstr*   first     = storage.ptr(firstRef);
            if (!first || first->op != MicroInstrOpcode::JumpCond || first->numOperands < 3)
                continue;
            const MicroInstr* second = storage.ptr(secondRef);
            const MicroInstr* skip   = storage.ptr(skipRef);
            const MicroInstr* tie    = storage.ptr(tieRef);
            if (!second || !skip || !tie ||
                second->op != MicroInstrOpcode::JumpCond ||
                skip->op != MicroInstrOpcode::JumpCond || tie->op != MicroInstrOpcode::Label ||
                second->numOperands < 3 || skip->numOperands < 3)
                continue;
            const auto* firstOps  = first->ops(operands);
            const auto* secondOps = second->ops(operands);
            const auto* skipOps   = skip->ops(operands);
            const auto* tieOps    = tie->ops(operands);
            if (!firstOps || !secondOps || !skipOps || !tieOps ||
                firstOps[0].cpuCond == MicroCond::Unconditional ||
                secondOps[0].cpuCond == MicroCond::Unconditional ||
                skipOps[0].cpuCond != MicroCond::Unconditional ||
                firstOps[2].valueU64 != tieOps[0].valueU64)
                continue;
            MicroCond inverted = MicroCond::Unconditional;
            if (!MicroPassHelpers::invertLayoutBranchCondition(inverted, secondOps[0].cpuCond))
                continue;

            const uint32_t stepOrdinal = findLabel(secondOps[2].valueU64, static_cast<uint32_t>(order.size()));
            if (stepOrdinal <= ordinal + 4 ||
                stepOrdinal + 3 >= order.size())
                continue;
            const MicroInstrRef stepLabelRef = order[stepOrdinal];
            const MicroInstrRef updateRef    = order[stepOrdinal + 1];
            const MicroInstrRef backRef      = order[stepOrdinal + 2];
            const MicroInstr*   update       = storage.ptr(updateRef);
            const MicroInstr*   back         = storage.ptr(backRef);
            const MicroInstr*   stop         = storage.ptr(order[stepOrdinal + 3]);
            if (!update || !back || !stop ||
                update->op != MicroInstrOpcode::OpBinaryRegImm || back->op != MicroInstrOpcode::JumpCond ||
                stop->op != MicroInstrOpcode::Label || update->numOperands < 4 || back->numOperands < 3)
                continue;
            const auto*       updateOps  = update->ops(operands);
            const auto*       backOps    = back->ops(operands);
            const auto*       stopOps    = stop->ops(operands);
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
            if (findLabel(backOps[2].valueU64, ordinal) >= ordinal)
                continue;

            // Capture operands before insertions can grow their storage.
            std::array<MicroInstrOperand, 3> rewritten     = {secondOps[0], secondOps[1], secondOps[2]};
            rewritten[0].cpuCond                           = inverted;
            rewritten[2].valueU64                          = skipOps[2].valueU64;
            std::array<MicroInstrOperand, 3> jumpToStep    = {backOps[0], backOps[1], backOps[2]};
            jumpToStep[2].valueU64                         = secondOps[2].valueU64;
            std::array<MicroInstrOperand, 4> updateCopy    = {updateOps[0], updateOps[1], updateOps[2], updateOps[3]};
            const MicroInstrOperand          stepLabelCopy = storage.ptr(stepLabelRef)->ops(operands)[0];
            std::array<MicroInstrOperand, 3> backCopy      = {backOps[0], backOps[1], backOps[2]};
            const MicroInstrOpcode           updateOpcode  = update->op;
            const MicroInstrOpcode           backOpcode    = back->op;

            storage.insertDerivedBefore(operands, tieRef, MicroInstrOpcode::Label, std::span(&stepLabelCopy, 1));
            storage.insertDerivedBefore(operands, tieRef, updateOpcode, updateCopy);
            storage.insertDerivedBefore(operands, tieRef, backOpcode, backCopy);
            storage.insertDerivedBefore(operands, order[stepOrdinal + 3], MicroInstrOpcode::JumpCond, jumpToStep);
            MicroInstr*        rewrittenSecond = storage.ptr(secondRef);
            MicroInstrOperand* rewrittenOps    = rewrittenSecond->ops(operands);
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

    // A two-way count comparison can place its advancing step before the
    // header. Mismatches then branch backward to the step and fall through
    // the next comparison, instead of paying an unconditional back edge on
    // every advance. The one-time entry jumps over that step.
    bool placeMismatchStepBeforeHeader(MicroPassContext& context, const std::vector<MicroInstrRef>& order)
    {
        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;
        for (uint32_t header = 0; header + 9 < order.size(); ++header)
        {
            const MicroInstr*        headerInst = storage.ptr(order[header]);
            const MicroInstrOperand* headerOps  = headerInst ? headerInst->ops(operands) : nullptr;
            if (!headerInst || headerInst->op != MicroInstrOpcode::Label || !headerOps)
                continue;

            for (uint32_t loads = 1; loads <= 2; ++loads)
            {
                const uint32_t compare = header + 1 + loads;
                if (compare + 6 >= order.size())
                    break;
                // Earlier iterations proved the prefix. A failed next load
                // also rules out every longer prefix at this header.
                if (storage.ptr(order[compare - 1])->op != MicroInstrOpcode::LoadAmcRegMem)
                    break;

                const MicroInstr* cmp = storage.ptr(order[compare]);
                if (!cmp || (cmp->op != MicroInstrOpcode::CmpAmcReg && cmp->op != MicroInstrOpcode::CmpRegReg))
                    continue;
                const MicroInstr* equal       = storage.ptr(order[compare + 1]);
                const MicroInstr* lessOrEqual = storage.ptr(order[compare + 2]);
                const MicroInstr* stepLabel   = storage.ptr(order[compare + 3]);
                const MicroInstr* update      = storage.ptr(order[compare + 4]);
                const MicroInstr* back        = storage.ptr(order[compare + 5]);
                const MicroInstr* tieLabel    = storage.ptr(order[compare + 6]);
                if (!equal || !lessOrEqual || !stepLabel || !update || !back || !tieLabel ||
                    equal->op != MicroInstrOpcode::JumpCond || lessOrEqual->op != MicroInstrOpcode::JumpCond ||
                    stepLabel->op != MicroInstrOpcode::Label || update->op != MicroInstrOpcode::OpBinaryRegImm ||
                    back->op != MicroInstrOpcode::JumpCond || tieLabel->op != MicroInstrOpcode::Label ||
                    equal->numOperands < 3 || lessOrEqual->numOperands < 3 ||
                    update->numOperands < 4 || back->numOperands < 3)
                    continue;

                const MicroInstrOperand* equalOps  = equal->ops(operands);
                const MicroInstrOperand* lessOps   = lessOrEqual->ops(operands);
                const MicroInstrOperand* stepOps   = stepLabel->ops(operands);
                const MicroInstrOperand* updateOps = update->ops(operands);
                const MicroInstrOperand* backOps   = back->ops(operands);
                const MicroInstrOperand* tieOps    = tieLabel->ops(operands);
                if (!equalOps || !lessOps || !stepOps || !updateOps || !backOps || !tieOps ||
                    equalOps[0].cpuCond != MicroCond::Equal || lessOps[0].cpuCond != MicroCond::BelowOrEqual ||
                    equalOps[2].valueU64 != tieOps[0].valueU64 ||
                    backOps[0].cpuCond != MicroCond::Unconditional || backOps[2].valueU64 != headerOps[0].valueU64 ||
                    (updateOps[2].microOp != MicroOp::Add && updateOps[2].microOp != MicroOp::Subtract) ||
                    updateOps[1].opBits != MicroOpBits::B64 || updateOps[3].valueU64 != 1)
                    continue;

                const uint64_t    mismatchLabelId = context.builder->createLabel().get();
                MicroInstrOperand entryJump[3]    = {backOps[0], backOps[1], backOps[2]};
                MicroInstrOperand mismatchLabelOps[1];
                mismatchLabelOps[0].valueU64      = mismatchLabelId;
                MicroInstrOperand exitJump[3]     = {lessOps[0], lessOps[1], lessOps[2]};
                MicroInstrOperand stepLabelOps[1] = {stepOps[0]};
                MicroInstrOperand updateCopy[4]   = {updateOps[0], updateOps[1], updateOps[2], updateOps[3]};

                storage.insertDerivedBefore(operands, order[header], MicroInstrOpcode::JumpCond, entryJump);
                storage.insertDerivedBefore(operands, order[header], MicroInstrOpcode::Label, mismatchLabelOps);
                storage.insertDerivedBefore(operands, order[header], MicroInstrOpcode::JumpCond, exitJump);
                storage.insertDerivedBefore(operands, order[header], MicroInstrOpcode::Label, stepLabelOps);
                storage.insertDerivedBefore(operands, order[header], MicroInstrOpcode::OpBinaryRegImm, updateCopy);

                MicroInstr*        rewrittenEqual = storage.ptr(order[compare + 1]);
                MicroInstrOperand* rewrittenOps   = rewrittenEqual->ops(operands);
                rewrittenOps[0].cpuCond           = MicroCond::NotEqual;
                rewrittenOps[2].valueU64          = mismatchLabelId;
                storage.erase(order[compare + 2]);
                storage.erase(order[compare + 3]);
                storage.erase(order[compare + 4]);
                storage.erase(order[compare + 5]);
                context.builder->invalidateControlFlowGraph();
                context.passChanged = true;
                return true;
            }
        }
        return false;
    }
}

namespace
{
    struct ScanReloadQuery
    {
        MicroInstrRef load;
        MicroInstrRef compare;
        MicroInstrRef exit;
        MicroReg      value;
        MicroReg      base;
        MicroReg      index;
        MicroOpBits   bits;
    };

    MicroInstrRef scanReloadFrontier(const MicroPassContext& context, const ScanReloadQuery& query)
    {
        const auto& cfg = context.builder->controlFlowGraph();
        if (!cfg.supportsDeadCodeLiveness() || cfg.hasUnsupportedControlFlowForCfgLiveness())
            return MicroInstrRef::invalid();
        const auto refs = cfg.instructionRefs();
        const auto at   = cfg.indexOf(query.exit);
        if (at == MicroControlFlowGraph::K_NO_INDEX)
            return MicroInstrRef::invalid();
        SmallVector<uint8_t, 128> visited(refs.size(), 0);
        SmallVector<uint32_t>     pending;
        pending.push_back(at);
        MicroInstrRef frontier;
        while (!pending.empty())
        {
            const auto i = pending.back();
            pending.pop_back();
            if (visited[i])
                continue;
            visited[i]              = 1;
            const auto* instruction = context.instructions->ptr(refs[i]);
            if (!instruction)
                return MicroInstrRef::invalid();
            const auto  touch   = MicroPassHelpers::regTouch(*instruction, *context.operands, query.value, context.encoder);
            const auto& info    = MicroInstr::info(instruction->op);
            const auto* ops     = instruction->ops(*context.operands);
            const auto  written = touch.def ? MicroPassHelpers::integerResultBits(*instruction, ops) : 0;
            if (!touch.use && touch.def && (written >= 32 || written >= getNumBits(query.bits)))
                continue;
            const bool boundary = touch.use || touch.def || instruction->op == MicroInstrOpcode::Ret || info.flags.has(MicroInstrFlagsE::WritesMemory) || info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                                  instruction->op == MicroInstrOpcode::Push || instruction->op == MicroInstrOpcode::Pop ||
                                  MicroPassHelpers::regTouch(*instruction, *context.operands, query.base, context.encoder).def ||
                                  MicroPassHelpers::regTouch(*instruction, *context.operands, query.index, context.encoder).def;
            if (boundary)
            {
                if (frontier.isValid() && frontier != refs[i])
                    return MicroInstrRef::invalid();
                frontier = refs[i];
                continue;
            }
            for (const auto next : cfg.successors(i))
                pending.push_back(next);
        }
        return frontier;
    }

    // Every incoming path must carry the same original read and address to
    // this point. A killed-value path can merge back here, and a frontier in
    // another loop can execute again after a write: dominance alone proves
    // neither property. Trace all predecessors up to the original load.
    bool scanReloadIsEquivalent(const MicroPassContext& context, const ScanReloadQuery& query, MicroInstrRef before)
    {
        const auto& cfg  = context.builder->controlFlowGraph();
        const auto  refs = cfg.instructionRefs();
        const auto  at   = cfg.indexOf(before);
        if (at == MicroControlFlowGraph::K_NO_INDEX || cfg.singleEntry() == MicroControlFlowGraph::K_NO_INDEX)
            return false;
        SmallVector<uint8_t, 128> visited(refs.size(), 0);
        SmallVector<uint32_t>     pending;
        for (const auto previous : cfg.predecessors(at))
            pending.push_back(previous);
        bool reachedLoad = false;
        while (!pending.empty())
        {
            const auto i = pending.back();
            pending.pop_back();
            if (refs[i] == query.load)
            {
                reachedLoad = true;
                continue;
            }
            if (i == at)
                return false;
            if (visited[i])
                continue;
            visited[i]              = 1;
            const auto* instruction = context.instructions->ptr(refs[i]);
            if (!instruction)
                return false;
            const auto& info       = MicroInstr::info(instruction->op);
            const auto  valueTouch = MicroPassHelpers::regTouch(*instruction, *context.operands, query.value, context.encoder);
            if (valueTouch.def || (valueTouch.use && refs[i] != query.compare) ||
                info.flags.has(MicroInstrFlagsE::WritesMemory) || info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                instruction->op == MicroInstrOpcode::Push || instruction->op == MicroInstrOpcode::Pop ||
                MicroPassHelpers::regTouch(*instruction, *context.operands, query.base, context.encoder).def ||
                MicroPassHelpers::regTouch(*instruction, *context.operands, query.index, context.encoder).def ||
                cfg.predecessors(i).empty())
                return false;
            for (const auto previous : cfg.predecessors(i))
                pending.push_back(previous);
        }
        return reachedLoad;
    }

    // Keep only the comparison in a read-only scan. The final value is loaded
    // where it is first observed, before any memory or address change; paths
    // that discard it need no reload. The scan loses a separate load instruction
    // and its memory compare can fuse with the conditional branch.
    bool sinkScanCompareValue(MicroPassContext& context)
    {
        if (!context.encoder || !context.builder->backendBuildCfg().runsCostlyOptimizations())
            return false;
        auto&                      storage  = *context.instructions;
        auto&                      operands = *context.operands;
        std::vector<MicroInstrRef> order;
        order.reserve(storage.count());
        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
            order.push_back(it.current);
        MicroPassHelpers::MicroPhysLiveness liveness;
        bool                                analyzed = false;
        for (size_t at = 0; at + 6 < order.size(); ++at)
        {
            const auto* header  = storage.ptr(order[at]);
            const auto* load    = storage.ptr(order[at + 1]);
            const auto* compare = storage.ptr(order[at + 2]);
            const auto* leave   = storage.ptr(order[at + 3]);
            const auto* step    = storage.ptr(order[at + 4]);
            const auto* back    = storage.ptr(order[at + 5]);
            const auto* exit    = storage.ptr(order[at + 6]);
            if (header->op != MicroInstrOpcode::Label || load->op != MicroInstrOpcode::LoadAmcRegMem ||
                compare->op != MicroInstrOpcode::CmpRegReg || leave->op != MicroInstrOpcode::JumpCond ||
                back->op != MicroInstrOpcode::JumpCond || exit->op != MicroInstrOpcode::Label)
                continue;
            const auto* h     = header->ops(operands);
            const auto* l     = load->ops(operands);
            const auto* c     = compare->ops(operands);
            const auto* j     = leave->ops(operands);
            const auto* s     = step->ops(operands);
            const auto* b     = back->ops(operands);
            const auto* e     = exit->ops(operands);
            const auto  value = l[0].reg;
            const auto  base  = l[1].reg;
            const auto  index = l[2].reg;
            if (!value.isInt() || !base.isInt() || !index.isInt() || !c[1].reg.isInt() ||
                c[0].reg != value || value == base || value == index || value == c[1].reg ||
                l[3].opBits != c[2].opBits || l[4].opBits != MicroOpBits::B64 ||
                j[0].cpuCond == MicroCond::Unconditional || j[2].valueU64 != e[0].valueU64 ||
                b[0].cpuCond != MicroCond::Unconditional || b[2].valueU64 != h[0].valueU64)
                continue;
            bool unitStep = false;
            if (step->op == MicroInstrOpcode::OpUnaryReg)
                unitStep = s[0].reg == index && s[1].opBits == MicroOpBits::B64 && (s[2].microOp == MicroOp::Add || s[2].microOp == MicroOp::Subtract);
            else if (step->op == MicroInstrOpcode::OpBinaryRegImm)
                unitStep = s[0].reg == index && s[1].opBits == MicroOpBits::B64 &&
                           (s[2].microOp == MicroOp::Add || s[2].microOp == MicroOp::Subtract) && !s[3].hasWideImmediateValue() && s[3].valueU64 == 1;
            if (!unitStep)
                continue;
            if (!analyzed)
            {
                MicroPassHelpers::computePhysicalLiveness(liveness, context, MicroPassHelpers::MicroPhysLivenessMode::LiveOutOnly);
                analyzed = true;
            }
            const auto& cfg = context.builder->controlFlowGraph();
            if (!liveness.valid || !liveness.isLiveOut(cfg.indexOf(order[at + 6]), value))
                continue;
            const ScanReloadQuery query{order[at + 1], order[at + 2], order[at + 6], value, base, index, l[3].opBits};
            const auto            before = scanReloadFrontier(context, query);
            if (before.isInvalid() || !scanReloadIsEquivalent(context, query, before))
                continue;
            const auto dom = MicroPassHelpers::computeInstructionDominators(cfg, cfg.singleEntry());
            if (!dom.dominates(cfg.indexOf(order[at + 1]), cfg.indexOf(before)))
                continue;
            std::array<MicroInstrOperand, 7> savedLoad;
            std::copy_n(l, 7, savedLoad.begin());
            MicroInstrOperand memoryCompare[7] = {};
            memoryCompare[0].reg               = base;
            memoryCompare[1].reg               = index;
            memoryCompare[2]                   = c[1];
            memoryCompare[3]                   = l[4];
            memoryCompare[4]                   = c[2];
            memoryCompare[5]                   = l[5];
            memoryCompare[6]                   = l[6];
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::LoadAmcRegMem, savedLoad);
            storage.insertDerivedBefore(operands, order[at + 2], MicroInstrOpcode::CmpAmcReg, memoryCompare);
            storage.erase(order[at + 1]);
            storage.erase(order[at + 2]);
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
    if (storage.count() < 4)
        return Result::Continue;

    // Finish every scan split before indexing rotations: consuming one post-RA
    // sweep per scan could otherwise leave unrelated loops unrotated.
    while (sinkScanCompareValue(context))
    {
    }

    // Recognition does not mutate the listing. Index all incoming jumps once;
    // every header can then check its unique back edge without rescanning the function.
    struct JumpTarget
    {
        uint32_t count   = 0;
        uint32_t ordinal = 0;
    };
    // One flat table: this runs in every post-RA sweep of every function, and a node-based
    // map allocated for each jump target.
    FlatKeyMap<JumpTarget>     jumpsByTarget;
    std::vector<MicroInstrRef> order;
    bool                       hasJumpCond = false;
    order.reserve(storage.count());
    for (auto it = storage.view().begin(), endIt = storage.view().end(); it != endIt; ++it)
    {
        const auto ordinal = static_cast<uint32_t>(order.size());
        order.push_back(it.current);
        if (it->op != MicroInstrOpcode::JumpCond)
            continue;
        hasJumpCond     = true;
        uint32_t target = 0;
        if (!tryGetJumpTargetLabelId(target, *it, it->ops(operands)))
            continue;
        JumpTarget& incoming = jumpsByTarget.getOrInsert(target);
        ++incoming.count;
        incoming.ordinal = ordinal;
    }

    if (!hasJumpCond)
        return Result::Continue;

    if (unrollBoundedByteScan(context, order))
        return Result::Continue;
    if (peelOpposingIndexSwaps(context, order))
        return Result::Continue;
    if (threadRepeatedCompareExits(context, order))
        return Result::Continue;
    if (threadRepeatedIndexedZeroTest(context, order))
        return Result::Continue;
    if (placeShortLoopStep(context, order))
        return Result::Continue;
    if (placeMismatchStepBeforeHeader(context, order))
        return Result::Continue;
    if (rotateLatchConnectors(context, order))
        return Result::Continue;

    // Every rotation needs an incoming jump to its header.
    if (!jumpsByTarget.size())
        return Result::Continue;

    SmallVector<Rotation> rotations;

    for (uint32_t ordinal = 0; ordinal + 3 < order.size(); ++ordinal)
    {
        const MicroInstr* labelInst = storage.ptr(order[ordinal]);
        if (!labelInst || labelInst->op != MicroInstrOpcode::Label)
            continue;
        uint32_t labelId = 0;
        if (!tryGetLabelId(labelId, *labelInst, labelInst->ops(operands)))
            continue;

        // A header without one incoming jump cannot rotate, regardless of
        // its test run. The incoming-jump index stays fixed during recognition.
        const JumpTarget* incoming = jumpsByTarget.find(labelId);
        if (!incoming || incoming->count != 1)
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
            // A compare or test defines only flags. Copying an arithmetic instruction would
            // also copy its value definition.
            if (MicroInstr::isCompareOrTest(testInst->op))
            {
                if (haveTest)
                    break;
                haveTest = true;
            }
            else if (!isDuplicableHeaderConnector(*testInst))
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
        const uint32_t backOrdinal = incoming->ordinal;
        if (backOrdinal <= testEnd)
            continue;
        const MicroInstrRef      backRef  = order[backOrdinal];
        const MicroInstr*        backInst = storage.ptr(backRef);
        const MicroInstrOperand* backOps  = backInst->ops(operands);
        if (backOps[0].cpuCond != MicroCond::Unconditional)
            continue;

        // Falling out of the rotated back edge must reach the same exit as the
        // header test. Adjacent labels may name that exit, or an unconditional
        // jump may forward to it without doing any work on the fallthrough.
        if (backOrdinal + 1 >= order.size())
            continue;
        bool exitsAfterBack = false;
        for (uint32_t after = backOrdinal + 1; after < order.size(); ++after)
        {
            const MicroInstr* afterInst = storage.ptr(order[after]);
            uint32_t          afterId   = 0;
            if (!afterInst)
                break;
            const MicroInstrOperand* afterOps = afterInst->ops(operands);
            if (tryGetLabelId(afterId, *afterInst, afterOps))
            {
                if (afterId == exitLabelId)
                    exitsAfterBack = true;
                continue;
            }
            if (!exitsAfterBack && afterInst->op == MicroInstrOpcode::JumpCond && afterOps &&
                afterOps[0].cpuCond == MicroCond::Unconditional &&
                tryGetJumpTargetLabelId(afterId, *afterInst, afterOps) && afterId == exitLabelId)
                exitsAfterBack = true;
            break;
        }
        if (!exitsAfterBack)
            continue;

        MicroCond inverted = MicroCond::Unconditional;
        if (!MicroPassHelpers::invertLayoutBranchCondition(inverted, cond))
            continue;

        rotations.push_back({.testBegin = testBegin, .testEnd = testEnd, .jccRef = jccRef, .bodyFirstRef = order[testEnd + 1], .backRef = backRef, .inverted = inverted});
    }

    if (rotations.empty())
        return Result::Continue;

    // A copied RIP-relative connector needs its own relocation. Keep a
    // snapshot because inserting the copies grows the builder's relocation
    // vector while rotations are applied.
    std::unordered_map<uint32_t, SmallVector<MicroRelocation, 2>> relocationsByRef;
    for (const MicroRelocation& reloc : context.builder->codeRelocations())
    {
        if (reloc.instructionRef.isValid())
            relocationsByRef[reloc.instructionRef.get()].push_back(reloc);
    }

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
            testCopy.append(testOps, testInst->numOperands);
            const MicroInstrOpcode testOp  = testInst->op;
            const MicroInstrRef    copyRef = storage.insertDerivedBefore(operands, rotation.backRef, testOp, {testCopy.data(), testCopy.size()});
            const auto             relocIt = relocationsByRef.find(order[ordinal].get());
            if (relocIt != relocationsByRef.end())
            {
                for (MicroRelocation reloc : relocIt->second)
                {
                    reloc.instructionRef = copyRef;
                    context.builder->addRelocation(reloc);
                }
            }
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
