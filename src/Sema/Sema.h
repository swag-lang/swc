#pragma once
#include "Parser/Ast.h"
#include "Parser/AstVisit.h"
#include "Report/Diagnostic.h"
#include "Symbol/Scope.h"
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

enum class CastKind
{
    LiteralSuffix,
    Implicit,
    Explicit,
    Promotion,
};

struct CastContext
{
    CastKind   kind;
    AstNodeRef errorNodeRef;
};

class Sema
{
    TaskContext* ctx_     = nullptr;
    SemaContext* semaCtx_ = nullptr;
    AstVisit     visit_;

    void               setVisitors();
    void               enterNode(AstNode& node);
    AstVisitStepResult preNode(AstNode& node);
    AstVisitStepResult postNode(AstNode& node);
    AstVisitStepResult preChild(AstNode& node, AstNodeRef& childRef);

    Scope*                              rootScope_    = nullptr;
    Scope*                              currentScope_ = nullptr;
    std::vector<std::unique_ptr<Scope>> scopes_;

public:
    Sema(TaskContext& ctx, SemaContext& semCtx);
    Sema(TaskContext& ctx, const Sema& parent, AstNodeRef root);
    ~Sema();
    JobResult exec();

    TaskContext&            ctx() { return *ctx_; }
    const TaskContext&      ctx() const { return *ctx_; }
    SemaContext&            semaCtx() { return *semaCtx_; }
    const SemaContext&      semaCtx() const { return *semaCtx_; }
    AstVisit&               visit() { return visit_; }
    const AstVisit&         visit() const { return visit_; }
    Ast&                    ast();
    const Ast&              ast() const;
    AstNode&                node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode&          node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }
    CompilerInstance&       compiler() { return ctx().compiler(); }
    const CompilerInstance& compiler() const { return ctx().compiler(); }
    ConstantManager&        constMgr() { return compiler().constMgr(); }
    const ConstantManager&  constMgr() const { return compiler().constMgr(); }
    TypeManager&            typeMgr() { return compiler().typeMgr(); }
    const TypeManager&      typeMgr() const { return compiler().typeMgr(); }
    const Token&            token(SourceViewRef srcViewRef, TokenRef tokenRef) const { return compiler().srcView(srcViewRef).token(tokenRef); }

    Scope*       currentScope() { return currentScope_; }
    const Scope* currentScope() const { return currentScope_; }
    Scope*       rootScope() { return rootScope_; }
    const Scope* rootScope() const { return rootScope_; }
    Scope*       pushScope(ScopeFlags flags);
    void         popScope();

    void       setReportArguments(Diagnostic& diag, SourceViewRef srcViewRef, TokenRef tokenRef) const;
    Diagnostic reportError(DiagnosticId id, AstNodeRef nodeRef);
    Diagnostic reportError(DiagnosticId id, AstNodeRef nodeRef, SourceViewRef srcViewRef, TokenRef tokenRef);
    Diagnostic reportError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokenRef);
    void       raiseError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokenRef);
    void       raiseError(DiagnosticId id, AstNodeRef nodeRef);
    void       raiseInvalidType(AstNodeRef nodeRef, TypeInfoRef srcTypeRef, TypeInfoRef targetTypeRef);
    void       raiseCannotCast(AstNodeRef nodeRef, TypeInfoRef srcTypeRef, TypeInfoRef targetTypeRef);
    void       raiseLiteralOverflow(AstNodeRef nodeRef, TypeInfoRef targetTypeRef);
    void       raiseExprNotConst(AstNodeRef nodeRef);
    void       raiseInternalError(const AstNode& node);

    bool        castAllowed(const CastContext& castCtx, TypeInfoRef srcTypeRef, TypeInfoRef targetTypeRef);
    ConstantRef cast(const CastContext& castCtx, ConstantRef srcRef, TypeInfoRef targetTypeRef);
};

SWC_END_NAMESPACE()
