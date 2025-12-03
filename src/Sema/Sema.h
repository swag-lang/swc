#pragma once
#include "Parser/Ast.h"
#include "Parser/AstVisit.h"
#include "Sema/SemaInfo.h"
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

    TaskContext&             ctx() { return *ctx_; }
    const TaskContext&       ctx() const { return *ctx_; }
    SemaInfo&                semaInfo() { return *semaInfo_; }
    const SemaInfo&          semaInfo() const { return *semaInfo_; }
    AstVisit&                visit() { return visit_; }
    const AstVisit&          visit() const { return visit_; }
    AstNode&                 node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode&           node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }
    CompilerInstance&        compiler() { return ctx().compiler(); }
    const CompilerInstance&  compiler() const { return ctx().compiler(); }
    ConstantManager&         cstMgr() { return compiler().cstMgr(); }
    const ConstantManager&   cstMgr() const { return compiler().cstMgr(); }
    TypeManager&             typeMgr() { return compiler().typeMgr(); }
    const TypeManager&       typeMgr() const { return compiler().typeMgr(); }
    IdentifierManager&       idMgr() { return compiler().idMgr(); }
    const IdentifierManager& idMgr() const { return compiler().idMgr(); }
    SourceView&              srcView(SourceViewRef srcViewRef) { return compiler().srcView(srcViewRef); }
    const SourceView&        srcView(SourceViewRef srcViewRef) const { return compiler().srcView(srcViewRef); }
    const Token&             token(SourceViewRef srcViewRef, TokenRef tokRef) const { return srcView(srcViewRef).token(tokRef); }

    void       semaInherit(AstNode& nodeDst, AstNodeRef srcRef);
    Ast&       ast();
    const Ast& ast() const;

    TypeRef              typeRefOf(AstNodeRef n) const { return semaInfo().getTypeRef(ctx(), n); }
    ConstantRef          constantRefOf(AstNodeRef n) const { return semaInfo().getConstantRef(n); }
    const ConstantValue& constantOf(AstNodeRef n) const { return semaInfo().getConstant(ctx(), n); }
    const Symbol&        symbolOf(AstNodeRef n) const { return semaInfo().getSymbol(ctx(), n); }
    void                 setType(AstNodeRef n, TypeRef ref) { semaInfo().setType(n, ref); }
    void                 setConstant(AstNodeRef n, ConstantRef ref) { semaInfo().setConstant(n, ref); }
    void                 setSymbol(AstNodeRef n, Symbol* symbol) { semaInfo().setSymbol(n, symbol); }
    bool                 hasType(AstNodeRef n) const { return semaInfo().hasType(n); }
    bool                 hasConstant(AstNodeRef n) const { return semaInfo().hasConstant(n); }
    bool                 hasSymbol(AstNodeRef n) const { return semaInfo().hasSymbol(n); }

    AstNodeRef       curNodeRef() const { return visit_.currentNodeRef(); }
    Scope&           curScope() { return *currentScope_; }
    const Scope&     curScope() const { return *currentScope_; }
    SymbolMap&       curSymMap() { return currentScope_->symMap(); }
    const SymbolMap& curSymMap() const { return currentScope_->symMap(); }
    Scope*           pushScope(ScopeFlags flags);
    void             popScope();

    void       setReportArguments(Diagnostic& diag, SourceViewRef srcViewRef, TokenRef tokRef) const;
    Diagnostic reportError(DiagnosticId id, AstNodeRef nodeRef);
    Diagnostic reportError(DiagnosticId id, AstNodeRef nodeRef, SourceViewRef srcViewRef, TokenRef tokRef);
    Diagnostic reportError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef);
    void       raiseError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef);
    void       raiseError(DiagnosticId id, AstNodeRef nodeRef);
    void       raiseInvalidType(AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    void       raiseCannotCast(AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    void       raiseLiteralOverflow(AstNodeRef nodeRef, TypeRef targetTypeRef);
    void       raiseExprNotConst(AstNodeRef nodeRef);
    void       raiseInternalError(const AstNode& node);

    bool        castAllowed(const CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef);
    ConstantRef cast(const CastContext& castCtx, ConstantRef srcRef, TypeRef targetTypeRef);
};

SWC_END_NAMESPACE()
