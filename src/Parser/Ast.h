#pragma once
#include "Core/RefStore.h"
#include "Core/Types.h"
#include "Parser/AstNode.h"
#include "Parser/AstNodes.h"
#include "Report/Stats.h"

SWC_BEGIN_NAMESPACE()

class Ast
{
protected:
    friend class Parser;
    RefStore<> store_;
    AstNodeRef root_ = INVALID_REF;

public:
    static constexpr const AstNodeIdInfo& nodeIdInfos(AstNodeId id) { return AST_NODE_ID_INFOS[static_cast<size_t>(id)]; }
    static constexpr std::string_view     nodeIdName(AstNodeId id) { return nodeIdInfos(id).name; }

    template<AstNodeId T>
    auto makeNode()
    {
        using NodeType = AstTypeOf<T>::type;
        auto result    = store_.emplace_uninit<NodeType>();
#if SWC_HAS_STATS
        Stats::get().numAstNodes.fetch_add(1);
#endif
        return result;
    }

    template<AstNodeId T>
    auto node()
    {
        using NodeType = AstTypeOf<T>::type;
        return castAst<const NodeType*>(store_.ptr<AstNode*>(root_));
    }
};

SWC_END_NAMESPACE()
