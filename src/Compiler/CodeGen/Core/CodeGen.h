#pragma once
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstVisit.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;
class MicroInstrBuilder;

class CodeGen
{
public:
    explicit CodeGen(Sema& sema);
    Result exec(SymbolFunction& symbolFunc, AstNodeRef root);

    Sema&                    sema() { return *sema_; }
    const Sema&              sema() const { return *sema_; }
    TaskContext&             ctx();
    const TaskContext&       ctx() const;
    Ast&                     ast();
    const Ast&               ast() const;
    AstVisit&                visit() { return visit_; }
    const AstVisit&          visit() const { return visit_; }
    SymbolFunction*          currentFunction() { return currentFunction_; }
    const SymbolFunction*    currentFunction() const { return currentFunction_; }
    MicroInstrBuilder*       builder() { return builder_; }
    const MicroInstrBuilder* builder() const { return builder_; }

private:
    void   setVisitors();
    Result preNode(AstNode& node);
    Result postNode(AstNode& node);
    Result preNodeChild(AstNode& node, AstNodeRef& childRef);
    Result postNodeChild(AstNode& node, AstNodeRef& childRef);

    Sema*              sema_ = nullptr;
    AstVisit           visit_;
    SymbolFunction*    currentFunction_ = nullptr;
    MicroInstrBuilder* builder_         = nullptr;
};

SWC_END_NAMESPACE();
