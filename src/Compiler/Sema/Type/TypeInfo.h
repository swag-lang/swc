#pragma once
#include <array>
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Support/Core/Flags.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Utf8.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

class Symbol;
class SymbolEnum;
class SymbolStruct;
class SymbolInterface;
class SymbolAlias;
class SymbolFunction;
class SymbolNamespace;
class TaskContext;
class TypeManager;
class TypeInfo;

namespace TypeRuntimeHash
{
    uint32_t compute(const TaskContext& ctx, const TypeInfo& typeInfo);
}

enum class TypeInfoFlagsE : uint8_t
{
    Zero     = 0,
    Const    = 1 << 0,
    Nullable = 1 << 1,
};
using TypeInfoFlags = EnumFlags<TypeInfoFlagsE>;

enum class TypeInfoKindFlagsE : uint16_t
{
    Zero                = 0,
    AliasOrEnum         = 1 << 0,
    AnyPointerOrCString = 1 << 1,
    AnyPointer          = 1 << 2,
    PointerOrReference  = 1 << 3,
    Type                = 1 << 4,
    Aggregate           = 1 << 5,
    IntLike             = 1 << 6,
    NumericIntLike      = 1 << 7,
    AnyVariadic         = 1 << 8,
    PointerLike         = 1 << 9,
    StringOrSlice       = 1 << 10,
    AnyString           = 1 << 11,
    StructOrArray       = 1 << 12,
    ArrayOrSlice        = 1 << 13,
    StructOrAggregateStruct = 1 << 14,
    ArrayOrAggregateArray   = 1 << 15,
};
using TypeInfoKindFlags = EnumFlags<TypeInfoKindFlagsE>;

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
    CString,
    Enum,
    ValuePointer,
    BlockPointer,
    MoveReference,
    Slice,
    Array,
    AggregateStruct,
    AggregateArray,
    Struct,
    Interface,
    Alias,
    Function,
    Variadic,
    TypedVariadic,
    CodeBlock,
    TypeInfo,
    Simd,
};

namespace TypeInfoKindFlagsDetail
{
    // Kind-only query bits are shared here so TypeInfo gains no per-instance storage.
    constexpr size_t KIND_COUNT = static_cast<size_t>(TypeInfoKind::Simd) + 1;

