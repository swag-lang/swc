#pragma once

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    // Where an attribute accepts being written. Keep in sync with the Swag mirror
    // 'Swag.AttributeUsage' in bin/runtime/api.swg: 'AttrUsage' arguments are read back
    // from the reflected attribute value, so both spellings share these bits.
    enum class AttributeUsage : uint32_t
    {
        Enum              = 0x00000001,
        EnumValue         = 0x00000002,
        StructVariable    = 0x00000004,
        GlobalVariable    = 0x00000008,
        Variable          = 0x00000010,
        Struct            = 0x00000020,
        Function          = 0x00000040,
        FunctionParameter = 0x00000080,
        File              = 0x00000100,
        Constant          = 0x00000200,
        Alias             = 0x00000400,
        Scope             = 0x00000800,
        Multi             = 0x01000000,
        Gen               = 0x02000000,
        All               = 0x04000000,
        None              = 0x00000000,
    };
}

SWC_END_NAMESPACE();
