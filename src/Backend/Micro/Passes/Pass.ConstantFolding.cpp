#include "pch.h"
#include "Backend/Micro/Passes/Pass.ConstantFolding.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/Passes/Pass.SsaValuePropagation.Internal.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Main/TaskContext.h"
#include "Support/Report/Assert.h"

// Pre-RA constant folding driven by SSA reaching definitions.
//
// Computes a per-value "known constant" lattice as a fixed-point over the SSA
// graph, then rewrites instructions whose inputs are known. Phi joins are
// folded only when every incoming value resolves to the same constant.
//
// Patterns folded:
//   LoadRegImm / ClearReg                : seed values.
//   LoadRegReg with known src            : rewritten to LoadRegImm.
//   OpBinaryRegImm with known lhs        : evaluated, rewritten to LoadRegImm.
//   OpBinaryRegReg with known lhs+rhs    : evaluated, rewritten to LoadRegImm.
//   LoadSignedExt/ZeroExtRegReg of const : extended, rewritten to LoadRegImm.
//   cvtf2f of a constant source (reached
//     through a GP->XMM bitcast)         : bit-pattern converted, rewritten
//                                          to LoadRegImm on the float dest
//                                          (Legalize lowers float-imm load).
//   Load from a constant's address       : the bytes exist at compile time;
//                                          rewritten to LoadRegImm (LLVM's
//                                          ConstantFoldLoadFromConstPtr).
//   Float add/sub/mul/div/sqrt of known
//     operands                           : evaluated in IEEE-754 to the
//                                          LoadRegImm the float dest takes.
//   Float identities (x-0, x*1, x*2...)  : the op is erased, or becomes the
//                                          copy or the `x+x` it stands for.
//
// The propagation step never mutates the IR, so the fixed point is stable.
// Rewrite is a single linear pass; the outer pass-manager loop handles
// re-running and re-building SSA after a change.

SWC_BEGIN_NAMESPACE();

namespace
{
    struct KnownValue
    {
        uint64_t    value  = 0;
        MicroOpBits opBits = MicroOpBits::B64;
    };

    bool isFloatArithmeticOp(const MicroOp op)
    {
        switch (op)
        {
            case MicroOp::FloatAdd:
            case MicroOp::FloatSubtract:
            case MicroOp::FloatMultiply:
            case MicroOp::FloatDivide:
                return true;
            default:
                return false;
        }
    }

    bool isScalarFloatBits(const MicroOpBits opBits)
    {
        return opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64;
    }

    // IEEE-754 bit patterns of the identity constants, per width.
    uint64_t floatBitsOfOne(const MicroOpBits opBits)
    {
        return opBits == MicroOpBits::B64 ? 0x3FF0000000000000ull : 0x3F800000ull;
    }

    uint64_t floatBitsOfTwo(const MicroOpBits opBits)
    {
        return opBits == MicroOpBits::B64 ? 0x4000000000000000ull : 0x40000000ull;
    }

    uint64_t floatBitsOfNegativeZero(const MicroOpBits opBits)
    {
        return opBits == MicroOpBits::B64 ? 0x8000000000000000ull : 0x80000000ull;
    }

    // Both operands and the result are the low `opBits` of the pattern. A single
    // operation evaluated here rounds exactly as the emitted scalar instruction
    // does: one IEEE-754 operation, round to nearest even, no contraction.
    template<typename T>
    bool evaluateFloatArithmetic(T& outResult, const MicroOp op, const T lhs, const T rhs)
    {
        switch (op)
        {
            case MicroOp::FloatAdd:
                outResult = lhs + rhs;
                return true;
            case MicroOp::FloatSubtract:
                outResult = lhs - rhs;
                return true;
            case MicroOp::FloatMultiply:
                outResult = lhs * rhs;
                return true;
            case MicroOp::FloatDivide:
                outResult = lhs / rhs;
                return true;
            case MicroOp::FloatSqrt:
                outResult = std::sqrt(rhs);
                return true;
            default:
                return false;
        }
    }

