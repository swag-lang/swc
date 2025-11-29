#pragma once

SWC_BEGIN_NAMESPACE()

enum class TypeInfoKind
{
    Invalid = 0,
    Bool,
    Int,
    Float,
    String,
};

class TypeInfo
{
    friend struct TypeInfoHash;
    friend class TypeManager;

public:
    enum class ToStringMode
    {
        Diagnostic,
        Count,
    };

private:
    TypeInfo() = delete;
    explicit TypeInfo(TypeInfoKind kind);

    Utf8 toString(ToStringMode mode = ToStringMode::Diagnostic) const;

    TypeInfoKind kind_ = TypeInfoKind::Invalid;

    union
    {
        // clang-format off
        struct { uint32_t bits; bool isUnsigned; } int_;
        struct { uint32_t bits; } float_;
        struct { std::string_view string; } string_;
        // clang-format on
    };

public:
    bool operator==(const TypeInfo& other) const noexcept;

    TypeInfoKind kind() const noexcept { return kind_; }
    bool         isBool() const noexcept { return kind_ == TypeInfoKind::Bool; }
    bool         isString() const noexcept { return kind_ == TypeInfoKind::String; }
    bool         isInt() const noexcept { return kind_ == TypeInfoKind::Int; }
    bool         isInt0() const noexcept { return kind_ == TypeInfoKind::Int && int_.bits == 0; }
    bool         isIntUnsigned() const noexcept { return isInt() && int_.isUnsigned; }
    bool         isIntSigned() const noexcept { return isInt() && !int_.isUnsigned; }
    bool         isFloat() const noexcept { return kind_ == TypeInfoKind::Float; }
    bool         isIntFloat() const noexcept { return kind_ == TypeInfoKind::Int || kind_ == TypeInfoKind::Float; }
    bool         canBePromoted() const noexcept { return isIntFloat(); }

    // clang-format off
    uint32_t intBits() const noexcept { SWC_ASSERT(isInt()); return int_.bits; }
    uint32_t floatBits() const noexcept { SWC_ASSERT(isFloat()); return float_.bits; }
    // clang-format on

    static TypeInfo makeBool();
    static TypeInfo makeString();
    static TypeInfo makeInt(uint32_t bits, bool isUnsigned);
    static TypeInfo makeFloat(uint32_t bits);
};

struct TypeInfoHash
{
    size_t operator()(const TypeInfo& t) const noexcept;
};

SWC_END_NAMESPACE()
