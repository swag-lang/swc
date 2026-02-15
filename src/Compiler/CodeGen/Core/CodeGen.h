#pragma once
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstVisit.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;
class MicroInstrBuilder;
struct MicroReg;
struct SemaNodeView;
struct Token;

struct CodeGenNodePayload
{
    uint32_t virtualRegister = 0;
    TypeRef  typeRef         = TypeRef::invalid();
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
    Ast&                     ast();
    const Ast&               ast() const;
    AstNode&                 node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode&           node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }
    AstVisit&                visit() { return visit_; }
    const AstVisit&          visit() const { return visit_; }
    AstNodeRef               curNodeRef() const { return visit_.currentNodeRef(); }
    SemaNodeView             nodeView(AstNodeRef nodeRef);
    SemaNodeView             curNodeView();
    const Token&             token(const SourceCodeRef& codeRef) const;
    SymbolFunction&          function() { return *SWC_CHECK_NOT_NULL(function_); }
    const SymbolFunction&    function() const { return *SWC_CHECK_NOT_NULL(function_); }
    Result                   emitConstReturnValue(const SemaNodeView& exprView);
    CodeGenNodePayload*      payload(AstNodeRef nodeRef) const;
    MicroReg                 payloadVirtualReg(AstNodeRef nodeRef) const;
    MicroReg                 payloadVirtualReg(const CodeGenNodePayload& nodePayload) const;
    CodeGenNodePayload&      setPayload(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    uint32_t                 nextVirtualRegister() { return nextVirtualRegister_++; }
    MicroInstrBuilder&       builder() { return *SWC_CHECK_NOT_NULL(builder_); }
    const MicroInstrBuilder& builder() const { return *SWC_CHECK_NOT_NULL(builder_); }

private:
    void   setVisitors();
    Result preNode(AstNode& node);
    Result postNode(AstNode& node);
    Result preNodeChild(AstNode& node, AstNodeRef& childRef);
    Result postNodeChild(AstNode& node, AstNodeRef& childRef);

    Sema*              sema_ = nullptr;
    AstVisit           visit_;
    SymbolFunction*    function_            = nullptr;
    MicroInstrBuilder* builder_             = nullptr;
    uint32_t           nextVirtualRegister_ = 1;
};

SWC_END_NAMESPACE();