    constexpr TypeInfoKindFlags get(const TypeInfoKind kind) noexcept
    {
        TypeInfoKindFlags flags = TypeInfoKindFlagsE::Zero;
        switch (kind)
        {
            case TypeInfoKind::Bool:
                flags.add(TypeInfoKindFlagsE::NumericIntLike);
                break;
            case TypeInfoKind::Int:
                flags.add(TypeInfoKindFlagsE::IntLike);
                flags.add(TypeInfoKindFlagsE::NumericIntLike);
                break;
            case TypeInfoKind::Char:
            case TypeInfoKind::Rune:
                flags.add(TypeInfoKindFlagsE::IntLike);
                flags.add(TypeInfoKindFlagsE::NumericIntLike);
                break;
            case TypeInfoKind::String:
                flags.add(TypeInfoKindFlagsE::PointerLike);
                flags.add(TypeInfoKindFlagsE::StringOrSlice);
                flags.add(TypeInfoKindFlagsE::AnyString);
                break;
            case TypeInfoKind::TypeValue:
                flags.add(TypeInfoKindFlagsE::Type);
                break;
            case TypeInfoKind::Any:
                flags.add(TypeInfoKindFlagsE::PointerLike);
                break;
            case TypeInfoKind::CString:
                flags.add(TypeInfoKindFlagsE::AnyPointerOrCString);
                flags.add(TypeInfoKindFlagsE::PointerLike);
                flags.add(TypeInfoKindFlagsE::AnyString);
                break;
            case TypeInfoKind::Enum:
                flags.add(TypeInfoKindFlagsE::AliasOrEnum);
                flags.add(TypeInfoKindFlagsE::Type);
                break;
            case TypeInfoKind::ValuePointer:
            case TypeInfoKind::BlockPointer:
                flags.add(TypeInfoKindFlagsE::AnyPointerOrCString);
                flags.add(TypeInfoKindFlagsE::AnyPointer);
                flags.add(TypeInfoKindFlagsE::PointerOrReference);
                flags.add(TypeInfoKindFlagsE::PointerLike);
                break;
            case TypeInfoKind::MoveReference:
                flags.add(TypeInfoKindFlagsE::PointerOrReference);
                break;
            case TypeInfoKind::Slice:
                flags.add(TypeInfoKindFlagsE::PointerLike);
                flags.add(TypeInfoKindFlagsE::StringOrSlice);
                flags.add(TypeInfoKindFlagsE::ArrayOrSlice);
                break;
            case TypeInfoKind::AggregateStruct:
                flags.add(TypeInfoKindFlagsE::StructOrAggregateStruct);
                flags.add(TypeInfoKindFlagsE::Aggregate);
                break;
            case TypeInfoKind::AggregateArray:
                flags.add(TypeInfoKindFlagsE::ArrayOrAggregateArray);
                flags.add(TypeInfoKindFlagsE::Aggregate);
                break;
            case TypeInfoKind::Struct:
                flags.add(TypeInfoKindFlagsE::Type);
                flags.add(TypeInfoKindFlagsE::StructOrArray);
                flags.add(TypeInfoKindFlagsE::StructOrAggregateStruct);
                break;
            case TypeInfoKind::Interface:
                flags.add(TypeInfoKindFlagsE::Type);
                flags.add(TypeInfoKindFlagsE::PointerLike);
                break;
            case TypeInfoKind::Alias:
                flags.add(TypeInfoKindFlagsE::AliasOrEnum);
                break;
            case TypeInfoKind::Function:
                flags.add(TypeInfoKindFlagsE::PointerLike);
                break;
            case TypeInfoKind::TypeInfo:
                flags.add(TypeInfoKindFlagsE::Type);
                flags.add(TypeInfoKindFlagsE::PointerLike);
                break;
            case TypeInfoKind::Variadic:
            case TypeInfoKind::TypedVariadic:
                flags.add(TypeInfoKindFlagsE::AnyVariadic);
                break;
            case TypeInfoKind::Invalid:
            case TypeInfoKind::Float:
            case TypeInfoKind::Void:
            case TypeInfoKind::Null:
            case TypeInfoKind::CodeBlock:
            case TypeInfoKind::Simd:
                break;
            case TypeInfoKind::Array:
                flags.add(TypeInfoKindFlagsE::StructOrArray);
                flags.add(TypeInfoKindFlagsE::ArrayOrSlice);
                flags.add(TypeInfoKindFlagsE::ArrayOrAggregateArray);
                break;
        }
        return flags;
    }

    inline constexpr std::array<TypeInfoKindFlags, KIND_COUNT> BY_KIND = [] {
        std::array<TypeInfoKindFlags, KIND_COUNT> result{};
        for (size_t i = 0; i < result.size(); ++i)
            result[i] = get(static_cast<TypeInfoKind>(i));
        return result;
    }();
}

enum class TypeExpandE : uint32_t
{
    None     = 0,
    Alias    = 1 << 0,
    Enum     = 1 << 1,
    Pointer  = 1 << 2,
    Function = 1 << 3,
    Array    = 1 << 4,
    Slice    = 1 << 5,
    Variadic = 1 << 6,
    All      = 0xFFFFFFFF,
};
using TypeExpand = EnumFlags<TypeExpandE>;

class TypeInfo
{
    friend struct TypeInfoHash;
    friend class TypeManager;
    friend uint32_t TypeRuntimeHash::compute(const TaskContext& ctx, const TypeInfo& typeInfo);

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
    Utf8 toFullName(const TaskContext& ctx) const;
    Utf8 toFamily(const TaskContext& ctx) const;
    Utf8 toArticleFamily(const TaskContext& ctx) const;

