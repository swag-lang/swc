#pragma once
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE()

class SemaContext
{
    Ast ast_;

    struct Shard
    {
        std::shared_mutex                      mutex;
        std::unordered_map<uint32_t, uint32_t> map;
    };

    constexpr static uint32_t NUM_SHARDS = 16;
    Shard                     shards_[NUM_SHARDS];

public:
    Ast&       ast() { return ast_; }
    const Ast& ast() const { return ast_; }

    TypeInfoRef getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const;
};

SWC_END_NAMESPACE()
