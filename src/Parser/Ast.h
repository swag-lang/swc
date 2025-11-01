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
    std::pair<Ref, T*> makeNode()
    {
        auto result = store_.emplace_uninit<T>();
#if SWC_HAS_STATS
        Stats::get().numAstNodes.fetch_add(1);
#endif
        return result;
    }

    template<AstNodeId T>
    std::pair<Ref, AstTypeOf<T>*> makeNode()
    {
        auto result = store_.emplace_uninit<AstTypeOf<T>>();
#if SWC_HAS_STATS
        Stats::get().numAstNodes.fetch_add(1);
#endif
        return result;
    }
};

SWC_END_NAMESPACE()
