#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.SlpVectorize.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ScalarBlock
    {
        std::vector<MicroInstrRef> instructions;
        MicroInstrRef              end;
        uint32_t                   roots = 0;
    };

    // Propagate upper-half observations backwards through copies, scalar
    // arithmetic and phis. A low-half-only value can have its register name
    // separated from later definitions without preserving an unrelated upper half.
    std::vector<uint8_t> observedUpperHalves(const MicroPassContext& context, const MicroSsaState& ssa)
    {
        const auto                         values = ssa.values();
        std::vector<uint8_t>               observed(values.size());
        std::vector<std::vector<uint32_t>> inputs(values.size());
        for (uint32_t id = 0; id < values.size(); ++id)
        {
            const auto& value = values[id];
            if (!value.reg.isVirtualFloat())
                continue;
            // Edges from a result to an already-observed input cannot add a fact.
            // Once one use observes this value, the remaining uses need no scan.
            for (const auto& use : value.uses)
            {
                if (use.kind == MicroSsaState::UseSite::Kind::Phi)
                {
                    const auto* phi = ssa.phiInfo(use.phiIndex);
                    if (phi && phi->resultValueId != MicroSsaState::K_INVALID_VALUE)
                        inputs[phi->resultValueId].push_back(id);
                    else
                    {
                        observed[id] = 1;
                        break;
                    }
                    continue;
                }
                const MicroInstr* instruction = context.instructions->ptr(use.instRef);
                const auto*       ops         = instruction ? instruction->ops(*context.operands) : nullptr;
                if (!ops)
                {
                    observed[id] = 1;
                    break;
                }
                bool upperFlows = false;
                bool understood = false;
                switch (instruction->op)
                {
                    case MicroInstrOpcode::LoadRegReg:
                        understood = true;
                        upperFlows = (ops[2].opBits == MicroOpBits::B128 && ops[1].reg == value.reg) ||
                                     (ops[2].opBits != MicroOpBits::B128 && ops[0].reg == value.reg && ops[1].reg.isAnyFloat());
                        break;
                    case MicroInstrOpcode::LoadMemReg:
                    case MicroInstrOpcode::StoreVecMemReg:
                        understood = ops[2].opBits == MicroOpBits::B32 || ops[2].opBits == MicroOpBits::B64;
                        break;
                    case MicroInstrOpcode::CmpRegReg:
                    case MicroInstrOpcode::CmpMemReg:
                        understood = ops[2].opBits == MicroOpBits::B32 || ops[2].opBits == MicroOpBits::B64;
                        break;
                    case MicroInstrOpcode::OpBinaryRegReg:
                    case MicroInstrOpcode::OpBinaryRegMem:
                        if (ops[2].opBits == MicroOpBits::B32 || ops[2].opBits == MicroOpBits::B64)
                        {
                            understood = true;
                            upperFlows = ops[3].microOp == MicroOp::FloatSqrt ? instruction->op == MicroInstrOpcode::OpBinaryRegReg && ops[1].reg == value.reg : ops[0].reg == value.reg;
                            if (instruction->op == MicroInstrOpcode::OpBinaryRegReg &&
                                (ops[3].microOp == MicroOp::FloatAnd || ops[3].microOp == MicroOp::FloatXor) && ops[1].reg == value.reg)
                                upperFlows = true;
                        }
                        else if (instruction->packedFloatInputBits(ops) == MicroOpBits::B64)
                            understood = true;
                        break;
                    case MicroInstrOpcode::OpBinaryRegRegReg:
                    case MicroInstrOpcode::OpBinaryRegRegMem:
                        if (ops[3].opBits == MicroOpBits::B32 || ops[3].opBits == MicroOpBits::B64)
                        {
                            understood = true;
                            upperFlows = ops[1].reg == value.reg;
                            if (instruction->op == MicroInstrOpcode::OpBinaryRegRegReg &&
                                (ops[4].microOp == MicroOp::FloatAnd || ops[4].microOp == MicroOp::FloatXor) && ops[2].reg == value.reg)
                                upperFlows = true;
                        }
                        else if (instruction->packedFloatInputBits(ops) == MicroOpBits::B64)
                            understood = true;
                        break;
                    case MicroInstrOpcode::OpTernaryRegRegReg:
                    case MicroInstrOpcode::OpTernaryRegRegMem:
                        understood = ops[3].opBits == MicroOpBits::B32 || ops[3].opBits == MicroOpBits::B64;
                        upperFlows = understood && ops[0].reg == value.reg;
                        break;
                    default:
                        break;
                }
                if (!understood)
                {
                    observed[id] = 1;
                    break;
                }
                else if (upperFlows)
                {
                    uint32_t result;
                    if (ops[0].reg.isVirtualFloat() && ssa.defValue(ops[0].reg, use.instRef, result))
                        inputs[result].push_back(id);
                    else
                    {
                        observed[id] = 1;
                        break;
                    }
                }
            }
        }
        std::vector<uint32_t> pending;
        for (uint32_t id = 0; id < observed.size(); ++id)
            if (observed[id])
                pending.push_back(id);
        while (!pending.empty())
        {
            const uint32_t result = pending.back();
            pending.pop_back();
            for (const uint32_t source : inputs[result])
                if (!observed[source])
                {
                    observed[source] = 1;
                    pending.push_back(source);
                }
        }
        return observed;
    }

    struct ScalarRewrite
    {
        MicroInstrRef                  reference;
        MicroInstrOpcode               opcode;
        SmallVector<MicroInstrOperand> operands;
        bool                           clearDestination = false;
    };

    struct ScalarExitCopy
    {
        MicroInstrRef before;
        MicroReg      destination;
        MicroReg      source;
    };
}

