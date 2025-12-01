#pragma once
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE()

class Symbol;

class SemaInfo
{
    Ast ast_;

    struct Shard
    {
        std::shared_mutex mutex;
        Store             store;
    };

    constexpr static uint32_t NUM_SHARDS = 16;
    Shard                     shards_[NUM_SHARDS];

public:
    Ast&       ast() { return ast_; }
    const Ast& ast() const { return ast_; }

    void                 setConstant(AstNodeRef nodeRef, ConstantRef ref);
    bool                 hasConstant(AstNodeRef nodeRef) const;
    ConstantRef          getConstantRef(AstNodeRef nodeRef) const;
    const ConstantValue& getConstant(const TaskContext& ctx, AstNodeRef nodeRef) const;

    void    setType(AstNodeRef nodeRef, TypeRef ref);
    bool    hasType(AstNodeRef nodeRef) const;
    TypeRef getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const;

    SemaRef setSymbol(AstNodeRef nodeRef, Symbol* symbol);
};

SWC_END_NAMESPACE()
