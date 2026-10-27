#pragma once
#include "Backend/ABI/CallConvKind.h"
#include "Backend/RuntimeSafety.h"
#include "Compiler/Sema/Helpers/SemaSafety.h"
#include "Support/Core/Flags.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/SmallVector.h"
#include "Support/Core/Utf8.h"
#include "Support/Report/WarningPolicy.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

enum class RtAttributeFlagsE : uint64_t
{
    Zero           = 0,
    EnumFlags      = 1 << 0,
    Strict         = 1 << 1,
    FullInit       = 1 << 2,
    Propagate      = 1 << 3,
    AttrMulti      = 1 << 4,
    ConstExpr      = 1 << 5,
    PrintMicro     = 1 << 6,
    PrintAst       = 1 << 7,
    Compiler       = 1 << 9,
    Inline         = 1 << 10,
    NoInline       = 1 << 11,
    PlaceHolder    = 1 << 12,
    Macro          = 1 << 14,
    Mixin          = 1 << 15,
    Implicit       = 1 << 16,
    CalleeReturn   = 1 << 18,
    Discardable    = 1 << 19,
    NoCopy         = 1 << 22,
    Opaque         = 1 << 23,
    NoDuplicate    = 1 << 25,
    NoDoc          = 1 << 26,
    OperatorIgnore = 1 << 27,
    DynCast        = 1 << 28,
    ReadOnly       = 1 << 29,
    NoReturn       = 1 << 30,
    Signal         = 1ull << 31,
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
    bool operator==(const AttributeParamInstance&) const = default;

    IdentifierRef nameIdRef   = IdentifierRef::invalid();
    ConstantRef   valueCstRef = ConstantRef::invalid();
};

struct AttributeInstance
{
    bool operator==(const AttributeInstance&) const = default;

    const SymbolFunction*                symbol = nullptr;
    SmallVector4<AttributeParamInstance> params;
};

struct RuntimeSafetyOverride
{
    uint16_t whatMask = 0;
    bool     value    = false;
};

struct AttributeList
{
    bool operator==(const AttributeList&) const = default;

    SmallVector4<AttributeInstance> attributes;

    RtAttributeFlags rtFlags = RtAttributeFlagsE::Zero;

    uint64_t            returnBorrowsParamsMask  = 0;
    uint64_t            storesParamsMask         = 0;
    uint64_t            storesIntoParamPairs     = 0;
    uint64_t            freesParamsMask          = 0;
    uint64_t            reallocatesParamsMask    = 0;
    uint64_t            returnsPayloadParamsMask = 0;
    uint64_t            returnsStorageParamsMask = 0;
    std::optional<bool> observesExternalBorrows;

    uint64_t returnsIndirectParamsMask    = 0;
    uint64_t storesIndirectParamsMask     = 0;
    uint64_t storesIndirectIntoParamPairs = 0;
    uint64_t freesIndirectParamsMask      = 0;

    // Debug print options are rare, but every scope copies its attribute list.
    // Keep their string storage in vectors instead of inflating each copied list.
    std::vector<Utf8> printMicroPassOptions;
    std::vector<Utf8> printAstStageOptions;

    WarningPolicy       warnings;
    std::optional<bool> backendOptimize;

    bool                        hasForeign = false;
    Utf8                        foreignModuleName;
    Utf8                        foreignFunctionName;
    Utf8                        foreignLinkModuleName;
    std::optional<CallConvKind> foreignCallConvKind;
    std::optional<CallConvKind> declaredCallConvKind;

    GeneratedOperatorFlags generatedOperators = GeneratedOperatorFlagsE::Zero;
    SourceCodeRef          generatedOperatorsCodeRef;

    bool empty() const
    {
        return attributes.empty() &&
               rtFlags.none() &&
               !hasRuntimeSafetyOverrides_ &&
               !hasSanityOverrides_ &&
               returnBorrowsParamsMask == 0 &&
               storesParamsMask == 0 &&
               storesIntoParamPairs == 0 &&
               freesParamsMask == 0 &&
               reallocatesParamsMask == 0 &&
               returnsPayloadParamsMask == 0 &&
               returnsStorageParamsMask == 0 &&
               !observesExternalBorrows.has_value() &&
               returnsIndirectParamsMask == 0 &&
               storesIndirectParamsMask == 0 &&
               storesIndirectIntoParamPairs == 0 &&
               freesIndirectParamsMask == 0 &&
               printMicroPassOptions.empty() &&
               printAstStageOptions.empty() &&
               warnings.empty() &&
               !backendOptimize.has_value() &&
               !hasForeign &&
               foreignModuleName.empty() &&
               foreignFunctionName.empty() &&
               foreignLinkModuleName.empty() &&
               !foreignCallConvKind.has_value() &&
               !declaredCallConvKind.has_value() &&
               generatedOperators.none();
    }

