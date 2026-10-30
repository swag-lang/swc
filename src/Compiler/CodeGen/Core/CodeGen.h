#pragma once
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroReg.h"
#include "Backend/RuntimeBuildConfig.h"
#include "Compiler/CodeGen/Core/CodeGenNodePayload.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Support/Core/Flags.h"
#include "Support/Core/PointerSet.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Memory/Arena.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class MicroBuilder;
class CompilerInstance;
class ConstantManager;
class TypeManager;
class TypeInfo;
class TypeGen;
class IdentifierManager;
class SourceView;
class SymbolVariable;
struct ResolvedCallArgument;
struct Token;
struct SemaInlinePayload;

namespace CodeGenFunctionHelpers
{
    struct FunctionParameterInfo;
}

struct CodeGenGlobalToDropEntry
{
    const SymbolVariable* variable = nullptr;
    const SymbolFunction* opDrop   = nullptr;
    uint32_t              sizeOf   = 0;
    uint32_t              count    = 0;
};

struct CodeGenTemporaryDrop
{
    AstNodeRef            flushRootRef = AstNodeRef::invalid();
    TypeRef               typeRef      = TypeRef::invalid();
    const SymbolVariable* storageSym   = nullptr;
};

enum class CodeGenLifecycleKind : uint8_t
{
    Drop,
    PostCopy,
    PostMove,
};

struct ScopedDebugNoStep final
{
    ScopedDebugNoStep(MicroBuilder& builder, const bool value) :
        builder(&builder),
        savedValue(builder.currentDebugNoStep())
    {
        builder.setCurrentDebugNoStep(value);
    }

    ~ScopedDebugNoStep()
    {
        builder->setCurrentDebugNoStep(savedValue);
    }

    MicroBuilder* builder    = nullptr;
    bool          savedValue = false;
};

struct ScopedDebugSource final
{
    ScopedDebugSource(MicroBuilder& builder, const SourceCodeRef& value) :
        builder(&builder),
        savedValue(builder.currentDebugSourceCodeRef())
    {
        if (value.isValid())
            builder.setCurrentDebugSourceCodeRef(value);
    }

    ~ScopedDebugSource()
    {
        builder->setCurrentDebugSourceCodeRef(savedValue);
    }

    MicroBuilder* builder = nullptr;
    SourceCodeRef savedValue;
};

struct CodeGenDeferredAction
{
    enum class Kind : uint8_t
    {
        DeferStmt,
        ImplicitDrop,
        PopErrorScope,
        EndValueBorrow,
    };

    Kind                 kind               = Kind::DeferStmt;
    CodeGenLifecycleKind lifecycleKind      = CodeGenLifecycleKind::Drop;
    uint32_t             borrowRecordOffset = 0;

    AstNodeRef       deferStmtRef = AstNodeRef::invalid();
    AstNodeRef       bodyRef      = AstNodeRef::invalid();
    AstModifierFlags modifierFlags;

    TypeRef               lifecycleTypeRef = TypeRef::invalid();
    const SymbolVariable* variable         = nullptr;
};

#if !SWC_HAS_REF_DEBUG_INFO
static_assert(sizeof(void*) != 8 || sizeof(CodeGenDeferredAction) == 32);
static_assert(sizeof(void*) != 8 || sizeof(CodeGenTemporaryDrop) == 16);
#endif

struct CodeGenDeferScope
{
    AstNodeRef    scopeRef      = AstNodeRef::invalid();
    AstNodeRef    breakOwnerRef = AstNodeRef::invalid();
    AstNodeRef    switchCaseRef = AstNodeRef::invalid();
    MicroInstrRef entryRef      = MicroInstrRef::invalid();

    SmallVector<CodeGenDeferredAction, 4> actions;
    bool                                  borrowOnly = false;
};

// Move-elision facts: last lexical use, declaring block, and address escapes.
// An escaped address forbids skipping reset/drop. deferEscaped tracks defer
// bodies and closures, the observers that can outlive a move at return.
struct CodeGenMoveElisionVar
{
    AstNodeRef lastUseRef   = AstNodeRef::invalid();
    AstNodeRef declBlockRef = AstNodeRef::invalid();
    bool       escaped      = false;
    bool       deferEscaped = false;
};

