#pragma once
#include "Backend/RuntimeBase.h"

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    enum class TypeInfoKind : uint8_t
    {
        Invalid,
        Native,
        Namespace,
        Enum,
        Func,
        Lambda,
        Pointer,
        Array,
        Slice,
        TypeListTuple,
        TypeListArray,
        Variadic,
        TypedVariadic,
        CVariadic, // Reserved to keep the runtime TypeInfoKind values stable.
        Struct,
        Generic,
        Alias,
        CodeBlock,
        Interface,
        Attribute,
        Simd,
    };

    enum class TypeInfoNativeKind : uint8_t
    {
        Void,
        S8,
        S16,
        S32,
        S64,
        U8,
        U16,
        U32,
        U64,
        F32,
        F64,
        Bool,
        Rune,
        String,
        Any,
        CString,
    };

    enum class TypeInfoFlags : uint32_t
    {
        Zero                 = 0x00000000,
        PointerTypeInfo      = 0x00000001,
        Integer              = 0x00000002,
        Float                = 0x00000004,
        Unsigned             = 0x00000008,
        HasPostCopy          = 0x00000010,
        HasPostMove          = 0x00000020,
        HasDrop              = 0x00000040,
        Strict               = 0x00000080,
        CanCopy              = 0x00000100,
        Tuple                = 0x00000200,
        CString              = 0x00000400,
        Generic              = 0x00000800,
        PointerRef           = 0x00001000,
        PointerMoveRef       = 0x00002000,
        PointerArithmetic    = 0x00004000,
        Character            = 0x00008000,
        Const                = 0x00010000,
        Nullable             = 0x00020000,
        RequiresExplicitInit = 0x00080000,
    };

    enum class TypeValueFlags : uint32_t
    {
        Zero     = 0,
        AutoName = 1,
        HasUsing = 2,
        LateInit = 4,
        ReadOnly = 8,
        Internal = 16,
        Private  = 32,
    };

    struct AttributeParam
    {
        String name;
        Any    value;
    };

    struct Attribute
    {
        const TypeInfo*       type;
        Slice<AttributeParam> params;
    };

    struct TypeValue
    {
        String           name;
        const TypeInfo*  pointedType;
        const void*      value;
        Slice<Attribute> attributes;
        uint32_t         offset;
        uint32_t         crc;
        TypeValueFlags   flags;
        uint32_t         padding;
    };

    struct TypeInfo
    {
        String        fullname;
        String        name;
        uint32_t      sizeofType;
        uint32_t      crc;
        TypeInfoFlags flags = TypeInfoFlags::Zero;
        TypeInfoKind  kind  = TypeInfoKind::Invalid;
        uint8_t       padding[3];
    };

    struct TypeInfoNative
    {
        TypeInfo           base;
        TypeInfoNativeKind nativeKind = TypeInfoNativeKind::Void;
    };

    struct TypeInfoPointer
    {
        TypeInfo        base;
        const TypeInfo* pointedType;
    };

    struct TypeInfoAlias
    {
        TypeInfo        base;
        const TypeInfo* rawType;
    };

    struct TypeInfoCodeBlock
    {
        TypeInfo        base;
        const TypeInfo* rawType;
    };

    struct TypeInfoStruct
    {
        TypeInfo base;
        void (*opInit)(void*);
        void (*opDrop)(void*);
        void (*opPostCopy)(void*);
        void (*opPostMove)(void*);
        String           structName;
        const TypeInfo*  fromGeneric;
        Slice<TypeValue> generics;
        Slice<TypeValue> fields;
        Slice<TypeValue> usingFields;
        Slice<TypeValue> methods;
        Slice<TypeValue> interfaces;
        Slice<Attribute> attributes;
    };

    struct TypeInfoFunc
    {
        TypeInfo         base;
        Slice<TypeValue> generics;
        Slice<TypeValue> parameters;
        const TypeInfo*  returnType;
        Slice<Attribute> attributes;
    };

    struct TypeInfoEnum
    {
        TypeInfo         base;
        Slice<TypeValue> values;
        const TypeInfo*  rawType;
        Slice<Attribute> attributes;
    };

    struct TypeInfoArray
    {
        TypeInfo        base;
        const TypeInfo* pointedType;
        const TypeInfo* finalType;
        uint64_t        count;
        uint64_t        totalCount;
    };

    struct TypeInfoSlice
    {
        TypeInfo        base;
        const TypeInfo* pointedType;
    };

    struct TypeInfoSimd
    {
        TypeInfo        base;
        const TypeInfo* laneType;
        uint64_t        count;
    };

    struct TypeInfoVariadic
    {
        TypeInfo        base;
        const TypeInfo* rawType;
    };

    struct TypeInfoGeneric
    {
        TypeInfo        base;
        const TypeInfo* rawType;
    };

    struct TypeInfoNamespace
    {
        TypeInfo base;
    };

    struct Module
    {
        String          name;
        Slice<TypeInfo> types;
    };

    struct ProcessInfos
    {
        Slice<Module> types;
        String        args;
    };
}

SWC_END_NAMESPACE();
