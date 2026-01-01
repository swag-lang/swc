#pragma once
#include "Core/Store.h"
#include "Core/StringMap.h"
#include "Lexer/SourceView.h"
#include "Math/Hash.h"

SWC_BEGIN_NAMESPACE()

class TaskContext;

struct Identifier
{
    std::string_view name;
};

using IdentifierRef = StrongRef<Identifier>;

class IdentifierManager
{
public:
    void              setup(TaskContext&);
    IdentifierRef     addIdentifier(const TaskContext& ctx, SourceViewRef srcViewRef, TokenRef tokRef);
    IdentifierRef     addIdentifier(std::string_view name);
    IdentifierRef     addIdentifier(std::string_view name, uint32_t hash);
    const Identifier& get(IdentifierRef idRef) const;

    IdentifierRef nameSwag() const { return nameSwag_; }
    IdentifierRef nameEnumFlags() const { return nameEnumFlags_; }
    IdentifierRef nameAttributeUsage() const { return nameAttributeUsage_; }
    IdentifierRef nameTargetOs() const { return nameTargetOs_; }

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

    IdentifierRef nameSwag_           = IdentifierRef::invalid();
    IdentifierRef nameEnumFlags_      = IdentifierRef::invalid();
    IdentifierRef nameAttributeUsage_ = IdentifierRef::invalid();
    IdentifierRef nameTargetOs_       = IdentifierRef::invalid();
};

SWC_END_NAMESPACE()

template<>
struct std::hash<swc::IdentifierRef>
{
    size_t operator()(const swc::IdentifierRef& r) const noexcept
    {
        return swc::Math::hash(r.get());
    }
};
