#pragma once
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class SymbolNamespace;
class Symbol;
class SymbolVariable;
class SemaScope;

constexpr uint16_t        NODE_PAYLOAD_KIND_MASK   = 0x000F;
constexpr uint16_t        NODE_PAYLOAD_SHARD_MASK  = 0x00F0;
constexpr uint16_t        NODE_PAYLOAD_FLAGS_MASK  = 0xFF00;
constexpr uint16_t        NODE_PAYLOAD_SHARD_SHIFT = 4;
constexpr static uint32_t NODE_PAYLOAD_SHARD_NUM   = 1 << NODE_PAYLOAD_SHARD_SHIFT;

enum class NodePayloadKind : uint16_t
{
    Invalid         = 0,
    ConstantRef     = 1,
    TypeRef         = 2,
    SymbolRef       = 3,
    Substitute      = 4,
    ExternalStorage = 5,
    SymbolList      = 6,
};

enum class NodePayloadFlags : uint16_t
{
    ConstAssignBinding = 1 << 11,
    ConstAssignTarget  = 1 << 12,
    FoldedTypedConst   = 1 << 13,
    LValue             = 1 << 14,
    Value              = 1 << 15,
};

enum class CallArgumentPassKind : uint8_t
{
    Direct          = 0,
    InterfaceObject = 1,
};

enum class CallArgumentDefaultKind : uint8_t
{
    None           = 0,
    Constant       = 1,
    CallerLocation = 2,
};

struct ResolvedCallArgument
{
    AstNodeRef              argRef                   = AstNodeRef::invalid();
    CallArgumentPassKind    passKind                 = CallArgumentPassKind::Direct;
    CallArgumentDefaultKind defaultKind              = CallArgumentDefaultKind::None;
    bool                    bindsReferenceToValue    = false;
    bool                    movesValueToParam        = false;
    bool                    passUfcsAddressAsPointer = false;
    ConstantRef             typeInfoCstRef           = ConstantRef::invalid();
    ConstantRef             defaultCstRef            = ConstantRef::invalid();
};

class NodePayload
{
    friend class Sema;
    friend class SourceFile;
    friend class SemaJob;

public:
    struct StoredView
    {
        TypeRef                  typeRef       = TypeRef::invalid();
        ConstantRef              cstRef        = ConstantRef::invalid();
        const Symbol*            sym           = nullptr;
        std::span<const Symbol*> symList       = {};
        bool                     hasSymbol     = false;
        bool                     hasSymbolList = false;
        NodePayloadFlags         flags         = static_cast<NodePayloadFlags>(0);
    };

    // Resolved symbol payload read from a single payload snapshot. Reading the symbol(s)
    // from one snapshot (rather than a hasSymbol()/getSymbol() pair of separate atomic
    // loads) is mandatory for nodes that can be mutated concurrently (shared generic eval
    // nodes): a kind transition between the two reads would otherwise reinterpret a
    // ConstantRef/TypeRef value as a PagedStore offset and index past the store's pages.
    struct ResolvedSymbols
    {
        std::span<const Symbol* const> symbols      = {};
        bool                           isSymbolList = false;
    };

    NodePayload() = default;
    ~NodePayload();
    bool            hasResolvedCallArguments(AstNodeRef nodeRef) const;
    StoredView      viewStored(const TaskContext& ctx, AstNodeRef nodeRef) const;
    ResolvedSymbols resolveSymbols(AstNodeRef nodeRef) const;

protected:
    Ast&       ast() { return ast_; }
    const Ast& ast() const { return ast_; }

    static NodePayloadKind  payloadKind(const AstNode& node) { return static_cast<NodePayloadKind>(node.payloadBits() & NODE_PAYLOAD_KIND_MASK); }
    static uint32_t         payloadShard(const AstNode& node) { return (node.payloadBits() & NODE_PAYLOAD_SHARD_MASK) >> NODE_PAYLOAD_SHARD_SHIFT; }
    static bool             hasPayloadFlags(const AstNode& node, NodePayloadFlags value) { return (node.payloadBits() & static_cast<uint16_t>(value)) != 0; }
    static NodePayloadFlags payloadFlags(const AstNode& node) { return static_cast<NodePayloadFlags>(node.payloadBits() & ~NODE_PAYLOAD_KIND_MASK & ~NODE_PAYLOAD_SHARD_MASK); }
    static void             setPayloadKind(AstNode& node, NodePayloadKind value);
    static void             setPayloadShard(AstNode& node, uint32_t shard);
    static void             addPayloadFlags(AstNode& node, NodePayloadFlags value);
    static void             removePayloadFlags(AstNode& node, NodePayloadFlags value);

    const SymbolNamespace& moduleNamespace() const { return *(moduleNamespace_); }
    SymbolNamespace&       moduleNamespace() { return *(moduleNamespace_); }
    void                   setModuleNamespace(SymbolNamespace& ns) { moduleNamespace_ = &ns; }

    const SymbolNamespace& fileNamespace() const { return *(fileNamespace_); }
    SymbolNamespace&       fileNamespace() { return *(fileNamespace_); }
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
    const Symbol& getSymbol(const TaskContext& ctx, AstNodeRef nodeRef) const;
    Symbol&       getSymbol(const TaskContext& ctx, AstNodeRef nodeRef);
    void          setSymbol(AstNodeRef nodeRef, const Symbol* symbol);

