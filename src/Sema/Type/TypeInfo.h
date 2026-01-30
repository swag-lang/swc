#pragma once
#include "Math/Hash.h"
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE();

class Symbol;
class SymbolEnum;
class SymbolStruct;
class SymbolInterface;
class SymbolAlias;
class SymbolFunction;
class TypeManager;

enum class TypeInfoFlagsE : uint8_t
{
    Zero     = 0,
    Const    = 1 << 0,
    Nullable = 1 << 1,
};
using TypeInfoFlags = EnumFlags<TypeInfoFlagsE>;

enum class TypeInfoKind : uint8_t
{
    Invalid = 0,
    Bool,
    Int,
    Float,
    Char,
    String,
    TypeValue,
    Rune,
    Any,
    Void,
    Null,
    Undefined,
    CString,
    Enum,
    ValuePointer,
    BlockPointer,
    Reference,
    Slice,
    Array,
    Aggregate,
    Struct,
    Interface,
    Alias,
    Function,
    Variadic,
    TypedVariadic,
    TypeInfo,
};

class TypeInfo;
using TypeRef = StrongRef<TypeInfo>;

enum class TypeExpandE : uint32_t
{
    None      = 0,
    Alias     = 1 << 0,
    Enum      = 1 << 1,
    Pointer   = 1 << 2,
    Function  = 1 << 3,
    Array     = 1 << 4,
    Slice     = 1 << 5,
    Variadic  = 1 << 6,
    Aggregate = 1 << 7,
    All       = 0xFFFFFFFF,
};
using TypeExpand = EnumFlags<TypeExpandE>;

class TypeInfo
{
    friend struct TypeInfoHash;
    friend class TypeManager;

public:
    enum class Sign : uint8_t
    {
        Unknown,
        Signed,
        Unsigned
    };

    TypeInfo(const TypeInfo&);
    TypeInfo(TypeInfo&& other) noexcept;
    TypeInfo& operator=(const TypeInfo&);
    TypeInfo& operator=(TypeInfo&& other) noexcept;
    ~TypeInfo();

    bool operator==(const TypeInfo& other) const noexcept;
    Utf8 toName(const TaskContext& ctx) const;
    Utf8 toFamily(const TaskContext& ctx) const;
    Utf8 toArticleFamily(const TaskContext& ctx) const;

    TypeInfoKind  kind() const noexcept { return kind_; }
    TypeInfoFlags flags() const noexcept { return flags_; }
    TypeRef       typeRef() const noexcept { return typeRef_; }
    bool          hasFlag(TypeInfoFlagsE flag) const noexcept { return flags_.has(flag); }
    void          addFlag(TypeInfoFlagsE flag) noexcept { flags_.add(flag); }
    bool          isConst() const noexcept { return flags_.has(TypeInfoFlagsE::Const); }
    bool          isNullable() const noexcept { return flags_.has(TypeInfoFlagsE::Nullable); }

