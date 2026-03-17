#pragma once
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroReg.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class MicroBuilder;
class CompilerInstance;
class ConstantManager;
class TypeManager;
class TypeGen;
class IdentifierManager;
class SourceView;
class SymbolVariable;
struct ResolvedCallArgument;
struct Token;
struct SemaInlinePayload;

struct CodeGenNodePayload
{
    enum class StorageKind : uint8_t
    {
        Value,
        Address,
    };

    MicroReg    reg;
    TypeRef     typeRef     = TypeRef::invalid();
    StorageKind storageKind = StorageKind::Value;
    union
    {
        SymbolVariable* runtimeStorageSym = nullptr;
        SymbolFunction* runtimeFunctionSymbol;
    };

    void setIsValue() { storageKind = StorageKind::Value; }
    bool isValue() const { return storageKind == StorageKind::Value; }
    void setIsAddress() { storageKind = StorageKind::Address; }
    bool isAddress() const { return storageKind == StorageKind::Address; }

    void setValueOrAddress(bool isIndirect)
    {
        if (isIndirect)
            setIsAddress();
        else
            setIsValue();
    }

    TypeRef effectiveTypeRef(TypeRef fallbackTypeRef) const
    {
        if (typeRef.isValid())
            return typeRef;
        return fallbackTypeRef;
    }
};

struct CodeGenGvtdEntry
{
    SymbolVariable* variable = nullptr;
    SymbolFunction* opDrop   = nullptr;
    uint32_t        sizeOf   = 0;
    uint32_t        count    = 0;
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

class CodeGenFrame
{
public:
    enum class BreakContextKind : uint8_t
    {
        None,
        Scope,
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
        AstNodeRef               rootNodeRef = AstNodeRef::invalid();
        const SemaInlinePayload* payload     = nullptr;
        MicroLabelRef            doneLabel   = MicroLabelRef::invalid();
    };

    const BreakContext& currentBreakContext() const { return breakable_; }
    void                setCurrentBreakContent(AstNodeRef nodeRef, BreakContextKind kind)
    {
        breakable_.nodeRef = nodeRef;
        breakable_.kind    = kind;
    }
    BreakContextKind currentBreakableKind() const { return breakable_.kind; }

    AstNodeRef    currentSwitch() const { return currentSwitch_; }
    void          setCurrentSwitch(AstNodeRef nodeRef) { currentSwitch_ = nodeRef; }
    AstNodeRef    currentSwitchCase() const { return currentSwitchCase_; }
    void          setCurrentSwitchCase(AstNodeRef nodeRef) { currentSwitchCase_ = nodeRef; }
    MicroLabelRef currentLoopContinueLabel() const { return currentLoopContinueLabel_; }
    void          setCurrentLoopContinueLabel(MicroLabelRef labelRef) { currentLoopContinueLabel_ = labelRef; }
    MicroLabelRef currentLoopBreakLabel() const { return currentLoopBreakLabel_; }
    void          setCurrentLoopBreakLabel(MicroLabelRef labelRef) { currentLoopBreakLabel_ = labelRef; }
    MicroReg      currentLoopIndexReg() const { return currentLoopIndexReg_; }
    void          setCurrentLoopIndex(MicroReg reg, TypeRef typeRef)
    {
        currentLoopIndexReg_     = reg;
        currentLoopIndexTypeRef_ = typeRef;
    }
    TypeRef              currentLoopIndexTypeRef() const { return currentLoopIndexTypeRef_; }
    const InlineContext& currentInlineContext() const { return inlineContext_; }
    void                 setCurrentInlineContext(AstNodeRef rootNodeRef, const SemaInlinePayload* payload, MicroLabelRef doneLabel)
    {
        inlineContext_.rootNodeRef = rootNodeRef;
        inlineContext_.payload     = payload;
        inlineContext_.doneLabel   = doneLabel;
    }
    void setCurrentInlineDoneLabel(MicroLabelRef doneLabel) { inlineContext_.doneLabel = doneLabel; }
    bool hasCurrentInlineContext() const { return inlineContext_.payload != nullptr && inlineContext_.rootNodeRef.isValid(); }

private:
    BreakContext  breakable_;
    AstNodeRef    currentSwitch_            = AstNodeRef::invalid();
    AstNodeRef    currentSwitchCase_        = AstNodeRef::invalid();
    MicroLabelRef currentLoopContinueLabel_ = MicroLabelRef::invalid();
    MicroLabelRef currentLoopBreakLabel_    = MicroLabelRef::invalid();
    MicroReg      currentLoopIndexReg_      = MicroReg::invalid();
    TypeRef       currentLoopIndexTypeRef_  = TypeRef::invalid();
    InlineContext inlineContext_;
};

class CodeGen
{
public:
    explicit CodeGen(Sema& sema);
    Result exec(SymbolFunction& symbolFunc, AstNodeRef root);

