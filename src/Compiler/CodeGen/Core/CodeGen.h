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
        Ref                                           doneLabel       = INVALID_REF;
        TypeRef                                       compareTypeRef  = TypeRef::invalid();
        MicroReg                                      switchValueReg;
        MicroOpBits                                   compareOpBits   = MicroOpBits::B64;
        bool                                          hasExpression   = false;
        bool                                          useUnsignedCond = false;
        std::unordered_map<AstNodeRef, SwitchCaseCodeGenState> caseStates;
    };

    struct LocalStackSlot
    {
        uint32_t offset = 0;
        uint32_t size   = 0;
        uint32_t align  = 1;
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

    Ast&              ast();
    const Ast&        ast() const;
    SourceView&       srcView(SourceViewRef srcViewRef);
    const SourceView& srcView(SourceViewRef srcViewRef) const;
    AstNode&          node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode&    node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }
    AstVisit&         visit() { return visit_; }
    const AstVisit&   visit() const { return visit_; }
    AstNodeRef        curNodeRef() const { return visit_.currentNodeRef(); }
    AstNode&          curNode() { return node(curNodeRef()); }
    const AstNode&    curNode() const { return node(curNodeRef()); }
    const Token&      token(const SourceCodeRef& codeRef) const;

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
    IfStmtCodeGenState&       setIfStmtCodeGenState(AstNodeRef nodeRef, const IfStmtCodeGenState& value)
    {
        const auto it = ifStmtCodeGenStates_.insert_or_assign(nodeRef, value).first;
        return it->second;
    }
    IfStmtCodeGenState* ifStmtCodeGenState(AstNodeRef nodeRef)
    {
        const auto it = ifStmtCodeGenStates_.find(nodeRef);
        if (it == ifStmtCodeGenStates_.end())
            return nullptr;
        return &it->second;
    }
    void eraseIfStmtCodeGenState(AstNodeRef nodeRef)
    {
        ifStmtCodeGenStates_.erase(nodeRef);
    }

    SwitchStmtCodeGenState& setSwitchStmtCodeGenState(AstNodeRef nodeRef, const SwitchStmtCodeGenState& value)
    {
        const auto it = switchStmtCodeGenStates_.insert_or_assign(nodeRef, value).first;
        return it->second;
    }
    SwitchStmtCodeGenState* switchStmtCodeGenState(AstNodeRef nodeRef)
    {
        const auto it = switchStmtCodeGenStates_.find(nodeRef);
        if (it == switchStmtCodeGenStates_.end())
            return nullptr;
        return &it->second;
    }
    void eraseSwitchStmtCodeGenState(AstNodeRef nodeRef)
    {
        switchStmtCodeGenStates_.erase(nodeRef);
    }

    void pushActiveSwitch(AstNodeRef nodeRef)
    {
        activeSwitchStack_.push_back(nodeRef);
    }
    void popActiveSwitch()
    {
        if (!activeSwitchStack_.empty())
            activeSwitchStack_.pop_back();
    }
    AstNodeRef currentSwitchRef() const
    {
        if (activeSwitchStack_.empty())
            return AstNodeRef::invalid();
        return activeSwitchStack_.back();
    }

    void pushActiveSwitchCase(AstNodeRef nodeRef)
    {
        activeSwitchCaseStack_.push_back(nodeRef);
    }
    void popActiveSwitchCase()
    {
        if (!activeSwitchCaseStack_.empty())
            activeSwitchCaseStack_.pop_back();
    }
    AstNodeRef currentSwitchCaseRef() const
    {
        if (activeSwitchCaseStack_.empty())
            return AstNodeRef::invalid();
        return activeSwitchCaseStack_.back();
    }

    MicroReg nextVirtualRegisterForType(TypeRef typeRef);
    MicroReg nextVirtualRegister() { return MicroReg::virtualReg(nextVirtualRegister_++); }
    MicroReg nextVirtualIntRegister() { return MicroReg::virtualIntReg(nextVirtualRegister_++); }
    MicroReg nextVirtualFloatRegister() { return MicroReg::virtualFloatReg(nextVirtualRegister_++); }

private:
    AstNodeRef resolvedNodeRef(AstNodeRef nodeRef) { return sema().viewZero(nodeRef).nodeRef(); }
    void       setVisitors();
    Result     preNode(AstNode& node);
    Result     postNode(AstNode& node);
    Result     preNodeChild(AstNode& node, AstNodeRef& childRef);
    Result     postNodeChild(AstNode& node, AstNodeRef& childRef);
    Result     emitConstant(AstNodeRef nodeRef);

    Sema*                                                         sema_ = nullptr;
    AstVisit                                                      visit_;
    SymbolFunction*                                               function_            = nullptr;
    MicroBuilder*                                                 builder_             = nullptr;
    uint32_t                                                      nextVirtualRegister_ = 1;
    std::unordered_map<const SymbolVariable*, CodeGenNodePayload> variablePayloads_;
    std::unordered_map<const SymbolVariable*, LocalStackSlot>     localStackSlots_;
    uint32_t                                                      localStackFrameSize_ = 0;
    MicroReg                                                      localStackBaseReg_;
    std::unordered_map<AstNodeRef, IfStmtCodeGenState>            ifStmtCodeGenStates_;
    std::unordered_map<AstNodeRef, SwitchStmtCodeGenState>        switchStmtCodeGenStates_;
    SmallVector<AstNodeRef>                                       activeSwitchStack_;
    SmallVector<AstNodeRef>                                       activeSwitchCaseStack_;
};

SWC_END_NAMESPACE();