struct CodeGenDeferredEmissionCursor
{
    size_t scopeIndex      = 0;
    size_t nextActionCount = 0;
};

class CodeGenFrame
{
public:
    // A 'scope' is deliberately absent: it is reachable by 'break to <name>' only, never by a
    // bare 'break' or by 'continue', so it never becomes the current break or continue context.
    enum class BreakContextKind : uint8_t
    {
        None,
        Loop,
        Switch,
    };

    struct BreakContext
    {
        AstNodeRef       nodeRef = AstNodeRef::invalid();
        BreakContextKind kind    = BreakContextKind::None;
    };

    struct InlineContext
    {
        const SemaInlinePayload* payload          = nullptr;
        SymbolVariable*         resultStorageSym = nullptr;

        AstNodeRef    rootNodeRef      = AstNodeRef::invalid();
        MicroLabelRef doneLabel        = MicroLabelRef::invalid();
        MicroReg      resultStorageReg = MicroReg::invalid();

        bool noOuterDoneLabel    = false; // true when in local-function context
        bool directReturnStorage = false; // the result is built in the enclosing return storage
    };

    const BreakContext& currentBreakContext() const { return breakable_; }
    void                setCurrentBreakContent(AstNodeRef nodeRef, BreakContextKind kind);
    BreakContextKind    currentBreakableKind() const { return breakable_.kind; }

    const BreakContext& currentContinueContext() const { return continuable_; }
    BreakContextKind    currentContinuableKind() const { return continuable_.kind; }

    AstNodeRef currentSwitch() const { return currentSwitch_; }
    void       setCurrentSwitch(AstNodeRef nodeRef) { currentSwitch_ = nodeRef; }
    AstNodeRef currentSwitchCase() const { return currentSwitchCase_; }
    void       setCurrentSwitchCase(AstNodeRef nodeRef) { currentSwitchCase_ = nodeRef; }

    MicroLabelRef currentLoopContinueLabel() const { return currentLoopContinueLabel_; }
    void          setCurrentLoopContinueLabel(MicroLabelRef labelRef) { currentLoopContinueLabel_ = labelRef; }
    MicroLabelRef currentLoopBreakLabel() const { return currentLoopBreakLabel_; }
    void          setCurrentLoopBreakLabel(MicroLabelRef labelRef) { currentLoopBreakLabel_ = labelRef; }
    bool          currentLoopHasContinueJump() const { return currentLoopHasContinueJump_; }
    void          setCurrentLoopHasContinueJump(bool value) { currentLoopHasContinueJump_ = value; }

    const InlineContext& currentInlineContext() const { return inlineContext_; }
    InlineContext&       currentInlineContext() { return inlineContext_; }
    void                 setCurrentInlineContext(AstNodeRef rootNodeRef, const SemaInlinePayload* payload, MicroLabelRef doneLabel);
    void                 clearCurrentInlineContext() { inlineContext_ = {}; }
    AstNodeRef           currentInlineBoundaryRootRef() const { return inlineBoundaryRootRef_; }
    void                 setCurrentInlineBoundaryRootRef(AstNodeRef nodeRef) { inlineBoundaryRootRef_ = nodeRef; }
    void                 setCurrentInlineDoneLabel(MicroLabelRef doneLabel) { inlineContext_.doneLabel = doneLabel; }
    bool                 hasCurrentInlineBoundary() const { return inlineBoundaryRootRef_.isValid(); }
    bool                 hasCurrentInlineContext() const { return inlineContext_.payload != nullptr && inlineContext_.rootNodeRef.isValid(); }

private:
    BreakContext breakable_;
    BreakContext continuable_;

    AstNodeRef currentSwitch_     = AstNodeRef::invalid();
    AstNodeRef currentSwitchCase_ = AstNodeRef::invalid();

    MicroLabelRef currentLoopContinueLabel_   = MicroLabelRef::invalid();
    MicroLabelRef currentLoopBreakLabel_      = MicroLabelRef::invalid();
    AstNodeRef    inlineBoundaryRootRef_      = AstNodeRef::invalid();
    bool          currentLoopHasContinueJump_ = false;

