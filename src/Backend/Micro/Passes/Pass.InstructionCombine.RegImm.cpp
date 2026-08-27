#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// OpBinaryRegImm combiner: identity / absorbing element / reassociation.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
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
                   MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, useRef);
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
            const auto magnitude = static_cast<uint64_t>(negated ? -signedImm : signedImm);
            if (magnitude != 2 && magnitude != 3 && magnitude != 5 && magnitude != 9)
                return false;

            // Keep this operation intact when its only consumer can fuse it with
            // another immediate operation later in the same forward scan.
            if (feedsReassociableImmediate(ctx, ref, dst, opBits, op, imm))
                return false;

            // The multiply writes flags the address computation does not (the
            // negation below writes its own, which the same check covers).
            if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref))
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
                if (!ctx.claimAll({ref}))
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
            const auto reaching = ctx.ssa->reachingDef(dst, ref);
            if (!reaching.valid() || reaching.isPhi || !reaching.inst)
                return false;
            if (reaching.inst->op != MicroInstrOpcode::OpBinaryRegImm)
                return false;

            const MicroInstrOperand* prevOps = reaching.inst->ops(*ctx.operands);
            if (!prevOps || prevOps[0].reg != dst || !isSameOpBitsInt(prevOps[1].opBits, opBits))
                return false;

            const auto* valueInfo = ctx.ssa->valueInfo(reaching.valueId);
            if (!valueInfo || valueInfo->uses.size() != 1)
                return false;

            auto     combinedOp  = MicroOp::Add;
            uint64_t combinedImm = 0;
            if (!tryReassociate(prevOps[2].microOp, prevOps[3].valueU64, op, imm, opBits, combinedOp, combinedImm))
                return false;
            if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref))
                return false;

            if (!ctx.claimAll({ref, reaching.instRef}))
                return false;

            MicroInstrOperand rewritten[4];
            rewritten[0].reg      = dst;
            rewritten[1].opBits   = opBits;
            rewritten[2].microOp  = combinedOp;
            rewritten[3].valueU64 = combinedImm;
            ctx.emitRewrite(reaching.instRef, MicroInstrOpcode::OpBinaryRegImm, rewritten);
            ctx.emitErase(ref);
            return true;
        }
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
        const bool flagsDeadAfter = MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref);

        if (isRightIdentity(op, opBits, imm) && flagsDeadAfter && ctx.ssa && !ctx.ssa->isRegUsedAfter(dst, ref))
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
                MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref) &&
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
        const auto singleRealUse = [&](MicroReg reg, MicroInstrRef defRef) {
            uint32_t vId = 0;
            return ctx.ssa->defValue(reg, defRef, vId) && ctx.ssa->transitiveInstructionUseCount(vId, 2) == 1;
        };

        MicroReg      cur    = dst;
        MicroInstrRef curRef = ref;
        for (int depth = 0; depth < 8; ++depth)
        {
            const auto reach = ctx.ssa->reachingDef(cur, curRef);
            if (!reach.valid() || reach.isPhi || !reach.inst)
                return false;
            if (!singleRealUse(cur, reach.instRef))
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
            if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, reach.instRef))
                return false;

            // Drop the AND; `cur` keeps its pre-mask value, which the shift needs.
            if (!ctx.claimAll({reach.instRef}))
                return false;
            ctx.emitErase(reach.instRef);
            return true;
        }

        return false;
    }
}

SWC_END_NAMESPACE();
