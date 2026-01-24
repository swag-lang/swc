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
    bool          hasFlag(TypeInfoFlagsE flag) const noexcept { return flags_.has(flag); }
    void          addFlag(TypeInfoFlagsE flag) noexcept { flags_.add(flag); }
    bool          isConst() const noexcept { return flags_.has(TypeInfoFlagsE::Const); }
    bool          isNullable() const noexcept { return flags_.has(TypeInfoFlagsE::Nullable); }

    bool isBool() const noexcept { return kind_ == TypeInfoKind::Bool; }
    bool isChar() const noexcept { return kind_ == TypeInfoKind::Char; }
    bool isString() const noexcept { return kind_ == TypeInfoKind::String; }
    bool isInt() const noexcept { return kind_ == TypeInfoKind::Int; }
    bool isIntUnsized() const noexcept { return kind_ == TypeInfoKind::Int && asInt.bits == 0; }
    bool isFloat() const noexcept { return kind_ == TypeInfoKind::Float; }
    bool isFloatUnsized() const noexcept { return kind_ == TypeInfoKind::Float && asFloat.bits == 0; }
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
    bool isAlias() const noexcept { return kind_ == TypeInfoKind::Alias; }
    bool isFunction() const noexcept { return kind_ == TypeInfoKind::Function; }
    bool isVariadic() const noexcept { return kind_ == TypeInfoKind::Variadic; }
    bool isTypedVariadic() const noexcept { return kind_ == TypeInfoKind::TypedVariadic; }

    bool isIntUnsigned() const noexcept { return isInt() && asInt.sign == Sign::Unsigned; }
    bool isIntSigned() const noexcept { return isInt() && asInt.sign == Sign::Signed; }
    bool isIntSignKnown() const noexcept { return isInt() && asInt.sign != Sign::Unknown; }
    bool isIntUnsizedSigned() const noexcept { return isIntUnsized() && isIntSigned(); }
    bool isIntUnsizedUnsigned() const noexcept { return isIntUnsized() && isIntUnsigned(); }
    bool isIntUnsizedUnknownSign() const noexcept { return isIntUnsized() && asInt.sign == Sign::Unknown; }
    bool isType() const noexcept { return isTypeValue() || isEnum() || isStruct() || isInterface() || isTypeInfo(); }
    bool isCharRune() const noexcept { return isChar() || isRune(); }
    bool isIntLike() const noexcept { return isInt() || isCharRune(); }
    bool isPointerLike() const noexcept { return isAnyPointer() || isSlice() || isString() || isCString() || isAny() || isInterface() || isFunction() || isTypeInfo() || isTypeInfo(); }
    bool isScalarNumeric() const noexcept { return isIntLike() || isFloat(); }
    bool isIntLikeUnsigned() const noexcept { return isCharRune() || isIntUnsigned(); }
    bool isConcreteScalar() const noexcept { return isScalarNumeric() && !isIntUnsized() && !isFloatUnsized(); }
    bool isAnyPointer() const noexcept { return isValuePointer() || isBlockPointer(); }
    bool isAnyVariadic() const noexcept { return isVariadic() || isTypedVariadic(); }
    bool isAnyString() const noexcept { return isString() || isCString(); }

    bool isEnumFlags() const noexcept;
    bool isLambdaClosure() const noexcept;
    bool isLambdaMethod() const noexcept;
    bool isLambdaThrowable() const noexcept;
    bool isConstPointerToAnyTypeInfo(TaskContext& ctx) const noexcept;

    // clang-format off
    Sign                 intSign() const noexcept { SWC_ASSERT(isInt()); return asInt.sign; }
    uint32_t             intBits() const noexcept { SWC_ASSERT(isInt()); return asInt.bits; }
    uint32_t             intLikeBits() const noexcept { SWC_ASSERT(isIntLike()); return isCharRune() ? 32 : asInt.bits; }
    uint32_t             scalarNumericBits() const noexcept { SWC_ASSERT(isScalarNumeric()); return isIntLike() ? intLikeBits() : floatBits(); }
    uint32_t             floatBits() const noexcept { SWC_ASSERT(isFloat()); return asFloat.bits; }
    SymbolEnum&          symEnum() const noexcept { SWC_ASSERT(isEnum()); return *asEnum.sym; }
    SymbolStruct&        symStruct() const noexcept { SWC_ASSERT(isStruct()); return *asStruct.sym; }
    SymbolInterface&     symInterface() const noexcept { SWC_ASSERT(isInterface()); return *asInterface.sym; }
    SymbolAlias&         symAlias() const noexcept { SWC_ASSERT(isAlias()); return *asAlias.sym; }
    SymbolFunction&      symFunction() const noexcept { SWC_ASSERT(isFunction()); return *asFunction.sym; }
    TypeRef              typeRef() const noexcept { SWC_ASSERT(isTypeValue() || isAnyPointer() || isReference() || isSlice() || isAlias() || isTypedVariadic()); return asTypeRef.typeRef; }
    auto&                arrayDims() const noexcept { SWC_ASSERT(isArray()); return asArray.dims; }
    TypeRef              arrayElemTypeRef() const noexcept { SWC_ASSERT(isArray()); return asArray.typeRef; }
    TypeRef              underlyingTypeRef() const noexcept;
    TypeRef              ultimateTypeRef(const TaskContext& ctx, TypeRef defaultTypeRef = TypeRef::invalid()) const noexcept;
    // clang-format on

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

    TypeInfoKind  kind_  = TypeInfoKind::Invalid;
    TypeInfoFlags flags_ = TypeInfoFlagsE::Zero;

    union
    {
        struct
        {
            uint32_t bits;
            Sign     sign;
        } asInt;

        struct
        {
            uint32_t bits;
        } asFloat;

        struct
        {
            TypeRef typeRef;
        } asTypeRef;

        struct
        {
            SymbolEnum* sym;
        } asEnum;

        struct
        {
            SymbolStruct* sym;
        } asStruct;

        struct
        {
            SymbolInterface* sym;
        } asInterface;

        struct
        {
            SymbolAlias* sym;
        } asAlias;

        struct
        {
            std::vector<uint64_t> dims;
            TypeRef               typeRef;
        } asArray;

        struct
        {
            SymbolFunction* sym;
        } asFunction;
    };
};

struct TypeInfoHash
{
    size_t operator()(const TypeInfo& t) const noexcept { return t.hash(); }
};

SWC_END_NAMESPACE();

template<>
struct std::hash<swc::TypeRef>
{
    size_t operator()(const swc::TypeRef& ref) const noexcept
    {
        return swc::Math::hash(ref.get());
    }
};
