#include "pch.h"
#include "Backend/Micro/Passes/Pass.ValueNumbering.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/SmallVector.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/Assert.h"

// Dominance-scoped value numbering. See the header for the high-level contract.
//
// The pass runs inside the pre-RA fixed-point loop and converges across its
// iterations rather than within one sweep: rewrites are planned against one
// SSA snapshot and applied together, so a duplicated dependency chain loses
// its head on the first sweep, the next instruction on the following one
// (once the head's copy is transparent to the canonicalizer), and so on
// until both chains share every step.
//
// Memory reads are numbered too, on a stricter scope: a load repeats an
// earlier one only when nothing between them could have changed what it
// reads, and that is decided by a memory epoch rather than by dominance — the
// counter advances at every label, store, push/pop and call, so two loads
// share a value only when they sit in the same straight line with no write of
// any kind in between. Two loads match on the bytes they read, whatever each
// one does with them: the byte a text scanner compares and then consumes,
// `text[p] != ','` followed by `text[p] - 48`, is read once through a
// zero-extending load and once as a plain byte, and the second becomes a copy
// of the first — or an extension of it, when the extension is on that side.
// Loads through the frame are left alone: a local's slot belongs to mem2reg,
// and numbering its reloads first only leaves copy chains behind once the
// slot is promoted.

SWC_BEGIN_NAMESPACE();

namespace
{
    // Registers whose value a key may name. Only plain virtual registers are
    // SSA-tracked; anything else (stack pointer, NoBase, physical registers)
    // makes the instruction opaque to numbering.
    bool isNumberableReg(const MicroReg reg)
    {
        return reg.isVirtual();
    }

    // Values proven equal to an earlier one by a key match that could not be
    // rewritten (the earlier register was already overwritten). Keys of later
    // consumers resolve through this map, so a duplicated two-address chain —
    // whose intermediate results die the instruction after they are made —
    // still matches step by step until its tail, where the surviving result
    // register allows the actual rewrite and DCE unwinds the rest.
    using ValueAliases = std::unordered_map<uint32_t, uint32_t>;

    uint32_t resolveValueAlias(const ValueAliases& aliases, uint32_t valueId)
    {
        for (uint32_t depth = 0; depth < 8; ++depth)
        {
            const auto it = aliases.find(valueId);
            if (it == aliases.end())
                break;
            valueId = it->second;
        }
        return valueId;
    }

    // Follow plain register copies back to the value they forward, so the
    // interleaved `T = A` copies two-address lowering emits do not make
    // identical computes look different. A copy is transparent only when the
    // consumer reads no more bits than the copy moved: following a narrow
    // copy for a wider consumer would equate values that differ in the bits
    // the copy never wrote.
    uint32_t canonicalUseValue(const MicroSsaState& ssa, const MicroOperandStorage& operands, const ValueAliases& aliases, const MicroReg reg, const MicroInstrRef atRef, const MicroOpBits consumerBits)
    {
        MicroSsaState::ReachingDef reach = ssa.reachingDef(reg, atRef);
        if (!reach.valid())
            return MicroSsaState::K_INVALID_VALUE;

        for (uint32_t depth = 0; depth < 8; ++depth)
        {
            if (reach.isPhi || !reach.inst || reach.inst->op != MicroInstrOpcode::LoadRegReg)
                break;

            const MicroInstrOperand* copyOps = reach.inst->ops(operands);
            if (!copyOps)
                break;
            if (getNumBits(consumerBits) > getNumBits(copyOps[2].opBits))
                break;
            const MicroReg srcReg = copyOps[1].reg;
            if (!isNumberableReg(srcReg))
                break;

            const MicroSsaState::ReachingDef srcReach = ssa.reachingDef(srcReg, reach.instRef);
            if (!srcReach.valid())
                break;
            reach = srcReach;
        }

        return resolveValueAlias(aliases, reach.valueId);
    }

