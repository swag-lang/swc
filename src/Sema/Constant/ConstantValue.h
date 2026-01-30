#pragma once
#include "Math/ApFloat.h"
#include "Math/ApsInt.h"
#include "Sema/Type/TypeInfo.h"

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
    Aggregate,
};

class ConstantValue
{
    friend struct ConstantValueHash;
    friend class ConstantManager;

public:
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
    bool         isAggregate() const { return kind_ == ConstantKind::Aggregate; }

    // clang-format off
    bool getBool() const { SWC_ASSERT(isBool()); return asBool.val; }
    char32_t getChar() const { SWC_ASSERT(isChar()); return asCharRune.val; }
    char32_t getRune() const { SWC_ASSERT(isRune()); return asCharRune.val; }
    std::string_view getString() const { SWC_ASSERT(isString()); return asString.val; }
    const ApsInt& getInt() const { SWC_ASSERT(isInt()); return asInt.val; }
    const ApFloat& getFloat() const { SWC_ASSERT(isFloat()); return asFloat.val; }
    uint64_t getValuePointer() const { SWC_ASSERT(isValuePointer()); return asPointer.val; }
    uint64_t getBlockPointer() const { SWC_ASSERT(isBlockPointer()); return asPointer.val; }
    uint64_t getSlicePointer() const { SWC_ASSERT(isSlice()); return asSlice.ptr; }
    uint64_t getSliceCount() const { SWC_ASSERT(isSlice()); return asSlice.count; }
    TypeRef getTypeValue() const { SWC_ASSERT(isTypeValue()); return asTypeInfo.val; }
    ConstantRef getEnumValue() const { SWC_ASSERT(isEnumValue()); return asEnumValue.val; }
    std::string_view getStruct() const { SWC_ASSERT(isStruct()); return asStruct.val; }
    const std::vector<ConstantRef>& getAggregate() const { SWC_ASSERT(isAggregate()); return asAggregate.val; }
    // clang-format on

    template<typename T>
    const T* getStruct(TypeRef typeRef) const
    {
        SWC_ASSERT(isStruct(typeRef));
        return reinterpret_cast<const T*>(asStruct.val.data());
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
    static ConstantValue makeStruct(const TaskContext& ctx, TypeRef typeRef, std::string_view bytes);
    static ConstantValue makeAggregate(const TaskContext& ctx, TypeRef typeRef, const std::vector<ConstantRef>& values);
    static ConstantValue makeValuePointer(TaskContext& ctx, TypeRef typeRef, uint64_t value, TypeInfoFlagsE flags = TypeInfoFlagsE::Zero);
    static ConstantValue makeBlockPointer(TaskContext& ctx, TypeRef typeRef, uint64_t value, TypeInfoFlagsE flags = TypeInfoFlagsE::Zero);
    static ConstantValue makeSlice(TaskContext& ctx, TypeRef typeRef, uint64_t ptr, uint64_t count, TypeInfoFlagsE flags = TypeInfoFlagsE::Zero);

    uint32_t hash() const noexcept;
    ApsInt   getIntLike() const;
    bool     ge(const ConstantValue& rhs) const noexcept;
    Utf8     toString(const TaskContext& ctx) const;

private:
    ConstantKind kind_    = ConstantKind::Invalid;
    TypeRef      typeRef_ = TypeRef::invalid();

    union
    {
        struct
        {
            std::string_view val;
        } asString;

        struct
        {
            std::string_view val;
        } asStruct;

        struct
        {
            char32_t val;
        } asCharRune;

        struct
        {
            bool val;
        } asBool;

        struct
        {
            ApsInt val;
        } asInt;

        struct
        {
            ApFloat val;
        } asFloat;

        struct
        {
            uint64_t val;
        } asPointer;

        struct
        {
            uint64_t ptr;
            uint64_t count;
        } asSlice;

        struct
        {
            TypeRef val;
        } asTypeInfo;

        struct
        {
            ConstantRef val;
        } asEnumValue;

        struct
        {
            std::vector<ConstantRef> val;
        } asAggregate;
    };
};

struct ConstantValueHash
{
    size_t operator()(const ConstantValue& v) const noexcept { return v.hash(); }
};

SWC_END_NAMESPACE();
