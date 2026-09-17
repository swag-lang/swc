#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Backend/Micro/MicroPassHelpers.h"

// Zero/sign extend whose upper bits are never read. Collapses to a plain
// LoadRegReg at srcBits, or an erase when dst == src.
//
// The bits a value's readers take are its demanded bits, walked through
// plain copies as LLVM's DemandedBits walks through moves and casts: a
// parameter sign-extended on entry, copied into a local and only compared at
// 32 bits never needs its upper half.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        constexpr uint32_t K_MAX_DEMAND_DEPTH = 4;

        // The widest bit any reader takes from the value `reg` holds; 64 when a
        // reader is not understood. A copy into another virtual register reads
        // what that register's own readers read, capped at the copy's width. A
        // phi reads what the merged value's readers read: one nothing reads,
        // as the SSA places at a join the value does not live through, reads
        // nothing, and one met again on a loop adds nothing new.
        uint32_t demandedBits(const MicroSsaState& ssa, const MicroStorage& storage, const MicroOperandStorage& operands, const MicroSsaState::ValueInfo& valueInfo, MicroReg reg, uint32_t depth, SmallVector<uint32_t>& visitedPhis)
        {
            uint32_t widest = 0;
            for (const auto& useSite : valueInfo.uses)
            {
                if (useSite.kind == MicroSsaState::UseSite::Kind::Phi)
                {
                    const MicroSsaState::PhiInfo* phi = ssa.phiInfo(useSite.phiIndex);
                    if (!phi || phi->reg != reg || depth >= K_MAX_DEMAND_DEPTH)
                        return 64;
                    if (std::ranges::find(visitedPhis, useSite.phiIndex) != visitedPhis.end())
                        continue;
                    visitedPhis.push_back(useSite.phiIndex);
                    const auto* phiValue = ssa.valueInfo(phi->resultValueId);
                    if (!phiValue)
                        return 64;
                    widest = std::max(widest, demandedBits(ssa, storage, operands, *phiValue, reg, depth + 1, visitedPhis));
                    if (widest >= 64)
                        return 64;
                    continue;
                }
                if (useSite.kind != MicroSsaState::UseSite::Kind::Instruction)
                    return 64;
                const MicroInstr* useInst = storage.ptr(useSite.instRef);
                if (!useInst)
                    return 64;
                const MicroInstrOperand* useOps  = useInst->ops(operands);
                const MicroOpBits        useBits = useReadBits(*useInst, useOps, reg);
                if (useBits == MicroOpBits::Zero)
                    return 64;

                uint32_t bits = getNumBits(useBits);
                if (useInst->op == MicroInstrOpcode::LoadRegReg && useOps[1].reg == reg && useOps[0].reg != reg &&
                    useOps[0].reg.isVirtual() && depth < K_MAX_DEMAND_DEPTH)
                {
                    uint32_t copyValueId = 0;
                    if (!ssa.defValue(useOps[0].reg, useSite.instRef, copyValueId))
                        return 64;
                    const auto* copyInfo = ssa.valueInfo(copyValueId);
                    if (!copyInfo)
                        return 64;
                    bits = std::min(bits, demandedBits(ssa, storage, operands, *copyInfo, useOps[0].reg, depth + 1, visitedPhis));
                }

                widest = std::max(widest, bits);
                if (widest >= 64)
                    return 64;
            }
            return widest;
        }

        // Whether `reg`, read at 32 bits where `atRef` reads it, is a boolean:
        // a setcc byte zero-extended to at least 32 bits, possibly copied.
        bool isExtendedBooleanByte(const Context& ctx, MicroReg reg, MicroInstrRef atRef)
        {
            constexpr uint32_t K_MAX_COPY_CHAIN = 4;
            for (uint32_t depth = 0; depth < K_MAX_COPY_CHAIN; ++depth)
            {
                const MicroSsaState::ReachingDef def = ctx.ssa->reachingDef(reg, atRef);
                if (!def.valid() || def.isPhi || !def.inst)
                    return false;

                const MicroInstrOperand* ops = def.inst->ops(*ctx.operands);
                if (def.inst->op == MicroInstrOpcode::LoadRegReg && ops[1].reg.isVirtualInt() && getNumBits(ops[2].opBits) >= 32)
                {
                    reg   = ops[1].reg;
                    atRef = def.instRef;
                    continue;
                }

                if (def.inst->op != MicroInstrOpcode::LoadZeroExtRegReg || ops[3].opBits != MicroOpBits::B8 || getNumBits(ops[2].opBits) < 32 ||
                    !ops[1].reg.isVirtualInt())
                    return false;
                const MicroSsaState::ReachingDef set = ctx.ssa->reachingDef(ops[1].reg, def.instRef);
                return set.valid() && !set.isPhi && set.inst && set.inst->op == MicroInstrOpcode::SetCondReg;
            }

            return false;
        }
    }

    // `a <=> b` lowers to zext(a > b) - zext(a < b) at 32 bits, sign-extended
    // into the result. The difference of two booleans fits a byte, so the
    // subtraction and the extension take the bytes, as LLVM narrows it, and
    // the two zero-extensions die.
    bool tryNarrowBooleanDifference(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[1].reg.isVirtualInt() || ops[3].opBits != MicroOpBits::B32 || getNumBits(ops[2].opBits) < 32)
            return false;

        const MicroSsaState::ReachingDef sub = ctx.ssa->reachingDef(ops[1].reg, ref);
        if (!sub.valid() || sub.isPhi || !sub.inst || sub.inst->op != MicroInstrOpcode::OpBinaryRegReg || ctx.isClaimed(sub.instRef))
            return false;

        const MicroInstrOperand* subOps = sub.inst->ops(*ctx.operands);
        if (subOps[3].microOp != MicroOp::Subtract || subOps[2].opBits != MicroOpBits::B32 || !subOps[1].reg.isVirtualInt() || subOps[0].reg == subOps[1].reg)
            return false;
        if (singleDirectInstructionUse(*ctx.ssa, sub.valueId) != ref)
            return false;
        if (!isExtendedBooleanByte(ctx, subOps[0].reg, sub.instRef) || !isExtendedBooleanByte(ctx, subOps[1].reg, sub.instRef))
            return false;
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, sub.instRef, ctx.builder))
            return false;
        if (!ctx.claimAll({ref, sub.instRef}))
            return false;

        MicroInstrOperand narrowOps[4];
        for (size_t idx = 0; idx < 4; ++idx)
            narrowOps[idx] = subOps[idx];
        narrowOps[2].opBits = MicroOpBits::B8;
        ctx.emitRewrite(sub.instRef, MicroInstrOpcode::OpBinaryRegReg, narrowOps);

        MicroInstrOperand extendOps[4];
        for (size_t idx = 0; idx < 4; ++idx)
            extendOps[idx] = ops[idx];
        extendOps[3].opBits = MicroOpBits::B8;
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadSignedExtRegReg, extendOps);
        return true;
    }

    bool tryNarrowExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;

        const MicroReg    dst     = ops[0].reg;
        const MicroReg    src     = ops[1].reg;
        const MicroOpBits dstBits = ops[2].opBits;
        const MicroOpBits srcBits = ops[3].opBits;

        if (!dst.isVirtual() || dstBits == srcBits || srcBits == MicroOpBits::Zero)
            return false;

        uint32_t valueId = 0;
        if (!ctx.ssa->defValue(dst, ref, valueId))
            return false;

        const auto* valueInfo = ctx.ssa->valueInfo(valueId);
        if (!valueInfo || valueInfo->uses.empty())
            return false;

        SmallVector<uint32_t> visitedPhis;
        if (demandedBits(*ctx.ssa, *ctx.storage, *ctx.operands, *valueInfo, dst, 0, visitedPhis) > getNumBits(srcBits))
            return false;

        if (!ctx.claimAll({ref}))
            return false;

        if (dst == src)
        {
            ctx.emitErase(ref);
            return true;
        }

        MicroInstrOperand moveOps[3];
        moveOps[0].reg    = dst;
        moveOps[1].reg    = src;
        moveOps[2].opBits = srcBits;
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, moveOps);
        return true;
    }

    // A 32-bit copy whose readers never look above bit 31 moves the whole
    // register instead. The zero-extension it performed is unobservable, and
    // a full-width move is what copy elimination merges and what the
    // allocator's same-register copies erase to: `mov ecx, ecx` survived to the
    // emitted code for every u32 parameter copied into a local. The readers are
    // claimed so no rule of the same sweep can lean on the upper half being
    // zero while it stops being so.
    //
    // A byte or word write whose readers take no more than its own bits is
    // widened to 32 bits the same way, as LLVM promotes i8 arithmetic on x86:
    // the write no longer keeps the rest of the register, so the value it
    // replaces can die, and a select of two such bytes becomes a cmov.
    bool tryWidenCopyWithNarrowReaders(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;

        const bool        immediate = inst.op == MicroInstrOpcode::LoadRegImm;
        const MicroOpBits bits      = ops[immediate ? 1 : 2].opBits;
        const bool        partial   = bits == MicroOpBits::B8 || bits == MicroOpBits::B16;
        if (bits != MicroOpBits::B32 && !partial)
            return false;
        if (immediate && (!partial || ops[2].hasWideImmediateValue()))
            return false;

        const MicroReg dst = ops[0].reg;
        const MicroReg src = immediate ? MicroReg::invalid() : ops[1].reg;
        if (!dst.isVirtualInt() || (!immediate && (!src.isAnyInt() || dst == src)))
            return false;
        if (partial && ctx.booleanMerges.contains(dst.index()))
            return false;

        uint32_t valueId = 0;
        if (!ctx.ssa->defValue(dst, ref, valueId))
            return false;
        const auto* valueInfo = ctx.ssa->valueInfo(valueId);
        if (!valueInfo || valueInfo->uses.empty())
            return false;
        SmallVector<uint32_t> visitedPhis;
        if (demandedBits(*ctx.ssa, *ctx.storage, *ctx.operands, *valueInfo, dst, 0, visitedPhis) > getNumBits(bits))
            return false;

        if (ctx.isRelocated(ref))
            return false;
        for (const auto& useSite : valueInfo->uses)
        {
            if (useSite.kind == MicroSsaState::UseSite::Kind::Instruction && ctx.isClaimed(useSite.instRef))
                return false;
        }
        if (!ctx.claimAll({ref}))
            return false;
        for (const auto& useSite : valueInfo->uses)
        {
            if (useSite.kind == MicroSsaState::UseSite::Kind::Instruction)
                ctx.claimed.insert(useSite.instRef.get());
        }

        if (immediate)
        {
            MicroInstrOperand loadOps[3];
            loadOps[0].reg      = dst;
            loadOps[1].opBits   = MicroOpBits::B32;
            loadOps[2].valueU64 = ops[2].valueU64 & (bits == MicroOpBits::B8 ? 0xFF : 0xFFFF);
            ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegImm, loadOps);
            return true;
        }

        MicroInstrOperand moveOps[3];
        moveOps[0].reg    = dst;
        moveOps[1].reg    = src;
        moveOps[2].opBits = partial ? MicroOpBits::B32 : MicroOpBits::B64;
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, moveOps);
        return true;
    }
}

SWC_END_NAMESPACE();
