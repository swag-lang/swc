#pragma once
#include "Backend/Micro/MicroSsaState.h"

SWC_BEGIN_NAMESPACE();

template<typename T_VALUE, typename T_TRAITS, typename T_CONTEXT>
using SsaTryInferInstructionFn = bool (*)(T_VALUE& outValue, const T_CONTEXT& context, uint32_t valueId, const MicroSsaState::ValueInfo& valueInfo, const std::vector<T_VALUE>& values, const std::vector<uint8_t>& flags);

template<typename T_VALUE, typename T_TRAITS>
bool tryGetSsaValue(T_VALUE& outValue, const std::vector<T_VALUE>& values, const std::vector<uint8_t>& flags, const uint32_t valueId)
{
    if (valueId >= flags.size() || !flags[valueId])
        return false;

    outValue = values[valueId];
    return T_TRAITS::isValid(outValue);
}

template<typename T_VALUE, typename T_TRAITS>
bool tryGetSsaReachingValue(T_VALUE& outValue, const MicroSsaState& ssaState, const std::vector<T_VALUE>& values, const std::vector<uint8_t>& flags, MicroReg reg, MicroInstrRef instRef)
{
    const auto reachingDef = ssaState.reachingDef(reg, instRef);
    if (!reachingDef.valid())
        return false;

    return tryGetSsaValue<T_VALUE, T_TRAITS>(outValue, values, flags, reachingDef.valueId);
}

template<typename T_VALUE, typename T_TRAITS>
bool tryInferSsaPhiValue(T_VALUE& outValue, const MicroSsaState::PhiInfo& phiInfo, const std::vector<T_VALUE>& values, const std::vector<uint8_t>& flags)
{
    bool    hasCandidate = false;
    T_VALUE candidate{};

    for (const uint32_t incomingValueId : phiInfo.incomingValueIds)
    {
        T_VALUE incomingValue{};
        if (!tryGetSsaValue<T_VALUE, T_TRAITS>(incomingValue, values, flags, incomingValueId))
            return false;

        if (!hasCandidate)
        {
            candidate    = incomingValue;
            hasCandidate = true;
            continue;
        }

        if (!T_TRAITS::same(candidate, incomingValue))
            return false;
    }

    if (!hasCandidate)
        return false;

    outValue = candidate;
    return true;
}

template<typename T_VALUE, typename T_TRAITS, typename T_CONTEXT>
void computeSsaValueFixedPoint(std::vector<T_VALUE>& outValues, std::vector<uint8_t>& outFlags, const MicroSsaState& ssaState, const T_CONTEXT& context, const SsaTryInferInstructionFn<T_VALUE, T_TRAITS, T_CONTEXT> tryInferInstruction)
{
    const auto values = ssaState.values();
    outValues.assign(values.size(), T_VALUE{});
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
            T_VALUE     inferredValue{};
            bool        inferred = false;

            if (valueInfo.isPhi())
            {
                const auto* phiInfo = ssaState.phiInfoForValue(valueId);
                if (phiInfo)
                    inferred = tryInferSsaPhiValue<T_VALUE, T_TRAITS>(inferredValue, *phiInfo, outValues, outFlags);
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
