#pragma once
#include "Backend/ABI/CallConv.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Helpers/SemaSafety.h"
#include "Support/Core/Flags.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/SmallVector.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

// Some runtime attributes have their own flag
enum class RtAttributeFlagsE : uint64_t
{
    Zero           = 0,
    EnumFlags      = 1 << 0,
    Strict         = 1 << 1,
    Complete       = 1 << 2,
    Incomplete     = 1 << 3,
    AttrMulti      = 1 << 4,
    ConstExpr      = 1 << 5,
    PrintMicro     = 1 << 6,
    PrintAst       = 1 << 7,
    Compiler       = 1 << 9,
    Inline         = 1 << 10,
    NoInline       = 1 << 11,
    PlaceHolder    = 1 << 12,
    NoPrint        = 1 << 13,
    Macro          = 1 << 14,
    Mixin          = 1 << 15,
    Implicit       = 1 << 16,
    CalleeReturn   = 1 << 18,
    Discardable    = 1 << 19,
    Global         = 1 << 20,
    Tls            = 1 << 21,
    NoCopy         = 1 << 22,
    Opaque         = 1 << 23,
    NoDuplicate    = 1 << 25,
    NoDoc          = 1 << 26,
    OperatorIgnore = 1 << 27,
};
using RtAttributeFlags = EnumFlags<RtAttributeFlagsE>;

enum class GeneratedOperatorFlagsE : uint32_t
{
    Zero      = 0,
    OpEquals  = 1 << 0,
    OpCompare = 1 << 1,
};
using GeneratedOperatorFlags = EnumFlags<GeneratedOperatorFlagsE>;

struct AttributeParamInstance
{
    IdentifierRef nameIdRef   = IdentifierRef::invalid();
    ConstantRef   valueCstRef = ConstantRef::invalid();
};

// One attribute
struct AttributeInstance
{
    const SymbolFunction*                symbol = nullptr;
    SmallVector4<AttributeParamInstance> params;
};

struct RuntimeSafetyOverride
{
    uint16_t whatMask = 0;
    bool     value    = false;
};

// A list of attributes
struct AttributeList
{
    SmallVector4<AttributeInstance>     attributes;
    RtAttributeFlags                    rtFlags = RtAttributeFlagsE::Zero;
    SmallVector4<RuntimeSafetyOverride> runtimeSafetyOverrides;
    SmallVector4<RuntimeSafetyOverride> sanityOverrides;
    uint64_t                            returnBorrowsParamsMask = 0;
    uint64_t                            storesParamsMask        = 0;
    uint64_t                            storesIntoParamPairs    = 0;
    uint64_t                            freesParamsMask         = 0;
    SmallVector4<Utf8>                  printMicroPassOptions;
    SmallVector4<Utf8>                  printAstStageOptions;
    std::optional<bool>                 backendOptimize;
    bool                                hasForeign = false;
    Utf8                                foreignModuleName;
    Utf8                                foreignFunctionName;
    Utf8                                foreignLinkModuleName;
    std::optional<CallConvKind>         foreignCallConvKind;
    GeneratedOperatorFlags              generatedOperators = GeneratedOperatorFlagsE::Zero;
    SourceCodeRef                       generatedOperatorsCodeRef;

    bool empty() const
    {
        return attributes.empty() &&
               rtFlags.none() &&
               runtimeSafetyOverrides.empty() &&
               sanityOverrides.empty() &&
               returnBorrowsParamsMask == 0 &&
               storesParamsMask == 0 &&
               storesIntoParamPairs == 0 &&
               freesParamsMask == 0 &&
               printMicroPassOptions.empty() &&
               printAstStageOptions.empty() &&
               !backendOptimize.has_value() &&
               !hasForeign &&
               foreignModuleName.empty() &&
               foreignFunctionName.empty() &&
               foreignLinkModuleName.empty() &&
               !foreignCallConvKind.has_value() &&
               generatedOperators.none();
    }

