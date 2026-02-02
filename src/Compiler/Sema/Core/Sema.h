// ReSharper disable CppMemberFunctionMayBeStatic
#pragma once
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Sema/Core/SemaContext.h"
#include "Compiler/Sema/Core/SemaFrame.h"
#include "Compiler/Sema/Core/SemaScope.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

struct CastContext;
struct SemaNodeView;
class SymbolNamespace;
class MatchContext;
class IdentifierManager;

class Sema
{
public:
    Sema(TaskContext& ctx, SemaContext& semInfo, bool declPass);
    Sema(TaskContext& ctx, const Sema& parent, AstNodeRef root);
    ~Sema();
    JobResult exec();

    TaskContext&               ctx() { return *ctx_; }
    const TaskContext&         ctx() const { return *ctx_; }
    bool                       isDeclPass() const { return declPass_; }
    SemaFrame&                 frame() { return frames_.back(); }
    const SemaFrame&           frame() const { return frames_.back(); }
    std::span<const SemaFrame> frames() const { return frames_; }
    AstVisit&                  visit() { return visit_; }
    const AstVisit&            visit() const { return visit_; }
    AstNode&                   node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode&             node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }
    CompilerInstance&          compiler() { return ctx().compiler(); }
    const CompilerInstance&    compiler() const { return ctx().compiler(); }
    const Token&               token(SourceCodeRef loc) const { return srcView(loc.srcViewRef).token(loc.tokRef); }
    const Token&               token(SourceViewRef srcViewRef, TokenRef tokRef) const { return srcView(srcViewRef).token(tokRef); }

    ConstantManager&         cstMgr();
    const ConstantManager&   cstMgr() const;
    TypeManager&             typeMgr();
    const TypeManager&       typeMgr() const;
    TypeGen&                 typeGen();
    const TypeGen&           typeGen() const;
    IdentifierManager&       idMgr();
    const IdentifierManager& idMgr() const;
    SourceView&              srcView(SourceViewRef srcViewRef);
    const SourceView&        srcView(SourceViewRef srcViewRef) const;
    Ast&                     ast();
    Utf8                     fileName() const;
    const SourceFile*        file() const;
    const Ast&               ast() const;

    const SymbolNamespace& moduleNamespace() const { return semaContext().moduleNamespace(); }
    SymbolNamespace&       moduleNamespace() { return semaContext().moduleNamespace(); }
    void                   setModuleNamespace(SymbolNamespace& ns) { semaContext().setModuleNamespace(ns); }
    const SymbolNamespace& fileNamespace() const { return semaContext().fileNamespace(); }
    SymbolNamespace&       fileNamespace() { return semaContext().fileNamespace(); }
    void                   setFileNamespace(SymbolNamespace& ns) { semaContext().setFileNamespace(ns); }

    TypeRef                  typeRefOf(AstNodeRef n) const { return semaContext().getTypeRef(ctx(), n); }
    ConstantRef              constantRefOf(AstNodeRef n) const { return semaContext().getConstantRef(ctx(), n); }
    const ConstantValue&     constantOf(AstNodeRef n) const { return semaContext().getConstant(ctx(), n); }
    const Symbol&            symbolOf(AstNodeRef n) const { return semaContext().getSymbol(ctx(), n); }
    Symbol&                  symbolOf(AstNodeRef n) { return semaContext().getSymbol(ctx(), n); }
    void                     setType(AstNodeRef n, TypeRef ref) { semaContext().setType(n, ref); }
    void                     setConstant(AstNodeRef n, ConstantRef ref) { semaContext().setConstant(n, ref); }
    void                     setSymbol(AstNodeRef n, Symbol* symbol) { semaContext().setSymbol(n, symbol); }
    void                     setSymbol(AstNodeRef n, const Symbol* symbol) { semaContext().setSymbol(n, symbol); }
    bool                     hasType(AstNodeRef n) const { return semaContext().hasType(ctx(), n); }
    bool                     hasConstant(AstNodeRef n) const { return semaContext().hasConstant(ctx(), n); }
    bool                     hasSymbol(AstNodeRef n) const { return semaContext().hasSymbol(n); }
    bool                     hasSubstitute(AstNodeRef n) const { return semaContext().hasSubstitute(n); }
    AstNodeRef               getSubstituteRef(AstNodeRef n) const { return semaContext().getSubstituteRef(n); }
    void                     setSubstitute(AstNodeRef n, AstNodeRef substNodeRef) { semaContext().setSubstitute(n, substNodeRef); }
    void                     setSymbolList(AstNodeRef n, std::span<const Symbol*> symbols) { semaContext().setSymbolList(n, symbols); }
    void                     setSymbolList(AstNodeRef n, std::span<Symbol*> symbols) { semaContext().setSymbolList(n, symbols); }
    bool                     hasSymbolList(AstNodeRef n) const { return semaContext().hasSymbolList(n); }
    std::span<const Symbol*> getSymbolList(AstNodeRef n) const { return semaContext().getSymbolList(n); }
    std::span<Symbol*>       getSymbolList(AstNodeRef n) { return semaContext().getSymbolList(n); }
    bool                     hasPayload(AstNodeRef n) const { return semaContext().hasPayload(n); }
    void                     setPayload(AstNodeRef n, void* payload) { semaContext().setPayload(n, payload); }

    bool isLValue(const AstNode& node) const { return SemaContext::hasSemaFlags(node, NodeSemaFlags::LValue); }
    bool isValue(const AstNode& node) const { return SemaContext::hasSemaFlags(node, NodeSemaFlags::Value); }
    void setIsLValue(AstNode& node) { SemaContext::addSemaFlags(node, NodeSemaFlags::LValue); }
    void setIsValue(AstNode& node) { SemaContext::addSemaFlags(node, NodeSemaFlags::Value); }
    bool isLValue(AstNodeRef ref) const { return SemaContext::hasSemaFlags(node(ref), NodeSemaFlags::LValue); }
    bool isValue(AstNodeRef ref) const { return SemaContext::hasSemaFlags(node(ref), NodeSemaFlags::Value); }
    void setIsLValue(AstNodeRef ref) { SemaContext::addSemaFlags(node(ref), NodeSemaFlags::LValue); }
    void setIsValue(AstNodeRef ref) { SemaContext::addSemaFlags(node(ref), NodeSemaFlags::Value); }

    void inheritSemaFlags(AstNode& nodeDst, AstNodeRef srcRef) { SemaContext::inheritSemaFlags(nodeDst, node(srcRef)); }
    void inheritSemaKindRef(AstNode& nodeDst, AstNodeRef srcRef) { SemaContext::inheritSemaKindRef(nodeDst, node(srcRef)); }
    void inheritSema(AstNode& nodeDst, AstNodeRef srcRef) { SemaContext::inheritSema(nodeDst, node(srcRef)); }

    template<typename T>
    T* payload(AstNodeRef n) const
    {
        return static_cast<T*>(semaContext().getPayload(n));
    }

    AstNodeRef       curNodeRef() const { return visit_.currentNodeRef(); }
    SymbolMap*       curSymMap() { return curScope_->symMap(); }
    const SymbolMap* curSymMap() const { return curScope_->symMap(); }
    const SymbolMap* topSymMap() const { return startSymMap_; }

    SemaScope&       curScope() { return *curScope_; }
    const SemaScope& curScope() const { return *curScope_; }
    void             pushFramePopOnPostChild(const SemaFrame& frame, AstNodeRef popAfterChildRef);
    void             pushFramePopOnPostNode(const SemaFrame& frame);
    SemaScope*       pushScopePopOnPostChild(SemaScopeFlags flags, AstNodeRef popAfterChildRef);
    SemaScope*       pushScopePopOnPostNode(SemaScopeFlags flags, AstNodeRef popNodeRef = AstNodeRef::invalid());
    bool             enteringState() const { return visit_.enteringState(); }

    Result waitIdentifier(IdentifierRef idRef, SourceCodeRef loc);
    Result waitCompilerDefined(IdentifierRef idRef, SourceCodeRef loc);
    Result waitImplRegistrations(IdentifierRef idRef, SourceCodeRef loc);
    Result waitCompleted(const Symbol* symbol, SourceCodeRef loc);
    Result waitDeclared(const Symbol* symbol, SourceCodeRef loc);
    Result waitTyped(const Symbol* symbol, SourceCodeRef loc);

    Result      waitIdentifier(IdentifierRef idRef, SourceViewRef srcViewRef, TokenRef tokRef);
    Result      waitCompilerDefined(IdentifierRef idRef, SourceViewRef srcViewRef, TokenRef tokRef);
    Result      waitImplRegistrations(IdentifierRef idRef, SourceViewRef srcViewRef, TokenRef tokRef);
    Result      waitCompleted(const Symbol* symbol, SourceViewRef srcViewRef, TokenRef tokRef);
    Result      waitDeclared(const Symbol* symbol, SourceViewRef srcViewRef, TokenRef tokRef);
    Result      waitTyped(const Symbol* symbol, SourceViewRef srcViewRef, TokenRef tokRef);
    Result      waitCompleted(const TypeInfo* type, AstNodeRef nodeRef);
    static void waitDone(TaskContext& ctx, JobClientId clientId);

