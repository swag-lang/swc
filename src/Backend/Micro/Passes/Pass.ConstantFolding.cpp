#include "pch.h"
#include "Backend/Micro/Passes/Pass.ConstantFolding.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Memory/MemoryProfile.h"

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

    bool tryGetKnownValue(KnownValue&                    out,
                          const std::vector<KnownValue>& knownValues,
                          const std::vector<uint8_t>&    knownFlags,
                          uint32_t                       valueId)
    {
        if (valueId >= knownFlags.size() || !knownFlags[valueId])
            return false;
        out = knownValues[valueId];
        return true;
    }

    bool sameKnownValue(const KnownValue& lhs, const KnownValue& rhs)
    {
        return lhs.value == rhs.value && lhs.opBits == rhs.opBits;
    }

    bool tryGetKnownReachingValue(KnownValue&                    out,
                                  const MicroSsaState&           ssaState,
                                  const std::vector<KnownValue>& knownValues,
                                  const std::vector<uint8_t>&    knownFlags,
                                  MicroReg                       reg,
                                  MicroInstrRef                  instRef)
    {
        const auto reaching = ssaState.reachingDef(reg, instRef);
        if (!reaching.valid())
            return false;
        return tryGetKnownValue(out, knownValues, knownFlags, reaching.valueId);
    }

    bool tryInferPhiConstant(KnownValue&                    out,
                             const MicroSsaState::PhiInfo&  phiInfo,
                             const std::vector<KnownValue>& knownValues,
                             const std::vector<uint8_t>&    knownFlags)
    {
        bool       hasCandidate = false;
        KnownValue candidate;

        for (const uint32_t incomingValueId : phiInfo.incomingValueIds)
        {
            KnownValue incomingValue;
            if (!tryGetKnownValue(incomingValue, knownValues, knownFlags, incomingValueId))
                return false;
            if (!hasCandidate)
            {
                candidate    = incomingValue;
                hasCandidate = true;
                continue;
            }
            if (!sameKnownValue(candidate, incomingValue))
                return false;
        }

        if (!hasCandidate)
            return false;
        out = candidate;
        return true;
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
    bool convertFloatBitPattern(uint64_t&    outBits,
                                MicroOpBits& outDstBits,
                                uint64_t     value,
                                MicroOpBits  srcBits)
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

    bool tryInferInstructionConstant(KnownValue&                     out,
                                     const MicroSsaState&            ssaState,
                                     const MicroStorage&             storage,
                                     const MicroOperandStorage&      operands,
                                     const std::vector<KnownValue>&  knownValues,
                                     const std::vector<uint8_t>&     knownFlags,
                                     const MicroSsaState::ValueInfo& valueInfo)
    {
        if (!valueInfo.instRef.isValid())
            return false;

        const MicroInstr* inst = storage.ptr(valueInfo.instRef);
        if (!inst)
            return false;
        const MicroInstrOperand* ops = inst->ops(operands);
        if (!ops)
            return false;

        switch (inst->op)
        {
            case MicroInstrOpcode::LoadRegImm:
                // Pre-legalize, LoadRegImm can target a float reg directly;
                // we still track the bit pattern so cvtf2f folding can see it.
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtual())
                    return false;
                out.value  = ops[2].valueU64;
                out.opBits = ops[1].opBits;
                return true;

            case MicroInstrOpcode::ClearReg:
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtual())
                    return false;
                out.value  = 0;
                out.opBits = ops[1].opBits;
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
                if (!tryGetKnownReachingValue(src, ssaState, knownValues, knownFlags, ops[1].reg, valueInfo.instRef))
                    return false;

                const MicroOpBits moveBits = ops[2].opBits;
                out.value  = src.value & getBitsMask(moveBits);
                out.opBits = moveBits;
                return true;
            }

            case MicroInstrOpcode::OpBinaryRegImm:
            {
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
                    return false;

                KnownValue inputValue;
                if (!tryGetKnownReachingValue(inputValue, ssaState, knownValues, knownFlags, ops[0].reg, valueInfo.instRef))
                    return false;

                uint64_t   foldedValue = 0;
                const auto status      = MicroPassHelpers::foldBinaryImmediate(foldedValue, inputValue.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits);
                if (status != Math::FoldStatus::Ok)
                    return false;

                out.value  = foldedValue;
                out.opBits = ops[1].opBits;
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
                    if (!tryGetKnownReachingValue(srcValue, ssaState, knownValues, knownFlags, ops[1].reg, valueInfo.instRef))
                        return false;

                    const MicroOpBits srcBits = ops[2].opBits;
                    if (srcValue.opBits != srcBits)
                        return false;

                    uint64_t    converted = 0;
                    MicroOpBits dstBits   = MicroOpBits::Zero;
                    if (!convertFloatBitPattern(converted, dstBits, srcValue.value, srcBits))
                        return false;

                    out.value  = converted;
                    out.opBits = dstBits;
                    return true;
                }

                if (!valueInfo.reg.isVirtualInt())
                    return false;

                KnownValue lhs;
                KnownValue rhs;
                if (!tryGetKnownReachingValue(lhs, ssaState, knownValues, knownFlags, ops[0].reg, valueInfo.instRef))
                    return false;
                if (!tryGetKnownReachingValue(rhs, ssaState, knownValues, knownFlags, ops[1].reg, valueInfo.instRef))
                    return false;

                uint64_t   foldedValue = 0;
                const auto status      = MicroPassHelpers::foldBinaryImmediate(foldedValue, lhs.value, rhs.value, ops[3].microOp, ops[2].opBits);
                if (status != Math::FoldStatus::Ok)
                    return false;

                out.value  = foldedValue;
                out.opBits = ops[2].opBits;
                return true;
            }

            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            {
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
                    return false;

                KnownValue src;
                if (!tryGetKnownReachingValue(src, ssaState, knownValues, knownFlags, ops[1].reg, valueInfo.instRef))
                    return false;

                const bool isSigned = inst->op == MicroInstrOpcode::LoadSignedExtRegReg;
                out.value  = extendBits(src.value, ops[3].opBits, ops[2].opBits, isSigned);
                out.opBits = ops[2].opBits;
                return true;
            }

            default:
                return false;
        }
    }

    void computeKnownValues(std::vector<KnownValue>&   knownValues,
                            std::vector<uint8_t>&      knownFlags,
                            const MicroSsaState&       ssaState,
                            const MicroStorage&        storage,
                            const MicroOperandStorage& operands)
    {
        knownValues.assign(ssaState.values().size(), {});
        knownFlags.assign(ssaState.values().size(), 0);

        bool changed = true;
        while (changed)
        {
            changed           = false;
            const auto values = ssaState.values();
            for (uint32_t valueId = 0; valueId < values.size(); ++valueId)
            {
                if (knownFlags[valueId])
                    continue;

                const auto& valueInfo = values[valueId];
                KnownValue  knownValue;
                bool        inferred = false;

                if (valueInfo.isPhi())
                {
                    const auto* phiInfo = ssaState.phiInfoForValue(valueId);
                    if (phiInfo)
                        inferred = tryInferPhiConstant(knownValue, *phiInfo, knownValues, knownFlags);
                }
                else
                {
                    inferred = tryInferInstructionConstant(knownValue, ssaState, storage, operands, knownValues, knownFlags, valueInfo);
                }

                if (!inferred)
                    continue;

                knownValues[valueId] = knownValue;
                knownFlags[valueId]  = 1;
                changed              = true;
            }
        }
    }

    bool tryFoldCopyFromKnown(const MicroSsaState&           ssaState,
                              const std::vector<KnownValue>& knownValues,
                              const std::vector<uint8_t>&    knownFlags,
                              MicroInstrRef                  instRef,
                              MicroInstr&                    inst,
                              MicroInstrOperand*             ops)
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

    bool tryFoldBinaryRegImm(const MicroSsaState&           ssaState,
                             const std::vector<KnownValue>& knownValues,
                             const std::vector<uint8_t>&    knownFlags,
                             MicroInstrRef                  instRef,
                             MicroInstr&                    inst,
                             MicroInstrOperand*             ops)
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
            return false;
        if (!ops)
            return false;
        if (!ops[0].reg.isVirtualInt())
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

    bool tryFoldBinaryRegReg(const MicroSsaState&           ssaState,
                             const MicroOperandStorage&     operands,
                             const std::vector<KnownValue>& knownValues,
                             const std::vector<uint8_t>&    knownFlags,
                             MicroInstrRef                  instRef,
                             MicroInstr&                    inst,
                             MicroInstrOperand*             ops)
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        if (!ops)
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

            uint64_t    converted = 0;
            MicroOpBits dstBits   = MicroOpBits::Zero;
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

    bool tryFoldExtend(const MicroSsaState&           ssaState,
                       const std::vector<KnownValue>& knownValues,
                       const std::vector<uint8_t>&    knownFlags,
                       MicroInstrRef                  instRef,
                       MicroInstr&                    inst,
                       MicroInstrOperand*             ops)
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
}

Result MicroConstantFoldingPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/ConstFold");
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

    const auto view  = storage.view();
    const auto endIt = view.end();
    for (auto it = view.begin(); it != endIt; ++it)
    {
        const MicroInstrRef instRef = it.current;
        MicroInstr&         inst    = *it;
        MicroInstrOperand*  ops     = inst.ops(operands);

        const bool changed = tryFoldCopyFromKnown(*ssaState, knownValues, knownFlags, instRef, inst, ops) ||
                             tryFoldBinaryRegImm(*ssaState, knownValues, knownFlags, instRef, inst, ops) ||
                             tryFoldBinaryRegReg(*ssaState, operands, knownValues, knownFlags, instRef, inst, ops) ||
                             tryFoldExtend(*ssaState, knownValues, knownFlags, instRef, inst, ops);
        if (changed)
            context.passChanged = true;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
