#pragma once

SWC_BEGIN_NAMESPACE();

template<typename T>
class StrongRef
{
public:
    StrongRef() = default;

    explicit constexpr StrongRef(uint32_t val) :
        value_(val)
    {
    }

    constexpr uint32_t get() const { return value_; }

    constexpr bool operator==(const StrongRef& other) const { return value_ == other.value_; }
    constexpr bool operator!=(const StrongRef& other) const { return value_ != other.value_; }
    constexpr bool operator<(const StrongRef& other) const { return value_ < other.value_; }
    constexpr bool operator<=(const StrongRef& other) const { return value_ <= other.value_; }
    constexpr bool operator>(const StrongRef& other) const { return value_ > other.value_; }
    constexpr bool operator>=(const StrongRef& other) const { return value_ >= other.value_; }

    constexpr bool             isValid() const { return value_ != std::numeric_limits<uint32_t>::max(); }
    constexpr bool             isInvalid() const { return value_ == std::numeric_limits<uint32_t>::max(); }
    constexpr void             setInvalid() { value_ = std::numeric_limits<uint32_t>::max(); }
    static constexpr StrongRef invalid() { return StrongRef(std::numeric_limits<uint32_t>::max()); }

    StrongRef offset(int offset) { return StrongRef(value_ + offset); }

    // Keep references distinct from booleans and integer values.
    explicit operator bool() const     = delete;
    explicit operator int() const      = delete;
    explicit operator uint32_t() const = delete;

#if SWC_HAS_REF_DEBUG_INFO
    const T* dbgPtr = nullptr;
#endif

private:
    uint32_t value_ = std::numeric_limits<uint32_t>::max();
};

SWC_END_NAMESPACE();

template<typename T>
struct std::hash<swc::StrongRef<T>>
{
    size_t operator()(const swc::StrongRef<T>& v) const noexcept
    {
        return std::hash<uint32_t>{}(v.get());
    }
};
