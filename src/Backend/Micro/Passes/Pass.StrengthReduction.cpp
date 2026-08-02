#include "pch.h"
#include "Backend/Micro/Passes/Pass.StrengthReduction.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Math/Helpers.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/Assert.h"

// Pre-RA strength reduction on virtual registers.
//
// Rewrites OpBinaryRegImm into a cheaper form when the immediate exposes a
// pattern the target can encode in fewer / faster instructions:
//
//   v *  0    -> v &  0          (Multiply by zero  -> bitwise mask zero)
//   v *  1    -> v +  0          (Multiply by one   -> identity, dropped by InstCombine)
//   v *  pow2 -> v << log2       (Multiply by power of two -> shift left)
//   v /u pow2 -> v >> log2       (Unsigned divide by pow2 -> logical shift right)
//   v %u pow2 -> v &  (pow2-1)   (Unsigned modulo by pow2 -> bitwise mask)
//   v +/- 0   -> erase if dead   (handled defensively; InstCombine also matches it)
//   v *u w    -> v *s w          (Unsigned multiply -> signed, when flags are dead)
//
// Division and modulo by any other non-zero constant expand into the classic
// multiply-high sequences (Hacker's Delight 10-4 / 10-9): a hardware divide
// costs tens of cycles while the replacement runs in a handful, and every
// mainstream optimizing compiler performs this rewrite. Signed division by a
// power of two gets the dedicated sign-bias sequence. Only B32/B64 operands
// are expanded; B8/B16 divides are too rare to justify the extra forms.

SWC_BEGIN_NAMESPACE();

namespace
{
    // Only x86's one-operand `mul` computes the full double-width product, and
    // it pays for that by hard-wiring rax:rdx and refusing an immediate: a
    // multiply by a constant becomes materialize-constant, save rax, move,
    // multiply, move back, restore rax. `imul` has neither restriction, and its
    // low half is bit-identical whatever the signedness - the wide product lives
    // in MultiplyHigh{Signed,Unsigned}, which this never touches.
    //
    // The one observable difference is the overflow flag: `mul` raises it when
    // the high half is non-zero, `imul` when the signed product does not fit.
    // The arithmetic-overflow safety check reads exactly that, so the rewrite
    // only applies where the flags provably die first.
    bool tryUseSignedMultiply(MicroInstrOperand* ops, const uint8_t microOpSlot)
    {
        if (ops[microOpSlot].microOp != MicroOp::MultiplyUnsigned)
            return false;

        ops[microOpSlot].microOp = MicroOp::MultiplySigned;
        return true;
    }

    bool canRewriteShift(MicroOpBits opBits, uint64_t immediate)
    {
        const uint32_t bitCount = getNumBits(opBits);
        if (!bitCount)
            return false;
        if (!Math::isPowerOfTwo(immediate))
            return false;
        return Math::integerLog2(immediate) < bitCount;
    }

    bool tryReduceMultiplyToShift(MicroInstrOperand* ops, MicroOpBits opBits, uint64_t immediate)
    {
        if (!canRewriteShift(opBits, immediate))
            return false;

        ops[2].microOp  = MicroOp::ShiftLeft;
        ops[3].valueU64 = Math::integerLog2(immediate);
        return true;
    }

    bool tryReduceMultiplyByZero(MicroInstrOperand* ops, uint64_t immediate)
    {
        if (immediate != 0)
            return false;

        ops[2].microOp  = MicroOp::And;
        ops[3].valueU64 = 0;
        return true;
    }

    bool tryReduceMultiplyByOne(MicroInstrOperand* ops, uint64_t immediate)
    {
        if (immediate != 1)
            return false;

        ops[2].microOp  = MicroOp::Add;
        ops[3].valueU64 = 0;
        return true;
    }

    bool tryReduceUnsignedDivideToShift(MicroInstrOperand* ops, MicroOpBits opBits, uint64_t immediate)
    {
        if (immediate == 0 || !canRewriteShift(opBits, immediate))
            return false;

        ops[2].microOp  = MicroOp::ShiftRight;
        ops[3].valueU64 = Math::integerLog2(immediate);
        return true;
    }