    InlineContext inlineContext_;
};

#if !SWC_HAS_REF_DEBUG_INFO
static_assert(sizeof(void*) != 8 || sizeof(CodeGenFrame::InlineContext) == 32);
static_assert(sizeof(void*) != 8 || sizeof(CodeGenFrame) == 72);
#endif

class CodeGen
{
public:
    using LifecycleKind = CodeGenLifecycleKind;

    explicit CodeGen(Sema& sema);
    Result exec(SymbolFunction& symbolFunc, AstNodeRef root);

    // Appends one stage per '--print-micro' request whose pattern names `scopedName`.
    static void appendCommandLinePrintMicroStages(std::vector<Utf8>& stages, std::span<const Utf8> requests, std::string_view scopedName);

    Sema&                   sema() { return *(sema_); }
    const Sema&             sema() const { return *(sema_); }
    TaskContext&            ctx();
    const TaskContext&      ctx() const;
    CompilerInstance&       compiler();
    const CompilerInstance& compiler() const;

    const Runtime::BuildCfg&        buildCfg() const;
    const Runtime::BuildCfgBackend& buildCfgBackend() const { return buildCfg().backend; }
    Runtime::BuildCfgBackendKind    buildCfgBackendKind() const { return buildCfg().backendKind; }
    bool                            isDebugInfoEnabled() const { return buildCfgBackend().debugInfo; }
    bool                            isNativeBuild() const { return Runtime::backendKindProducesNativeArtifact(buildCfgBackendKind()); }
    bool                            isNativeExecutableBuild() const { return buildCfgBackendKind() == Runtime::BuildCfgBackendKind::Executable; }

    ConstantManager&         cstMgr();
    const ConstantManager&   cstMgr() const;
    TypeManager&             typeMgr();
    const TypeManager&       typeMgr() const;
    TypeGen&                 typeGen();
    const TypeGen&           typeGen() const;
    IdentifierManager&       idMgr();
    const IdentifierManager& idMgr() const;

    MicroBuilder&       builder() { return *(builder_); }
    const MicroBuilder& builder() const { return *(builder_); }