namespace
{
    constexpr uint32_t K_MAX_ROOT_HOIST_INSTRUCTIONS = 256;
    constexpr uint32_t K_ROOT_PAIR_WINDOW            = 4096;

    bool packIndependentRoots(MicroPassContext& context);

    struct RootCandidate
    {
        MicroInstrRef reference;
        MicroReg      destination;
        MicroReg      left;
        MicroReg      right;
        bool          divide = false;
    };

    bool readRoot(RootCandidate& root, const MicroInstr& instruction, const MicroOperandStorage& operands, MicroInstrRef reference)
    {
        const auto* ops = instruction.ops(operands);
        if (!ops || !ops[0].reg.isVirtualFloat())
            return false;
        if (instruction.op == MicroInstrOpcode::OpBinaryRegReg && ops[2].opBits == MicroOpBits::B64 && ops[3].microOp == MicroOp::FloatSqrt)
        {
            root = {reference, ops[0].reg, ops[1].reg, MicroReg::invalid(), false};
            return true;
        }
        if (instruction.op == MicroInstrOpcode::OpBinaryRegRegReg && ops[3].opBits == MicroOpBits::B64 && ops[4].microOp == MicroOp::FloatDivide)
        {
            root = {reference, ops[0].reg, ops[1].reg, ops[2].reg, true};
            return true;
        }
        return false;
    }

    struct FrameRange
    {
        uint64_t offset = 0;
        uint32_t size   = 0;
    };

    // Prove a pure input graph can execute at the first root. Memory snapshots
    // retain their byte ranges; fresh names preserve intervening register values.
    struct RootHoistPlan
    {
        MicroPassContext*              context = nullptr;
        const MicroSsaState*           ssa     = nullptr;
        std::span<const MicroInstrRef> references;
        const FlatKeyMap<uint32_t>*    positions    = nullptr;
        const FlatKeyMap<uint64_t>*    stackOffsets = nullptr;
        uint32_t                       first        = 0;
        uint32_t                       second       = 0;
        FlatKeySet                     selected;
        FlatKeySet                     visiting;
        std::vector<MicroInstrRef>     order;

        bool frameAddress(uint64_t& offset, MicroReg base, MicroInstrRef at) const
        {
            for (uint32_t depth = 0; depth < MicroPassHelpers::K_MAX_ROOT_CHAIN; ++depth)
            {
                if (base == context->encoder->stackPointerReg())
                {
                    const auto* displacement = stackOffsets->find(at.get());
                    if (!displacement)
                        return false;
                    offset += *displacement;
                    return true;
                }
                const auto definition = ssa->reachingDef(base, at);
                if (!definition.valid() || definition.isPhi || !definition.inst)
                    return false;
                const auto* ops = definition.inst->ops(*context->operands);
                if (!ops || ops[2].opBits != MicroOpBits::B64)
                    return false;
                if (definition.inst->op == MicroInstrOpcode::LoadAddrRegMem)
                    offset += ops[3].valueU64;
                else if (definition.inst->op != MicroInstrOpcode::LoadRegReg || !ops[1].reg.isAnyInt())
                    return false;
                base = ops[1].reg;
                at   = definition.instRef;
            }
            return false;
        }

