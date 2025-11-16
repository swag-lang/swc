#pragma once
#include "Core/RefStore.h"
#include "Main/Stats.h"
#include "Parser/AstNode.h"
#include "Parser/AstNodes.h"

SWC_BEGIN_NAMESPACE()
class LexerOutput;

class Ast
{
    RefStore<>         store_;
    AstNodeRef         root_   = AstNodeRef::invalid();
    const LexerOutput* lexOut_ = nullptr;

public:
    static constexpr const AstNodeIdInfo& nodeIdInfos(AstNodeId id) { return AST_NODE_ID_INFOS[static_cast<size_t>(id)]; }
    static constexpr std::string_view     nodeIdName(AstNodeId id) { return nodeIdInfos(id).name; }
    auto&                                 store() { return store_; }
    AstNodeRef                            root() const { return root_; }
    void                                  setRoot(AstNodeRef root) { root_ = root; }
    const LexerOutput&                    lexOut() const { return *lexOut_; }
    void                                  setLexOut(const LexerOutput& lexOut) { lexOut_ = &lexOut; }

    // Get a node depending on its ref
    template<AstNodeId ID>
    auto node(AstNodeRef nodeRef)
    {
        SWC_ASSERT(nodeRef.isValid());
        using NodeType = AstTypeOf<ID>::type;
        return castAst<NodeType>(store_.ptr<AstNode>(nodeRef.get()));
    }

    AstNode*       node(AstNodeRef nodeRef) { return store_.ptr<AstNode>(nodeRef.get()); }
    const AstNode* node(AstNodeRef nodeRef) const { return store_.ptr<AstNode>(nodeRef.get()); }

    void nodes(SmallVector<AstNodeRef>& out, SpanRef spanRef) const;

    // Construct new nodes
    template<AstNodeId ID>
    auto makeNode()
    {
        using NodeType    = AstTypeOf<ID>::type;
        auto result       = store_.emplace_uninit<NodeType>();
        result.second->id = ID;
        result.second->clearFlags();
#if SWC_HAS_STATS
        Stats::get().numAstNodes.fetch_add(1);
#endif
        return std::pair<AstNodeRef, NodeType*>(result);
    }

    template<typename T = AstNode>
    std::pair<AstNodeRef, T*>
    makeNode(AstNodeId id)
    {
        return visitAstNodeId(id, [&]<auto N>() {
            auto [ref, raw] = makeNode<N>();
            return std::pair{ref, reinterpret_cast<T*>(raw)};
        });
    }
};

SWC_END_NAMESPACE()
