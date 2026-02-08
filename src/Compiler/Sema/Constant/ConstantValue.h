#pragma once
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Math/ApFloat.h"
#include "Support/Math/ApsInt.h"

SWC_BEGIN_NAMESPACE();
class TaskContext;
class TypeInfo;

class ConstantValue;
using ConstantRef = StrongRef<ConstantValue>;

enum class ConstantKind
{
    Invalid,
    Bool,
    Char,
    Rune,
    String,
    Int,
    Float,
    ValuePointer,
    BlockPointer,
    Slice,
    Null,
    Undefined,
    TypeValue,
    EnumValue,
    Struct,
    AggregateStruct,
    Array,
    AggregateArray,
};

class ConstantValue
{
    friend struct ConstantValueHash;
    friend class ConstantManager;

public:
    enum class PayloadOwnership : uint8_t
    {
        Owned,
        Borrowed,
    };

    ConstantValue();
    ConstantValue(const ConstantValue& other);
    ConstantValue(ConstantValue&& other) noexcept;
    ~ConstantValue();

    ConstantValue& operator=(const ConstantValue& other);
    ConstantValue& operator=(ConstantValue&& other) noexcept;

    bool operator==(const ConstantValue& rhs) const noexcept;

    bool eq(const ConstantValue& rhs) const noexcept;
    bool lt(const ConstantValue& rhs) const noexcept;
    bool le(const ConstantValue& rhs) const noexcept;
    bool gt(const ConstantValue& rhs) const noexcept;

    ConstantKind kind() const { return kind_; }
    TypeRef      typeRef() const { return typeRef_; }
    void         setTypeRef(TypeRef ref) { typeRef_ = ref; }
    bool         isValid() const { return kind_ != ConstantKind::Invalid; }
    bool         isBool() const { return kind_ == ConstantKind::Bool; }
    bool         isChar() const { return kind_ == ConstantKind::Char; }
    bool         isRune() const { return kind_ == ConstantKind::Rune; }
    bool         isString() const { return kind_ == ConstantKind::String; }
    bool         isInt() const { return kind_ == ConstantKind::Int; }
    bool         isFloat() const { return kind_ == ConstantKind::Float; }
    bool         isValuePointer() const { return kind_ == ConstantKind::ValuePointer; }
    bool         isBlockPointer() const { return kind_ == ConstantKind::BlockPointer; }
    bool         isSlice() const { return kind_ == ConstantKind::Slice; }
    bool         isNull() const { return kind_ == ConstantKind::Null; }
    bool         isTypeValue() const { return kind_ == ConstantKind::TypeValue; }
    bool         isEnumValue() const { return kind_ == ConstantKind::EnumValue; }
    bool         isStruct() const { return kind_ == ConstantKind::Struct; }
    bool         isStruct(TypeRef typeRef) const { return kind_ == ConstantKind::Struct && typeRef_ == typeRef; }
    bool         isArray() const { return kind_ == ConstantKind::Array; }
    bool         isAggregate() const { return kind_ == ConstantKind::AggregateArray || kind_ == ConstantKind::AggregateStruct; }
    bool         isAggregateStruct() const { return kind_ == ConstantKind::AggregateStruct; }
    bool         isAggregateArray() const { return kind_ == ConstantKind::AggregateArray; }

    bool isPayloadBorrowed() const
    {
        SWC_ASSERT(isStruct() || isArray() || isSlice());
        return payloadBorrowed_;
    }

    bool getBool() const
    {
        SWC_ASSERT(isBool());
        return payloadBool_.val;
    }

    char32_t getChar() const
    {
        SWC_ASSERT(isChar());
        return payloadCharRune_.val;
    }

    char32_t getRune() const
    {
        SWC_ASSERT(isRune());
        return payloadCharRune_.val;
    }

    std::string_view getString() const
    {
        SWC_ASSERT(isString());
        return payloadString_.val;
    }

    const ApsInt& getInt() const
    {
        SWC_ASSERT(isInt());
        return payloadInt_.val;
    }

    const ApFloat& getFloat() const
    {
        SWC_ASSERT(isFloat());
        return payloadFloat_.val;
    }

    uint64_t getValuePointer() const
    {
        SWC_ASSERT(isValuePointer());
        return payloadPointer_.val;
    }

    uint64_t getBlockPointer() const
    {
        SWC_ASSERT(isBlockPointer());
        return payloadPointer_.val;
    }

    ByteSpan getSlice() const
    {
        SWC_ASSERT(isSlice());
        return payloadSlice_.val;
    }

    TypeRef getTypeValue() const
    {
        SWC_ASSERT(isTypeValue());
        return payloadTypeValue_.val;
    }

    ConstantRef getEnumValue() const
    {
        SWC_ASSERT(isEnumValue());
        return payloadEnumValue_.val;
    }

    ByteSpan getStruct() const
    {
        SWC_ASSERT(isStruct());
        return payloadStruct_.val;
    }

    ByteSpan getArray() const
    {
        SWC_ASSERT(isArray());
        return payloadArray_.val;
    }

    const std::vector<ConstantRef>& getAggregate() const
    {
        SWC_ASSERT(isAggregate());
        return payloadAggregate_.val;
    }

    const std::vector<ConstantRef>& getAggregateArray() const
    {
        SWC_ASSERT(isAggregateArray());
        return payloadAggregate_.val;
    }

    const std::vector<ConstantRef>& getAggregateStruct() const
    {
        SWC_ASSERT(isAggregateStruct());
        return payloadAggregate_.val;
    }