        bool memoryRange(FrameRange& range, const MicroInstr& instruction, MicroInstrRef reference) const
        {
            const auto& info = MicroInstr::info(instruction.op);
            const auto* ops  = instruction.ops(*context->operands);
            if (!ops || !info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
                return false;
            range.offset = ops[info.memOffsetOperandIndex].valueU64;
            if (!frameAddress(range.offset, ops[info.memBaseOperandIndex].reg, reference))
                return false;
            switch (instruction.op)
            {
                case MicroInstrOpcode::LoadRegMem:
                case MicroInstrOpcode::LoadVecRegMem:
                case MicroInstrOpcode::LoadMemReg:
                case MicroInstrOpcode::StoreVecMemReg:
                case MicroInstrOpcode::OpBinaryRegMem:
                    range.size = getNumBytes(ops[2].opBits);
                    return true;
                case MicroInstrOpcode::OpBinaryRegRegMem:
                case MicroInstrOpcode::OpTernaryRegRegMem:
                    range.size = getNumBytes(ops[3].opBits);
                    return true;
                case MicroInstrOpcode::LoadMemImm:
                    range.size = getNumBytes(ops[1].opBits);
                    return true;
                default:
                    return false;
            }
        }

        bool canHoistRead(const MicroInstr& instruction, uint32_t index) const
        {
            const auto& info = MicroInstr::info(instruction.op);
            if (!info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) || instruction.op == MicroInstrOpcode::LoadAddrRegMem)
                return true;
            const auto* ops = instruction.ops(*context->operands);
            if (ops[info.memBaseOperandIndex].reg.isInstructionPointer())
                return std::ranges::any_of(context->builder->codeRelocations(), [&](const MicroRelocation& relocation) { return relocation.instructionRef == references[index] && relocation.kind == MicroRelocation::Kind::ConstantAddress; });
            FrameRange read;
            if (!memoryRange(read, instruction, references[index]))
                return false;
            for (uint32_t earlier = first; earlier < index; ++earlier)
            {
                const auto& writer     = *context->instructions->ptr(references[earlier]);
                const auto& writerInfo = MicroInstr::info(writer.op);
                if (!writerInfo.flags.has(MicroInstrFlagsE::WritesMemory))
                    continue;
                const auto* writerOps = writer.ops(*context->operands);
                if (writerOps && writerInfo.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) && writerOps[writerInfo.memBaseOperandIndex].reg.isInstructionPointer())
                    continue;
                FrameRange write;
                if (!memoryRange(write, writer, references[earlier]) || read.offset - write.offset < write.size || write.offset - read.offset < read.size)
                    return false;
            }
            return true;
        }

        bool prepareValue(MicroReg reg, MicroInstrRef at)
        {
            if (!reg.isValid() || reg.isSpecial())
                return true;
            const auto* atPosition = positions->find(at.get());
            if (!atPosition)
                return false;
            if (!reg.isVirtual())
            {
                for (uint32_t index = first; index < *atPosition; ++index)
                {
                    const auto* useDef = ssa->instrUseDef(references[index]);
                    if (useDef && std::ranges::find(useDef->defs, reg) != useDef->defs.end())
                        return false;
                }
                return true;
            }
            if (ssa->sameValueAt(reg, references[first], at))
                return true;
            const auto definition = ssa->reachingDef(reg, at);
            return definition.valid() && !definition.isPhi && prepareInstruction(definition.instRef);
        }

        bool prepareInstruction(MicroInstrRef reference)
        {
            if (order.size() >= K_MAX_ROOT_HOIST_INSTRUCTIONS)
                return false;
            if (selected.contains(reference.get()))
                return true;
            const auto* position = positions->find(reference.get());
            if (!position || *position <= first || *position >= second || !visiting.insert(reference.get()))
                return false;
            const auto&   instruction = *context->instructions->ptr(reference);
            const auto&   info        = MicroInstr::info(instruction.op);
            const auto*   ops         = instruction.ops(*context->operands);
            const auto*   useDef      = ssa->instrUseDef(reference);
            RootCandidate root;
            if (readRoot(root, instruction, *context->operands, reference))
                return false;
            if (!useDef || useDef->defs.size() != 1 || !useDef->defs[0].isVirtual() ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) || info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::WritesMemory) || info.flags.has(MicroInstrFlagsE::UsesCpuFlags) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction) || MicroPassHelpers::instructionActuallyDefinesCpuFlags(instruction, ops) ||
                context->builder->virtualRegForbiddenPhysRegs().contains(useDef->defs[0]) || context->builder->shouldPreserveVirtualCopy(useDef->defs[0]) ||
                !canHoistRead(instruction, *position))
                return false;
            for (const MicroReg reg : useDef->uses)
                if (!prepareValue(reg, reference))
                    return false;
            const auto modes = info.resolvedRegModes(ops);
            if (std::ranges::find(modes, MicroInstrRegMode::UseDef) != modes.end())
                return false;
            selected.insert(reference.get());
            order.push_back(reference);
            return true;
        }
    };
}