    bool                     hasSymbolList(AstNodeRef nodeRef) const;
    std::span<const Symbol*> getSymbolList(AstNodeRef nodeRef) const;
    std::span<Symbol*>       getSymbolList(AstNodeRef nodeRef);
    void                     setSymbolList(AstNodeRef nodeRef, std::span<const Symbol*> symbols);
    void                     setSymbolList(AstNodeRef nodeRef, std::span<Symbol*> symbols);

    void  copyResolvedCallArguments(AstNodeRef dstNodeRef, AstNodeRef srcNodeRef);
    void  setResolvedCallArguments(AstNodeRef nodeRef, std::span<const ResolvedCallArgument> args);
    void  appendResolvedCallArguments(AstNodeRef nodeRef, SmallVector<ResolvedCallArgument>& out) const;
    bool  hasLoweringPayload(AstNodeRef nodeRef) const;
    void  setLoweringPayload(AstNodeRef nodeRef, void* payload);
    void* getLoweringPayload(AstNodeRef nodeRef) const;
    bool  hasInlinePayload(AstNodeRef nodeRef) const;
    void  setInlinePayload(AstNodeRef nodeRef, void* payload);
    void* getInlinePayload(AstNodeRef nodeRef) const;
    bool  hasInlineContextOverride(AstNodeRef nodeRef) const;
    void  setInlineContextOverride(AstNodeRef nodeRef, void* payload);
    void* getInlineContextOverride(AstNodeRef nodeRef) const;
    bool  hasSemaPayload(AstNodeRef nodeRef) const;
    void  setSemaPayload(AstNodeRef nodeRef, void* payload);
    void* getSemaPayload(AstNodeRef nodeRef) const;
    void  clearSemaPayload(AstNodeRef nodeRef);
    void  setConstAssignSourceParameter(AstNodeRef nodeRef, const SymbolVariable* sourceParam);
    const SymbolVariable* getConstAssignSourceParameter(AstNodeRef nodeRef) const;

    static void propagatePayloadFlags(AstNode& nodeDst, const AstNode& nodeSrc, uint16_t mask, bool merge);
    static void inheritPayloadKindRef(AstNode& nodeDst, const AstNode& nodeSrc);
    static void inheritPayload(AstNode& nodeDst, const AstNode& nodeSrc);

private:
    struct Shard;

    struct SubstituteStorage
    {
        AstNodeRef       substNodeRef  = AstNodeRef::invalid();
        NodePayloadKind  originalKind  = NodePayloadKind::Invalid;
        uint32_t         originalRef   = 0;
        uint32_t         originalShard = 0;
        NodePayloadFlags originalFlags = static_cast<NodePayloadFlags>(0);
    };

    struct PayloadInfo
    {
        NodePayloadKind kind     = NodePayloadKind::Invalid;
        uint32_t        ref      = 0;
        uint32_t        shardIdx = 0;
    };

    std::span<const Symbol* const> getSymbolListImpl(AstNodeRef nodeRef) const;
    void                           setSymbolListImpl(AstNodeRef nodeRef, std::span<const Symbol*> symbols);
    void                           setSymbolListImpl(AstNodeRef nodeRef, std::span<Symbol*> symbols);
    static void                    updatePayloadFlags(AstNode& node, std::span<const Symbol*> symbols);
    static void                    storePayload(AstNode& node, uint16_t bits, uint32_t ref);
    static uint16_t                applySymbolPayloadFlags(uint16_t bits, std::span<const Symbol*> symbols);
    PayloadInfo                    payloadInfo(const AstNode& node) const;
    std::span<const Symbol* const> symbolsFromInfo(const PayloadInfo& info) const;
    NodePayloadFlags               payloadFlagsStored(const AstNode& node) const;
    SubstituteStorage*             substituteStorage(const AstNode& node);
    const SubstituteStorage*       substituteStorage(const AstNode& node) const;
    Shard*                         ensureShard(uint32_t shardIdx);
    Shard*                         tryGetShard(uint32_t shardIdx);
    const Shard*                   tryGetShard(uint32_t shardIdx) const;

    Ast              ast_;
    SymbolNamespace* moduleNamespace_ = nullptr;
    SymbolNamespace* fileNamespace_   = nullptr;

    struct Shard
    {
        mutable std::mutex                    storeMutex;
        mutable std::shared_mutex             loweringPayloadsMutex;
        mutable std::shared_mutex             inlinePayloadsMutex;
        mutable std::shared_mutex             inlineContextOverridesMutex;
        mutable std::shared_mutex             semaPayloadsMutex;
        mutable std::shared_mutex             constAssignSourceParametersMutex;
        mutable std::shared_mutex             resolvedCallArgsMutex;
        PagedStore                            store;
        std::unordered_map<AstNodeRef, void*>                  loweringPayloads;
        std::unordered_map<AstNodeRef, void*>                  inlinePayloads;
        std::unordered_map<AstNodeRef, void*>                  inlineContextOverrides;
        std::unordered_map<AstNodeRef, void*>                  semaPayloads;
        std::unordered_map<AstNodeRef, const SymbolVariable*> constAssignSourceParameters;

        // Resolved call arguments are stored inline (not in `store`) so writing them only
        // contends on `resolvedCallArgsMutex`, never on the hot `storeMutex` shared with the
        // symbol/substitute payload writers.
        std::unordered_map<AstNodeRef, SmallVector<ResolvedCallArgument, 4>> resolvedCallArgsByNode;
    };

    std::array<std::atomic<Shard*>, NODE_PAYLOAD_SHARD_NUM> shards_{};
};

SWC_END_NAMESPACE();
