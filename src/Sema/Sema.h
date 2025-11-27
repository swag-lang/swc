#pragma once
#include "Parser/Ast.h"
#include "Parser/AstVisit.h"
#include "Report/Diagnostic.h"
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

class Sema
{
    TaskContext* ctx_ = nullptr;
    Ast*         ast_ = nullptr;
    AstVisit     visit_;

    AstVisitStepResult preNode(AstNode& node);
    AstVisitStepResult postNode(AstNode& node);
    AstVisitStepResult preChild(AstNode& node, AstNodeRef& childRef);

public:
    Sema(TaskContext& ctx, Ast* ast, AstNodeRef root);
    JobResult exec();

    TaskContext&            ctx() { return *ctx_; }
    const TaskContext&      ctx() const { return *ctx_; }
    Ast&                    ast() { return *ast_; }
    const Ast&              ast() const { return *ast_; }
    AstVisit&               visit() { return visit_; }
    const AstVisit&         visit() const { return visit_; }
    AstNode&                node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode&          node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }
    CompilerInstance&       compiler() { return ctx().compiler(); }
    const CompilerInstance& compiler() const { return ctx().compiler(); }
    ConstantManager&        constMgr() { return compiler().constMgr(); }
    const ConstantManager&  constMgr() const { return compiler().constMgr(); }
    TypeManager&            typeMgr() { return compiler().typeMgr(); }
    const TypeManager&      typeMgr() const { return compiler().typeMgr(); }
    const Token&            token(SourceViewRef srcViewRef, TokenRef tokenRef) const { return compiler().srcView(srcViewRef).token(tokenRef); }

    Diagnostic reportError(DiagnosticId id, AstNodeRef nodeRef);
    Diagnostic reportError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokenRef);
    void       raiseError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokenRef);
    void       raiseError(DiagnosticId id, AstNodeRef nodeRef);
    void       raiseInvalidType(AstNodeRef nodeRef, TypeInfoRef wantedType, TypeInfoRef hasType);
    void       raiseInternalError(const AstNode* node);

    ConstantRef convert(const ConstantValue& src, TypeInfoRef targetTypeRef);
};

SWC_END_NAMESPACE()
