#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Support/Core/PagedStore.h"
#include "Support/Core/StringMap.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

struct Identifier
{
    std::string_view name;
};

class IdentifierManager
{
public:
    enum class RuntimeFunctionKind : uint8_t
    {
        Exit,
        TestCountInit,
        TestCountTick,
        HasErr,
        IsErrContext,
        SetErrRaw,
        PushErr,
        PopErr,
        CatchErr,
        FailedAssume,
        Panic,
        SafetyPanic,
        As,
        Is,
        TypeCmp,
        TlsAlloc,
        TlsGetPtr,
        TlsGetValue,
        RaiseException,
        StringCmp,
        Count,
    };

    enum class PredefinedName : uint8_t
    {
        Swag,
        AttributeUsage,
        AttrMulti,
        ConstExpr,
        PrintMicro,
        PrintAst,
        Compiler,
        Inline,
        NoInline,
        Optimize,
        CanOverflow,
        PlaceHolder,
        NoPrint,
        Macro,
        Mixin,
        Implicit,
        EnumFlags,
        EnumIndex,
        NoDuplicate,
        Complete,
        Commutative,
        CalleeReturn,
        Foreign,
        Discardable,
        Tls,
        NoCopy,
        Opaque,
        Incomplete,
        NoDoc,
        Strict,
        Global,
        Me,
        TargetOs,
        TargetArch,
        OpBinary,
        OpBinaryRight,
        OpUnary,
        OpAssign,
        OpIndexAssign,
        OpCast,
        OpEquals,
        OpCompare,
        OpPostCopy,
        OpPostMove,
        OpDrop,
        OpCount,
        OpData,
        OpSet,
        OpSetLiteral,
        OpSlice,
        OpIndex,
        OpIndexSet,
        OpVisit,
        TypeInfo,
        TypeInfoNative,
        TypeInfoPointer,
        TypeInfoStruct,
        TypeInfoFunc,
        TypeInfoEnum,
        TypeInfoArray,
        TypeInfoSlice,
        TypeInfoAlias,
        TypeInfoVariadic,
        TypeInfoGeneric,
        TypeInfoNamespace,
        TypeInfoCodeBlock,
        TypeInfoKind,
        TypeInfoNativeKind,
        TypeInfoFlags,
        TypeValue,
        TypeValueFlags,
        Attribute,
        AttributeParam,
        Interface,
        SourceCodeLocation,
        ErrorValue,
        ScratchAllocator,
        Context,
        ContextFlags,
        Module,
        ProcessInfos,
        Gvtd,
        BuildCfg,
        RuntimeExit,
        RuntimeTestCountInit,
        RuntimeTestCountTick,
        RuntimeHasErr,
        RuntimeIsErrContext,
        RuntimeSetErrRaw,
        RuntimePushErr,
        RuntimePopErr,
        RuntimeCatchErr,
        RuntimeFailedAssume,
        RuntimePanic,
        RuntimeSafetyPanic,
        RuntimeAs,
        RuntimeIs,
        RuntimeTypeCmp,
        RuntimeStringCmp,
        RuntimeTlsAlloc,
        RuntimeTlsGetPtr,
        RuntimeTlsGetValue,
        RuntimeRaiseException,
        Count,
    };

    void                setup(const TaskContext& ctx);
    IdentifierRef       addIdentifier(const TaskContext& ctx, const SourceCodeRef& codeRef);
    IdentifierRef       addIdentifier(std::string_view name);
    IdentifierRef       addIdentifier(std::string_view name, uint32_t hash);
    IdentifierRef       addIdentifierOwned(std::string_view name);
    IdentifierRef       addIdentifierOwned(std::string_view name, uint32_t hash);
    const Identifier&   get(IdentifierRef idRef) const;
    IdentifierRef       predefined(PredefinedName name) const { return predefined_[static_cast<size_t>(name)]; }
    IdentifierRef       runtimeFunction(RuntimeFunctionKind kind) const { return runtimeFunctions_[static_cast<size_t>(kind)]; }
    RuntimeFunctionKind runtimeFunctionKind(IdentifierRef idRef) const;

private:
    IdentifierRef addIdentifierInternal(std::string_view name, uint32_t hash, bool copyName);

    static constexpr uint32_t INTERN_STRIPE_BITS  = 4;
    static constexpr uint32_t INTERN_STRIPE_COUNT = 1u << INTERN_STRIPE_BITS;

    struct InternStripe
    {
        StringMap<IdentifierRef>  map;
        mutable std::shared_mutex mutex;
    };

    struct Shard
    {
        PagedStore                                    store;
        PagedStore                                    stringStore;
        std::array<InternStripe, INTERN_STRIPE_COUNT> internStripes;
        mutable std::mutex                            storeMutex;
    };

    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    static constexpr uint32_t LOCAL_BITS  = 32 - SHARD_BITS;
    static constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1;
    Shard                     shards_[SHARD_COUNT];

    std::array<IdentifierRef, static_cast<size_t>(PredefinedName::Count)>      predefined_       = {};
    std::array<IdentifierRef, static_cast<size_t>(RuntimeFunctionKind::Count)> runtimeFunctions_ = {};
};

SWC_END_NAMESPACE();
