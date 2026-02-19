#pragma once
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

struct CodeGenNodePayload
{
    enum class StorageKind : uint8_t
    {
        Value,
        Address,
    };

    MicroReg    reg         = MicroReg::invalid();
    TypeRef     typeRef     = TypeRef::invalid();
    StorageKind storageKind = StorageKind::Value;
};

class CodeGen
{
public:
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
    Ast&                     ast();
    const Ast&               ast() const;
    SourceView&              srcView(SourceViewRef srcViewRef);
    const SourceView&        srcView(SourceViewRef srcViewRef) const;
    AstNode&                 node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode&           node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }
    AstVisit&                visit() { return visit_; }
    const AstVisit&          visit() const { return visit_; }

    AstNodeRef     curNodeRef() const { return visit_.currentNodeRef(); }
    AstNode&       curNode() { return node(curNodeRef()); }
    const AstNode& curNode() const { return node(curNodeRef()); }
    const Token&   token(const SourceCodeRef& codeRef) const;

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

    void                      appendResolvedCallArguments(AstNodeRef nodeRef, SmallVector<ResolvedCallArgument>& out) const;
    SymbolFunction&           function() { return *SWC_CHECK_NOT_NULL(function_); }
    const SymbolFunction&     function() const { return *SWC_CHECK_NOT_NULL(function_); }
    CodeGenNodePayload*       payload(AstNodeRef nodeRef) const;
    void                      setVariablePayload(const SymbolVariable& sym, const CodeGenNodePayload& payload);
    const CodeGenNodePayload* variablePayload(const SymbolVariable& sym) const;
    CodeGenNodePayload&       inheritPayload(AstNodeRef dstNodeRef, AstNodeRef srcNodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload&       setPayload(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload&       setPayloadValue(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload&       setPayloadAddress(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    static void               setPayloadValue(CodeGenNodePayload& payload);
    static void               setPayloadAddress(CodeGenNodePayload& payload);
    MicroReg                  nextVirtualRegisterForType(TypeRef typeRef);
    bool                      canUseOperandRegDirect(const CodeGenNodePayload& operandPayload) const;
    MicroReg                  nextVirtualRegister() { return MicroReg::virtualReg(nextVirtualRegister_++); }
    MicroReg                  nextVirtualIntRegister() { return MicroReg::virtualIntReg(nextVirtualRegister_++); }
    MicroReg                  nextVirtualFloatRegister() { return MicroReg::virtualFloatReg(nextVirtualRegister_++); }
    MicroBuilder&             builder() { return *SWC_CHECK_NOT_NULL(builder_); }
    const MicroBuilder&       builder() const { return *SWC_CHECK_NOT_NULL(builder_); }

private:
    void   setVisitors();
    Result emitConstant(AstNodeRef nodeRef);
    Result preNode(AstNode& node);
    Result postNode(AstNode& node);
    Result preNodeChild(AstNode& node, AstNodeRef& childRef);
    Result postNodeChild(AstNode& node, AstNodeRef& childRef);

    Sema*                                                         sema_ = nullptr;
    AstVisit                                                      visit_;
    SymbolFunction*                                               function_            = nullptr;
    MicroBuilder*                                                 builder_             = nullptr;
    uint32_t                                                      nextVirtualRegister_ = 1;
    std::unordered_map<const SymbolVariable*, CodeGenNodePayload> variablePayloads_;
};

SWC_END_NAMESPACE();