    bool hasRtFlag(RtAttributeFlagsE fl) const { return rtFlags.has(fl); }
    void addRtFlag(RtAttributeFlags fl) { rtFlags.add(fl); }
    bool hasGeneratedOperators() const { return generatedOperators.any(); }
    void addGeneratedOperator(GeneratedOperatorFlags fl, const SourceCodeRef& codeRef)
    {
        generatedOperators.add(fl);
        if (!generatedOperatorsCodeRef.isValid())
            generatedOperatorsCodeRef = codeRef;
    }

    void addRuntimeSafetyOverride(Runtime::SafetyWhat what, bool value)
    {
        runtimeSafetyOverrides.push_back({.whatMask = SemaSafety::mask(what), .value = value});
    }

    uint16_t effectiveRuntimeSafetyMask(Runtime::SafetyWhat buildCfgMask) const
    {
        uint16_t result = SemaSafety::mask(buildCfgMask);
        for (const auto& overrideValue : runtimeSafetyOverrides)
        {
            if (overrideValue.value)
                result |= overrideValue.whatMask;
            else
                result &= ~overrideValue.whatMask;
        }

        return result;
    }

    bool hasRuntimeSafety(Runtime::SafetyWhat buildCfgMask, Runtime::SafetyWhat what) const
    {
        const uint16_t effectiveMask = effectiveRuntimeSafetyMask(buildCfgMask);
        return SemaSafety::hasMask(effectiveMask, what);
    }

    // The STATIC (compile-time) sanity checks reuse the SafetyWhat flags but are
    // controlled by their own attribute ('Swag.Sanity') and build-config mask.
    void addSanityOverride(Runtime::SafetyWhat what, bool value)
    {
        sanityOverrides.push_back({.whatMask = SemaSafety::mask(what), .value = value});
    }

    uint16_t effectiveSanityMask(Runtime::SafetyWhat buildCfgMask) const
    {
        uint16_t result = SemaSafety::mask(buildCfgMask);
        for (const auto& overrideValue : sanityOverrides)
        {
            if (overrideValue.value)
                result |= overrideValue.whatMask;
            else
                result &= ~overrideValue.whatMask;
        }

        return result;
    }

    bool hasSanity(Runtime::SafetyWhat buildCfgMask, Runtime::SafetyWhat what) const
    {
        const uint16_t effectiveMask = effectiveSanityMask(buildCfgMask);
        return SemaSafety::hasMask(effectiveMask, what);
    }

    // Computed borrow summaries re-imported from a module API ('Swag.BorrowSummary'):
    // bit i of 'returns' = the return value may borrow parameter #i, bit i of 'stores'
    // = parameter #i may be stored beyond the call, bit (i*8+j) of 'into' = parameter
    // #j may be stored into storage reachable from parameter #i, bit i of 'frees' =
    // the call invalidates what parameter #i points to.
    void addBorrowSummary(uint64_t returnsMask, uint64_t storesMask, uint64_t intoPairs, uint64_t freesMask)
    {
        returnBorrowsParamsMask |= returnsMask;
        storesParamsMask |= storesMask;
        storesIntoParamPairs |= intoPairs;
        freesParamsMask |= freesMask;
    }

    void setBackendOptimize(bool value)
    {
        backendOptimize = value;
    }

    CallConvKind resolvedForeignCallConvKind() const
    {
        return foreignCallConvKind.value_or(CallConvKind::C);
    }

    void setForeign(std::string_view moduleName, std::string_view functionName, std::string_view linkModuleName = {}, std::optional<CallConvKind> callConvKind = std::nullopt)
    {
        hasForeign            = true;
        foreignModuleName     = moduleName;
        foreignFunctionName   = functionName;
        foreignLinkModuleName = linkModuleName;
        foreignCallConvKind   = callConvKind;
    }
};

SWC_END_NAMESPACE();
