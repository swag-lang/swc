#include "pch.h"
#include "Backend/Micro/Passes/Pass.InductionVariable.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Report/Assert.h"

// See the header for the contract. An induction is a register with one
// definition inside the loop, `add r, step` where the step is an immediate or
// a register the loop never writes. The shapes the lowering produces from one,
// and what each becomes:
//
//     mov  t, i                  ->  mov t, acc          with, in the preheader,
//     imul t, stride                 (erased)            mov acc, i / imul acc, stride
//                                                        and behind `add i, step`,
//     mov  t, i                  ->  mov t, acc          add acc, stride * step
//     imul t, C  |  shl t, k         (erased)
//
//     t = i * stride             ->  mov t, acc          (three-operand form)
//
//     mov  t, base               ->  mov t, p            with, in the preheader,
//     add  t, acc                    (erased)            mov p, base / add p, acc
//                                                        and behind `add acc, delta`,
//     t = base + acc             ->  mov t, p            add p, delta
//     t = &[base + acc + disp]   ->  mov t, p
//
// The second family carries a pointer: it applies when every use of the
// induction is such a sum, so the induction itself dies with them and the
// loop carries the pointer in its place; the accumulator of the first family
// then leaves no register behind. The values move together because they only
// ever change at one point.

SWC_BEGIN_NAMESPACE();

namespace
{
    using NaturalLoop = MicroPassHelpers::NaturalLoop;

    constexpr uint32_t K_INVALID = std::numeric_limits<uint32_t>::max();

    bool isMultiplyOp(const MicroOp op)
    {
        return op == MicroOp::MultiplySigned || op == MicroOp::MultiplyUnsigned;
    }

    bool isStepOp(const MicroOp op)
    {
        return op == MicroOp::Add || op == MicroOp::Subtract;
    }

    bool isCounterBits(const MicroOpBits bits)
    {
        return bits == MicroOpBits::B32 || bits == MicroOpBits::B64;
    }

    bool fitsSigned32(const int64_t value)
    {
        return value >= std::numeric_limits<int32_t>::min() && value <= std::numeric_limits<int32_t>::max();
    }

    // Truncates a value to the induction's width, as the machine does.
    uint64_t wrapToBits(const uint64_t value, const MicroOpBits bits)
    {
        return bits == MicroOpBits::B32 ? (value & 0xFFFFFFFFull) : value;
    }

    // A register the loop steps once: `add reg, imm` or `add reg, invariant`.
    struct Induction
    {
        MicroReg      reg     = MicroReg::invalid();
        MicroInstrRef stepRef = MicroInstrRef::invalid();
        MicroOpBits   bits    = MicroOpBits::Zero;
        MicroOp       stepOp  = MicroOp::Add;
        MicroReg      stepReg = MicroReg::invalid(); // invalid when the step is an immediate
        uint64_t      stepImm = 0;                   // the magnitude, positive
    };

    enum class Shape : uint8_t
    {
        CopyThenOp,   // `mov t, a` followed by the destructive op on t
        ThreeOperand, // `t = a op b`
        AddressOfSum, // `t = &[a + b + disp]`
    };

    // One product or sum of an induction found in the body.
    struct Candidate
    {
        Shape         shape       = Shape::CopyThenOp;
        MicroInstrRef firstRef    = MicroInstrRef::invalid(); // the copy, or the whole instruction
        MicroInstrRef secondRef   = MicroInstrRef::invalid(); // the destructive op, CopyThenOp only
        MicroReg      dstReg      = MicroReg::invalid();
        uint32_t      inductionIx = K_INVALID;
        bool          isSum       = false;
        MicroReg      otherReg    = MicroReg::invalid(); // the invariant stride or base; invalid for an immediate stride
        uint64_t      otherImm    = 0;                   // the immediate stride, or the sum's displacement
        MicroOp       mulOp       = MicroOp::MultiplySigned;
        MicroInstrRef copyOfInductionRef = MicroInstrRef::invalid(); // a sum's copy of the induction, erased with the sum
    };

    // The register that carries one (induction, other, displacement) family.
    struct Carrier
    {
        MicroReg reg         = MicroReg::invalid();
        uint32_t inductionIx = K_INVALID;
        bool     isSum       = false;
        MicroReg otherReg    = MicroReg::invalid();
        uint64_t otherImm    = 0;
    };