    bool isBool() const noexcept { return kind_ == TypeInfoKind::Bool; }
    bool isChar() const noexcept { return kind_ == TypeInfoKind::Char; }
    bool isString() const noexcept { return kind_ == TypeInfoKind::String; }
    bool isInt() const noexcept { return kind_ == TypeInfoKind::Int; }
    bool isIntUnsized() const noexcept { return kind_ == TypeInfoKind::Int && payloadInt_.bits == 0; }
    bool isFloat() const noexcept { return kind_ == TypeInfoKind::Float; }
    bool isFloatUnsized() const noexcept { return kind_ == TypeInfoKind::Float && payloadFloat_.bits == 0; }
    bool isTypeValue() const noexcept { return kind_ == TypeInfoKind::TypeValue; }
    bool isRune() const noexcept { return kind_ == TypeInfoKind::Rune; }
    bool isAny() const noexcept { return kind_ == TypeInfoKind::Any; }
    bool isVoid() const noexcept { return kind_ == TypeInfoKind::Void; }
    bool isNull() const noexcept { return kind_ == TypeInfoKind::Null; }
    bool isUndefined() const noexcept { return kind_ == TypeInfoKind::Undefined; }
    bool isCString() const noexcept { return kind_ == TypeInfoKind::CString; }
    bool isEnum() const noexcept { return kind_ == TypeInfoKind::Enum; }
    bool isStruct() const noexcept { return kind_ == TypeInfoKind::Struct; }
    bool isInterface() const noexcept { return kind_ == TypeInfoKind::Interface; }
    bool isTypeInfo() const noexcept { return kind_ == TypeInfoKind::TypeInfo; }
    bool isValuePointer() const noexcept { return kind_ == TypeInfoKind::ValuePointer; }
    bool isBlockPointer() const noexcept { return kind_ == TypeInfoKind::BlockPointer; }
    bool isReference() const noexcept { return kind_ == TypeInfoKind::Reference; }
    bool isSlice() const noexcept { return kind_ == TypeInfoKind::Slice; }
    bool isArray() const noexcept { return kind_ == TypeInfoKind::Array; }
    bool isAggregate() const noexcept { return kind_ == TypeInfoKind::Aggregate; }
    bool isAlias() const noexcept { return kind_ == TypeInfoKind::Alias; }
    bool isFunction() const noexcept { return kind_ == TypeInfoKind::Function; }
    bool isVariadic() const noexcept { return kind_ == TypeInfoKind::Variadic; }
    bool isTypedVariadic() const noexcept { return kind_ == TypeInfoKind::TypedVariadic; }

    bool isIntUnsigned() const noexcept { return isInt() && payloadInt_.sign == Sign::Unsigned; }
    bool isIntSigned() const noexcept { return isInt() && payloadInt_.sign == Sign::Signed; }
    bool isIntSignKnown() const noexcept { return isInt() && payloadInt_.sign != Sign::Unknown; }
    bool isIntUnsizedSigned() const noexcept { return isIntUnsized() && isIntSigned(); }
    bool isIntUnsizedUnsigned() const noexcept { return isIntUnsized() && isIntUnsigned(); }
    bool isIntUnsizedUnknownSign() const noexcept { return isIntUnsized() && payloadInt_.sign == Sign::Unknown; }
    bool isType() const noexcept { return isTypeValue() || isEnum() || isStruct() || isInterface() || isTypeInfo(); }
    bool isCharRune() const noexcept { return isChar() || isRune(); }
    bool isIntLike() const noexcept { return isInt() || isCharRune(); }
    bool isPointerLike() const noexcept { return isAnyPointer() || isSlice() || isString() || isCString() || isAny() || isInterface() || isFunction() || isTypeInfo() || isTypeInfo(); }
    bool isConvertibleToBool() const noexcept { return isBool() || isPointerLike() || isIntLike(); }
    bool isScalarNumeric() const noexcept { return isIntLike() || isFloat(); }
    bool isIntLikeUnsigned() const noexcept { return isCharRune() || isIntUnsigned(); }
    bool isConcreteScalar() const noexcept { return isScalarNumeric() && !isIntUnsized() && !isFloatUnsized(); }
    bool isAnyPointer() const noexcept { return isValuePointer() || isBlockPointer(); }
    bool isAnyVariadic() const noexcept { return isVariadic() || isTypedVariadic(); }
    bool isAnyString() const noexcept { return isString() || isCString(); }

    bool isEnumFlags() const noexcept;
    bool isLambdaClosure() const noexcept;
    bool isLambdaMethod() const noexcept;
    bool isAnyTypeInfo(TaskContext& ctx) const noexcept;

