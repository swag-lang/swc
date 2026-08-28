#pragma once

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    enum class TargetOs;
}

enum class NativeObjectFormat : uint8_t
{
    WindowsCoff,
};

std::optional<NativeObjectFormat> getNativeObjFormat(Runtime::TargetOs targetOs);

SWC_END_NAMESPACE();
