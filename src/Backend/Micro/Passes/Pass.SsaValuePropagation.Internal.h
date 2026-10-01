#pragma once
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Core/RefTypes.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

struct MicroSsaKnownValue
{
    uint64_t    value  = 0;
    MicroOpBits opBits = MicroOpBits::B64;

    bool covers(MicroOpBits readBits, MicroReg reg) const
    {
        // Only an integer dword definition also proves its zero upper half.
        return getNumBits(readBits) <= getNumBits(opBits) ||
               (reg.isAnyInt() && opBits == MicroOpBits::B32 && readBits == MicroOpBits::B64);
    }
};

struct MicroSsaKnownValueTraits
{
    [[maybe_unused]] static bool isValid(const MicroSsaKnownValue&)
    {
        return true;
    }

    [[maybe_unused]] static bool same(const MicroSsaKnownValue& lhs, const MicroSsaKnownValue& rhs)
    {
        return lhs.value == rhs.value && lhs.opBits == rhs.opBits;
    }
};

struct MicroSsaKnownValueContext
{
    const MicroSsaState*       ssaState = nullptr;
    const MicroStorage*        storage  = nullptr;
    const MicroOperandStorage* operands = nullptr;
};

struct MicroSsaCanonicalValue
{
    MicroReg reg     = MicroReg::invalid();
    uint32_t valueId = MicroSsaState::K_INVALID_VALUE;

    bool valid() const
    {
        return reg.isValid() && valueId != MicroSsaState::K_INVALID_VALUE;
    }
};

// These passes run sequentially and overwrite every SSA-sized entry before reading it.
// Keeping their storage on the worker avoids allocating it for each pass and function.
struct MicroSsaValueScratch
{
    std::vector<MicroSsaKnownValue>     knownValues;
    std::vector<MicroSsaCanonicalValue> canonicalValues;
    std::vector<uint8_t>                flags;
    std::vector<MicroInstrRef>          toErase;
};

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

inline bool tryGetKnownReachingValue(MicroSsaKnownValue& outValue, const MicroSsaKnownValueContext& context, const std::vector<MicroSsaKnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, MicroReg reg, MicroInstrRef instRef)
{
    SWC_ASSERT(context.ssaState != nullptr);
    return tryGetSsaReachingValue<MicroSsaKnownValue, MicroSsaKnownValueTraits>(outValue, *context.ssaState, knownValues, knownFlags, reg, instRef);
}

inline bool tryGetKnownReachingValue(MicroSsaKnownValue& outValue, const MicroSsaState& ssaState, const std::vector<MicroSsaKnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, MicroReg reg, MicroInstrRef instRef)
{
    return tryGetSsaReachingValue<MicroSsaKnownValue, MicroSsaKnownValueTraits>(outValue, ssaState, knownValues, knownFlags, reg, instRef);
}

template<typename T_VALUE, typename T_TRAITS>
bool tryInferSsaPhiValue(T_VALUE& outValue, const MicroSsaState::PhiInfo& phiInfo, const std::vector<T_VALUE>& values, const std::vector<uint8_t>& flags)
{
    if (phiInfo.incomingValueIds.empty())
        return false;

    T_VALUE candidate{};
    if (!tryGetSsaValue<T_VALUE, T_TRAITS>(candidate, values, flags, phiInfo.incomingValueIds.front()))
        return false;

    for (size_t i = 1; i < phiInfo.incomingValueIds.size(); ++i)
    {
        T_VALUE incomingValue{};
        if (!tryGetSsaValue<T_VALUE, T_TRAITS>(incomingValue, values, flags, phiInfo.incomingValueIds[i]))
            return false;

        if (!T_TRAITS::same(candidate, incomingValue))
            return false;
    }

    outValue = candidate;
    return true;
}

template<typename T_VALUE, typename T_TRAITS, typename T_CONTEXT>
void computeSsaValueFixedPoint(std::vector<T_VALUE>& outValues, std::vector<uint8_t>& outFlags, const MicroSsaState& ssaState, const T_CONTEXT& context, const SsaTryInferInstructionFn<T_VALUE, T_TRAITS, T_CONTEXT> tryInferInstruction)
{
    const auto values = ssaState.values();
    // Every read checks the corresponding flag, so retained entries need no reset.
    outValues.resize(values.size());
    outFlags.assign(values.size(), 0);

    size_t unresolved = values.size();
    bool   changed    = true;
    while (changed && unresolved)
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
                const auto* phiInfo = ssaState.phiInfo(valueInfo.phiIndex);
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
            --unresolved;
            changed = true;
        }

        // SSA creates instruction values in dominator order, with each read
        // preceding the instruction's writes. Without phis all dependencies
        // have already been considered, so another sweep cannot infer more.
        if (ssaState.phis().empty())
            break;
    }
}

SWC_END_NAMESPACE();
