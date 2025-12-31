#pragma once
#include "Parser/Ast.h"
#include "Parser/AstVisit.h"
#include "Sema/Core/SemaFrame.h"
#include "Sema/Core/SemaScope.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

struct CastContext;
struct SemaNodeView;
class SymbolNamespace;
class LookUpContext;
class IdentifierManager;

class Sema
{
public:
    Sema(TaskContext& ctx, SemaInfo& semInfo, bool declPass);
    Sema(TaskContext& ctx, const Sema& parent, AstNodeRef root);
    ~Sema();
    JobResult exec();

    TaskContext&            ctx() { return *ctx_; }
    const TaskContext&      ctx() const { return *ctx_; }
    bool                    isDeclPass() const { return declPass_; }
    SemaInfo&               semaInfo() { return *semaInfo_; }
    const SemaInfo&         semaInfo() const { return *semaInfo_; }
    SemaFrame&              frame() { return frame_.back(); }
    const SemaFrame&        frame() const { return frame_.back(); }
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
    Utf8                     fileName() const;
    const Ast&               ast() const;

    TypeRef              typeRefOf(AstNodeRef n) const { return semaInfo().getTypeRef(ctx(), n); }
    ConstantRef          constantRefOf(AstNodeRef n) const { return semaInfo().getConstantRef(ctx(), n); }
    const ConstantValue& constantOf(AstNodeRef n) const { return semaInfo().getConstant(ctx(), n); }
    const Symbol&        symbolOf(AstNodeRef n) const { return semaInfo().getSymbol(ctx(), n); }
    Symbol&              symbolOf(AstNodeRef n) { return semaInfo().getSymbol(ctx(), n); }
    void                 setType(AstNodeRef n, TypeRef ref) { semaInfo().setType(n, ref); }
    void                 setConstant(AstNodeRef n, ConstantRef ref) { semaInfo().setConstant(n, ref); }
    void                 setSymbol(AstNodeRef n, Symbol* symbol) { semaInfo().setSymbol(n, symbol); }
    void                 setSymbol(AstNodeRef n, const Symbol* symbol) { semaInfo().setSymbol(n, symbol); }
    bool                 hasType(AstNodeRef n) const { return semaInfo().hasType(n); }
    bool                 hasConstant(AstNodeRef n) const { return semaInfo().hasConstant(ctx(), n); }
    bool                 hasSymbol(AstNodeRef n) const { return semaInfo().hasSymbol(n); }
    bool                 hasPayload(AstNodeRef n) const { return semaInfo().hasPayload(n); }
    void                 setPayload(AstNodeRef n, void* payload) { semaInfo().setPayload(n, payload); }

    template<typename T>
    T* payload(AstNodeRef n) const
    {
        return static_cast<T*>(semaInfo().getPayload(n));
    }

    AstNodeRef       curNodeRef() const { return visit_.currentNodeRef(); }
    SymbolMap*       curSymMap() { return curScope_->symMap(); }
    const SymbolMap* curSymMap() const { return curScope_->symMap(); }

    SemaScope&       curScope() { return *curScope_; }
    const SemaScope& curScope() const { return *curScope_; }
    SemaScope*       pushScope(SemaScopeFlags flags);
    void             popScope();
    void             pushFrame(const SemaFrame& frame);
    void             popFrame();

    AstVisitStepResult waitIdentifier(IdentifierRef idRef);
    AstVisitStepResult waitCompilerDefined(IdentifierRef idRef);
    AstVisitStepResult waitComplete(const Symbol* symbol);
    AstVisitStepResult waitDeclared(const Symbol* symbol);
    static void        waitDone(TaskContext& ctx, JobClientId clientId);

private:
    TaskContext* ctx_      = nullptr;
    SemaInfo*    semaInfo_ = nullptr;
    AstVisit     visit_;

    void               setVisitors();
    void               enterNode(AstNode& node);
    AstVisitStepResult preDecl(AstNode& node);
    AstVisitStepResult preDeclChild(AstNode& node, AstNodeRef& childRef);
    AstVisitStepResult postDecl(AstNode& node);
    AstVisitStepResult preNode(AstNode& node);
    AstVisitStepResult postNode(AstNode& node);
    AstVisitStepResult preNodeChild(AstNode& node, AstNodeRef& childRef);

    std::vector<std::unique_ptr<SemaScope>> scopes_;
    SymbolMap*                              startSymMap_ = nullptr;
    SemaScope*                              curScope_    = nullptr;
    bool                                    declPass_    = false;

    std::vector<SemaFrame> frame_;
};

SWC_END_NAMESPACE()