    constexpr uint8_t K_NO_SLOT = 0xFF;

    // How a load widens the bytes it reads into its destination.
    enum class LoadExtension : uint8_t
    {
        None,
        Zero,
        Signed,
    };

    // Operand shape of one CSE-eligible opcode: which slots are value inputs,
    // which raw slots complete the key, and where the result width lives.
    struct NumberingShape
    {
        SmallVector<uint8_t, 2> useSlots;
        SmallVector<uint8_t, 4> rawSlots;
        uint8_t                 movBitsSlot          = 0;
        bool                    dstIsAlsoUse         = false;
        bool                    hasImmediate         = false;
        uint8_t                 immediateSlot        = 0;
        bool                    keyedByRelocationToo = false;

        // A load. Its inputs are addresses, read at 64 bits whatever the width
        // of the value loaded; its key names the bytes read (the address and
        // their width) and not the opcode, so the plain and the extending loads
        // of one cell share it; and the match is scoped by memory epoch.
        bool          readsMemory  = false;
        uint8_t       memoryFamily = 0;
        uint8_t       srcBitsSlot  = 0;
        uint8_t       addrBitsSlot = K_NO_SLOT;
        LoadExtension extension    = LoadExtension::None;
    };

    // Key words that open a memory key, one per address family, chosen outside
    // the opcode range so a load never collides with a compute.
    constexpr uint64_t K_MEMORY_KEY_BASE = 0x1000;

    bool numberingShapeFor(const MicroInstrOpcode op, NumberingShape& outShape)
    {
        switch (op)
        {
            case MicroInstrOpcode::OpBinaryRegImm:
                // ops: [0] dst (read-modify-write), [1] opBits, [2] microOp, [3] imm
                outShape.useSlots      = {};
                outShape.rawSlots      = {1, 2};
                outShape.movBitsSlot   = 1;
                outShape.dstIsAlsoUse  = true;
                outShape.hasImmediate  = true;
                outShape.immediateSlot = 3;
                return true;

            case MicroInstrOpcode::OpBinaryRegReg:
                // ops: [0] dst (read-modify-write), [1] src, [2] opBits, [3] microOp
                outShape.useSlots     = {1};
                outShape.rawSlots     = {2, 3};
                outShape.movBitsSlot  = 2;
                outShape.dstIsAlsoUse = true;
                return true;

            case MicroInstrOpcode::LoadAddrRegMem:
                // ops: [0] dst, [1] base, [2] opBits, [3] offset
                outShape.useSlots    = {1};
                outShape.rawSlots    = {2, 3};
                outShape.movBitsSlot = 2;
                return true;

            case MicroInstrOpcode::LoadAddrAmcRegMem:
                // ops: [0] dst, [1] base, [2] mul, [3] opBitsDst, [4] opBitsValue, [5] mulValue, [6] addValue
                outShape.useSlots    = {1, 2};
                outShape.rawSlots    = {3, 4, 5, 6};
                outShape.movBitsSlot = 3;
                return true;

            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
                // ops: [0] dst, [1] src, [2] dstBits, [3] srcBits
                outShape.useSlots    = {1};
                outShape.rawSlots    = {2, 3};
                outShape.movBitsSlot = 2;
                return true;

            case MicroInstrOpcode::LoadRegPtrReloc:
                // ops: [0] dst, [1] opBits, [2] target. The address of a global,
                // a constant or a function: the same relocation always resolves
                // to the same value, so every re-materialization of one inside a
                // loop is redundant. The target word alone does not identify it —
                // offset 0 exists in every data segment — so the relocation's own
                // identity completes the key.
                outShape.useSlots             = {};
                outShape.rawSlots             = {1, 2};
                outShape.movBitsSlot          = 1;
                outShape.keyedByRelocationToo = true;
                return true;

            case MicroInstrOpcode::LoadRegMem:
                // ops: [0] dst, [1] base, [2] opBits, [3] offset
                outShape.useSlots     = {1};
                outShape.rawSlots     = {3};
                outShape.movBitsSlot  = 2;
                outShape.readsMemory  = true;
                outShape.memoryFamily = 0;
                outShape.srcBitsSlot  = 2;
                return true;

            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
                // ops: [0] dst, [1] base, [2] dstBits, [3] srcBits, [4] offset
                outShape.useSlots     = {1};
                outShape.rawSlots     = {4};
                outShape.movBitsSlot  = 2;
                outShape.readsMemory  = true;
                outShape.memoryFamily = 0;
                outShape.srcBitsSlot  = 3;
                outShape.extension    = op == MicroInstrOpcode::LoadSignedExtRegMem ? LoadExtension::Signed : LoadExtension::Zero;
                return true;

            case MicroInstrOpcode::LoadAmcRegMem:
                // ops: [0] dst, [1] base, [2] index, [3] loadBits, [4] addrBits, [5] mul, [6] add.
                // The extending forms have no addressing-width operand — they
                // are 64-bit by construction — so the key leaves it out and the
                // plain form only takes part when it addresses at 64 bits too.
                outShape.useSlots     = {1, 2};
                outShape.rawSlots     = {5, 6};
                outShape.movBitsSlot  = 3;
                outShape.readsMemory  = true;
                outShape.memoryFamily = 1;
                outShape.srcBitsSlot  = 3;
                outShape.addrBitsSlot = 4;
                return true;

            case MicroInstrOpcode::LoadSignedExtAmcRegMem:
            case MicroInstrOpcode::LoadZeroExtAmcRegMem:
                // ops: [0] dst, [1] base, [2] index, [3] dstBits, [4] srcBits, [5] mul, [6] add
                outShape.useSlots     = {1, 2};
                outShape.rawSlots     = {5, 6};
                outShape.movBitsSlot  = 3;
                outShape.readsMemory  = true;
                outShape.memoryFamily = 1;
                outShape.srcBitsSlot  = 4;
                outShape.extension    = op == MicroInstrOpcode::LoadSignedExtAmcRegMem ? LoadExtension::Signed : LoadExtension::Zero;
                return true;

            default:
                return false;
        }
    }

