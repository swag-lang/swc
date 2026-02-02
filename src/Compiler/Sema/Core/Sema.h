#pragma once
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Sema/Core/SemaFrame.h"
#include "Compiler/Sema/Core/SemaInfo.h"
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
    Sema(TaskContext& ctx, SemaInfo& semInfo, bool declPass);
    Sema(TaskContext& ctx, const Sema& parent, AstNodeRef root);
    ~Sema();
    JobResult exec();

    TaskContext&               ctx() { return *ctx_; }
    const TaskContext&         ctx() const { return *ctx_; }
    bool                       isDeclPass() const { return declPass_; }
    SemaInfo&                  semaInfo() { return *semaInfo_; }
    const SemaInfo&            semaInfo() const { return *semaInfo_; }
    SemaFrame&                 frame() { return frames_.back(); }
    const SemaFrame&           frame() const { return frames_.back(); }
    std::span<const SemaFrame> frames() const { return frames_; }
    AstVisit&                  visit() { return visit_; }
    const AstVisit&            visit() const { return visit_; }
    AstNode&                   node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode&             node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }
    CompilerInstance&          compiler() { return ctx().compiler(); }
    const CompilerInstance&    compiler() const { return ctx().compiler(); }
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

    const SymbolNamespace& moduleNamespace() const { return semaInfo().moduleNamespace(); }
    SymbolNamespace&       moduleNamespace() { return semaInfo().moduleNamespace(); }
    void                   setModuleNamespace(SymbolNamespace& ns) { semaInfo().setModuleNamespace(ns); }
    const SymbolNamespace& fileNamespace() const { return semaInfo().fileNamespace(); }
    SymbolNamespace&       fileNamespace() { return semaInfo().fileNamespace(); }
    void                   setFileNamespace(SymbolNamespace& ns) { semaInfo().setFileNamespace(ns); }

    TypeRef                  typeRefOf(AstNodeRef n) const { return semaInfo().getTypeRef(ctx(), n); }
    ConstantRef              constantRefOf(AstNodeRef n) const { return semaInfo().getConstantRef(ctx(), n); }
    const ConstantValue&     constantOf(AstNodeRef n) const { return semaInfo().getConstant(ctx(), n); }
    const Symbol&            symbolOf(AstNodeRef n) const { return semaInfo().getSymbol(ctx(), n); }
    Symbol&                  symbolOf(AstNodeRef n) { return semaInfo().getSymbol(ctx(), n); }
    void                     setType(AstNodeRef n, TypeRef ref) { semaInfo().setType(n, ref); }
    void                     setConstant(AstNodeRef n, ConstantRef ref) { semaInfo().setConstant(n, ref); }
    void                     setSymbol(AstNodeRef n, Symbol* symbol) { semaInfo().setSymbol(n, symbol); }
    void                     setSymbol(AstNodeRef n, const Symbol* symbol) { semaInfo().setSymbol(n, symbol); }
    bool                     hasType(AstNodeRef n) const { return semaInfo().hasType(ctx(), n); }
    bool                     hasConstant(AstNodeRef n) const { return semaInfo().hasConstant(ctx(), n); }
    bool                     hasSymbol(AstNodeRef n) const { return semaInfo().hasSymbol(n); }
    bool                     hasSubstitute(AstNodeRef n) const { return semaInfo().hasSubstitute(n); }
    AstNodeRef               getSubstituteRef(AstNodeRef n) const { return semaInfo().getSubstituteRef(n); }
    void                     setSubstitute(AstNodeRef n, AstNodeRef substNodeRef) { semaInfo().setSubstitute(n, substNodeRef); }
    void                     setSymbolList(AstNodeRef n, std::span<const Symbol*> symbols) { semaInfo().setSymbolList(n, symbols); }
    void                     setSymbolList(AstNodeRef n, std::span<Symbol*> symbols) { semaInfo().setSymbolList(n, symbols); }
    bool                     hasSymbolList(AstNodeRef n) const { return semaInfo().hasSymbolList(n); }
    std::span<const Symbol*> getSymbolList(AstNodeRef n) const { return semaInfo().getSymbolList(n); }
    std::span<Symbol*>       getSymbolList(AstNodeRef n) { return semaInfo().getSymbolList(n); }
    bool                     hasPayload(AstNodeRef n) const { return semaInfo().hasPayload(n); }
    void                     setPayload(AstNodeRef n, void* payload) { semaInfo().setPayload(n, payload); }

    bool isLValue(const AstNode& n) const { return SemaInfo::isLValue(n); }
    bool isValue(const AstNode& n) const { return SemaInfo::isValue(n); }
    bool isLValue(AstNodeRef n) const { return SemaInfo::isLValue(node(n)); }
    bool isValue(AstNodeRef n) const { return SemaInfo::isValue(node(n)); }
    void setIsLValue(AstNode& n) { SemaInfo::setIsLValue(n); }
    void setIsValue(AstNode& n) { SemaInfo::setIsValue(n); }
    void setIsLValue(AstNodeRef n) { SemaInfo::setIsLValue(node(n)); }
    void setIsValue(AstNodeRef n) { SemaInfo::setIsValue(node(n)); }

    void inheritSemaFlags(AstNode& nodeDst, AstNodeRef srcRef) { SemaInfo::inheritSemaFlags(nodeDst, node(srcRef)); }
    void inheritSemaKindRef(AstNode& nodeDst, AstNodeRef srcRef) { SemaInfo::inheritSemaKindRef(nodeDst, node(srcRef)); }
    void inheritSema(AstNode& nodeDst, AstNodeRef srcRef) { SemaInfo::inheritSema(nodeDst, node(srcRef)); }

    template<typename T>
    T* payload(AstNodeRef n) const
    {
        return static_cast<T*>(semaInfo().getPayload(n));
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

    Result      waitIdentifier(IdentifierRef idRef, SourceViewRef srcViewRef, TokenRef tokRef);
    Result      waitCompilerDefined(IdentifierRef idRef, SourceViewRef srcViewRef, TokenRef tokRef);
    Result      waitImplRegistrations(IdentifierRef idRef, SourceViewRef srcViewRef, TokenRef tokRef);
    Result      waitCompleted(const Symbol* symbol, SourceViewRef srcViewRef, TokenRef tokRef);
    Result      waitDeclared(const Symbol* symbol, SourceViewRef srcViewRef, TokenRef tokRef);
    Result      waitTyped(const Symbol* symbol, SourceViewRef srcViewRef, TokenRef tokRef);
    Result      waitCompleted(const TypeInfo* type, AstNodeRef nodeRef);
    static void waitDone(TaskContext& ctx, JobClientId clientId);

private:
    SemaScope* pushScope(SemaScopeFlags flags);
    void       popScope();
    void       pushFrame(const SemaFrame& frame);
    void       popFrame();

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

    TaskContext* ctx_      = nullptr;
    SemaInfo*    semaInfo_ = nullptr;
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