    bool sameFamily(const Carrier& carrier, const Candidate& candidate)
    {
        return carrier.inductionIx == candidate.inductionIx && carrier.isSum == candidate.isSum &&
               carrier.otherReg == candidate.otherReg && carrier.otherImm == candidate.otherImm;
    }

    MicroInstrOperand regOperand(const MicroReg reg)
    {
        MicroInstrOperand op;
        op.reg = reg;
        return op;
    }

    MicroInstrOperand bitsOperand(const MicroOpBits bits)
    {
        MicroInstrOperand op;
        op.opBits = bits;
        return op;
    }

    MicroInstrOperand microOpOperand(const MicroOp microOp)
    {
        MicroInstrOperand op;
        op.microOp = microOp;
        return op;
    }

    MicroInstrOperand immOperand(const uint64_t value, const MicroOpBits bits)
    {
        MicroInstrOperand op;
        op.setImmediateValue(ApInt(value, getNumBits(bits)));
        return op;
    }

    void insertCopy(MicroStorage& storage, MicroOperandStorage& operands, const MicroInstrRef beforeRef, const MicroReg dst, const MicroReg src, const MicroOpBits bits)
    {
        const MicroInstrOperand ops[3] = {regOperand(dst), regOperand(src), bitsOperand(bits)};
        storage.insertDerivedBefore(operands, beforeRef, MicroInstrOpcode::LoadRegReg, ops);
    }

    void insertOpRegReg(MicroStorage& storage, MicroOperandStorage& operands, const MicroInstrRef beforeRef, const MicroReg dst, const MicroReg src, const MicroOp microOp, const MicroOpBits bits)
    {
        const MicroInstrOperand ops[4] = {regOperand(dst), regOperand(src), bitsOperand(bits), microOpOperand(microOp)};
        storage.insertDerivedBefore(operands, beforeRef, MicroInstrOpcode::OpBinaryRegReg, ops);
    }

    void insertOpRegImm(MicroStorage& storage, MicroOperandStorage& operands, const MicroInstrRef beforeRef, const MicroReg dst, const MicroOp microOp, const uint64_t imm, const MicroOpBits bits)
    {
        const MicroInstrOperand ops[4] = {regOperand(dst), bitsOperand(bits), microOpOperand(microOp), immOperand(imm, bits)};
        storage.insertDerivedBefore(operands, beforeRef, MicroInstrOpcode::OpBinaryRegImm, ops);
    }

    // Steps a carrier the way its induction is stepped.
    void insertStep(MicroStorage& storage, MicroOperandStorage& operands, const MicroInstrRef beforeRef, const MicroReg dst, const Induction& induction)
    {
        if (induction.stepReg.isValid())
            insertOpRegReg(storage, operands, beforeRef, dst, induction.stepReg, induction.stepOp, induction.bits);
        else
            insertOpRegImm(storage, operands, beforeRef, dst, induction.stepOp, induction.stepImm, induction.bits);
    }

    // Turns an instruction into `mov dst, src`.
    void rewriteToCopy(MicroInstr& inst, MicroInstrOperand* ops, const MicroReg dst, const MicroReg src, const MicroOpBits bits)
    {
        inst.op          = MicroInstrOpcode::LoadRegReg;
        inst.numOperands = 3;
        ops[0].reg       = dst;
        ops[1].reg       = src;
        ops[2].opBits    = bits;
    }

    struct LoopScan
    {
        std::unordered_map<MicroReg, uint32_t>      defCount;  // definitions inside the body
        std::unordered_map<MicroReg, MicroInstrRef> singleDef; // the one definition, when there is one
        std::unordered_map<MicroReg, uint32_t>      useCount;  // uses in the whole function
    };