private:
    SemaScope*         pushScope(SemaScopeFlags flags);
    void               popScope();
    void               pushFrame(const SemaFrame& frame);
    void               popFrame();
    SemaContext&       semaContext() { return *semaContext_; }
    const SemaContext& semaContext() const { return *semaContext_; }

    void   setVisitors();
    Result preDecl(AstNode& node);
    Result preDeclChild(AstNode& node, AstNodeRef& childRef);
    Result postDeclChild(AstNode& node, AstNodeRef& childRef);
    Result postDecl(AstNode& node);
    Result preNode(AstNode& node);
    Result postNode(AstNode& node);
    Result preNodeChild(AstNode& node, AstNodeRef& childRef);
    Result postNodeChild(AstNode& node, AstNodeRef& childRef);

    void errorCleanupNode(AstNode& node);

    void processDeferredPopsPostChild(AstNodeRef nodeRef, AstNodeRef childRef);
    void processDeferredPopsPostNode(AstNodeRef nodeRef);

    TaskContext* ctx_         = nullptr;
    SemaContext* semaContext_ = nullptr;
    AstVisit     visit_;

    std::vector<std::unique_ptr<SemaScope>> scopes_;
    SymbolMap*                              startSymMap_ = nullptr;
    SemaScope*                              curScope_    = nullptr;
    bool                                    declPass_    = false;

    std::vector<SemaFrame> frames_;

    struct DeferredPopFrame
    {
        AstNodeRef nodeRef;
        AstNodeRef childRef;
        bool       onPostNode = false;
        size_t     expectedFrameCountBefore;
        size_t     expectedFrameCountAfter;
    };

    struct DeferredPopScope
    {
        AstNodeRef nodeRef;
        AstNodeRef childRef;
        bool       onPostNode = false;
        size_t     expectedScopeCountBefore;
        size_t     expectedScopeCountAfter;
    };

    std::vector<DeferredPopFrame> deferredPopFrames_;
    std::vector<DeferredPopScope> deferredPopScopes_;
};

SWC_END_NAMESPACE();