bool SlpVectorize::exposeScalarValues(MicroPassContext& context)
{
    if (!context.builder || !context.instructions || !context.operands || !context.encoder ||
        !context.builder->backendBuildCfg().optimizes() || !context.builder->backendBuildCfg().vectorize ||
        !context.encoder->supportsNonDestructiveFloatBinary())
        return false;
    std::vector<ScalarBlock> blocks;
    ScalarBlock              current;
    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        const auto flags = MicroInstr::info(it->op).flags;
        if (it->op == MicroInstrOpcode::Label || flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
            flags.has(MicroInstrFlagsE::JumpInstruction) || flags.has(MicroInstrFlagsE::IsCallInstruction))
        {
            if (current.roots >= 2)
            {
                current.end = it.current;
                blocks.push_back(std::move(current));
            }
            current = {};
            continue;
        }
        const auto* ops = it->ops(*context.operands);
        if (it->op == MicroInstrOpcode::OpBinaryRegReg && ops && ops[2].opBits == MicroOpBits::B64 && ops[3].microOp == MicroOp::FloatSqrt)
            ++current.roots;
        current.instructions.push_back(it.current);
    }
    if (blocks.empty())
        return false;

    MicroSsaState ssa;
    ssa.build(*context.builder, *context.instructions, *context.operands, context.encoder);
    if (!ssa.isValid())
        return false;
    const auto                  observed  = observedUpperHalves(context, ssa);
    uint32_t                    nextFloat = MicroPassHelpers::computeNextVirtualFloatRegIndex(context);
    std::vector<ScalarRewrite>  rewrites;
    std::vector<ScalarExitCopy> exitCopies;
    for (const ScalarBlock& block : blocks)
    {
        FlatKeyMap<MicroReg>                   names;
        std::unordered_map<MicroReg, uint32_t> lastDefinitions;
        std::unordered_set<uint32_t>           members;
        bool                                   eligible = true;
        for (const MicroInstrRef reference : block.instructions)
        {
            members.insert(reference.get());
            const auto* useDef = ssa.instrUseDef(reference);
            if (!useDef)
            {
                eligible = false;
                break;
            }
            for (const MicroReg reg : useDef->defs)
            {
                if (!reg.isVirtualFloat())
                    continue;
                uint32_t value;
                if (!ssa.defValue(reg, reference, value) || observed[value] ||
                    context.builder->virtualRegForbiddenPhysRegs().contains(reg) || context.builder->shouldPreserveVirtualCopy(reg) ||
                    nextFloat >= MicroReg::K_MAX_INDEX)
                {
                    eligible = false;
                    break;
                }
                names.emplace(value, MicroReg::virtualFloatReg(nextFloat++));
                lastDefinitions.insert_or_assign(reg, value);
            }
        }
        if (!eligible || names.empty())
            continue;
        const auto useName = [&](MicroReg reg, MicroInstrRef reference) {
            if (!reg.isVirtualFloat())
                return reg;
            const uint32_t value = ssa.reachingValueId(reg, reference);
            const auto*    name  = names.find(value);
            return name ? *name : reg;
        };
        const size_t rewriteStart = rewrites.size();
        const size_t exitStart    = exitCopies.size();
        for (const MicroInstrRef reference : block.instructions)
        {
            const auto& instruction = *context.instructions->ptr(reference);
            const auto* ops         = instruction.ops(*context.operands);
            if (!ops)
                continue;
            const auto    modes = MicroInstr::info(instruction.op).resolvedRegModes(ops);
            ScalarRewrite rewrite;
            rewrite.reference = reference;
            rewrite.opcode    = instruction.op;
            rewrite.operands.assign(ops, ops + instruction.numOperands);
            for (uint32_t operand = 0; operand < modes.size(); ++operand)
            {
                if (modes[operand] == MicroInstrRegMode::None || !ops[operand].reg.isVirtualFloat())
                    continue;
                const MicroReg original = ops[operand].reg;
                if (modes[operand] == MicroInstrRegMode::Use)
                    rewrite.operands[operand].reg = useName(original, reference);
                else
                {
                    uint32_t value;
                    if (!ssa.defValue(original, reference, value) || !names.find(value))
                    {
                        eligible = false;
                        break;
                    }
                    rewrite.operands[operand].reg = *names.find(value);
                    if (modes[operand] == MicroInstrRegMode::UseDef)
                    {
                        if (operand || (instruction.op != MicroInstrOpcode::OpBinaryRegReg && instruction.op != MicroInstrOpcode::OpBinaryRegMem) || ops[2].opBits != MicroOpBits::B64)
                        {
                            eligible = false;
                            break;
                        }
                        const MicroOp operation = ops[3].microOp;
                        if (operation != MicroOp::FloatAdd && operation != MicroOp::FloatSubtract && operation != MicroOp::FloatMultiply && operation != MicroOp::FloatDivide &&
                            operation != MicroOp::FloatMin && operation != MicroOp::FloatMax && operation != MicroOp::FloatAnd && operation != MicroOp::FloatXor)
                        {
                            eligible = false;
                            break;
                        }
                        const MicroReg destination = rewrite.operands[0].reg;
                        const MicroReg left        = useName(original, reference);
                        rewrite.operands.clear();
                        MicroInstrOperand item;
                        item.reg = destination;
                        rewrite.operands.push_back(item);
                        item.reg = left;
                        rewrite.operands.push_back(item);
                        item.reg = useName(ops[1].reg, reference);
                        rewrite.operands.push_back(item);
                        item.opBits = ops[2].opBits;
                        rewrite.operands.push_back(item);
                        item.microOp = ops[3].microOp;
                        rewrite.operands.push_back(item);
                        rewrite.opcode = instruction.op == MicroInstrOpcode::OpBinaryRegReg ? MicroInstrOpcode::OpBinaryRegRegReg : MicroInstrOpcode::OpBinaryRegRegMem;
                        if (instruction.op == MicroInstrOpcode::OpBinaryRegMem)
                            rewrite.operands.push_back(ops[4]);
                        break;
                    }
                }
            }
            if (!eligible)
                break;
            if (instruction.op == MicroInstrOpcode::LoadRegReg && ops[0].reg.isVirtualFloat() && ops[1].reg.isAnyFloat())
            {
                if (ops[2].opBits != MicroOpBits::B64 && ops[2].opBits != MicroOpBits::B128)
                {
                    eligible = false;
                    break;
                }
                rewrite.operands[1].reg    = useName(ops[1].reg, reference);
                rewrite.operands[2].opBits = MicroOpBits::B64;
                rewrite.clearDestination   = true;
            }
            rewrites.push_back(std::move(rewrite));
        }
        if (eligible)
        {
            for (const auto& [reg, value] : lastDefinitions)
            {
                const auto* info        = ssa.valueInfo(value);
                bool        liveOutside = false;
                for (const auto& use : info->uses)
                {
                    if (use.kind == MicroSsaState::UseSite::Kind::Phi)
                    {
                        const auto* phi = ssa.phiInfo(use.phiIndex);
                        liveOutside |= phi && ssa.transitiveInstructionUseCount(phi->resultValueId, 1);
                    }
                    else if (!members.contains(use.instRef.get()))
                        liveOutside = true;
                }
                if (liveOutside)
                    exitCopies.push_back({block.end, reg, *names.find(value)});
            }
        }
        else
        {
            rewrites.resize(rewriteStart);
            exitCopies.resize(exitStart);
        }
    }
    if (rewrites.empty())
        return false;
    for (const ScalarRewrite& rewrite : rewrites)
    {
        auto* instruction = context.instructions->ptr(rewrite.reference);
        if (rewrite.clearDestination)
        {
            MicroInstrOperand clear[2];
            clear[0].reg    = rewrite.operands[0].reg;
            clear[1].opBits = MicroOpBits::B64;
            context.instructions->insertDerivedBefore(*context.operands, rewrite.reference, MicroInstrOpcode::ClearReg, clear);
            instruction = context.instructions->ptr(rewrite.reference);
        }
        if (instruction->numOperands == rewrite.operands.size() && instruction->op == rewrite.opcode)
            std::ranges::copy(rewrite.operands, instruction->ops(*context.operands));
        else
        {
            const auto replacement = context.instructions->insertDerivedBefore(*context.operands, rewrite.reference, rewrite.opcode, rewrite.operands);
            for (auto& relocation : context.builder->codeRelocations())
                if (relocation.instructionRef == rewrite.reference)
                    relocation.instructionRef = replacement;
            context.instructions->erase(rewrite.reference);
        }
    }
    for (const ScalarExitCopy& copy : exitCopies)
    {
        MicroInstrOperand clear[2];
        clear[0].reg    = copy.destination;
        clear[1].opBits = MicroOpBits::B64;
        context.instructions->insertDerivedBefore(*context.operands, copy.before, MicroInstrOpcode::ClearReg, clear);
        MicroInstrOperand move[3];
        move[0].reg    = copy.destination;
        move[1].reg    = copy.source;
        move[2].opBits = MicroOpBits::B64;
        context.instructions->insertDerivedBefore(*context.operands, copy.before, MicroInstrOpcode::LoadRegReg, move);
    }
    context.builder->invalidateControlFlowGraph();
    if (context.ssaState)
        context.ssaState->invalidate();
    context.passChanged = true;
    return true;
}

