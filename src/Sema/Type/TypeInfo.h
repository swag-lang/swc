#pragma once
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE()

class SymbolEnum;
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
    Enum,
};

class TypeInfo;
using TypeRef = StrongRef<TypeInfo>;

class TypeInfo
{
public:
    enum class Sign : uint8_t
    {
        Unknown,
        Signed,
        Unsigned
    };

private:
    friend struct TypeInfoHash;
    friend class TypeManager;

    TypeInfo() = delete;
    explicit TypeInfo(TypeInfoKind kind);

    Utf8 toName(const TaskContext& ctx) const;

    TypeInfoKind kind_ = TypeInfoKind::Invalid;

    union
    {
        // clang-format off
        struct { uint32_t bits; Sign sign; } asInt;
        struct { uint32_t bits; } asFloat;
        struct { TypeRef typeRef; } asTypeInfo;
        struct { SymbolEnum* enumSym; } asEnum;
        // clang-format on
    };

public:
    bool operator==(const TypeInfo& other) const noexcept;

    TypeInfoKind kind() const noexcept { return kind_; }
    bool         isBool() const noexcept { return kind_ == TypeInfoKind::Bool; }
    bool         isChar() const noexcept { return kind_ == TypeInfoKind::Char; }
    bool         isString() const noexcept { return kind_ == TypeInfoKind::String; }

    bool isInt() const noexcept { return kind_ == TypeInfoKind::Int; }
    bool isIntUnsized() const noexcept { return kind_ == TypeInfoKind::Int && asInt.bits == 0; }
    bool isIntUnsigned() const noexcept { return isInt() && asInt.sign == Sign::Unsigned; }
    bool isIntSigned() const noexcept { return isInt() && asInt.sign == Sign::Signed; }
    bool isIntSignKnown() const noexcept { return isInt() && asInt.sign != Sign::Unknown; }
    bool isIntUnsizedSigned() const noexcept { return isIntUnsized() && isIntSigned(); }
    bool isIntUnsizedUnsigned() const noexcept { return isIntUnsized() && isIntUnsigned(); }
    bool isIntUnsizedUnknownSign() const noexcept { return isIntUnsized() && asInt.sign == Sign::Unknown; }

    bool isFloat() const noexcept { return kind_ == TypeInfoKind::Float; }
    bool isFloatUnsized() const noexcept { return kind_ == TypeInfoKind::Float && asFloat.bits == 0; }
    bool isTypeInfo() const noexcept { return kind_ == TypeInfoKind::TypeInfo; }
    bool isRune() const noexcept { return kind_ == TypeInfoKind::Rune; }
    bool isAny() const noexcept { return kind_ == TypeInfoKind::Any; }
    bool isVoid() const noexcept { return kind_ == TypeInfoKind::Void; }
    bool isCString() const noexcept { return kind_ == TypeInfoKind::CString; }

    bool isCharRune() const noexcept { return isChar() || isRune(); }
    bool isIntLike() const noexcept { return isInt() || isCharRune(); }
    bool isScalarNumeric() const noexcept { return isIntLike() || isFloat(); }
    bool isIntLikeUnsigned() const noexcept { return isCharRune() || isIntUnsigned(); }
    bool isConcreteScalar() const noexcept { return isScalarNumeric() && !isIntUnsized() && !isFloatUnsized(); }

    // clang-format off
    Sign intSign() const noexcept { SWC_ASSERT(isInt()); return asInt.sign; }
    uint32_t intBits() const noexcept { SWC_ASSERT(isInt()); return asInt.bits; }
    uint32_t intLikeBits() const noexcept { SWC_ASSERT(isIntLike()); return isCharRune() ? 32 : asInt.bits; }
    uint32_t scalarNumericBits() const noexcept { SWC_ASSERT(isScalarNumeric()); return isIntLike() ? intLikeBits() : floatBits(); }
    uint32_t floatBits() const noexcept { SWC_ASSERT(isFloat()); return asFloat.bits; }
    // clang-format on

    static TypeInfo makeBool();
    static TypeInfo makeChar();
    static TypeInfo makeString();
    static TypeInfo makeInt(uint32_t bits, Sign sign);
    static TypeInfo makeFloat(uint32_t bits);
    static TypeInfo makeTypeInfo(TypeRef typeRef);
    static TypeInfo makeRune();
    static TypeInfo makeAny();
    static TypeInfo makeVoid();
    static TypeInfo makeCString();
    static TypeInfo makeEnum(SymbolEnum* enumSym);

    uint32_t hash() const;
};

struct TypeInfoHash
{
    size_t operator()(const TypeInfo& t) const noexcept { return t.hash(); }
};

SWC_END_NAMESPACE()