    bool evaluateFloatBits(uint64_t& outBits, const MicroOp op, const uint64_t lhsBits, const uint64_t rhsBits, const MicroOpBits opBits)
    {
        if (opBits == MicroOpBits::B64)
        {
            double lhs = 0.0;
            double rhs = 0.0;
            std::memcpy(&lhs, &lhsBits, sizeof(lhs));
            std::memcpy(&rhs, &rhsBits, sizeof(rhs));
            double result = 0.0;
            if (!evaluateFloatArithmetic(result, op, lhs, rhs))
                return false;
            std::memcpy(&outBits, &result, sizeof(result));
            return true;
        }

        if (opBits == MicroOpBits::B32)
        {
            const auto lhsLow = static_cast<uint32_t>(lhsBits);
            const auto rhsLow = static_cast<uint32_t>(rhsBits);
            float      lhs    = 0.0f;
            float      rhs    = 0.0f;
            std::memcpy(&lhs, &lhsLow, sizeof(lhs));
            std::memcpy(&rhs, &rhsLow, sizeof(rhs));
            float result = 0.0f;
            if (!evaluateFloatArithmetic(result, op, lhs, rhs))
                return false;
            uint32_t resultBits = 0;
            std::memcpy(&resultBits, &result, sizeof(result));
            outBits = resultBits;
            return true;
        }

        return false;
    }

    // Loads through the address of a constant. The relocation of a
    // LoadRegPtrReloc carries the address the JIT itself patches in, so the
    // bytes behind it are readable now; the read is bounded to the allocation
    // that owns the address and refused where the payload carries relocations
    // (a pointer field's compile-time bytes are not its runtime value). The
    // address flows through the few pure forms the sweep leaves between the
    // materialization and the load: copies, `lea [base + K]`, `add/sub K`.
    struct ConstantMemoryContext
    {
        const MicroSsaState*                   ssaState    = nullptr;
        const MicroStorage*                    storage     = nullptr;
        const MicroOperandStorage*             operands    = nullptr;
        const TaskContext*                     taskContext = nullptr;
        std::unordered_map<uint32_t, uint64_t> constantAddressByInstruction;
    };

    constexpr uint32_t K_MAX_ADDRESS_CHAIN_DEPTH = 8;

    bool resolveConstantAddress(uint64_t& outAddress, const ConstantMemoryContext& context, const MicroReg reg, const MicroInstrRef atInstRef, const uint32_t depth)
    {
        if (!depth || !reg.isVirtualInt())
            return false;

        const MicroSsaState::ReachingDef def = context.ssaState->reachingDef(reg, atInstRef);
        if (!def.valid() || def.isPhi || !def.instRef.isValid())
            return false;

        const MicroInstr* inst = context.storage->ptr(def.instRef);
        if (!inst)
            return false;
        const MicroInstrOperand* ops = inst->ops(*context.operands);
        if (!ops || ops[0].reg != reg)
            return false;

        switch (inst->op)
        {
            case MicroInstrOpcode::LoadRegPtrReloc:
            {
                const auto found = context.constantAddressByInstruction.find(def.instRef.get());
                if (found == context.constantAddressByInstruction.end())
                    return false;
                outAddress = found->second;
                return true;
            }

            case MicroInstrOpcode::LoadRegReg:
                if (ops[2].opBits != MicroOpBits::B64)
                    return false;
                return resolveConstantAddress(outAddress, context, ops[1].reg, def.instRef, depth - 1);

            case MicroInstrOpcode::LoadAddrRegMem:
            {
                if (ops[2].opBits != MicroOpBits::B64)
                    return false;
                uint64_t base = 0;
                if (!resolveConstantAddress(base, context, ops[1].reg, def.instRef, depth - 1))
                    return false;
                outAddress = base + ops[3].valueU64;
                return true;
            }

            case MicroInstrOpcode::OpBinaryRegImm:
            {
                if (ops[1].opBits != MicroOpBits::B64 || (ops[2].microOp != MicroOp::Add && ops[2].microOp != MicroOp::Subtract))
                    return false;
                uint64_t base = 0;
                if (!resolveConstantAddress(base, context, reg, def.instRef, depth - 1))
                    return false;
                outAddress = ops[2].microOp == MicroOp::Add ? base + ops[3].valueU64 : base - ops[3].valueU64;
                return true;
            }

            default:
                return false;
        }
    }

