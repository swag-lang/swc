#pragma once
#include "Backend/Micro/MicroSsaState.h"
#include <vector>

SWC_BEGIN_NAMESPACE();

template<typename TValue, typename TTraits, typename TContext>
using SsaTryInferInstructionFn = bool (*)(TValue&                         outValue,
                                          const TContext&                 context,
                                          uint32_t                        valueId,
                                          const MicroSsaState::ValueInfo& valueInfo,
                                          const std::vector<TValue>&      values,
                                          const std::vector<uint8_t>&     flags);

template<typename TValue, typename TTraits>
bool tryGetSsaValue(TValue& outValue, const std::vector<TValue>& values, const std::vector<uint8_t>& flags, const uint32_t valueId)
{
    if (valueId >= flags.size() || !flags[valueId])
        return false;

    outValue = values[valueId];
    return TTraits::isValid(outValue);
}

template<typename TValue, typename TTraits>
bool tryGetSsaReachingValue(TValue&                     outValue,
                            const MicroSsaState&        ssaState,
                            const std::vector<TValue>&  values,
                            const std::vector<uint8_t>& flags,
                            const MicroReg              reg,
                            const MicroInstrRef         instRef)
{
    const auto reachingDef = ssaState.reachingDef(reg, instRef);
    if (!reachingDef.valid())
        return false;

    return tryGetSsaValue<TValue, TTraits>(outValue, values, flags, reachingDef.valueId);
}

template<typename TValue, typename TTraits>
bool tryInferSsaPhiValue(TValue&                       outValue,
                         const MicroSsaState::PhiInfo& phiInfo,
                         const std::vector<TValue>&    values,
                         const std::vector<uint8_t>&   flags)
{
    bool   hasCandidate = false;
    TValue candidate{};

    for (const uint32_t incomingValueId : phiInfo.incomingValueIds)
    {
        TValue incomingValue{};
        if (!tryGetSsaValue<TValue, TTraits>(incomingValue, values, flags, incomingValueId))
            return false;

        if (!hasCandidate)
        {
            candidate    = incomingValue;
            hasCandidate = true;
            continue;
        }

        if (!TTraits::same(candidate, incomingValue))
            return false;
    }

    if (!hasCandidate)
        return false;

    outValue = candidate;
    return true;
}

template<typename TValue, typename TTraits, typename TContext>
void computeSsaValueFixedPoint(std::vector<TValue>&                                      outValues,
                               std::vector<uint8_t>&                                     outFlags,
                               const MicroSsaState&                                      ssaState,
                               const TContext&                                           context,
                               const SsaTryInferInstructionFn<TValue, TTraits, TContext> tryInferInstruction)
{
    const auto values = ssaState.values();
    outValues.assign(values.size(), TValue{});
    outFlags.assign(values.size(), 0);

    bool changed = true;
    while (changed)
    {
        changed = false;
        for (uint32_t valueId = 0; valueId < values.size(); ++valueId)
        {
            if (outFlags[valueId])
                continue;

            const auto& valueInfo = values[valueId];
            TValue      inferredValue{};
            bool        inferred = false;

            if (valueInfo.isPhi())
            {
                const auto* phiInfo = ssaState.phiInfoForValue(valueId);
                if (phiInfo)
                    inferred = tryInferSsaPhiValue<TValue, TTraits>(inferredValue, *phiInfo, outValues, outFlags);
            }
            else
            {
                inferred = tryInferInstruction(inferredValue, context, valueId, valueInfo, outValues, outFlags);
            }

            if (!inferred)
                continue;

            outValues[valueId] = inferredValue;
            outFlags[valueId]  = 1;
            changed            = true;
        }
    }
}

SWC_END_NAMESPACE();