    TypeInfoKind  kind() const noexcept { return kind_; }
    TypeInfoFlags flags() const noexcept { return flags_; }
    TypeRef       typeRef() const noexcept { return typeRef_; }
    bool          hasFlag(TypeInfoFlagsE flag) const noexcept { return flags_.has(flag); }
    void          addFlag(TypeInfoFlagsE flag) noexcept { flags_.add(flag); }
    void          removeFlag(TypeInfoFlagsE flag) noexcept { flags_.remove(flag); }

    bool isConst() const noexcept { return flags_.has(TypeInfoFlagsE::Const); }
    bool isNullable() const noexcept { return flags_.has(TypeInfoFlagsE::Nullable); }
    // Non-null is the default for nullable-capable types: a bare `*T`, `string`, `[..] T`,
    // `any`, `cstring`, `[*] T` or `typeinfo` cannot hold null unless qualified with nullable.
    bool isNonNullable() const noexcept { return isSupportsNullableQualifier() && !flags_.has(TypeInfoFlagsE::Nullable); }
    bool isAggregateStruct() const noexcept { return kind_ == TypeInfoKind::AggregateStruct; }
    bool isAggregateArray() const noexcept { return kind_ == TypeInfoKind::AggregateArray; }
    bool isStructOrAggregateStruct() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::StructOrAggregateStruct); }
    bool isArrayOrAggregateArray() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::ArrayOrAggregateArray); }
    bool isBool() const noexcept { return kind_ == TypeInfoKind::Bool; }
    bool isChar() const noexcept { return kind_ == TypeInfoKind::Char; }
    bool isString() const noexcept { return kind_ == TypeInfoKind::String; }
    bool isInt() const noexcept { return kind_ == TypeInfoKind::Int; }
    bool isFloat() const noexcept { return kind_ == TypeInfoKind::Float; }
    bool isTypeValue() const noexcept { return kind_ == TypeInfoKind::TypeValue; }
    bool isRune() const noexcept { return kind_ == TypeInfoKind::Rune; }
    bool isAny() const noexcept { return kind_ == TypeInfoKind::Any; }
    bool isVoid() const noexcept { return kind_ == TypeInfoKind::Void; }
    bool isNull() const noexcept { return kind_ == TypeInfoKind::Null; }
    bool isCString() const noexcept { return kind_ == TypeInfoKind::CString; }
    bool isEnum() const noexcept { return kind_ == TypeInfoKind::Enum; }
    bool isStruct() const noexcept { return kind_ == TypeInfoKind::Struct; }
    bool isInterface() const noexcept { return kind_ == TypeInfoKind::Interface; }
    bool isTypeInfo() const noexcept { return kind_ == TypeInfoKind::TypeInfo; }
    bool isValuePointer() const noexcept { return kind_ == TypeInfoKind::ValuePointer; }
    bool isBlockPointer() const noexcept { return kind_ == TypeInfoKind::BlockPointer; }
    bool isReference() const noexcept { return kind_ == TypeInfoKind::MoveReference; }
    bool isMoveReference() const noexcept { return kind_ == TypeInfoKind::MoveReference; }
    bool isSlice() const noexcept { return kind_ == TypeInfoKind::Slice; }
    bool isArray() const noexcept { return kind_ == TypeInfoKind::Array; }
    bool isAggregate() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::Aggregate); }
    bool isAlias() const noexcept { return kind_ == TypeInfoKind::Alias; }
    bool isFunction() const noexcept { return kind_ == TypeInfoKind::Function; }
    bool isVariadic() const noexcept { return kind_ == TypeInfoKind::Variadic; }
    bool isTypedVariadic() const noexcept { return kind_ == TypeInfoKind::TypedVariadic; }
    bool isCodeBlock() const noexcept { return kind_ == TypeInfoKind::CodeBlock; }
    bool isIntUnsized() const noexcept { return kind_ == TypeInfoKind::Int && payloadInt_.bits == 0; }
    bool isFloatUnsized() const noexcept { return kind_ == TypeInfoKind::Float && payloadFloat_.bits == 0; }
    bool isScalarUnsized() const noexcept { return isIntUnsized() || isFloatUnsized(); }
    bool isIntUnsigned() const noexcept { return isInt() && payloadInt_.sign == Sign::Unsigned; }
    bool isIntSigned() const noexcept { return isInt() && payloadInt_.sign == Sign::Signed; }
    bool isIntSignKnown() const noexcept { return isInt() && payloadInt_.sign != Sign::Unknown; }
    bool isIntUnsizedSigned() const noexcept { return isIntUnsized() && isIntSigned(); }
    bool isIntUnsizedUnsigned() const noexcept { return isIntUnsized() && isIntUnsigned(); }
    bool isIntUnsizedUnknownSign() const noexcept { return isIntUnsized() && payloadInt_.sign == Sign::Unknown; }
    bool isType() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::Type); }
    bool isAliasOrEnum() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::AliasOrEnum); }
    bool isCharRune() const noexcept { return isChar() || isRune(); }
    bool isIntLike() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::IntLike); }
    bool isNumericIntLike() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::NumericIntLike); }
    bool isNumericSigned() const noexcept { return isIntSigned(); }
    bool isPointerLike() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::PointerLike); }
    bool isConvertibleToBool() const noexcept { return isBool() || isPointerLike() || isIntLike() || isFloat() || isEnumFlags(); }
    bool isScalarNumeric() const noexcept { return isIntLike() || isFloat(); }
    bool isIntLikeUnsigned() const noexcept { return isCharRune() || isIntUnsigned(); }
    bool isBoolOrIntLikeUnsigned() const noexcept { return isBool() || isIntLikeUnsigned(); }
    bool usesUnsignedConditions() const noexcept { return isFloat() || isIntLikeUnsigned() || isPointerLike() || isBool() || isEnum(); }
    bool isConcreteScalar() const noexcept { return isScalarNumeric() && !isIntUnsized() && !isFloatUnsized(); }
    bool isAnyPointer() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::AnyPointer); }
    bool isNonNullValuePointer() const noexcept { return isValuePointer() && !isNullable(); }
    bool isPointerOrReference() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::PointerOrReference); }
    bool isAnyPointerOrCString() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::AnyPointerOrCString); }
    bool isReferenceOrNonNullValuePointer() const noexcept { return isReference() || isNonNullValuePointer(); }
    bool isPointerLikeOrReference() const noexcept { return isPointerLike() || isReference(); }
    bool isAnyVariadic() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::AnyVariadic); }
    bool isAnyString() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::AnyString); }
    bool isStringOrSlice() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::StringOrSlice); }
    bool isStructOrArray() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::StructOrArray); }
    bool hasDirectPayloadTypeRef() const noexcept { return isTypeValue() || isPointerOrReference() || isSlice() || isTypedVariadic() || isCodeBlock(); }
    bool isArrayOrSlice() const noexcept { return hasKindFlag(TypeInfoKindFlagsE::ArrayOrSlice); }
    bool isArrayOrSimd() const noexcept { return isArray() || isSimd(); }
    bool isIndirectIndexable() const noexcept { return isPointerOrReference() || isSlice() || isTypedVariadic(); }
    bool isIndexable() const noexcept { return isArrayOrSlice() || isString() || isCString() || isAnyVariadic(); }
    bool isSimd() const noexcept { return kind_ == TypeInfoKind::Simd; }

    bool isSupportsNullableQualifier() const noexcept;
    bool isEnumFlags() const noexcept;
    bool isLambdaClosure() const noexcept;
    bool isLambdaMethod() const noexcept;
    bool isAnyTypeInfo(const TaskContext& ctx) const noexcept;
    bool isPointerLikeAliasAware(const TaskContext& ctx) const noexcept;
    bool isConvertibleToBoolAliasAware(const TaskContext& ctx) const noexcept;

    Sign payloadIntSign() const noexcept
    {
        SWC_ASSERT(isInt());
        return payloadInt_.sign;
    }

    uint32_t payloadIntBits() const noexcept
    {
        SWC_ASSERT(isInt());
        return payloadInt_.bits;
    }

    uint32_t payloadIntBitsOr(uint32_t defaultBits) const noexcept
    {
        const uint32_t bits = payloadIntBits();
        return bits ? bits : defaultBits;
    }

    uint32_t payloadIntLikeBits() const noexcept
    {
        SWC_ASSERT(isIntLike());
        return isCharRune() ? 32 : payloadInt_.bits;
    }

    uint32_t payloadIntLikeBitsOr(uint32_t defaultBits) const noexcept
    {
        const uint32_t bits = payloadIntLikeBits();
        return bits ? bits : defaultBits;
    }

    uint32_t payloadScalarNumericBits() const noexcept
    {
        SWC_ASSERT(isScalarNumeric());
        return isIntLike() ? payloadIntLikeBits() : payloadFloatBits();
    }

    uint32_t payloadScalarNumericBitsOr(uint32_t defaultBits) const noexcept
    {
        const uint32_t bits = payloadScalarNumericBits();
        return bits ? bits : defaultBits;
    }

    uint32_t payloadFloatBits() const noexcept
    {
        SWC_ASSERT(isFloat());
        return payloadFloat_.bits;
    }

    uint32_t payloadFloatBitsOr(uint32_t defaultBits) const noexcept
    {
        const uint32_t bits = payloadFloatBits();
        return bits ? bits : defaultBits;
    }

    SymbolEnum& payloadSymEnum() const noexcept
    {
        SWC_ASSERT(isEnum());
        return *(payloadEnum_.sym);
    }

    SymbolStruct& payloadSymStruct() const noexcept
    {
        SWC_ASSERT(isStruct());
        return *(payloadStruct_.sym);
    }

    SymbolInterface& payloadSymInterface() const noexcept
    {
        SWC_ASSERT(isInterface());
        return *(payloadInterface_.sym);
    }

    SymbolAlias& payloadSymAlias() const noexcept
    {
        SWC_ASSERT(isAlias());
        return *(payloadAlias_.sym);
    }

    SymbolFunction& payloadSymFunction() const noexcept
    {
        SWC_ASSERT(isFunction());
        return *(payloadFunction_.sym);
    }

    auto& payloadArrayDims() const noexcept
    {
        SWC_ASSERT(isArray());
        return payloadArray_.dims;
    }

    const auto& payloadArrayIndexTypeRefs() const noexcept
    {
        SWC_ASSERT(isArray());
        return payloadArray_.indexTypeRefs;
    }

    TypeRef payloadArrayIndexTypeRef(size_t dimension = 0) const noexcept
    {
        SWC_ASSERT(isArray());
        if (payloadArray_.indexTypeRefs.empty())
            return TypeRef::invalid();
        SWC_ASSERT(dimension < payloadArray_.indexTypeRefs.size());
        return payloadArray_.indexTypeRefs[dimension];
    }

    TypeRef payloadArrayElemTypeRef() const noexcept
    {
        SWC_ASSERT(isArray());
        return payloadArray_.typeRef;
    }

    const auto& payloadAggregate() const noexcept
    {
        SWC_ASSERT(isAggregate());
        return payloadAggregate_;
    }

    TypeRef payloadSimdLaneTypeRef() const noexcept
    {
        SWC_ASSERT(isSimd());
        return payloadSimd_.laneTypeRef;
    }

    uint32_t payloadSimdLaneCount() const noexcept
    {
        SWC_ASSERT(isSimd());
        return payloadSimd_.laneCount;
    }

    bool    tryGetAggregateMemberIndexByName(size_t& outIndex, const TaskContext& ctx, IdentifierRef name) const noexcept;
    TypeRef unwrapAliasEnum(const TaskContext& ctx, TypeRef defaultTypeRef = TypeRef::invalid()) const noexcept;
    TypeRef unwrap(const TaskContext& ctx, TypeRef defaultTypeRef = TypeRef::invalid(), TypeExpand expandFlags = TypeExpandE::All) const noexcept;
    TypeRef payloadTypeRef() const noexcept;
    TypeRef dereferenceTypeRef(const TaskContext& ctx) const;

    // Null means expansion kept this type; callers retain their original metadata.
    // Keep the ordinary-type gate inline, and carry the metadata through the wrapped path.
    const TypeInfo* unwrapAliasType(const TaskContext& ctx) const noexcept
    {
        SWC_ASSERT(typeRef_.isValid());
        return isAlias() ? resolveAliasType<false>(ctx) : nullptr;
    }

    const TypeInfo* unwrapAliasEnumType(const TaskContext& ctx) const noexcept
    {
        SWC_ASSERT(typeRef_.isValid());
        return isAliasOrEnum() ? resolveAliasType<true>(ctx) : nullptr;
    }

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
    static TypeInfo makeCString(TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeTypeInfo(TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeEnum(SymbolEnum* sym);
    static TypeInfo makeStruct(SymbolStruct* sym);
    static TypeInfo makeInterface(SymbolInterface* sym, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeAlias(SymbolAlias* sym);
    static TypeInfo makeValuePointer(TypeRef pointeeTypeRef, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeBlockPointer(TypeRef pointeeTypeRef, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeMoveReference(TypeRef pointeeTypeRef, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeSlice(TypeRef pointeeTypeRef, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeArray(const std::span<const uint64_t>& dims,
                              TypeRef                          elementTypeRef,
                              TypeInfoFlags                    flags         = TypeInfoFlagsE::Zero,
                              const std::span<const TypeRef>&  indexTypeRefs = {});
    static TypeInfo makeAggregateStruct(const std::span<const IdentifierRef>& names, const std::span<const TypeRef>& types);
    static TypeInfo makeAggregateArray(const std::span<const TypeRef>& types);
    static TypeInfo makeFunction(SymbolFunction* sym, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static TypeInfo makeVariadic();
    static TypeInfo makeTypedVariadic(TypeRef typeRef);
    static TypeInfo makeCodeBlock(TypeRef typeRef);
    static TypeInfo makeSimd(TypeRef laneTypeRef, uint32_t laneCount, TypeInfoFlags flags = TypeInfoFlagsE::Zero);

    uint32_t hash() const;
    uint32_t runtimeHash(const TaskContext& ctx) const;

    // A seed lets nested arrays continue the same sequence of dimension multiplications.
    uint64_t arrayTotalElementCount(uint64_t count = 1) const;
    uint64_t sliceCountFromArrayCast(TaskContext& ctx, const TypeInfo& dstElementType) const;

    uint64_t sizeOf(TaskContext& ctx) const;
    uint32_t alignOf(TaskContext& ctx) const;
    bool     isCompleted(TaskContext& ctx) const;
    Symbol*  getSymbol() const;
    Symbol*  getNotCompletedSymbol(TaskContext& ctx) const;

private:
    explicit TypeInfo(TypeInfoKind kind, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    bool hasKindFlag(TypeInfoKindFlagsE flag) const noexcept
    {
        return TypeInfoKindFlagsDetail::BY_KIND[static_cast<size_t>(kind_)].has(flag);
    }
    template<bool IncludeEnum>
    const TypeInfo* resolveAliasType(const TaskContext& ctx) const noexcept;

    // The parts of hash() that an array or aggregate payload contributes, so a type can be hashed
    // from its parts before one is built.
    static uint32_t hashHeader(TypeInfoKind kind, TypeInfoFlags flags);
    static uint32_t hashArrayPayload(uint32_t h, std::span<const uint64_t> dims, TypeRef elementTypeRef, std::span<const TypeRef> indexTypeRefs);
    static uint32_t hashAggregatePayload(uint32_t h, TypeInfoKind kind, std::span<const TypeRef> types, std::span<const IdentifierRef> names);

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
            std::vector<TypeRef>  indexTypeRefs;
            TypeRef               typeRef;
        } payloadArray_;

        struct
        {
            std::vector<TypeRef>       types;
            std::vector<IdentifierRef> names;
        } payloadAggregate_;

        struct
        {
            SymbolFunction* sym;
        } payloadFunction_;

        struct
        {
            TypeRef  laneTypeRef;
            uint32_t laneCount;
        } payloadSimd_;
    };
};

struct TypeInfoHash
{
    size_t operator()(const TypeInfo& t) const noexcept { return t.hash(); }
};

SWC_END_NAMESPACE();
