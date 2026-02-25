#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroTypes.h"
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

    void setIsValue() { storageKind = StorageKind::Value; }
    bool isValue() const { return storageKind == StorageKind::Value; }
    void setIsAddress() { storageKind = StorageKind::Address; }
    bool isAddress() const { return storageKind == StorageKind::Address; }
};

class CodeGenFrame
{
public:
    AstNodeRef currentSwitch() const { return currentSwitch_; }
    void       setCurrentSwitch(AstNodeRef nodeRef) { currentSwitch_ = nodeRef; }
    AstNodeRef currentSwitchCase() const { return currentSwitchCase_; }
    void       setCurrentSwitchCase(AstNodeRef nodeRef) { currentSwitchCase_ = nodeRef; }

private:
    AstNodeRef currentSwitch_     = AstNodeRef::invalid();
    AstNodeRef currentSwitchCase_ = AstNodeRef::invalid();
};

class CodeGen
{
public:
    struct IfStmtCodeGenState
    {
        Ref  falseLabel   = INVALID_REF;
        Ref  doneLabel    = INVALID_REF;
        bool hasElseBlock = false;
    };

    struct SwitchCaseCodeGenState
    {
        Ref  testLabel     = INVALID_REF;
        Ref  bodyLabel     = INVALID_REF;
        Ref  nextTestLabel = INVALID_REF;
        Ref  nextBodyLabel = INVALID_REF;
        bool hasNextCase   = false;
    };

    struct SwitchStmtCodeGenState
    {
        Ref                                                    doneLabel      = INVALID_REF;
        TypeRef                                                compareTypeRef = TypeRef::invalid();
        MicroReg                                               switchValueReg;
        MicroOpBits                                            compareOpBits   = MicroOpBits::B64;
        bool                                                   hasExpression   = false;
        bool                                                   useUnsignedCond = false;
        std::unordered_map<AstNodeRef, SwitchCaseCodeGenState> caseStates;
    };

    struct IfStmtCodeGenPayload
    {
        IfStmtCodeGenState state;
    };

    struct SwitchStmtCodeGenPayload
    {
        SwitchStmtCodeGenState state;
    };

    struct LocalStackSlot
    {
        uint32_t offset = 0;
        uint32_t size   = 0;
        uint32_t align  = 1;
    };

    struct VariableSymbolCodeGenPayload
    {
        CodeGenNodePayload payload;
        LocalStackSlot     localSlot;
        bool               hasPayload   = false;
        bool               hasLocalSlot = false;
    };

    explicit CodeGen(Sema& sema);
    Result exec(SymbolFunction& symbolFunc, AstNodeRef root);

    Sema&                    sema() { return *SWC_CHECK_NOT_NULL(sema_); }
    const Sema&              sema() const { return *SWC_CHECK_NOT_NULL(sema_); }
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
    MicroBuilder&            builder() { return *SWC_CHECK_NOT_NULL(builder_); }
    const MicroBuilder&      builder() const { return *SWC_CHECK_NOT_NULL(builder_); }

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
    SymbolFunction&       function() { return *SWC_CHECK_NOT_NULL(function_); }
    const SymbolFunction& function() const { return *SWC_CHECK_NOT_NULL(function_); }

    CodeGenNodePayload&       payload(AstNodeRef nodeRef);
    CodeGenNodePayload*       safePayload(AstNodeRef nodeRef);
    void                      setVariablePayload(const SymbolVariable& sym, const CodeGenNodePayload& payload);
    const CodeGenNodePayload* variablePayload(const SymbolVariable& sym) const;
    void                      setLocalStackSlot(const SymbolVariable& sym, const LocalStackSlot& slot);
    const LocalStackSlot*     localStackSlot(const SymbolVariable& sym) const;
    void                      setLocalStackFrameSize(uint32_t frameSize) { localStackFrameSize_ = frameSize; }
    uint32_t                  localStackFrameSize() const { return localStackFrameSize_; }
    bool                      hasLocalStackFrame() const { return localStackFrameSize_ != 0; }
    void                      setLocalStackBaseReg(MicroReg reg) { localStackBaseReg_ = reg; }
    MicroReg                  localStackBaseReg() const { return localStackBaseReg_; }
    CodeGenNodePayload&       inheritPayload(AstNodeRef dstNodeRef, AstNodeRef srcNodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload&       setPayload(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload&       setPayloadValue(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload&       setPayloadAddress(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    IfStmtCodeGenState&       setIfStmtCodeGenState(AstNodeRef nodeRef, const IfStmtCodeGenState& value);
    IfStmtCodeGenState*       ifStmtCodeGenState(AstNodeRef nodeRef);
    void                      eraseIfStmtCodeGenState(AstNodeRef nodeRef);
    SwitchStmtCodeGenState&   setSwitchStmtCodeGenState(AstNodeRef nodeRef, const SwitchStmtCodeGenState& value);
    SwitchStmtCodeGenState*   switchStmtCodeGenState(AstNodeRef nodeRef);
    void                      eraseSwitchStmtCodeGenState(AstNodeRef nodeRef);
    void                      pushFrame(const CodeGenFrame& frame);
    void                      popFrame();

    MicroReg nextVirtualRegisterForType(TypeRef typeRef);
    MicroReg nextVirtualRegister() { return MicroReg::virtualReg(nextVirtualRegister_++); }
    MicroReg nextVirtualIntRegister() { return MicroReg::virtualIntReg(nextVirtualRegister_++); }
    MicroReg nextVirtualFloatRegister() { return MicroReg::virtualFloatReg(nextVirtualRegister_++); }

private:
    AstNodeRef                           resolvedNodeRef(AstNodeRef nodeRef) { return sema().viewZero(nodeRef).nodeRef(); }
    static VariableSymbolCodeGenPayload* safeVariableSymbolPayload(const SymbolVariable& sym);
    VariableSymbolCodeGenPayload&        ensureVariableSymbolPayload(const SymbolVariable& sym);
    void                                 setVisitors();
    Result                               preNode(AstNode& node);
    Result                               postNode(AstNode& node);
    Result                               preNodeChild(AstNode& node, AstNodeRef& childRef);
    Result                               postNodeChild(AstNode& node, AstNodeRef& childRef);
    Result                               emitConstant(AstNodeRef nodeRef);

    Sema*                     sema_ = nullptr;
    AstVisit                  visit_;
    std::vector<CodeGenFrame> frames_;
    SymbolFunction*           function_            = nullptr;
    MicroBuilder*             builder_             = nullptr;
    uint32_t                  nextVirtualRegister_ = 1;
    uint32_t                  localStackFrameSize_ = 0;
    MicroReg                  localStackBaseReg_;
    AstNodeRef                root_      = AstNodeRef::invalid();
    bool                      started_   = false;
    bool                      completed_ = false;
};

SWC_END_NAMESPACE();
