#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// Zero-extensions of values that are already zero-extended.
//
// A 32-bit integer write clears the upper half of its 64-bit register
// (MicroInstr.h states the contract). The lowering widens every `u32` it adds
// in 64 bits with an explicit `zero_extend b64 <- b32`, so a word loaded from
// memory and promoted for a 64-bit addition costs a load and a `mov r32, r32`
// that changes nothing, and masking the sum back with `& 0xFFFFFFFF` costs
// another where a 32-bit addition would have produced the masked value
// directly. ChaCha20's key-stream loop spent six of its twenty-five
// instructions that way.
//
// Two rules, both anchored on the extend:
//
//     zero_extend d, s, b64 <- b32          s defined by a 32-bit write
//   ->
//     d = s (b64)
//
//     op s, x, b64 ; zero_extend d, s, b64 <- b32
//   ->
//     op s, x, b32 ; d = s (b64)
//
// The second needs the operation's result read by the extend alone, and its
// low 32 bits to depend only on the low 32 bits of its inputs.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        constexpr uint32_t K_MAX_PHI_DEPTH = 8;

        // Binary operations whose low 32 result bits are a function of their
        // operands' low 32 bits, so a 32-bit mask over the 64-bit result is
        // the 32-bit operation itself. Shifts are out: a 64-bit count reaches
        // bit 63 where a 32-bit one is masked to five bits.
        bool lowBitsDependOnLowBits(const MicroOp op)
        {
            switch (op)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                case MicroOp::MultiplySigned:
                    return true;
                default:
                    return false;
            }
        }

        // Integer operations whose 32-bit form writes its whole destination.
        // The bit scans do not: they leave the destination untouched on a
        // zero source.
        bool writesWholeRegisterAt32(const MicroOp op)
        {
            switch (op)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                case MicroOp::MultiplySigned:
                case MicroOp::MultiplyUnsigned:
                case MicroOp::DivideSigned:
                case MicroOp::DivideUnsigned:
                case MicroOp::ModuloSigned:
                case MicroOp::ModuloUnsigned:
                case MicroOp::ShiftLeft:
                case MicroOp::ShiftArithmeticLeft:
                case MicroOp::ShiftRight:
                case MicroOp::ShiftArithmeticRight:
                case MicroOp::RotateLeft:
                case MicroOp::RotateRight:
                case MicroOp::Negate:
                case MicroOp::BitwiseNot:
                case MicroOp::ByteSwap:
                case MicroOp::PopCount:
                case MicroOp::LeadingZeroCount:
                case MicroOp::TrailingZeroCount:
                    return true;
                default:
                    return false;
            }
        }

        bool extendLeavesUpperHalfZero(const MicroOpBits dstBits, const MicroOpBits srcBits)
        {
            if (dstBits == MicroOpBits::B32)
                return true;
            return dstBits == MicroOpBits::B64 && getNumBits(srcBits) <= 32;
        }

        // Whether the instruction defines `reg` with its upper 32 bits zero: a
        // 32-bit integer write, or a widening whose source is at most 32 bits.
        bool definesZeroExtended32(const MicroInstr& inst, const MicroInstrOperand* ops, const MicroReg reg)
        {
            if (!ops || ops[0].reg != reg)
                return false;

            switch (inst.op)
            {
                case MicroInstrOpcode::ClearReg:
                    return true;
                case MicroInstrOpcode::LoadRegImm:
                    return ops[1].opBits == MicroOpBits::B32 ||
                           (ops[1].opBits == MicroOpBits::B64 && !ops[2].hasWideImmediateValue() && ops[2].valueU64 <= UINT32_MAX);
                case MicroInstrOpcode::LoadRegReg:
                case MicroInstrOpcode::LoadRegMem:
                    return ops[2].opBits == MicroOpBits::B32;
                case MicroInstrOpcode::LoadCondRegReg:
                case MicroInstrOpcode::LoadAmcRegMem:
                case MicroInstrOpcode::LoadAddrAmcRegMem:
                    return ops[3].opBits == MicroOpBits::B32;
                // A 32-bit `lea` writes the whole register, like any 32-bit result.
                case MicroInstrOpcode::LoadAddrRegMem:
                    return ops[2].opBits == MicroOpBits::B32;
                case MicroInstrOpcode::LoadZeroExtRegReg:
                case MicroInstrOpcode::LoadZeroExtRegMem:
                    return extendLeavesUpperHalfZero(ops[2].opBits, ops[3].opBits);
                case MicroInstrOpcode::LoadZeroExtAmcRegMem:
                    return extendLeavesUpperHalfZero(ops[3].opBits, ops[4].opBits);
                case MicroInstrOpcode::LoadSignedExtRegReg:
                case MicroInstrOpcode::LoadSignedExtRegMem:
                    return ops[2].opBits == MicroOpBits::B32;
                case MicroInstrOpcode::OpBinaryRegReg:
                case MicroInstrOpcode::OpBinaryRegMem:
                    return ops[2].opBits == MicroOpBits::B32 && writesWholeRegisterAt32(ops[3].microOp);
                case MicroInstrOpcode::OpBinaryRegImm:
                case MicroInstrOpcode::OpUnaryReg:
                    return ops[1].opBits == MicroOpBits::B32 && writesWholeRegisterAt32(ops[2].microOp);
                default:
                    return false;
            }
        }

        // A value is zero-extended when its definition is, or when every input
        // of the phi that merges it is. A phi met again on the way is the
        // loop-carried copy of the value being decided, which its other inputs
        // settle.
        bool valueIsZeroExtended32(const Context& ctx, const uint32_t valueId, SmallVector<uint32_t>& visited, const uint32_t depth)
        {
            if (depth >= K_MAX_PHI_DEPTH)
                return false;
            const MicroSsaState::ValueInfo* value = ctx.ssa->valueInfo(valueId);
            if (!value)
                return false;

            if (value->isPhi())
            {
                if (depth >= K_MAX_PHI_DEPTH)
                    return false;
                if (std::ranges::find(visited, valueId) != visited.end())
                    return true;
                visited.push_back(valueId);

                const MicroSsaState::PhiInfo* phi = ctx.ssa->phiInfo(value->phiIndex);
                if (!phi || phi->incomingValueIds.empty())
                    return false;
                for (const uint32_t incoming : phi->incomingValueIds)
                {
                    if (!valueIsZeroExtended32(ctx, incoming, visited, depth + 1))
                        return false;
                }
                return true;
            }

            const MicroInstr* inst = ctx.storage->ptr(value->instRef);
            if (inst && inst->op == MicroInstrOpcode::LoadRegReg)
            {
                const auto* ops = inst->ops(*ctx.operands);
                if (ops && ops[2].opBits == MicroOpBits::B64)
                {
                    const auto source = ctx.ssa->reachingDef(ops[1].reg, value->instRef);
                    return source.valid() && valueIsZeroExtended32(ctx, source.valueId, visited, depth + 1);
                }
            }
            return inst && definesZeroExtended32(*inst, inst->ops(*ctx.operands), value->reg);
        }

        bool isDwordToQwordExtend(const MicroInstrOperand* ops)
        {
            return ops &&
                   ops[0].reg.isVirtualInt() &&
                   ops[1].reg.isVirtualInt() &&
                   ops[2].opBits == MicroOpBits::B64 &&
                   ops[3].opBits == MicroOpBits::B32;
        }

        constexpr uint64_t K_UNBOUNDED = UINT64_MAX;

        uint64_t boundedAdd(uint64_t left, uint64_t right)
        {
            return left > K_UNBOUNDED - right ? K_UNBOUNDED : left + right;
        }

        uint64_t boundedMultiply(uint64_t left, uint64_t right)
        {
            return left && right > K_UNBOUNDED / left ? K_UNBOUNDED : left * right;
        }

        // All ones up to the highest set bit: the largest value an or or a xor
        // of values up to `value` can reach.
        uint64_t fillBelow(uint64_t value)
        {
            return value ? (UINT64_MAX >> std::countl_zero(value)) : 0;
        }

        // An upper bound on the unsigned value a definition leaves in its
        // register, or K_UNBOUNDED. Only operations whose result is exactly
        // the arithmetic one at their width are bounded: a sum that could
        // wrap is not.
        uint64_t valueUpperBound(const Context& ctx, uint32_t valueId, SmallVector<uint32_t>& visited, uint32_t depth);

        uint64_t regUpperBound(const Context& ctx, MicroReg reg, MicroInstrRef atRef, SmallVector<uint32_t>& visited, uint32_t depth)
        {
            if (!reg.isVirtualInt())
                return K_UNBOUNDED;
            const MicroSsaState::ReachingDef def = ctx.ssa->reachingDef(reg, atRef);
            return def.valid() ? valueUpperBound(ctx, def.valueId, visited, depth + 1) : K_UNBOUNDED;
        }

        uint64_t valueUpperBound(const Context& ctx, uint32_t valueId, SmallVector<uint32_t>& visited, uint32_t depth)
        {
            if (depth >= K_MAX_PHI_DEPTH)
                return K_UNBOUNDED;
            const MicroSsaState::ValueInfo* value = ctx.ssa->valueInfo(valueId);
            if (!value)
                return K_UNBOUNDED;

            if (value->isPhi())
            {
                // A loop-carried value is not bounded by its first input.
                if (std::ranges::find(visited, valueId) != visited.end())
                    return K_UNBOUNDED;
                visited.push_back(valueId);
                const MicroSsaState::PhiInfo* phi = ctx.ssa->phiInfo(value->phiIndex);
                if (!phi || phi->incomingValueIds.empty())
                    return K_UNBOUNDED;
                uint64_t bound = 0;
                for (const uint32_t incoming : phi->incomingValueIds)
                    bound = std::max(bound, valueUpperBound(ctx, incoming, visited, depth + 1));
                return bound;
            }

            const MicroInstr* inst = ctx.storage->ptr(value->instRef);
            if (!inst)
                return K_UNBOUNDED;
            const MicroInstrOperand* ops = inst->ops(*ctx.operands);
            if (!ops || ops[0].reg != value->reg)
                return K_UNBOUNDED;

            switch (inst->op)
            {
                case MicroInstrOpcode::ClearReg:
                    return 0;

                case MicroInstrOpcode::LoadRegImm:
                    return ops[2].hasWideImmediateValue() ? K_UNBOUNDED : ops[2].valueU64 & getBitsMask(ops[1].opBits);

                case MicroInstrOpcode::LoadZeroExtRegReg:
                case MicroInstrOpcode::LoadZeroExtRegMem:
                    return getBitsMask(ops[3].opBits);

                // A 32-bit move clears the upper half; a byte or word move keeps it.
                case MicroInstrOpcode::LoadRegReg:
                    if (ops[2].opBits == MicroOpBits::B64)
                        return regUpperBound(ctx, ops[1].reg, value->instRef, visited, depth);
                    if (ops[2].opBits == MicroOpBits::B32)
                        return std::min(regUpperBound(ctx, ops[1].reg, value->instRef, visited, depth), getBitsMask(MicroOpBits::B32));
                    return K_UNBOUNDED;

                case MicroInstrOpcode::LoadRegMem:
                    return ops[2].opBits == MicroOpBits::B32 ? getBitsMask(MicroOpBits::B32) : K_UNBOUNDED;

                case MicroInstrOpcode::LoadCondRegReg:
                {
                    if (getNumBits(ops[3].opBits) < 32)
                        return K_UNBOUNDED;
                    const uint64_t kept     = regUpperBound(ctx, ops[0].reg, value->instRef, visited, depth);
                    const uint64_t selected = regUpperBound(ctx, ops[1].reg, value->instRef, visited, depth);
                    return std::min(std::max(kept, selected), getBitsMask(ops[3].opBits));
                }

                case MicroInstrOpcode::OpBinaryRegImm:
                {
                    const MicroOpBits bits = ops[1].opBits;
                    if ((bits != MicroOpBits::B32 && bits != MicroOpBits::B64) || ops[3].hasWideImmediateValue())
                        return K_UNBOUNDED;
                    const uint64_t mask  = getBitsMask(bits);
                    const uint64_t imm   = ops[3].valueU64 & mask;
                    const uint64_t input = std::min(regUpperBound(ctx, ops[0].reg, value->instRef, visited, depth), mask);
                    uint64_t       bound = K_UNBOUNDED;
                    switch (ops[2].microOp)
                    {
                        case MicroOp::And:
                            return std::min(input, imm);
                        case MicroOp::ShiftRight:
                            return imm < getNumBits(bits) ? input >> imm : K_UNBOUNDED;
                        case MicroOp::Add:
                            bound = boundedAdd(input, imm);
                            break;
                        case MicroOp::Or:
                        case MicroOp::Xor:
                            bound = fillBelow(std::max(input, imm));
                            break;
                        case MicroOp::MultiplySigned:
                            if (input > mask >> 1 || imm > mask >> 1)
                                return K_UNBOUNDED;
                            bound = boundedMultiply(input, imm);
                            break;
                        case MicroOp::MultiplyUnsigned:
                            bound = boundedMultiply(input, imm);
                            break;
                        default:
                            return K_UNBOUNDED;
                    }
                    return bound <= mask ? bound : K_UNBOUNDED;
                }

                case MicroInstrOpcode::OpBinaryRegReg:
                {
                    const MicroOpBits bits = ops[2].opBits;
                    if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                        return K_UNBOUNDED;
                    const uint64_t mask  = getBitsMask(bits);
                    const uint64_t left  = std::min(regUpperBound(ctx, ops[0].reg, value->instRef, visited, depth), mask);
                    const uint64_t right = std::min(regUpperBound(ctx, ops[1].reg, value->instRef, visited, depth), mask);
                    uint64_t       bound = K_UNBOUNDED;
                    switch (ops[3].microOp)
                    {
                        case MicroOp::And:
                            return std::min(left, right);
                        case MicroOp::Add:
                            bound = boundedAdd(left, right);
                            break;
                        case MicroOp::Or:
                        case MicroOp::Xor:
                            bound = fillBelow(std::max(left, right));
                            break;
                        case MicroOp::MultiplySigned:
                            if (left > mask >> 1 || right > mask >> 1)
                                return K_UNBOUNDED;
                            bound = boundedMultiply(left, right);
                            break;
                        case MicroOp::MultiplyUnsigned:
                            bound = boundedMultiply(left, right);
                            break;
                        default:
                            return K_UNBOUNDED;
                    }
                    return bound <= mask ? bound : K_UNBOUNDED;
                }

                default:
                    return K_UNBOUNDED;
            }
        }

        void emitExtendAsCopy(Context& ctx, const MicroInstrRef ref, const MicroReg dst, const MicroReg src)
        {
            if (dst == src)
            {
                ctx.emitErase(ref);
                return;
            }

            MicroInstrOperand moveOps[3];
            moveOps[0].reg    = dst;
            moveOps[1].reg    = src;
            moveOps[2].opBits = MicroOpBits::B64;
            ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, moveOps);
        }
    }

    bool isValueZeroExtended32(const Context& ctx, uint32_t valueId)
    {
        SmallVector<uint32_t> visited;
        return ctx.ssa && valueIsZeroExtended32(ctx, valueId, visited, 0);
    }

    bool tryDropRedundantZeroExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        // The destination may be a physical register: the extension into the
        // return register of a `u32` function is the one every such function
        // ends with, and a full copy is what the allocator can fold away.
        if (!ops || !ops[0].reg.isAnyInt() || !ops[1].reg.isVirtualInt() || ops[2].opBits != MicroOpBits::B64 || ops[3].opBits != MicroOpBits::B32)
            return false;

        const MicroReg dst = ops[0].reg;
        const MicroReg src = ops[1].reg;

        const MicroSsaState::ReachingDef reaching = ctx.ssa->reachingDef(src, ref);
        if (!reaching.valid())
            return false;

        SmallVector<uint32_t> visited;
        if (!valueIsZeroExtended32(ctx, reaching.valueId, visited, 0))
            return false;

        if (!ctx.claimAll({ref}))
            return false;

        emitExtendAsCopy(ctx, ref, dst, src);
        return true;
    }

    // A dword whose sign bit is known clear, in a register whose upper half is
    // clear, is already its own sign extension: a count of booleans returned
    // as s32 needs no movsxd, as LLVM drops a sext of a known non-negative value.
    bool tryDropNonNegativeSignExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isAnyInt() || !ops[1].reg.isVirtualInt() || ops[2].opBits != MicroOpBits::B64 || ops[3].opBits != MicroOpBits::B32)
            return false;

        const MicroSsaState::ReachingDef reaching = ctx.ssa->reachingDef(ops[1].reg, ref);
        if (!reaching.valid())
            return false;

        SmallVector<uint32_t> visited;
        if (!valueIsZeroExtended32(ctx, reaching.valueId, visited, 0))
            return false;
        visited.clear();
        if (valueUpperBound(ctx, reaching.valueId, visited, 0) > 0x7FFFFFFFu)
            return false;

        if (!ctx.claimAll({ref}))
            return false;
        emitExtendAsCopy(ctx, ref, ops[0].reg, ops[1].reg);
        return true;
    }

    bool tryNarrowMaskedArithmetic(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!isDwordToQwordExtend(ops))
            return false;

        const MicroReg dst = ops[0].reg;
        const MicroReg src = ops[1].reg;

        const MicroSsaState::ReachingDef reaching = ctx.ssa->reachingDef(src, ref);
        if (!reaching.valid() || reaching.isPhi || !reaching.inst || ctx.isClaimed(reaching.instRef))
            return false;

        const MicroInstr&        def    = *reaching.inst;
        const MicroInstrOperand* defOps = def.ops(*ctx.operands);
        if (!defOps || defOps[0].reg != src)
            return false;

        // A memory operand narrows with the operation: the low four bytes of
        // the word are the low 32 bits of the value.
        uint8_t bitsSlot = 0;
        uint8_t immSlot  = 0;
        MicroOp op       = MicroOp::Add;
        switch (def.op)
        {
            case MicroInstrOpcode::OpBinaryRegReg:
            case MicroInstrOpcode::OpBinaryRegMem:
                bitsSlot = 2;
                op       = defOps[3].microOp;
                break;
            case MicroInstrOpcode::OpBinaryRegImm:
                bitsSlot = 1;
                immSlot  = 3;
                op       = defOps[2].microOp;
                break;
            default:
                return false;
        }

        if (defOps[bitsSlot].opBits != MicroOpBits::B64 || !lowBitsDependOnLowBits(op))
            return false;

        // Every other reader of the result wants its upper half.
        if (singleDirectInstructionUse(*ctx.ssa, reaching.valueId) != ref)
            return false;

        // The narrower operation sets the flags at 32 bits.
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, reaching.instRef, ctx.builder))
            return false;

        if (!ctx.claimAll({reaching.instRef, ref}))
            return false;

        MicroInstrOperand narrowOps[Action::K_MAX_OPS] = {};
        for (uint8_t i = 0; i < def.numOperands; ++i)
            narrowOps[i] = defOps[i];
        narrowOps[bitsSlot].opBits = MicroOpBits::B32;
        if (immSlot)
            narrowOps[immSlot].valueU64 &= 0xFFFFFFFFu;
        ctx.emitRewrite(reaching.instRef, def.op, std::span{narrowOps, def.numOperands});

        emitExtendAsCopy(ctx, ref, dst, src);
        return true;
    }

    // A byte or word masked by a constant of its width, then widened, is the
    // same mask applied at 32 bits: the bits above the byte are cleared by the
    // mask instead of the extension, as LLVM's `zext(and x, C)` becomes
    // `and (zext x), C`. `popcount`-style `(x >> i) & 1` sums lose a move per
    // bit.
    bool tryWidenMaskedNarrowValue(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isVirtualInt() || !ops[1].reg.isVirtualInt() || getNumBits(ops[2].opBits) < 32 ||
            (ops[3].opBits != MicroOpBits::B8 && ops[3].opBits != MicroOpBits::B16))
            return false;

        const MicroReg dst = ops[0].reg;
        const MicroReg src = ops[1].reg;

        const MicroSsaState::ReachingDef reaching = ctx.ssa->reachingDef(src, ref);
        if (!reaching.valid() || reaching.isPhi || !reaching.inst || ctx.isClaimed(reaching.instRef) ||
            reaching.inst->op != MicroInstrOpcode::OpBinaryRegImm)
            return false;

        const MicroInstrOperand* andOps = reaching.inst->ops(*ctx.operands);
        if (!andOps || andOps[0].reg != src || andOps[1].opBits != ops[3].opBits || andOps[2].microOp != MicroOp::And ||
            andOps[3].hasWideImmediateValue() || (andOps[3].valueU64 & ~getBitsMask(ops[3].opBits)) != 0)
            return false;

        if (singleDirectInstructionUse(*ctx.ssa, reaching.valueId) != ref)
            return false;

        // The wider mask sets the sign flag from another bit.
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, reaching.instRef, ctx.builder))
            return false;

        if (!ctx.claimAll({reaching.instRef, ref}))
            return false;

        MicroInstrOperand wideOps[4];
        for (uint8_t i = 0; i < 4; ++i)
            wideOps[i] = andOps[i];
        wideOps[1].opBits = MicroOpBits::B32;
        wideOps[3].setImmediateValue(ApInt(andOps[3].valueU64, 32));
        ctx.emitRewrite(reaching.instRef, MicroInstrOpcode::OpBinaryRegImm, wideOps);

        emitExtendAsCopy(ctx, ref, dst, src);
        return true;
    }
}

SWC_END_NAMESPACE();