    // One round over every natural loop. Returns true when it changed the IR.
    bool reduceRound(MicroPassContext& context)
    {
        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;

        MicroSsaState        localSsaState;
        const MicroSsaState* ssaState = MicroSsaState::ensureFor(context, localSsaState);
        if (!ssaState || !ssaState->isValid())
            return false;

        const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
        if (cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness())
            return false;

        const uint32_t n = cfg.instructionCount();
        if (n == 0)
            return false;

        const uint32_t entry = MicroPassHelpers::findSingleCfgEntry(cfg);
        if (entry == MicroPassHelpers::MicroDomTree::K_INVALID_NODE)
            return false;

        const MicroPassHelpers::MicroDomTree      dom           = MicroPassHelpers::computeInstructionDominators(cfg, entry);
        std::unordered_map<uint32_t, NaturalLoop> loopsByHeader = MicroPassHelpers::findNaturalLoops(cfg, dom);
        if (loopsByHeader.empty())
            return false;

        const auto                             instrRefs = cfg.instructionRefs();
        std::unordered_map<uint32_t, uint32_t> refToIndex;
        refToIndex.reserve(n);
        for (uint32_t i = 0; i < n; ++i)
            refToIndex[instrRefs[i].get()] = i;

        uint32_t nextVirtualIntRegIndex = 0;
        bool     changed                = false;

        for (auto& loop : loopsByHeader | std::views::values)
        {
            const uint32_t      header    = loop.header;
            const auto&         inBody    = loop.inBody;
            const MicroInstrRef headerRef = instrRefs[header];

            // A clean preheader: one predecessor outside the loop, which is the
            // linear predecessor and falls through into the header. A carrier's
            // first value is computed there with a multiply or an add, so the
            // flags must be dead at that point.
            uint32_t externalPredCount = 0;
            for (const uint32_t p : cfg.predecessors(header))
                if (p < n && !inBody[p])
                    ++externalPredCount;
            if (externalPredCount != 1)
                continue;

            const MicroInstrRef prevRef = storage.findPreviousInstructionRef(headerRef);
            if (!prevRef.isValid())
                continue;
            const auto prevIt = refToIndex.find(prevRef.get());
            if (prevIt == refToIndex.end() || inBody[prevIt->second])
                continue;
            const MicroInstr* prevInst = storage.ptr(prevRef);
            if (!prevInst)
                continue;
            const MicroInstrFlags prevFlags = MicroInstr::info(prevInst->op).flags;
            if ((prevFlags.has(MicroInstrFlagsE::JumpInstruction) || prevFlags.has(MicroInstrFlagsE::TerminatorInstruction)) &&
                !prevFlags.has(MicroInstrFlagsE::ConditionalJump))
                continue;
            if (!MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, prevRef))
                continue;

            LoopScan scan;
            for (uint32_t i = 0; i < n; ++i)
            {
                const MicroInstrUseDef* useDef = ssaState->instrUseDef(instrRefs[i]);
                if (!useDef)
                    continue;
                for (const MicroReg use : useDef->uses)
                    ++scan.useCount[use];
                if (!inBody[i])
                    continue;
                for (const MicroReg def : useDef->defs)
                {
                    if (++scan.defCount[def] == 1)
                        scan.singleDef[def] = instrRefs[i];
                }
            }

            // A register the loop never writes.
            auto isInvariantReg = [&](const MicroReg reg) {
                return reg.isVirtualInt() && !scan.defCount.contains(reg);
            };

            // The inductions: one in-loop definition, an add or a subtract of an
            // immediate or of an invariant register at the induction's width,
            // whose flags nothing reads before they are redefined (a carrier's
            // step lands right behind it and writes them too).
            std::vector<Induction> inductions;
            auto inductionIndexOf = [&](const MicroReg reg) -> uint32_t {
                for (uint32_t k = 0; k < inductions.size(); ++k)
                    if (inductions[k].reg == reg)
                        return k;
                if (!reg.isVirtualInt())
                    return K_INVALID;
                const auto countIt = scan.defCount.find(reg);
                if (countIt == scan.defCount.end() || countIt->second != 1)
                    return K_INVALID;
                const MicroInstrRef stepRef  = scan.singleDef[reg];
                const MicroInstr*   stepInst = storage.ptr(stepRef);
                const auto*         stepOps  = stepInst ? stepInst->ops(operands) : nullptr;
                if (!stepOps || stepOps[0].reg != reg)
                    return K_INVALID;

                Induction induction;
                induction.reg     = reg;
                induction.stepRef = stepRef;
                if (stepInst->op == MicroInstrOpcode::OpBinaryRegImm)
                {
                    // ops: [0] dst, [1] opBits, [2] microOp, [3] imm
                    if (!isCounterBits(stepOps[1].opBits) || !isStepOp(stepOps[2].microOp) || stepOps[3].hasWideImmediateValue())
                        return K_INVALID;
                    const auto magnitude = static_cast<int64_t>(stepOps[3].valueU64);
                    if (magnitude <= 0 || !fitsSigned32(magnitude))
                        return K_INVALID;
                    induction.bits    = stepOps[1].opBits;
                    induction.stepOp  = stepOps[2].microOp;
                    induction.stepImm = stepOps[3].valueU64;
                }
                else if (stepInst->op == MicroInstrOpcode::OpBinaryRegReg)
                {
                    // ops: [0] dst, [1] src, [2] opBits, [3] microOp
                    if (!isCounterBits(stepOps[2].opBits) || !isStepOp(stepOps[3].microOp) || !isInvariantReg(stepOps[1].reg))
                        return K_INVALID;
                    induction.bits    = stepOps[2].opBits;
                    induction.stepOp  = stepOps[3].microOp;
                    induction.stepReg = stepOps[1].reg;
                }
                else
                    return K_INVALID;

                if (!MicroPassHelpers::areCpuFlagsRedefinedBeforeBoundary(storage, operands, stepRef))
                    return K_INVALID;
                if (!storage.findNextInstructionRef(stepRef).isValid())
                    return K_INVALID;

                inductions.push_back(induction);
                return static_cast<uint32_t>(inductions.size() - 1);
            };

            // Splits a pair of registers into the induction and the invariant,
            // in either order.
            auto splitPair = [&](const MicroReg a, const MicroReg b, uint32_t& outInductionIx, MicroReg& outOther) {
                outInductionIx = inductionIndexOf(a);
                outOther       = b;
                if (outInductionIx == K_INVALID)
                {
                    outInductionIx = inductionIndexOf(b);
                    outOther       = a;
                }
                return outInductionIx != K_INVALID && isInvariantReg(outOther) && outOther != inductions[outInductionIx].reg;
            };

            // A register copied from an induction right before the instruction
            // at `ref`, and read nowhere else, stands for the induction: the
            // copy is the one the products above leave behind, and copy
            // elimination does not forward a loop-carried value. The sum then
            // takes the copy with it.
            auto throughAdjacentCopy = [&](const MicroInstrRef ref, const MicroReg reg, MicroInstrRef& outCopyRef) -> MicroReg {
                if (inductionIndexOf(reg) != K_INVALID)
                    return reg;
                const MicroInstrRef      prevCopyRef = storage.findPreviousInstructionRef(ref);
                const MicroInstr*        prevCopy    = prevCopyRef.isValid() ? storage.ptr(prevCopyRef) : nullptr;
                const MicroInstrOperand* copyOps     = prevCopy ? prevCopy->ops(operands) : nullptr;
                if (!copyOps || prevCopy->op != MicroInstrOpcode::LoadRegReg || copyOps[0].reg != reg || !isCounterBits(copyOps[2].opBits))
                    return reg;
                const auto defIt = scan.defCount.find(reg);
                const auto useIt = scan.useCount.find(reg);
                if (defIt == scan.defCount.end() || defIt->second != 1 || useIt == scan.useCount.end() || useIt->second != 1)
                    return reg;
                const uint32_t inductionIx = inductionIndexOf(copyOps[1].reg);
                if (inductionIx == K_INVALID || inductions[inductionIx].bits != copyOps[2].opBits)
                    return reg;
                outCopyRef = prevCopyRef;
                return copyOps[1].reg;
            };

            std::vector<Candidate> products;
            std::vector<Candidate> sums;
            for (uint32_t i = 0; i < n; ++i)
            {
                if (!inBody[i])
                    continue;
                const MicroInstrRef      ref  = instrRefs[i];
                const MicroInstr*        inst = storage.ptr(ref);
                const MicroInstrOperand* ops  = inst ? inst->ops(operands) : nullptr;
                if (!ops)
                    continue;

                Candidate candidate;
                candidate.firstRef = ref;
                candidate.dstReg   = ops[0].reg;
                MicroOpBits bits   = MicroOpBits::Zero;

                if (inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    // `mov t, a` followed by the destructive op on t.
                    bits = ops[2].opBits;
                    if (!ops[0].reg.isVirtualInt() || !isCounterBits(bits))
                        continue;
                    const MicroInstrRef opRef = storage.findNextInstructionRef(ref);
                    const auto          opIt  = refToIndex.find(opRef.get());
                    if (!opRef.isValid() || opIt == refToIndex.end() || !inBody[opIt->second])
                        continue;
                    const MicroInstr*        opInst = storage.ptr(opRef);
                    const MicroInstrOperand* opOps  = opInst ? opInst->ops(operands) : nullptr;
                    if (!opOps || opOps[0].reg != ops[0].reg)
                        continue;
                    candidate.shape     = Shape::CopyThenOp;
                    candidate.secondRef = opRef;

                    if (opInst->op == MicroInstrOpcode::OpBinaryRegReg)
                    {
                        // ops: [0] dst, [1] src, [2] opBits, [3] microOp
                        if (opOps[2].opBits != bits)
                            continue;
                        if (isMultiplyOp(opOps[3].microOp))
                        {
                            candidate.inductionIx = inductionIndexOf(ops[1].reg);
                            candidate.otherReg    = opOps[1].reg;
                            candidate.mulOp       = opOps[3].microOp;
                            if (candidate.inductionIx == K_INVALID || !isInvariantReg(candidate.otherReg) || candidate.otherReg == ops[1].reg)
                                continue;
                            if (inductions[candidate.inductionIx].stepReg.isValid())
                                continue; // a product needs an immediate step
                        }
                        else if (opOps[3].microOp == MicroOp::Add)
                        {
                            const MicroReg lhs = throughAdjacentCopy(ref, ops[1].reg, candidate.copyOfInductionRef);
                            const MicroReg rhs = throughAdjacentCopy(ref, opOps[1].reg, candidate.copyOfInductionRef);
                            if (!splitPair(lhs, rhs, candidate.inductionIx, candidate.otherReg))
                                continue;
                            candidate.isSum = true;
                        }
                        else
                            continue;
                    }
                    else if (opInst->op == MicroInstrOpcode::OpBinaryRegImm)
                    {
                        // ops: [0] dst, [1] opBits, [2] microOp, [3] imm
                        if (opOps[1].opBits != bits || opOps[3].hasWideImmediateValue())
                            continue;
                        candidate.inductionIx = inductionIndexOf(ops[1].reg);
                        if (candidate.inductionIx == K_INVALID || inductions[candidate.inductionIx].stepReg.isValid())
                            continue;
                        if (isMultiplyOp(opOps[2].microOp))
                        {
                            candidate.otherImm = wrapToBits(opOps[3].valueU64, bits);
                            candidate.mulOp    = opOps[2].microOp;
                        }
                        else if (opOps[2].microOp == MicroOp::ShiftLeft && opOps[3].valueU64 < getNumBits(bits))
                        {
                            candidate.otherImm = wrapToBits(1ull << opOps[3].valueU64, bits);
                            candidate.mulOp    = MicroOp::MultiplySigned;
                        }
                        else
                            continue;
                        if (candidate.otherImm == 0 || candidate.otherImm == 1)
                            continue;
                    }
                    else
                        continue;

                    if (!MicroPassHelpers::areCpuFlagsRedefinedBeforeBoundary(storage, operands, opRef))
                        continue;
                }
                else if (inst->op == MicroInstrOpcode::OpBinaryRegRegReg)
                {
                    // ops: [0] dst, [1] src1, [2] src2, [3] opBits, [4] microOp
                    bits = ops[3].opBits;
                    if (!ops[0].reg.isVirtualInt() || !isCounterBits(bits))
                        continue;
                    candidate.shape = Shape::ThreeOperand;
                    if (isMultiplyOp(ops[4].microOp))
                    {
                        if (!splitPair(ops[1].reg, ops[2].reg, candidate.inductionIx, candidate.otherReg))
                            continue;
                        if (inductions[candidate.inductionIx].stepReg.isValid())
                            continue;
                        candidate.mulOp = ops[4].microOp;
                    }
                    else if (ops[4].microOp == MicroOp::Add)
                    {
                        const MicroReg lhs = throughAdjacentCopy(ref, ops[1].reg, candidate.copyOfInductionRef);
                        const MicroReg rhs = throughAdjacentCopy(ref, ops[2].reg, candidate.copyOfInductionRef);
                        if (!splitPair(lhs, rhs, candidate.inductionIx, candidate.otherReg))
                            continue;
                        candidate.isSum = true;
                    }
                    else
                        continue;
                }
                else if (inst->op == MicroInstrOpcode::LoadAddrAmcRegMem)
                {
                    // ops: [0] dst, [1] base, [2] index, [3] opBitsDst, [4] opBitsValue, [5] mul, [6] add
                    bits = ops[3].opBits;
                    if (!ops[0].reg.isVirtualInt() || !isCounterBits(bits) || ops[4].opBits != bits || ops[5].valueU64 != 1)
                        continue;
                    const MicroReg lhs = throughAdjacentCopy(ref, ops[1].reg, candidate.copyOfInductionRef);
                    const MicroReg rhs = throughAdjacentCopy(ref, ops[2].reg, candidate.copyOfInductionRef);
                    if (!splitPair(lhs, rhs, candidate.inductionIx, candidate.otherReg))
                        continue;
                    candidate.shape    = Shape::AddressOfSum;
                    candidate.isSum    = true;
                    candidate.otherImm = ops[6].valueU64;
                }
                else
                    continue;

                const Induction& induction = inductions[candidate.inductionIx];
                if (bits != induction.bits || candidate.dstReg == induction.reg || candidate.dstReg == candidate.otherReg)
                    continue;

                (candidate.isSum ? sums : products).push_back(candidate);
            }

            // Products first; the sums over the accumulators they make are for
            // a later sweep, once copy elimination has put the accumulator
            // itself in the sum.
            std::vector<Candidate> chosen;
            if (!products.empty())
                chosen = std::move(products);
            else
            {
                // A sum is carried only when it takes every use of its
                // induction with it, so the induction dies and the carried
                // pointer costs no register.
                std::unordered_map<uint32_t, uint32_t> sumsPerInduction;
                for (const Candidate& candidate : sums)
                    ++sumsPerInduction[candidate.inductionIx];
                for (const Candidate& candidate : sums)
                {
                    const Induction& induction = inductions[candidate.inductionIx];
                    const auto       useIt     = scan.useCount.find(induction.reg);
                    const uint32_t   uses      = useIt == scan.useCount.end() ? 0 : useIt->second;
                    // The step reads the induction once itself.
                    if (uses == sumsPerInduction[candidate.inductionIx] + 1)
                        chosen.push_back(candidate);
                }
            }
            if (chosen.empty())
                continue;

            if (nextVirtualIntRegIndex == 0)
                nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);