    bool tryReduceUnsignedModuloToMask(MicroInstrOperand* ops, MicroOpBits opBits, uint64_t immediate)
    {
        if (immediate == 0 || !canRewriteShift(opBits, immediate))
            return false;

        ops[2].microOp  = MicroOp::And;
        ops[3].valueU64 = immediate - 1;
        return true;
    }

    bool tryReduceAddSubZero(const MicroInstrOperand* ops, MicroStorage& storage, MicroInstrRef instRef, const MicroSsaState& ssaState)
    {
        if (!ssaState.isRegUsedAfter(ops[0].reg, instRef))
        {
            storage.erase(instRef);
            return true;
        }

        return false;
    }

    ///////////////////////////////////////////
    // Division by constant -> multiply-high expansion.

    struct UnsignedDivisionMagic
    {
        uint64_t multiplier = 0;
        uint32_t shift      = 0;
        bool     addFixup   = false; // multiplier does not fit N bits: use the add/shr fixup sequence
    };

    // Hacker's Delight figure 10-9, generalized to the operand width. Requires a
    // non-power-of-two divisor >= 3. All arithmetic stays within N bits.
    UnsignedDivisionMagic computeUnsignedDivisionMagic(uint64_t divisor, uint32_t bits)
    {
        SWC_ASSERT(divisor >= 3 && !Math::isPowerOfTwo(divisor));
        SWC_ASSERT(bits == 32 || bits == 64);

        const uint64_t twoNm1 = 1ull << (bits - 1);
        const uint64_t maxU   = (bits == 64) ? ~0ull : (1ull << bits) - 1;

        UnsignedDivisionMagic magic;
        const uint64_t nc = maxU - (maxU - divisor + 1) % divisor;
        uint32_t       p  = bits - 1;
        uint64_t       q1 = twoNm1 / nc;
        uint64_t       r1 = twoNm1 - q1 * nc;
        uint64_t       q2 = (twoNm1 - 1) / divisor;
        uint64_t       r2 = (twoNm1 - 1) - q2 * divisor;
        uint64_t       delta;

        do
        {
            ++p;
            if (r1 >= nc - r1)
            {
                q1 = 2 * q1 + 1;
                r1 = 2 * r1 - nc;
            }
            else
            {
                q1 = 2 * q1;
                r1 = 2 * r1;
            }

            if (r2 + 1 >= divisor - r2)
            {
                if (q2 >= twoNm1 - 1)
                    magic.addFixup = true;
                q2 = 2 * q2 + 1;
                r2 = 2 * r2 + 1 - divisor;
            }
            else
            {
                if (q2 >= twoNm1)
                    magic.addFixup = true;
                q2 = 2 * q2;
                r2 = 2 * r2 + 1;
            }

            delta = divisor - 1 - r2;
        } while (p < bits * 2 && (q1 < delta || (q1 == delta && r1 == 0)));

        magic.multiplier = (q2 + 1) & maxU;
        magic.shift      = p - bits;
        return magic;
    }

    struct SignedDivisionMagic
    {
        uint64_t multiplier = 0; // N-bit two's-complement pattern
        uint32_t shift      = 0;
    };

    // Hacker's Delight figure 10-4, generalized to the operand width. Requires a
    // non-power-of-two divisor >= 2 (negative divisors are not expanded).
    SignedDivisionMagic computeSignedDivisionMagic(uint64_t divisor, uint32_t bits)
    {
        SWC_ASSERT(divisor >= 2 && !Math::isPowerOfTwo(divisor));
        SWC_ASSERT(bits == 32 || bits == 64);

        const uint64_t twoNm1 = 1ull << (bits - 1);
        const uint64_t maxU   = (bits == 64) ? ~0ull : (1ull << bits) - 1;

        const uint64_t anc = twoNm1 - 1 - (twoNm1 % divisor);
        uint32_t       p   = bits - 1;
        uint64_t       q1  = twoNm1 / anc;
        uint64_t       r1  = twoNm1 - q1 * anc;
        uint64_t       q2  = twoNm1 / divisor;
        uint64_t       r2  = twoNm1 - q2 * divisor;
        uint64_t       delta;

        do
        {
            ++p;
            q1 = 2 * q1;
            r1 = 2 * r1;
            if (r1 >= anc)
            {
                q1 += 1;
                r1 -= anc;
            }

            q2 = 2 * q2;
            r2 = 2 * r2;
            if (r2 >= divisor)
            {
                q2 += 1;
                r2 -= divisor;
            }

            delta = divisor - r2;
        } while (q1 < delta || (q1 == delta && r1 == 0));

        SignedDivisionMagic magic;
        magic.multiplier = (q2 + 1) & maxU;
        magic.shift      = p - bits;
        return magic;
    }

