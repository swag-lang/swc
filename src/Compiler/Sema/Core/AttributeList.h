#pragma once
#include "Backend/Runtime.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

// Some runtime attributes have their own flag
enum class RtAttributeFlagsE : uint64_t
{
    Zero         = 0,
    EnumFlags    = 1 << 0,
    Strict       = 1 << 1,
    Complete     = 1 << 2,
    Incomplete   = 1 << 3,
    AttrMulti    = 1 << 4,
    ConstExpr    = 1 << 5,
    PrintMicro   = 1 << 6,
    Compiler     = 1 << 9,
    Inline       = 1 << 10,
    NoInline     = 1 << 11,
    PlaceHolder  = 1 << 12,
    NoPrint      = 1 << 13,
    Macro        = 1 << 14,
    Mixin        = 1 << 15,
    Implicit     = 1 << 16,
    Overload     = 1 << 17,
    CalleeReturn = 1 << 18,
    Discardable  = 1 << 19,
    NotGeneric   = 1 << 20,
    Tls          = 1 << 21,
    NoCopy       = 1 << 22,
    Opaque       = 1 << 23,
    EnumIndex    = 1 << 24,
    NoDuplicate  = 1 << 25,
    NoDoc        = 1 << 26,
    Global       = 1 << 27,
};
using RtAttributeFlags = EnumFlags<RtAttributeFlagsE>;

// One attribute
struct AttributeInstance
{
    const SymbolFunction* symbol = nullptr;
};

// A list of attributes
struct AttributeList
{
    SmallVector4<AttributeInstance> attributes;
    RtAttributeFlags                rtFlags = RtAttributeFlagsE::Zero;
    SmallVector4<Utf8>              printMicroPassOptions;
    bool                            hasBackendOptimize = false;
    Runtime::BuildCfgBackendOptim   backendOptimize    = Runtime::BuildCfgBackendOptim::O0;
    bool                            hasForeign         = false;
    Utf8                            foreignModuleName;
    Utf8                            foreignFunctionName;

    bool hasRtFlag(RtAttributeFlagsE fl) const { return rtFlags.has(fl); }
    void addRtFlag(RtAttributeFlags fl) { rtFlags.add(fl); }
    void setBackendOptimize(Runtime::BuildCfgBackendOptim value)
    {
        hasBackendOptimize = true;
        backendOptimize    = value;
    }

    void setForeign(std::string_view moduleName, std::string_view functionName)
    {
        hasForeign         = true;
        foreignModuleName  = moduleName;
        foreignFunctionName = functionName;
    }
};

SWC_END_NAMESPACE();
