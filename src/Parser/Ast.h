#pragma once
#include "Core/Store.h"
#include "Lexer/Lexer.h"
#include "Main/Stats.h"
#include "Parser/AstNode.h"
#include "Parser/AstNodes.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

class SourceView;
class Verify;

enum class AstFlagsE : uint32_t
{
    Zero        = 0,
    HasErrors   = 1 << 0,
    HasWarnings = 1 << 1,
    GlobalSkip  = 1 << 2,
};
using AstFlags = EnumFlags<AstFlagsE>;

class Ast
{
public:
    static constexpr const AstNodeIdInfo& nodeIdInfos(AstNodeId id) { return AST_NODE_ID_INFOS[static_cast<size_t>(id)]; }
    static constexpr std::string_view     nodeIdName(AstNodeId id) { return nodeIdInfos(id).name; }

    AstNodeRef        root() const { return root_; }
    void              setRoot(AstNodeRef root) { root_ = root; }
    SourceView&       srcView() { return *srcView_; }
    const SourceView& srcView() const { return *srcView_; }
    void              setSourceView(SourceView& srcView) { srcView_ = &srcView; }
    bool              hasFlag(AstFlags flag) const { return flags_.has(flag); }
    void              addFlag(AstFlags flag) { flags_.add(flag); }

    AstNode&       node(AstNodeRef nodeRef);
    const AstNode& node(AstNodeRef nodeRef) const;
    void           nodes(SmallVector<AstNodeRef>& out, SpanRef spanRef) const;
    AstNodeRef     oneNode(SpanRef spanRef) const;
    void           tokens(SmallVector<TokenRef>& out, SpanRef spanRef) const;

    template<AstNodeId ID>
    auto node(AstNodeRef nodeRef)
    {
        SWC_ASSERT(nodeRef.isValid());
        using NodeType = AstTypeOf<ID>::type;

        const uint32_t g = nodeRef.get();
        return shards_[refShard(g)].store.ptr<AstNode>(refLocal(g))->cast<NodeType>();
    }

    template<typename T>
    SpanRef pushSpan(const std::span<T>& s)
    {
        const uint32_t shard = chooseShard();
        SpanRef        local;

        {
            std::unique_lock lock(shards_[shard].mutex);
            local = shards_[shard].store.push_span(s);
        }

        return SpanRef(packRef(shard, local.get()));
    }

    template<AstNodeId ID>
    auto makeNode(TokenRef tokRef)
    {
        using NodeType = AstTypeOf<ID>::type;

        const uint32_t            shard = chooseShard();
        std::pair<Ref, NodeType*> local;

        {
            std::unique_lock lock(shards_[shard].mutex);
            local = shards_[shard].store.emplace_uninit<NodeType>();
        }

        const uint32_t localByteRef = local.first;

        AstNodeRef globalRef{packRef(shard, localByteRef)};
        ::new (local.second) AstNode(ID, srcView_->ref(), tokRef);

#if SWC_HAS_STATS
        Stats::get().numAstNodes.fetch_add(1, std::memory_order_relaxed);
#endif

        auto value = std::pair<AstNodeRef, NodeType*>{globalRef, local.second};
#if SWC_HAS_REF_DEBUG_INFO
        value.first.setDbgPtr(value.second);
#endif
        return value;
    }

    AstNodeRef findNodeRef(const AstNode* node) const;

public:
    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    static constexpr uint32_t LOCAL_BITS  = 32u - SHARD_BITS;
    static constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1u;

    static uint32_t packRef(uint32_t shard, uint32_t localIndex)
    {
        SWC_ASSERT(localIndex < LOCAL_MASK);
        return (shard << LOCAL_BITS) | (localIndex & LOCAL_MASK);
    }

    static uint32_t refShard(uint32_t globalRef) { return globalRef >> LOCAL_BITS; }
    static uint32_t refLocal(uint32_t globalRef) { return globalRef & LOCAL_MASK; }

private:
    static uint32_t chooseShard() { return JobManager::threadIndex() % SHARD_COUNT; }

    struct Shard
    {
        Store                     store;
        mutable std::shared_mutex mutex;
    };

    Shard       shards_[SHARD_COUNT];
    SourceView* srcView_ = nullptr;
    AstNodeRef  root_    = AstNodeRef::invalid();
    AstFlags    flags_   = AstFlagsE::Zero;
};

SWC_END_NAMESPACE();
