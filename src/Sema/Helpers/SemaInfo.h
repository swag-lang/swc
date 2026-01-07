#pragma once
#include "Parser/Ast.h"
#include "Sema/Constant/ConstantValue.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

class SymbolNamespace;
class Symbol;
class SemaScope;

constexpr uint16_t        SEMA_KIND_MASK   = 0x000F;
constexpr uint16_t        SEMA_SHARD_MASK  = 0x00F0;
constexpr uint16_t        SEMA_SHARD_SHIFT = 4;
constexpr static uint32_t SEMA_SHARD_NUM   = 1 << SEMA_SHARD_SHIFT;

enum class NodeSemaKind : uint16_t
{
    Invalid     = 0,
    ConstantRef = 1,
    TypeRef     = 2,
    SymbolRef   = 3,
    Substitute  = 4,
    Payload     = 5,
};

enum class NodeSemaFlags : uint16_t
{
    LValue = 1 << 14,
    Value  = 1 << 15,
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

    Shard shards_[SEMA_SHARD_NUM];

public:
    Ast&       ast() { return ast_; }
    const Ast& ast() const { return ast_; }

    static NodeSemaKind  semaKind(const AstNode& node) { return static_cast<NodeSemaKind>(node.semaBits() & SEMA_KIND_MASK); }
    static void          setSemaKind(AstNode& node, NodeSemaKind value) { node.semaBits() = (node.semaBits() & ~SEMA_KIND_MASK) | static_cast<uint16_t>(value); }
    static uint32_t      semaShard(const AstNode& node) { return (node.semaBits() & SEMA_SHARD_MASK) >> SEMA_SHARD_SHIFT; }
    static void          setSemaShard(AstNode& node, uint32_t shard) { node.semaBits() = (node.semaBits() & ~SEMA_SHARD_MASK) | static_cast<uint16_t>(shard << SEMA_SHARD_SHIFT); }
    static void          addSemaFlags(AstNode& node, NodeSemaFlags value) { node.semaBits() |= static_cast<uint16_t>(value); }
    static void          removeSemaFlags(AstNode& node, NodeSemaFlags value) { node.semaBits() &= ~static_cast<uint16_t>(value); }
    static bool          hasSemaFlags(const AstNode& node, NodeSemaFlags value) { return (node.semaBits() & static_cast<uint16_t>(value)) != 0; }
    static NodeSemaFlags semaFlags(const AstNode& node) { return static_cast<NodeSemaFlags>(node.semaBits() & ~SEMA_KIND_MASK & ~SEMA_SHARD_MASK); }

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

SWC_END_NAMESPACE();
