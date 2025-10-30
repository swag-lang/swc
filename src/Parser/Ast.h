#pragma once
#include "Core/RefStore.h"
#include "Core/Types.h"
#include "Parser/AstNode.h"
#include "Report/Stats.h"

SWC_BEGIN_NAMESPACE()

class Ast
{
protected:
    friend class Parser;
    RefStore<> store_;
    AstNodeRef root_ = INVALID_REF;

public:
    template<class T>
    AstNode* node(AstNodeRef ref)
    {
        return store_.ptr<T>(ref);
    }

    template<class T>
    const AstNode* node(AstNodeRef ref) const
    {
        return store_.ptr<T>(ref);
    }

    static constexpr const AstNodeIdInfo& nodeIdInfos(AstNodeId id) { return AST_NODE_ID_INFOS[static_cast<size_t>(id)]; }
    static constexpr std::string_view     nodeIdName(AstNodeId id) { return nodeIdInfos(id).name; }

    template<class T>
    std::pair<Ref, T*> makeNodePtr(AstNodeId id, TokenRef token)
    {
        auto result          = store_.emplace_uninit<T>();
        result.second->token = token;
#if SWC_HAS_STATS
        Stats::get().numAstNodes.fetch_add(1);
#endif
        return result;
    }

    template<class T>
    std::pair<Ref, T*> makeNodePtr(TokenRef token)
    {
        auto result          = store_.emplace_uninit<T>();
        result.second->token = token;
#if SWC_HAS_STATS
        Stats::get().numAstNodes.fetch_add(1);
#endif
        return result;
    }

    AstNodeRef makeNode(AstNodeId id, TokenRef token)
    {
        return makeNodePtr<AstNode>(id, token).first;
    }
};

SWC_END_NAMESPACE()
