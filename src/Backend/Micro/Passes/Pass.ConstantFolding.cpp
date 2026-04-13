#include "pch.h"
#include "Backend/Micro/Passes/Pass.ConstantFolding.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Memory/MemoryProfile.h"

// Pre-RA constant folding backed by SSA def-use chains.
// Uses exact reaching definitions across the CFG, including phi joins when all
// incoming values are the same constant.

SWC_BEGIN_NAMESPACE();

namespace
{
    struct KnownValue
    {
        uint64_t    value  = 0;
        MicroOpBits opBits = MicroOpBits::B64;
    };

    bool tryGetKnownValue(KnownValue& out, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, const uint32_t valueId)
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

    bool tryGetKnownReachingValue(KnownValue& out, const MicroSsaState& ssaState, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, const MicroReg reg, const MicroInstrRef instRef)
    {
        const auto reachingDef = ssaState.reachingDef(reg, instRef);
        if (!reachingDef.valid())
            return false;

        return tryGetKnownValue(out, knownValues, knownFlags, reachingDef.valueId);
    }

    bool tryInferPhiConstant(KnownValue& out, const MicroSsaState& ssaState, const MicroSsaState::PhiInfo& phiInfo, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags)
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

        SWC_UNUSED(ssaState);
        if (!hasCandidate)
            return false;

        out = candidate;
        return true;
    }

    bool tryInferInstructionConstant(KnownValue& out, const MicroSsaState& ssaState, const MicroStorage& storage, const MicroOperandStorage& operands, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, const MicroSsaState::ValueInfo& valueInfo)
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
                if (inst->numOperands < 3 || ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
                    return false;

                out.value  = ops[2].valueU64;
                out.opBits = ops[1].opBits;
                return true;

            case MicroInstrOpcode::ClearReg:
                if (inst->numOperands < 2 || ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
                    return false;

                out.value  = 0;
                out.opBits = ops[1].opBits;
                return true;

            case MicroInstrOpcode::LoadRegReg:
            {
                if (inst->numOperands < 3 || ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt() || ops[2].opBits != MicroOpBits::B64)
                    return false;

                return tryGetKnownReachingValue(out, ssaState, knownValues, knownFlags, ops[1].reg, valueInfo.instRef);
            }

            case MicroInstrOpcode::OpBinaryRegImm:
            {
                if (inst->numOperands < 4 || ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
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

            default:
                break;
        }

        return false;
    }

    void computeKnownValues(std::vector<KnownValue>& knownValues, std::vector<uint8_t>& knownFlags, const MicroSsaState& ssaState, const MicroStorage& storage, const MicroOperandStorage& operands)
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
                        inferred = tryInferPhiConstant(knownValue, ssaState, *phiInfo, knownValues, knownFlags);
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

    bool tryFoldCopyFromKnown(const MicroSsaState& ssaState, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, const MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::LoadRegReg)
            return false;
        if (!ops || inst.numOperands < 3)
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

    bool tryFoldBinaryRegImm(const MicroSsaState& ssaState, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, const MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
            return false;
        if (!ops || inst.numOperands < 4)
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
                             tryFoldBinaryRegImm(*ssaState, knownValues, knownFlags, instRef, inst, ops);
        if (changed)
            context.passChanged = true;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