    // Inserts the replacement instructions right before the div/mod being expanded,
    // deriving their debug info from it.
    struct DivisionExpansionEmitter
    {
        MicroStorage&        storage;
        MicroOperandStorage& operands;
        MicroInstrRef        beforeRef;
        MicroOpBits          opBits;
        uint32_t&            nextVirtualIntRegIndex;

        MicroReg allocVirtualReg() const
        {
            SWC_ASSERT(nextVirtualIntRegIndex < MicroReg::K_MAX_INDEX);
            return MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
        }

        void emitLoadImm(MicroReg reg, uint64_t value) const
        {
            MicroInstrOperand ops[3];
            ops[0].reg    = reg;
            ops[1].opBits = opBits;
            ops[2].setImmediateValue(ApInt(value, getNumBits(opBits)));
            storage.insertDerivedBefore(operands, beforeRef, MicroInstrOpcode::LoadRegImm, ops);
        }

        void emitCopy(MicroReg dst, MicroReg src) const
        {
            MicroInstrOperand ops[3];
            ops[0].reg    = dst;
            ops[1].reg    = src;
            ops[2].opBits = opBits;
            storage.insertDerivedBefore(operands, beforeRef, MicroInstrOpcode::LoadRegReg, ops);
        }

        void emitOpRegImm(MicroReg reg, MicroOp op, uint64_t value) const
        {
            MicroInstrOperand ops[4];
            ops[0].reg    = reg;
            ops[1].opBits = opBits;
            ops[2].microOp = op;
            ops[3].setImmediateValue(ApInt(value, getNumBits(opBits)));
            storage.insertDerivedBefore(operands, beforeRef, MicroInstrOpcode::OpBinaryRegImm, ops);
        }

        void emitOpRegReg(MicroReg dst, MicroReg src, MicroOp op) const
        {
            MicroInstrOperand ops[4];
            ops[0].reg    = dst;
            ops[1].reg    = src;
            ops[2].opBits = opBits;
            ops[3].microOp = op;
            storage.insertDerivedBefore(operands, beforeRef, MicroInstrOpcode::OpBinaryRegReg, ops);
        }

        // dst = dst / C for a non-power-of-two unsigned constant.
        // With the fixup: q = ((n - mulhi(n, M)) >> 1 + mulhi(n, M)) >> (shift - 1).
        void emitUnsignedDivide(MicroReg dst, const UnsignedDivisionMagic& magic) const
        {
            const MicroReg magicReg = allocVirtualReg();
            emitLoadImm(magicReg, magic.multiplier);

            if (!magic.addFixup)
            {
                emitOpRegReg(dst, magicReg, MicroOp::MultiplyHighUnsigned);
                if (magic.shift)
                    emitOpRegImm(dst, MicroOp::ShiftRight, magic.shift);
                return;
            }

            SWC_ASSERT(magic.shift >= 1);
            const MicroReg dividendReg = allocVirtualReg();
            emitCopy(dividendReg, dst);
            emitOpRegReg(dst, magicReg, MicroOp::MultiplyHighUnsigned);
            const MicroReg fixupReg = allocVirtualReg();
            emitCopy(fixupReg, dividendReg);
            emitOpRegReg(fixupReg, dst, MicroOp::Subtract);
            emitOpRegImm(fixupReg, MicroOp::ShiftRight, 1);
            emitOpRegReg(fixupReg, dst, MicroOp::Add);
            if (magic.shift > 1)
                emitOpRegImm(fixupReg, MicroOp::ShiftRight, magic.shift - 1);
            emitCopy(dst, fixupReg);
        }

