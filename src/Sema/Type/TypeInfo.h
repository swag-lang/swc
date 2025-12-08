#pragma once

SWC_BEGIN_NAMESPACE()

class TypeManager;

enum class TypeInfoKind
{
    Invalid = 0,
    Bool,
    Int,
    Float,
    Char,
    String,
    TypeInfo,
    Rune,
    Any,
    Void,
    CString,
};

class TypeInfo
{
    friend struct TypeInfoHash;
    friend class TypeManager;

    TypeInfo() = delete;
    explicit TypeInfo(TypeInfoKind kind);

    Utf8 toName(const TypeManager& typeMgr) const;

    TypeInfoKind kind_ = TypeInfoKind::Invalid;

    union
    {
        // clang-format off
        struct { uint32_t bits; bool isUnsigned; } asInt;
        struct { uint32_t bits; } asFloat;
        struct { TypeRef typeRef; } asTypeInfo;
        // clang-format on
    };

public:
    bool operator==(const TypeInfo& other) const noexcept;

    TypeInfoKind kind() const noexcept { return kind_; }
    bool         isBool() const noexcept { return kind_ == TypeInfoKind::Bool; }
    bool         isChar() const noexcept { return kind_ == TypeInfoKind::Char; }
    bool         isString() const noexcept { return kind_ == TypeInfoKind::String; }
    bool         isInt() const noexcept { return kind_ == TypeInfoKind::Int; }
    bool         isIntUnsized() const noexcept { return kind_ == TypeInfoKind::Int && asInt.bits == 0; }
    bool         isIntUnsigned() const noexcept { return isInt() && asInt.isUnsigned; }
    bool         isIntSigned() const noexcept { return isInt() && !asInt.isUnsigned; }
    bool         isFloat() const noexcept { return kind_ == TypeInfoKind::Float; }
    bool         isIntFloat() const noexcept { return kind_ == TypeInfoKind::Int || kind_ == TypeInfoKind::Float; }
    bool         isTypeInfo() const noexcept { return kind_ == TypeInfoKind::TypeInfo; }
    bool         isRune() const noexcept { return kind_ == TypeInfoKind::Rune; }
    bool         isAny() const noexcept { return kind_ == TypeInfoKind::Any; }
    bool         isVoid() const noexcept { return kind_ == TypeInfoKind::Void; }
    bool         isCString() const noexcept { return kind_ == TypeInfoKind::CString; }

    bool canBePromoted() const noexcept { return isIntFloat() || isChar(); }

    // clang-format off
    uint32_t intBits() const noexcept { SWC_ASSERT(isInt() || isChar()); return isChar() ? 32 : asInt.bits; }
    uint32_t floatBits() const noexcept { SWC_ASSERT(isFloat()); return asFloat.bits; }
    // clang-format on

    static TypeInfo makeBool();
    static TypeInfo makeChar();
    static TypeInfo makeString();
    static TypeInfo makeInt(uint32_t bits, bool isUnsigned);
    static TypeInfo makeFloat(uint32_t bits);
    static TypeInfo makeTypeInfo(TypeRef typeRef);
    static TypeInfo makeRune();
    static TypeInfo makeAny();
    static TypeInfo makeVoid();
    static TypeInfo makeCString();

    uint32_t hash() const;
};

struct TypeInfoHash
{
    size_t operator()(const TypeInfo& t) const noexcept { return t.hash(); }
};

SWC_END_NAMESPACE()