            std::vector<Carrier>         carriers;
            std::vector<MicroInstrRef>   erased;
            std::unordered_set<uint32_t> inductionsCarried;
            for (const Candidate& candidate : chosen)
            {
                const Induction& induction = inductions[candidate.inductionIx];

                uint32_t carrierIx = K_INVALID;
                for (uint32_t k = 0; k < carriers.size(); ++k)
                    if (sameFamily(carriers[k], candidate))
                        carrierIx = k;

                if (carrierIx == K_INVALID)
                {
                    Carrier carrier;
                    carrier.inductionIx = candidate.inductionIx;
                    carrier.isSum       = candidate.isSum;
                    carrier.otherReg    = candidate.otherReg;
                    carrier.otherImm    = candidate.otherImm;

                    const MicroInstrRef afterStepRef = storage.findNextInstructionRef(induction.stepRef);
                    if (candidate.isSum)
                    {
                        // Preheader: p = base + induction (+ disp). Behind the
                        // induction's step: the same step.
                        const auto disp = static_cast<int64_t>(candidate.otherImm);
                        if (induction.bits == MicroOpBits::B64 && !fitsSigned32(disp))
                            continue;
                        SWC_ASSERT(nextVirtualIntRegIndex < MicroReg::K_MAX_INDEX);
                        carrier.reg = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
                        insertCopy(storage, operands, headerRef, carrier.reg, candidate.otherReg, induction.bits);
                        insertOpRegReg(storage, operands, headerRef, carrier.reg, induction.reg, MicroOp::Add, induction.bits);
                        if (candidate.otherImm != 0)
                            insertOpRegImm(storage, operands, headerRef, carrier.reg, MicroOp::Add, wrapToBits(candidate.otherImm, induction.bits), induction.bits);
                        insertStep(storage, operands, afterStepRef, carrier.reg, induction);
                    }
                    else
                    {
                        // The step of the accumulator: stride * step. A unit
                        // step adds the stride itself; an immediate stride
                        // folds; any other pair is one more multiply in the
                        // preheader.
                        const auto signedStep = induction.stepOp == MicroOp::Add ? static_cast<int64_t>(induction.stepImm) : -static_cast<int64_t>(induction.stepImm);
                        MicroReg   deltaReg   = MicroReg::invalid();
                        uint64_t   deltaImm   = 0;
                        bool       deltaIsImm = false;
                        if (candidate.otherReg.isValid())
                        {
                            if (signedStep == 1 || signedStep == -1)
                                deltaReg = candidate.otherReg;
                            else
                            {
                                SWC_ASSERT(nextVirtualIntRegIndex < MicroReg::K_MAX_INDEX);
                                deltaReg = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
                                insertCopy(storage, operands, headerRef, deltaReg, candidate.otherReg, induction.bits);
                                insertOpRegImm(storage, operands, headerRef, deltaReg, MicroOp::MultiplySigned, wrapToBits(static_cast<uint64_t>(signedStep), induction.bits), induction.bits);
                            }
                        }
                        else
                        {
                            const auto delta = static_cast<int64_t>(wrapToBits(candidate.otherImm * static_cast<uint64_t>(signedStep), induction.bits));
                            if (induction.bits == MicroOpBits::B64 && !fitsSigned32(delta))
                                continue;
                            deltaIsImm = true;
                            deltaImm   = static_cast<uint64_t>(delta);
                        }

                        SWC_ASSERT(nextVirtualIntRegIndex < MicroReg::K_MAX_INDEX);
                        carrier.reg = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);

                        // Preheader: acc = induction * stride.
                        insertCopy(storage, operands, headerRef, carrier.reg, induction.reg, induction.bits);
                        if (candidate.otherReg.isValid())
                            insertOpRegReg(storage, operands, headerRef, carrier.reg, candidate.otherReg, candidate.mulOp, induction.bits);
                        else
                            insertOpRegImm(storage, operands, headerRef, carrier.reg, candidate.mulOp, candidate.otherImm, induction.bits);

                        // Behind the induction's step: acc += stride * step.
                        if (deltaIsImm)
                            insertOpRegImm(storage, operands, afterStepRef, carrier.reg, MicroOp::Add, deltaImm, induction.bits);
                        else
                            insertOpRegReg(storage, operands, afterStepRef, carrier.reg, deltaReg, signedStep < 0 && deltaReg == candidate.otherReg ? MicroOp::Subtract : MicroOp::Add, induction.bits);
                    }

                    carriers.push_back(carrier);
                    carrierIx = static_cast<uint32_t>(carriers.size() - 1);
                }

