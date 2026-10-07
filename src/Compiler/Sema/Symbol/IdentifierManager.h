#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Support/Core/PagedStore.h"
#include "Support/Core/RefTypes.h"
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
        EnsureRuntimeAllocator,
        SetupRuntime,
        ReleaseRuntime,
        CloseRuntime,
        HasErr,
        IsErrContext,
        SetErrRaw,
        PushErr,
        PopErr,
        CatchErr,
        EndErr,
        BindErr,
        ClearErr,
        FailedExpect,
        FailedCast,
        Panic,
        SafetyPanic,
        As,
        DynamicCast,
        RuntimeTypeCast,
        RuntimeValueCast,
        Is,
        TypeCmp,
        TlsAlloc,
        TlsSetValue,
        TlsGetPtr,
        TlsGetValue,
        TlsVarPtr,
        RaiseException,
        StringCmp,
        SliceCmp,
        RunTest,
        TestsDone,
        ParallelRange,
        ParallelRangeFallible,
        Count,
    };

    enum class PredefinedName : uint8_t
    {
        Swag,
        AttributeUsage,
        AttrUsage,
        AttrMulti,
        TestTag,
        ConstExpr,
        ReadOnly,
        PrintMicro,
        PrintAst,
        Compiler,
        Inline,
        NoInline,
        Optimize,
        PlaceHolder,
        Macro,
        Mixin,
        Implicit,
        EnumFlags,
        ReservedEnumAttribute,
        NoDuplicate,
        FullInit,
        Commutative,
        Operators,
        OperatorIgnore,
        CalleeReturn,
        Foreign,
        Discardable,
        NoCopy,
        DynCast,
        Opaque,
        NoDoc,
        Strict,
        Me,
        TargetOs,
        TargetArch,
        CompilerCommand,
        Operator,
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
        OpIndexPtr,
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
        TypeInfoSimd,
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
        RuntimeEnsureRuntimeAllocator,
        RuntimeSetupRuntime,
        RuntimeReleaseRuntime,
        RuntimeCloseRuntime,
        RuntimeHasErr,
        RuntimeIsErrContext,
        RuntimeSetErrRaw,
        RuntimePushErr,
        RuntimePopErr,
        RuntimeCatchErr,
        RuntimeEndErr,
        RuntimeBindErr,
        RuntimeClearErr,
        RuntimeFailedExpect,
        RuntimeFailedCast,
        RuntimePanic,
        RuntimeSafetyPanic,
        RuntimeAs,
        RuntimeDynamicCast,
        RuntimeTypeCast,
        RuntimeValueCast,
        RuntimeIs,
        RuntimeTypeCmp,
        RuntimeStringCmp,
        RuntimeSliceCmp,
        RuntimeTlsAlloc,
        RuntimeTlsSetValue,
        RuntimeTlsGetPtr,
        RuntimeTlsGetValue,
        RuntimeTlsVarPtr,
        RuntimeRaiseException,
        RuntimeRunTest,
        RuntimeTestsDone,
        RuntimeParallelRange,
        RuntimeParallelRangeFallible,
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

    // Open-addressed and append-only. A slot packs the name hash with the reference plus one in
    // a single word, so a reader that sees a slot sees all of it. Readers probe it without a
    // lock; writers fill it under the stripe mutex once the identifier is stored.
    struct InternTable
    {
        std::unique_ptr<std::atomic<uint64_t>[]> slots;
        uint32_t                                 capacity = 0; // power of two
        uint32_t                                 size     = 0; // writer-only
    };

    // Each stripe owns its cache line: neighbours locked by other workers must not share it.
    // 'map' is the writers' authority; 'table' answers lookups without a lock. Every table
    // generation stays alive with the stripe, for readers still probing an older one.
    struct alignas(64) InternStripe
    {
        StringMap<IdentifierRef>                  map;
        std::atomic<InternTable*>                 table = nullptr;
        std::vector<std::unique_ptr<InternTable>> tables;
        std::mutex                                mutex; // writers only
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

    IdentifierRef   findInterned(const InternTable* table, std::string_view name, uint32_t hash) const noexcept;
    static void     publishInterned(InternStripe& stripe, IdentifierRef idRef, uint32_t hash);
    static uint32_t internSlot(uint32_t hash, uint32_t capacity) noexcept;

    std::array<IdentifierRef, static_cast<size_t>(PredefinedName::Count)>      predefined_       = {};
    std::array<IdentifierRef, static_cast<size_t>(RuntimeFunctionKind::Count)> runtimeFunctions_ = {};
};

SWC_END_NAMESPACE();