namespace
{
    bool rootResultIsScalar(const MicroPassContext& context, const MicroSsaState& ssa, const std::vector<uint8_t>& observed, const RootCandidate& root, bool replaceUses)
    {
        uint32_t value;
        if (!ssa.defValue(root.destination, root.reference, value) || observed[value] ||
            context.builder->virtualRegForbiddenPhysRegs().contains(root.destination) || context.builder->shouldPreserveVirtualCopy(root.destination))
            return false;
        for (const auto& use : ssa.valueInfo(value)->uses)
        {
            if (use.kind == MicroSsaState::UseSite::Kind::Phi)
            {
                const auto* phi = ssa.phiInfo(use.phiIndex);
                if (!phi || ssa.transitiveInstructionUseCount(phi->resultValueId, 1))
                    return false;
                continue;
            }
            if (!replaceUses)
                continue;
            const auto* instruction = context.instructions->ptr(use.instRef);
            const auto* ops         = instruction->ops(*context.operands);
            const auto  modes       = MicroInstr::info(instruction->op).resolvedRegModes(ops);
            for (uint32_t operand = 0; operand < modes.size(); ++operand)
                if (modes[operand] == MicroInstrRegMode::UseDef && ops[operand].reg == root.destination)
                    return false;
        }
        return true;
    }

