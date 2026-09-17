#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// OpBinaryRegReg combiner: idempotent self-ops (v op v).

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        constexpr uint32_t K_MAX_INPLACE_WINDOW = 32;

        bool isInPlaceBinaryOp(MicroInstrOpcode op)
        {
            return op == MicroInstrOpcode::OpBinaryRegReg ||
                   op == MicroInstrOpcode::OpBinaryRegImm ||
                   op == MicroInstrOpcode::OpBinaryRegMem;
        }

        bool isBlockBoundary(const MicroInstr& inst)
        {
            const MicroInstrDef& info = MicroInstr::info(inst.op);
            return inst.op == MicroInstrOpcode::Label ||
                   info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                   info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                   info.flags.has(MicroInstrFlagsE::IsCallInstruction);
        }

        // A doubling with dead flags is one address computation. Read the
        // uncopied input when the two add operands name the same SSA value.
        bool tryDoubleInput(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (ops[3].microOp != MicroOp::Add || !ops[1].reg.isVirtualInt())
                return false;
            const MicroOpBits bits = ops[2].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                return false;
            MicroInstrRef copyRef;
            if (ops[0].reg != ops[1].reg)
            {
                if (!ctx.ssa)
                    return false;
                const auto def = ctx.ssa->reachingDef(ops[0].reg, ref);
                if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::LoadRegReg)
                    return false;
                const auto* copy = def.inst->ops(*ctx.operands);
                if (!copy || copy[1].reg != ops[1].reg || getNumBits(copy[2].opBits) < getNumBits(bits))
                    return false;
                const auto source = ctx.ssa->reachingDef(ops[1].reg, def.instRef);
                if (!source.valid() || ctx.ssa->reachingDef(ops[1].reg, ref).valueId != source.valueId)
                    return false;
                copyRef = def.instRef;
            }
            if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
                !ctx.claimAll({ref, copyRef.isValid() ? copyRef : ref}))
                return false;
            MicroInstrOperand address[8] = {};
            address[0].reg               = ops[0].reg;
            address[1].reg               = ops[1].reg;
            address[2].reg               = ops[1].reg;
            address[3].opBits            = bits;
            address[4].opBits            = MicroOpBits::B64;
            address[5].valueU64          = 1;
            ctx.emitRewrite(ref, MicroInstrOpcode::LoadAddrAmcRegMem, address, true);
            return true;
        }

        // Multiplication by the same small constant can follow an add/subtract.
        // Keep each input read at its original address-computation position.
        bool tryFactorScaledInputs(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (!ctx.ssa || !ops[1].reg.isVirtualInt() || ops[2].opBits != MicroOpBits::B64 ||
                (ops[3].microOp != MicroOp::Add && ops[3].microOp != MicroOp::Subtract))
                return false;
            std::array                              defs{ctx.ssa->reachingDef(ops[0].reg, ref), ctx.ssa->reachingDef(ops[1].reg, ref)};
            std::array                              copies{MicroInstrRef::invalid(), MicroInstrRef::invalid()};
            std::array<const MicroInstrOperand*, 2> addresses;
            for (uint32_t i = 0; i < 2; ++i)
            {
                if (defs[i].valid() && !defs[i].isPhi && defs[i].inst && defs[i].inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = defs[i].inst->ops(*ctx.operands);
                    if (!copy || copy[2].opBits != MicroOpBits::B64 || !copy[1].reg.isVirtualInt() ||
                        ctx.ssa->transitiveInstructionUseCount(defs[i].valueId, 2) != 1)
                        return false;
                    copies[i] = defs[i].instRef;
                    defs[i]   = ctx.ssa->reachingDef(copy[1].reg, copies[i]);
                }
                if (!defs[i].valid() || defs[i].isPhi || !defs[i].inst || defs[i].inst->op != MicroInstrOpcode::LoadAddrAmcRegMem ||
                    ctx.ssa->transitiveInstructionUseCount(defs[i].valueId, 2) != 1)
                    return false;
                addresses[i]        = defs[i].inst->ops(*ctx.operands);
                const auto* address = addresses[i];
                if (!address || !address[1].reg.isVirtualInt() || address[1].reg != address[2].reg ||
                    address[3].opBits != MicroOpBits::B64 || address[4].opBits != MicroOpBits::B64 || address[6].valueU64 != 0 ||
                    (address[5].valueU64 != 1 && address[5].valueU64 != 2 && address[5].valueU64 != 4 && address[5].valueU64 != 8))
                    return false;
                MicroInstrRef cursor = defs[i].instRef;
                for (uint32_t step = 0; step < K_MAX_INPLACE_WINDOW && cursor.isValid() && cursor != ref; ++step)
                {
                    const auto* current = ctx.instruction(cursor);
                    if (!current || isBlockBoundary(*current))
                        return false;
                    cursor = ctx.nextRef(cursor);
                }
                if (cursor != ref)
                    return false;
            }
            if (defs[0].instRef == defs[1].instRef || !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
                return false;

            if (addresses[0][5].valueU64 != addresses[1][5].valueU64 && addresses[0][1].reg == addresses[1][1].reg)
            {
                const uint64_t leftFactor  = addresses[0][5].valueU64 + 1;
                const uint64_t rightFactor = addresses[1][5].valueU64 + 1;
                const uint64_t factor      = ops[3].microOp == MicroOp::Add ? leftFactor + rightFactor
                                                                           : leftFactor > rightFactor ? leftFactor - rightFactor : 0;
                const bool encodable = factor == 1 || factor == 2 || factor == 3 || factor == 5 || factor == 9;
                const MicroReg source = addresses[0][1].reg;
                const auto sourceValue = ctx.ssa->reachingDef(source, defs[0].instRef);
                if (!encodable || !sourceValue.valid() || ctx.ssa->reachingDef(source, defs[1].instRef).valueId != sourceValue.valueId ||
                    ctx.ssa->reachingDef(source, ref).valueId != sourceValue.valueId ||
                    !ctx.claimAll({ref, defs[0].instRef, defs[1].instRef,
                                   copies[0].isValid() ? copies[0] : ref, copies[1].isValid() ? copies[1] : ref}))
                    return false;

                if (factor == 1)
                {
                    const MicroInstrOperand copy[3] = {ops[0], addresses[0][1], addresses[0][3]};
                    ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, copy);
                }
                else
                {
                    MicroInstrOperand combined[8] = {};
                    combined[0]                   = ops[0];
                    combined[1]                   = addresses[0][1];
                    combined[2]                   = addresses[0][1];
                    combined[3]                   = addresses[0][3];
                    combined[4]                   = addresses[0][4];
                    combined[5].valueU64          = factor - 1;
                    ctx.emitRewrite(ref, MicroInstrOpcode::LoadAddrAmcRegMem, combined, true);
                }
                ctx.emitErase(defs[0].instRef);
                ctx.emitErase(defs[1].instRef);
                return true;
            }

            if (addresses[0][5].valueU64 != addresses[1][5].valueU64 ||
                !ctx.claimAll({ref, defs[0].instRef, defs[1].instRef,
                               copies[0].isValid() ? copies[0] : ref, copies[1].isValid() ? copies[1] : ref}))
                return false;
            for (uint32_t i = 0; i < 2; ++i)
            {
                const MicroInstrOperand copy[3] = {addresses[i][0], addresses[i][1], addresses[i][3]};
                ctx.emitRewrite(defs[i].instRef, MicroInstrOpcode::LoadRegReg, copy);
            }
            MicroInstrOperand combined[8];
            std::copy_n(addresses[0], 8, combined);
            combined[0].reg = ops[0].reg;
            combined[1].reg = ops[0].reg;
            combined[2].reg = ops[0].reg;
            ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegReg, std::span{ops, 4});
            ctx.emitRewrite(ref, MicroInstrOpcode::LoadAddrAmcRegMem, combined, true);
            return true;
        }

        // Distribute a common shift through a single-use integer combination.
        // Addition/subtraction commute only with left shifts; bitwise operations
        // commute with either direction, including arithmetic right shifts.
        bool tryFactorCommonShifts(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (!ctx.ssa || !ops[1].reg.isVirtualInt())
                return false;
            const MicroOp outer    = ops[3].microOp;
            const bool    leftOnly = outer == MicroOp::Add || outer == MicroOp::Subtract;
            if (!leftOnly && outer != MicroOp::And && outer != MicroOp::Or && outer != MicroOp::Xor)
                return false;
            const MicroOpBits bits = ops[2].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                return false;
            std::array                              regs{ops[0].reg, ops[1].reg};
            std::array                              defs{ctx.ssa->reachingDef(regs[0], ref), ctx.ssa->reachingDef(regs[1], ref)};
            std::array                              copies{MicroInstrRef::invalid(), MicroInstrRef::invalid()};
            std::array<const MicroInstrOperand*, 2> shifts;
            for (uint32_t i = 0; i < 2; ++i)
            {
                if (defs[i].valid() && !defs[i].isPhi && defs[i].inst && defs[i].inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = defs[i].inst->ops(*ctx.operands);
                    if (!copy || copy[2].opBits != bits || !copy[1].reg.isVirtualInt() ||
                        ctx.ssa->transitiveInstructionUseCount(defs[i].valueId, 2) != 1)
                        return false;
                    copies[i] = defs[i].instRef;
                    regs[i]   = copy[1].reg;
                    defs[i]   = ctx.ssa->reachingDef(regs[i], copies[i]);
                }
                if (!defs[i].valid() || defs[i].isPhi || !defs[i].inst || defs[i].inst->op != MicroInstrOpcode::OpBinaryRegImm ||
                    ctx.ssa->transitiveInstructionUseCount(defs[i].valueId, 2) != 1)
                    return false;
                shifts[i] = defs[i].inst->ops(*ctx.operands);
                if (!shifts[i] || shifts[i][1].opBits != bits || shifts[i][3].hasWideImmediateValue() ||
                    shifts[i][3].valueU64 == 0 || shifts[i][3].valueU64 >= getNumBits(bits))
                    return false;
                const MicroOp shift = shifts[i][2].microOp;
                if (shift != MicroOp::ShiftLeft && shift != MicroOp::ShiftArithmeticLeft &&
                    (leftOnly || (shift != MicroOp::ShiftRight && shift != MicroOp::ShiftArithmeticRight)))
                    return false;
                if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, defs[i].instRef, ctx.builder))
                    return false;
                MicroInstrRef cursor = defs[i].instRef;
                for (uint32_t step = 0; step < K_MAX_INPLACE_WINDOW && cursor.isValid() && cursor != ref; ++step)
                {
                    const auto* current = ctx.instruction(cursor);
                    if (!current || isBlockBoundary(*current))
                        return false;
                    cursor = ctx.nextRef(cursor);
                }
                if (cursor != ref)
                    return false;
            }
            if (defs[0].instRef == defs[1].instRef || shifts[0][2].microOp != shifts[1][2].microOp ||
                shifts[0][3].valueU64 != shifts[1][3].valueU64 ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
                !ctx.claimAll({ref, defs[0].instRef, defs[1].instRef,
                               copies[0].isValid() ? copies[0] : ref, copies[1].isValid() ? copies[1] : ref}))
                return false;
            const MicroInstrOperand shifted[4] = {ops[0], shifts[0][1], shifts[0][2], shifts[0][3]};
            ctx.emitErase(defs[0].instRef);
            ctx.emitErase(defs[1].instRef);
            ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegReg, std::span{ops, 4});
            ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegImm, shifted);
            return true;
        }

        // Variable scalar shifts already mask their count to five or six bits.
        // Bypass a source mask only when it preserves all those low count bits.
        bool tryBypassShiftCountMaskImpl(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
        {
            const auto*    ops        = inst.ops(*ctx.operands);
            const uint32_t countIndex = inst.op == MicroInstrOpcode::OpBinaryRegRegReg ? 2 : 1;
            if (ctx.isClaimed(ref) || !ctx.ssa || !ops || !ops[0].reg.isVirtualInt() || !ops[countIndex].reg.isVirtualInt() ||
                (ops[countIndex + 1].opBits != MicroOpBits::B32 && ops[countIndex + 1].opBits != MicroOpBits::B64))
                return false;
            switch (ops[countIndex + 2].microOp)
            {
                case MicroOp::ShiftLeft:
                case MicroOp::ShiftArithmeticLeft:
                case MicroOp::ShiftRight:
                case MicroOp::ShiftArithmeticRight:
                case MicroOp::RotateLeft:
                case MicroOp::RotateRight:
                    break;
                default:
                    return false;
            }
            auto          mask = ctx.ssa->reachingDef(ops[countIndex].reg, ref);
            MicroInstrRef copyRef;
            if (mask.valid() && !mask.isPhi && mask.inst && mask.inst->op == MicroInstrOpcode::LoadRegReg)
            {
                const auto* copy = mask.inst->ops(*ctx.operands);
                if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < 32)
                    return false;
                copyRef = mask.instRef;
                mask    = ctx.ssa->reachingDef(copy[1].reg, copyRef);
            }
            if (!mask.valid() || mask.isPhi || !mask.inst || mask.inst->op != MicroInstrOpcode::OpBinaryRegImm)
                return false;
            const auto*    masked    = mask.inst->ops(*ctx.operands);
            const uint64_t countMask = getNumBits(ops[countIndex + 1].opBits) - 1;
            if (!masked || masked[2].microOp != MicroOp::And || masked[3].hasWideImmediateValue() ||
                getNumBits(masked[1].opBits) < 32 || (masked[3].valueU64 & countMask) != countMask)
                return false;
            const auto input = ctx.ssa->reachingDef(masked[0].reg, mask.instRef);
            if (!input.valid() || input.isPhi || !input.inst || input.inst->op != MicroInstrOpcode::LoadRegReg)
                return false;
            const auto* copied = input.inst->ops(*ctx.operands);
            if (!copied || !copied[1].reg.isVirtualInt() || getNumBits(copied[2].opBits) < 32)
                return false;
            const auto source = ctx.ssa->reachingDef(copied[1].reg, input.instRef);
            if (!source.valid() || ctx.ssa->reachingDef(copied[1].reg, ref).valueId != source.valueId ||
                !ctx.claimAll({ref, mask.instRef, input.instRef, copyRef.isValid() ? copyRef : ref}))
                return false;
            MicroInstrOperand shift[5];
            std::copy_n(ops, inst.numOperands, shift);
            shift[countIndex].reg = copied[1].reg;
            ctx.emitRewrite(ref, inst.op, std::span{shift, inst.numOperands});
            return true;
        }

        // Opposite variable shifts with counts c and -c form a rotation.
        // The three-operand shift form keeps both input snapshots explicit.
        bool tryFoldVariableRotate(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (!ctx.ssa || ops[3].microOp != MicroOp::Or || !ops[1].reg.isVirtualInt() ||
                (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64) ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
                return false;
            const MicroOpBits                       bits = ops[2].opBits;
            std::array                              defs{ctx.ssa->reachingDef(ops[0].reg, ref), ctx.ssa->reachingDef(ops[1].reg, ref)};
            std::array<MicroInstrRef, 2>            copies;
            std::array<const MicroInstrOperand*, 2> shifts;
            for (uint32_t side = 0; side < 2; ++side)
            {
                auto& def = defs[side];
                if (def.valid() && !def.isPhi && def.inst && def.inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = def.inst->ops(*ctx.operands);
                    if (!copy || getNumBits(copy[2].opBits) < getNumBits(bits) || !copy[1].reg.isVirtualInt() ||
                        ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                        return false;
                    copies[side] = def.instRef;
                    def          = ctx.ssa->reachingDef(copy[1].reg, copies[side]);
                }
                if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::OpBinaryRegRegReg ||
                    ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                    return false;
                shifts[side] = def.inst->ops(*ctx.operands);
                if (!shifts[side] || shifts[side][3].opBits != bits || !shifts[side][1].reg.isVirtualInt() || !shifts[side][2].reg.isVirtualInt() ||
                    (shifts[side][4].microOp != MicroOp::ShiftLeft && shifts[side][4].microOp != MicroOp::ShiftRight))
                    return false;
            }
            const MicroReg sourceReg = shifts[0][1].reg;
            const auto     source    = ctx.ssa->reachingDef(sourceReg, defs[0].instRef);
            if (shifts[0][4].microOp == shifts[1][4].microOp || sourceReg != shifts[1][1].reg || !source.valid() ||
                ctx.ssa->reachingDef(sourceReg, defs[1].instRef).valueId != source.valueId ||
                ctx.ssa->reachingDef(sourceReg, ref).valueId != source.valueId)
                return false;
            for (uint32_t negativeSide = 0; negativeSide < 2; ++negativeSide)
            {
                auto          negative = ctx.ssa->reachingDef(shifts[negativeSide][2].reg, defs[negativeSide].instRef);
                MicroInstrRef negativeCopy;
                if (negative.valid() && !negative.isPhi && negative.inst && negative.inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = negative.inst->ops(*ctx.operands);
                    if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < 32)
                        continue;
                    negativeCopy = negative.instRef;
                    negative     = ctx.ssa->reachingDef(copy[1].reg, negativeCopy);
                }
                if (!negative.valid() || negative.isPhi || !negative.inst)
                    continue;
                const auto*   negOps = negative.inst->ops(*ctx.operands);
                MicroReg      count;
                MicroInstrRef countRef = negative.instRef;
                MicroInstrRef zeroRef;
                MicroInstrRef inputCopy;
                // `width - n` counts like `0 - n`: the shift masks its count to the width.
                if (negative.inst->op == MicroInstrOpcode::OpBinaryRegReg && negOps && negOps[3].microOp == MicroOp::Subtract &&
                    getNumBits(negOps[2].opBits) >= 32)
                {
                    const auto zero = ctx.ssa->reachingDef(negOps[0].reg, negative.instRef);
                    if (!zero.valid() || zero.isPhi || !zero.inst)
                        continue;
                    const auto* zeroOps = zero.inst->ops(*ctx.operands);
                    if (!zeroOps || (zero.inst->op != MicroInstrOpcode::ClearReg && zero.inst->op != MicroInstrOpcode::LoadRegImm) ||
                        getNumBits(zeroOps[1].opBits) < 32 ||
                        (zero.inst->op != MicroInstrOpcode::ClearReg &&
                         (zero.inst->op != MicroInstrOpcode::LoadRegImm || zeroOps[2].hasWideImmediateValue() || zeroOps[2].valueU64 % getNumBits(bits) != 0)))
                        continue;
                    zeroRef = zero.instRef;
                    count   = negOps[1].reg;
                }
                else if (negative.inst->op == MicroInstrOpcode::OpUnaryReg && negOps && negOps[2].microOp == MicroOp::Negate &&
                         getNumBits(negOps[1].opBits) >= 32)
                {
                    const auto input = ctx.ssa->reachingDef(negOps[0].reg, negative.instRef);
                    if (!input.valid() || input.isPhi || !input.inst || input.inst->op != MicroInstrOpcode::LoadRegReg)
                        continue;
                    const auto* copy = input.inst->ops(*ctx.operands);
                    if (!copy || getNumBits(copy[2].opBits) < 32)
                        continue;
                    count     = copy[1].reg;
                    countRef  = input.instRef;
                    inputCopy = input.instRef;
                }
                else
                    continue;
                const uint32_t positiveSide  = 1 - negativeSide;
                MicroReg       positiveCount = shifts[positiveSide][2].reg;
                MicroInstrRef  positiveRef   = defs[positiveSide].instRef;
                MicroInstrRef  positiveCopy;
                if (positiveCount != count)
                {
                    const auto positive = ctx.ssa->reachingDef(positiveCount, positiveRef);
                    if (!positive.valid() || positive.isPhi || !positive.inst || positive.inst->op != MicroInstrOpcode::LoadRegReg)
                        continue;
                    const auto* copy = positive.inst->ops(*ctx.operands);
                    if (!copy || getNumBits(copy[2].opBits) < 32)
                        continue;
                    positiveCount = copy[1].reg;
                    positiveRef   = positive.instRef;
                    positiveCopy  = positive.instRef;
                }
                if (positiveCount != count || !count.isVirtualInt() || count == ops[0].reg)
                    continue;
                const auto countValue = ctx.ssa->reachingDef(count, countRef);
                if (!countValue.valid() || ctx.ssa->reachingDef(count, positiveRef).valueId != countValue.valueId ||
                    ctx.ssa->reachingDef(count, ref).valueId != countValue.valueId ||
                    !ctx.claimAll({ref, defs[0].instRef, defs[1].instRef, negative.instRef,
                                   copies[0].isValid() ? copies[0] : ref, copies[1].isValid() ? copies[1] : ref,
                                   negativeCopy.isValid() ? negativeCopy : ref, zeroRef.isValid() ? zeroRef : ref,
                                   inputCopy.isValid() ? inputCopy : ref, positiveCopy.isValid() ? positiveCopy : ref}))
                    continue;
                MicroInstrOperand copy[3];
                copy[0].reg    = ops[0].reg;
                copy[1].reg    = sourceReg;
                copy[2].opBits = bits;
                ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadRegReg, copy);
                MicroInstrOperand rotate[4];
                rotate[0].reg     = ops[0].reg;
                rotate[1].reg     = count;
                rotate[2].opBits  = bits;
                rotate[3].microOp = shifts[positiveSide][4].microOp == MicroOp::ShiftLeft ? MicroOp::RotateLeft : MicroOp::RotateRight;
                ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegReg, rotate);
                return true;
            }
            return false;
        }

        // Complementary logical shifts of one value form a rotate. Keep the
        // input reads and the left result's copies at their original positions.
        bool tryFoldRotate(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (!ctx.ssa || ops[3].microOp != MicroOp::Or || !ops[1].reg.isVirtualInt())
                return false;
            const MicroOpBits bits = ops[2].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                return false;
            std::array                                regs{ops[0].reg, ops[1].reg};
            std::array                                defs{ctx.ssa->reachingDef(regs[0], ref), ctx.ssa->reachingDef(regs[1], ref)};
            std::array                                copies{MicroInstrRef::invalid(), MicroInstrRef::invalid()};
            std::array<MicroSsaState::ReachingDef, 2> inputs;
            std::array<const MicroInstrOperand*, 2>   shifts;
            std::array<const MicroInstrOperand*, 2>   inputOps;
            for (uint32_t i = 0; i < 2; ++i)
            {
                if (defs[i].valid() && !defs[i].isPhi && defs[i].inst && defs[i].inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = defs[i].inst->ops(*ctx.operands);
                    if (!copy || (copy[2].opBits != bits && copy[2].opBits != MicroOpBits::B64) ||
                        !copy[1].reg.isVirtualInt() || ctx.ssa->transitiveInstructionUseCount(defs[i].valueId, 2) != 1)
                        return false;
                    copies[i] = defs[i].instRef;
                    regs[i]   = copy[1].reg;
                    defs[i]   = ctx.ssa->reachingDef(regs[i], copies[i]);
                }
                if (!defs[i].valid() || defs[i].isPhi || !defs[i].inst || defs[i].inst->op != MicroInstrOpcode::OpBinaryRegImm ||
                    ctx.ssa->transitiveInstructionUseCount(defs[i].valueId, 2) != 1)
                    return false;
                shifts[i] = defs[i].inst->ops(*ctx.operands);
                if (!shifts[i] || shifts[i][3].hasWideImmediateValue() ||
                    (shifts[i][2].microOp != MicroOp::ShiftLeft && shifts[i][2].microOp != MicroOp::ShiftRight) ||
                    shifts[i][3].valueU64 == 0 || shifts[i][3].valueU64 >= getNumBits(bits))
                    return false;
                inputs[i] = ctx.ssa->reachingDef(regs[i], defs[i].instRef);
                if (!inputs[i].valid() || inputs[i].isPhi || !inputs[i].inst || inputs[i].inst->op != MicroInstrOpcode::LoadRegReg)
                    return false;
                inputOps[i] = inputs[i].inst->ops(*ctx.operands);
                if (!inputOps[i] || inputOps[i][2].opBits != shifts[i][1].opBits || !inputOps[i][1].reg.isVirtualInt() ||
                    !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, defs[i].instRef, ctx.builder))
                    return false;
            }
            if (regs[0] == regs[1] || shifts[0][1].opBits != shifts[1][1].opBits ||
                shifts[0][2].microOp == shifts[1][2].microOp ||
                shifts[0][3].valueU64 + shifts[1][3].valueU64 != getNumBits(bits) ||
                inputOps[0][1].reg != inputOps[1][1].reg)
                return false;
            const auto source = ctx.ssa->reachingDef(inputOps[0][1].reg, inputs[0].instRef);
            if (!source.valid() || ctx.ssa->reachingDef(inputOps[1][1].reg, inputs[1].instRef).valueId != source.valueId)
                return false;
            if (shifts[0][1].opBits != bits &&
                (bits != MicroOpBits::B32 || shifts[0][1].opBits != MicroOpBits::B64 || !isValueZeroExtended32(ctx, source.valueId)))
                return false;
            if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
                return false;
            bool          seenSecond = false;
            MicroInstrRef cursor     = defs[0].instRef;
            for (uint32_t step = 0; step < K_MAX_INPLACE_WINDOW && cursor.isValid() && cursor != ref; ++step)
            {
                const auto* current = ctx.storage->ptr(cursor);
                if (!current || isBlockBoundary(*current))
                    return false;
                seenSecond |= cursor == defs[1].instRef;
                cursor = ctx.storage->findNextInstructionRef(cursor);
            }
            if (cursor != ref || !seenSecond ||
                !ctx.claimAll({ref, defs[0].instRef, defs[1].instRef, inputs[0].instRef, inputs[1].instRef,
                               copies[0].isValid() ? copies[0] : ref, copies[1].isValid() ? copies[1] : ref}))
                return false;
            MicroInstrOperand rotate[4];
            rotate[0].reg     = regs[0];
            rotate[1].opBits  = bits;
            rotate[2].microOp = shifts[0][2].microOp == MicroOp::ShiftLeft ? MicroOp::RotateLeft : MicroOp::RotateRight;
            rotate[3]         = shifts[0][3];
            ctx.emitRewrite(defs[0].instRef, MicroInstrOpcode::OpBinaryRegImm, rotate);
            ctx.emitErase(defs[1].instRef);
            if (copies[1].isValid())
                ctx.emitErase(copies[1]);
            ctx.emitErase(ref);
            return true;
        }

        struct MaskedInput
        {
            MicroReg      reg;
            MicroReg      rawSource;
            MicroReg      source;
            MicroInstrRef defRef;
            MicroInstrRef copyRef;
            MicroInstrRef sourceCopyRef;
            MicroInstrRef sourceRef;
            uint64_t      mask = 0;
        };

        bool readMaskedInput(MaskedInput& out, const Context& ctx, MicroReg reg, MicroInstrRef ref, MicroOpBits bits)
        {
            auto def = ctx.ssa->reachingDef(reg, ref);
            if (def.valid() && !def.isPhi && def.inst && def.inst->op == MicroInstrOpcode::LoadRegReg)
            {
                const auto* copy = def.inst->ops(*ctx.operands);
                if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < getNumBits(bits) ||
                    ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                    return false;
                out.copyRef = def.instRef;
                reg         = copy[1].reg;
                def         = ctx.ssa->reachingDef(reg, out.copyRef);
            }
            if (!def.valid() || def.isPhi || !def.inst || ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                return false;
            const auto* ops = def.inst->ops(*ctx.operands);
            if (!ops)
                return false;
            out.reg       = reg;
            out.defRef    = def.instRef;
            out.rawSource = reg;
            if (def.inst->op == MicroInstrOpcode::OpBinaryRegImm)
            {
                if (ops[1].opBits != bits || ops[2].microOp != MicroOp::And || ops[3].hasWideImmediateValue())
                    return false;
                out.mask = ops[3].valueU64 & getBitsMask(bits);
                if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, def.instRef, ctx.builder))
                    return false;
            }
            else if (def.inst->op == MicroInstrOpcode::LoadZeroExtRegReg)
            {
                if (ops[2].opBits != bits || !ops[1].reg.isVirtualInt() ||
                    ops[3].opBits == MicroOpBits::Zero || getNumBits(ops[3].opBits) > getNumBits(bits))
                    return false;
                out.mask      = getBitsMask(ops[3].opBits);
                out.rawSource = ops[1].reg;
            }
            else
                return false;

            out.source    = out.rawSource;
            out.sourceRef = out.defRef;
            const auto input = ctx.ssa->reachingDef(out.source, out.sourceRef);
            if (out.reg == out.rawSource && input.valid() && !input.isPhi && input.inst && input.inst->op == MicroInstrOpcode::LoadRegReg)
            {
                const auto* copy = input.inst->ops(*ctx.operands);
                if (copy && copy[1].reg.isVirtualInt() && getNumBits(copy[2].opBits) >= getNumBits(bits))
                {
                    out.source        = copy[1].reg;
                    out.sourceRef     = input.instRef;
                    out.sourceCopyRef = input.instRef;
                }
            }
            return true;
        }

        // (a & M) op (a & N) = a & (M op N). Zero-extensions are masks
        // too, so canonicalizing a byte mask early must not hide this fold.
        bool tryCombineBitMasks(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            const MicroOp op = ops[3].microOp;
            if (!ctx.ssa || (op != MicroOp::And && op != MicroOp::Or && op != MicroOp::Xor) || !ops[1].reg.isVirtualInt())
                return false;
            const MicroOpBits bits = ops[2].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                return false;
            MaskedInput lhs;
            MaskedInput rhs;
            if (!readMaskedInput(lhs, ctx, ops[0].reg, ref, bits) || !readMaskedInput(rhs, ctx, ops[1].reg, ref, bits) ||
                lhs.source != rhs.source || lhs.defRef == rhs.defRef)
                return false;
            const auto source = ctx.ssa->reachingDef(lhs.source, lhs.sourceRef);
            if (!source.valid() || ctx.ssa->reachingDef(rhs.source, rhs.sourceRef).valueId != source.valueId)
                return false;
            if (!ctx.claimAll({ref, lhs.defRef, rhs.defRef, lhs.copyRef.isValid() ? lhs.copyRef : ref, rhs.copyRef.isValid() ? rhs.copyRef : ref,
                              lhs.sourceCopyRef.isValid() ? lhs.sourceCopyRef : ref, rhs.sourceCopyRef.isValid() ? rhs.sourceCopyRef : ref}))
                return false;

            // Keep the left input snapshot where the original mask read it.
            if (lhs.reg == lhs.rawSource)
                ctx.emitErase(lhs.defRef);
            else
            {
                MicroInstrOperand copy[3];
                copy[0].reg    = lhs.reg;
                copy[1].reg    = lhs.rawSource;
                copy[2].opBits = bits;
                ctx.emitRewrite(lhs.defRef, MicroInstrOpcode::LoadRegReg, copy);
            }
            ctx.emitErase(rhs.defRef);
            if (rhs.copyRef.isValid())
                ctx.emitErase(rhs.copyRef);
            MicroInstrOperand combined[4];
            combined[0].reg      = ops[0].reg;
            combined[1].opBits   = bits;
            combined[2].microOp  = MicroOp::And;
            combined[3].valueU64 = op == MicroOp::And ? lhs.mask & rhs.mask : op == MicroOp::Or ? lhs.mask | rhs.mask : lhs.mask ^ rhs.mask;
            ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegImm, combined);
            return true;
        }

        // ~a ^ ~b = a ^ b. Erasing the two single-use complements keeps
        // their input reads in place. NOT preserves flags, and the final XOR
        // computes the same result and flags even when a branch reads them.
        bool tryCancelBitwiseComplements(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (!ctx.ssa || ops[3].microOp != MicroOp::Xor || !ops[1].reg.isVirtualInt())
                return false;
            const MicroOpBits bits = ops[2].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                return false;
            std::array defs{ctx.ssa->reachingDef(ops[0].reg, ref), ctx.ssa->reachingDef(ops[1].reg, ref)};
            std::array copies{MicroInstrRef::invalid(), MicroInstrRef::invalid()};
            for (uint32_t i = 0; i < 2; ++i)
            {
                if (defs[i].valid() && !defs[i].isPhi && defs[i].inst && defs[i].inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = defs[i].inst->ops(*ctx.operands);
                    if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < getNumBits(bits) ||
                        ctx.ssa->transitiveInstructionUseCount(defs[i].valueId, 2) != 1)
                        return false;
                    copies[i] = defs[i].instRef;
                    defs[i] = ctx.ssa->reachingDef(copy[1].reg, copies[i]);
                }
                if (!defs[i].valid() || defs[i].isPhi || !defs[i].inst || defs[i].inst->op != MicroInstrOpcode::OpUnaryReg ||
                    ctx.ssa->transitiveInstructionUseCount(defs[i].valueId, 2) != 1)
                    return false;
                const auto* unary = defs[i].inst->ops(*ctx.operands);
                if (!unary || unary[1].opBits != bits || unary[2].microOp != MicroOp::BitwiseNot)
                    return false;
            }
            if (defs[0].instRef == defs[1].instRef ||
                !ctx.claimAll({ref, defs[0].instRef, defs[1].instRef, copies[0].isValid() ? copies[0] : ref, copies[1].isValid() ? copies[1] : ref}))
                return false;
            ctx.emitErase(defs[0].instRef);
            ctx.emitErase(defs[1].instRef);
            return true;
        }

        // a + (-b) = a - b; a - (-b) = a + b. Removing the single-use
        // negation preserves its input snapshot through any intervening copy.
        bool tryFoldNegatedRhs(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (!ctx.ssa || (ops[3].microOp != MicroOp::Add && ops[3].microOp != MicroOp::Subtract) ||
                !ops[1].reg.isVirtualInt())
                return false;
            const MicroOpBits bits = ops[2].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                return false;
            auto          def = ctx.ssa->reachingDef(ops[1].reg, ref);
            MicroInstrRef copyRef;
            if (def.valid() && !def.isPhi && def.inst && def.inst->op == MicroInstrOpcode::LoadRegReg)
            {
                const auto* copy = def.inst->ops(*ctx.operands);
                if (!copy || !copy[1].reg.isVirtualInt() || copy[2].opBits != bits ||
                    ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                    return false;
                copyRef = def.instRef;
                def     = ctx.ssa->reachingDef(copy[1].reg, copyRef);
            }
            if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::OpUnaryReg ||
                ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                return false;
            const auto* unary = def.inst->ops(*ctx.operands);
            if (!unary || unary[1].opBits != bits || unary[2].microOp != MicroOp::Negate ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, def.instRef, ctx.builder) ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
                !ctx.claimAll({ref, def.instRef, copyRef.isValid() ? copyRef : ref}))
                return false;
            MicroInstrOperand binary[4];
            std::ranges::copy(std::span{ops, 4}, binary);
            binary[3].microOp = ops[3].microOp == MicroOp::Add ? MicroOp::Subtract : MicroOp::Add;
            ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegReg, binary);
            ctx.emitErase(def.instRef);
            return true;
        }

        // (-a) - b = -(a + b). Move the single-use negation after the
        // arithmetic while retaining both original operand snapshots.
        bool tryFoldNegatedLhs(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (!ctx.ssa || ops[3].microOp != MicroOp::Subtract ||
                !ops[1].reg.isVirtualInt())
                return false;
            const MicroOpBits bits = ops[2].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                return false;
            auto          def = ctx.ssa->reachingDef(ops[0].reg, ref);
            MicroInstrRef copyRef;
            if (def.valid() && !def.isPhi && def.inst && def.inst->op == MicroInstrOpcode::LoadRegReg)
            {
                const auto* copy = def.inst->ops(*ctx.operands);
                if (!copy || !copy[1].reg.isVirtualInt() || copy[2].opBits != bits ||
                    ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                    return false;
                copyRef = def.instRef;
                def     = ctx.ssa->reachingDef(copy[1].reg, copyRef);
            }
            if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::OpUnaryReg ||
                ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                return false;
            const auto* unary = def.inst->ops(*ctx.operands);
            if (!unary || unary[1].opBits != bits || unary[2].microOp != MicroOp::Negate ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, def.instRef, ctx.builder) ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
                !ctx.claimAll({ref, def.instRef, copyRef.isValid() ? copyRef : ref}))
                return false;
            MicroInstrOperand binary[4];
            std::ranges::copy(std::span{ops, 4}, binary);
            binary[3].microOp = MicroOp::Add;
            ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegReg, binary);
            MicroInstrOperand negate[3];
            negate[0].reg     = ops[0].reg;
            negate[1].opBits  = bits;
            negate[2].microOp = MicroOp::Negate;
            ctx.emitRewrite(ref, MicroInstrOpcode::OpUnaryReg, negate);
            ctx.emitErase(def.instRef);
            return true;
        }

        // a ^ ~b = ~(a ^ b). Keep both input snapshots, but let the XOR
        // consume the original value so the complemented temporary can die.
        bool tryMoveXorComplement(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (!ctx.ssa || ops[3].microOp != MicroOp::Xor || !ops[1].reg.isVirtualInt())
                return false;
            const MicroOpBits bits = ops[2].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                return false;
            for (uint32_t side = 0; side < 2; ++side)
            {
                auto          def = ctx.ssa->reachingDef(ops[side].reg, ref);
                MicroInstrRef copyRef;
                if (def.valid() && !def.isPhi && def.inst && def.inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = def.inst->ops(*ctx.operands);
                    if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < getNumBits(bits) ||
                        ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                        continue;
                    copyRef = def.instRef;
                    def     = ctx.ssa->reachingDef(copy[1].reg, copyRef);
                }
                if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::OpUnaryReg ||
                    ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                    continue;
                const auto* unary = def.inst->ops(*ctx.operands);
                if (!unary || unary[1].opBits != bits || unary[2].microOp != MicroOp::BitwiseNot ||
                    !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
                    !ctx.claimAll({ref, def.instRef, copyRef.isValid() ? copyRef : ref}))
                    continue;
                ctx.emitErase(def.instRef);
                ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegReg, std::span{ops, 4});
                MicroInstrOperand complement[3];
                complement[0].reg     = ops[0].reg;
                complement[1].opBits  = bits;
                complement[2].microOp = MicroOp::BitwiseNot;
                ctx.emitRewrite(ref, MicroInstrOpcode::OpUnaryReg, complement);
                return true;
            }
            return false;
        }

        // (a & mask) | (b & ~mask) = b ^ ((a ^ b) & mask).
        // Rebuild only the final value, after proving all three inputs survive
        // there. Dead-code elimination then removes the old single-use arms.
        bool tryFoldBitwiseSelect(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (!ctx.ssa || (ops[3].microOp != MicroOp::Or && ops[3].microOp != MicroOp::Xor) || !ops[1].reg.isVirtualInt())
                return false;
            const MicroOpBits bits = ops[2].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                return false;
            std::array                                  regs{ops[0].reg, ops[1].reg};
            std::array                                  defs{ctx.ssa->reachingDef(regs[0], ref), ctx.ssa->reachingDef(regs[1], ref)};
            std::array<MicroInstrRef, 2>                copies;
            std::array<MicroSsaState::ReachingDef, 2>   initial;
            std::array<std::array<MicroReg, 2>, 2>      inputs;
            std::array<std::array<MicroInstrRef, 2>, 2> inputRefs;
            for (uint32_t side = 0; side < 2; ++side)
            {
                auto& def = defs[side];
                if (def.valid() && !def.isPhi && def.inst && def.inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = def.inst->ops(*ctx.operands);
                    if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < getNumBits(bits) ||
                        ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                        return false;
                    copies[side] = def.instRef;
                    regs[side]   = copy[1].reg;
                    def          = ctx.ssa->reachingDef(regs[side], copies[side]);
                }
                if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::OpBinaryRegReg ||
                    ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                    return false;
                const auto* binary = def.inst->ops(*ctx.operands);
                if (!binary || binary[2].opBits != bits || binary[3].microOp != MicroOp::And || !binary[1].reg.isVirtualInt())
                    return false;
                initial[side]     = ctx.ssa->reachingDef(regs[side], def.instRef);
                const auto& start = initial[side];
                if (!start.valid() || start.isPhi || !start.inst || start.inst->op != MicroInstrOpcode::LoadRegReg)
                    return false;
                const auto* copy = start.inst->ops(*ctx.operands);
                if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < getNumBits(bits) ||
                    !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, def.instRef, ctx.builder))
                    return false;
                inputs[side]    = {copy[1].reg, binary[1].reg};
                inputRefs[side] = {start.instRef, def.instRef};
            }
            if (defs[0].instRef == defs[1].instRef)
                return false;

            for (uint32_t invertedSide = 0; invertedSide < 2; ++invertedSide)
            {
                const uint32_t normalSide = 1 - invertedSide;
                for (uint32_t invertedMask = 0; invertedMask < 2; ++invertedMask)
                {
                    MicroReg      inverse    = inputs[invertedSide][invertedMask];
                    auto          inverseDef = ctx.ssa->reachingDef(inverse, inputRefs[invertedSide][invertedMask]);
                    MicroInstrRef inverseCopy;
                    if (inverseDef.valid() && !inverseDef.isPhi && inverseDef.inst && inverseDef.inst->op == MicroInstrOpcode::LoadRegReg)
                    {
                        const auto* copy = inverseDef.inst->ops(*ctx.operands);
                        if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < getNumBits(bits))
                            continue;
                        inverseCopy = inverseDef.instRef;
                        inverse     = copy[1].reg;
                        inverseDef  = ctx.ssa->reachingDef(inverse, inverseCopy);
                    }
                    if (!inverseDef.valid() || inverseDef.isPhi || !inverseDef.inst || inverseDef.inst->op != MicroInstrOpcode::OpUnaryReg)
                        continue;
                    const auto* unary = inverseDef.inst->ops(*ctx.operands);
                    if (!unary || unary[1].opBits != bits || unary[2].microOp != MicroOp::BitwiseNot)
                        continue;
                    const auto inverseInput = ctx.ssa->reachingDef(inverse, inverseDef.instRef);
                    if (!inverseInput.valid() || inverseInput.isPhi || !inverseInput.inst || inverseInput.inst->op != MicroInstrOpcode::LoadRegReg)
                        continue;
                    const auto* maskCopy = inverseInput.inst->ops(*ctx.operands);
                    if (!maskCopy || !maskCopy[1].reg.isVirtualInt() || getNumBits(maskCopy[2].opBits) < getNumBits(bits))
                        continue;
                    const MicroReg mask = maskCopy[1].reg;
                    for (uint32_t normalMask = 0; normalMask < 2; ++normalMask)
                    {
                        if (mask != inputs[normalSide][normalMask])
                            continue;
                        const auto maskValue = ctx.ssa->reachingDef(mask, inverseInput.instRef);
                        if (!maskValue.valid() || ctx.ssa->reachingDef(mask, inputRefs[normalSide][normalMask]).valueId != maskValue.valueId ||
                            ctx.ssa->reachingDef(mask, ref).valueId != maskValue.valueId)
                            continue;
                        const MicroReg a      = inputs[normalSide][1 - normalMask];
                        const MicroReg b      = inputs[invertedSide][1 - invertedMask];
                        const auto     aValue = ctx.ssa->reachingDef(a, inputRefs[normalSide][1 - normalMask]);
                        const auto     bValue = ctx.ssa->reachingDef(b, inputRefs[invertedSide][1 - invertedMask]);
                        if (ops[0].reg == a || ops[0].reg == b || ops[0].reg == mask || !aValue.valid() || !bValue.valid() ||
                            ctx.ssa->reachingDef(a, ref).valueId != aValue.valueId || ctx.ssa->reachingDef(b, ref).valueId != bValue.valueId)
                            continue;
                        if (!ctx.claimAll({ref, defs[0].instRef, defs[1].instRef, initial[0].instRef, initial[1].instRef,
                                           inverseDef.instRef, inverseInput.instRef, inverseCopy.isValid() ? inverseCopy : ref,
                                           copies[0].isValid() ? copies[0] : ref, copies[1].isValid() ? copies[1] : ref}))
                            continue;
                        MicroInstrOperand copy[3];
                        copy[0].reg    = ops[0].reg;
                        copy[1].reg    = a;
                        copy[2].opBits = bits;
                        ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadRegReg, copy);
                        MicroInstrOperand binary[4];
                        binary[0].reg     = ops[0].reg;
                        binary[1].reg     = b;
                        binary[2].opBits  = bits;
                        binary[3].microOp = MicroOp::Xor;
                        ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegReg, binary);
                        binary[1].reg     = mask;
                        binary[3].microOp = MicroOp::And;
                        ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegReg, binary);
                        binary[1].reg     = b;
                        binary[3].microOp = MicroOp::Xor;
                        ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegReg, binary);
                        return true;
                    }
                }
            }
            return false;
        }

        // (a | b) - (a & b) = a ^ b: the subtrahend only contains bits
        // already set in the minuend, so no borrow can cross a bit position.
        bool tryFoldBitwiseDifference(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (!ctx.ssa || ops[3].microOp != MicroOp::Subtract || !ops[1].reg.isVirtualInt() ||
                (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64) ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
                return false;
            const MicroOpBits                           bits = ops[2].opBits;
            std::array                                  regs{ops[0].reg, ops[1].reg};
            std::array                                  defs{ctx.ssa->reachingDef(regs[0], ref), ctx.ssa->reachingDef(regs[1], ref)};
            std::array<MicroInstrRef, 2>                copies;
            std::array<MicroSsaState::ReachingDef, 2>   initial;
            std::array<std::array<MicroReg, 2>, 2>      inputs;
            std::array<std::array<MicroInstrRef, 2>, 2> inputRefs;
            for (uint32_t side = 0; side < 2; ++side)
            {
                auto& def = defs[side];
                if (def.valid() && !def.isPhi && def.inst && def.inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = def.inst->ops(*ctx.operands);
                    if (!copy || copy[2].opBits != bits || !copy[1].reg.isVirtualInt() ||
                        ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                        return false;
                    copies[side] = def.instRef;
                    regs[side]   = copy[1].reg;
                    def          = ctx.ssa->reachingDef(regs[side], copies[side]);
                }
                if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::OpBinaryRegReg ||
                    ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                    return false;
                const auto* binary = def.inst->ops(*ctx.operands);
                if (!binary || binary[2].opBits != bits || binary[3].microOp != (side == 0 ? MicroOp::Or : MicroOp::And) ||
                    !binary[1].reg.isVirtualInt() ||
                    !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, def.instRef, ctx.builder))
                    return false;
                initial[side] = ctx.ssa->reachingDef(regs[side], def.instRef);
                if (!initial[side].valid() || initial[side].isPhi || !initial[side].inst || initial[side].inst->op != MicroInstrOpcode::LoadRegReg)
                    return false;
                const auto* copy = initial[side].inst->ops(*ctx.operands);
                if (!copy || copy[2].opBits != bits || !copy[1].reg.isVirtualInt())
                    return false;
                inputs[side]    = {copy[1].reg, binary[1].reg};
                inputRefs[side] = {initial[side].instRef, def.instRef};
            }
            for (uint32_t order = 0; order < 2; ++order)
            {
                bool equal = true;
                for (uint32_t input = 0; input < 2; ++input)
                {
                    const MicroReg reg   = inputs[0][input];
                    const auto     value = ctx.ssa->reachingDef(reg, inputRefs[0][input]);
                    equal &= value.valid() && reg == inputs[1][input ^ order] &&
                             ctx.ssa->reachingDef(reg, inputRefs[1][input ^ order]).valueId == value.valueId &&
                             ctx.ssa->reachingDef(reg, ref).valueId == value.valueId;
                }
                if (!equal || ops[0].reg == inputs[0][1] ||
                    !ctx.claimAll({ref, defs[0].instRef, defs[1].instRef, initial[0].instRef, initial[1].instRef,
                                   copies[0].isValid() ? copies[0] : ref, copies[1].isValid() ? copies[1] : ref}))
                    continue;
                MicroInstrOperand copy[3];
                copy[0].reg    = ops[0].reg;
                copy[1].reg    = inputs[0][0];
                copy[2].opBits = bits;
                ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadRegReg, copy);
                MicroInstrOperand binary[4];
                binary[0].reg     = ops[0].reg;
                binary[1].reg     = inputs[0][1];
                binary[2].opBits  = bits;
                binary[3].microOp = MicroOp::Xor;
                ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegReg, binary);
                return true;
            }
            return false;
        }

        // An address and its unchanged base differ by the encoded displacement.
        // Replacing only the subtraction also preserves other address users.
        bool tryFoldAddressDifference(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (!ctx.ssa || ops[3].microOp != MicroOp::Subtract || !ops[1].reg.isVirtualInt() ||
                (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64) ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
                return false;
            const MicroOpBits bits = ops[2].opBits;
            for (uint32_t side = 0; side < 2; ++side)
            {
                auto          address = ctx.ssa->reachingDef(ops[side].reg, ref);
                MicroInstrRef addressCopy;
                if (address.valid() && !address.isPhi && address.inst && address.inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = address.inst->ops(*ctx.operands);
                    if (!copy || copy[2].opBits != bits || !copy[1].reg.isVirtualInt())
                        continue;
                    addressCopy = address.instRef;
                    address     = ctx.ssa->reachingDef(copy[1].reg, addressCopy);
                }
                if (!address.valid() || address.isPhi || !address.inst || address.inst->op != MicroInstrOpcode::LoadAddrRegMem)
                    continue;
                const auto* lea = address.inst->ops(*ctx.operands);
                if (!lea || lea[2].opBits != bits || !lea[1].reg.isVirtualInt() || lea[3].hasWideImmediateValue())
                    continue;
                MicroReg      other    = ops[1 - side].reg;
                MicroInstrRef otherRef = ref;
                MicroInstrRef otherCopy;
                if (other != lea[1].reg)
                {
                    const auto value = ctx.ssa->reachingDef(other, ref);
                    if (!value.valid() || value.isPhi || !value.inst || value.inst->op != MicroInstrOpcode::LoadRegReg)
                        continue;
                    const auto* copy = value.inst->ops(*ctx.operands);
                    if (!copy || copy[2].opBits != bits)
                        continue;
                    other     = copy[1].reg;
                    otherRef  = value.instRef;
                    otherCopy = value.instRef;
                }
                if (other != lea[1].reg)
                    continue;
                const auto base = ctx.ssa->reachingDef(other, address.instRef);
                if (!base.valid() || ctx.ssa->reachingDef(other, otherRef).valueId != base.valueId ||
                    !ctx.claimAll({ref, address.instRef, addressCopy.isValid() ? addressCopy : ref, otherCopy.isValid() ? otherCopy : ref}))
                    continue;
                MicroInstrOperand result[3];
                result[0].reg      = ops[0].reg;
                result[1].opBits   = bits;
                result[2].valueU64 = (side == 0 ? lea[3].valueU64 : 0ull - lea[3].valueU64) & getBitsMask(bits);
                ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegImm, result);
                return true;
            }
            return false;
        }

        // a ^ (a | b) = ~a & b; a & (a ^ b) = a & ~b.
        // Reconstruct the result only when both original inputs still reach it.
        bool tryFoldRepeatedBitwiseComplement(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            const MicroOp outer = ops[3].microOp;
            if (!ctx.ssa || (outer != MicroOp::And && outer != MicroOp::Xor) || !ops[1].reg.isVirtualInt())
                return false;
            const MicroOpBits bits = ops[2].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                return false;
            const MicroOp inner = outer == MicroOp::And ? MicroOp::Xor : MicroOp::Or;

            for (uint32_t side = 0; side < 2; ++side)
            {
                MicroReg      innerReg = ops[side].reg;
                auto          def      = ctx.ssa->reachingDef(innerReg, ref);
                MicroInstrRef resultCopy;
                if (def.valid() && !def.isPhi && def.inst && def.inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = def.inst->ops(*ctx.operands);
                    if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < getNumBits(bits) ||
                        ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                        continue;
                    resultCopy = def.instRef;
                    innerReg   = copy[1].reg;
                    def        = ctx.ssa->reachingDef(innerReg, resultCopy);
                }
                if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::OpBinaryRegReg ||
                    ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                    continue;
                const auto* binary = def.inst->ops(*ctx.operands);
                if (!binary || binary[2].opBits != bits || binary[3].microOp != inner || !binary[1].reg.isVirtualInt())
                    continue;
                const auto initial = ctx.ssa->reachingDef(innerReg, def.instRef);
                if (!initial.valid() || initial.isPhi || !initial.inst || initial.inst->op != MicroInstrOpcode::LoadRegReg)
                    continue;
                const auto* input = initial.inst->ops(*ctx.operands);
                if (!input || !input[1].reg.isVirtualInt() || getNumBits(input[2].opBits) < getNumBits(bits))
                    continue;

                const std::array inputs{input[1].reg, binary[1].reg};
                const std::array inputRefs{initial.instRef, def.instRef};
                for (uint32_t common = 0; common < 2; ++common)
                {
                    MicroReg      other    = ops[1 - side].reg;
                    MicroInstrRef otherRef = ref;
                    MicroInstrRef otherCopy;
                    if (other != inputs[common])
                    {
                        const auto reaching = ctx.ssa->reachingDef(other, ref);
                        if (!reaching.valid() || reaching.isPhi || !reaching.inst || reaching.inst->op != MicroInstrOpcode::LoadRegReg)
                            continue;
                        const auto* copy = reaching.inst->ops(*ctx.operands);
                        if (!copy || getNumBits(copy[2].opBits) < getNumBits(bits))
                            continue;
                        other     = copy[1].reg;
                        otherRef  = reaching.instRef;
                        otherCopy = reaching.instRef;
                    }
                    if (other != inputs[common])
                        continue;
                    const auto commonValue = ctx.ssa->reachingDef(other, inputRefs[common]);
                    if (!commonValue.valid() || ctx.ssa->reachingDef(other, otherRef).valueId != commonValue.valueId)
                        continue;
                    const uint32_t negatedIndex = outer == MicroOp::Xor ? common : 1 - common;
                    const MicroReg negated      = inputs[negatedIndex];
                    const MicroReg normal       = inputs[1 - negatedIndex];
                    const auto     negatedValue = ctx.ssa->reachingDef(negated, inputRefs[negatedIndex]);
                    const auto     normalValue  = ctx.ssa->reachingDef(normal, inputRefs[1 - negatedIndex]);
                    if (!negatedValue.valid() || !normalValue.valid() ||
                        ctx.ssa->reachingDef(negated, ref).valueId != negatedValue.valueId ||
                        ctx.ssa->reachingDef(normal, ref).valueId != normalValue.valueId ||
                        !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
                        continue;
                    if (!ctx.nextVirtualFloatRegIndex)
                        MicroPassHelpers::computeNextVirtualRegIndices(*ctx.passContext, ctx.nextVirtualIntRegIndex, ctx.nextVirtualFloatRegIndex);
                    if (ctx.nextVirtualIntRegIndex >= MicroReg::K_MAX_INDEX ||
                        !ctx.claimAll({ref, def.instRef, initial.instRef, resultCopy.isValid() ? resultCopy : ref, otherCopy.isValid() ? otherCopy : ref}))
                        continue;
                    const MicroReg    temporary = MicroReg::virtualIntReg(ctx.nextVirtualIntRegIndex++);
                    MicroInstrOperand copy[3];
                    copy[0].reg    = temporary;
                    copy[1].reg    = negated;
                    copy[2].opBits = bits;
                    ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadRegReg, copy);
                    MicroInstrOperand complement[3];
                    complement[0].reg     = temporary;
                    complement[1].opBits  = bits;
                    complement[2].microOp = MicroOp::BitwiseNot;
                    ctx.emitInsertBefore(ref, MicroInstrOpcode::OpUnaryReg, complement);
                    MicroInstrOperand binaryAnd[4];
                    binaryAnd[0].reg     = temporary;
                    binaryAnd[1].reg     = normal;
                    binaryAnd[2].opBits  = bits;
                    binaryAnd[3].microOp = MicroOp::And;
                    ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegReg, binaryAnd);
                    copy[0].reg = ops[0].reg;
                    copy[1].reg = temporary;
                    ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, copy);
                    return true;
                }
            }
            return false;
        }

        // Repeated bitwise inputs absorb or cancel; addition and subtraction
        // cancel as (a + b) - a = b and (a - b) + b = a.
        // The inner value must belong to this expression alone. Keep the reads
        // at the final operation only when their original values still reach it.
        bool tryFoldRepeatedInput(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            const MicroOp outer = ops[3].microOp;
            if (!ctx.ssa || (outer != MicroOp::And && outer != MicroOp::Or && outer != MicroOp::Xor && outer != MicroOp::Add && outer != MicroOp::Subtract) || !ops[1].reg.isVirtualInt())
                return false;
            const MicroOpBits bits = ops[2].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                return false;
            const bool    arithmetic = outer == MicroOp::Add || outer == MicroOp::Subtract;
            const MicroOp inner      = arithmetic ? (outer == MicroOp::Add ? MicroOp::Subtract : MicroOp::Add) : (outer == MicroOp::And ? MicroOp::Or : outer == MicroOp::Or ? MicroOp::And
                                                                                                                                                                             : MicroOp::Xor);

            for (uint32_t side = 0; side < (outer == MicroOp::Subtract ? 1u : 2u); ++side)
            {
                MicroReg      innerReg = ops[side].reg;
                auto          def      = ctx.ssa->reachingDef(innerReg, ref);
                MicroInstrRef resultCopy;
                if (def.valid() && !def.isPhi && def.inst && def.inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = def.inst->ops(*ctx.operands);
                    if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < getNumBits(bits) ||
                        ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                        continue;
                    resultCopy = def.instRef;
                    innerReg   = copy[1].reg;
                    def        = ctx.ssa->reachingDef(innerReg, resultCopy);
                }
                if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::OpBinaryRegReg ||
                    ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                    continue;
                const auto* binary   = def.inst->ops(*ctx.operands);
                const bool  foldOrXor = binary && outer == MicroOp::Or && binary[3].microOp == MicroOp::Xor;
                if (!binary || binary[2].opBits != bits || (binary[3].microOp != inner && !foldOrXor) || !binary[1].reg.isVirtualInt())
                    continue;
                const auto initial = ctx.ssa->reachingDef(innerReg, def.instRef);
                if (!initial.valid() || initial.isPhi || !initial.inst || initial.inst->op != MicroInstrOpcode::LoadRegReg)
                    continue;
                const auto* input = initial.inst->ops(*ctx.operands);
                if (!input || !input[1].reg.isVirtualInt() || getNumBits(input[2].opBits) < getNumBits(bits))
                    continue;

                const std::array inputs{input[1].reg, binary[1].reg};
                const std::array inputRefs{initial.instRef, def.instRef};
                for (uint32_t common = 0; common < 2; ++common)
                {
                    // Subtraction's right input is the only one an outer add cancels.
                    if (outer == MicroOp::Add && common != 1)
                        continue;
                    MicroReg      other    = ops[1 - side].reg;
                    MicroInstrRef otherRef = ref;
                    MicroInstrRef otherCopy;
                    if (other != inputs[common])
                    {
                        const auto reaching = ctx.ssa->reachingDef(other, ref);
                        if (!reaching.valid() || reaching.isPhi || !reaching.inst || reaching.inst->op != MicroInstrOpcode::LoadRegReg)
                            continue;
                        const auto* copy = reaching.inst->ops(*ctx.operands);
                        if (!copy || getNumBits(copy[2].opBits) < getNumBits(bits))
                            continue;
                        other     = copy[1].reg;
                        otherRef  = reaching.instRef;
                        otherCopy = reaching.instRef;
                    }
                    if (other != inputs[common])
                        continue;
                    const auto commonValue = ctx.ssa->reachingDef(other, inputRefs[common]);
                    if (!commonValue.valid() || ctx.ssa->reachingDef(other, otherRef).valueId != commonValue.valueId)
                        continue;
                    const uint32_t resultIndex = (outer == MicroOp::Xor || arithmetic) ? 1 - common : common;
                    const MicroReg result      = inputs[resultIndex];
                    const auto     resultValue = ctx.ssa->reachingDef(result, inputRefs[resultIndex]);
                    if (!resultValue.valid() || ctx.ssa->reachingDef(result, ref).valueId != resultValue.valueId)
                        continue;
                    if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
                        !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, def.instRef, ctx.builder))
                        continue;
                    if (!ctx.claimAll({ref, def.instRef, initial.instRef, resultCopy.isValid() ? resultCopy : ref, otherCopy.isValid() ? otherCopy : ref}))
                        continue;

                    MicroInstrOperand copy[3];
                    copy[0].reg    = ops[0].reg;
                    copy[2].opBits = bits;
                    if (foldOrXor)
                    {
                        MicroInstrOperand absorbed[4];
                        std::copy_n(binary, 4, absorbed);
                        absorbed[3].microOp = MicroOp::Or;
                        ctx.emitRewrite(def.instRef, MicroInstrOpcode::OpBinaryRegReg, absorbed);
                        copy[1].reg = innerReg;
                    }
                    else
                    {
                        copy[1].reg = result;
                        ctx.emitErase(def.instRef);
                    }
                    ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, copy);
                    if (resultCopy.isValid())
                        ctx.emitErase(resultCopy);
                    return true;
                }
            }
            return false;
        }

        // q + (a - 3q) is a - 2q. Strength reduction commonly exposes this
        // shape when quotient and remainder by three are combined. Keep the
        // subtraction in place and reduce its single-use address product.
        bool tryReduceAddedScaledDifference(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (!ctx.ssa || ops[3].microOp != MicroOp::Add || ops[2].opBits != MicroOpBits::B64 || !ops[1].reg.isVirtualInt())
                return false;

            for (uint32_t quotientSide = 0; quotientSide < 2; ++quotientSide)
            {
                MicroReg      quotient    = ops[quotientSide].reg;
                auto          quotientDef = ctx.ssa->reachingDef(quotient, ref);
                MicroInstrRef quotientCopy = MicroInstrRef::invalid();
                if (quotientDef.valid() && !quotientDef.isPhi && quotientDef.inst && quotientDef.inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = quotientDef.inst->ops(*ctx.operands);
                    if (!copy || copy[2].opBits != MicroOpBits::B64 || !copy[1].reg.isVirtualInt() ||
                        ctx.ssa->transitiveInstructionUseCount(quotientDef.valueId, 2) != 1)
                        continue;
                    quotientCopy = quotientDef.instRef;
                    quotient     = copy[1].reg;
                    quotientDef  = ctx.ssa->reachingDef(quotient, quotientCopy);
                }
                if (!quotientDef.valid())
                    continue;

                const MicroReg remainder    = ops[1 - quotientSide].reg;
                const auto     remainderDef = ctx.ssa->reachingDef(remainder, ref);
                if (!remainderDef.valid() || remainderDef.isPhi || !remainderDef.inst || remainderDef.inst->op != MicroInstrOpcode::OpBinaryRegReg ||
                    ctx.ssa->transitiveInstructionUseCount(remainderDef.valueId, 2) != 1)
                    continue;
                const auto* subtract = remainderDef.inst->ops(*ctx.operands);
                if (!subtract || subtract[0].reg != remainder || subtract[2].opBits != MicroOpBits::B64 || subtract[3].microOp != MicroOp::Subtract)
                    continue;

                const auto productDef = ctx.ssa->reachingDef(subtract[1].reg, remainderDef.instRef);
                if (!productDef.valid() || productDef.isPhi || !productDef.inst || productDef.inst->op != MicroInstrOpcode::LoadAddrAmcRegMem ||
                    ctx.ssa->transitiveInstructionUseCount(productDef.valueId, 2) != 1)
                    continue;
                const auto* product = productDef.inst->ops(*ctx.operands);
                if (!product || product[1].reg != quotient || product[2].reg != quotient ||
                    product[3].opBits != MicroOpBits::B64 || product[4].opBits != MicroOpBits::B64 ||
                    product[5].valueU64 != 2 || product[6].valueU64 != 0)
                    continue;
                const auto productQuotient = ctx.ssa->reachingDef(quotient, productDef.instRef);
                if (!productQuotient.valid() || productQuotient.valueId != quotientDef.valueId ||
                    ctx.ssa->reachingDef(quotient, ref).valueId != quotientDef.valueId)
                    continue;

                bool                       foldLogicalHalf = false;
                const MicroInstrOperand*   shift           = nullptr;
                const MicroSsaState::ValueInfo* quotientInfo = ctx.ssa->valueInfo(quotientDef.valueId);
                if (!quotientDef.isPhi && quotientDef.inst && quotientDef.inst->op == MicroInstrOpcode::OpBinaryRegImm && quotientInfo)
                {
                    shift = quotientDef.inst->ops(*ctx.operands);
                    foldLogicalHalf = shift && shift[0].reg == quotient && shift[1].opBits == MicroOpBits::B64 &&
                                      shift[2].microOp == MicroOp::ShiftRight && !shift[3].hasWideImmediateValue() && shift[3].valueU64 == 1;
                    for (const auto& use : quotientInfo->uses)
                    {
                        foldLogicalHalf &= use.kind == MicroSsaState::UseSite::Kind::Instruction &&
                                           (use.instRef == productDef.instRef || use.instRef == quotientCopy);
                    }
                    foldLogicalHalf &= MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, quotientDef.instRef, ctx.builder);
                }
                if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
                    !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, remainderDef.instRef, ctx.builder) ||
                    !ctx.claimAll({ref, remainderDef.instRef, productDef.instRef, quotientCopy.isValid() ? quotientCopy : ref,
                                   foldLogicalHalf ? quotientDef.instRef : ref}))
                    continue;

                if (foldLogicalHalf)
                {
                    MicroInstrOperand masked[4];
                    std::copy_n(shift, 4, masked);
                    masked[2].microOp = MicroOp::And;
                    masked[3].setImmediateValue(ApInt(UINT64_MAX - 1, 64));
                    ctx.emitRewrite(quotientDef.instRef, MicroInstrOpcode::OpBinaryRegImm, masked);
                    const MicroInstrOperand productCopy[3] = {product[0], product[1], product[3]};
                    ctx.emitRewrite(productDef.instRef, MicroInstrOpcode::LoadRegReg, productCopy);
                }
                else
                {
                    MicroInstrOperand reducedProduct[8];
                    std::copy_n(product, 8, reducedProduct);
                    reducedProduct[5].valueU64 = 1;
                    ctx.emitRewrite(productDef.instRef, MicroInstrOpcode::LoadAddrAmcRegMem, reducedProduct, true);
                }

                MicroInstrOperand copy[3];
                copy[0].reg    = ops[0].reg;
                copy[1].reg    = remainder;
                copy[2].opBits = MicroOpBits::B64;
                ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, copy);
                return true;
            }
            return false;
        }

        struct ProductBit
        {
            MicroReg      reg      = MicroReg::invalid();
            uint32_t      index    = 0;
            MicroInstrRef shiftRef = MicroInstrRef::invalid();
            MicroInstrRef copyRef  = MicroInstrRef::invalid();
        };

        // Recover the original bit when its shifted value is used only by
        // this mask. Other consumers retain the shift and its existing value.
        void recoverProductBit(const Context& ctx, ProductBit& bit, MicroInstrRef inputRef, MicroInstrRef productRef)
        {
            const auto shifted = ctx.ssa->reachingDef(bit.reg, inputRef);
            if (!shifted.valid() || shifted.isPhi || !shifted.inst || shifted.inst->op != MicroInstrOpcode::OpBinaryRegImm)
                return;
            const auto* shift = shifted.inst->ops(*ctx.operands);
            if (!shift || (shift[2].microOp != MicroOp::ShiftRight && shift[2].microOp != MicroOp::ShiftArithmeticRight) ||
                (shift[1].opBits != MicroOpBits::B32 && shift[1].opBits != MicroOpBits::B64) || shift[3].hasWideImmediateValue())
                return;
            const uint32_t index = static_cast<uint32_t>(shift[3].valueU64 & (getNumBits(shift[1].opBits) - 1));
            // TEST can reach the low dword with an immediate, or the top bit
            // of the full register through its sign flag.
            if ((index >= 32 && index != 63) || ctx.ssa->transitiveInstructionUseCount(shifted.valueId, 2) != 1)
                return;
            const auto initial = ctx.ssa->reachingDef(bit.reg, shifted.instRef);
            if (!initial.valid() || initial.isPhi || !initial.inst || initial.inst->op != MicroInstrOpcode::LoadRegReg)
                return;
            const auto* copy = initial.inst->ops(*ctx.operands);
            if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) <= index)
                return;
            const auto source = ctx.ssa->reachingDef(copy[1].reg, initial.instRef);
            if (!source.valid() || ctx.ssa->reachingDef(copy[1].reg, productRef).valueId != source.valueId ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, shifted.instRef, ctx.builder))
                return;
            bit.reg      = copy[1].reg;
            bit.index    = index;
            bit.shiftRef = shifted.instRef;
            bit.copyRef  = initial.instRef;
        }

        // A single extracted bit is a zero/one multiplier. Select the other input
        // directly and leave the original mask input available to other users.
        bool trySelectLowBitProduct(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            const MicroOpBits bits = ops[2].opBits;
            if (!ctx.ssa || ops[3].microOp != MicroOp::MultiplySigned || !ops[1].reg.isVirtualInt() ||
                (bits != MicroOpBits::B32 && bits != MicroOpBits::B64))
                return false;
            for (uint32_t side = 0; side < 2; ++side)
            {
                MicroReg      maskReg       = ops[side].reg;
                auto          mask          = ctx.ssa->reachingDef(maskReg, ref);
                MicroInstrRef maskCopy      = MicroInstrRef::invalid();
                uint32_t      maskCopyValue = 0;
                if (mask.valid() && !mask.isPhi && mask.inst && mask.inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = mask.inst->ops(*ctx.operands);
                    if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < getNumBits(bits))
                        continue;
                    maskCopyValue = mask.valueId;
                    maskCopy      = mask.instRef;
                    maskReg       = copy[1].reg;
                    mask          = ctx.ssa->reachingDef(maskReg, maskCopy);
                }
                if (!mask.valid() || mask.isPhi || !mask.inst || mask.inst->op != MicroInstrOpcode::OpBinaryRegImm)
                    continue;
                const auto* masked = mask.inst->ops(*ctx.operands);
                if (!masked || masked[3].hasWideImmediateValue() ||
                    (masked[1].opBits != MicroOpBits::B32 && masked[1].opBits != MicroOpBits::B64))
                    continue;
                const uint32_t topBit   = getNumBits(masked[1].opBits) - 1;
                const bool     topShift = masked[2].microOp == MicroOp::ShiftRight && (masked[3].valueU64 & topBit) == topBit;
                if (!topShift && (masked[2].microOp != MicroOp::And || masked[3].valueU64 != 1))
                    continue;
                if (ctx.ssa->transitiveInstructionUseCount(mask.valueId, 2) != 1 ||
                    (maskCopy.isValid() && ctx.ssa->transitiveInstructionUseCount(maskCopyValue, 2) != 1))
                    continue;
                const auto initial = ctx.ssa->reachingDef(maskReg, mask.instRef);
                if (!initial.valid() || initial.isPhi || !initial.inst || initial.inst->op != MicroInstrOpcode::LoadRegReg)
                    continue;
                const auto* copied = initial.inst->ops(*ctx.operands);
                if (!copied || !copied[1].reg.isVirtualInt() || (topShift && getNumBits(copied[2].opBits) <= topBit))
                    continue;
                // A single-use computed factor can already carry the product
                // in its own result register. A zero plus CMOV then adds work.
                auto factor = ctx.ssa->reachingDef(ops[1 - side].reg, ref);
                for (uint32_t depth = 0; depth < 8 && factor.valid() && !factor.isPhi && factor.inst && factor.inst->op == MicroInstrOpcode::LoadRegReg; ++depth)
                {
                    const auto* copy = factor.inst->ops(*ctx.operands);
                    if (!copy || !copy[1].reg.isVirtualInt())
                        break;
                    factor = ctx.ssa->reachingDef(copy[1].reg, factor.instRef);
                }
                if (factor.valid() && !factor.isPhi && factor.inst && factor.inst->op != MicroInstrOpcode::LoadRegReg &&
                    ctx.ssa->transitiveInstructionUseCount(factor.valueId, 2) == 1)
                    continue;
                const MicroReg input      = copied[1].reg;
                const auto     inputValue = ctx.ssa->reachingDef(input, initial.instRef);
                if (!inputValue.valid() || ctx.ssa->reachingDef(input, ref).valueId != inputValue.valueId ||
                    !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, mask.instRef, ctx.builder) ||
                    !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
                    continue;
                ProductBit bit{.reg = input, .index = topShift ? topBit : 0};
                if (!topShift)
                    recoverProductBit(ctx, bit, initial.instRef, ref);
                if (!ctx.nextVirtualFloatRegIndex)
                    MicroPassHelpers::computeNextVirtualRegIndices(*ctx.passContext, ctx.nextVirtualIntRegIndex, ctx.nextVirtualFloatRegIndex);
                if (ctx.nextVirtualIntRegIndex >= MicroReg::K_MAX_INDEX ||
                    !ctx.claimAll({ref, mask.instRef, initial.instRef, maskCopy.isValid() ? maskCopy : ref, bit.shiftRef.isValid() ? bit.shiftRef : ref, bit.copyRef.isValid() ? bit.copyRef : ref}))
                    continue;

                const MicroReg    temporary = MicroReg::virtualIntReg(ctx.nextVirtualIntRegIndex++);
                MicroInstrOperand clear[2]  = {};
                clear[0].reg                = temporary;
                clear[1].opBits             = MicroOpBits::B32;
                ctx.emitInsertBefore(ref, MicroInstrOpcode::ClearReg, clear);
                const bool        sign     = bit.index == 7 || bit.index == 15 || bit.index == 31 || bit.index == 63;
                const MicroOpBits testBits = sign ? microOpBitsFromBitWidth(bit.index + 1) : bit.index < 8 ? MicroOpBits::B8
                                                                                         : bit.index < 16  ? MicroOpBits::B16
                                                                                                           : MicroOpBits::B32;
                MicroInstrOperand test[3]  = {};
                test[0].reg                = bit.reg;
                if (sign)
                {
                    test[1].reg    = bit.reg;
                    test[2].opBits = testBits;
                    ctx.emitInsertBefore(ref, MicroInstrOpcode::TestRegReg, test);
                }
                else
                {
                    test[1].opBits   = testBits;
                    test[2].valueU64 = 1ull << bit.index;
                    ctx.emitInsertBefore(ref, MicroInstrOpcode::TestRegImm, test);
                }
                MicroInstrOperand select[4] = {};
                select[0].reg               = temporary;
                select[1]                   = ops[1 - side];
                select[2].cpuCond           = sign ? MicroCond::Sign : MicroCond::NotZero;
                select[3].opBits            = bits;
                ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadCondRegReg, select);
                MicroInstrOperand copy[3] = {};
                copy[0]                   = ops[0];
                copy[1].reg               = temporary;
                copy[2]                   = ops[2];
                ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, copy);
                ctx.emitErase(mask.instRef);
                if (bit.shiftRef.isValid())
                    ctx.emitErase(bit.shiftRef);
                if (maskCopy.isValid())
                    ctx.emitErase(maskCopy);
                return true;
            }
            return false;
        }

        // The unmultiplied input is a product with an implicit factor of one.
        // Rebuild at the final operation only after both input values survive.
        bool tryFactorSingleProduct(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            const MicroOp     outer = ops[3].microOp;
            const MicroOpBits bits  = ops[2].opBits;
            if (!ctx.ssa || (outer != MicroOp::Add && outer != MicroOp::Subtract) || !ops[1].reg.isVirtualInt() ||
                (bits != MicroOpBits::B32 && bits != MicroOpBits::B64))
                return false;
            for (uint32_t side = 0; side < (outer == MicroOp::Add ? 2u : 1u); ++side)
            {
                MicroReg      productReg  = ops[side].reg;
                auto          product     = ctx.ssa->reachingDef(productReg, ref);
                MicroInstrRef productCopy = MicroInstrRef::invalid();
                if (product.valid() && !product.isPhi && product.inst && product.inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const auto* copy = product.inst->ops(*ctx.operands);
                    if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < getNumBits(bits) ||
                        ctx.ssa->transitiveInstructionUseCount(product.valueId, 2) != 1)
                        continue;
                    productCopy = product.instRef;
                    productReg  = copy[1].reg;
                    product     = ctx.ssa->reachingDef(productReg, productCopy);
                }
                if (!product.valid() || product.isPhi || !product.inst || product.inst->op != MicroInstrOpcode::OpBinaryRegReg ||
                    ctx.ssa->transitiveInstructionUseCount(product.valueId, 2) != 1)
                    continue;
                const auto* multiply = product.inst->ops(*ctx.operands);
                if (!multiply || multiply[3].microOp != MicroOp::MultiplySigned || multiply[2].opBits != bits || !multiply[1].reg.isVirtualInt())
                    continue;
                const auto initial = ctx.ssa->reachingDef(productReg, product.instRef);
                if (!initial.valid() || initial.isPhi || !initial.inst || initial.inst->op != MicroInstrOpcode::LoadRegReg)
                    continue;
                const auto* copied = initial.inst->ops(*ctx.operands);
                if (!copied || !copied[1].reg.isVirtualInt() || getNumBits(copied[2].opBits) < getNumBits(bits))
                    continue;
                const std::array inputs{copied[1].reg, multiply[1].reg};
                const std::array inputRefs{initial.instRef, product.instRef};
                for (uint32_t common = 0; common < 2; ++common)
                {
                    MicroReg      other     = ops[1 - side].reg;
                    MicroInstrRef otherRef  = ref;
                    MicroInstrRef otherCopy = MicroInstrRef::invalid();
                    if (other != inputs[common])
                    {
                        const auto reaching = ctx.ssa->reachingDef(other, ref);
                        if (!reaching.valid() || reaching.isPhi || !reaching.inst || reaching.inst->op != MicroInstrOpcode::LoadRegReg)
                            continue;
                        const auto* copy = reaching.inst->ops(*ctx.operands);
                        if (!copy || getNumBits(copy[2].opBits) < getNumBits(bits))
                            continue;
                        other     = copy[1].reg;
                        otherRef  = reaching.instRef;
                        otherCopy = reaching.instRef;
                    }
                    if (other != inputs[common])
                        continue;
                    const auto     commonValue = ctx.ssa->reachingDef(other, inputRefs[common]);
                    const MicroReg factor      = inputs[1 - common];
                    const auto     factorValue = ctx.ssa->reachingDef(factor, inputRefs[1 - common]);
                    if (!commonValue.valid() || !factorValue.valid() ||
                        ctx.ssa->reachingDef(other, otherRef).valueId != commonValue.valueId ||
                        ctx.ssa->reachingDef(other, ref).valueId != commonValue.valueId ||
                        ctx.ssa->reachingDef(factor, ref).valueId != factorValue.valueId)
                        continue;
                    if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
                        !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, product.instRef, ctx.builder))
                        continue;
                    if (!ctx.nextVirtualFloatRegIndex)
                        MicroPassHelpers::computeNextVirtualRegIndices(*ctx.passContext, ctx.nextVirtualIntRegIndex, ctx.nextVirtualFloatRegIndex);
                    if (ctx.nextVirtualIntRegIndex >= MicroReg::K_MAX_INDEX ||
                        !ctx.claimAll({ref, product.instRef, initial.instRef, productCopy.isValid() ? productCopy : ref, otherCopy.isValid() ? otherCopy : ref}))
                        continue;
                    const MicroReg    temporary   = MicroReg::virtualIntReg(ctx.nextVirtualIntRegIndex++);
                    MicroInstrOperand adjusted[4] = {};
                    adjusted[0].reg               = temporary;
                    adjusted[1].reg               = factor;
                    adjusted[2].opBits            = bits;
                    adjusted[3].valueU64          = outer == MicroOp::Add ? 1 : UINT64_MAX;
                    ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadAddrRegMem, adjusted);
                    MicroInstrOperand result[4] = {};
                    result[0].reg               = temporary;
                    result[1].reg               = other;
                    result[2].opBits            = bits;
                    result[3].microOp           = MicroOp::MultiplySigned;
                    ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegReg, result);
                    MicroInstrOperand copy[3] = {};
                    copy[0].reg               = ops[0].reg;
                    copy[1].reg               = temporary;
                    copy[2].opBits            = bits;
                    ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, copy);
                    ctx.emitErase(product.instRef);
                    if (productCopy.isValid())
                        ctx.emitErase(productCopy);
                    return true;
                }
            }
            return false;
        }

        // Factor bitwise operations and low products over addition/subtraction. Keep the two non-common
        // inputs at their original read positions and move only the common
        // input, after proving that its value survives to the final operation.
        bool tryFactorCommonInputs(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            const MicroOp outer      = ops[3].microOp;
            const bool    arithmetic = outer == MicroOp::Add || outer == MicroOp::Subtract;
            if (!ctx.ssa || (!arithmetic && outer != MicroOp::Xor && outer != MicroOp::Or && outer != MicroOp::And) || !ops[1].reg.isVirtualInt())
                return false;
            const MicroOp inner = arithmetic ? MicroOp::MultiplySigned : outer == MicroOp::And ? MicroOp::Or
                                                                                               : MicroOp::And;
            if (arithmetic && !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
                return false;
            const MicroOpBits bits = ops[2].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                return false;

            std::array    regs{ops[0].reg, ops[1].reg};
            std::array    defs{ctx.ssa->reachingDef(regs[0], ref), ctx.ssa->reachingDef(regs[1], ref)};
            MicroInstrRef lhsCopy = MicroInstrRef::invalid();
            if (defs[0].valid() && !defs[0].isPhi && defs[0].inst && defs[0].inst->op == MicroInstrOpcode::LoadRegReg)
            {
                const MicroInstrOperand* copied = defs[0].inst->ops(*ctx.operands);
                if (!copied || copied[2].opBits != bits || !copied[1].reg.isVirtualInt() ||
                    ctx.ssa->transitiveInstructionUseCount(defs[0].valueId, 2) != 1)
                    return false;
                lhsCopy = defs[0].instRef;
                regs[0] = copied[1].reg;
                defs[0] = ctx.ssa->reachingDef(regs[0], lhsCopy);
            }
            if (regs[0] == regs[1])
                return false;
            std::array<MicroSsaState::ReachingDef, 2> initial;
            std::array<const MicroInstrOperand*, 2>   binaryOps;
            std::array<const MicroInstrOperand*, 2>   copyOps;
            for (uint32_t i = 0; i < 2; ++i)
            {
                if (!defs[i].valid() || defs[i].isPhi || !defs[i].inst || defs[i].inst->op != MicroInstrOpcode::OpBinaryRegReg)
                    return false;
                binaryOps[i] = defs[i].inst->ops(*ctx.operands);
                if (!binaryOps[i] || binaryOps[i][2].opBits != bits || binaryOps[i][3].microOp != inner ||
                    ctx.ssa->transitiveInstructionUseCount(defs[i].valueId, 2) != 1)
                    return false;
                initial[i] = ctx.ssa->reachingDef(regs[i], defs[i].instRef);
                if (!initial[i].valid() || initial[i].isPhi || !initial[i].inst || initial[i].inst->op != MicroInstrOpcode::LoadRegReg)
                    return false;
                copyOps[i] = initial[i].inst->ops(*ctx.operands);
                if (!copyOps[i] || copyOps[i][2].opBits != bits || !copyOps[i][1].reg.isVirtualInt() ||
                    binaryOps[i][1].reg == regs[0] || binaryOps[i][1].reg == regs[1] || binaryOps[i][1].reg == ops[0].reg)
                    return false;
                if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, defs[i].instRef, ctx.builder))
                    return false;
            }

            const MicroReg common = copyOps[0][1].reg;
            if (common != copyOps[1][1].reg || common == regs[0] || common == regs[1] || common == ops[0].reg)
                return false;
            const auto commonValue = ctx.ssa->reachingDef(common, initial[0].instRef);
            if (!commonValue.valid() || ctx.ssa->reachingDef(common, initial[1].instRef).valueId != commonValue.valueId ||
                ctx.ssa->reachingDef(common, ref).valueId != commonValue.valueId)
                return false;

            bool          seenSecond = false;
            MicroInstrRef cursor     = defs[0].instRef;
            for (uint32_t step = 0; step < K_MAX_INPLACE_WINDOW && cursor.isValid() && cursor != ref; ++step)
            {
                const MicroInstr* current = ctx.storage->ptr(cursor);
                if (!current || isBlockBoundary(*current))
                    return false;
                seenSecond |= cursor == defs[1].instRef;
                if (cursor == lhsCopy && !seenSecond)
                    return false;
                cursor = ctx.storage->findNextInstructionRef(cursor);
            }
            if (cursor != ref || !seenSecond || !ctx.claimAll({ref, defs[0].instRef, defs[1].instRef, initial[0].instRef, initial[1].instRef, lhsCopy.isValid() ? lhsCopy : ref}))
                return false;

            MicroInstrOperand first[3];
            first[0].reg    = regs[0];
            first[1].reg    = binaryOps[0][1].reg;
            first[2].opBits = bits;
            ctx.emitRewrite(defs[0].instRef, MicroInstrOpcode::LoadRegReg, first);

            MicroInstrOperand factored[4];
            factored[0].reg     = regs[0];
            factored[1].reg     = binaryOps[1][1].reg;
            factored[2].opBits  = bits;
            factored[3].microOp = outer;
            ctx.emitRewrite(defs[1].instRef, MicroInstrOpcode::OpBinaryRegReg, factored);
            factored[0].reg     = ops[0].reg;
            factored[1].reg     = common;
            factored[3].microOp = inner;
            ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegReg, factored);
            return true;
        }
    }

    // Collapse the in-place-update copy round-trip that `acc op= x` lowers to once
    // mem2reg has promoted `acc` to a (loop-carried) virtual register:
    //
    //     T = A          (LoadRegReg, T a fresh temp, A the accumulator)
    //     T = T op C     (the anchored in-place op; C may be reg/imm/mem)
    //     A = T          (LoadRegReg, write the result back to A)
    //   ->
    //     A = A op C
    //
    // T only mirrors A across the update, so operating in place on A is identical
    // and removes a two-move recurrence on the loop's critical path. Copy
    // elimination cannot do this: it forwards *uses* of a copy, but the op's
    // destination is a use+def it must skip, and A is a preserved/loop-carried
    // value it must not rewrite. This changes only how A is defined and leaves its
    // observed value unchanged. Operates on virtual registers (unique temps), so
    // there is no physical-register-reuse hazard. Uses transitive-instruction-use
    // counts (not raw use-list sizes) so dead loop-header phis don't hide the
    // single-consumer shape.
    bool tryFuseInPlaceUpdate(Context& ctx, MicroInstrRef opRef, const MicroInstr& opInst)
    {
        if (ctx.isClaimed(opRef) || !ctx.ssa)
            return false;
        if (!isInPlaceBinaryOp(opInst.op))
            return false;

        const MicroInstrOperand* ops = opInst.ops(*ctx.operands);
        if (!ops)
            return false;

        const MicroReg t = ops[0].reg;
        if (!t.isVirtualInt())
            return false;

        // The op must update t in place: t is read and written and is its only
        // def. A source operand equal to t would dangle once the init copy is
        // erased, so reject those.
        const MicroInstrUseDef opUseDef = opInst.collectUseDef(*ctx.operands, nullptr);
        if (opUseDef.defs.size() != 1 || opUseDef.defs[0] != t || !microRegSpanContains(opUseDef.uses, t))
            return false;
        if ((opInst.op == MicroInstrOpcode::OpBinaryRegReg || opInst.op == MicroInstrOpcode::OpBinaryRegMem) && ops[1].reg == t)
            return false;

        // The value t holds entering the op must come from `t = A`, consumed only
        // by this op.
        const auto reachT = ctx.ssa->reachingDef(t, opRef);
        if (!reachT.valid() || reachT.isPhi)
            return false;
        const MicroInstrRef initRef  = reachT.instRef;
        const MicroInstr*   initInst = ctx.storage->ptr(initRef);
        if (!initInst || initInst->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const MicroInstrOperand* initOps = initInst->ops(*ctx.operands);
        if (!initOps || initOps[0].reg != t)
            return false;
        const MicroReg a = initOps[1].reg;
        if (!a.isVirtualInt() || a == t)
            return false;
        if (singleDirectInstructionUse(*ctx.ssa, reachT.valueId) != opRef)
            return false;

        // The op's result must be consumed only by the writeback `A = t`.
        uint32_t resultValueId = 0;
        if (!ctx.ssa->defValue(t, opRef, resultValueId))
            return false;
        const MicroInstrRef writebackRef = singleDirectInstructionUse(*ctx.ssa, resultValueId);
        if (!writebackRef.isValid())
            return false;
        const MicroInstr* wbInst = ctx.storage->ptr(writebackRef);
        if (!wbInst || wbInst->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const MicroInstrOperand* wbOps = wbInst->ops(*ctx.operands);
        if (!wbOps || wbOps[1].reg != t || wbOps[0].reg != a)
            return false;

        // A must hold the same value at the init, the op (which will now read it),
        // and the writeback: it must not be redefined across the region.
        const auto reachAInit = ctx.ssa->reachingDef(a, initRef);
        if (!reachAInit.valid() ||
            ctx.ssa->reachingDef(a, opRef).valueId != reachAInit.valueId ||
            ctx.ssa->reachingDef(a, writebackRef).valueId != reachAInit.valueId)
            return false;

        // Confine init/op/writeback to one basic block and confirm A is not read
        // between the op and the writeback — the rewrite defines A at the op's
        // position, earlier than the original writeback, so an intervening reader
        // of A would otherwise observe the new value instead of the old one.
        const auto             endIt = ctx.storage->view().end();
        MicroStorage::Iterator it{ctx.storage, initRef};

        bool seenOp    = false;
        bool reachedWb = false;
        for (uint32_t step = 0; step < K_MAX_INPLACE_WINDOW && it != endIt; ++step, ++it)
        {
            const MicroInstrRef cur = it.current;
            if (cur == writebackRef)
            {
                reachedWb = true;
                break;
            }
            const MicroInstr& w = *it;
            if (cur != initRef && cur != opRef && isBlockBoundary(w))
                return false;
            if (seenOp && cur != opRef)
            {
                const MicroInstrUseDef ud = w.collectUseDef(*ctx.operands, nullptr);
                if (microRegSpanContains(ud.uses, a))
                    return false;
            }
            if (cur == opRef)
                seenOp = true;
        }
        if (!reachedWb || !seenOp)
            return false;

        if (!ctx.claimAll({initRef, opRef, writebackRef}))
            return false;

        MicroInstrOperand newOps[Action::K_MAX_OPS] = {};
        const uint8_t     numOps                    = opInst.numOperands;
        if (numOps > Action::K_MAX_OPS)
            return false;
        for (uint8_t i = 0; i < numOps; ++i)
            newOps[i] = ops[i];
        newOps[0].reg = a;

        ctx.emitRewrite(opRef, opInst.op, std::span<const MicroInstrOperand>(newOps, numOps));
        ctx.emitErase(initRef);
        ctx.emitErase(writebackRef);
        return true;
    }

    bool tryBypassShiftCountMask(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        return tryBypassShiftCountMaskImpl(ctx, ref, inst);
    }

    bool tryOpBinaryRegReg(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isVirtualInt())
            return false;
        if (tryDoubleInput(ctx, ref, ops))
            return true;
        if (ops[0].reg != ops[1].reg)
            return tryFoldNegatedRhs(ctx, ref, ops) || tryFoldNegatedLhs(ctx, ref, ops) || tryFoldVariableRotate(ctx, ref, ops) || tryFoldRotate(ctx, ref, ops) || tryFactorCommonShifts(ctx, ref, ops) || tryFactorScaledInputs(ctx, ref, ops) || tryCombineBitMasks(ctx, ref, ops) || tryCancelBitwiseComplements(ctx, ref, ops) || tryMoveXorComplement(ctx, ref, ops) || tryFoldBitwiseSelect(ctx, ref, ops) || tryFoldBitwiseDifference(ctx, ref, ops) || tryFoldAddressDifference(ctx, ref, ops) || tryFoldRepeatedBitwiseComplement(ctx, ref, ops) || tryFoldRepeatedInput(ctx, ref, ops) || tryReduceAddedScaledDifference(ctx, ref, ops) || trySelectLowBitProduct(ctx, ref, ops) || tryFactorSingleProduct(ctx, ref, ops) || tryFactorCommonInputs(ctx, ref, ops);

        const MicroReg    dst    = ops[0].reg;
        const MicroOpBits opBits = ops[2].opBits;
        const MicroOp     op     = ops[3].microOp;

        switch (op)
        {
            case MicroOp::And:
            case MicroOp::Or:
                // v op v == v. Rewriting to a self-copy buys nothing pre-RA,
                // so only drop when the result is unused afterward.
                if (ctx.ssa && !ctx.ssa->isRegUsedAfter(dst, ref))
                {
                    if (!ctx.claimAll({ref}))
                        return false;
                    ctx.emitErase(ref);
                    return true;
                }
                return false;

            case MicroOp::Subtract:
            case MicroOp::Xor:
            {
                if (!ctx.claimAll({ref}))
                    return false;
                MicroInstrOperand clearOps[2];
                clearOps[0].reg    = dst;
                clearOps[1].opBits = opBits;
                ctx.emitRewrite(ref, MicroInstrOpcode::ClearReg, clearOps);
                return true;
            }

            default:
                return false;
        }
    }

    // A shift of a value that is still needed afterwards:
    //
    //     copy d, s; d <<= c      ->      d = s << c
    //
    // The machine has a shift that names its source, its count and its result
    // separately, and takes the count from any register. Written the other
    // way it costs the copy above, and a move of the count into the one
    // register the legacy form reads it from. It writes no flags, so it only
    // stands where nothing reads them after the shift.
    bool tryThreeOperandShift(Context& ctx, const MicroInstrRef ref, const MicroInstr& inst)
    {
        if (!ctx.ssa || ctx.isClaimed(ref) || ctx.isRelocated(ref))
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;

        // ops: [0] dst (read and written), [1] count, [2] opBits, [3] microOp
        const MicroOp op = ops[3].microOp;
        if (op != MicroOp::ShiftLeft && op != MicroOp::ShiftRight && op != MicroOp::ShiftArithmeticRight && op != MicroOp::ShiftArithmeticLeft)
            return false;
        if (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64)
            return false;

        const MicroReg dst   = ops[0].reg;
        const MicroReg count = ops[1].reg;
        if (!dst.isVirtualInt() || !count.isVirtualInt() || dst == count)
            return false;

        // The copy that put the value where the shift could destroy it.
        const auto reaching = ctx.ssa->reachingDef(dst, ref);
        if (!reaching.valid() || reaching.isPhi || !reaching.inst)
            return false;
        if (reaching.inst->op != MicroInstrOpcode::LoadRegReg)
            return false;

        const MicroInstrOperand* copyOps = reaching.inst->ops(*ctx.operands);
        if (!copyOps || copyOps[0].reg != dst || copyOps[2].opBits != ops[2].opBits)
            return false;

        const MicroReg src = copyOps[1].reg;
        if (!src.isVirtualInt() || src == count || src == dst)
            return false;
        if (ctx.ssa->transitiveInstructionUseCount(reaching.valueId, 2) != 1)
            return false;

        // The legacy shift writes the flags and this form does not.
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
            return false;

        if (!ctx.claimAll({ref, reaching.instRef}))
            return false;

        MicroInstrOperand newOps[5] = {};
        newOps[0].reg    = dst;
        newOps[1].reg    = src;
        newOps[2].reg    = count;
        newOps[3].opBits = ops[2].opBits;
        newOps[4].microOp = op;
        ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegRegReg, std::span<const MicroInstrOperand>(newOps, 5), true);
        ctx.emitErase(reaching.instRef);
        return true;
    }
    namespace
    {
        constexpr uint32_t K_MAX_BSWAP_DEPTH = 10;
        constexpr int8_t   K_BIT_ZERO        = -1;

        // Where each bit of a value comes from: a bit of one leaf value, or
        // zero. LLVM's recognizeBSwapOrBitReverseIdiom tracks the same thing.
        struct BitSources
        {
            uint32_t leafValue = 0;
            MicroReg leafReg   = MicroReg::invalid();
            bool     hasLeaf   = false;
            int8_t   bits[64]  = {};
        };

        bool mergeLeaf(BitSources& into, const BitSources& from)
        {
            if (!from.hasLeaf)
                return true;
            if (into.hasLeaf && into.leafValue != from.leafValue)
                return false;
            into.hasLeaf   = true;
            into.leafValue = from.leafValue;
            into.leafReg   = from.leafReg;
            return true;
        }

        bool traceBitSources(const Context& ctx, const MicroReg reg, const MicroInstrRef atRef, const uint32_t depth, BitSources& out)
        {
            const MicroSsaState::ReachingDef def = ctx.ssa->reachingDef(reg, atRef);
            if (!def.valid())
                return false;

            const auto leaf = [&] {
                out.hasLeaf   = true;
                out.leafValue = def.valueId;
                out.leafReg   = reg;
                for (int8_t i = 0; i < 64; ++i)
                    out.bits[i] = i;
                return true;
            };
            if (def.isPhi || !def.inst || depth >= K_MAX_BSWAP_DEPTH)
                return leaf();

            const MicroInstrOperand* ops = def.inst->ops(*ctx.operands);
            if (!ops || ops[0].reg != reg)
                return leaf();

            switch (def.inst->op)
            {
                case MicroInstrOpcode::LoadRegReg:
                {
                    if (!ops[1].reg.isVirtualInt() || (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64))
                        return leaf();
                    if (!traceBitSources(ctx, ops[1].reg, def.instRef, depth + 1, out))
                        return false;
                    if (ops[2].opBits == MicroOpBits::B32)
                    {
                        for (uint32_t i = 32; i < 64; ++i)
                            out.bits[i] = K_BIT_ZERO;
                    }
                    return true;
                }

                case MicroInstrOpcode::OpBinaryRegImm:
                {
                    const MicroOpBits bits = ops[1].opBits;
                    const MicroOp     op   = ops[2].microOp;
                    if ((bits != MicroOpBits::B32 && bits != MicroOpBits::B64) || ops[3].hasWideImmediateValue() ||
                        (op != MicroOp::ShiftRight && op != MicroOp::ShiftLeft && op != MicroOp::And))
                        return leaf();
                    const uint32_t width = getNumBits(bits);
                    const uint64_t imm   = ops[3].valueU64;
                    if (op != MicroOp::And && imm >= width)
                        return leaf();

                    BitSources input;
                    if (!traceBitSources(ctx, reg, def.instRef, depth + 1, input))
                        return false;
                    out = input;
                    for (uint32_t i = 0; i < 64; ++i)
                    {
                        int8_t source = K_BIT_ZERO;
                        if (i < width)
                        {
                            if (op == MicroOp::ShiftRight)
                                source = i + imm < width ? input.bits[i + imm] : K_BIT_ZERO;
                            else if (op == MicroOp::ShiftLeft)
                                source = i >= imm ? input.bits[i - imm] : K_BIT_ZERO;
                            else
                                source = (imm >> i) & 1 ? input.bits[i] : K_BIT_ZERO;
                        }
                        out.bits[i] = source;
                    }
                    return true;
                }

                case MicroInstrOpcode::OpBinaryRegReg:
                {
                    const MicroOpBits bits = ops[2].opBits;
                    if (ops[3].microOp != MicroOp::Or || (bits != MicroOpBits::B32 && bits != MicroOpBits::B64) || !ops[1].reg.isVirtualInt())
                        return leaf();
                    BitSources left;
                    BitSources right;
                    if (!traceBitSources(ctx, reg, def.instRef, depth + 1, left) ||
                        !traceBitSources(ctx, ops[1].reg, def.instRef, depth + 1, right))
                        return false;
                    const uint32_t width = getNumBits(bits);
                    out                  = BitSources{};
                    for (uint32_t i = 0; i < 64; ++i)
                    {
                        if (i >= width)
                        {
                            out.bits[i] = K_BIT_ZERO;
                            continue;
                        }
                        if (left.bits[i] != K_BIT_ZERO && right.bits[i] != K_BIT_ZERO)
                            return false;
                        out.bits[i] = left.bits[i] != K_BIT_ZERO ? left.bits[i] : right.bits[i];
                    }
                    // Only the sides that contribute a bit name the leaf.
                    bool leftUsed  = false;
                    bool rightUsed = false;
                    for (uint32_t i = 0; i < width; ++i)
                    {
                        leftUsed |= left.bits[i] != K_BIT_ZERO;
                        rightUsed |= right.bits[i] != K_BIT_ZERO;
                    }
                    return (!leftUsed || mergeLeaf(out, left)) && (!rightUsed || mergeLeaf(out, right));
                }

                default:
                    return leaf();
            }
        }
    }

    // The bytes of a value reassembled in reverse order by shifts, masks and
    // ors are its byte swap, as LLVM's bswap idiom recognizer finds:
    //
    //     (x >> 24) | ((x >> 8) & 0xFF00) | ((x << 8) & 0xFF0000) | (x << 24)
    //   ->
    //     t = x; bswap t
    //
    // Every bit of the result must come from the one source the byte swap
    // puts there, and that source must still hold its value at the root.
    bool tryRecognizeByteSwap(Context& ctx, const MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;
        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || ops[3].microOp != MicroOp::Or || (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64))
            return false;
        const MicroReg dst = ops[0].reg;
        if (!dst.isVirtualInt() || !ops[1].reg.isVirtualInt())
            return false;

        BitSources left;
        BitSources right;
        if (!traceBitSources(ctx, dst, ref, 1, left) || !traceBitSources(ctx, ops[1].reg, ref, 1, right))
            return false;
        if (!left.hasLeaf || !right.hasLeaf || left.leafValue != right.leafValue)
            return false;

        const uint32_t width = getNumBits(ops[2].opBits);
        const uint32_t bytes = width / 8;
        BitSources     sources = left;
        for (uint32_t i = 0; i < width; ++i)
        {
            if (left.bits[i] != K_BIT_ZERO && right.bits[i] != K_BIT_ZERO)
                return false;
            sources.bits[i] = left.bits[i] != K_BIT_ZERO ? left.bits[i] : right.bits[i];
            const uint32_t expected = (bytes - 1 - i / 8) * 8 + i % 8;
            if (sources.bits[i] != static_cast<int8_t>(expected))
                return false;
        }

        const MicroSsaState::ReachingDef leafAtRoot = ctx.ssa->reachingDef(sources.leafReg, ref);
        if (!leafAtRoot.valid() || leafAtRoot.valueId != sources.leafValue || sources.leafReg == dst)
            return false;
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
            return false;
        if (!ctx.claimAll({ref}))
            return false;

        MicroInstrOperand copy[3];
        copy[0].reg    = dst;
        copy[1].reg    = sources.leafReg;
        copy[2].opBits = ops[2].opBits;
        ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadRegReg, copy);

        MicroInstrOperand swap[3];
        swap[0].reg     = dst;
        swap[1].opBits  = ops[2].opBits;
        swap[2].microOp = MicroOp::ByteSwap;
        ctx.emitRewrite(ref, MicroInstrOpcode::OpUnaryReg, swap);
        return true;
    }
}

SWC_END_NAMESPACE();
