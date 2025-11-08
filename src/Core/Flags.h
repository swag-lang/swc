#pragma once

SWC_BEGIN_NAMESPACE()

template<typename T>
struct EnumFlags
{
    static_assert(std::is_enum_v<T>, "EnumFlags<T> requires T to be an enum type");
    using U    = std::underlying_type_t<T>;
    using Self = EnumFlags<T>;

    constexpr EnumFlags() = default;

    // implicit on purpose
    // ReSharper disable once CppNonExplicitConvertingConstructor
    constexpr EnumFlags(T other) :
        flags{static_cast<U>(other)}
    {
    }

    // comparisons
    constexpr bool operator==(const Self& other) const { return flags == other.flags; }
    constexpr bool operator!=(const Self& other) const { return !(*this == other); }
    friend bool    operator<(const EnumFlags& lhs, const EnumFlags& rhs) { return lhs.flags < rhs.flags; }
    friend bool    operator<=(const EnumFlags& lhs, const EnumFlags& rhs) { return !(rhs < lhs); }
    friend bool    operator>(const EnumFlags& lhs, const EnumFlags& rhs) { return rhs < lhs; }
    friend bool    operator>=(const EnumFlags& lhs, const EnumFlags& rhs) { return !(lhs < rhs); }

    // bitwise OR
    friend constexpr Self operator|(Self a, Self b) { return Self{static_cast<T>(a.flags | b.flags)}; }
    friend constexpr Self operator|(Self a, T b) { return Self{static_cast<T>(a.flags | static_cast<U>(b))}; }
    friend constexpr Self operator|(T a, Self b) { return Self{static_cast<T>(static_cast<U>(a) | b.flags)}; }

    // queries: hasAll / has (alias) / hasAny
    constexpr bool hasAll(Self fl) const { return (flags & fl.flags) == fl.flags; }
    constexpr bool hasAll(T fl) const { return (flags & static_cast<U>(fl)) == static_cast<U>(fl); }

    constexpr bool has(Self fl) const { return hasAny(fl); }
    constexpr bool has(T fl) const { return hasAny(fl); }

    constexpr bool hasAny(Self fl) const { return (flags & fl.flags) != 0; }
    constexpr bool hasAny(T fl) const { return (flags & static_cast<U>(fl)) != 0; }

    // hasAny — multiple (pass {A,B,C} or {EnumFlags{A}, EnumFlags{B}})
    constexpr bool hasAny(std::initializer_list<T> list) const
    {
        U mask = 0;
        for (T x : list)
            mask |= static_cast<U>(x);
        return (flags & mask) != 0;
    }

    constexpr bool hasAny(std::initializer_list<Self> list) const
    {
        U mask = 0;
        for (Self x : list)
            mask |= x.flags;
        return (flags & mask) != 0;
    }

    // functional helpers
    constexpr Self with(Self fl) const { return Self{static_cast<T>(flags | fl.flags)}; }
    constexpr Self with(T fl) const { return Self{static_cast<T>(flags | static_cast<U>(fl))}; }

    constexpr Self mask(Self fl) const { return Self{static_cast<T>(flags & fl.flags)}; }
    constexpr Self mask(T fl) const { return Self{static_cast<T>(flags & static_cast<U>(fl))}; }

    constexpr Self maskInvert(Self fl) const { return Self{static_cast<T>(flags & ~fl.flags)}; }
    constexpr Self maskInvert(T fl) const { return Self{static_cast<T>(flags & ~static_cast<U>(fl))}; }

    // mutating helpers
    constexpr void add(Self fl) { flags |= fl.flags; }
    constexpr void add(T fl) { flags |= static_cast<U>(fl); }
    constexpr void remove(Self fl) { flags &= ~fl.flags; }
    constexpr void remove(T fl) { flags &= ~static_cast<U>(fl); }
    constexpr void clear() { flags = 0; }

    U flags = 0;
};

SWC_END_NAMESPACE()