    struct RootProducts
    {
        MicroReg inputs = MicroReg::invalid();
        MicroReg roots  = MicroReg::invalid();
    };

    // A pair of scalar products made from the two lanes of one packed square
    // root is the same packed multiply, without two extractions and a repack.
    // Match SSA values rather than register names: either input can have been
    // redefined between producing the roots and consuming the products.
    RootProducts packedRootProducts(const MicroPassContext& context, const MicroSsaState& ssa, const RootCandidate& first, const RootCandidate& second)
    {
        if (!first.divide)
            return {};
        const auto firstDef  = ssa.reachingDef(first.right, first.reference);
        const auto secondDef = ssa.reachingDef(second.right, second.reference);
        if (!firstDef.valid() || firstDef.isPhi || !secondDef.valid() || secondDef.isPhi ||
            ssa.transitiveInstructionUseCount(firstDef.valueId, 2) != 1 ||
            ssa.transitiveInstructionUseCount(secondDef.valueId, 2) != 1 ||
            ssa.reachingValueId(first.left, first.reference) == firstDef.valueId ||
            ssa.reachingValueId(second.left, second.reference) == secondDef.valueId)
            return {};
        const auto* firstProduct  = context.instructions->ptr(firstDef.instRef);
        const auto* secondProduct = context.instructions->ptr(secondDef.instRef);
        if (!firstProduct || !secondProduct || firstProduct->op != MicroInstrOpcode::OpBinaryRegRegReg ||
            secondProduct->op != MicroInstrOpcode::OpBinaryRegRegReg)
            return {};
        const auto* firstOps  = firstProduct->ops(*context.operands);
        const auto* secondOps = secondProduct->ops(*context.operands);
        if (firstOps[3].opBits != MicroOpBits::B64 || secondOps[3].opBits != MicroOpBits::B64 ||
            firstOps[4].microOp != MicroOp::FloatMultiply || secondOps[4].microOp != MicroOp::FloatMultiply)
            return {};
        const auto rootsDef = ssa.reachingDef(firstOps[2].reg, firstDef.instRef);
        const auto highDef  = ssa.reachingDef(secondOps[2].reg, secondDef.instRef);
        if (!rootsDef.valid() || rootsDef.isPhi || !highDef.valid() || highDef.isPhi)
            return {};
        const auto* roots = context.instructions->ptr(rootsDef.instRef);
        const auto* high  = context.instructions->ptr(highDef.instRef);
        if (!roots || !high || roots->op != MicroInstrOpcode::VecUnaryRegReg || high->op != MicroInstrOpcode::OpBinaryRegRegImm)
            return {};
        const auto* rootOps = roots->ops(*context.operands);
        const auto* highOps = high->ops(*context.operands);
        if (rootOps[2].opBits != MicroOpBits::B128 || rootOps[3].microOp != MicroOp::VecSqrtF64 ||
            highOps[2].opBits != MicroOpBits::B128 || highOps[3].microOp != MicroOp::VecShiftRightBytes ||
            highOps[4].valueU64 != 8 || ssa.reachingValueId(highOps[1].reg, highDef.instRef) != rootsDef.valueId ||
            ssa.reachingValueId(rootOps[0].reg, first.reference) != rootsDef.valueId)
            return {};
        const auto inputDef = ssa.reachingDef(rootOps[1].reg, rootsDef.instRef);
        if (!inputDef.valid() || inputDef.isPhi)
            return {};
        const auto* input = context.instructions->ptr(inputDef.instRef);
        if (!input || input->op != MicroInstrOpcode::OpBinaryRegRegReg)
            return {};
        const auto* inputOps = input->ops(*context.operands);
        if (ssa.reachingValueId(inputOps[1].reg, inputDef.instRef) == MicroSsaState::K_INVALID_VALUE ||
            ssa.reachingValueId(inputOps[2].reg, inputDef.instRef) == MicroSsaState::K_INVALID_VALUE)
            return {};
        if (inputOps[3].opBits != MicroOpBits::B128 || inputOps[4].microOp != MicroOp::VecUnpackLo64 ||
            ssa.reachingValueId(inputOps[1].reg, inputDef.instRef) != ssa.reachingValueId(firstOps[1].reg, firstDef.instRef) ||
            ssa.reachingValueId(inputOps[2].reg, inputDef.instRef) != ssa.reachingValueId(secondOps[1].reg, secondDef.instRef) ||
            ssa.reachingValueId(inputOps[0].reg, first.reference) != inputDef.valueId)
            return {};
        return {inputOps[0].reg, rootOps[0].reg};
    }

