#pragma once
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Support/Core/PointerSet.h"
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
    AstNodeRef argRef = AstNodeRef::invalid();

    CallArgumentPassKind    passKind    = CallArgumentPassKind::Direct;
    CallArgumentDefaultKind defaultKind = CallArgumentDefaultKind::None;

    bool bindsReferenceToValue    = false;
    bool movesValueToParam        = false;
    bool passUfcsAddressAsPointer = false;
    bool isUfcsReceiver           = false;

    ConstantRef typeInfoCstRef = ConstantRef::invalid();
    ConstantRef defaultCstRef  = ConstantRef::invalid();
};

class NodePayload
{
    friend class Sema;
    friend class SourceFile;
    friend class SemaJob;

public:
    // The store holding this node when it belongs to this payload's Ast, null otherwise.
    const Ast* storeOf(const AstNode* node) const { return ast_.tryFindNodeRef(node).isValid() ? &ast_ : nullptr; }

    struct StoredView
    {
        TypeRef                  typeRef = TypeRef::invalid();
        ConstantRef              cstRef  = ConstantRef::invalid();
        const Symbol*            sym     = nullptr;
        std::span<const Symbol*> symList = {};

        bool             hasSymbol     = false;
        bool             hasSymbolList = false;
        NodePayloadFlags flags         = static_cast<NodePayloadFlags>(0);
    };

    // Read symbols from one payload snapshot. On shared generic-evaluation nodes,
    // separate kind and value reads can race with payload replacement, treating
    // a ConstantRef or TypeRef as a PagedStore offset.
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

    // Retain the source symbol when conversion or folding replaces its payload,
    // so exported bodies still expose dependencies named in the source. By default,
    // keep symbols an export can hide (non-public or type-owned). Editor snapshots
    // additionally retain public names and selected calls before folding/inlining.
    const Symbol* foldedSourceSymbol(AstNodeRef nodeRef) const;
    void          retainEditorSymbols() { retainEditorSymbols_ = true; }

    // Fallible expressions a 'Swag.Propagate' body handles as an unwritten 'try', in no
    // particular order and possibly repeated. Only editor snapshots record them.
    std::span<const AstNodeRef> implicitPropagations() const { return implicitPropagations_; }

protected:
    Ast&       ast() { return ast_; }
    const Ast& ast() const { return ast_; }

    static NodePayloadKind payloadKind(const AstNode& node) { return static_cast<NodePayloadKind>(node.payloadBits() & NODE_PAYLOAD_KIND_MASK); }
    static bool            hasPayloadFlags(const AstNode& node, NodePayloadFlags value) { return (node.payloadBits() & static_cast<uint16_t>(value)) != 0; }

    static void setPayloadKind(AstNode& node, NodePayloadKind value);
    static void addPayloadFlags(AstNode& node, NodePayloadFlags value);
    static void removePayloadFlags(AstNode& node, NodePayloadFlags value);

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
    void                 clearConstant(AstNodeRef nodeRef);

    bool hasSubstitute(AstNodeRef nodeRef) const;
    void setSubstitute(AstNodeRef nodeRef, AstNodeRef substNodeRef);

    // Resolve substitutions while keeping the common unchanged-node path inline.
    // Every semantic view uses this lookup; only substituted nodes walk the chain.
    //
    // Inspect kind from a single payload snapshot. Concurrent generic evaluation
    // can replace the payload; a second read could misinterpret a constant/type
    // reference as a store offset.
    AstNodeRef getSubstituteRef(AstNodeRef nodeRef) const
    {
        if (nodeRef.isInvalid())
            return nodeRef;

        const AstNode& node  = ast().node(nodeRef);
        const uint64_t state = node.payloadState();
        if (static_cast<NodePayloadKind>(AstNode::payloadBitsFromState(state) & NODE_PAYLOAD_KIND_MASK) != NodePayloadKind::Substitute)
        {
#if SWC_HAS_REF_DEBUG_INFO
            nodeRef.dbgPtr = &node;
#endif
            return nodeRef;
        }

        return followSubstituteChain(nodeRef);
    }

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

    void copyResolvedCallArguments(AstNodeRef dstNodeRef, AstNodeRef srcNodeRef);
    void setResolvedCallArguments(AstNodeRef nodeRef, std::span<const ResolvedCallArgument> args);
    void appendResolvedCallArguments(AstNodeRef nodeRef, SmallVector<ResolvedCallArgument>& out) const;

    // Copy an existing argument under the shard lock; no view escapes payload replacement.
    ResolvedCallArgument getResolvedCallArgument(AstNodeRef nodeRef, uint32_t index) const;

    // Missing payloads and out-of-range indices yield no argument.
    std::optional<ResolvedCallArgument> tryGetResolvedCallArgument(AstNodeRef nodeRef, uint32_t index) const;

    bool  hasLoweringPayload(AstNodeRef nodeRef) const;
    void  setLoweringPayload(AstNodeRef nodeRef, void* payload);
    void* getLoweringPayload(AstNodeRef nodeRef) const;

