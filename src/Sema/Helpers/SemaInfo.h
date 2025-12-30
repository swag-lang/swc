#pragma once
#include "Parser/Ast.h"
#include "Sema/Constant/ConstantValue.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE()

class SymbolNamespace;
class Symbol;
class SemaScope;

constexpr uint8_t SEMA_KIND_MASK = 0x7;

enum class NodeSemaKind : uint8_t
{
    Invalid     = 0,
    ConstantRef = 1,
    TypeRef     = 2,
    SymbolRef   = 3,
    Substitute  = 4,
    Payload     = 5,
};

enum class NodeSemaFlags : uint8_t
{
    ValueExpr = 1 << 7,
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

    static NodeSemaKind  semaKind(const AstNode& node) { return static_cast<NodeSemaKind>(node.semaBits() & SEMA_KIND_MASK); }
    static void          setSemaKind(AstNode& node, NodeSemaKind value) { node.semaBits() = (node.semaBits() & ~SEMA_KIND_MASK) | static_cast<uint8_t>(value); }
    static void          addSemaFlags(AstNode& node, NodeSemaFlags value) { node.semaBits() |= static_cast<uint8_t>(value); }
    static void          removeSemaFlags(AstNode& node, NodeSemaFlags value) { node.semaBits() &= ~static_cast<uint8_t>(value); }
    static bool          hasSemaFlags(const AstNode& node, NodeSemaFlags value) { return (node.semaBits() & static_cast<uint8_t>(value)) != 0; }
    static NodeSemaFlags semaFlags(const AstNode& node) { return static_cast<NodeSemaFlags>(node.semaBits() & ~SEMA_KIND_MASK); }

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
    AstNodeRef getSubstituteRef(AstNodeRef nodeRef) const;

    bool    hasType(AstNodeRef nodeRef) const;
    TypeRef getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const;
    void    setType(AstNodeRef nodeRef, TypeRef ref);

    bool          hasSymbol(AstNodeRef nodeRef) const;
    const Symbol& getSymbol(const TaskContext&, AstNodeRef nodeRef) const;
    Symbol&       getSymbol(const TaskContext&, AstNodeRef nodeRef);
    void          setSymbol(AstNodeRef nodeRef, const Symbol* symbol);

    bool  hasPayload(AstNodeRef nodeRef) const;
    void  setPayload(AstNodeRef nodeRef, void* payload);
    void* getPayload(AstNodeRef nodeRef) const;
};

SWC_END_NAMESPACE()