    // An instruction after which a load may observe different memory: any
    // write, a call, a stack adjustment, and a label, where another path may
    // join the straight line the epoch vouches for. A conditional jump keeps
    // the fall-through path straight and does not advance it; an unconditional
    // one is always followed by a label.
    bool advancesMemoryEpoch(const MicroInstr& inst)
    {
        if (inst.op == MicroInstrOpcode::Label)
            return true;
        const MicroInstrDef& info = MicroInstr::info(inst.op);
        return info.flags.has(MicroInstrFlagsE::WritesMemory) || info.flags.has(MicroInstrFlagsE::IsCallInstruction);
    }

    // Registers that hold an address into the frame: the stack pointer and
    // every copy, lea or addition chained from one. Flow-insensitive and
    // transitive, so it over-approximates — which only withholds numbering
    // from a load, never numbers one it should not.
    void collectFrameDerivedRegs(std::unordered_set<MicroReg>& out, const MicroStorage& storage, const MicroOperandStorage& operands, const MicroReg stackPointer)
    {
        if (!stackPointer.isValid())
            return;
        out.insert(stackPointer);

        bool changed = true;
        while (changed)
        {
            changed = false;
            for (const MicroInstr& inst : storage.view())
            {
                const MicroInstrOperand* ops = inst.ops(operands);
                if (!ops)
                    continue;

                bool derived = false;
                switch (inst.op)
                {
                    case MicroInstrOpcode::LoadRegReg:
                    case MicroInstrOpcode::LoadAddrRegMem:
                    case MicroInstrOpcode::LoadAddrAmcRegMem:
                        derived = out.contains(ops[1].reg);
                        break;
                    case MicroInstrOpcode::OpBinaryRegReg:
                        derived = ops[3].microOp == MicroOp::Add && out.contains(ops[1].reg);
                        break;
                    case MicroInstrOpcode::OpBinaryRegRegReg:
                        derived = ops[4].microOp == MicroOp::Add && (out.contains(ops[1].reg) || out.contains(ops[2].reg));
                        break;
                    case MicroInstrOpcode::OpBinaryRegRegImm:
                        derived = (ops[3].microOp == MicroOp::Add || ops[3].microOp == MicroOp::Subtract) && out.contains(ops[1].reg);
                        break;
                    default:
                        break;
                }

                if (derived && out.insert(ops[0].reg).second)
                    changed = true;
            }
        }
    }