    Sema&                    sema() { return *(sema_); }
    const Sema&              sema() const { return *(sema_); }
    TaskContext&             ctx();
    const TaskContext&       ctx() const;
    CompilerInstance&        compiler();
    const CompilerInstance&  compiler() const;
    ConstantManager&         cstMgr();
    const ConstantManager&   cstMgr() const;
    TypeManager&             typeMgr();
    const TypeManager&       typeMgr() const;
    TypeGen&                 typeGen();
    const TypeGen&           typeGen() const;
    IdentifierManager&       idMgr();
    const IdentifierManager& idMgr() const;
    MicroBuilder&            builder() { return *(builder_); }
    const MicroBuilder&      builder() const { return *(builder_); }

    Ast&                          ast();
    const Ast&                    ast() const;
    SourceView&                   srcView(SourceViewRef srcViewRef);
    const SourceView&             srcView(SourceViewRef srcViewRef) const;
    AstNode&                      node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode&                node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }
    AstVisit&                     visit() { return visit_; }
    const AstVisit&               visit() const { return visit_; }
    AstNodeRef                    curNodeRef() const { return visit_.currentNodeRef(); }
    AstNode&                      curNode() { return node(curNodeRef()); }
    const AstNode&                curNode() const { return node(curNodeRef()); }
    const Token&                  token(const SourceCodeRef& codeRef) const;
    CodeGenFrame&                 frame() { return frames_.back(); }
    const CodeGenFrame&           frame() const { return frames_.back(); }
    std::span<const CodeGenFrame> frames() const { return frames_; }