    bool  hasInlinePayload(AstNodeRef nodeRef) const;
    void  setInlinePayload(AstNodeRef nodeRef, void* payload);
    void* getInlinePayload(AstNodeRef nodeRef) const;

    bool  hasInlineContextOverride(AstNodeRef nodeRef) const;
    void  setInlineContextOverride(AstNodeRef nodeRef, void* payload);
    void* getInlineContextOverride(AstNodeRef nodeRef) const;
    void  getInlineContext(AstNodeRef nodeRef, void*& outPayload, void*& outOverride) const;

    bool  hasSemaPayload(AstNodeRef nodeRef) const;
    void  setSemaPayload(AstNodeRef nodeRef, void* payload);
    void* getSemaPayload(AstNodeRef nodeRef) const;
    void  clearSemaPayload(AstNodeRef nodeRef);

    void                  setConstAssignSourceParameter(AstNodeRef nodeRef, const SymbolVariable* sourceParam);
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
        NodePayloadFlags originalFlags = static_cast<NodePayloadFlags>(0);
        uint32_t         originalRef   = 0;
        uint32_t         originalShard = 0;
    };

#if !SWC_HAS_REF_DEBUG_INFO
    static_assert(sizeof(SubstituteStorage) == 16);
#endif

    struct PayloadInfo
    {
        NodePayloadKind kind     = NodePayloadKind::Invalid;
        uint32_t        ref      = 0;
        uint32_t        shardIdx = 0;
    };

    AstNodeRef                     followSubstituteChain(AstNodeRef nodeRef) const;
    std::span<const Symbol* const> getSymbolListImpl(AstNodeRef nodeRef) const;
    void                           recordFoldedSourceSymbol(AstNodeRef nodeRef, const AstNode& node);
    void                           recordImplicitPropagation(AstNodeRef nodeRef);
    void                           setSymbolListImpl(AstNodeRef nodeRef, std::span<const Symbol* const> symbols);
    static void                    updatePayloadFlags(AstNode& node, std::span<const Symbol*> symbols);

    static void                    storePayload(AstNode& node, uint16_t bits, uint32_t ref);
    static uint16_t                applySymbolPayloadFlags(uint16_t bits, std::span<const Symbol* const> symbols);
    PayloadInfo                    payloadInfo(const AstNode& node) const;
    std::span<const Symbol* const> symbolsFromInfo(const PayloadInfo& info) const;
    NodePayloadFlags               payloadFlagsStored(const AstNode& node) const;

    Shard*       ensureShard(uint32_t shardIdx);
    Shard*       tryGetShard(uint32_t shardIdx);
    const Shard* tryGetShard(uint32_t shardIdx) const;

    Ast              ast_;
    SymbolNamespace* moduleNamespace_     = nullptr;
    SymbolNamespace* fileNamespace_       = nullptr;
    bool             retainEditorSymbols_ = false;

    std::shared_mutex       implicitPropagationsMutex_;
    std::vector<AstNodeRef> implicitPropagations_;

    struct Shard
    {
        mutable std::mutex        storeMutex;
        mutable std::shared_mutex loweringPayloadsMutex;
        mutable std::shared_mutex inlinePayloadsMutex;
        mutable std::shared_mutex inlineContextOverridesMutex;
        mutable std::shared_mutex semaPayloadsMutex;
        mutable std::shared_mutex constAssignSourceParametersMutex;
        mutable std::shared_mutex foldedSourceSymbolsMutex;
        mutable std::shared_mutex resolvedCallArgsMutex;

        PagedStore store{PagedStore::K_DEFAULT_PAGE_SIZE, PagedStore::ReverseLookup::Disabled};

        RefPointerMap<AstNodeRef> loweringPayloads;
        RefPointerMap<AstNodeRef> inlinePayloads;
        RefPointerMap<AstNodeRef> inlineContextOverrides;
        RefPointerMap<AstNodeRef> semaPayloads;

        RefPointerMap<AstNodeRef, const SymbolVariable> constAssignSourceParameters;
        RefPointerMap<AstNodeRef, const Symbol>         foldedSourceSymbols;

        // Publish side-table counts so empty tables can be queried without locking.
        // Update a count under its entry's lock: readers that must observe an entry
        // must also observe the nonzero count.
        std::atomic<uint32_t> loweringPayloadsCount{0};
        std::atomic<uint32_t> inlinePayloadsCount{0};
        std::atomic<uint32_t> inlineContextOverridesCount{0};
        std::atomic<uint32_t> semaPayloadsCount{0};
        std::atomic<uint32_t> constAssignSourceParametersCount{0};
        std::atomic<uint32_t> foldedSourceSymbolsCount{0};
        std::atomic<uint32_t> resolvedCallArgsCount{0};

        // Store call arguments inline so writers need only resolvedCallArgsMutex,
        // avoiding contention on the store shared with symbol/substitute payloads.
        std::unordered_map<AstNodeRef, SmallVector<ResolvedCallArgument, 4>> resolvedCallArgsByNode;
    };

    std::array<std::atomic<Shard*>, NODE_PAYLOAD_SHARD_NUM> shards_{};
};

SWC_END_NAMESPACE();
