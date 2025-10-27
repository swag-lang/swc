// ReSharper disable CppInconsistentNaming
#pragma once

SWC_BEGIN_NAMESPACE();

template<typename T>
struct Flags
{
    using U = std::underlying_type_t<T>;

    Flags() = default;

    // ReSharper disable once CppNonExplicitConvertingConstructor
    constexpr Flags(T other) :
        flags{static_cast<U>(other)}
    {
    }

    bool operator==(const Flags& other) const { return flags == other.flags; }

    bool  has(T fl) const { return (flags & static_cast<U>(fl)) != 0; }
    Flags with(T fl) const { return Flags{static_cast<T>(flags | static_cast<U>(fl))}; }
    Flags mask(T fl) const { return Flags{static_cast<T>(flags & static_cast<U>(fl))}; }
    Flags maskInvert(T fl) const { return Flags{static_cast<T>(flags & ~static_cast<U>(fl))}; }
    void  add(T fl) { flags |= static_cast<U>(fl); }
    void  add(T fl0, T fl1) { flags |= static_cast<U>(fl0) | static_cast<U>(fl1); }
    void  remove(T fl) { flags &= ~static_cast<U>(fl); }
    void  clear() { flags = 0; }

    U flags = 0;
};

// Opt-in trait
template<class E>
struct enable_bitmask_operators : std::false_type
{
};

#define SWC_ENABLE_BITMASK(E)                           \
    template<>                                          \
    struct enable_bitmask_operators<E> : std::true_type \
    {                                                   \
    }

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
