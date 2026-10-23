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
};

constexpr bool isValidCallConvKind(CallConvKind kind) noexcept
{
    switch (kind)
    {
        case CallConvKind::C:
        case CallConvKind::WindowsX64:
        case CallConvKind::Swag:
            return true;
    }

    return false;
}

SWC_END_NAMESPACE();