    // clang-format off
    Sign                 payloadIntSign() const noexcept { SWC_ASSERT(isInt()); return payloadInt_.sign; }
    uint32_t             payloadIntBits() const noexcept { SWC_ASSERT(isInt()); return payloadInt_.bits; }
    uint32_t             payloadIntLikeBits() const noexcept { SWC_ASSERT(isIntLike()); return isCharRune() ? 32 : payloadInt_.bits; }
    uint32_t             payloadScalarNumericBits() const noexcept { SWC_ASSERT(isScalarNumeric()); return isIntLike() ? payloadIntLikeBits() : payloadFloatBits(); }
    uint32_t             payloadFloatBits() const noexcept { SWC_ASSERT(isFloat()); return payloadFloat_.bits; }
    SymbolEnum&          payloadSymEnum() const noexcept { SWC_ASSERT(isEnum()); return *payloadEnum_.sym; }
    SymbolStruct&        payloadSymStruct() const noexcept { SWC_ASSERT(isStruct()); return *payloadStruct_.sym; }
    SymbolInterface&     payloadSymInterface() const noexcept { SWC_ASSERT(isInterface()); return *payloadInterface_.sym; }
    SymbolAlias&         payloadSymAlias() const noexcept { SWC_ASSERT(isAlias()); return *payloadAlias_.sym; }
    SymbolFunction&      payloadSymFunction() const noexcept { SWC_ASSERT(isFunction()); return *payloadFunction_.sym; }
    TypeRef              payloadTypeRef() const noexcept { SWC_ASSERT(isTypeValue() || isAnyPointer() || isReference() || isSlice() || isAlias() || isTypedVariadic()); return payloadTypeRef_.typeRef; }
    auto&                payloadArrayDims() const noexcept { SWC_ASSERT(isArray()); return payloadArray_.dims; }
    TypeRef              payloadArrayElemTypeRef() const noexcept { SWC_ASSERT(isArray()); return payloadArray_.typeRef; }
    // clang-format on

    TypeRef unwrap(const TaskContext& ctx, TypeRef defaultTypeRef = TypeRef::invalid(), TypeExpand expandFlags = TypeExpandE::All) const noexcept;

    static TypeInfo makeBool();
    static TypeInfo makeChar();
    static TypeInfo makeString(TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeInt(uint32_t bits, Sign sign);
    static TypeInfo makeFloat(uint32_t bits);
    static TypeInfo makeTypeValue(TypeRef typeRef);
    static TypeInfo makeRune();
    static TypeInfo makeAny(TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeVoid();
    static TypeInfo makeNull();
    static TypeInfo makeUndefined();
    static TypeInfo makeCString(TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeTypeInfo();
    static TypeInfo makeEnum(SymbolEnum* sym);
    static TypeInfo makeStruct(SymbolStruct* sym);
    static TypeInfo makeInterface(SymbolInterface* sym);
    static TypeInfo makeAlias(SymbolAlias* sym);
    static TypeInfo makeValuePointer(TypeRef pointeeTypeRef, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeBlockPointer(TypeRef pointeeTypeRef, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeReference(TypeRef pointeeTypeRef, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeSlice(TypeRef pointeeTypeRef, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeArray(const std::vector<uint64_t>& dims, TypeRef elementTypeRef, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeAggregate(TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeFunction(SymbolFunction* sym, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeVariadic();
    static TypeInfo makeTypedVariadic(TypeRef typeRef);

    uint32_t hash() const;
    uint64_t sizeOf(TaskContext& ctx) const;
    uint32_t alignOf(TaskContext& ctx) const;
    bool     isCompleted(TaskContext& ctx) const;
    Symbol*  getSymbolDependency(TaskContext& ctx) const;

private:
    explicit TypeInfo(TypeInfoKind kind, TypeInfoFlags flags = TypeInfoFlagsE::Zero);

    TypeInfoKind  kind_    = TypeInfoKind::Invalid;
    TypeInfoFlags flags_   = TypeInfoFlagsE::Zero;
    TypeRef       typeRef_ = TypeRef::invalid();

    union
    {
        struct
        {
            uint32_t bits;
            Sign     sign;
        } payloadInt_;

        struct
        {
            uint32_t bits;
        } payloadFloat_;

        struct
        {
            TypeRef typeRef;
        } payloadTypeRef_;

        struct
        {
            SymbolEnum* sym;
        } payloadEnum_;

        struct
        {
            SymbolStruct* sym;
        } payloadStruct_;

        struct
        {
            SymbolInterface* sym;
        } payloadInterface_;

        struct
        {
            SymbolAlias* sym;
        } payloadAlias_;

        struct
        {
            std::vector<uint64_t> dims;
            TypeRef               typeRef;
        } payloadArray_;

        struct
        {
            SymbolFunction* sym;
        } payloadFunction_;
    };
};

struct TypeInfoHash
{
    size_t operator()(const TypeInfo& t) const noexcept { return t.hash(); }
};

SWC_END_NAMESPACE();