    bool readConstantBytes(uint64_t& outBits, const TaskContext& taskContext, const uint64_t address, const uint32_t byteWidth)
    {
        SWC_ASSERT(byteWidth >= 1 && byteWidth <= sizeof(uint64_t));
        const ConstantManager& cstMgr = taskContext.cstMgr();
        const void*            ptr    = reinterpret_cast<const void*>(address);

        DataSegmentRef segmentRef;
        if (!cstMgr.resolveDataSegmentRef(segmentRef, ptr))
            return false;

        const DataSegment&    segment = cstMgr.shardDataSegment(segmentRef.shardIndex);
        DataSegmentAllocation allocation;
        if (!segment.findAllocation(allocation, segmentRef.offset))
            return false;
        if (segmentRef.offset + byteWidth > allocation.offset + allocation.size)
            return false;
        if (segment.hasRelocations(segmentRef.offset, byteWidth))
            return false;

        uint64_t bits = 0;
        std::memcpy(&bits, ptr, byteWidth);
        outBits = bits;
        return true;
    }

    void collectConstantAddresses(ConstantMemoryContext& context, const MicroBuilder& builder)
    {
        for (const MicroRelocation& relocation : builder.codeRelocations())
        {
            if (relocation.kind != MicroRelocation::Kind::ConstantAddress || relocation.form != MicroRelocation::Form::Absolute64)
                continue;
            if (!relocation.instructionRef.isValid() || !relocation.targetAddress)
                continue;
            context.constantAddressByInstruction[relocation.instructionRef.get()] = relocation.targetAddress;
        }
    }

    struct KnownValueTraits
    {
        [[maybe_unused]] static bool isValid(const KnownValue&)
        {
            return true;
        }

        [[maybe_unused]] static bool same(const KnownValue& lhs, const KnownValue& rhs)
        {
            return lhs.value == rhs.value && lhs.opBits == rhs.opBits;
        }
    };

    struct KnownValueContext
    {
        const MicroSsaState*       ssaState = nullptr;
        const MicroStorage*        storage  = nullptr;
        const MicroOperandStorage* operands = nullptr;
    };

    bool tryGetKnownReachingValue(KnownValue& outValue, const KnownValueContext& context, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, MicroReg reg, MicroInstrRef instRef)
    {
        SWC_ASSERT(context.ssaState != nullptr);
        return tryGetSsaReachingValue<KnownValue, KnownValueTraits>(outValue, *context.ssaState, knownValues, knownFlags, reg, instRef);
    }

    bool tryGetKnownReachingValue(KnownValue& outValue, const MicroSsaState& ssaState, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, MicroReg reg, MicroInstrRef instRef)
    {
        return tryGetSsaReachingValue<KnownValue, KnownValueTraits>(outValue, ssaState, knownValues, knownFlags, reg, instRef);
    }

    uint64_t extendBits(uint64_t value, MicroOpBits srcBits, MicroOpBits dstBits, bool isSigned)
    {
        const uint64_t srcMask = getBitsMask(srcBits);
        uint64_t       masked  = value & srcMask;
        if (isSigned)
        {
            const uint32_t srcBitsNum = getNumBits(srcBits);
            const uint64_t signBit    = 1ULL << (srcBitsNum - 1);
            if (masked & signBit)
                masked |= ~srcMask;
        }
        return masked & getBitsMask(dstBits);
    }

    // Convert an IEEE-754 bit pattern between f32/f64. On success fills the
    // destination bit pattern and its width; returns false for unsupported
    // source widths.
    bool convertFloatBitPattern(uint64_t& outBits, MicroOpBits& outDstBits, uint64_t value, MicroOpBits srcBits)
    {
        if (srcBits == MicroOpBits::B64)
        {
            double asDouble = 0.0;
            std::memcpy(&asDouble, &value, sizeof(asDouble));
            const auto asFloat = static_cast<float>(asDouble);
            uint32_t   bits    = 0;
            std::memcpy(&bits, &asFloat, sizeof(bits));
            outBits    = bits;
            outDstBits = MicroOpBits::B32;
            return true;
        }
        if (srcBits == MicroOpBits::B32)
        {
            const auto lo      = static_cast<uint32_t>(value);
            float      asFloat = 0.0f;
            std::memcpy(&asFloat, &lo, sizeof(asFloat));
            const auto asDouble = static_cast<double>(asFloat);
            uint64_t   bits     = 0;
            std::memcpy(&bits, &asDouble, sizeof(bits));
            outBits    = bits;
            outDstBits = MicroOpBits::B64;
            return true;
        }
        return false;
    }

