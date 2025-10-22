#pragma once

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