        // dst = dst / C for a positive signed constant power of two (C = 2^k, k >= 1):
        // q = (n + ((n >> N-1) >>u N-k)) >> k, all shifts arithmetic except the bias.
        void emitSignedDividePow2(MicroReg dst, uint32_t log2Divisor) const
        {
            const uint32_t bits    = getNumBits(opBits);
            const MicroReg biasReg = allocVirtualReg();
            emitCopy(biasReg, dst);
            emitOpRegImm(biasReg, MicroOp::ShiftArithmeticRight, bits - 1);
            emitOpRegImm(biasReg, MicroOp::ShiftRight, bits - log2Divisor);
            emitOpRegReg(dst, biasReg, MicroOp::Add);
            emitOpRegImm(dst, MicroOp::ShiftArithmeticRight, log2Divisor);
        }

        // dst = dst / C for a positive non-power-of-two signed constant:
        // t = mulhi_s(n, M); if M < 0 then t += n; t >>= shift (arithmetic);
        // q = t + (t >>u N-1). The dividend must be provided when M is negative.
        void emitSignedDivideMagic(MicroReg dst, MicroReg dividendReg, const SignedDivisionMagic& magic) const
        {
            const uint32_t bits           = getNumBits(opBits);
            const bool     negativeMagic  = (magic.multiplier >> (bits - 1)) & 1;
            const MicroReg magicReg       = allocVirtualReg();
            emitLoadImm(magicReg, magic.multiplier);
            emitOpRegReg(dst, magicReg, MicroOp::MultiplyHighSigned);
            if (negativeMagic)
                emitOpRegReg(dst, dividendReg, MicroOp::Add);
            if (magic.shift)
                emitOpRegImm(dst, MicroOp::ShiftArithmeticRight, magic.shift);
            const MicroReg signReg = allocVirtualReg();
            emitCopy(signReg, dst);
            emitOpRegImm(signReg, MicroOp::ShiftRight, bits - 1);
            emitOpRegReg(dst, signReg, MicroOp::Add);
        }

        // Rewrites the quotient already in dst into the remainder: r = n - q * C.
        void emitRemainderFromQuotient(MicroReg dst, MicroReg dividendReg, uint64_t divisor) const
        {
            emitOpRegImm(dst, MicroOp::MultiplySigned, divisor);
            const MicroReg remainderReg = allocVirtualReg();
            emitCopy(remainderReg, dividendReg);
            emitOpRegReg(remainderReg, dst, MicroOp::Subtract);
            emitCopy(dst, remainderReg);
        }
    };

    bool tryExpandDivisionByConstant(MicroPassContext& context, MicroStorage& storage, MicroOperandStorage& operands, MicroInstrRef instRef, MicroInstrOperand* ops, uint32_t& nextVirtualIntRegIndex)
    {
        const MicroOpBits opBits = ops[1].opBits;
        if (opBits != MicroOpBits::B32 && opBits != MicroOpBits::B64)
            return false;

        const uint32_t bits      = getNumBits(opBits);
        const uint64_t bitsMask  = getBitsMask(opBits);
        const MicroOp  microOp   = ops[2].microOp;
        const uint64_t immediate = ops[3].valueU64 & bitsMask;
        const MicroReg dstReg    = ops[0].reg;

        const bool isSigned = microOp == MicroOp::DivideSigned || microOp == MicroOp::ModuloSigned;
        const bool isModulo = microOp == MicroOp::ModuloUnsigned || microOp == MicroOp::ModuloSigned;

        if (immediate == 0)
            return false; // preserve the hardware divide-by-zero behavior

        // Signed divisors <= 0 are rare; INT_MIN / -1 would also need trap-preserving
        // care. Keep the hardware divide for them.
        const bool signBitSet = (immediate >> (bits - 1)) & 1;
        if (isSigned && signBitSet)
            return false;

        if (nextVirtualIntRegIndex == 0)
            nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);

        const DivisionExpansionEmitter emitter{storage, operands, instRef, opBits, nextVirtualIntRegIndex};

        if (!isSigned)
        {
            // Powers of two (and 1) are reduced to shift/mask before this point; the
            // masked immediate can still be one when the stored value carried bits
            // above the operand width. Leave that oddity to the hardware divide.
            if (Math::isPowerOfTwo(immediate))
                return false;

            const UnsignedDivisionMagic magic = computeUnsignedDivisionMagic(immediate, bits);
            if (isModulo)
            {
                const MicroReg dividendReg = emitter.allocVirtualReg();
                emitter.emitCopy(dividendReg, dstReg);
                emitter.emitUnsignedDivide(dstReg, magic);
                emitter.emitRemainderFromQuotient(dstReg, dividendReg, immediate);
            }
            else
            {
                emitter.emitUnsignedDivide(dstReg, magic);
            }

            storage.erase(instRef);
            return true;
        }

