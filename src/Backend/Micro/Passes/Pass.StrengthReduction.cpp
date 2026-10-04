#include "pch.h"
#include "Backend/Micro/Passes/Pass.StrengthReduction.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Math/Helpers.h"
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
//
// A signed division or remainder by a positive constant is the unsigned one
// when the dividend cannot be negative, and the unsigned forms are the cheap
// ones: a mask, a shift, a multiply-high with no sign correction. The dividend
// is proved non-negative by what defines it (a zero extension, a mask, a
// logical shift, a 32-bit result read at 64 bits) or by a test that every
// path to the division has passed, as the `cand >= 0` of a loop condition is
// for the `cand % size` of its body.

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
    bool tryUseSignedMultiply(MicroPassContext& context, MicroInstrRef instRef, MicroInstrOperand* ops, const uint8_t microOpSlot)
    {
        if (ops[microOpSlot].microOp != MicroOp::MultiplyUnsigned)
            return false;
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*context.instructions, *context.operands, instRef, context.builder))
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

    ///////////////////////////////////////////
    // `x % C == 0` -> divisibility test.

    // The flag reader of `cmp`, when it only asks for equality.
    MicroInstr* findEqualityReader(MicroStorage& storage, MicroOperandStorage& operands, MicroInstrRef cmpRef, MicroInstrRef& outRef, MicroCond*& outCond)
    {
        outRef             = storage.findNextInstructionRef(cmpRef);
        MicroInstr* reader = outRef.isValid() ? storage.ptr(outRef) : nullptr;
        if (!reader)
            return nullptr;
        MicroInstrOperand* readerOps = reader->ops(operands);
        switch (reader->op)
        {
            case MicroInstrOpcode::SetCondReg:
                outCond = &readerOps[1].cpuCond;
                break;
            case MicroInstrOpcode::JumpCond:
                outCond = &readerOps[0].cpuCond;
                break;
            case MicroInstrOpcode::LoadCondRegReg:
                outCond = &readerOps[2].cpuCond;
                break;
            default:
                return nullptr;
        }
        return *outCond == MicroCond::Equal || *outCond == MicroCond::NotEqual ? reader : nullptr;
    }

    // Whether the remainder `instRef` leaves in `value` is only ever compared
    // with zero for equality: the compare follows, its one reader asks for
    // equal or not equal, and nothing else reads the remainder or the flags.
    bool isOnlyTestedAgainstZero(MicroPassContext& context, MicroStorage& storage, MicroOperandStorage& operands, const MicroSsaState*& ssaState, MicroSsaState& localSsaState, MicroInstrRef instRef, const MicroReg value, const MicroOpBits opBits, MicroInstrRef& outCmpRef)
    {
        // The compare may follow a few moves that leave the flags alone, as
        // the zero it reads being loaded.
        constexpr uint32_t K_MAX_MOVES = 3;
        MicroInstrRef      cmpRef      = storage.findNextInstructionRef(instRef);
        const MicroInstr*  cmp         = cmpRef.isValid() ? storage.ptr(cmpRef) : nullptr;
        for (uint32_t step = 0; step < K_MAX_MOVES && cmp && (cmp->op == MicroInstrOpcode::LoadRegImm || cmp->op == MicroInstrOpcode::LoadRegReg); ++step)
        {
            if (cmp->ops(operands)[0].reg == value)
                return false;
            cmpRef = storage.findNextInstructionRef(cmpRef);
            cmp    = cmpRef.isValid() ? storage.ptr(cmpRef) : nullptr;
        }
        if (!cmp || cmp->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const MicroInstrOperand* cmpOps = cmp->ops(operands);
        if (cmpOps[0].reg != value || cmpOps[1].opBits != opBits || cmpOps[2].hasWideImmediateValue() || (cmpOps[2].valueU64 & getBitsMask(opBits)) != 0)
            return false;

        MicroInstrRef readerRef;
        MicroCond*    cond = nullptr;
        if (!findEqualityReader(storage, operands, cmpRef, readerRef, cond))
            return false;
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, readerRef, context.builder))
            return false;
        // Only the matching compare and reader need SSA to prove unique use.
        if (!ssaState)
            ssaState = MicroSsaState::ensureFor(context, localSsaState);
        if (!ssaState || !ssaState->isValid())
            return false;
        // The compare is the remainder's only reader.
        uint32_t remainderId = MicroSsaState::K_INVALID_VALUE;
        if (!ssaState->defValue(value, instRef, remainderId) || ssaState->transitiveInstructionUseCount(remainderId, 2) != 1)
            return false;

        outCmpRef = cmpRef;
        return true;
    }

    // A signed remainder by a power of two is zero exactly when the low bits
    // of the dividend are, whatever its sign: `x % 8 == 0` tests `x & 7`.
    // The sign correction only matters to a reader of the remainder's value.
    bool tryReduceSignedModuloPow2Equality(MicroPassContext& context, MicroStorage& storage, MicroOperandStorage& operands, const MicroSsaState*& ssaState, MicroSsaState& localSsaState, MicroInstrRef instRef, MicroInstrOperand* ops)
    {
        const MicroOpBits opBits  = ops[1].opBits;
        const uint64_t    divisor = ops[3].valueU64 & getBitsMask(opBits);
        if ((opBits != MicroOpBits::B32 && opBits != MicroOpBits::B64) || ops[3].hasWideImmediateValue() || divisor < 2 ||
            !Math::isPowerOfTwo(divisor) || !canRewriteShift(opBits, divisor) || !ops[0].reg.isVirtualInt())
            return false;

        MicroInstrRef cmpRef;
        if (!isOnlyTestedAgainstZero(context, storage, operands, ssaState, localSsaState, instRef, ops[0].reg, opBits, cmpRef))
            return false;

        ops[2].microOp  = MicroOp::And;
        ops[3].valueU64 = divisor - 1;
        return true;
    }

    // The inverse of an odd value modulo 2^64, by Newton's iteration: each step
    // doubles the correct low bits, from the three an odd value starts with.
    uint64_t oddInverse(uint64_t value)
    {
        uint64_t inverse = value;
        for (uint32_t step = 0; step < 5; ++step)
            inverse *= 2 - value * inverse;
        return inverse;
    }

    // An unsigned remainder by a constant only compared with zero is a
    // divisibility test, as LLVM's urem-seteq fold builds it:
    //
    //     r = x % C; cmp r, 0; sete      ->    x *= inv(C0); x = rotr(x, k)
    //                                          cmp x, (2^N - 1) / C; setbe
    //
    // with C = C0 * 2^k and C0 odd. Multiplying by the inverse maps the
    // multiples of C0 onto [0, (2^N - 1) / C0], and the rotation also sends
    // anything with a low bit set among the k low bits above the limit.
    bool tryReduceUnsignedModuloEquality(MicroPassContext& context, MicroStorage& storage, MicroOperandStorage& operands, const MicroSsaState*& ssaState, MicroSsaState& localSsaState, MicroInstrRef instRef, MicroInstrOperand* ops, uint32_t& nextVirtualIntRegIndex)
    {
        const MicroOpBits opBits  = ops[1].opBits;
        const uint32_t    bits    = getNumBits(opBits);
        const uint64_t    mask    = getBitsMask(opBits);
        const uint64_t    divisor = ops[3].valueU64 & mask;
        const MicroReg    value   = ops[0].reg;
        if ((opBits != MicroOpBits::B32 && opBits != MicroOpBits::B64) || divisor < 3 || Math::isPowerOfTwo(divisor) || !value.isVirtualInt())
            return false;

        MicroInstrRef cmpRef;
        if (!isOnlyTestedAgainstZero(context, storage, operands, ssaState, localSsaState, instRef, value, opBits, cmpRef))
            return false;

        const uint32_t shift   = static_cast<uint32_t>(std::countr_zero(divisor));
        const uint64_t odd     = divisor >> shift;
        const uint64_t inverse = oddInverse(odd) & mask;
        const uint64_t limit   = mask / divisor;
        if (opBits == MicroOpBits::B64 && limit > static_cast<uint64_t>(std::numeric_limits<int32_t>::max()))
            return false;

        if (opBits == MicroOpBits::B32)
        {
            ops[2].microOp = MicroOp::MultiplySigned;
            ops[3].setImmediateValue(ApInt(inverse, 32));
        }
        else
        {
            if (!nextVirtualIntRegIndex)
                nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
            const MicroReg    inverseReg = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
            MicroInstrOperand loadOps[3];
            loadOps[0].reg    = inverseReg;
            loadOps[1].opBits = MicroOpBits::B64;
            loadOps[2].setImmediateValue(ApInt(inverse, 64));
            storage.insertDerivedBefore(operands, instRef, MicroInstrOpcode::LoadRegImm, loadOps);
            MicroInstrOperand mulOps[4];
            mulOps[0].reg     = value;
            mulOps[1].reg     = inverseReg;
            mulOps[2].opBits  = MicroOpBits::B64;
            mulOps[3].microOp = MicroOp::MultiplySigned;
            storage.insertDerivedBefore(operands, instRef, MicroInstrOpcode::OpBinaryRegReg, mulOps);
            storage.erase(instRef);
        }

        if (shift)
        {
            MicroInstrOperand rotateOps[4];
            rotateOps[0].reg     = value;
            rotateOps[1].opBits  = opBits;
            rotateOps[2].microOp = MicroOp::RotateRight;
            rotateOps[3].setImmediateValue(ApInt(shift, bits));
            storage.insertDerivedBefore(operands, cmpRef, MicroInstrOpcode::OpBinaryRegImm, rotateOps);
        }

        MicroInstrOperand* cmpOps = storage.ptr(cmpRef)->ops(operands);
        cmpOps[2].setImmediateValue(ApInt(limit, bits));
        MicroInstrRef ignored;
        MicroCond*    cond = nullptr;
        findEqualityReader(storage, operands, cmpRef, ignored, cond);
        *cond = *cond == MicroCond::Equal ? MicroCond::BelowOrEqual : MicroCond::Above;
        return true;
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
        const uint64_t        nc = maxU - (maxU - divisor + 1) % divisor;
        uint32_t              p  = bits - 1;
        uint64_t              q1 = twoNm1 / nc;
        uint64_t              r1 = twoNm1 - q1 * nc;
        uint64_t              q2 = (twoNm1 - 1) / divisor;
        uint64_t              r2 = (twoNm1 - 1) - q2 * divisor;
        uint64_t              delta;

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
        MicroStorage*        storage;
        MicroOperandStorage* operands;
        MicroInstrRef        beforeRef;
        MicroOpBits          opBits;
        uint32_t*            nextVirtualIntRegIndex;

        MicroReg allocVirtualReg() const
        {
            SWC_ASSERT(*nextVirtualIntRegIndex < MicroReg::K_MAX_INDEX);
            return MicroReg::virtualIntReg((*nextVirtualIntRegIndex)++);
        }

        void emitLoadImm(MicroReg reg, uint64_t value) const
        {
            MicroInstrOperand ops[3];
            ops[0].reg    = reg;
            ops[1].opBits = opBits;
            ops[2].setImmediateValue(ApInt(value, getNumBits(opBits)));
            storage->insertDerivedBefore(*operands, beforeRef, MicroInstrOpcode::LoadRegImm, ops);
        }

        void emitCopy(MicroReg dst, MicroReg src) const
        {
            MicroInstrOperand ops[3];
            ops[0].reg    = dst;
            ops[1].reg    = src;
            ops[2].opBits = opBits;
            storage->insertDerivedBefore(*operands, beforeRef, MicroInstrOpcode::LoadRegReg, ops);
        }

        void emitOpRegImm(MicroReg reg, MicroOp op, uint64_t value) const
        {
            MicroInstrOperand ops[4];
            ops[0].reg     = reg;
            ops[1].opBits  = opBits;
            ops[2].microOp = op;
            ops[3].setImmediateValue(ApInt(value, getNumBits(opBits)));
            storage->insertDerivedBefore(*operands, beforeRef, MicroInstrOpcode::OpBinaryRegImm, ops);
        }

        void emitOpRegReg(MicroReg dst, MicroReg src, MicroOp op) const
        {
            MicroInstrOperand ops[4];
            ops[0].reg     = dst;
            ops[1].reg     = src;
            ops[2].opBits  = opBits;
            ops[3].microOp = op;
            storage->insertDerivedBefore(*operands, beforeRef, MicroInstrOpcode::OpBinaryRegReg, ops);
        }

        // dst = (zext(src) * multiplier) >> shift, the 64-bit product of a
        // 32-bit value and a 32-bit multiplier, which cannot overflow.
        void emitWideHigh32(MicroReg dst, MicroReg src, uint64_t multiplier, uint32_t shift) const
        {
            const MicroReg wideReg  = allocVirtualReg();
            const MicroReg magicReg = allocVirtualReg();
            emitCopy(wideReg, src);
            MicroInstrOperand loadOps[3];
            loadOps[0].reg    = magicReg;
            loadOps[1].opBits = MicroOpBits::B64;
            loadOps[2].setImmediateValue(ApInt(multiplier, 64));
            storage->insertDerivedBefore(*operands, beforeRef, MicroInstrOpcode::LoadRegImm, loadOps);
            MicroInstrOperand mulOps[4];
            mulOps[0].reg     = wideReg;
            mulOps[1].reg     = magicReg;
            mulOps[2].opBits  = MicroOpBits::B64;
            mulOps[3].microOp = MicroOp::MultiplySigned;
            storage->insertDerivedBefore(*operands, beforeRef, MicroInstrOpcode::OpBinaryRegReg, mulOps);
            MicroInstrOperand shiftOps[4];
            shiftOps[0].reg     = wideReg;
            shiftOps[1].opBits  = MicroOpBits::B64;
            shiftOps[2].microOp = MicroOp::ShiftRight;
            shiftOps[3].setImmediateValue(ApInt(shift, 64));
            storage->insertDerivedBefore(*operands, beforeRef, MicroInstrOpcode::OpBinaryRegImm, shiftOps);
            emitCopy(dst, wideReg);
        }

        // dst = (sext(dst) * sext(multiplier)) >> shift, arithmetic, in 64 bits.
        void emitWideSignedHigh32(MicroReg dst, uint64_t multiplier, uint32_t shift) const
        {
            const MicroReg    wideReg  = allocVirtualReg();
            const MicroReg    magicReg = allocVirtualReg();
            MicroInstrOperand extendOps[4];
            extendOps[0].reg    = wideReg;
            extendOps[1].reg    = dst;
            extendOps[2].opBits = MicroOpBits::B64;
            extendOps[3].opBits = MicroOpBits::B32;
            storage->insertDerivedBefore(*operands, beforeRef, MicroInstrOpcode::LoadSignedExtRegReg, extendOps);
            MicroInstrOperand loadOps[3];
            loadOps[0].reg    = magicReg;
            loadOps[1].opBits = MicroOpBits::B64;
            loadOps[2].setImmediateValue(ApInt(static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(multiplier))), 64));
            storage->insertDerivedBefore(*operands, beforeRef, MicroInstrOpcode::LoadRegImm, loadOps);
            MicroInstrOperand mulOps[4];
            mulOps[0].reg     = wideReg;
            mulOps[1].reg     = magicReg;
            mulOps[2].opBits  = MicroOpBits::B64;
            mulOps[3].microOp = MicroOp::MultiplySigned;
            storage->insertDerivedBefore(*operands, beforeRef, MicroInstrOpcode::OpBinaryRegReg, mulOps);
            MicroInstrOperand shiftOps[4];
            shiftOps[0].reg     = wideReg;
            shiftOps[1].opBits  = MicroOpBits::B64;
            shiftOps[2].microOp = MicroOp::ShiftArithmeticRight;
            shiftOps[3].setImmediateValue(ApInt(shift, 64));
            storage->insertDerivedBefore(*operands, beforeRef, MicroInstrOpcode::OpBinaryRegImm, shiftOps);
            emitCopy(dst, wideReg);
        }

        // dst = dst / C for a non-power-of-two unsigned constant.
        // With the fixup: q = ((n - mulhi(n, M)) >> 1 + mulhi(n, M)) >> (shift - 1).
        void emitUnsignedDivide(MicroReg dst, const UnsignedDivisionMagic& magic) const
        {
            // A 32-bit dividend times a 32-bit multiplier fits in 64 bits: the
            // plain 64-bit product shifted down is the high half, as LLVM emits
            // it, and needs neither rax nor rdx.
            if (opBits == MicroOpBits::B32)
            {
                if (!magic.addFixup)
                {
                    emitWideHigh32(dst, dst, magic.multiplier, 32 + magic.shift);
                    return;
                }

                SWC_ASSERT(magic.shift >= 1);
                const MicroReg dividendReg = allocVirtualReg();
                emitCopy(dividendReg, dst);
                emitWideHigh32(dst, dividendReg, magic.multiplier, 32);
                const MicroReg fixupReg = allocVirtualReg();
                emitCopy(fixupReg, dividendReg);
                emitOpRegReg(fixupReg, dst, MicroOp::Subtract);
                emitOpRegImm(fixupReg, MicroOp::ShiftRight, 1);
                emitOpRegReg(fixupReg, dst, MicroOp::Add);
                if (magic.shift > 1)
                    emitOpRegImm(fixupReg, MicroOp::ShiftRight, magic.shift - 1);
                emitCopy(dst, fixupReg);
                return;
            }

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
        // From C = 4, as LLVM's x86 lowering does, the rounding bias is
        // selected instead: q = (n >= 0 ? n : n + C - 1) >> k, a `lea`, a
        // compare, a `cmov` and the shift.
        void emitSignedDividePow2(MicroReg dst, uint32_t log2Divisor) const
        {
            const uint32_t bits = getNumBits(opBits);
            if (log2Divisor > 1 && log2Divisor < 32)
            {
                const MicroReg roundedReg = allocVirtualReg();
                emitCopy(roundedReg, dst);
                emitOpRegImm(roundedReg, MicroOp::Add, (1ull << log2Divisor) - 1);
                MicroInstrOperand cmpOps[3];
                cmpOps[0].reg    = dst;
                cmpOps[1].opBits = opBits;
                cmpOps[2].setImmediateValue(ApInt(uint64_t{0}, bits));
                storage->insertDerivedBefore(*operands, beforeRef, MicroInstrOpcode::CmpRegImm, cmpOps);
                MicroInstrOperand selectOps[4];
                selectOps[0].reg     = roundedReg;
                selectOps[1].reg     = dst;
                selectOps[2].cpuCond = MicroCond::GreaterOrEqual;
                selectOps[3].opBits  = opBits;
                storage->insertDerivedBefore(*operands, beforeRef, MicroInstrOpcode::LoadCondRegReg, selectOps);
                emitOpRegImm(roundedReg, MicroOp::ShiftArithmeticRight, log2Divisor);
                emitCopy(dst, roundedReg);
                return;
            }

            const MicroReg biasReg = allocVirtualReg();
            emitCopy(biasReg, dst);
            // Division by two needs only the sign bit as its rounding bias.
            if (log2Divisor > 1)
                emitOpRegImm(biasReg, MicroOp::ShiftArithmeticRight, bits - 1);
            emitOpRegImm(biasReg, MicroOp::ShiftRight, bits - log2Divisor);
            emitOpRegReg(dst, biasReg, MicroOp::Add);
            emitOpRegImm(dst, MicroOp::ShiftArithmeticRight, log2Divisor);
        }

        // r = ((n + bias) & (C - 1)) - bias rounds signed remainders toward zero.
        // Computing the low bits directly avoids materializing and rescaling a quotient.
        void emitSignedModuloPow2(MicroReg dst, uint32_t log2Divisor) const
        {
            const uint32_t bits    = getNumBits(opBits);
            const MicroReg biasReg = allocVirtualReg();
            emitCopy(biasReg, dst);
            if (log2Divisor > 1)
                emitOpRegImm(biasReg, MicroOp::ShiftArithmeticRight, bits - 1);
            emitOpRegImm(biasReg, MicroOp::ShiftRight, bits - log2Divisor);
            emitOpRegReg(dst, biasReg, MicroOp::Add);
            emitOpRegImm(dst, MicroOp::And, (1ull << log2Divisor) - 1);
            emitOpRegReg(dst, biasReg, MicroOp::Subtract);
        }

        // dst = dst / C for a positive non-power-of-two signed constant:
        // t = mulhi_s(n, M); if M < 0 then t += n; t >>= shift (arithmetic);
        // q = t + (t >>u N-1). The dividend must be provided when M is negative.
        void emitSignedDivideMagic(MicroReg dst, MicroReg dividendReg, const SignedDivisionMagic& magic) const
        {
            const uint32_t bits          = getNumBits(opBits);
            const bool     negativeMagic = (magic.multiplier >> (bits - 1)) & 1;
            if (opBits == MicroOpBits::B32)
            {
                // The 64-bit product of two sign-extended 32-bit values holds
                // the signed high half; with a positive multiplier the magic
                // shift folds into the one that extracts it.
                const uint32_t shift = negativeMagic ? 32 : 32 + magic.shift;
                emitWideSignedHigh32(dst, magic.multiplier, shift);
                if (negativeMagic)
                {
                    emitOpRegReg(dst, dividendReg, MicroOp::Add);
                    if (magic.shift)
                        emitOpRegImm(dst, MicroOp::ShiftArithmeticRight, magic.shift);
                }
            }
            else
            {
                const MicroReg magicReg = allocVirtualReg();
                emitLoadImm(magicReg, magic.multiplier);
                emitOpRegReg(dst, magicReg, MicroOp::MultiplyHighSigned);
                if (negativeMagic)
                    emitOpRegReg(dst, dividendReg, MicroOp::Add);
                if (magic.shift)
                    emitOpRegImm(dst, MicroOp::ShiftArithmeticRight, magic.shift);
            }
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

    // A compare with a constant whose following jump leaves, on one of its two
    // edges, a value that cannot be negative. `proven` is the first instruction
    // of that edge and is reached through it alone, so whatever it dominates
    // has passed the test.
    struct SignTest
    {
        uint32_t    valueId = MicroSsaState::K_INVALID_VALUE;
        uint32_t    proven  = 0;
        MicroOpBits bits    = MicroOpBits::Zero;
    };

    void collectSignTests(std::vector<SignTest>& outTests, const MicroSsaState& ssa, const MicroControlFlowGraph& cfg, const MicroStorage& storage, const MicroOperandStorage& operands)
    {
        const auto     refs = cfg.instructionRefs();
        const uint32_t n    = cfg.instructionCount();
        for (uint32_t i = 0; i + 2 < n; ++i)
        {
            const MicroInstr* cmp  = storage.ptr(refs[i]);
            const MicroInstr* jump = storage.ptr(refs[i + 1]);
            if (!cmp || !jump || cmp->op != MicroInstrOpcode::CmpRegImm || jump->op != MicroInstrOpcode::JumpCond || jump->numOperands < 3)
                continue;
            const MicroInstrOperand* cmpOps  = cmp->ops(operands);
            const MicroInstrOperand* jumpOps = jump->ops(operands);
            if (!cmpOps || !jumpOps || !cmpOps[0].reg.isVirtualInt() || cmpOps[2].hasWideImmediateValue())
                continue;
            const MicroOpBits bits = cmpOps[1].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                continue;

            // The immediate as a signed value of the compared width.
            const uint32_t width = getNumBits(bits);
            const int64_t  bound = static_cast<int64_t>(cmpOps[2].valueU64 << (64 - width)) >> (64 - width);

            // Not below `bound` on one edge; that edge proves the sign when
            // `bound` is not negative, or is minus one for a strict test.
            uint32_t proven = MicroSsaState::K_INVALID_VALUE;
            switch (jumpOps[0].cpuCond)
            {
                case MicroCond::Less:
                    if (bound >= 0)
                        proven = i + 2;
                    break;
                case MicroCond::LessOrEqual:
                    if (bound >= -1)
                        proven = i + 2;
                    break;
                case MicroCond::GreaterOrEqual:
                    if (bound >= 0)
                        proven = cfg.indexOfLabel(jumpOps[2].valueU64);
                    break;
                case MicroCond::Greater:
                    if (bound >= -1)
                        proven = cfg.indexOfLabel(jumpOps[2].valueU64);
                    break;
                default:
                    break;
            }
            // A jump to the very next instruction proves nothing on either edge.
            const uint32_t target = cfg.indexOfLabel(jumpOps[2].valueU64);
            if (proven >= n || target == i + 2 || cfg.predecessors(proven).size() != 1 || cfg.predecessors(proven)[0] != i + 1)
                continue;

            // The test also bounds every value the compared register was copied from.
            MicroSsaState::ReachingDef tested = ssa.reachingDef(cmpOps[0].reg, refs[i]);
            for (uint32_t depth = 0; depth < 8 && tested.valid(); ++depth)
            {
                outTests.push_back({.valueId = tested.valueId, .proven = proven, .bits = bits});
                if (tested.isPhi || !tested.inst || tested.inst->op != MicroInstrOpcode::LoadRegReg)
                    break;
                const MicroInstrOperand* copyOps = tested.inst->ops(operands);
                if (!copyOps || getNumBits(copyOps[2].opBits) < getNumBits(bits) || !copyOps[1].reg.isVirtualInt())
                    break;
                tested = ssa.reachingDef(copyOps[1].reg, tested.instRef);
            }
        }
    }

    // Whether the value `reg` holds when `atRef` reads it cannot be negative at
    // `bits`. Copies are followed back to the value they forward.
    bool isKnownNonNegative(const MicroSsaState& ssa, const MicroPassHelpers::MicroDomTree& dom, std::span<const SignTest> tests, const MicroOperandStorage& operands, MicroReg reg, MicroInstrRef atRef, const uint32_t atIndex, const MicroOpBits bits)
    {
        MicroSsaState::ReachingDef reach = ssa.reachingDef(reg, atRef);
        for (uint32_t depth = 0; depth < 8 && reach.valid(); ++depth)
        {
            for (const SignTest& test : tests)
            {
                if (test.valueId == reach.valueId && test.bits == bits && dom.dominates(test.proven, atIndex))
                    return true;
            }

            if (reach.isPhi || !reach.inst)
                return false;
            const MicroInstrOperand* defOps = reach.inst->ops(operands);
            if (!defOps)
                return false;

            switch (reach.inst->op)
            {
                case MicroInstrOpcode::LoadZeroExtRegReg:
                case MicroInstrOpcode::LoadZeroExtRegMem:
                case MicroInstrOpcode::LoadZeroExtAmcRegMem:
                {
                    // Zero bits from the source width up: the top bit read here is one of them.
                    const bool        indexed = reach.inst->op == MicroInstrOpcode::LoadZeroExtAmcRegMem;
                    const MicroOpBits dstBits = defOps[indexed ? 3 : 2].opBits;
                    const MicroOpBits srcBits = defOps[indexed ? 4 : 3].opBits;
                    return getNumBits(dstBits) >= 32 && getNumBits(srcBits) < getNumBits(bits);
                }

                case MicroInstrOpcode::LoadRegImm:
                    if (defOps[1].opBits == MicroOpBits::B32 && bits == MicroOpBits::B64)
                        return true;
                    return defOps[1].opBits == bits && !defOps[2].hasWideImmediateValue() &&
                           ((defOps[2].valueU64 >> (getNumBits(bits) - 1)) & 1) == 0;

                case MicroInstrOpcode::OpBinaryRegImm:
                    if (defOps[1].opBits != bits || defOps[3].hasWideImmediateValue())
                        return bits == MicroOpBits::B64 && MicroPassHelpers::definesZeroHighBits(*reach.inst, defOps);
                    if (defOps[2].microOp == MicroOp::And)
                        return ((defOps[3].valueU64 >> (getNumBits(bits) - 1)) & 1) == 0;
                    if (defOps[2].microOp == MicroOp::ShiftRight)
                        return defOps[3].valueU64 >= 1 && defOps[3].valueU64 < getNumBits(bits);
                    return false;

                case MicroInstrOpcode::LoadRegReg:
                {
                    // A full-width copy forwards its source unchanged; a
                    // 32-bit one read at 64 bits has a clear upper half.
                    if (getNumBits(defOps[2].opBits) < getNumBits(bits))
                        return defOps[2].opBits == MicroOpBits::B32 && bits == MicroOpBits::B64;
                    if (!defOps[1].reg.isVirtualInt())
                        return false;
                    reach = ssa.reachingDef(defOps[1].reg, reach.instRef);
                    continue;
                }

                default:
                    // A 32-bit result clears the upper half of its register.
                    return bits == MicroOpBits::B64 && MicroPassHelpers::definesZeroHighBits(*reach.inst, defOps);
            }
        }
        return false;
    }

    // Turn every signed division or remainder of a provably non-negative
    // dividend by a positive constant into its unsigned form, before the
    // reductions below look at them. Only the operation changes, so the
    // analyses this reads stay valid for the whole scan.
    bool useUnsignedDivisionWhereProven(MicroPassContext& context, MicroStorage& storage, MicroOperandStorage& operands, MicroSsaState& ssaScratch)
    {
        std::vector<MicroInstrRef> candidates;
        const auto                 view = storage.view();
        for (auto it = view.begin(), endIt = view.end(); it != endIt; ++it)
        {
            if (it->op != MicroInstrOpcode::OpBinaryRegImm)
                continue;
            const MicroInstrOperand* ops = it->ops(operands);
            if (!ops || !ops[0].reg.isVirtualInt() || ops[3].hasWideImmediateValue() ||
                (ops[2].microOp != MicroOp::DivideSigned && ops[2].microOp != MicroOp::ModuloSigned) ||
                (ops[1].opBits != MicroOpBits::B32 && ops[1].opBits != MicroOpBits::B64))
                continue;
            const uint64_t immediate = ops[3].valueU64 & getBitsMask(ops[1].opBits);
            if (immediate != 0 && ((immediate >> (getNumBits(ops[1].opBits) - 1)) & 1) == 0)
                candidates.push_back(it.current);
        }
        if (candidates.empty() || !context.builder)
            return false;

        const MicroSsaState* ssa = MicroSsaState::ensureFor(context, ssaScratch);
        if (!ssa || !ssa->isValid())
            return false;
        const MicroControlFlowGraph& cfg   = context.builder->controlFlowGraph();
        const uint32_t               entry = MicroPassHelpers::findSingleCfgEntry(cfg);
        if (entry == MicroPassHelpers::MicroDomTree::K_INVALID_NODE)
            return false;
        const MicroPassHelpers::MicroDomTree dom = MicroPassHelpers::computeInstructionDominators(cfg, entry);

        std::vector<SignTest> tests;
        collectSignTests(tests, *ssa, cfg, storage, operands);

        bool changed = false;
        for (const MicroInstrRef ref : candidates)
        {
            MicroInstr*        inst = storage.ptr(ref);
            MicroInstrOperand* ops  = inst ? inst->ops(operands) : nullptr;
            if (!ops)
                continue;
            if (!isKnownNonNegative(*ssa, dom, tests, operands, ops[0].reg, ref, cfg.indexOf(ref), ops[1].opBits))
                continue;
            ops[2].microOp = ops[2].microOp == MicroOp::DivideSigned ? MicroOp::DivideUnsigned : MicroOp::ModuloUnsigned;
            changed        = true;
        }
        return changed;
    }

    bool tryExpandDivisionByConstant(MicroPassContext& context, MicroStorage& storage, MicroOperandStorage& operands, MicroInstrRef instRef, MicroInstrOperand* ops, uint32_t& nextVirtualIntRegIndex)
    {
        const MicroOpBits opBits = ops[1].opBits;
        if (opBits != MicroOpBits::B32 && opBits != MicroOpBits::B64)
            return false;

        const uint32_t bits      = getNumBits(opBits);
        const uint64_t bitsMask  = getBitsMask(opBits);
        const MicroOp  microOp   = ops[2].microOp;
        uint64_t       immediate = ops[3].valueU64 & bitsMask;
        const MicroReg dstReg    = ops[0].reg;

        const bool isSigned = microOp == MicroOp::DivideSigned || microOp == MicroOp::ModuloSigned;
        const bool isModulo = microOp == MicroOp::ModuloUnsigned || microOp == MicroOp::ModuloSigned;

        if (immediate == 0)
            return false; // preserve the hardware divide-by-zero behavior

        const bool signBitSet = (immediate >> (bits - 1)) & 1;
        if (isSigned && signBitSet)
        {
            // The divisor's sign does not affect a remainder. Only -2 produces
            // a smaller sequence than IDIV; wider powers of two grow the code.
            // Keeping -1 on IDIV also preserves the INT_MIN % -1 trap.
            const uint64_t magnitude = (~immediate + 1) & bitsMask;
            if (!isModulo || magnitude != 2)
                return false;
            immediate = magnitude;
        }

        // These cases never need a fresh register. Powers of two (and 1) are
        // normally reduced earlier; a masked immediate can still become one
        // when its stored value carried bits above the operand width.
        if (!isSigned && Math::isPowerOfTwo(immediate))
            return false;
        if (isSigned && immediate == 1)
        {
            // n / 1 == n, n % 1 == 0, for any signed n.
            ops[2].microOp  = isModulo ? MicroOp::And : MicroOp::Add;
            ops[3].valueU64 = 0;
            return true;
        }

        if (nextVirtualIntRegIndex == 0)
            nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);

        const DivisionExpansionEmitter emitter{&storage, &operands, instRef, opBits, &nextVirtualIntRegIndex};

        if (!isSigned)
        {
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

        if (isModulo && Math::isPowerOfTwo(immediate))
        {
            emitter.emitSignedModuloPow2(dstReg, Math::integerLog2(immediate));
            storage.erase(instRef);
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
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    MicroStorage&                storage  = *context.instructions;
    MicroOperandStorage&         operands = *context.operands;
    std::optional<MicroSsaState> localSsaState;
    MicroSsaState&               ssaScratch             = context.ssaState ? *context.ssaState : localSsaState.emplace();
    const MicroSsaState*         ssaState               = nullptr;
    uint32_t                     nextVirtualIntRegIndex = 0; // computed lazily on the first expansion

    if (useUnsignedDivisionWhereProven(context, storage, operands, ssaScratch))
        context.passChanged = true;

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

        // Changing signedness is safe only when nobody observes the multiply's flags.
        // Test the operation before scanning the flags: only unsigned multiply
        // has a signed replacement. RegImm keeps the operation in slot 2, RegReg in 3.
        const bool usedSignedMultiply = tryUseSignedMultiply(context, instRef, ops, isRegImm ? 2 : 3);
        if (usedSignedMultiply)
            context.passChanged = true;

        if (!isRegImm)
            continue;

        const MicroOpBits opBits    = ops[1].opBits;
        const MicroOp     microOp   = ops[2].microOp;
        const uint64_t    immediate = ops[3].valueU64;
        bool              changed   = false;
        switch (microOp)
        {
            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
                if (immediate > 1 && !canRewriteShift(opBits, immediate))
                    break;
                // A successful signed rewrite already proved the flags dead
                // in this unchanged suffix, including across CFG edges.
                if (!usedSignedMultiply && !MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, instRef, context.builder))
                    break;
                changed = tryReduceMultiplyByZero(ops, immediate) ||
                          tryReduceMultiplyByOne(ops, immediate) ||
                          tryReduceMultiplyToShift(ops, opBits, immediate);
                break;

            case MicroOp::Add:
            case MicroOp::Subtract:
                if (immediate == 0)
                {
                    if (!MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, instRef, context.builder))
                        break;
                    if (!ssaState)
                        ssaState = MicroSsaState::ensureFor(context, ssaScratch);
                    if (ssaState && ssaState->isValid() && !ssaState->isRegUsedAfter(ops[0].reg, instRef))
                        changed = storage.erase(instRef);
                }
                break;

            case MicroOp::DivideUnsigned:
                if (!MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, instRef, context.builder))
                    break;
                changed = tryReduceUnsignedDivideToShift(ops, opBits, immediate) ||
                          tryExpandDivisionByConstant(context, storage, operands, instRef, ops, nextVirtualIntRegIndex);
                break;

            case MicroOp::ModuloUnsigned:
                if (!MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, instRef, context.builder))
                    break;
                if (tryReduceUnsignedModuloToMask(ops, opBits, immediate))
                {
                    changed = true;
                    break;
                }
                changed = tryReduceUnsignedModuloEquality(context, storage, operands, ssaState, ssaScratch, instRef, ops, nextVirtualIntRegIndex) ||
                          tryExpandDivisionByConstant(context, storage, operands, instRef, ops, nextVirtualIntRegIndex);
                break;

            case MicroOp::DivideSigned:
            case MicroOp::ModuloSigned:
                if (microOp == MicroOp::ModuloSigned && MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, instRef, context.builder) &&
                    tryReduceSignedModuloPow2Equality(context, storage, operands, ssaState, ssaScratch, instRef, ops))
                {
                    changed = true;
                    break;
                }
                if (deferSignedDivision_)
                    break;
                if (!MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, instRef, context.builder))
                    break;
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