    void emitRootPair(MicroPassContext& context, const MicroSsaState& ssa, const RootCandidate& first, const RootCandidate& second, const RootHoistPlan& plan)
    {
        const auto           products = packedRootProducts(context, ssa, first, second);
        uint32_t             next     = MicroPassHelpers::computeNextVirtualFloatRegIndex(context);
        uint32_t             nextInt  = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
        FlatKeyMap<MicroReg> names;
        for (const MicroInstrRef reference : plan.order)
        {
            const auto*                    instruction = context.instructions->ptr(reference);
            std::vector<MicroInstrOperand> operands(instruction->ops(*context.operands), instruction->ops(*context.operands) + instruction->numOperands);
            const auto                     modes = MicroInstr::info(instruction->op).resolvedRegModes(operands.data());
            for (uint32_t operand = 0; operand < modes.size(); ++operand)
            {
                if (modes[operand] == MicroInstrRegMode::Use)
                {
                    const auto* name = names.find(ssa.reachingValueId(operands[operand].reg, reference));
                    if (name)
                        operands[operand].reg = *name;
                }
                else if (modes[operand] == MicroInstrRegMode::Def)
                {
                    uint32_t value;
                    ssa.defValue(operands[operand].reg, reference, value);
                    operands[operand].reg = operands[operand].reg.isVirtualFloat() ? MicroReg::virtualFloatReg(next++) : MicroReg::virtualIntReg(nextInt++);
                    names.emplace(value, operands[operand].reg);
                }
            }
            const auto                   replacement = context.instructions->insertDerivedBefore(*context.operands, first.reference, instruction->op, operands);
            std::vector<MicroRelocation> relocations;
            for (const auto& relocation : context.builder->codeRelocations())
                if (relocation.instructionRef == reference)
                {
                    auto copy           = relocation;
                    copy.instructionRef = replacement;
                    relocations.push_back(copy);
                }
            for (const auto& relocation : relocations)
                context.builder->codeRelocations().push_back(relocation);
        }
        // Share each hoisted definition with its existing scalar consumers.
        // The original definition remains available to destructive uses and phis.
        for (const MicroInstrRef reference : plan.order)
        {
            const auto* useDef = ssa.instrUseDef(reference);
            uint32_t    value;
            ssa.defValue(useDef->defs[0], reference, value);
            const auto replacement = *names.find(value);
            for (const auto& use : ssa.valueInfo(value)->uses)
            {
                if (use.kind != MicroSsaState::UseSite::Kind::Instruction)
                    continue;
                auto*      instruction = context.instructions->ptr(use.instRef);
                auto*      ops         = instruction->ops(*context.operands);
                const auto modes       = MicroInstr::info(instruction->op).resolvedRegModes(ops);
                for (uint32_t operand = 0; operand < modes.size(); ++operand)
                    if (modes[operand] == MicroInstrRegMode::Use && ops[operand].reg == useDef->defs[0])
                        ops[operand].reg = replacement;
            }
        }
        const auto renamed = [&](MicroReg reg) {
            const auto* name = names.find(ssa.reachingValueId(reg, second.reference));
            return name ? *name : reg;
        };
        const MicroReg    left   = MicroReg::virtualFloatReg(next++);
        const MicroReg    right  = MicroReg::virtualFloatReg(next++);
        const MicroReg    result = MicroReg::virtualFloatReg(next++);
        MicroInstrOperand binary[5];
        binary[0].reg     = left;
        binary[1].reg     = first.left;
        binary[2].reg     = renamed(second.left);
        binary[3].opBits  = MicroOpBits::B128;
        binary[4].microOp = MicroOp::VecUnpackLo64;
        context.instructions->insertDerivedBefore(*context.operands, first.reference, MicroInstrOpcode::OpBinaryRegRegReg, binary);
        if (first.divide)
        {
            binary[0].reg     = right;
            binary[1].reg     = products.inputs.isValid() ? products.inputs : first.right;
            binary[2].reg     = products.inputs.isValid() ? products.roots : renamed(second.right);
            binary[4].microOp = products.inputs.isValid() ? MicroOp::VecMulF64 : MicroOp::VecUnpackLo64;
            context.instructions->insertDerivedBefore(*context.operands, first.reference, MicroInstrOpcode::OpBinaryRegRegReg, binary);
            binary[0].reg     = result;
            binary[1].reg     = left;
            binary[2].reg     = right;
            binary[4].microOp = MicroOp::VecDivF64;
            context.instructions->insertDerivedBefore(*context.operands, first.reference, MicroInstrOpcode::OpBinaryRegRegReg, binary);
        }
        else
        {
            MicroInstrOperand unary[4];
            unary[0].reg     = result;
            unary[1].reg     = left;
            unary[2].opBits  = MicroOpBits::B128;
            unary[3].microOp = MicroOp::VecSqrtF64;
            context.instructions->insertDerivedBefore(*context.operands, first.reference, MicroInstrOpcode::VecUnaryRegReg, unary);
        }
        uint32_t value;
        ssa.defValue(first.destination, first.reference, value);
        for (const auto& use : ssa.valueInfo(value)->uses)
        {
            if (use.kind != MicroSsaState::UseSite::Kind::Instruction)
                continue;
            auto*      instruction = context.instructions->ptr(use.instRef);
            auto*      ops         = instruction->ops(*context.operands);
            const auto modes       = MicroInstr::info(instruction->op).resolvedRegModes(ops);
            for (uint32_t operand = 0; operand < modes.size(); ++operand)
                if (modes[operand] == MicroInstrRegMode::Use && ops[operand].reg == first.destination)
                    ops[operand].reg = result;
        }
        MicroInstrOperand extract[5];
        extract[0].reg     = second.destination;
        extract[1].reg     = result;
        extract[2].opBits  = MicroOpBits::B128;
        extract[3].microOp = MicroOp::VecShiftRightBytes;
        extract[4].setImmediateValue(ApInt(uint64_t{8}, 64));
        context.instructions->insertDerivedBefore(*context.operands, second.reference, MicroInstrOpcode::OpBinaryRegRegImm, extract);
        context.instructions->erase(first.reference);
        context.instructions->erase(second.reference);
        context.builder->invalidateControlFlowGraph();
        if (context.ssaState)
            context.ssaState->invalidate();
        context.passChanged = true;
    }