        if (immediate == 1)
        {
            // n / 1 == n, n % 1 == 0, for any signed n.
            ops[2].microOp  = isModulo ? MicroOp::And : MicroOp::Add;
            ops[3].valueU64 = 0;
            return true;
        }

        const MicroReg dividendReg = emitter.allocVirtualReg();
        emitter.emitCopy(dividendReg, dstReg);

        if (Math::isPowerOfTwo(immediate))
            emitter.emitSignedDividePow2(dstReg, Math::integerLog2(immediate));
        else
            emitter.emitSignedDivideMagic(dstReg, dividendReg, computeSignedDivisionMagic(immediate, bits));

        if (isModulo)
            emitter.emitRemainderFromQuotient(dstReg, dividendReg, immediate);

        storage.erase(instRef);
        return true;
    }
}

Result MicroStrengthReductionPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/StrengthReduce");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;
    MicroSsaState        localSsaState;
    const MicroSsaState* ssaState               = nullptr;
    uint32_t             nextVirtualIntRegIndex = 0; // computed lazily on the first expansion

    const auto view  = storage.view();
    const auto endIt = view.end();
    for (auto it = view.begin(); it != endIt;)
    {
        const MicroInstrRef instRef = it.current;
        const MicroInstr&   inst    = *it;
        ++it;

        const bool isRegImm = inst.op == MicroInstrOpcode::OpBinaryRegImm;
        const bool isRegReg = inst.op == MicroInstrOpcode::OpBinaryRegReg;
        if (!isRegImm && !isRegReg)
            continue;

        MicroInstrOperand* ops = inst.ops(operands);
        if (!ops)
            continue;

        if (!ops[0].reg.isAnyInt())
            continue;

        // Changing which condition the flags describe needs the strict window:
        // a fused branch keeps them live across a jump, which the relaxed
        // "dead after" contract does not see.
        if (MicroPassHelpers::areCpuFlagsRedefinedBeforeBoundary(storage, operands, instRef))
        {
            // ops: RegImm is [1] opBits [2] microOp [3] imm, RegReg is [2] opBits [3] microOp.
            if (tryUseSignedMultiply(ops, isRegImm ? 2 : 3))
                context.passChanged = true;
        }

        if (!isRegImm)
            continue;

        const MicroOpBits opBits    = ops[1].opBits;
        const MicroOp     microOp   = ops[2].microOp;
        const uint64_t    immediate = ops[3].valueU64;
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, instRef))
            continue;

        bool changed = false;
        switch (microOp)
        {
            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
                changed = tryReduceMultiplyByZero(ops, immediate) ||
                          tryReduceMultiplyByOne(ops, immediate) ||
                          tryReduceMultiplyToShift(ops, opBits, immediate);
                break;

            case MicroOp::Add:
            case MicroOp::Subtract:
                if (immediate == 0)
                {
                    if (!ssaState)
                        ssaState = MicroSsaState::ensureFor(context, localSsaState);
                    if (ssaState && ssaState->isValid())
                        changed = tryReduceAddSubZero(ops, storage, instRef, *ssaState);
                }
                break;

            case MicroOp::DivideUnsigned:
                changed = tryReduceUnsignedDivideToShift(ops, opBits, immediate) ||
                          tryExpandDivisionByConstant(context, storage, operands, instRef, ops, nextVirtualIntRegIndex);
                break;

            case MicroOp::ModuloUnsigned:
                changed = tryReduceUnsignedModuloToMask(ops, opBits, immediate) ||
                          tryExpandDivisionByConstant(context, storage, operands, instRef, ops, nextVirtualIntRegIndex);
                break;

            case MicroOp::DivideSigned:
            case MicroOp::ModuloSigned:
                changed = tryExpandDivisionByConstant(context, storage, operands, instRef, ops, nextVirtualIntRegIndex);
                break;

            default:
                break;
        }

        if (changed)
            context.passChanged = true;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
