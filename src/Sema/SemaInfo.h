#pragma once
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE()

class Symbol;
class Scope;

enum class NodeSemaKind : uint8_t
{
    IsConstantRef = 1,
    IsTypeRef     = 2,
    IsSymbolRef   = 3,
};

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

    static NodeSemaKind&       semaNodeKind(AstNode& node) { return reinterpret_cast<NodeSemaKind&>(node.semaKindRaw()); }
    static const NodeSemaKind& semaNodeKind(const AstNode& node) { return reinterpret_cast<const NodeSemaKind&>(node.semaKindRaw()); }

    bool hasConstant(AstNodeRef nodeRef) const;
    bool hasType(AstNodeRef nodeRef) const;
    bool hasSymbol(AstNodeRef nodeRef) const;

    TypeRef     getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const;
    ConstantRef getConstantRef(AstNodeRef nodeRef) const;

    const ConstantValue& getConstant(const TaskContext& ctx, AstNodeRef nodeRef) const;
    const Symbol&        getSymbol(const TaskContext&, AstNodeRef nodeRef) const;

    void    setType(AstNodeRef nodeRef, TypeRef ref);
    void    setConstant(AstNodeRef nodeRef, ConstantRef ref);
    SemaRef setSymbol(AstNodeRef nodeRef, Symbol* symbol);
};

SWC_END_NAMESPACE()
