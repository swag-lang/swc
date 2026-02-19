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
        PlaceHolder,
        NoPrint,
        Macro,
        Mixin,
        Implicit,
        EnumFlags,
        EnumIndex,
        NoDuplicate,
        Complete,
        Overload,
        CalleeReturn,
        Foreign,
        Discardable,
        NotGeneric,
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
        OpUnary,
        OpAssign,
        OpIndexAssign,
        OpCast,
        OpEquals,
        OpCmp,
        OpPostCopy,
        OpPostMove,
        OpDrop,
        OpCount,
        OpData,
        OpAffect,
        OpAffectLiteral,
        OpSlice,
        OpIndex,
        OpIndexAffect,
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
        Count,
    };

    void              setup(const TaskContext& ctx);
    IdentifierRef     addIdentifier(const TaskContext& ctx, const SourceCodeRef& codeRef);
    IdentifierRef     addIdentifier(std::string_view name);
    IdentifierRef     addIdentifier(std::string_view name, uint32_t hash);
    IdentifierRef     addIdentifierOwned(std::string_view name);
    IdentifierRef     addIdentifierOwned(std::string_view name, uint32_t hash);
    const Identifier& get(IdentifierRef idRef) const;

    IdentifierRef predefined(PredefinedName name) const { return predefined_[static_cast<size_t>(name)]; }

private:
    IdentifierRef addIdentifierInternal(std::string_view name, uint32_t hash, bool copyName);

    struct Shard
    {
        PagedStore                store;
        PagedStore                stringStore;
        StringMap<IdentifierRef>  map;
        mutable std::shared_mutex mutex;
    };

    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    static constexpr uint32_t LOCAL_BITS  = 32 - SHARD_BITS;
    static constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1;
    Shard                     shards_[SHARD_COUNT];

    std::array<IdentifierRef, static_cast<size_t>(PredefinedName::Count)> predefined_ = {};
};

SWC_END_NAMESPACE();
