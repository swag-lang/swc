#pragma once

SWC_BEGIN_NAMESPACE()

template<typename T>
struct EnumFlags
{
    using U    = std::underlying_type_t<T>;
    using Type = T;
    using Self = EnumFlags;

    static_assert(std::is_enum_v<T>, "EnumFlags<T> requires T to be an enum type");

    constexpr EnumFlags() = default;

    // ReSharper disable once CppNonExplicitConvertingConstructor
    constexpr EnumFlags(T other) :
        flags{static_cast<U>(other)}
    {
    }

    constexpr bool        operator==(const Self& other) const { return flags == other.flags; }
    constexpr bool        operator!=(const Self& other) const { return !(*this == other); }
    friend bool           operator<(const EnumFlags& lhs, const EnumFlags& rhs) { return lhs.flags < rhs.flags; }
    friend bool           operator<=(const EnumFlags& lhs, const EnumFlags& rhs) { return !(rhs < lhs); }
    friend bool           operator>(const EnumFlags& lhs, const EnumFlags& rhs) { return rhs < lhs; }
    friend bool           operator>=(const EnumFlags& lhs, const EnumFlags& rhs) { return !(lhs < rhs); }
    friend constexpr Self operator|(Self a, Self b) { return Self{static_cast<T>(a.flags | b.flags)}; }
    friend constexpr Self operator|(Self a, T b) { return Self{static_cast<T>(a.flags | static_cast<U>(b))}; }
    friend constexpr Self operator|(T a, Self b) { return Self{static_cast<T>(static_cast<U>(a) | b.flags)}; }

    constexpr bool hasAll(Self fl) const { return (flags & fl.flags) == fl.flags; }
    constexpr bool hasAll(T fl) const { return (flags & static_cast<U>(fl)) == static_cast<U>(fl); }
    constexpr bool has(Self fl) const { return hasAny(fl); }
    constexpr bool has(T fl) const { return hasAny(fl); }
    constexpr bool hasNot(Self fl) const { return !hasAny(fl); }
    constexpr bool hasNot(T fl) const { return !hasAny(fl); }
    constexpr bool hasAny(Self fl) const { return (flags & fl.flags) != 0; }
    constexpr bool hasAny(T fl) const { return (flags & static_cast<U>(fl)) != 0; }

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

    constexpr Self with(Self fl) const { return Self{static_cast<T>(flags | fl.flags)}; }
    constexpr Self with(T fl) const { return Self{static_cast<T>(flags | static_cast<U>(fl))}; }
    constexpr Self mask(Self fl) const { return Self{static_cast<T>(flags & fl.flags)}; }
    constexpr Self mask(T fl) const { return Self{static_cast<T>(flags & static_cast<U>(fl))}; }
    constexpr Self maskInvert(Self fl) const { return Self{static_cast<T>(flags & ~fl.flags)}; }
    constexpr Self maskInvert(T fl) const { return Self{static_cast<T>(flags & ~static_cast<U>(fl))}; }
    constexpr void clearMask(T fl) { flags &= ~static_cast<U>(fl); }
    constexpr void add(Self fl) { flags |= fl.flags; }
    constexpr void add(T fl) { flags |= static_cast<U>(fl); }
    constexpr void remove(Self fl) { flags &= ~fl.flags; }
    constexpr void remove(T fl) { flags &= ~static_cast<U>(fl); }
    constexpr void clear() { flags = 0; }
    constexpr bool any() const { return flags != 0; }
    constexpr bool none() const { return flags == 0; }

    template<typename FN>
    void forEachSet(FN fn) const
    {
        U bits = flags;
        while (bits != 0)
        {
            U lsb = bits & static_cast<U>(-static_cast<std::make_signed_t<U>>(bits));
            bits &= ~lsb;
            fn(static_cast<T>(lsb));
        }
    }

    U flags = 0;

    U get() const { return flags; }
};

template<typename T, std::enable_if_t<std::is_enum_v<T>, int> = 0>
constexpr EnumFlags<T> operator|(T lhs, T rhs)
{
    return EnumFlags<T>(lhs) | rhs;
}

template<typename T>
struct AtomicEnumFlags
{
    using U    = std::underlying_type_t<T>;
    using Type = T;
    using Self = AtomicEnumFlags;

    static_assert(std::is_enum_v<T>, "AtomicEnumFlags<T> requires T to be an enum type");
    static_assert(std::is_integral_v<U> || std::is_unsigned_v<U>, "AtomicEnumFlags<T> requires an enum with an integral underlying type");

    constexpr AtomicEnumFlags() noexcept = default;

    // ReSharper disable once CppNonExplicitConvertingConstructor
    constexpr AtomicEnumFlags(T other) noexcept :
        flags{static_cast<U>(other)}
    {
    }

    constexpr AtomicEnumFlags(EnumFlags<T> other) noexcept :
        flags{other.flags}
    {
    }

    AtomicEnumFlags(const Self& other) noexcept :
        flags{other.flags.load(std::memory_order_relaxed)}
    {
    }

    Self& operator=(const Self& other) noexcept
    {
        if (this != &other)
            flags.store(other.flags.load(std::memory_order_relaxed), std::memory_order_relaxed);
        return *this;
    }

    U load(std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        return flags.load(mo);
    }

    void store(U v, std::memory_order mo = std::memory_order_release) noexcept
    {
        flags.store(v, mo);
    }