    bool tryInferInstructionConstant(KnownValue& outValue, const KnownValueContext& context, const uint32_t, const MicroSsaState::ValueInfo& valueInfo, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags)
    {
        if (!valueInfo.instRef.isValid())
            return false;

        SWC_ASSERT(context.storage != nullptr);
        SWC_ASSERT(context.operands != nullptr);

        const MicroInstr* inst = context.storage->ptr(valueInfo.instRef);
        if (!inst)
            return false;
        const MicroInstrOperand* ops = inst->ops(*context.operands);
        if (!ops)
            return false;

        switch (inst->op)
        {
            case MicroInstrOpcode::LoadRegImm:
                // Pre-legalize, LoadRegImm can target a float reg directly;
                // we still track the bit pattern so cvtf2f folding can see it.
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtual())
                    return false;
                outValue.value  = ops[2].valueU64;
                outValue.opBits = ops[1].opBits;
                return true;

            case MicroInstrOpcode::ClearReg:
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtual())
                    return false;
                outValue.value  = 0;
                outValue.opBits = ops[1].opBits;
                return true;

            case MicroInstrOpcode::LoadRegReg:
            {
                // A reg->reg move (including GP<->XMM) preserves the low
                // `opBits` bits of the source. Narrower moves yield a narrower
                // known value; the lattice records the carried width so later
                // uses (extends, cvtf2f) can reason about it precisely.
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtual())
                    return false;

                KnownValue src;
                if (!tryGetKnownReachingValue(src, context, knownValues, knownFlags, ops[1].reg, valueInfo.instRef))
                    return false;