    struct NumberingEntry
    {
        uint32_t                 index      = 0;
        MicroReg                 defReg     = MicroReg::invalid();
        uint32_t                 defValueId = MicroSsaState::K_INVALID_VALUE;
        uint32_t                 epoch      = 0;
        MicroInstrOpcode         op         = MicroInstrOpcode::OpBinaryRegImm;
        MicroOpBits              movBits    = MicroOpBits::B64;
        SmallVector<uint64_t, 8> key;
    };

    struct PlannedRewrite
    {
        MicroInstrRef    instRef = MicroInstrRef::invalid();
        MicroInstrOpcode op      = MicroInstrOpcode::LoadRegReg;
        MicroReg         dstReg  = MicroReg::invalid();
        MicroReg         srcReg  = MicroReg::invalid();
        MicroOpBits      movBits = MicroOpBits::B64;
        MicroOpBits      srcBits = MicroOpBits::B64;
    };

    // What a relocation points at, as key words. Two relocation-bearing loads
    // are the same value exactly when these agree; anything the emitter uses to
    // resolve the target has to appear here or two different addresses could
    // hash together.
    void appendRelocationIdentity(SmallVector<uint64_t, 8>& key, const MicroRelocation& reloc)
    {
        key.push_back(static_cast<uint64_t>(reloc.kind));
        key.push_back(reloc.targetAddress);
        key.push_back(reinterpret_cast<uint64_t>(reloc.targetSymbol));
        key.push_back(reloc.constantRef.get());
        key.push_back(reloc.constantShard);
        key.push_back(reloc.constantOffset);
    }

    uint64_t hashKey(const SmallVector<uint64_t, 8>& key)
    {
        uint64_t hash = 1469598103934665603ull;
        for (const uint64_t word : key)
        {
            hash ^= word;
            hash *= 1099511628211ull;
        }
        return hash;
    }
}

