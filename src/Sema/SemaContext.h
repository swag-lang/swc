#pragma once
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE()

class Symbol;

class SemaContext
{
    Ast ast_;

    struct Shard
    {
        std::shared_mutex mutex;
        Store<>           store;
    };

    constexpr static uint32_t NUM_SHARDS = 16;
    Shard                     shards_[NUM_SHARDS];

public:
    Ast&       ast() { return ast_; }
    const Ast& ast() const { return ast_; }

    TypeInfoRef getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const;
    SemaRef     addSymbol(AstNodeRef nodeRef, Symbol* symbol);
};

SWC_END_NAMESPACE()