                const MicroOpBits moveBits = ops[2].opBits;
                outValue.value             = src.value & getBitsMask(moveBits);
                outValue.opBits            = moveBits;
                return true;
            }

            case MicroInstrOpcode::OpBinaryRegImm:
            {
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
                    return false;

                KnownValue inputValue;
                if (!tryGetKnownReachingValue(inputValue, context, knownValues, knownFlags, ops[0].reg, valueInfo.instRef))
                    return false;

                uint64_t   foldedValue = 0;
                const auto status      = MicroPassHelpers::foldBinaryImmediate(foldedValue, inputValue.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits);
                if (status != Math::FoldStatus::Ok)
                    return false;

                outValue.value  = foldedValue;
                outValue.opBits = ops[1].opBits;
                return true;
            }

            case MicroInstrOpcode::OpBinaryRegReg:
            {
                if (ops[0].reg != valueInfo.reg)
                    return false;

                // cvtf2f: both operands are float virtual regs. If the source's
                // bit pattern is already known, fold the IEEE-754 conversion.
                if (ops[3].microOp == MicroOp::ConvertFloatToFloat && valueInfo.reg.isVirtualFloat())
                {
                    KnownValue srcValue;
                    if (!tryGetKnownReachingValue(srcValue, context, knownValues, knownFlags, ops[1].reg, valueInfo.instRef))
                        return false;

                    const MicroOpBits srcBits = ops[2].opBits;
                    if (srcValue.opBits != srcBits)
                        return false;

                    uint64_t converted = 0;
                    auto     dstBits   = MicroOpBits::Zero;
                    if (!convertFloatBitPattern(converted, dstBits, srcValue.value, srcBits))
                        return false;

                    outValue.value  = converted;
                    outValue.opBits = dstBits;
                    return true;
                }

                // Scalar float arithmetic of known operands. The square root
                // reads its source only; the two-address forms read the
                // destination's reaching value as their left operand.
                if (valueInfo.reg.isVirtualFloat())
                {
                    const MicroOp     op     = ops[3].microOp;
                    const MicroOpBits opBits = ops[2].opBits;
                    if ((!isFloatArithmeticOp(op) && op != MicroOp::FloatSqrt) || !isScalarFloatBits(opBits) || !ops[1].reg.isVirtualFloat())
                        return false;

                    KnownValue rhs;
                    if (!tryGetKnownReachingValue(rhs, context, knownValues, knownFlags, ops[1].reg, valueInfo.instRef) || rhs.opBits != opBits)
                        return false;
                    KnownValue lhs;
                    if (op != MicroOp::FloatSqrt && (!tryGetKnownReachingValue(lhs, context, knownValues, knownFlags, ops[0].reg, valueInfo.instRef) || lhs.opBits != opBits))
                        return false;

                    uint64_t folded = 0;
                    if (!evaluateFloatBits(folded, op, lhs.value, rhs.value, opBits))
                        return false;
                    outValue.value  = folded;
                    outValue.opBits = opBits;
                    return true;
                }

                if (!valueInfo.reg.isVirtualInt())
                    return false;

                KnownValue lhs;
                KnownValue rhs;
                if (!tryGetKnownReachingValue(lhs, context, knownValues, knownFlags, ops[0].reg, valueInfo.instRef))
                    return false;
                if (!tryGetKnownReachingValue(rhs, context, knownValues, knownFlags, ops[1].reg, valueInfo.instRef))
                    return false;

                uint64_t   foldedValue = 0;
                const auto status      = MicroPassHelpers::foldBinaryImmediate(foldedValue, lhs.value, rhs.value, ops[3].microOp, ops[2].opBits);
                if (status != Math::FoldStatus::Ok)
                    return false;

                outValue.value  = foldedValue;
                outValue.opBits = ops[2].opBits;
                return true;
            }

            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            {
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
                    return false;

                KnownValue src;
                if (!tryGetKnownReachingValue(src, context, knownValues, knownFlags, ops[1].reg, valueInfo.instRef))
                    return false;

                const bool isSigned = inst->op == MicroInstrOpcode::LoadSignedExtRegReg;
                outValue.value      = extendBits(src.value, ops[3].opBits, ops[2].opBits, isSigned);
                outValue.opBits     = ops[2].opBits;
                return true;
            }

            default:
                return false;
        }
    }

    void computeKnownValues(std::vector<KnownValue>& knownValues, std::vector<uint8_t>& knownFlags, const MicroSsaState& ssaState, const MicroStorage& storage, const MicroOperandStorage& operands)
    {
        const KnownValueContext context{&ssaState, &storage, &operands};
        computeSsaValueFixedPoint<KnownValue, KnownValueTraits>(knownValues, knownFlags, ssaState, context, tryInferInstructionConstant);
    }

    bool tryFoldCopyFromKnown(const MicroSsaState& ssaState, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::LoadRegReg)
            return false;
        if (!ops)
            return false;
        if (!ops[0].reg.isVirtualInt() || !ops[1].reg.isVirtualInt())
            return false;
        if (ops[2].opBits != MicroOpBits::B64)
            return false;

        KnownValue sourceValue;
        if (!tryGetKnownReachingValue(sourceValue, ssaState, knownValues, knownFlags, ops[1].reg, instRef))
            return false;

        inst.op          = MicroInstrOpcode::LoadRegImm;
        ops[1].opBits    = sourceValue.opBits;
        ops[2].valueU64  = sourceValue.value;
        inst.numOperands = 3;
        return true;
    }

    bool tryFoldBinaryRegImm(const MicroSsaState& ssaState, const MicroStorage& storage, const MicroOperandStorage& operands, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
            return false;
        if (!ops)
            return false;
        if (!ops[0].reg.isVirtualInt())
            return false;
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, instRef))
            return false;

        KnownValue inputValue;
        if (!tryGetKnownReachingValue(inputValue, ssaState, knownValues, knownFlags, ops[0].reg, instRef))
            return false;

        uint64_t   foldedValue = 0;
        const auto status      = MicroPassHelpers::foldBinaryImmediate(foldedValue, inputValue.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits);
        if (status != Math::FoldStatus::Ok)
            return false;

        inst.op          = MicroInstrOpcode::LoadRegImm;
        ops[2].valueU64  = foldedValue;
        inst.numOperands = 3;
        return true;
    }

    bool tryFoldBinaryRegReg(const MicroSsaState& ssaState, const MicroStorage& storage, const MicroOperandStorage& operands, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        if (!ops)
            return false;
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, instRef))
            return false;

        // cvtf2f(const) path.
        if (ops[3].microOp == MicroOp::ConvertFloatToFloat && ops[0].reg.isVirtualFloat())
        {
            KnownValue srcValue;
            if (!tryGetKnownReachingValue(srcValue, ssaState, knownValues, knownFlags, ops[1].reg, instRef))
                return false;

            const MicroOpBits srcBits = ops[2].opBits;
            if (srcValue.opBits != srcBits)
                return false;

            uint64_t converted = 0;
            auto     dstBits   = MicroOpBits::Zero;
            if (!convertFloatBitPattern(converted, dstBits, srcValue.value, srcBits))
                return false;

            // Rewrite to LoadRegImm [dst_float, dstBits, converted].
            // Legalize will lower the float-immediate load on targets that
            // can't encode it directly.
            inst.op          = MicroInstrOpcode::LoadRegImm;
            ops[1].opBits    = dstBits;
            ops[2].valueU64  = converted;
            inst.numOperands = 3;
            return true;
        }

        if (!ops[0].reg.isVirtualInt() || !ops[1].reg.isVirtualInt())
            return false;

        KnownValue lhs;
        KnownValue rhs;
        if (!tryGetKnownReachingValue(lhs, ssaState, knownValues, knownFlags, ops[0].reg, instRef))
            return false;
        if (!tryGetKnownReachingValue(rhs, ssaState, knownValues, knownFlags, ops[1].reg, instRef))
            return false;

        uint64_t   foldedValue = 0;
        const auto status      = MicroPassHelpers::foldBinaryImmediate(foldedValue, lhs.value, rhs.value, ops[3].microOp, ops[2].opBits);
        if (status != Math::FoldStatus::Ok)
            return false;

        inst.op          = MicroInstrOpcode::LoadRegImm;
        ops[1].opBits    = ops[2].opBits;
        ops[2].valueU64  = foldedValue;
        inst.numOperands = 3;
        return true;
    }

    bool tryFoldExtend(const MicroSsaState& ssaState, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::LoadSignedExtRegReg && inst.op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        if (!ops)
            return false;
        if (!ops[0].reg.isVirtualInt() || !ops[1].reg.isVirtualInt())
            return false;

        KnownValue src;
        if (!tryGetKnownReachingValue(src, ssaState, knownValues, knownFlags, ops[1].reg, instRef))
            return false;

        const bool        isSigned = inst.op == MicroInstrOpcode::LoadSignedExtRegReg;
        const MicroOpBits dstBits  = ops[2].opBits;
        const MicroOpBits srcBits  = ops[3].opBits;
        const uint64_t    extended = extendBits(src.value, srcBits, dstBits, isSigned);

        inst.op          = MicroInstrOpcode::LoadRegImm;
        ops[1].opBits    = dstBits;
        ops[2].valueU64  = extended;
        inst.numOperands = 3;
        return true;
    }

    // A load whose base register holds the address of a constant, at a
    // displacement the sweep has already made literal, is the constant's own
    // bytes. Plain, sign-extending and zero-extending loads all become the
    // immediate they would have produced; a packed load is left alone.
    bool tryFoldLoadFromConstant(const ConstantMemoryContext& context, MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops)
    {
        if (!ops || !context.taskContext)
            return false;

        MicroOpBits dstBits    = MicroOpBits::Zero;
        MicroOpBits loadBits   = MicroOpBits::Zero;
        uint64_t    offset     = 0;
        bool        signExtend = false;
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegMem:
                dstBits  = ops[2].opBits;
                loadBits = dstBits;
                offset   = ops[3].valueU64;
                break;
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
                dstBits    = ops[2].opBits;
                loadBits   = ops[3].opBits;
                offset     = ops[4].valueU64;
                signExtend = inst.op == MicroInstrOpcode::LoadSignedExtRegMem;
                break;
            default:
                return false;
        }

        if (!ops[0].reg.isVirtual() || loadBits == MicroOpBits::Zero || loadBits == MicroOpBits::B128 || dstBits == MicroOpBits::B128)
            return false;

        uint64_t baseAddress = 0;
        if (!resolveConstantAddress(baseAddress, context, ops[1].reg, instRef, K_MAX_ADDRESS_CHAIN_DEPTH))
            return false;

        uint64_t bits = 0;
        if (!readConstantBytes(bits, *context.taskContext, baseAddress + offset, getNumBits(loadBits) / 8))
            return false;

        inst.op          = MicroInstrOpcode::LoadRegImm;
        ops[1].opBits    = dstBits;
        ops[2].valueU64  = extendBits(bits, loadBits, dstBits, signExtend);
        inst.numOperands = 3;
        return true;
    }

    struct FloatFoldContext
    {
        const MicroSsaState*           ssaState     = nullptr;
        MicroStorage*                  storage      = nullptr;
        MicroOperandStorage*           operands     = nullptr;
        const std::vector<KnownValue>* knownValues  = nullptr;
        const std::vector<uint8_t>*    knownFlags   = nullptr;
        bool                           noSignedZero = false;
    };

    // The exact identities: `x - (+0)`, `x + (-0)`, `x * 1`, `x / 1` return x
    // for every x, sign of zero and NaN included. Adding +0 or subtracting -0
    // turns -0 into +0, so those two only hold once the build gives up signed
    // zeros - the same gate LLVM's `nsz` puts on them.
    bool isRightIdentity(const MicroOp op, const uint64_t rhsBits, const MicroOpBits opBits, const bool noSignedZero)
    {
        const uint64_t negativeZero = floatBitsOfNegativeZero(opBits);
        switch (op)
        {
            case MicroOp::FloatAdd:
                return rhsBits == negativeZero || (noSignedZero && rhsBits == 0);
            case MicroOp::FloatSubtract:
                return rhsBits == 0 || (noSignedZero && rhsBits == negativeZero);
            case MicroOp::FloatMultiply:
            case MicroOp::FloatDivide:
                return rhsBits == floatBitsOfOne(opBits);
            default:
                return false;
        }
    }

    bool isLeftIdentity(const MicroOp op, const uint64_t lhsBits, const MicroOpBits opBits, const bool noSignedZero)
    {
        switch (op)
        {
            case MicroOp::FloatAdd:
                return lhsBits == floatBitsOfNegativeZero(opBits) || (noSignedZero && lhsBits == 0);
            case MicroOp::FloatMultiply:
                return lhsBits == floatBitsOfOne(opBits);
            default:
                return false;
        }
    }

    // Two-address scalar float arithmetic with a known operand. Both known:
    // evaluated. A known right operand that is the identity: the op goes
    // (queued, since the walk is on). A known left identity: the op is the
    // copy of its right operand. `2 * x` either way is `x + x`, which is exact
    // and needs no constant register - the form clang emits (`addsd x, x`).
    bool tryFoldFloatBinaryRegReg(const FloatFoldContext& context, std::vector<MicroInstrRef>& outErase, MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegReg || !ops)
            return false;
        if (!ops[0].reg.isVirtualFloat() || !ops[1].reg.isVirtualFloat())
            return false;

        const MicroOp     op     = ops[3].microOp;
        const MicroOpBits opBits = ops[2].opBits;
        if (!isFloatArithmeticOp(op) || !isScalarFloatBits(opBits))
            return false;

        KnownValue rhs;
        KnownValue lhs;
        const bool rhsKnown = tryGetKnownReachingValue(rhs, *context.ssaState, *context.knownValues, *context.knownFlags, ops[1].reg, instRef) && rhs.opBits == opBits;
        const bool lhsKnown = tryGetKnownReachingValue(lhs, *context.ssaState, *context.knownValues, *context.knownFlags, ops[0].reg, instRef) && lhs.opBits == opBits;

        if (lhsKnown && rhsKnown)
        {
            uint64_t folded = 0;
            if (!evaluateFloatBits(folded, op, lhs.value, rhs.value, opBits))
                return false;
            inst.op          = MicroInstrOpcode::LoadRegImm;
            ops[1].opBits    = opBits;
            ops[2].valueU64  = folded;
            inst.numOperands = 3;
            return true;
        }

        if (rhsKnown)
        {
            if (isRightIdentity(op, rhs.value, opBits, context.noSignedZero))
            {
                outErase.push_back(instRef);
                return true;
            }
            if (op == MicroOp::FloatMultiply && rhs.value == floatBitsOfTwo(opBits))
            {
                ops[1].reg     = ops[0].reg;
                ops[3].microOp = MicroOp::FloatAdd;
                return true;
            }
            return false;
        }

        if (lhsKnown)
        {
            if (isLeftIdentity(op, lhs.value, opBits, context.noSignedZero))
            {
                inst.op          = MicroInstrOpcode::LoadRegReg;
                inst.numOperands = 3;
                return true;
            }
            if (op == MicroOp::FloatMultiply && lhs.value == floatBitsOfTwo(opBits))
            {
                MicroInstrOperand copyOps[3];
                copyOps[0].reg    = ops[0].reg;
                copyOps[1].reg    = ops[1].reg;
                copyOps[2].opBits = opBits;
                context.storage->insertDerivedBefore(*context.operands, instRef, MicroInstrOpcode::LoadRegReg, copyOps);
                ops[1].reg     = ops[0].reg;
                ops[3].microOp = MicroOp::FloatAdd;
                return true;
            }
        }

        return false;
    }
}

