namespace Swag
{
    // #########################################################
    // Type reflection
    // #########################################################

    // How two types are compared.
    #[EnumFlags]
    enum TypeCmpFlags
    {
        Strict   = 0
        CastAny  = 1
        Unscoped = 2
    }

    // The kind of the typeinfo.
    enum TypeInfoKind: u8
    {
        Invalid
        Native            // The typeinfo is a [[TypeInfoNative]]. See [[TypeInfoNativeKind]] for the underlying type.
        Namespace         // The typeinfo is a [[TypeInfoNamespace]]
        Enum              // The typeinfo is a [[TypeInfoEnum]]
        Func              // The typeinfo is a [[TypeInfoFunc]]
        Lambda            // The typeinfo is a [[TypeInfoFunc]], but this is a lambda or a func
        Pointer           // The typeinfo is a [[TypeInfoPointer]]
        Array             // The typeinfo is a [[TypeInfoArray]]
        Slice             // The typeinfo is a [[TypeInfoSlice]]
        TypeListTuple     // The typeinfo is a [[TypeInfoStruct]]
        TypeListArray     // The typeinfo is a [[TypeInfoArray]]
        Variadic          // The typeinfo is a [[TypeInfoVariadic]]
        TypedVariadic     // The typeinfo is a [[TypeInfoVariadic]]
        CVariadic         // Reserved ABI value; no Swag type currently produces this kind.
        Struct            // The typeinfo is a [[TypeInfoStruct]]
        Generic           // The typeinfo is a [[TypeInfoGeneric]]
        Alias             // The typeinfo is a [[TypeInfoAlias]]
        CodeBlock         // The typeinfo is a [[TypeInfoCodeBlock]]
        Interface         // The typeinfo is a [[TypeInfoStruct]], but this is an interface
        Attribute         // The typeinfo is a [[TypeInfoFunc]], but this is an attribute
        Simd              // The typeinfo is a [[TypeInfoSimd]]
    }

    // The native type described by a [[TypeInfoNative]], whose 'kind' is 'TypeInfoKind.Native'.
    enum TypeInfoNativeKind: u8
    {
        Void
        S8
        S16
        S32
        S64
        U8
        U16
        U32
        U64
        F32
        F64
        Bool
        Rune
        String
        Any
        CString
    }

    // Properties of a type, stored in each [[TypeInfo]].
    #[Swag.EnumFlags]
    enum TypeInfoFlags: u32
    {
        Zero                 = 0x00000000
        PointerTypeInfo      = 0x00000001     // This is a pointer to a [[TypeInfo]] struct
        Integer              = 0x00000002     // This is a native integer
        Float                = 0x00000004     // This is a native float
        Unsigned             = 0x00000008     // This is a native unsigned integer
        HasPostCopy          = 0x00000010     // This is a struct with a 'opPostCopy'
        HasPostMove          = 0x00000020     // This is a struct with a 'opPostMove'
        HasDrop              = 0x00000040     // This is a struct with a 'opDrop'
        Strict               = 0x00000080     // This is an alias with the Swag.Strict attribute
        CanCopy              = 0x00000100     // This is a struct that can be copied
        Tuple                = 0x00000200     // This is a positional tuple
        CString              = 0x00000400     // This is a 'cstring'
        Generic              = 0x00000800     // This is a generic type
        PointerRef           = 0x00001000     // This is a reference
        PointerMoveRef       = 0x00002000     // This is a move reference
        PointerArithmetic    = 0x00004000     // This is a pointer to multiple values
        Character            = 0x00008000     // This is a 32 bits character
        Const                = 0x00010000     // This is const
        Nullable             = 0x00020000     // This is a nullable type
        RequiresExplicitInit = 0x00080000     // This type must be explicitly initialized
        HasDynamicStorage    = 0x00100000     // This value contains compiler-managed dynamic identity slots
        Record               = 0x00200000     // This is an anonymous record with named fields
    }

    // Runtime representation of an interface value.
    //
    // A null method table means the interface is absent. A present interface may have a
    // null instance pointer when its methods do not access instance storage.
    struct Interface
    {
        public
        {
            obj:    *void?     // Pointer to the associated struct instance
            itable: const [*] ([*] void?)?     // Pointer to the table: [0] type descriptor, then method pointers
        }
    }

    const ClosureCaptureBufferSize = 64     // Bytes a closure can capture inline

    // Runtime representation of a closure: its entry point and its captured values.
    struct ClosureValue
    {
        public
        {
            invoke:  *void?
            capture: [ClosureCaptureBufferSize] u8
        }
    }

    // One parameter of an attribute instance, as reflected at runtime.
    struct AttributeParam
    {
        public
        {
            name:  string?     // Name of the attribute parameter
            value: any?        // Optional default value
        }
    }

    // One attribute instance attached to a declaration, as reflected at runtime.
    struct Attribute
    {
        public
        {
            type:   const *TypeInfo?
            params: const [..] AttributeParam?     // Attribute parameters
        }
    }

    // Properties of a [[TypeValue]].
    #[EnumFlags]
    enum TypeValueFlags
    {
        Zero = 0
        AutoName
        HasUsing
        LateInit     // 'late' field: starts null, receives its value later
        ReadOnly     // 'readonly' field: read anywhere, written only by the declaring type
        Internal     // 'internal' field: reached only inside the declaring module
        Private      // 'private' field: reached only by the declaring type
    }

