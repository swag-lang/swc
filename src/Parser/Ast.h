#pragma once
#include "Core/Store.h"
#include "Lexer/Lexer.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Parser/AstNode.h"
#include "Parser/AstNodes.h"

SWC_BEGIN_NAMESPACE()

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
    Store       store_;
    SourceView* srcView_ = nullptr;
    AstNodeRef  root_    = AstNodeRef::invalid();
    AstFlags    flags_   = AstFlagsE::Zero;

public:
    static constexpr const AstNodeIdInfo& nodeIdInfos(AstNodeId id) { return AST_NODE_ID_INFOS[static_cast<size_t>(id)]; }
    static constexpr std::string_view     nodeIdName(AstNodeId id) { return nodeIdInfos(id).name; }
    auto&                                 store() { return store_; }
    AstNodeRef                            root() const { return root_; }
    void                                  setRoot(AstNodeRef root) { root_ = root; }
    SourceView&                           srcView() { return *srcView_; }
    const SourceView&                     srcView() const { return *srcView_; }
    void                                  setSourceView(SourceView& srcView) { srcView_ = &srcView; }
    bool                                  hasFlag(AstFlags flag) const { return flags_.has(flag); }
    void                                  addFlag(AstFlags flag) { flags_.add(flag); }

    // Get a node depending on its ref
    template<AstNodeId ID>
    auto node(AstNodeRef nodeRef)
    {
        SWC_ASSERT(nodeRef.isValid());
        using NodeType = AstTypeOf<ID>::type;
        return castAst<NodeType>(store_.ptr<AstNode>(nodeRef.get()));
    }

    AstNode&       node(AstNodeRef nodeRef) { return *store_.ptr<AstNode>(nodeRef.get()); }
    const AstNode& node(AstNodeRef nodeRef) const { return *store_.ptr<AstNode>(nodeRef.get()); }

    void nodes(SmallVector<AstNodeRef>& out, SpanRef spanRef) const;

    template<AstNodeId ID>
    auto makeNode(TokenRef tokRef)
    {
        using NodeType = AstTypeOf<ID>::type;
        auto result    = store_.emplace_uninit<NodeType>();
        ::new (result.second) AstNode(ID, srcView_->ref(), tokRef);
#if SWC_HAS_STATS
        Stats::get().numAstNodes.fetch_add(1);
#endif
        return std::pair<AstNodeRef, NodeType*>(result);
    }
};

SWC_END_NAMESPACE()