    Ast&              ast();
    const Ast&        ast() const;
    SourceView&       srcView(SourceViewRef srcViewRef);
    const SourceView& srcView(SourceViewRef srcViewRef) const;
    AstNode&          node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode&    node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }

    AstVisit&       visit() { return visit_; }
    const AstVisit& visit() const { return visit_; }
    AstNodeRef      curNodeRef() const { return visit_.currentNodeRef(); }
    AstNode&        curNode() { return node(curNodeRef()); }
    const AstNode&  curNode() const { return node(curNodeRef()); }
    const Token&    token(const SourceCodeRef& codeRef) const;

    CodeGenFrame&                 frame() { return frames_.back(); }
    const CodeGenFrame&           frame() const { return frames_.back(); }
    std::span<const CodeGenFrame> frames() const { return frames_; }

    SemaNodeView view(AstNodeRef nodeRef) { return sema().view(nodeRef); }
    SemaNodeView view(AstNodeRef nodeRef, EnumFlags<SemaNodeViewPartE> part) { return sema().view(nodeRef, part); }

    AstNodeRef resolvedNodeRef(AstNodeRef nodeRef) { return sema().resolvedNodeRef(nodeRef); }
    AstNodeRef resolvedNodeRef(AstNodeRef nodeRef) const { return sema().resolvedNodeRef(nodeRef); }

    SemaNodeView viewZero(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Zero); }
    SemaNodeView viewNode(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node); }
    SemaNodeView viewType(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Type); }
    SemaNodeView viewConstant(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Constant); }
    SemaNodeView viewSymbol(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Symbol); }
    SemaNodeView viewTypeConstant(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant); }
    SemaNodeView viewTypeSymbol(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol); }
    SemaNodeView viewNodeType(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type); }
    SemaNodeView viewNodeTypeConstant(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant); }
    SemaNodeView viewNodeTypeSymbol(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol); }
    SemaNodeView viewNodeTypeConstantSymbol(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol); }
    SemaNodeView viewNodeSymbolList(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Symbol); }

    SemaNodeView curView() { return view(curNodeRef()); }
    SemaNodeView curView(EnumFlags<SemaNodeViewPartE> part) { return view(curNodeRef(), part); }
    SemaNodeView curViewZero() { return curView(SemaNodeViewPartE::Zero); }
    SemaNodeView curViewNode() { return curView(SemaNodeViewPartE::Node); }
    SemaNodeView curViewType() { return curView(SemaNodeViewPartE::Type); }
    SemaNodeView curViewConstant() { return curView(SemaNodeViewPartE::Constant); }
    SemaNodeView curViewSymbol() { return curView(SemaNodeViewPartE::Symbol); }
    SemaNodeView curViewTypeConstant() { return curView(SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant); }
    SemaNodeView curViewTypeSymbol() { return curView(SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol); }
    SemaNodeView curViewNodeType() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type); }
    SemaNodeView curViewNodeTypeConstant() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant); }
    SemaNodeView curViewNodeTypeSymbol() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol); }
    SemaNodeView curViewNodeTypeConstantSymbol() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol); }

    const CodeGenLoweringPayload* loweringPayload(AstNodeRef nodeRef) const;
    const SymbolVariable*         runtimeStorageSymbol(AstNodeRef nodeRef) const;
    TypeRef                       transparentPayloadTypeRef();
    void                          appendResolvedCallArguments(AstNodeRef nodeRef, SmallVector<ResolvedCallArgument>& out) const;

    SymbolFunction&       function() { return *(function_); }
    const SymbolFunction& function() const { return *(function_); }

    template<typename T>
    T* safeNodePayload(AstNodeRef nodeRef)
    {
        static_assert(!std::is_base_of_v<CodeGenNodePayload, T> || std::is_same_v<CodeGenNodePayload, T>);
        if constexpr (std::is_base_of_v<CodeGenNodePayload, T>)
            nodeRef = resolvedNodeRef(nodeRef);
        if (nodeRef.isInvalid())
            return nullptr;

        if constexpr (std::is_base_of_v<CodeGenNodePayload, T>)
            return static_cast<T*>(nodePayloads_.find(nodeRef));
        else
            return static_cast<T*>(auxNodePayloads_.find(nodeRef));
    }

    template<typename T>
    const T* safeNodePayload(AstNodeRef nodeRef) const
    {
        static_assert(!std::is_base_of_v<CodeGenNodePayload, T> || std::is_same_v<CodeGenNodePayload, T>);
        if constexpr (std::is_base_of_v<CodeGenNodePayload, T>)
            nodeRef = resolvedNodeRef(nodeRef);
        if (nodeRef.isInvalid())
            return nullptr;

        if constexpr (std::is_base_of_v<CodeGenNodePayload, T>)
            return static_cast<const T*>(nodePayloads_.find(nodeRef));
        else
            return static_cast<const T*>(auxNodePayloads_.find(nodeRef));
    }

    template<typename T>
    T& ensureNodePayload(AstNodeRef nodeRef)
    {
        const AstNodeRef queryNodeRef = nodeRef;
        if constexpr (std::is_base_of_v<CodeGenNodePayload, T>)
        {
            static_assert(std::is_same_v<CodeGenNodePayload, T>);
            nodeRef = resolvedNodeRef(nodeRef);
        }
        SWC_ASSERT(nodeRef.isValid());

        RefPointerMap<AstNodeRef>& payloads = std::is_base_of_v<CodeGenNodePayload, T> ? nodePayloads_ : auxNodePayloads_;
        T*                         payload  = static_cast<T*>(payloads.find(nodeRef));
        if (!payload)
        {
            if constexpr (std::is_trivially_destructible_v<T>)
            {
                payload = nodePayloadArena_.make<T>();
            }
            else
            {
                payload  = ctx().allocate<T>();
                *payload = {};
            }
            if constexpr (std::is_base_of_v<CodeGenNodePayload, T>)
                mergeLoweringNodePayloadMetadata(*payload, queryNodeRef, nodeRef);
            payloads.set(nodeRef, payload);
        }

        return *payload;
    }

    template<typename T>
    T& setNodePayload(AstNodeRef nodeRef, const T& payloadValue)
    {
        T& payload = ensureNodePayload<T>(nodeRef);
        payload    = payloadValue;
        return payload;
    }

    // Payload of the innermost enclosing ancestor with the given node id. Every '?.'
    // link is by construction inside its own OptionalChainExpr root, so the first
    // match going up is always the right owner.
    template<typename T>
    T* findEnclosingNodePayload(AstNodeId nodeId)
    {
        for (uint32_t up = 0;; up++)
        {
            const AstNodeRef parentRef = visit_.parentNodeRef(up);
            if (parentRef.isInvalid())
                return nullptr;

            if (node(parentRef).is(nodeId))
                return safeNodePayload<T>(parentRef);
        }
    }

    template<typename T>
    void clearNodePayload(AstNodeRef nodeRef)
    {
        nodeRef = resolvedNodeRef(nodeRef);
        if (nodeRef.isInvalid())
            return;

        if constexpr (std::is_base_of_v<CodeGenNodePayload, T>)
            nodePayloads_.erase(nodeRef);
        else
            auxNodePayloads_.erase(nodeRef);
    }

    CodeGenNodePayload& payload(AstNodeRef nodeRef);
    CodeGenNodePayload* safePayload(AstNodeRef nodeRef);
    bool                keepsFoldedConstant(AstNodeRef nodeRef);

    void                      setVariablePayload(const SymbolVariable& sym, const CodeGenNodePayload& payload);
    const CodeGenNodePayload* variablePayload(const SymbolVariable& sym) const;
    CodeGenNodePayload        conditionBindingPayload(TypeRef& outTypeRef, AstNodeRef nodeRef);

    void     setLocalStackFrameSize(uint32_t frameSize) { localStackFrameSize_ = frameSize; }
    uint32_t valueBorrowStackOffset = 0;
    uint32_t localStackFrameSize() const { return localStackFrameSize_; }
    bool     hasLocalStackFrame() const { return localStackFrameSize_ != 0; }
    void     setLocalStackBaseReg(MicroReg reg) { localStackBaseReg_ = reg; }
    MicroReg localStackBaseReg() const { return localStackBaseReg_; }

    void     setBodyEntryRef(MicroInstrRef ref) { bodyEntryRef_ = ref; }
    MicroReg vectorZeroRegister();

    void     setCurrentFunctionIndirectReturnStackOffset(uint32_t offset) { currentFunctionIndirectReturnStackOffset_ = offset; }
    void     clearCurrentFunctionIndirectReturnStackOffset() { currentFunctionIndirectReturnStackOffset_ = 0xFFFFFFFFu; }
    bool     hasCurrentFunctionIndirectReturnStackOffset() const { return currentFunctionIndirectReturnStackOffset_ != 0xFFFFFFFFu; }
    uint32_t currentFunctionIndirectReturnStackOffset() const { return currentFunctionIndirectReturnStackOffset_; }
    void     setCurrentFunctionIndirectReturnReg(MicroReg reg) { currentFunctionIndirectReturnReg_ = reg; }
    MicroReg currentFunctionIndirectReturnReg() const { return currentFunctionIndirectReturnReg_; }
    MicroReg ensureCurrentFunctionIndirectReturnReg(CallConvKind callConvKind);

    void     setCurrentFunctionClosureContextReg(MicroReg reg) { currentFunctionClosureContextReg_ = reg; }
    MicroReg currentFunctionClosureContextReg() const { return currentFunctionClosureContextReg_; }

    CodeGenNodePayload& inheritPayload(AstNodeRef dstNodeRef, AstNodeRef srcNodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload& setPayload(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload& setPayloadValue(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload& setPayloadAddress(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload& setPayloadAddressReg(AstNodeRef nodeRef, MicroReg reg, TypeRef typeRef = TypeRef::invalid());

    MicroReg           offsetAddressReg(MicroReg baseReg, uint32_t offset, bool forbidBaseReg = true);
    CodeGenNodePayload resolveLocalStackPayload(const SymbolVariable& sym, bool cache = true);
    MicroReg           runtimeStorageAddressReg(AstNodeRef nodeRef);

    bool   hasLifecycle(TypeRef typeRef, LifecycleKind lifecycleKind) const;
    bool   tryBuildLifecycleAction(TypeRef typeRef, LifecycleKind lifecycleKind, const SymbolFunction*& outFunction, uint32_t& outSizeOf, uint32_t& outCount) const;
    Result emitLifecycleAction(const SymbolFunction& calledFunction, MicroReg addressReg);
    Result emitLifecycleAction(const SymbolFunction& calledFunction, MicroReg addressReg, uint32_t sizeOf, uint32_t count);
    Result emitLifecycle(TypeRef typeRef, LifecycleKind lifecycleKind, MicroReg addressReg);
    Result emitLifecycle(TypeRef typeRef, LifecycleKind lifecycleKind, MicroReg addressReg, uint32_t count);
    Result emitLifecycle(TypeRef typeRef, LifecycleKind lifecycleKind, MicroReg addressReg, MicroReg countReg);

    void   registerTemporaryDrop(AstNodeRef valueRef, TypeRef typeRef, const SymbolVariable& storage);
    bool   hasTemporaryDrop(const SymbolVariable& storage) const;
    void   cancelTemporaryDrop(const SymbolVariable& storage);
    Result flushTemporaryDrops(AstNodeRef rootRef);
    Result emitTemporaryDropsForFailure(AstNodeRef scopeRef);

    void   pushDeferScope(AstNodeRef scopeRef = AstNodeRef::invalid(), AstNodeRef breakOwnerRef = AstNodeRef::invalid(), AstNodeRef switchCaseRef = AstNodeRef::invalid());
    Result popDeferScope();
    void   registerDefer(AstNodeRef deferStmtRef, AstNodeRef bodyRef, AstModifierFlags modifierFlags);
    void   registerErrorScopePop();
    void   registerValueBorrowEnd(uint32_t recordOffset);
    bool   hasOpenLocalValueBorrow() const;
    bool   openLocalValueBorrowMayCover(const SymbolVariable& local);

    struct ValueBorrowSite
    {
        AstNodeRef expressionRef;
        AstNodeRef scopeRef;
        TypeRef    typeRef;
        uint32_t   stackOffset;
        bool       addressHome;
    };

    SmallVector<ValueBorrowSite> valueBorrowSites;
    RefSet<AstNodeRef>           valueBorrowValueScopeRefs; // Scopes of the non-home sites: every node tests this, not the list
    RefSet<AstNodeRef>           valueBorrowExpressionRefs; // Values the sites borrow, for the same per-node test
    bool                         needsValueBorrowRuntime = false;

    void registerImplicitDrop(const SymbolVariable& symVar, const CodeGenFunctionHelpers::FunctionParameterInfo* paramInfo = nullptr);
    void initializeLocalStorageAtScopeEntry(const SymbolVariable& symVar);
    void registerImplicitParameterDrops(std::span<const CodeGenFunctionHelpers::FunctionParameterInfo> paramInfos);

    AstNodeRef currentFallibleScope();

    bool   hasDeferredStatements() const { return hasDeferredStatements_; }
    Result emitDeferredActionsForReturn();
    Result emitDeferredActionsUntilScopeRef(AstNodeRef scopeRef, bool popErrorScope = true);
    Result emitDeferredActionsUntilBreakOwner(AstNodeRef breakOwnerRef);
    Result emitDeferredActionsUntilSwitchCase(AstNodeRef switchCaseRef);
    Result emitDeferredActionsUntilOwner(AstNodeRef CodeGenDeferScope::* ownerField, AstNodeRef ownerRef);
    Result emitDeferredActionsDownTo(size_t stopScopeIndex);

    Result emitNodeNow(AstNodeRef nodeRef);
    void   invalidateNodePayloadRegs(AstNodeRef nodeRef);

    bool               containsDeferredActions(AstNodeRef nodeRef);
    CodeGenDeferScope& lifetimeDeferScope();
    bool               currentInstructionBlocksFallthrough() const;
    bool               inDeferredEmission() const { return deferredEmitDepth_ != 0; }

    // Move elision (see CodeGenMoveElision): per-function analysis cache and the set of
    // locals whose scope-exit drop has been elided by a consuming '#move'.
    bool                         moveElisionAnalyzed() const { return moveElisionAnalyzed_; }
    void                         setMoveElisionAnalyzed() { moveElisionAnalyzed_ = true; }
    CodeGenMoveElisionVar&       moveElisionVar(const SymbolVariable& symVar);
    const CodeGenMoveElisionVar* findMoveElisionVar(const SymbolVariable& symVar) const;
    void                         clearMoveElisionVars() { moveElisionVars_.clear(); }
    void                         markImplicitDropElided(const SymbolVariable& symVar) { elidedImplicitDrops_.insert(&symVar); }
    bool                         isImplicitDropElided(const SymbolVariable& symVar) const { return elidedImplicitDrops_.contains(&symVar); }

    // Locals built in the return storage of their return context, chosen once per function
    // by CodeGenMoveElision::selectReturnStorageLocals. A null context is the caller's slot.
    void                     addReturnStorageLocal(const SymbolVariable& symVar, const SemaInlinePayload* returnContext);
    bool                     isReturnStorageLocal(const SymbolVariable& symVar) const { return returnStorageLocals_.contains(&symVar); }
    const SemaInlinePayload* returnStorageLocalContext(const SymbolVariable& symVar) const { return returnStorageLocalContexts_.find(&symVar); }

    // A return of another value while a return-storage local lives: the value is built apart,
    // in 'demotedStorage' when the compiler had reserved the return slot for it.
    void                  addReplacingReturn(AstNodeRef returnRef, const SymbolVariable& symVar, const SymbolVariable* demotedStorage);
    const SymbolVariable* returnReplacedLocal(AstNodeRef returnRef) const;
    bool                  isDemotedReturnStorage(const SymbolVariable& symVar) const { return demotedReturnStorages_.contains(&symVar); }
    void                  setReturnReplacedLocal(const SymbolVariable* symVar) { returnReplacedLocal_ = symVar; }

    // Local moved out by the return being emitted: its drop is skipped for this return's
    // deferred actions only, so drops emitted for other control paths are unaffected.
    const SymbolVariable* returnMoveOutVar() const { return returnMoveOutVar_; }
    void                  setReturnMoveOutVar(const SymbolVariable* symVar) { returnMoveOutVar_ = symVar; }

    void                                      clearGlobalsToDropScratchLayout();
    void                                      setGlobalsToDropScratchLayout(uint32_t offset, uint32_t size, std::span<const CodeGenGlobalToDropEntry> entries);
    bool                                      hasGlobalsToDropScratchLayout() const { return globalsToDropScratchSize_ != 0; }
    uint32_t                                  globalsToDropScratchOffset() const { return globalsToDropScratchOffset_; }
    uint32_t                                  globalsToDropScratchSize() const { return globalsToDropScratchSize_; }
    std::span<const CodeGenGlobalToDropEntry> globalsToDropScratchEntries() const { return globalsToDropScratchEntries_; }

    void pushFrame(const CodeGenFrame& frame);
    void popFrame();

    MicroReg nextVirtualRegisterForType(TypeRef typeRef);
    MicroReg nextVirtualRegisterForType(TypeRef typeRef, const TypeInfo& typeInfo);
    MicroReg nextVirtualIntRegister() { return MicroReg::virtualIntReg(nextVirtualRegister_++); }
    MicroReg nextVirtualFloatRegister() { return MicroReg::virtualFloatReg(nextVirtualRegister_++); }

private:
    struct VariablePayloadState
    {
        CodeGenNodePayload payload;
        bool               hasPayload        = false;
        uint32_t           addressGeneration = 0;
    };

    // The states live in chunks that never move, so a payload handed out stays valid while
    // later variables are recorded; a flat index replaces a map node per variable.
    static constexpr uint32_t K_VARIABLE_PAYLOAD_CHUNK = 16;

    VariablePayloadState& ensureVariablePayloadState(const SymbolVariable& sym);

    void   setVisitors();
    Result preNode(AstNode& node);
    Result postNode(AstNode& node);
    Result preNodeChild(AstNode& node, AstNodeRef& childRef);
    Result postNodeChild(AstNode& node, AstNodeRef& childRef);
    Result emitConstant(AstNodeRef nodeRef);

    Result emitDeferredAction(const CodeGenDeferredAction& action);
    Result emitDeferredActionsInScope(size_t scopeIndex, size_t actionCount, bool popErrorScope = true);
    Result emitDeferredActionsFrom(size_t startScopeIndex, size_t startActionCount, size_t stopScopeIndex, bool hasStopScope, bool popStopErrorScope = true);
    bool   findInnermostDeferScopeIndex(AstNodeRef scopeRef, size_t& outScopeIndex) const;

    void                mergeLoweringNodePayloadMetadata(CodeGenNodePayload& payload, AstNodeRef nodeRef, AstNodeRef resolvedRef) const;
    CodeGenNodePayload* safePayload(AstNodeRef nodeRef, AstNodeRef resolvedRef);

    Sema*                     sema_ = nullptr;
    AstVisit                  visit_;
    std::vector<CodeGenFrame> frames_;

    RefPointerMap<AstNodeRef> nodePayloads_;
    // Control-flow state is keyed by the original node, not its value substitute.
    RefPointerMap<AstNodeRef> auxNodePayloads_;
    // These payloads only serve this CodeGen job, including while it is paused.
    Arena nodePayloadArena_{512};

    PointerMap<SymbolVariable, VariablePayloadState>        variablePayloads_;
    SmallVector<std::unique_ptr<VariablePayloadState[]>, 4> variablePayloadChunks_;
    uint32_t                                                variablePayloadCount_ = 0;

    // Filled only when a move asks whether it can be elided; most functions never do.
    FlatKeyMap<CodeGenMoveElisionVar, uint64_t>               moveElisionVars_;
    PointerSet<const SymbolVariable>                          elidedImplicitDrops_;
    PointerSet<const SymbolVariable>                          returnStorageLocals_;
    PointerMap<SymbolVariable, const SemaInlinePayload>       returnStorageLocalContexts_;
    SmallVector<std::pair<AstNodeRef, const SymbolVariable*>> replacingReturns_;
    PointerSet<const SymbolVariable>                          demotedReturnStorages_;
    const SymbolVariable*                                     returnReplacedLocal_ = nullptr;
    const SymbolVariable*                                     returnMoveOutVar_    = nullptr;
    bool                                                      moveElisionAnalyzed_ = false;

    SymbolFunction* function_            = nullptr;
    MicroBuilder*   builder_             = nullptr;
    uint32_t        nextVirtualRegister_ = 1;

    uint32_t      localStackFrameSize_ = 0;
    MicroReg      localStackBaseReg_;
    MicroReg      vectorZeroReg_;
    MicroInstrRef bodyEntryRef_;

    uint32_t currentFunctionIndirectReturnStackOffset_ = 0xFFFFFFFFu;
    MicroReg currentFunctionIndirectReturnReg_;
    MicroReg currentFunctionClosureContextReg_;

    SmallVector<CodeGenDeferScope, 32>         deferScopes_;
    SmallVector<CodeGenDeferredEmissionCursor> deferredEmissionCursors_;

    uint32_t deferredEmitDepth_                = 0;
    uint32_t currentDeferredAddressGeneration_ = 0;
    uint32_t nextDeferredAddressGeneration_    = 1;
    bool     hasDeferredStatements_            = false;

    uint32_t                              globalsToDropScratchOffset_ = 0;
    uint32_t                              globalsToDropScratchSize_   = 0;
    SmallVector<CodeGenGlobalToDropEntry> globalsToDropScratchEntries_;

    SmallVector<CodeGenTemporaryDrop, 4> temporaryDrops_;

    AstNodeRef root_      = AstNodeRef::invalid();
    bool       started_   = false;
    bool       completed_ = false;
};

SWC_END_NAMESPACE();