Result MicroValueNumberingPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/ValueNumbering");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;

    MicroSsaState        localSsaState;
    const MicroSsaState* ssaState = MicroSsaState::ensureFor(context, localSsaState);
    if (!ssaState || !ssaState->isValid())
        return Result::Continue;

    const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
    if (cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness())
        return Result::Continue;

    const uint32_t n = cfg.instructionCount();
    if (n == 0)
        return Result::Continue;

    const uint32_t entry = MicroPassHelpers::findSingleCfgEntry(cfg);
    if (entry == MicroPassHelpers::MicroDomTree::K_INVALID_NODE)
        return Result::Continue;

    const MicroPassHelpers::MicroDomTree dom = MicroPassHelpers::computeInstructionDominators(cfg, entry);

    const auto instrRefs = cfg.instructionRefs();

    // Relocation-bearing loads are keyed by what they point at, so the pass
    // needs to reach a relocation from its instruction.
    std::unordered_map<MicroInstrRef, const MicroRelocation*> relocationByInstruction;
    for (const MicroRelocation& reloc : context.builder->codeRelocations())
    {
        if (reloc.instructionRef.isValid())
            relocationByInstruction[reloc.instructionRef] = &reloc;
    }

    std::unordered_set<MicroReg> frameDerivedRegs;
    collectFrameDerivedRegs(frameDerivedRegs, storage, operands, CallConv::get(context.callConvKind).stackPointer);

    std::unordered_map<uint64_t, SmallVector<NumberingEntry, 2>> table;
    std::vector<PlannedRewrite>                                  rewrites;
    ValueAliases                                                 valueAliases;
    uint32_t                                                     memoryEpoch = 0;

    for (uint32_t i = 0; i < n; ++i)
    {
        const MicroInstrRef instRef = instrRefs[i];
        const MicroInstr*   inst    = storage.ptr(instRef);
        if (!inst)
            continue;

        if (advancesMemoryEpoch(*inst))
            ++memoryEpoch;

        NumberingShape shape;
        if (!numberingShapeFor(inst->op, shape))
            continue;

        const MicroInstrDef& info = MicroInstr::info(inst->op);
        if (info.flags.has(MicroInstrFlagsE::UsesCpuFlags))
            continue;

        const MicroInstrOperand* ops = inst->ops(operands);
        if (!ops)
            continue;

        const MicroReg dstReg = ops[0].reg;
        if (!isNumberableReg(dstReg))
            continue;

        // A >64-bit immediate would need extra key words; too rare to matter.
        if (shape.hasImmediate && ops[shape.immediateSlot].valueInt.bitWidth() > 64)
            continue;

        // A load through the frame is mem2reg's, and a RIP-relative one reads
        // an address the relocation binds rather than the base register.
        if (shape.readsMemory && (frameDerivedRegs.contains(ops[shape.useSlots[0]].reg) || relocationByInstruction.contains(instRef)))
            continue;
        if (shape.addrBitsSlot != K_NO_SLOT && ops[shape.addrBitsSlot].opBits != MicroOpBits::B64)
            continue;

        const MicroOpBits movBits = ops[shape.movBitsSlot].opBits;
        const MicroOpBits useBits = shape.readsMemory ? MicroOpBits::B64 : movBits;
        const MicroOpBits srcBits = shape.readsMemory ? ops[shape.srcBitsSlot].opBits : movBits;

        SmallVector<uint64_t, 8> key;
        key.push_back(shape.readsMemory ? K_MEMORY_KEY_BASE + shape.memoryFamily : static_cast<uint64_t>(inst->op));

        bool usable = true;
        if (shape.dstIsAlsoUse)
        {
            const uint32_t valueId = canonicalUseValue(*ssaState, operands, valueAliases, dstReg, instRef, movBits);
            usable                 = valueId != MicroSsaState::K_INVALID_VALUE;
            key.push_back(valueId);
        }
        for (const uint8_t slot : shape.useSlots)
        {
            const MicroReg useReg = ops[slot].reg;
            if (!isNumberableReg(useReg))
            {
                usable = false;
                break;
            }
            const uint32_t valueId = canonicalUseValue(*ssaState, operands, valueAliases, useReg, instRef, useBits);
            if (valueId == MicroSsaState::K_INVALID_VALUE)
            {
                usable = false;
                break;
            }
            key.push_back(valueId);
        }
        if (!usable)
            continue;

        for (const uint8_t slot : shape.rawSlots)
            key.push_back(ops[slot].valueU64);
        if (shape.readsMemory)
            key.push_back(static_cast<uint64_t>(srcBits));
        if (shape.hasImmediate)
            key.push_back(ops[shape.immediateSlot].valueU64);
        if (shape.keyedByRelocationToo)
        {
            const auto relocIt = relocationByInstruction.find(instRef);
            if (relocIt == relocationByInstruction.end())
                continue;
            appendRelocationIdentity(key, *relocIt->second);
        }

        uint32_t myValueId = MicroSsaState::K_INVALID_VALUE;
        if (!ssaState->defValue(dstReg, instRef, myValueId))
            continue;

        auto& bucket = table[hashKey(key)];

        bool replaced = false;
        for (const NumberingEntry& cand : bucket)
        {
            if (cand.key.size() != key.size() || !std::equal(cand.key.begin(), cand.key.end(), key.begin()))
                continue;
            if (shape.readsMemory && cand.epoch != memoryEpoch)
                continue;
            if (!dom.dominates(cand.index, i))
                continue;

            // Two loads of one cell are the same value only when they widen it
            // the same way; otherwise the earlier result still holds the bytes
            // in its low bits, and the later load becomes the extension it was.
            const bool sameResult = !shape.readsMemory || (cand.op == inst->op && cand.movBits == movBits);

            // The two results are the same value from here on, whether or not
            // the rewrite below is possible; later keys resolve through this.
            if (sameResult)
                valueAliases.emplace(myValueId, cand.defValueId);

            // The earlier result must still be what its register holds here.
            const MicroSsaState::ReachingDef reach = ssaState->reachingDef(cand.defReg, instRef);
            if (!reach.valid() || reach.valueId != cand.defValueId)
                continue;

            // Replacing a flag-defining compute with a copy removes its flags
            // definition outright, so the strict straight-line criterion
            // applies: the flags must be redefined before any control-flow
            // boundary (branch fusion keeps flags live across jumps, which
            // the relaxed areCpuFlagsDeadAfter contract does not see).
            if (info.flags.has(MicroInstrFlagsE::DefinesCpuFlags) &&
                !MicroPassHelpers::areCpuFlagsRedefinedBeforeBoundary(storage, operands, instRef))
                break;

            // Same result: a plain copy of it. A plain load of bytes an earlier
            // load already holds: a copy of just those bytes. An extending
            // load of them: the same extension, applied to the earlier register.
            PlannedRewrite rewrite;
            rewrite.instRef = instRef;
            rewrite.dstReg  = dstReg;
            rewrite.srcReg  = cand.defReg;
            rewrite.srcBits = srcBits;
            if (sameResult)
            {
                rewrite.op      = MicroInstrOpcode::LoadRegReg;
                rewrite.movBits = cand.movBits;
            }
            else if (shape.extension == LoadExtension::None)
            {
                rewrite.op      = MicroInstrOpcode::LoadRegReg;
                rewrite.movBits = srcBits;
            }
            else
            {
                rewrite.op      = shape.extension == LoadExtension::Zero ? MicroInstrOpcode::LoadZeroExtRegReg : MicroInstrOpcode::LoadSignedExtRegReg;
                rewrite.movBits = movBits;
            }
            rewrites.push_back(rewrite);
            replaced = true;
            break;
        }

        if (!replaced)
            bucket.push_back({.index = i, .defReg = dstReg, .defValueId = myValueId, .epoch = memoryEpoch, .op = inst->op, .movBits = movBits, .key = key});
    }

    if (rewrites.empty())
        return Result::Continue;

    for (const PlannedRewrite& rewrite : rewrites)
    {
        MicroInstr* inst = storage.ptr(rewrite.instRef);
        if (!inst)
            continue;
        MicroInstrOperand* ops = inst->ops(operands);
        if (!ops)
            continue;

        // A rewritten instruction no longer carries the address the relocation
        // was going to patch. Leaving the relocation attached would have the
        // emitter bind it to whatever the copy encodes.
        if (inst->op == MicroInstrOpcode::LoadRegPtrReloc)
            context.builder->invalidateRelocationForInstruction(rewrite.instRef);

        inst->op      = rewrite.op;
        ops[0].reg    = rewrite.dstReg;
        ops[1].reg    = rewrite.srcReg;
        ops[2].opBits = rewrite.movBits;
        if (rewrite.op == MicroInstrOpcode::LoadRegReg)
        {
            inst->numOperands = 3;
        }
        else
        {
            // LoadZeroExtRegReg / LoadSignedExtRegReg: [dst, src, dstBits, srcBits].
            inst->numOperands = 4;
            ops[3].opBits     = rewrite.srcBits;
        }
    }

    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