    SemaNodeView view(AstNodeRef nodeRef) { return sema().view(nodeRef); }
    SemaNodeView view(AstNodeRef nodeRef, EnumFlags<SemaNodeViewPartE> part) { return sema().view(nodeRef, part); }
    AstNodeRef   resolvedNodeRef(AstNodeRef nodeRef) { return sema().viewZero(nodeRef).nodeRef(); }
    SemaNodeView viewZero(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Zero); }
    SemaNodeView viewNode(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node); }
    SemaNodeView viewType(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Type); }
    SemaNodeView viewConstant(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Constant); }
    SemaNodeView viewSymbol(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Symbol); }
    SemaNodeView viewSymbolList(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Symbol); }
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
    SemaNodeView curViewSymbolList() { return curView(SemaNodeViewPartE::Symbol); }
    SemaNodeView curViewTypeConstant() { return curView(SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant); }
    SemaNodeView curViewTypeSymbol() { return curView(SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol); }
    SemaNodeView curViewNodeType() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type); }
    SemaNodeView curViewNodeTypeConstant() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant); }
    SemaNodeView curViewNodeTypeSymbol() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol); }
    SemaNodeView curViewNodeTypeConstantSymbol() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol); }

    void                  appendResolvedCallArguments(AstNodeRef nodeRef, SmallVector<ResolvedCallArgument>& out) const;
    SymbolFunction&       function() { return *(function_); }
    const SymbolFunction& function() const { return *(function_); }

    template<typename T>
    T* safeNodePayload(AstNodeRef nodeRef)
    {
        nodeRef = resolvedNodeRef(nodeRef);
        if (nodeRef.isInvalid())
            return nullptr;
        return sema().codeGenPayload<T>(nodeRef);
    }

    template<typename T>
    T& ensureNodePayload(AstNodeRef nodeRef)
    {
        nodeRef = resolvedNodeRef(nodeRef);
        SWC_ASSERT(nodeRef.isValid());

        T* payload = sema().codeGenPayload<T>(nodeRef);
        if (!payload)
        {
            payload = compiler().allocate<T>();
            sema().setCodeGenPayload(nodeRef, payload);
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

    CodeGenNodePayload&              payload(AstNodeRef nodeRef);
    CodeGenNodePayload*              safePayload(AstNodeRef nodeRef);
    void                             setVariablePayload(const SymbolVariable& sym, const CodeGenNodePayload& payload);
    static const CodeGenNodePayload* variablePayload(const SymbolVariable& sym);
    void                             setLocalStackFrameSize(uint32_t frameSize) { localStackFrameSize_ = frameSize; }
    uint32_t                         localStackFrameSize() const { return localStackFrameSize_; }
    bool                             hasLocalStackFrame() const { return localStackFrameSize_ != 0; }
    void                             setLocalStackBaseReg(MicroReg reg) { localStackBaseReg_ = reg; }
    MicroReg                         localStackBaseReg() const { return localStackBaseReg_; }
    void                             setCurrentFunctionIndirectReturnReg(MicroReg reg) { currentFunctionIndirectReturnReg_ = reg; }
    MicroReg                         currentFunctionIndirectReturnReg() const { return currentFunctionIndirectReturnReg_; }
    CodeGenNodePayload&              inheritPayload(AstNodeRef dstNodeRef, AstNodeRef srcNodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload&              setPayload(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload&              setPayloadValue(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload&              setPayloadAddress(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload&              setPayloadAddressReg(AstNodeRef nodeRef, MicroReg reg, TypeRef typeRef = TypeRef::invalid());
    MicroReg                         offsetAddressReg(MicroReg baseReg, uint32_t offset);
    CodeGenNodePayload               resolveLocalStackPayload(const SymbolVariable& sym);
    MicroReg                         runtimeStorageAddressReg(AstNodeRef nodeRef);

    void                              clearGvtdScratchLayout();
    void                              setGvtdScratchLayout(uint32_t offset, uint32_t size, std::span<const CodeGenGvtdEntry> entries);
    bool                              hasGvtdScratchLayout() const { return gvtdScratchSize_ != 0; }
    uint32_t                          gvtdScratchOffset() const { return gvtdScratchOffset_; }
    uint32_t                          gvtdScratchSize() const { return gvtdScratchSize_; }
    std::span<const CodeGenGvtdEntry> gvtdScratchEntries() const { return gvtdScratchEntries_; }
    void                              pushFrame(const CodeGenFrame& frame);
    void                              popFrame();

    MicroReg nextVirtualRegisterForType(TypeRef typeRef);
    MicroReg nextVirtualRegister() { return MicroReg::virtualReg(nextVirtualRegister_++); }
    MicroReg nextVirtualIntRegister() { return MicroReg::virtualIntReg(nextVirtualRegister_++); }
    MicroReg nextVirtualFloatRegister() { return MicroReg::virtualFloatReg(nextVirtualRegister_++); }

private:
    void   setVisitors();
    Result preNode(AstNode& node);
    Result postNode(AstNode& node);
    Result preNodeChild(AstNode& node, AstNodeRef& childRef);
    Result postNodeChild(AstNode& node, AstNodeRef& childRef);
    Result emitConstant(AstNodeRef nodeRef);

    Sema*                         sema_ = nullptr;
    AstVisit                      visit_;
    std::vector<CodeGenFrame>     frames_;
    SymbolFunction*               function_            = nullptr;
    MicroBuilder*                 builder_             = nullptr;
    uint32_t                      nextVirtualRegister_ = 1;
    uint32_t                      localStackFrameSize_ = 0;
    MicroReg                      localStackBaseReg_;
    MicroReg                      currentFunctionIndirectReturnReg_;
    uint32_t                      gvtdScratchOffset_ = 0;
    uint32_t                      gvtdScratchSize_   = 0;
    SmallVector<CodeGenGvtdEntry> gvtdScratchEntries_;
    AstNodeRef                    root_      = AstNodeRef::invalid();
    bool                          started_   = false;
    bool                          completed_ = false;
};

SWC_END_NAMESPACE();