    template<typename T>
    const T* getStruct(TypeRef typeRef) const
    {
        SWC_ASSERT(isStruct(typeRef));
        return reinterpret_cast<const T*>(payloadStruct_.val.data());
    }

    const TypeInfo& type(const TaskContext& ctx) const;

    static ConstantValue makeBool(const TaskContext& ctx, bool value);
    static ConstantValue makeNull(const TaskContext& ctx);
    static ConstantValue makeUndefined(const TaskContext& ctx);
    static ConstantValue makeString(const TaskContext& ctx, std::string_view value);
    static ConstantValue makeChar(const TaskContext& ctx, char32_t value);
    static ConstantValue makeRune(const TaskContext& ctx, char32_t value);
    static ConstantValue makeTypeValue(TaskContext& ctx, TypeRef value);
    static ConstantValue makeInt(const TaskContext& ctx, const ApsInt& value, uint32_t bitWidth, TypeInfo::Sign sign);
    static ConstantValue makeIntUnsized(const TaskContext& ctx, const ApsInt& value, TypeInfo::Sign sign);
    static ConstantValue makeFloat(const TaskContext& ctx, const ApFloat& value, uint32_t bitWidth);
    static ConstantValue makeFloatUnsized(const TaskContext& ctx, const ApFloat& value);
    static ConstantValue makeFromIntLike(const TaskContext& ctx, const ApsInt& v, const TypeInfo& ty);
    static ConstantValue makeEnumValue(const TaskContext& ctx, ConstantRef valueCst, TypeRef typeRef);
    static ConstantValue makeStruct(const TaskContext& ctx, TypeRef typeRef, ByteSpan bytes);
    static ConstantValue makeStructBorrowed(const TaskContext& ctx, TypeRef typeRef, ByteSpan bytes);
    static ConstantValue makeArray(const TaskContext& ctx, TypeRef typeRef, ByteSpan bytes);
    static ConstantValue makeArrayBorrowed(const TaskContext& ctx, TypeRef typeRef, ByteSpan bytes);
    static ConstantValue makeAggregateStruct(TaskContext& ctx, const std::span<IdentifierRef>& names, const std::span<ConstantRef>& values, const std::span<SourceCodeRef>& fieldRefs = {});
    static ConstantValue makeAggregateArray(TaskContext& ctx, const std::span<ConstantRef>& values, const std::span<SourceCodeRef>& fieldRefs = {});
    static ConstantValue makeValuePointer(TaskContext& ctx, TypeRef typeRef, uint64_t value, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static ConstantValue makeBlockPointer(TaskContext& ctx, TypeRef typeRef, uint64_t value, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static ConstantValue makeSlice(TaskContext& ctx, TypeRef typeRef, ByteSpan bytes, TypeInfoFlags flags = TypeInfoFlagsE::Zero);
    static ConstantValue makeSliceBorrowed(TaskContext& ctx, TypeRef typeRef, ByteSpan bytes, TypeInfoFlags flags = TypeInfoFlagsE::Zero);

    static ConstantValue make(TaskContext& ctx, const void* valuePtr, TypeRef typeRef);
    static ConstantValue make(TaskContext& ctx, const void* valuePtr, TypeRef typeRef, PayloadOwnership ownership);

    template<typename T>
    static ConstantValue makeIntSized(const TaskContext& ctx, T value)
    {
        constexpr bool isUnsigned = std::is_unsigned_v<T>;
        const ApsInt   v(static_cast<uint64_t>(value), sizeof(T) * 8, isUnsigned);
        return makeInt(ctx, v, sizeof(T) * 8, isUnsigned ? TypeInfo::Sign::Unsigned : TypeInfo::Sign::Signed);
    }

    uint32_t hash() const noexcept;
    ApsInt   getIntLike() const;
    bool     ge(const ConstantValue& rhs) const noexcept;
    Utf8     toString(const TaskContext& ctx) const;

    void setPayloadSlice(ByteSpan bytes) { payloadSlice_.val = bytes; }
    void setPayloadStruct(ByteSpan bytes) { payloadStruct_.val = bytes; }
    void setPayloadArray(ByteSpan bytes) { payloadArray_.val = bytes; }

private:
    ConstantKind kind_    = ConstantKind::Invalid;
    TypeRef      typeRef_ = TypeRef::invalid();

    // For Struct/Array/Slice only. When borrowed, the ByteSpan points to external storage whose lifetime must outlive
    // the constant (typically memory already stored in a `DataSegment`).
    bool payloadBorrowed_ = false;

    union
    {
        struct
        {
            std::string_view val;
        } payloadString_;

        struct
        {
            ByteSpan val;
        } payloadStruct_;

        struct
        {
            ByteSpan val;
        } payloadArray_;

        struct
        {
            char32_t val;
        } payloadCharRune_;

        struct
        {
            bool val;
        } payloadBool_;

        struct
        {
            ApsInt val;
        } payloadInt_;

        struct
        {
            ApFloat val;
        } payloadFloat_;

        struct
        {
            uint64_t val;
        } payloadPointer_;

        struct
        {
            ByteSpan val;
        } payloadSlice_;

        struct
        {
            TypeRef val;
        } payloadTypeValue_;

        struct
        {
            ConstantRef val;
        } payloadEnumValue_;

        struct
        {
            std::vector<ConstantRef> val;
        } payloadAggregate_;
    };
};

struct ConstantValueHash
{
    size_t operator()(const ConstantValue& v) const noexcept { return v.hash(); }
};

SWC_END_NAMESPACE();
