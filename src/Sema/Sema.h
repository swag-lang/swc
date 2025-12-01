#pragma once
#include "Parser/Ast.h"
#include "Parser/AstVisit.h"
#include "Sema/SemaInfo.h"
#include "Symbol/Scope.h"
#include "Thread/Job.h"
#include "Type/TypeManager.h"

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
    TaskContext* ctx_      = nullptr;
    SemaInfo*    semaInfo_ = nullptr;
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
    Sema(TaskContext& ctx, SemaInfo& semCtx);
    Sema(TaskContext& ctx, const Sema& parent, AstNodeRef root);
    ~Sema();
    JobResult exec();

    TaskContext&            ctx() { return *ctx_; }
    const TaskContext&      ctx() const { return *ctx_; }
    SemaInfo&               semaInfo() { return *semaInfo_; }
    const SemaInfo&         semaInfo() const { return *semaInfo_; }
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

    Ast&       ast();
    const Ast& ast() const;

    TypeRef              typeRefOf(AstNodeRef n) const { return semaInfo().getTypeRef(ctx(), n); }
    ConstantRef          constantRefOf(AstNodeRef n) const { return semaInfo().getConstantRef(n); }
    const ConstantValue& constantOf(AstNodeRef n) const { return semaInfo().getConstant(ctx(), n); }
    bool                 hasConstant(AstNodeRef n) const { return semaInfo().hasConstant(n); }

    AstNodeRef   currentNodeRef() const { return visit_.currentNodeRef(); }
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
    void       raiseInvalidType(AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    void       raiseCannotCast(AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    void       raiseLiteralOverflow(AstNodeRef nodeRef, TypeRef targetTypeRef);
    void       raiseExprNotConst(AstNodeRef nodeRef);
    void       raiseInternalError(const AstNode& node);

    bool        castAllowed(const CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef);
    ConstantRef cast(const CastContext& castCtx, ConstantRef srcRef, TypeRef targetTypeRef);
};

struct SemaNodeView
{
    const AstNode*       node    = nullptr;
    const ConstantValue* cst     = nullptr;
    ConstantRef          cstRef  = ConstantRef::invalid();
    TypeRef              typeRef = TypeRef::invalid();
    const TypeInfo*      type    = nullptr;

    SemaNodeView(Sema& sema, AstNodeRef nodeRef)
    {
        node    = &sema.node(nodeRef);
        typeRef = sema.typeRefOf(nodeRef);
        type    = &sema.typeMgr().get(typeRef);

        if (sema.hasConstant(nodeRef))
        {
            cstRef = sema.constantRefOf(nodeRef);
            cst    = &sema.constantOf(nodeRef);
        }
    }
};

SWC_END_NAMESPACE()
