#pragma once

SWC_BEGIN_NAMESPACE()

// Base template for strong type wrappers
template<typename>
class StrongRef
{
    uint32_t value_;

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
};

// Tag types for different reference kinds
// clang-format off
struct AstNodeTag{};
struct FileTag{};
struct TokenTag{};
struct SpanTag{};
struct TypeTag{};
struct ConstantTag{};
struct SourceViewTag{};
struct SemaTag{};
// clang-format on

// Type definitions
using AstNodeRef    = StrongRef<AstNodeTag>;
using FileRef       = StrongRef<FileTag>;
using TokenRef      = StrongRef<TokenTag>;
using SpanRef       = StrongRef<SpanTag>;
using TypeRef       = StrongRef<TypeTag>;
using ConstantRef   = StrongRef<ConstantTag>;
using SourceViewRef = StrongRef<SourceViewTag>;
using SemaRef       = StrongRef<SemaTag>;

SWC_END_NAMESPACE()