    bool hasRtFlag(RtAttributeFlags fl) const { return rtFlags.has(fl); }
    bool hasMacroOrMixin() const { return hasRtFlag(RtAttributeFlagsE::Macro | RtAttributeFlagsE::Mixin); }
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
        const uint16_t whatMask    = SemaSafety::mask(what);
        hasRuntimeSafetyOverrides_ = true;
        runtimeSafetyOverrideMask_ |= whatMask;
        if (value)
            runtimeSafetyEnabledMask_ |= whatMask;
        else
        {
            runtimeSafetyEnabledMask_ &= ~whatMask;
            runtimeSafetyDisableMask_ = runtimeSafetyDisableMask_.value_or(0) | whatMask;
        }
    }

    bool hasRuntimeSafetyOverrides() const { return hasRuntimeSafetyOverrides_; }

    // Ordinary inlining inherits every caller disable, including bits enabled again
    // later in that caller. Presence also preserves an explicit zero-mask disable.
    std::optional<uint16_t> runtimeSafetyDisables() const { return runtimeSafetyDisableMask_; }

    uint16_t effectiveRuntimeSafetyMask(Runtime::SafetyWhat buildCfgMask) const
    {
        return (SemaSafety::mask(buildCfgMask) & ~runtimeSafetyOverrideMask_) | runtimeSafetyEnabledMask_;
    }

    bool hasRuntimeSafety(Runtime::SafetyWhat buildCfgMask, Runtime::SafetyWhat what) const
    {
        const uint16_t effectiveMask = effectiveRuntimeSafetyMask(buildCfgMask);
        return SemaSafety::hasMask(effectiveMask, what);
    }

    // Compile-time sanity checks reuse SafetyWhat bits, with their own
    // Swag.Sanity attribute and build-configuration mask.
    void addSanityOverride(Runtime::SafetyWhat what, bool value)
    {
        const uint16_t whatMask = SemaSafety::mask(what);
        hasSanityOverrides_     = true;
        sanityOverrideMask_ |= whatMask;
        if (value)
            sanityEnabledMask_ |= whatMask;
        else
            sanityEnabledMask_ &= ~whatMask;
    }

    uint16_t effectiveSanityMask(Runtime::SafetyWhat buildCfgMask) const
    {
        return (SemaSafety::mask(buildCfgMask) & ~sanityOverrideMask_) | sanityEnabledMask_;
    }

    bool hasSanity(Runtime::SafetyWhat buildCfgMask, Runtime::SafetyWhat what) const
    {
        const uint16_t effectiveMask = effectiveSanityMask(buildCfgMask);
        return SemaSafety::hasMask(effectiveMask, what);
    }

    // Imported Swag.BorrowSummary masks (unary masks use bit i for parameter i):
    //   returns: the result may borrow parameter i.
    //   stores: parameter i may escape the call.
    //   into: bit i*8+j stores parameter j into storage reachable from i.
    //   frees: parameter i's pointee may be invalidated.
    //   reallocates: parameter i's owned payload may move or be released.
    //   returnsPayload: the result views parameter i's payload.
    //   returnsStorage: the result aliases parameter i's storage.
    // Indirect masks describe the source parameter's pointee; destination indices
    // still name direct parameters.
    void addBorrowSummary(uint64_t returnsMask, uint64_t storesMask, uint64_t intoPairs, uint64_t freesMask, uint64_t reallocatesMask, uint64_t returnsPayloadMask, uint64_t returnsStorageMask, bool observesExternal, uint64_t returnsIndirectMask, uint64_t storesIndirectMask, uint64_t intoIndirectPairs, uint64_t freesIndirectMask)
    {
        returnBorrowsParamsMask |= returnsMask;
        storesParamsMask |= storesMask;
        storesIntoParamPairs |= intoPairs;
        freesParamsMask |= freesMask;
        reallocatesParamsMask |= reallocatesMask;
        returnsPayloadParamsMask |= returnsPayloadMask;
        returnsStorageParamsMask |= returnsStorageMask & returnsMask;
        observesExternalBorrows = observesExternalBorrows.value_or(false) || observesExternal;

        returnsIndirectParamsMask |= returnsIndirectMask;
        storesIndirectParamsMask |= storesIndirectMask;
        storesIndirectIntoParamPairs |= intoIndirectPairs;
        freesIndirectParamsMask |= freesIndirectMask;
    }

    void setBackendOptimize(bool value)
    {
        backendOptimize = value;
    }

    // A foreign declaration inherits the convention of its scope unless 'Foreign'
    // names one explicitly.
    CallConvKind resolvedForeignCallConvKind() const
    {
        return foreignCallConvKind.value_or(declaredCallConvKind.value_or(CallConvKind::Swag));
    }

    void setForeign(std::string_view moduleName, std::string_view functionName, std::string_view linkModuleName = {}, std::optional<CallConvKind> callConvKind = std::nullopt)
    {
        hasForeign            = true;
        foreignModuleName     = moduleName;
        foreignFunctionName   = functionName;
        foreignLinkModuleName = linkModuleName;
        foreignCallConvKind   = callConvKind;
    }

private:
    uint16_t                runtimeSafetyOverrideMask_ = 0;
    uint16_t                runtimeSafetyEnabledMask_  = 0;
    std::optional<uint16_t> runtimeSafetyDisableMask_;
    bool                    hasRuntimeSafetyOverrides_ = false;

    // Sanity needs only the latest decision per bit. Preserve zero-mask presence
    // so explicit overrides keep the list nonempty; nested frames copy all state.
    uint16_t sanityOverrideMask_ = 0;
    uint16_t sanityEnabledMask_  = 0;
    bool     hasSanityOverrides_ = false;
};

SWC_END_NAMESPACE();
