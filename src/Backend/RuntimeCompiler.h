#pragma once
#include "Backend/RuntimeTypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    enum class CompilerMsgKind : uint32_t
    {
        PassAfterSemantic,
        PassBeforeRunByteCode,
        PassBeforeOutput,
        PassAllDone,
        SemFunctions,
        SemTypes,
        SemGlobals,
        AttributeGen,
    };

    enum class CompilerMsgMask : uint64_t
    {
        PassAfterSemantic = 1ull << static_cast<uint32_t>(CompilerMsgKind::PassAfterSemantic),
        PassBeforeRun     = 1ull << static_cast<uint32_t>(CompilerMsgKind::PassBeforeRunByteCode),
        PassBeforeOutput  = 1ull << static_cast<uint32_t>(CompilerMsgKind::PassBeforeOutput),
        PassAllDone       = 1ull << static_cast<uint32_t>(CompilerMsgKind::PassAllDone),
        SemFunctions      = 1ull << static_cast<uint32_t>(CompilerMsgKind::SemFunctions),
        SemTypes          = 1ull << static_cast<uint32_t>(CompilerMsgKind::SemTypes),
        SemGlobals        = 1ull << static_cast<uint32_t>(CompilerMsgKind::SemGlobals),
        AttributeGen      = 1ull << static_cast<uint32_t>(CompilerMsgKind::AttributeGen),
        All               = ~0ull,
    };

    struct CompilerMessage
    {
        String          moduleName;
        String          name;
        const TypeInfo* type;
        CompilerMsgKind kind;
    };

    struct ICompiler : Interface
    {
    };
}

SWC_END_NAMESPACE();
