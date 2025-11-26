#pragma once

SWC_BEGIN_NAMESPACE()
class TypeManager;

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
    Utf8 toString(const TypeManager& typeMgr, ToStringMode mode = ToStringMode::Diagnostic) const;

    TypeInfoKind kind_ = TypeInfoKind::Invalid;

    union
    {
        // clang-format off
        struct { uint32_t bits; bool isSigned; } int_;
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
    uint32_t     intBits() const noexcept { return int_.bits; }
    bool         isIntSigned() const noexcept { return isInt() && int_.isSigned; }
    bool         isFloat() const noexcept { return kind_ == TypeInfoKind::Float; }

    static TypeInfo makeBool();
    static TypeInfo makeString();
    static TypeInfo makeInt(uint32_t bits, bool isSigned);
    static TypeInfo makeFloat(uint32_t bits);
};

struct TypeInfoHash
{
    size_t operator()(const TypeInfo& t) const noexcept;
};

SWC_END_NAMESPACE()
