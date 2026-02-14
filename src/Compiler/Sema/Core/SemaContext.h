#pragma once
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include <unordered_map>

SWC_BEGIN_NAMESPACE();

class SymbolNamespace;
class Symbol;
class SemaScope;

constexpr uint16_t        NODE_PAYLOAD_KIND_MASK   = 0x000F;
constexpr uint16_t        NODE_PAYLOAD_SHARD_MASK  = 0x00F0;
constexpr uint16_t        NODE_PAYLOAD_FLAGS_MASK  = 0xFF00;
constexpr uint16_t        NODE_PAYLOAD_SHARD_SHIFT = 4;
constexpr static uint32_t NODE_PAYLOAD_SHARD_NUM   = 1 << NODE_PAYLOAD_SHARD_SHIFT;

enum class NodePayloadKind : uint16_t
{
    Invalid     = 0,
    ConstantRef = 1,
    TypeRef     = 2,
    SymbolRef   = 3,
    Substitute  = 4,
    Payload     = 5,
    SymbolList  = 6,
};

enum class NodePayloadFlags : uint16_t
{
    FoldedTypedConst = 1 << 13,
    LValue           = 1 << 14,
    Value            = 1 << 15,
};

class SemaContext
{
    friend class Sema;
    friend class SourceFile;
    friend class SemaJob;

protected:
    Ast&       ast() { return ast_; }
    const Ast& ast() const { return ast_; }

    static NodePayloadKind  payloadKind(const AstNode& node) { return static_cast<NodePayloadKind>(node.payloadBits() & NODE_PAYLOAD_KIND_MASK); }
    static void             setPayloadKind(AstNode& node, NodePayloadKind value) { node.payloadBits() = (node.payloadBits() & ~NODE_PAYLOAD_KIND_MASK) | static_cast<uint16_t>(value); }
    static uint32_t         payloadShard(const AstNode& node) { return (node.payloadBits() & NODE_PAYLOAD_SHARD_MASK) >> NODE_PAYLOAD_SHARD_SHIFT; }
    static void             setPayloadShard(AstNode& node, uint32_t shard) { node.payloadBits() = (node.payloadBits() & ~NODE_PAYLOAD_SHARD_MASK) | static_cast<uint16_t>(shard << NODE_PAYLOAD_SHARD_SHIFT); }
    static void             addPayloadFlags(AstNode& node, NodePayloadFlags value) { node.payloadBits() |= static_cast<uint16_t>(value); }
    static void             removePayloadFlags(AstNode& node, NodePayloadFlags value) { node.payloadBits() &= ~static_cast<uint16_t>(value); }
    static bool             hasPayloadFlags(const AstNode& node, NodePayloadFlags value) { return (node.payloadBits() & static_cast<uint16_t>(value)) != 0; }
    static NodePayloadFlags payloadFlags(const AstNode& node) { return static_cast<NodePayloadFlags>(node.payloadBits() & ~NODE_PAYLOAD_KIND_MASK & ~NODE_PAYLOAD_SHARD_MASK); }

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

    bool    hasType(const TaskContext& ctx, AstNodeRef nodeRef) const;
    TypeRef getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const;
    void    setType(AstNodeRef nodeRef, TypeRef ref);

    bool          hasSymbol(AstNodeRef nodeRef) const;
    const Symbol& getSymbol(const TaskContext&, AstNodeRef nodeRef) const;
    Symbol&       getSymbol(const TaskContext&, AstNodeRef nodeRef);
    void          setSymbol(AstNodeRef nodeRef, const Symbol* symbol);

    bool                     hasSymbolList(AstNodeRef nodeRef) const;
    std::span<const Symbol*> getSymbolList(AstNodeRef nodeRef) const;
    std::span<Symbol*>       getSymbolList(AstNodeRef nodeRef);
    void                     setSymbolList(AstNodeRef nodeRef, std::span<const Symbol*> symbols);
    void                     setSymbolList(AstNodeRef nodeRef, std::span<Symbol*> symbols);

    bool  hasPayload(AstNodeRef nodeRef) const;
    void  setPayload(AstNodeRef nodeRef, void* payload);
    void* getPayload(AstNodeRef nodeRef) const;
    bool  hasCodeGenPayload(AstNodeRef nodeRef) const;
    void  setCodeGenPayload(AstNodeRef nodeRef, void* payload);
    void* getCodeGenPayload(AstNodeRef nodeRef) const;

    static void propagatePayloadFlags(AstNode& nodeDst, const AstNode& nodeSrc, uint16_t mask, bool merge);
    static void inheritPayloadKindRef(AstNode& nodeDst, const AstNode& nodeSrc);
    static void inheritPayload(AstNode& nodeDst, const AstNode& nodeSrc);

private:
    std::span<const Symbol*> getSymbolListImpl(AstNodeRef nodeRef) const;
    void                     setSymbolListImpl(AstNodeRef nodeRef, std::span<const Symbol*> symbols);
    void                     setSymbolListImpl(AstNodeRef nodeRef, std::span<Symbol*> symbols);
    static void              updatePayloadFlags(AstNode& node, std::span<const Symbol*> symbols);

    Ast              ast_;
    SymbolNamespace* moduleNamespace_ = nullptr;
    SymbolNamespace* fileNamespace_   = nullptr;

    struct Shard
    {
        mutable std::shared_mutex           mutex;
        PagedStore                          store;
        std::unordered_map<uint32_t, void*> codeGenPayloads;
    };

    Shard shards_[NODE_PAYLOAD_SHARD_NUM];
};

SWC_END_NAMESPACE();
