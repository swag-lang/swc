// ReSharper disable CppInconsistentNaming
#pragma once

SWC_BEGIN_NAMESPACE();

template<class E>
struct enable_bitmask_operators : std::false_type
{
};

template<class E>
constexpr auto to_underlying(E e) noexcept
{
    return static_cast<std::underlying_type_t<E>>(e);
}

template<class E>
constexpr E
operator|(E a, E b) noexcept
    requires enable_bitmask_operators<E>::value
{
    return static_cast<E>(to_underlying(a) | to_underlying(b));
}

template<class E>
constexpr E
operator&(E a, E b) noexcept
    requires enable_bitmask_operators<E>::value
{
    return static_cast<E>(to_underlying(a) & to_underlying(b));
}

template<class E>
constexpr E
operator^(E a, E b) noexcept
    requires enable_bitmask_operators<E>::value
{
    return static_cast<E>(to_underlying(a) ^ to_underlying(b));
}

template<class E>
constexpr E
operator~(E a) noexcept
    requires enable_bitmask_operators<E>::value
{
    using U = std::make_unsigned_t<std::underlying_type_t<E>>;
    return static_cast<E>(~static_cast<U>(to_underlying(a)));
}

template<class E>
constexpr E&
operator|=(E& a, E b) noexcept
    requires enable_bitmask_operators<E>::value
{
    return a = a | b;
}

template<class E>
constexpr E&
operator&=(E& a, E b) noexcept
    requires enable_bitmask_operators<E>::value
{
    return a = a & b;
}

template<class E>
constexpr E&
operator^=(E& a, E b) noexcept
    requires enable_bitmask_operators<E>::value
{
    return a = a ^ b;
}

#define SWC_ENABLE_BITMASK(E)                           \
    template<>                                          \
    struct enable_bitmask_operators<E> : std::true_type \
    {                                                   \
    }

template<class E>
constexpr bool has_all(E value, E mask) noexcept
{
    return (value & mask) == mask;
}

template<class E>
constexpr bool has_any(E value, E mask) noexcept
{
    return static_cast<bool>(to_underlying(value & mask));
}

SWC_END_NAMESPACE();
