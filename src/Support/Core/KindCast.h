#pragma once

SWC_BEGIN_NAMESPACE();

namespace KindCast
{
    template<typename T, typename Base, typename Kind>
    inline auto safeCast(Base* base, Kind kind) noexcept -> decltype(static_cast<T*>(base))
    {
        return kind == T::K ? static_cast<T*>(base) : nullptr;
    }

    template<typename T, typename Base, typename Kind>
    inline auto safeCast(const Base* base, Kind kind) noexcept -> decltype(static_cast<const T*>(base))
    {
        return kind == T::K ? static_cast<const T*>(base) : nullptr;
    }
}

SWC_END_NAMESPACE();
