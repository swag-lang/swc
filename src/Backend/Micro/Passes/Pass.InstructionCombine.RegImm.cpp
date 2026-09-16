#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// OpBinaryRegImm combiner: identity / absorbing element / reassociation.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        // (x << shift) & mask = (x & (mask >> shift)) << shift.
        // Only move masks that become a byte/word/dword zero-extension. The
        // original shift reads its input in place; its single-use result and
        // optional copy then carry that masked input to the final shift.
        bool tryMaskShiftedValue(Context& ctx, MicroInstrRef ref, MicroReg dst, MicroOpBits bits, uint64_t mask)
        {
            if (!ctx.ssa || (bits != MicroOpBits::B32 && bits != MicroOpBits::B64))
                return false;
            MicroReg      shifted = dst;
            auto          def     = ctx.ssa->reachingDef(shifted, ref);
            MicroInstrRef copyRef;
            if (def.valid() && !def.isPhi && def.inst && def.inst->op == MicroInstrOpcode::LoadRegReg)
            {
                const auto* copy = def.inst->ops(*ctx.operands);
                if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < getNumBits(bits) ||
                    ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                    return false;
                copyRef = def.instRef;
                shifted = copy[1].reg;
                def     = ctx.ssa->reachingDef(shifted, copyRef);
            }
            if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::OpBinaryRegImm ||
                ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                return false;
            const auto* shiftOps = def.inst->ops(*ctx.operands);
            if (!shiftOps || shiftOps[1].opBits != bits || shiftOps[3].hasWideImmediateValue() ||
                (shiftOps[2].microOp != MicroOp::ShiftLeft && shiftOps[2].microOp != MicroOp::ShiftArithmeticLeft))
                return false;
            const uint64_t shift = shiftOps[3].valueU64;
            if (!shift || shift >= getNumBits(bits))
                return false;
            const uint64_t    inputMask = (mask & getBitsMask(bits)) >> shift;
            const MicroOpBits inputBits = inputMask == 0xFF ? MicroOpBits::B8 : inputMask == 0xFFFF                               ? MicroOpBits::B16
                                                                            : inputMask == 0xFFFFFFFF && bits == MicroOpBits::B64 ? MicroOpBits::B32
                                                                                                                                  : MicroOpBits::Zero;
            if (inputBits == MicroOpBits::Zero ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, def.instRef, ctx.builder) ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
                !ctx.claimAll({ref, def.instRef, copyRef.isValid() ? copyRef : ref}))
                return false;
            MicroInstrOperand extend[4];
            extend[0].reg    = shifted;
            extend[1].reg    = shifted;
            extend[2].opBits = bits;
            extend[3].opBits = inputBits;
            ctx.emitRewrite(def.instRef, MicroInstrOpcode::LoadZeroExtRegReg, extend);
            MicroInstrOperand shiftResult[4];
            shiftResult[0].reg      = dst;
            shiftResult[1].opBits   = getNumBits(inputBits) + shift <= 32 ? MicroOpBits::B32 : bits;
            shiftResult[2].microOp  = MicroOp::ShiftLeft;
            shiftResult[3].valueU64 = shift;
            ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegImm, shiftResult);
            return true;
        }

        bool feedsReassociableImmediate(const Context& ctx, MicroInstrRef ref, MicroReg dst, MicroOpBits opBits, MicroOp op, uint64_t imm)
        {
            if (!ctx.ssa)
                return false;

            uint32_t valueId = MicroSsaState::K_INVALID_VALUE;
            if (!ctx.ssa->defValue(dst, ref, valueId))
                return false;

            const MicroSsaState::ValueInfo* value = ctx.ssa->valueInfo(valueId);
            if (!value || value->uses.size() != 1 || value->uses.front().kind != MicroSsaState::UseSite::Kind::Instruction)
                return false;

            const MicroInstrRef useRef  = value->uses.front().instRef;
            const MicroInstr*   useInst = ctx.storage->ptr(useRef);
            if (!useInst || useInst->op != MicroInstrOpcode::OpBinaryRegImm)
                return false;

            const MicroInstrOperand* useOps = useInst->ops(*ctx.operands);
            if (!useOps || useOps[0].reg != dst || !isSameOpBitsInt(opBits, useOps[1].opBits))
                return false;

            MicroOp  combinedOp  = MicroOp::Add;
            uint64_t combinedImm = 0;
            return tryReassociate(op, imm, useOps[2].microOp, useOps[3].valueU64, opBits, combinedOp, combinedImm) &&
                   MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, useRef, ctx.builder);
        }

        bool emitClearReg(Context& ctx, MicroInstrRef ref, MicroReg dst, MicroOpBits opBits)
        {
            if (!ctx.claimAll({ref}))
                return false;
            MicroInstrOperand clearOps[2];
            clearOps[0].reg    = dst;
            clearOps[1].opBits = opBits;
            ctx.emitRewrite(ref, MicroInstrOpcode::ClearReg, clearOps);
            return true;
        }

        bool emitLoadRegImm(Context& ctx, MicroInstrRef ref, MicroReg dst, MicroOpBits opBits, uint64_t value)
        {
            if (!ctx.claimAll({ref}))
                return false;
            MicroInstrOperand loadOps[3];
            loadOps[0].reg      = dst;
            loadOps[1].opBits   = opBits;
            loadOps[2].valueU64 = value;
            ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegImm, loadOps);
            return true;
        }

        // dst *= {2,3,5,9}  ->  lea dst, [src + src*{1,2,4,8}]
        //
        // A three-cycle multiply becomes a one-cycle address computation, and
        // when dst was just copied from a register that still holds the same
        // value, the address form reads that source directly and the copy dies
        // with its last use. This is the shape every sample access of a
        // variable-stride filter produces: copy the stride, multiply by the tap
        // distance, index by the product.
        bool tryMultiplyToAddress(Context& ctx, MicroInstrRef ref, MicroReg dst, MicroOpBits opBits, MicroOp op, uint64_t imm)
        {
            if (op != MicroOp::MultiplySigned && op != MicroOp::MultiplyUnsigned)
                return false;
            // The address form computes a 64-bit result; a narrower multiply
            // keeps its truncating semantics only through its own width.
            if (opBits != MicroOpBits::B64)
                return false;

            // Only the scales the addressing mode encodes, and their negations.
            // Powers of two above one are strength-reduced to shifts before
            // this rule sees them.
            const auto signedImm = static_cast<int64_t>(imm);
            const bool negated   = signedImm < 0;
            // Unsigned negation also represents the magnitude of INT64_MIN.
            const auto magnitude = negated ? 0ull - imm : imm;
            if (magnitude != 2 && magnitude != 3 && magnitude != 5 && magnitude != 9)
                return false;

            // Keep this operation intact when its only consumer can fuse it with
            // another immediate operation later in the same forward scan.
            if (feedsReassociableImmediate(ctx, ref, dst, opBits, op, imm))
                return false;

            // The multiply writes flags the address computation does not (the
            // negation below writes its own, which the same check covers).
            if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
                return false;

            // When dst was just copied from a source register, the address form
            // can read that source directly. The positive rewrite needs the
            // source value still live here; the negated one rewrites the copy
            // itself, so it needs the copy consumed by this multiply alone.
            MicroInstrRef copyRef;
            MicroReg      copySource;
            bool          copySingleUse = false;
            if (ctx.ssa)
            {
                const auto copyReaching = ctx.ssa->reachingDef(dst, ref);
                if (copyReaching.valid() && !copyReaching.isPhi && copyReaching.inst &&
                    copyReaching.inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const MicroInstrOperand* copyOps = copyReaching.inst->ops(*ctx.operands);
                    if (copyOps && copyOps[0].reg == dst && copyOps[1].reg.isVirtualInt() && copyOps[2].opBits == MicroOpBits::B64)
                    {
                        const auto srcAtCopy    = ctx.ssa->reachingDef(copyOps[1].reg, copyReaching.instRef);
                        const auto srcAtRewrite = ctx.ssa->reachingDef(copyOps[1].reg, ref);
                        if (srcAtCopy.valid() && srcAtRewrite.valid() && srcAtCopy.valueId == srcAtRewrite.valueId)
                        {
                            copyRef    = copyReaching.instRef;
                            copySource = copyOps[1].reg;

                            const auto* copyValue = ctx.ssa->valueInfo(copyReaching.valueId);
                            copySingleUse         = copyValue && copyValue->uses.size() == 1;
                        }
                    }
                }
            }

            MicroInstrOperand leaOps[8] = {};
            leaOps[0].reg               = dst;
            leaOps[3].opBits            = MicroOpBits::B64;
            leaOps[4].opBits            = MicroOpBits::B64;
            leaOps[5].valueU64          = magnitude - 1;
            leaOps[6].valueU64          = 0;

            if (!negated)
            {
                // Reading the copy's source claims the copy too: another rule
                // of this sweep may otherwise retarget the instruction that
                // feeds it and erase it, and the source would be gone.
                if (copyRef.isValid() ? !ctx.claimAll({ref, copyRef}) : !ctx.claimAll({ref}))
                    return false;

                const MicroReg source = copyRef.isValid() ? copySource : dst;
                leaOps[1].reg         = source;
                leaOps[2].reg         = source;
                ctx.emitRewrite(ref, MicroInstrOpcode::LoadAddrAmcRegMem, std::span{leaOps, 8}, true);
                return true;
            }

            // dst = src; dst *= -K  ->  lea dst, [src + src*(K-1)]; neg dst.
            // Both slots exist already: the copy becomes the address
            // computation and the multiply becomes the negation. The copy must
            // feed this multiply alone, or its other readers would see the
            // product instead of the copied value.
            if (!copyRef.isValid() || !copySingleUse)
                return false;
            if (!ctx.claimAll({copyRef, ref}))
                return false;

            leaOps[1].reg = copySource;
            leaOps[2].reg = copySource;
            ctx.emitRewrite(copyRef, MicroInstrOpcode::LoadAddrAmcRegMem, std::span{leaOps, 8}, true);

            MicroInstrOperand negOps[3] = {};
            negOps[0].reg               = dst;
            negOps[1].opBits            = MicroOpBits::B64;
            negOps[2].microOp           = MicroOp::Negate;
            ctx.emitRewrite(ref, MicroInstrOpcode::OpUnaryReg, std::span{negOps, 3});
            return true;
        }

        bool tryReassociateWithPrevious(Context& ctx, MicroInstrRef ref, MicroReg dst, MicroOpBits opBits, MicroOp op, uint64_t imm)
        {
            MicroReg      source   = dst;
            auto          reaching = ctx.ssa->reachingDef(source, ref);
            MicroInstrRef copyRef;
            if (reaching.valid() && !reaching.isPhi && reaching.inst && reaching.inst->op == MicroInstrOpcode::LoadRegReg)
            {
                const auto* copy = reaching.inst->ops(*ctx.operands);
                if (!copy || copy[2].opBits != opBits || !copy[1].reg.isVirtualInt() ||
                    ctx.ssa->transitiveInstructionUseCount(reaching.valueId, 2) != 1)
                    return false;
                copyRef  = reaching.instRef;
                source   = copy[1].reg;
                reaching = ctx.ssa->reachingDef(source, copyRef);
            }
            if (!reaching.valid() || reaching.isPhi || !reaching.inst)
                return false;
            if (reaching.inst->op != MicroInstrOpcode::OpBinaryRegImm)
                return false;

            const MicroInstrOperand* prevOps = reaching.inst->ops(*ctx.operands);
            if (!prevOps || prevOps[0].reg != source || !isSameOpBitsInt(prevOps[1].opBits, opBits))
                return false;

            const auto* valueInfo = ctx.ssa->valueInfo(reaching.valueId);
            if (!valueInfo || valueInfo->uses.size() != 1)
                return false;

            auto     combinedOp  = MicroOp::Add;
            uint64_t combinedImm = 0;
            if (!tryReassociate(prevOps[2].microOp, prevOps[3].valueU64, op, imm, opBits, combinedOp, combinedImm))
                return false;
            // The result's single use says nothing about a setcc or overflow
            // guard reading the first operation's flags between the two.
            if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, reaching.instRef, ctx.builder))
                return false;
            if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
                return false;

            if (!ctx.claimAll({ref, reaching.instRef, copyRef.isValid() ? copyRef : ref}))
                return false;

            MicroInstrOperand rewritten[4];
            rewritten[0].reg      = source;
            rewritten[1].opBits   = opBits;
            rewritten[2].microOp  = combinedOp;
            rewritten[3].valueU64 = combinedImm;
            ctx.emitRewrite(reaching.instRef, MicroInstrOpcode::OpBinaryRegImm, rewritten);
            ctx.emitErase(ref);
            return true;
        }
    }

    // Two's-complement negation written as ~x + 1. The intermediate
    // complement must have no other readers, and neither flag result may
    // escape: NEG writes flags that NOT preserves, and differs from ADD.
    bool tryFoldComplementPlusOne(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;
        const auto* ops     = inst.ops(*ctx.operands);
        const bool  address = inst.op == MicroInstrOpcode::LoadAddrRegMem;
        if (!ops || ops[3].hasWideImmediateValue() || ops[3].valueU64 != 1 ||
            (!address && ops[2].microOp != MicroOp::Add))
            return false;
        const MicroReg    source = ops[address ? 1 : 0].reg;
        const MicroOpBits bits   = ops[address ? 2 : 1].opBits;
        if (!source.isVirtualInt() || !ops[0].reg.isVirtualInt())
            return false;
        if (!ctx.ssa || (bits != MicroOpBits::B32 && bits != MicroOpBits::B64))
            return false;
        auto          def = ctx.ssa->reachingDef(source, ref);
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
        if (!unary || unary[1].opBits != bits || unary[2].microOp != MicroOp::BitwiseNot ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, def.instRef, ctx.builder) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({ref, def.instRef, copyRef.isValid() ? copyRef : ref}))
            return false;
        MicroInstrOperand negate[3];
        negate[0].reg     = unary[0].reg;
        negate[1].opBits  = bits;
        negate[2].microOp = MicroOp::Negate;
        ctx.emitRewrite(def.instRef, MicroInstrOpcode::OpUnaryReg, negate);
        if (address)
        {
            MicroInstrOperand copy[3];
            copy[0].reg    = ops[0].reg;
            copy[1].reg    = source;
            copy[2].opBits = bits;
            ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, copy);
        }
        else
            ctx.emitErase(ref);
        return true;
    }

    bool tryOpBinaryRegImm(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isVirtualInt())
            return false;

        const MicroReg    dst    = ops[0].reg;
        const MicroOpBits opBits = ops[1].opBits;
        const MicroOp     op     = ops[2].microOp;
        const uint64_t    imm    = ops[3].valueU64;

        // Dropping or rewriting the operation also drops its flag write, and a
        // dead RESULT does not imply dead FLAGS: constant folding can rewrite
        // every consumer of an unrolled accumulator to a constant while an
        // overflow guard still reads the flags of the now value-dead add.
        const bool flagsDeadAfter = MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder);

        // An identity operation leaves a byte, word or full register as it
        // was; at 32 bits it also clears the upper half, which only matters
        // when that half may be set.
        const auto identityKeepsValue = [&] {
            if (!ctx.ssa)
                return false;
            if (!ctx.ssa->isRegUsedAfter(dst, ref) || opBits != MicroOpBits::B32)
                return true;
            const MicroSsaState::ReachingDef input = ctx.ssa->reachingDef(dst, ref);
            return input.valid() && isValueZeroExtended32(ctx, input.valueId);
        };
        if (isRightIdentity(op, opBits, imm) && flagsDeadAfter && identityKeepsValue())
        {
            if (!ctx.claimAll({ref}))
                return false;
            ctx.emitErase(ref);
            return true;
        }

        uint64_t absorbed = 0;
        if (isRightAbsorbing(op, opBits, imm, absorbed) && flagsDeadAfter)
        {
            if (absorbed == 0)
                return emitClearReg(ctx, ref, dst, opBits);
            return emitLoadRegImm(ctx, ref, dst, opBits, absorbed);
        }

        if (op == MicroOp::And && tryMaskShiftedValue(ctx, ref, dst, opBits, imm))
            return true;

        // and dst, 0xFF / 0xFFFF / 0xFFFFFFFF == a zero-extending self move. The
        // move needs no immediate at all (0xFFFFFFFF cannot even encode as a
        // sign-extended imm32, so the AND form costs a 10-byte materialization),
        // but it also drops the AND's flag write, so flags must be dead after.
        if (op == MicroOp::And && (opBits == MicroOpBits::B64 || opBits == MicroOpBits::B32))
        {
            MicroOpBits maskBits = MicroOpBits::Zero;
            if (imm == 0xFF)
                maskBits = MicroOpBits::B8;
            else if (imm == 0xFFFF)
                maskBits = MicroOpBits::B16;
            else if (imm == 0xFFFFFFFF && opBits == MicroOpBits::B64)
                maskBits = MicroOpBits::B32;

            if (maskBits != MicroOpBits::Zero &&
                MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) &&
                ctx.claimAll({ref}))
            {
                MicroInstrOperand extendOps[4];
                extendOps[0].reg    = dst;
                extendOps[1].reg    = dst;
                extendOps[2].opBits = opBits;
                extendOps[3].opBits = maskBits;
                ctx.emitRewrite(ref, MicroInstrOpcode::LoadZeroExtRegReg, extendOps);
                return true;
            }
        }

        if (flagsDeadAfter && op == MicroOp::Add && imm == 1 && tryFoldComplementPlusOne(ctx, ref, inst))
            return true;

        // The low product by all-one bits is -x. Keep checked multiplies:
        // NEG has different overflow/carry behavior from signed/unsigned MUL.
        if (flagsDeadAfter && (op == MicroOp::MultiplySigned || op == MicroOp::MultiplyUnsigned) &&
            (opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64) &&
            (imm & getBitsMask(opBits)) == getBitsMask(opBits) && ctx.claimAll({ref}))
        {
            MicroInstrOperand negate[3];
            negate[0].reg     = dst;
            negate[1].opBits  = opBits;
            negate[2].microOp = MicroOp::Negate;
            ctx.emitRewrite(ref, MicroInstrOpcode::OpUnaryReg, negate);
            return true;
        }

        // Fold an operation chain before strength-reducing either member. Besides
        // preserving the more general reassociation opportunity, this keeps
        // `x *= 3; x *= 5` as one multiply by 15 instead of two address computations.
        if (ctx.ssa && tryReassociateWithPrevious(ctx, ref, dst, opBits, op, imm))
            return true;

        return tryMultiplyToAddress(ctx, ref, dst, opBits, op, imm);
    }

    // (x & C) << s  ==  x << s   when the low (width - s) bits of C are all set.
    //
    // Those low bits are exactly the ones the left shift keeps; every bit the
    // mask clears is shifted out anyway, so the AND is dead. Frontends emit this
    // shape whenever source masks a value before a left shift (e.g. wrap-safe
    // arithmetic). The AND (and its materialized mask constant, removed later by
    // DCE) is pure overhead the shift makes redundant. Anchored on the shift.
    bool tryFoldRedundantMaskBeforeShift(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;

        const MicroOp op = ops[2].microOp;
        if (op != MicroOp::ShiftLeft && op != MicroOp::ShiftArithmeticLeft)
            return false;

        const MicroReg dst = ops[0].reg;
        if (!dst.isVirtualInt())
            return false;

        const MicroOpBits opBits = ops[1].opBits;
        const unsigned    width  = static_cast<uint8_t>(opBits);
        if (width == 0 || width > 64)
            return false;

        const uint64_t shift = ops[3].valueU64;
        if (shift == 0 || shift >= width)
            return false;

        const unsigned keptBits = width - static_cast<unsigned>(shift);
        const uint64_t keptMask = keptBits >= 64 ? ~0ull : ((1ull << keptBits) - 1);

        // Walk back from the shifted register to the AND that produced it. The
        // value typically reaches the shift through one or more value-preserving
        // copies (the builder materializes each step into a fresh temp), so the
        // AND is rarely the direct reaching def. Every hop must be single-use so
        // that dropping the mask cannot perturb another consumer.
        // Exactly one real instruction consumer (dead loop-header phis ignored, as
        // in tryFuseInPlaceUpdate) so dropping the mask cannot perturb anyone else.
        MicroReg      cur    = dst;
        MicroInstrRef curRef = ref;
        for (int depth = 0; depth < 8; ++depth)
        {
            const auto reach = ctx.ssa->reachingDef(cur, curRef);
            if (!reach.valid() || reach.isPhi || !reach.inst)
                return false;
            if (ctx.ssa->transitiveInstructionUseCount(reach.valueId, 2) != 1)
                return false;

            const MicroInstr*        defInst = reach.inst;
            const MicroInstrOperand* defOps  = defInst->ops(*ctx.operands);
            if (!defOps)
                return false;

            // Skip a value-preserving copy `cur = src`.
            if (defInst->op == MicroInstrOpcode::LoadRegReg && defOps[0].reg == cur)
            {
                const MicroReg src = defOps[1].reg;
                if (!src.isVirtualInt() || !isSameOpBitsInt(defOps[2].opBits, opBits))
                    return false;
                cur    = src;
                curRef = reach.instRef;
                continue;
            }

            // Otherwise this must be the in-place `cur &= C` we want to drop.
            if (defOps[0].reg != cur)
                return false;

            uint64_t mask = 0;
            if (defInst->op == MicroInstrOpcode::OpBinaryRegImm)
            {
                if (defOps[2].microOp != MicroOp::And || !isSameOpBitsInt(defOps[1].opBits, opBits))
                    return false;
                mask = defOps[3].valueU64;
            }
            else if (defInst->op == MicroInstrOpcode::OpBinaryRegReg)
            {
                if (defOps[3].microOp != MicroOp::And || !isSameOpBitsInt(defOps[2].opBits, opBits))
                    return false;
                const MicroReg maskReg = defOps[1].reg;
                if (!maskReg.isVirtualInt())
                    return false;
                const auto reachMask = ctx.ssa->reachingDef(maskReg, reach.instRef);
                if (!reachMask.valid() || reachMask.isPhi || !reachMask.inst || reachMask.inst->op != MicroInstrOpcode::LoadRegImm)
                    return false;
                const MicroInstrOperand* maskOps = reachMask.inst->ops(*ctx.operands);
                if (!maskOps)
                    return false;
                mask = maskOps[2].valueU64;
            }
            else
                return false;

            if ((mask & keptMask) != keptMask)
                return false;

            // The AND's flag write must be dead (the shift redefines flags).
            if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, reach.instRef, ctx.builder))
                return false;

            // Drop the AND; `cur` keeps its pre-mask value, which the shift needs.
            if (!ctx.claimAll({reach.instRef}))
                return false;
            ctx.emitErase(reach.instRef);
            return true;
        }

        return false;
    }
    // ~(~a + b) = a - b, including a constant displacement in place of b.
    // Rebuild only the final result after checking both source snapshots.
    bool tryFoldComplementedSum(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ops = inst.ops(*ctx.operands);
        if (ctx.isClaimed(ref) || !ctx.ssa || !ops || !ops[0].reg.isVirtualInt() || ops[2].microOp != MicroOp::BitwiseNot ||
            (ops[1].opBits != MicroOpBits::B32 && ops[1].opBits != MicroOpBits::B64) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
            return false;
        const MicroOpBits bits = ops[1].opBits;
        auto              sum  = ctx.ssa->reachingDef(ops[0].reg, ref);
        MicroInstrRef     resultCopy;
        if (sum.valid() && !sum.isPhi && sum.inst && sum.inst->op == MicroInstrOpcode::LoadRegReg)
        {
            const auto* copy = sum.inst->ops(*ctx.operands);
            if (!copy || !copy[1].reg.isVirtualInt() || getNumBits(copy[2].opBits) < getNumBits(bits) ||
                ctx.ssa->transitiveInstructionUseCount(sum.valueId, 2) != 1)
                return false;
            resultCopy = sum.instRef;
            sum        = ctx.ssa->reachingDef(copy[1].reg, resultCopy);
        }
        if (!sum.valid() || sum.isPhi || !sum.inst || ctx.ssa->transitiveInstructionUseCount(sum.valueId, 2) != 1)
            return false;
        const auto* add = sum.inst->ops(*ctx.operands);
        if (!add)
            return false;
        std::array<MicroReg, 2> inputs;
        std::array              inputRefs{sum.instRef, sum.instRef};
        MicroInstrRef           sumInputCopy;
        bool                    constant     = false;
        uint64_t                displacement = 0;
        if (sum.inst->op == MicroInstrOpcode::LoadAddrAmcRegMem)
        {
            if (add[3].opBits != bits || add[4].opBits != MicroOpBits::B64 || add[5].valueU64 != 1 || add[6].valueU64 != 0)
                return false;
            inputs = {add[1].reg, add[2].reg};
        }
        else if (sum.inst->op == MicroInstrOpcode::LoadAddrRegMem)
        {
            if (add[2].opBits != bits || add[3].hasWideImmediateValue())
                return false;
            inputs[0]    = add[1].reg;
            constant     = true;
            displacement = add[3].valueU64;
        }
        else if (sum.inst->op == MicroInstrOpcode::OpBinaryRegReg)
        {
            if (add[2].opBits != bits || add[3].microOp != MicroOp::Add ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, sum.instRef, ctx.builder))
                return false;
            const auto initial = ctx.ssa->reachingDef(add[0].reg, sum.instRef);
            if (!initial.valid() || initial.isPhi || !initial.inst || initial.inst->op != MicroInstrOpcode::LoadRegReg)
                return false;
            const auto* copy = initial.inst->ops(*ctx.operands);
            if (!copy || copy[2].opBits != bits)
                return false;
            inputs       = {copy[1].reg, add[1].reg};
            inputRefs[0] = initial.instRef;
            sumInputCopy = initial.instRef;
        }
        else
            return false;
        for (uint32_t side = 0; side < (constant ? 1u : 2u); ++side)
        {
            if (!inputs[side].isVirtualInt())
                continue;
            auto          complement = ctx.ssa->reachingDef(inputs[side], inputRefs[side]);
            MicroInstrRef complementCopy;
            if (complement.valid() && !complement.isPhi && complement.inst && complement.inst->op == MicroInstrOpcode::LoadRegReg)
            {
                const auto* copy = complement.inst->ops(*ctx.operands);
                if (!copy || !copy[1].reg.isVirtualInt() || copy[2].opBits != bits ||
                    ctx.ssa->transitiveInstructionUseCount(complement.valueId, 2) != 1)
                    continue;
                complementCopy = complement.instRef;
                complement     = ctx.ssa->reachingDef(copy[1].reg, complementCopy);
            }
            if (!complement.valid() || complement.isPhi || !complement.inst || complement.inst->op != MicroInstrOpcode::OpUnaryReg ||
                ctx.ssa->transitiveInstructionUseCount(complement.valueId, 2) != 1)
                continue;
            const auto* inverted = complement.inst->ops(*ctx.operands);
            if (!inverted || inverted[1].opBits != bits || inverted[2].microOp != MicroOp::BitwiseNot)
                continue;
            const auto original = ctx.ssa->reachingDef(inverted[0].reg, complement.instRef);
            if (!original.valid() || original.isPhi || !original.inst || original.inst->op != MicroInstrOpcode::LoadRegReg)
                continue;
            const auto* copied = original.inst->ops(*ctx.operands);
            if (!copied || !copied[1].reg.isVirtualInt() || copied[2].opBits != bits)
                continue;
            const MicroReg source      = copied[1].reg;
            const auto     sourceValue = ctx.ssa->reachingDef(source, original.instRef);
            if (!sourceValue.valid() || ctx.ssa->reachingDef(source, ref).valueId != sourceValue.valueId)
                continue;
            if (!constant)
            {
                const MicroReg other      = inputs[1 - side];
                const auto     otherValue = ctx.ssa->reachingDef(other, inputRefs[1 - side]);
                if (!other.isVirtualInt() || other == ops[0].reg || !otherValue.valid() ||
                    ctx.ssa->reachingDef(other, ref).valueId != otherValue.valueId)
                    continue;
            }
            if (!ctx.claimAll({ref, sum.instRef, complement.instRef, original.instRef,
                               resultCopy.isValid() ? resultCopy : ref, complementCopy.isValid() ? complementCopy : ref,
                               sumInputCopy.isValid() ? sumInputCopy : ref}))
                continue;
            MicroInstrOperand copy[3];
            copy[0].reg    = ops[0].reg;
            copy[1].reg    = source;
            copy[2].opBits = bits;
            ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadRegReg, copy);
            MicroInstrOperand subtract[4];
            subtract[0].reg = ops[0].reg;
            if (constant)
            {
                subtract[1].opBits   = bits;
                subtract[2].microOp  = MicroOp::Subtract;
                subtract[3].valueU64 = displacement;
                ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegImm, subtract, true);
            }
            else
            {
                subtract[1].reg     = inputs[1 - side];
                subtract[2].opBits  = bits;
                subtract[3].microOp = MicroOp::Subtract;
                ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegReg, subtract, true);
            }
            return true;
        }
        return false;
    }

}

SWC_END_NAMESPACE();