Result MicroConstantFoldingPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;
    MicroSsaState        localSsaState;
    const MicroSsaState* ssaState = MicroSsaState::ensureFor(context, localSsaState);
    if (!ssaState || !ssaState->isValid())
        return Result::Continue;

    std::vector<KnownValue> knownValues;
    std::vector<uint8_t>    knownFlags;
    computeKnownValues(knownValues, knownFlags, *ssaState, storage, operands);

    ConstantMemoryContext memoryContext;
    memoryContext.ssaState = ssaState;
    memoryContext.storage  = &storage;
    memoryContext.operands = &operands;
    if (context.builder && context.taskContext && context.taskContext->hasCompiler())
    {
        memoryContext.taskContext = context.taskContext;
        collectConstantAddresses(memoryContext, *context.builder);
    }

    FloatFoldContext floatContext;
    floatContext.ssaState     = ssaState;
    floatContext.storage      = &storage;
    floatContext.operands     = &operands;
    floatContext.knownValues  = &knownValues;
    floatContext.knownFlags   = &knownFlags;
    floatContext.noSignedZero = context.builder && context.builder->backendBuildCfg().fpMathNoSignedZero;

    std::vector<MicroInstrRef> toErase;
    const auto                 view  = storage.view();
    const auto                 endIt = view.end();
    for (auto it = view.begin(); it != endIt; ++it)
    {
        const MicroInstrRef instRef = it.current;
        MicroInstr&         inst    = *it;
        MicroInstrOperand*  ops     = inst.ops(operands);

        const bool changed = tryFoldCopyFromKnown(*ssaState, knownValues, knownFlags, instRef, inst, ops) ||
                             tryFoldBinaryRegImm(*ssaState, storage, operands, knownValues, knownFlags, instRef, inst, ops) ||
                             tryFoldBinaryRegReg(*ssaState, storage, operands, knownValues, knownFlags, instRef, inst, ops) ||
                             tryFoldExtend(*ssaState, knownValues, knownFlags, instRef, inst, ops) ||
                             tryFoldLoadFromConstant(memoryContext, instRef, inst, ops) ||
                             tryFoldFloatBinaryRegReg(floatContext, toErase, instRef, inst, ops);
        if (changed)
            context.passChanged = true;
    }

    for (const MicroInstrRef instRef : toErase)
        storage.erase(instRef);

    return Result::Continue;
}

SWC_END_NAMESPACE();