    bool packIndependentRoots(MicroPassContext& context)
    {
        if (!context.builder || !context.instructions || !context.operands || !context.encoder ||
            !context.builder->backendBuildCfg().optimizes() || !context.builder->backendBuildCfg().vectorize ||
            !context.encoder->supportsNonDestructiveFloatBinary())
            return false;
        uint32_t candidates = 0;
        for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
        {
            RootCandidate root;
            if (readRoot(root, *it, *context.operands, it.current))
                ++candidates;
        }
        if (candidates < 2)
            return false;
        const auto& math = context.builder->backendBuildCfg().math;
        if (!math.noNaN || !math.noInf)
            return false;
        bool changed = false;
        for (uint32_t kind = 0; kind < 2; ++kind)
        {
            bool paired = true;
            while (paired)
            {
                paired = false;
                MicroSsaState ssa;
                ssa.build(*context.builder, *context.instructions, *context.operands, context.encoder);
                if (!ssa.isValid() || MicroPassHelpers::computeNextVirtualFloatRegIndex(context) + K_MAX_ROOT_HOIST_INSTRUCTIONS + 4 >= MicroReg::K_MAX_INDEX ||
                    MicroPassHelpers::computeNextVirtualIntRegIndex(context) + K_MAX_ROOT_HOIST_INSTRUCTIONS >= MicroReg::K_MAX_INDEX)
                    return changed;
                const auto                 observed = observedUpperHalves(context, ssa);
                std::vector<MicroInstrRef> references;
                FlatKeyMap<uint32_t>       positions;
                for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
                {
                    positions.emplace(it.current.get(), static_cast<uint32_t>(references.size()));
                    references.push_back(it.current);
                }
                const auto stackOffsets = MicroPassHelpers::collectStackPointerOffsets(context, references.front(), 0);
                for (uint32_t firstIndex = 0; firstIndex < references.size() && !paired; ++firstIndex)
                {
                    RootCandidate first;
                    if (!readRoot(first, *context.instructions->ptr(references[firstIndex]), *context.operands, references[firstIndex]) || first.divide != (kind == 1) || !rootResultIsScalar(context, ssa, observed, first, true))
                        continue;
                    for (uint32_t secondIndex = firstIndex + 1; secondIndex < references.size() && secondIndex - firstIndex < K_ROOT_PAIR_WINDOW; ++secondIndex)
                    {
                        const auto& instruction = *context.instructions->ptr(references[secondIndex]);
                        const auto  flags       = MicroInstr::info(instruction.op).flags;
                        if (instruction.op == MicroInstrOpcode::Label || flags.has(MicroInstrFlagsE::TerminatorInstruction) || flags.has(MicroInstrFlagsE::JumpInstruction) || flags.has(MicroInstrFlagsE::IsCallInstruction))
                            break;
                        RootCandidate second;
                        if (!readRoot(second, instruction, *context.operands, references[secondIndex]) || second.divide != first.divide || second.destination == first.destination || !rootResultIsScalar(context, ssa, observed, second, false))
                            continue;
                        RootHoistPlan plan;
                        plan.context      = &context;
                        plan.ssa          = &ssa;
                        plan.references   = references;
                        plan.positions    = &positions;
                        plan.stackOffsets = &stackOffsets;
                        plan.first        = firstIndex;
                        plan.second       = secondIndex;
                        if (!plan.prepareValue(second.left, second.reference) || (second.divide && !plan.prepareValue(second.right, second.reference)))
                            continue;
                        emitRootPair(context, ssa, first, second, plan);
                        changed = paired = true;
                        break;
                    }
                }
            }
        }
        return changed;
    }
}

bool SlpVectorize::packRoots(MicroPassContext& context)
{
    return packIndependentRoots(context);
}

SWC_END_NAMESPACE();
