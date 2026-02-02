#pragma once
#include "Compiler/Lexer/SourceView.h"
#include "Support/Core/Store.h"
#include "Support/Core/StringMap.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

struct Identifier
{
    std::string_view name;
};

using IdentifierRef = StrongRef<Identifier>;

class IdentifierManager
{
public:
    enum class PredefinedName : uint8_t
    {
        Swag,
        AttributeUsage,

        AttrMulti,
        ConstExpr,
        PrintBc,
        PrintBcGen,
        PrintAsm,
        Compiler,
        Inline,
        NoInline,
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

        Count,
    };

    void              setup(TaskContext&);
    IdentifierRef     addIdentifier(const TaskContext& ctx, SourceCodeRef loc);
    IdentifierRef     addIdentifier(const TaskContext& ctx, SourceViewRef srcViewRef, TokenRef tokRef);
    IdentifierRef     addIdentifier(std::string_view name);
    IdentifierRef     addIdentifier(std::string_view name, uint32_t hash);
    const Identifier& getNoLock(IdentifierRef idRef) const;
    const Identifier& get(IdentifierRef idRef) const;

    IdentifierRef predefined(PredefinedName name) const { return predefined_[static_cast<size_t>(name)]; }

private:
    struct Shard
    {
        Store                     store;
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
