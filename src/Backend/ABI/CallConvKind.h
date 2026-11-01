#pragma once

SWC_BEGIN_NAMESPACE();

enum class CallConvKind : uint8_t
{
    // Target C ABI for the selected platform.
    C,
    // Concrete Windows x64 ABI.
    WindowsX64,
    // Swag's default compiled/JIT ABI for the current target runtime.
    Swag,
    // Concrete System V AMD64 ABI; appended to preserve serialized convention values.
    SystemVAMD64,
};

constexpr bool isValidCallConvKind(CallConvKind kind) noexcept
{
    switch (kind)
    {
        case CallConvKind::C:
        case CallConvKind::WindowsX64:
        case CallConvKind::Swag:
        case CallConvKind::SystemVAMD64:
            return true;
    }

    return false;
}

SWC_END_NAMESPACE();