    // Describes a named value of a type: a struct field, a function parameter, or an enum value.
    struct TypeValue
    {
        public
        {
            name:        string?                   // Name of the value
            pointedType: const *TypeInfo?          // Type of the value
            value:       const *void?              // Pointer to the constant value
            attributes:  const [..] Attribute?     // Associated attributes
            offset:      u32                       // Offset, in bytes
            crc:         u32                       // Unique CRC
            flags:       TypeValueFlags            // Associated flags
            padding:     u32
        }
    }

    // Describes a type at runtime; the base of every concrete type descriptor.
    //
    // The concrete descriptor can be borrowed with 'try cast', or extracted with 'assume cast'
    // when its type is known. Changing 'kind' does not change its dynamic identity.
    #[Swag.DynCast]
    struct TypeInfo
    {
        public
        {
            fullname:    string?             // The full scoped name of the type
            name:        string?             // The unscoped name
            sizeof:      u32                 // Size in bytes
            crc:         u32                 // Stable type hash; collisions are possible
            flags = TypeInfoFlags.Zero       // Some additional flags
            kind  = TypeInfoKind.Invalid     // The kind of the type
            padding:     [3] u8
            unqualified: const *TypeInfo?     // Compiler descriptor without outer const/nullability; null for user descriptions
        }
    }

    struct TypeInfoNative
    {
        public
        {
            using base: TypeInfo
            nativeKind: TypeInfoNativeKind = TypeInfoNativeKind.Void
        }
    }

    struct TypeInfoPointer
    {
        public
        {
            using base:  TypeInfo
            pointedType: const *TypeInfo     // The pointed type
        }
    }

    struct TypeInfoAlias
    {
        public
        {
            using base: TypeInfo
            rawType:    const *TypeInfo     // The underlying type
        }
    }

    struct TypeInfoCodeBlock
    {
        public
        {
            using base: TypeInfo
            rawType:    const *TypeInfo     // The underlying type
        }
    }

    // Describes one compiler-managed dynamic identity slot in a complete object.
    struct DynamicStructInfo
    {
        public
        {
            type:        const *TypeInfo      // Type of the complete object
            offset:      u64     // Byte offset of the slot from the complete object
            runtimeType: const *TypeInfo?     // Sealed self reference for a compiler-emitted type descriptor; otherwise null
        }
    }

    struct TypeInfoStruct
    {
        public
        {
            using base:   TypeInfo
            opInit:       (func(*void?))?                   // Initialization hook; null when zero-initialization suffices or explicit initialization is required
            opDrop:       (func(*void?))?                   // Pointer to the function to drop an instance of that struct
            opPostCopy:   (func(*void?))?                   // Pointer to the function to call after a copy
            opPostMove:   (func(*void?))?                   // Pointer to the function to call after a move
            structName:   string?                           // User name of the struct
            fromGeneric:  const *TypeInfo?                  // If it comes from a generic instantiation, this is the original generic struct
            generics:     const [..] TypeValue?             // Generic parameters
            fields:       const [..] TypeValue?             // All the fields
            usingFields:  const [..] TypeValue?             // All the fields marked with 'using'
            methods:      const [..] TypeValue?             // All the methods, if exported
            interfaces:   const [..] TypeValue?             // All the interfaces
            attributes:   const [..] Attribute?             // All the attributes
            dynamicSlots: const [..] DynamicStructInfo?     // Dynamic identity slots; empty for ordinary structs
        }
    }

    struct TypeInfoFunc
    {
        public
        {
            using base: TypeInfo
            generics:   const [..] TypeValue?     // Generic parameters
            parameters: const [..] TypeValue?     // Parameters
            returnType: const *TypeInfo?          // The return type, or 'null'
            attributes: const [..] Attribute?     // All the attributes
        }
    }

    struct TypeInfoEnum
    {
        public
        {
            using base: TypeInfo
            values:     const [..] TypeValue?     // All the values
            rawType:    const *TypeInfo?          // The underlying enum type
            attributes: const [..] Attribute?     // All the attributes
        }
    }

    struct TypeInfoArray
    {
        public
        {
            using base:  TypeInfo
            pointedType: const *TypeInfo     // The underlying type
            finalType:   const *TypeInfo     // If this is an array with multiple dimensions, this will be the final type
            count:       u64                 // Number of elements in the array
            totalCount:  u64                 // The total number of elements in case this has multiple dimensions
        }
    }

    struct TypeInfoSlice
    {
        public
        {
            using base:  TypeInfo
            pointedType: const *TypeInfo     // The underlying type
        }
    }

    struct TypeInfoSimd
    {
        public
        {
            using base: TypeInfo
            laneType:   const *TypeInfo     // The native type of one lane
            count:      u64     // Number of lanes in the vector
        }
    }

    struct TypeInfoVariadic
    {
        public
        {
            using base: TypeInfo
            rawType:    const *TypeInfo     // The underlying type
        }
    }

    struct TypeInfoGeneric
    {
        public
        {
            using base: TypeInfo
            rawType:    const *TypeInfo
        }
    }

    struct TypeInfoNamespace
    {
        public using base: TypeInfo
    }
}
