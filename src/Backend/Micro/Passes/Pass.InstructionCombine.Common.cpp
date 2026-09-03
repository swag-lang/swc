#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    //===-- Math / opcode helpers ------------------------------------------===//

    bool isSameOpBitsInt(MicroOpBits a, MicroOpBits b)
    {
        return a == b && a != MicroOpBits::Zero && a != MicroOpBits::B128;
    }

    bool isRightIdentity(MicroOp op, MicroOpBits opBits, uint64_t imm)
    {
        const uint64_t mask = getBitsMask(opBits);
        switch (op)
        {
            case MicroOp::Add:
            case MicroOp::Subtract:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
            case MicroOp::ShiftArithmeticLeft:
            case MicroOp::RotateLeft:
            case MicroOp::RotateRight:
                return (imm & mask) == 0;

            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
                return (imm & mask) == 1;

            case MicroOp::And:
                return (imm & mask) == mask;

            default:
                return false;
        }
    }

    bool isRightAbsorbing(MicroOp op, MicroOpBits opBits, uint64_t imm, uint64_t& outResult)
    {
        const uint64_t mask = getBitsMask(opBits);
        switch (op)
        {
            case MicroOp::And:
                if ((imm & mask) == 0)
                {
                    outResult = 0;
                    return true;
                }
                break;

            case MicroOp::Or:
                if ((imm & mask) == mask)
                {
                    outResult = mask;
                    return true;
                }
                break;

            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
                if ((imm & mask) == 0)
                {
                    outResult = 0;
                    return true;
                }
                break;

            default:
                break;
        }

        return false;
    }

    bool tryReassociate(MicroOp firstOp, uint64_t firstImm, MicroOp secondOp, uint64_t secondImm, MicroOpBits opBits, MicroOp& outOp, uint64_t& outImm)
    {
        return MicroPassHelpers::tryReassociateBinaryImmediate(firstOp, firstImm, secondOp, secondImm, opBits, outOp, outImm);
    }

    bool isMemFoldableOp(MicroOp op)
    {
        switch (op)
        {
            case MicroOp::Add:
            case MicroOp::Subtract:
            case MicroOp::And:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
                return true;
            default:
                return false;
        }
    }

    bool isControlOrCall(const MicroInstr& inst)
    {
        const auto& info = MicroInstr::info(inst.op);
        return info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
               info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
               info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
               inst.op == MicroInstrOpcode::Label;
    }

    bool writesMemory(const MicroInstr& inst)
    {
        return MicroInstr::info(inst.op).flags.has(MicroInstrFlagsE::WritesMemory);
    }

    MicroOpBits useReadBits(const MicroInstr& useInst, const MicroInstrOperand* useOps, MicroReg reg)
    {
        if (!useOps)
            return MicroOpBits::Zero;

        switch (useInst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::CmpRegReg:
                return useOps[2].opBits;

            case MicroInstrOpcode::CmpRegImm:
            case MicroInstrOpcode::OpBinaryRegImm:
                return useOps[1].opBits;

            case MicroInstrOpcode::OpBinaryRegReg:
                return useOps[2].opBits;

            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
                return useOps[1].reg == reg ? useOps[3].opBits : MicroOpBits::Zero;

            default:
                return MicroOpBits::Zero;
        }
    }

    // Counted through phis nothing reads: a value defined in a loop body
    // flows into a phi at the header whether or not the next iteration reads
    // it, and that phi kept every single-consumer fold out of loops.
    bool valueHasSingleUse(const MicroSsaState& ssa, MicroReg reg, MicroInstrRef defInstRef)
    {
        uint32_t valueId = 0;
        if (!ssa.defValue(reg, defInstRef, valueId))
            return false;
        return ssa.transitiveInstructionUseCount(valueId, 2) == 1;
    }

    MicroInstrRef singleDirectInstructionUse(const MicroSsaState& ssa, uint32_t valueId)
    {
        if (ssa.transitiveInstructionUseCount(valueId, 2) != 1)
            return MicroInstrRef::invalid();
        const auto* info = ssa.valueInfo(valueId);
        if (!info)
            return MicroInstrRef::invalid();
        MicroInstrRef found = MicroInstrRef::invalid();
        for (const auto& use : info->uses)
        {
            if (use.kind != MicroSsaState::UseSite::Kind::Instruction)
                continue;
            if (found.isValid())
                return MicroInstrRef::invalid();
            found = use.instRef;
        }
        return found;
    }

    bool isFrameDerivedAddress(const Context& ctx, MicroReg reg, MicroInstrRef atRef)
    {
        constexpr uint32_t K_MAX_ADDRESS_CHAIN = 8;

        for (uint32_t depth = 0; depth < K_MAX_ADDRESS_CHAIN; ++depth)
        {
            if (!reg.isValid())
                return false;
            if (reg == ctx.stackPointer)
                return true;
            if (!reg.isVirtualInt() || !ctx.ssa)
                return false;

            const MicroSsaState::ReachingDef def = ctx.ssa->reachingDef(reg, atRef);
            if (!def.valid() || def.isPhi || !def.inst)
                return false;

            const MicroInstrOperand* ops = def.inst->ops(*ctx.operands);
            if (!ops)
                return false;

            switch (def.inst->op)
            {
                case MicroInstrOpcode::LoadRegReg:
                case MicroInstrOpcode::LoadAddrRegMem:
                case MicroInstrOpcode::LoadAddrAmcRegMem:
                    reg   = ops[1].reg;
                    atRef = def.instRef;
                    break;
                default:
                    return false;
            }
        }

        return false;
    }

    bool isRelocatedAddress(const Context& ctx, MicroReg reg, MicroInstrRef atRef)
    {
        constexpr uint32_t K_MAX_COPY_CHAIN = 4;

        for (uint32_t depth = 0; depth < K_MAX_COPY_CHAIN; ++depth)
        {
            if (!reg.isVirtualInt() || !ctx.ssa)
                return false;

            const MicroSsaState::ReachingDef def = ctx.ssa->reachingDef(reg, atRef);
            if (!def.valid() || def.isPhi || !def.inst)
                return false;
            if (def.inst->op == MicroInstrOpcode::LoadRegPtrReloc)
                return true;
            if (def.inst->op != MicroInstrOpcode::LoadRegReg)
                return false;

            const MicroInstrOperand* ops = def.inst->ops(*ctx.operands);
            if (!ops)
                return false;
            reg   = ops[1].reg;
            atRef = def.instRef;
        }

        return false;
    }

    bool keepAccessScalar(Context& ctx, MicroInstrRef ref, MicroReg base)
    {
        if (!isFrameDerivedAddress(ctx, base, ref) && !isRelocatedAddress(ctx, base, ref))
            return false;
        return ctx.isInsideLoop(ref);
    }

    //===-- Context methods -------------------------------------------------===//

    bool Context::isInsideLoop(const MicroInstrRef ref)
    {
        if (!loopSlotsReady)
        {
            loopSlotsReady = true;
            loopSlotsAll   = true;
            if (builder)
            {
                const MicroControlFlowGraph& cfg   = builder->controlFlowGraph();
                const uint32_t               entry = MicroPassHelpers::findSingleCfgEntry(cfg);
                if (entry != MicroPassHelpers::MicroDomTree::K_INVALID_NODE && !cfg.hasUnsupportedControlFlowForCfgLiveness())
                {
                    const MicroPassHelpers::MicroDomTree dom   = MicroPassHelpers::computeInstructionDominators(cfg, entry);
                    const auto                           loops = MicroPassHelpers::findNaturalLoops(cfg, dom);
                    const auto                           refs  = cfg.instructionRefs();
                    for (const auto& loop : loops | std::views::values)
                    {
                        for (uint32_t i = 0; i < loop.inBody.size() && i < refs.size(); ++i)
                        {
                            if (loop.inBody[i])
                                loopSlots.insert(refs[i].get());
                        }
                    }
                    loopSlotsAll = false;
                }
            }
        }

        return loopSlotsAll || loopSlots.contains(ref.get());
    }

    bool Context::claimAll(std::initializer_list<MicroInstrRef> refs, bool allowRelocated)
    {
        for (const MicroInstrRef ref : refs)
            if (isClaimed(ref) || (!allowRelocated && isRelocated(ref)))
                return false;
        for (const MicroInstrRef ref : refs)
            claimed.insert(ref.get());
        return true;
    }
}

SWC_END_NAMESPACE();
