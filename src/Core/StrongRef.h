#pragma once

SWC_BEGIN_NAMESPACE()

// Base template for strong type wrappers
template<typename T>
class StrongRef
{
public:
    StrongRef() = default;
    explicit constexpr StrongRef(uint32_t val) :
        value_(val)
    {
    }

    // Explicit getter
    constexpr uint32_t get() const { return value_; }

    // Comparison operators (only with the same type)
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

    // Deleted conversion operators to prevent implicit casts
    explicit operator bool() const     = delete;
    explicit operator int() const      = delete;
    explicit operator uint32_t() const = delete;

#if SWC_HAS_DEBUG_INFO
    void     setDbgPtr(const T* ptr) { dbgPtr_ = ptr; }
    const T* dbgPtr() const { return dbgPtr_; }
#endif

private:
    uint32_t value_;

#if SWC_HAS_DEBUG_INFO
    const T* dbgPtr_ = nullptr;
#endif
};

SWC_END_NAMESPACE()