    void store(T v, std::memory_order mo = std::memory_order_release) noexcept
    {
        flags.store(static_cast<U>(v), mo);
    }

    EnumFlags<T> snapshot(std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        return EnumFlags<T>{static_cast<T>(flags.load(mo))};
    }

    bool hasAll(EnumFlags<T> fl, std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        const U v = flags.load(mo);
        return (v & fl.flags) == fl.flags;
    }

    bool hasAll(T fl, std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        const U v = flags.load(mo);
        const U m = static_cast<U>(fl);
        return (v & m) == m;
    }

    bool has(EnumFlags<T> fl, std::memory_order mo = std::memory_order_acquire) const noexcept { return hasAny(fl, mo); }
    bool has(T fl, std::memory_order mo = std::memory_order_acquire) const noexcept { return hasAny(fl, mo); }
    bool hasNot(EnumFlags<T> fl, std::memory_order mo = std::memory_order_acquire) const noexcept { return !hasAny(fl, mo); }
    bool hasNot(T fl, std::memory_order mo = std::memory_order_acquire) const noexcept { return !hasAny(fl, mo); }

    bool hasAny(EnumFlags<T> fl, std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        const U v = flags.load(mo);
        return (v & fl.flags) != 0;
    }

    bool hasAny(T fl, std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        const U v = flags.load(mo);
        return (v & static_cast<U>(fl)) != 0;
    }

    bool hasAny(std::initializer_list<T> list, std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        U mask = 0;
        for (T x : list)
            mask |= static_cast<U>(x);
        const U v = flags.load(mo);
        return (v & mask) != 0;
    }

    bool hasAny(std::initializer_list<EnumFlags<T>> list, std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        U mask = 0;
        for (auto x : list)
            mask |= x.flags;
        const U v = flags.load(mo);
        return (v & mask) != 0;
    }

    bool any(std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        return flags.load(mo) != 0;
    }

    bool none(std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        return flags.load(mo) == 0;
    }

    void add(EnumFlags<T> fl, std::memory_order mo = std::memory_order_acq_rel) noexcept
    {
        flags.fetch_or(fl.flags, mo);
    }

    void add(T fl, std::memory_order mo = std::memory_order_acq_rel) noexcept
    {
        flags.fetch_or(static_cast<U>(fl), mo);
    }

    void remove(EnumFlags<T> fl, std::memory_order mo = std::memory_order_acq_rel) noexcept
    {
        flags.fetch_and(static_cast<U>(~fl.flags), mo);
    }

    void remove(T fl, std::memory_order mo = std::memory_order_acq_rel) noexcept
    {
        flags.fetch_and(static_cast<U>(~static_cast<U>(fl)), mo);
    }

    void clear(std::memory_order mo = std::memory_order_acq_rel) noexcept
    {
        flags.store(0, mo);
    }

    void clearMask(T fl, std::memory_order mo = std::memory_order_acq_rel) noexcept
    {
        flags.fetch_and(static_cast<U>(~static_cast<U>(fl)), mo);
    }

    EnumFlags<T> with(EnumFlags<T> fl, std::memory_order mo = std::memory_order_acq_rel) noexcept
    {
        const U old = flags.fetch_or(fl.flags, mo);
        return EnumFlags<T>{static_cast<T>(old | fl.flags)};
    }

    EnumFlags<T> with(T fl, std::memory_order mo = std::memory_order_acq_rel) noexcept
    {
        const U m   = static_cast<U>(fl);
        const U old = flags.fetch_or(m, mo);
        return EnumFlags<T>{static_cast<T>(old | m)};
    }

    EnumFlags<T> mask(EnumFlags<T> fl, std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        const U v = flags.load(mo);
        return EnumFlags<T>{static_cast<T>(v & fl.flags)};
    }

    EnumFlags<T> mask(T fl, std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        const U v = flags.load(mo);
        return EnumFlags<T>{static_cast<T>(v & static_cast<U>(fl))};
    }

    EnumFlags<T> maskInvert(EnumFlags<T> fl, std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        const U v = flags.load(mo);
        return EnumFlags<T>{static_cast<T>(v & static_cast<U>(~fl.flags))};
    }
    EnumFlags<T> maskInvert(T fl, std::memory_order mo = std::memory_order_acquire) const noexcept
    {
        const U v = flags.load(mo);
        return EnumFlags<T>{static_cast<T>(v & static_cast<U>(~static_cast<U>(fl)))};
    }

    EnumFlags<T> update(EnumFlags<T> setMask, EnumFlags<T> clearMask, std::memory_order mo = std::memory_order_acq_rel) noexcept
    {
        U expected = flags.load(std::memory_order_relaxed);
        for (;;)
        {
            U desired = static_cast<U>((expected | setMask.flags) & ~clearMask.flags);
            if (flags.compare_exchange_weak(expected, desired, mo, std::memory_order_relaxed))
                return EnumFlags<T>{static_cast<T>(desired)};
        }
    }

    template<typename FN>
    void forEachSet(FN fn, std::memory_order mo = std::memory_order_acquire) const
    {
        U bits = flags.load(mo);
        while (bits != 0)
        {
            U lsb = bits & static_cast<U>(0 - bits);
            bits &= static_cast<U>(~lsb);
            fn(static_cast<T>(lsb));
        }
    }

    std::atomic<U> flags{0};
};

SWC_END_NAMESPACE()