                // The candidate becomes a copy of its carrier.
                MicroInstr*        firstInst = storage.ptr(candidate.firstRef);
                MicroInstrOperand* firstOps  = firstInst ? firstInst->ops(operands) : nullptr;
                if (!firstOps)
                    continue;
                rewriteToCopy(*firstInst, firstOps, candidate.dstReg, carriers[carrierIx].reg, induction.bits);
                if (candidate.secondRef.isValid())
                    erased.push_back(candidate.secondRef);
                if (candidate.copyOfInductionRef.isValid())
                    erased.push_back(candidate.copyOfInductionRef);
                if (candidate.isSum)
                    inductionsCarried.insert(candidate.inductionIx);
                changed = true;
            }

            // An induction whose every use now reads a carrier is dead, and
            // its step with it: nothing else reads the register the step
            // defines, and liveness alone never sees through the cycle.
            for (const uint32_t inductionIx : inductionsCarried)
                erased.push_back(inductions[inductionIx].stepRef);

            for (const MicroInstrRef ref : erased)
                storage.erase(ref);

            // The next loop reads a layout this one has changed; the pass
            // manager reruns the pass while it keeps finding work.
            if (changed)
                break;
        }

        if (changed)
        {
            if (context.ssaState)
                context.ssaState->invalidate();
            context.builder->invalidateControlFlowGraph();
        }
        return changed;
    }
}

Result MicroInductionVariablePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    if (!context.builder)
        return Result::Continue;

    // Loop-free functions are the common case: the cached back-edge test lets
    // them skip the SSA and dominator work.
    if (!context.builder->controlFlowGraph().hasLoop())
        return Result::Continue;

    if (reduceRound(context))
        context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
