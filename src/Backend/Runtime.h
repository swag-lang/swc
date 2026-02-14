#pragma once

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    enum class TargetOs
    {
        Windows,
        Linux,
    };

    struct TypeInfo;

    struct String
    {
        const char* ptr;
        uint64_t    length;
    };

    template<typename T>
    struct Slice
    {
        T*       ptr;
        uint64_t count;
    };

    struct Any
    {
        void*           value;
        const TypeInfo* type;
    };

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
        CVariadic,
        Struct,
        Generic,
        Alias,
        CodeBlock,
        Interface,
        Attribute,
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
        Undefined,
    };

    enum class TypeInfoFlags : uint32_t
    {
        Zero              = 0x00000000,
        PointerTypeInfo   = 0x00000001,
        Integer           = 0x00000002,
        Float             = 0x00000004,
        Unsigned          = 0x00000008,
        HasPostCopy       = 0x00000010,
        HasPostMove       = 0x00000020,
        HasDrop           = 0x00000040,
        Strict            = 0x00000080,
        CanCopy           = 0x00000100,
        Tuple             = 0x00000200,
        CString           = 0x00000400,
        Generic           = 0x00000800,
        PointerRef        = 0x00001000,
        PointerMoveRef    = 0x00002000,
        PointerArithmetic = 0x00004000,
        Character         = 0x00008000,
        Const             = 0x00010000,
        Nullable          = 0x00020000,
    };

    enum class TypeValueFlags : uint32_t
    {
        Zero     = 0,
        AutoName = 1,
        HasUsing = 2,
    };

    enum class RuntimeFlags : uint64_t
    {
        Zero         = 0,
        FromCompiler = 1,
    };

    struct Interface
    {
        void*  obj;
        void** itable;
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

    struct SourceCodeLocation
    {
        String   fileName;
        String   funcName;
        uint32_t lineStart;
        uint32_t colStart;
        uint32_t lineEnd;
        uint32_t colEnd;
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

    struct Gvtd
    {
        void* ptr;
        void (*opDrop)(void*);
        uint32_t sizeOf;
        uint32_t count;
    };

    enum class ContextFlags : uint64_t
    {
        None     = 0,
        Test     = 1,
        ByteCode = 2,
    };

    struct ErrorValue
    {
        Any      value;
        uint32_t pushUsedAlloc;
        uint32_t pushTraceIndex;
        uint32_t pushHasError;
        uint32_t padding;
    };

    struct ScratchAllocator
    {
        Interface allocator;
        uint8_t*  block;
        uint64_t  capacity;
        uint64_t  used;
        uint64_t  maxUsed;
        void*     firstLeak;
        uint64_t  totalLeak;
        uint64_t  maxLeak;
    };

    struct Context
    {
        Interface          allocator;
        ContextFlags       flags = ContextFlags::None;
        ScratchAllocator   tempAllocator;
        ScratchAllocator   errorAllocator;
        void*              debugAllocator;
        RuntimeFlags       runtimeFlags;
        uint64_t           user0;
        uint64_t           user1;
        uint64_t           user2;
        uint64_t           user3;
        SourceCodeLocation traces[32];
        ErrorValue         errors[32];
        SourceCodeLocation exceptionLoc;
        const void*        exceptionParams[4];
        void (*panic)(String, SourceCodeLocation);
        Any      curError;
        uint32_t errorIndex;
        uint32_t traceIndex;
        uint32_t hasError;
    };

    enum class SafetyWhat : uint16_t
    {
        BoundCheck  = 0x0001,
        Overflow    = 0x0002,
        Math        = 0x0004,
        DynCast     = 0x0008,
        Switch      = 0x0010,
        Bool        = 0x0020,
        NaN         = 0x0040,
        Unreachable = 0x0080,
        Null        = 0x0100,
        Memory      = 0x0200,
        None        = 0x0000,
        All         = 0xFFFF,
    };

    struct BuildCfgBackendLlvm
    {
        bool outputIr;
        bool fpMathFma;
        bool fpMathNoNaN;
        bool fpMathNoInf;
        bool fpMathNoSignedZero;
        bool fpMathUnsafe;
        bool fpMathApproxFunc;
    };

    struct BuildCfgBackendScbe
    {
        uint32_t unrollMemLimit;
    };

    enum class BuildCfgBackendKind
    {
        None,
        Export,
        Executable,
        Library,
    };

    enum class BuildCfgBackendSubKind
    {
        Default,
        Console,
    };

    enum class BuildCfgByteCodeOptim
    {
        O0,
        O1,
        O2,
        O3,
    };

    enum class BuildCfgBackendOptim
    {
        O0,
        O1,
        O2,
        O3,
        Os,
        Oz,
    };

    enum class BuildCfgDocKind
    {
        None,
        Api,
        Examples,
        Pages,
    };

    struct BuildCfgGenDoc
    {
        BuildCfgDocKind kind = BuildCfgDocKind::None;
        String          outputName;
        String          outputExtension;
        String          titleToc;
        String          titleContent;
        String          css;
        String          icon;
        String          startHead;
        String          endHead;
        String          startBody;
        String          endBody;
        String          morePages;
        String          quoteIconNote;
        String          quoteIconTip;
        String          quoteIconWarning;
        String          quoteIconAttention;
        String          quoteIconExample;
        String          quoteTitleNote;
        String          quoteTitleTip;
        String          quoteTitleWarning;
        String          quoteTitleAttention;
        String          quoteTitleExample;
        uint32_t        syntaxDefaultColor = 0x00222222;
        float           syntaxColorLum     = 0.5f;
        bool            hasFontAwesome     = true;
        bool            hasStyleSection    = true;
        bool            hasSwagWatermark   = true;
    };

    struct BuildCfg
    {
        uint32_t moduleVersion  = 0;
        uint32_t moduleRevision = 0;
        uint32_t moduleBuildNum = 0;
        String   moduleNamespace;
        bool     embeddedImports = false;

        uint32_t   tempAllocatorCapacity      = 4u * 1024u * 1024u;
        uint32_t   errorAllocatorCapacity     = 16u * 1024u;
        SafetyWhat safetyGuards               = SafetyWhat::All;
        bool       sanity                     = true;
        bool       debugAllocator             = true;
        bool       debugAllocatorCaptureStack = true;
        bool       debugAllocatorLeaks        = true;
        bool       errorStackTrace            = true;

        String warnAsErrors;
        String warnAsWarning;
        String warnAsDisabled;
        bool   warnDefaultDisabled = false;
        bool   warnDefaultErrors   = false;

        BuildCfgByteCodeOptim byteCodeOptimizeLevel = BuildCfgByteCodeOptim::O1;
        bool                  byteCodeEmitAssume    = true;
        bool                  byteCodeInline        = true;
        bool                  byteCodeAutoInline    = true;

        BuildCfgBackendKind    backendKind              = BuildCfgBackendKind::Executable;
        BuildCfgBackendSubKind backendSubKind           = BuildCfgBackendSubKind::Console;
        bool                   backendDebugInformations = false;
        bool                   backendDebugInline       = false;
        BuildCfgBackendOptim   backendOptimize          = BuildCfgBackendOptim::O0;
        uint32_t               backendNumCu             = 0;

        String              linkerArgs;
        BuildCfgBackendLlvm backendLlvm;
        BuildCfgBackendScbe backendScbe;

        String         repoPath;
        String         resAppIcoFileName;
        String         resAppName;
        String         resAppDescription;
        String         resAppCompany;
        String         resAppCopyright;
        BuildCfgGenDoc genDoc;
    };

    enum class CompilerMsgKind : uint32_t
    {
        PassAfterSemantic,
        PassBeforeRunByteCode,
        PassBeforeOutput,
        PassAllDone,
        SemFunctions,
        SemTypes,
        SemGlobals,
        AttributeGen,
    };

    enum class CompilerMsgMask : uint64_t
    {
        PassAfterSemantic = 1ull << static_cast<uint32_t>(CompilerMsgKind::PassAfterSemantic),
        PassBeforeRun     = 1ull << static_cast<uint32_t>(CompilerMsgKind::PassBeforeRunByteCode),
        PassBeforeOutput  = 1ull << static_cast<uint32_t>(CompilerMsgKind::PassBeforeOutput),
        PassAllDone       = 1ull << static_cast<uint32_t>(CompilerMsgKind::PassAllDone),
        SemFunctions      = 1ull << static_cast<uint32_t>(CompilerMsgKind::SemFunctions),
        SemTypes          = 1ull << static_cast<uint32_t>(CompilerMsgKind::SemTypes),
        SemGlobals        = 1ull << static_cast<uint32_t>(CompilerMsgKind::SemGlobals),
        AttributeGen      = 1ull << static_cast<uint32_t>(CompilerMsgKind::AttributeGen),
        All               = ~0ull,
    };

    struct CompilerMessage
    {
        String          moduleName;
        String          name;
        const TypeInfo* type;
        CompilerMsgKind kind;
    };

    struct ICompiler : Interface
    {
    };
}

SWC_END_NAMESPACE();
