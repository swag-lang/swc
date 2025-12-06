#pragma once
#include "Parser/Ast.h"
#include "Parser/AstVisit.h"
#include "Sema/SemaInfo.h"
#include "Symbol/Scope.h"
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

struct SemaNodeViewList;
class SymbolNamespace;
class LookupResult;
class IdentifierManager;

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
    TaskContext*     ctx_             = nullptr;
    SemaInfo*        semaInfo_        = nullptr;
    SymbolNamespace* moduleNamespace_ = nullptr;
    AstVisit         visit_;

    void               setVisitors();
    void               enterNode(AstNode& node);
    AstVisitStepResult preNode(AstNode& node);
    AstVisitStepResult postNode(AstNode& node);
    AstVisitStepResult preChild(AstNode& node, AstNodeRef& childRef);

    Scope*                              rootScope_ = nullptr;
    Scope*                              curScope_  = nullptr;
    std::vector<std::unique_ptr<Scope>> scopes_;

public:
    Sema(TaskContext& ctx, SemaInfo& semCtx, SymbolNamespace& moduleNamespace);
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
    const Token&            token(SourceViewRef srcViewRef, TokenRef tokRef) const { return srcView(srcViewRef).token(tokRef); }

    void                     semaInherit(AstNode& nodeDst, AstNodeRef srcRef);
    ConstantManager&         cstMgr();
    const ConstantManager&   cstMgr() const;
    TypeManager&             typeMgr();
    const TypeManager&       typeMgr() const;
    IdentifierManager&       idMgr();
    const IdentifierManager& idMgr() const;
    SourceView&              srcView(SourceViewRef srcViewRef);
    const SourceView&        srcView(SourceViewRef srcViewRef) const;
    Ast&                     ast();
    const Ast&               ast() const;

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
    Scope&           curScope() { return *curScope_; }
    const Scope&     curScope() const { return *curScope_; }
    SymbolMap*       curSymMap() { return curScope_->symMap(); }
    const SymbolMap* curSymMap() const { return curScope_->symMap(); }
    Scope*           pushScope(ScopeFlags flags);
    void             popScope();

    void       setReportArguments(Diagnostic& diag, SourceViewRef srcViewRef, TokenRef tokRef) const;
    Diagnostic reportError(DiagnosticId id, AstNodeRef nodeRef) const;
    Diagnostic reportError(DiagnosticId id, AstNodeRef nodeRef, SourceViewRef srcViewRef, TokenRef tokRef) const;
    Diagnostic reportError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef) const;
    void       raiseError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef) const;
    void       raiseError(DiagnosticId id, AstNodeRef nodeRef) const;

    void raiseInvalidType(AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef) const;
    void raiseCannotCast(AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef) const;
    void raiseLiteralOverflow(AstNodeRef nodeRef, TypeRef targetTypeRef) const;
    void raiseExprNotConst(AstNodeRef nodeRef) const;
    void raiseInternalError(const AstNode& node) const;

    bool        castAllowed(const CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef);
    ConstantRef cast(const CastContext& castCtx, ConstantRef srcRef, TypeRef targetTypeRef);
    bool        promoteConstantsIfNeeded(const SemaNodeViewList& ops, ConstantRef& leftRef, ConstantRef& rightRef);

    void               lookupIdentifier(LookupResult& result, IdentifierRef idRef) const;
    AstVisitStepResult pause(TaskStateKind kind, AstNodeRef nodeRef);
    static void        waitAll(TaskContext& ctx, JobClientId clientId);
};

SWC_END_NAMESPACE()
