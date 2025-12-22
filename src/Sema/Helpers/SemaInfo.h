#pragma once
#include "Parser/Ast.h"
#include "Sema/Constant/ConstantValue.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE()

class SymbolNamespace;
class Symbol;
class SemaScope;

enum class NodeSemaKind : uint8_t
{
    Invalid     = 0,
    ConstantRef = 1,
    TypeRef     = 2,
    SymbolRef   = 3,
    Substitute  = 4,
};

class SemaInfo
{
    Ast              ast_;
    SymbolNamespace* moduleNamespace_ = nullptr;
    SymbolNamespace* fileNamespace_   = nullptr;

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

    const SymbolNamespace& moduleNamespace() const { return *moduleNamespace_; }
    SymbolNamespace&       moduleNamespace() { return *moduleNamespace_; }
    void                   setModuleNamespace(SymbolNamespace& ns) { moduleNamespace_ = &ns; }

    const SymbolNamespace& fileNamespace() const { return *fileNamespace_; }
    SymbolNamespace&       fileNamespace() { return *fileNamespace_; }
    void                   setFileNamespace(SymbolNamespace& ns) { fileNamespace_ = &ns; }

    bool                 hasConstant(const TaskContext& ctx, AstNodeRef nodeRef) const;
    const ConstantValue& getConstant(const TaskContext& ctx, AstNodeRef nodeRef) const;
    ConstantRef          getConstantRef(const TaskContext& ctx, AstNodeRef nodeRef) const;
    void                 setConstant(AstNodeRef nodeRef, ConstantRef ref);

    bool       hasSubstitute(AstNodeRef nodeRef) const;
    void       setSubstitute(AstNodeRef nodeRef, AstNodeRef substNodeRef);
    AstNodeRef getSubstituteRef(const TaskContext&, AstNodeRef nodeRef) const;

    bool    hasType(AstNodeRef nodeRef) const;
    TypeRef getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const;
    void    setType(AstNodeRef nodeRef, TypeRef ref);

    bool          hasSymbol(AstNodeRef nodeRef) const;
    const Symbol& getSymbol(const TaskContext&, AstNodeRef nodeRef) const;
    Symbol&       getSymbol(const TaskContext&, AstNodeRef nodeRef);
    void          setSymbol(AstNodeRef nodeRef, Symbol* symbol);
    void          setSymbol(AstNodeRef nodeRef, const Symbol* symbol);
};

SWC_END_NAMESPACE()
