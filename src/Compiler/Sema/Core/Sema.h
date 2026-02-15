// ReSharper disable CppMemberFunctionMayBeStatic
#pragma once
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Sema/Core/NodePayloadContext.h"
#include "Compiler/Sema/Core/SemaFrame.h"
#include "Compiler/Sema/Core/SemaScope.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

struct CastRequest;
struct SemaNodeView;
class SymbolNamespace;
class MatchContext;
class IdentifierManager;

class Sema
{
public:
    Sema(TaskContext& ctx, NodePayloadContext& payloadContext, bool declPass);
    Sema(TaskContext& ctx, const Sema& parent, AstNodeRef root);
    ~Sema();
    JobResult exec();
    Result    execResult();

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
    const Token&               token(const SourceCodeRef& codeRef) const { return srcView(codeRef.srcViewRef).token(codeRef.tokRef); }
    SourceCodeRange            tokenCodeRange(const SourceCodeRef& codeRef) const { return srcView(codeRef.srcViewRef).tokenCodeRange(ctx(), codeRef.tokRef); }
    std::string_view           tokenString(const SourceCodeRef& codeRef) const { return srcView(codeRef.srcViewRef).tokenString(codeRef.tokRef); }

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

    const SymbolNamespace& moduleNamespace() const { return nodePayloadContext().moduleNamespace(); }
    SymbolNamespace&       moduleNamespace() { return nodePayloadContext().moduleNamespace(); }
    void                   setModuleNamespace(SymbolNamespace& ns) { nodePayloadContext().setModuleNamespace(ns); }
    const SymbolNamespace& fileNamespace() const { return nodePayloadContext().fileNamespace(); }
    SymbolNamespace&       fileNamespace() { return nodePayloadContext().fileNamespace(); }
    void                   setFileNamespace(SymbolNamespace& ns) { nodePayloadContext().setFileNamespace(ns); }

    TypeRef                  typeRefOf(AstNodeRef n) const { return nodePayloadContext().getTypeRef(ctx(), n); }
    ConstantRef              constantRefOf(AstNodeRef n) const { return nodePayloadContext().getConstantRef(ctx(), n); }
    const ConstantValue&     constantOf(AstNodeRef n) const { return nodePayloadContext().getConstant(ctx(), n); }
    const Symbol&            symbolOf(AstNodeRef n) const { return nodePayloadContext().getSymbol(ctx(), n); }
    Symbol&                  symbolOf(AstNodeRef n) { return nodePayloadContext().getSymbol(ctx(), n); }
    void                     setType(AstNodeRef n, TypeRef ref) { nodePayloadContext().setType(n, ref); }
    void                     setConstant(AstNodeRef n, ConstantRef ref) { nodePayloadContext().setConstant(n, ref); }
    void                     setSymbol(AstNodeRef n, Symbol* symbol) { nodePayloadContext().setSymbol(n, symbol); }
    void                     setSymbol(AstNodeRef n, const Symbol* symbol) { nodePayloadContext().setSymbol(n, symbol); }
    bool                     hasType(AstNodeRef n) const { return nodePayloadContext().hasType(ctx(), n); }
    bool                     hasConstant(AstNodeRef n) const { return nodePayloadContext().hasConstant(ctx(), n); }
    bool                     hasSymbol(AstNodeRef n) const { return nodePayloadContext().hasSymbol(n); }
    bool                     hasSubstitute(AstNodeRef n) const { return nodePayloadContext().hasSubstitute(n); }
    AstNodeRef               getSubstituteRef(AstNodeRef n) const { return nodePayloadContext().getSubstituteRef(n); }
    void                     setSubstitute(AstNodeRef n, AstNodeRef substNodeRef) { nodePayloadContext().setSubstitute(n, substNodeRef); }
    void                     setSymbolList(AstNodeRef n, std::span<const Symbol*> symbols) { nodePayloadContext().setSymbolList(n, symbols); }
    void                     setSymbolList(AstNodeRef n, std::span<Symbol*> symbols) { nodePayloadContext().setSymbolList(n, symbols); }
    bool                     hasSymbolList(AstNodeRef n) const { return nodePayloadContext().hasSymbolList(n); }
    std::span<const Symbol*> getSymbolList(AstNodeRef n) const { return nodePayloadContext().getSymbolList(n); }
    std::span<Symbol*>       getSymbolList(AstNodeRef n) { return nodePayloadContext().getSymbolList(n); }
    bool                     hasPayload(AstNodeRef n) const { return nodePayloadContext().hasPayload(n); }
    void                     setPayload(AstNodeRef n, void* payload) { nodePayloadContext().setPayload(n, payload); }
    bool                     hasCodeGenPayload(AstNodeRef n) const { return nodePayloadContext().hasCodeGenPayload(n); }
    void                     setCodeGenPayload(AstNodeRef n, void* payload) { nodePayloadContext().setCodeGenPayload(n, payload); }

    bool isLValue(const AstNode& node) const { return NodePayloadContext::hasPayloadFlags(node, NodePayloadFlags::LValue); }
    bool isValue(const AstNode& node) const { return NodePayloadContext::hasPayloadFlags(node, NodePayloadFlags::Value); }
    bool isFoldedTypedConst(const AstNode& node) const { return NodePayloadContext::hasPayloadFlags(node, NodePayloadFlags::FoldedTypedConst); }
    void setIsLValue(AstNode& node) { NodePayloadContext::addPayloadFlags(node, NodePayloadFlags::LValue); }
    void setIsValue(AstNode& node) { NodePayloadContext::addPayloadFlags(node, NodePayloadFlags::Value); }
    void setFoldedTypedConst(AstNode& node) { NodePayloadContext::addPayloadFlags(node, NodePayloadFlags::FoldedTypedConst); }
    bool isLValue(AstNodeRef ref) const { return NodePayloadContext::hasPayloadFlags(node(ref), NodePayloadFlags::LValue); }
    bool isValue(AstNodeRef ref) const { return NodePayloadContext::hasPayloadFlags(node(ref), NodePayloadFlags::Value); }
    bool isFoldedTypedConst(AstNodeRef ref) const { return NodePayloadContext::hasPayloadFlags(node(ref), NodePayloadFlags::FoldedTypedConst); }
    void setIsLValue(AstNodeRef ref) { NodePayloadContext::addPayloadFlags(node(ref), NodePayloadFlags::LValue); }
    void setIsValue(AstNodeRef ref) { NodePayloadContext::addPayloadFlags(node(ref), NodePayloadFlags::Value); }
    void setFoldedTypedConst(AstNodeRef ref) { NodePayloadContext::addPayloadFlags(node(ref), NodePayloadFlags::FoldedTypedConst); }

    void inheritPayloadFlags(AstNode& nodeDst, AstNodeRef srcRef) { NodePayloadContext::propagatePayloadFlags(nodeDst, node(srcRef), NODE_PAYLOAD_FLAGS_MASK, false); }
    void inheritPayloadKindRef(AstNode& nodeDst, AstNodeRef srcRef) { NodePayloadContext::inheritPayloadKindRef(nodeDst, node(srcRef)); }
    void inheritPayload(AstNode& nodeDst, AstNodeRef srcRef) { NodePayloadContext::inheritPayload(nodeDst, node(srcRef)); }

    template<typename T>
    T* payload(AstNodeRef n) const
    {
        return static_cast<T*>(nodePayloadContext().getPayload(n));
    }

    template<typename T>
    T* codeGenPayload(AstNodeRef n) const
    {
        return static_cast<T*>(nodePayloadContext().getCodeGenPayload(n));
    }

    AstNodeRef       curNodeRef() const { return visit_.currentNodeRef(); }
    SemaNodeView     nodeView(AstNodeRef nodeRef);
    SemaNodeView     curNodeView();
    SymbolMap*       curSymMap() { return curScope_->symMap(); }
    const SymbolMap* curSymMap() const { return curScope_->symMap(); }
    const SymbolMap* topSymMap() const { return startSymMap_; }

    SemaScope&       curScope() { return *curScope_; }
    const SemaScope& curScope() const { return *curScope_; }
    void             pushFramePopOnPostChild(const SemaFrame& frame, AstNodeRef popAfterChildRef);
    void             pushFramePopOnPostNode(const SemaFrame& frame, AstNodeRef popNodeRef = AstNodeRef::invalid());
    SemaScope*       pushScopePopOnPostChild(SemaScopeFlags flags, AstNodeRef popAfterChildRef);
    SemaScope*       pushScopePopOnPostNode(SemaScopeFlags flags, AstNodeRef popNodeRef = AstNodeRef::invalid());
    bool             enteringState() const { return visit_.enteringState(); }
    void             deferPostNodeAction(AstNodeRef nodeRef, std::function<Result(Sema&, AstNodeRef)> callback);

    Result      waitIdentifier(IdentifierRef idRef, const SourceCodeRef& codeRef);
    Result      waitPredefined(IdentifierManager::PredefinedName name, TypeRef& typeRef, const SourceCodeRef& codeRef);
    Result      waitCompilerDefined(IdentifierRef idRef, const SourceCodeRef& codeRef);
    Result      waitImplRegistrations(IdentifierRef idRef, const SourceCodeRef& codeRef);
    Result      waitSemaCompleted(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result      waitCodeGenCompleted(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result      waitDeclared(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result      waitTyped(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result      waitSemaCompleted(const TypeInfo* type, AstNodeRef nodeRef);
    static void waitDone(TaskContext& ctx, JobClientId clientId);

private:
    SemaScope*                pushScope(SemaScopeFlags flags);
    void                      popScope();
    void                      pushFrame(const SemaFrame& frame);
    void                      popFrame();
    NodePayloadContext&       nodePayloadContext() { return *nodePayloadContext_; }
    const NodePayloadContext& nodePayloadContext() const { return *nodePayloadContext_; }

    void   setVisitors();
    Result preDecl(AstNode& node);
    Result preDeclChild(AstNode& node, AstNodeRef& childRef);
    Result postDeclChild(AstNode& node, AstNodeRef& childRef);
    Result postDecl(AstNode& node);
    Result preNode(AstNode& node);
    Result postNode(AstNode& node);
    Result preNodeChild(AstNode& node, AstNodeRef& childRef);
    Result postNodeChild(AstNode& node, AstNodeRef& childRef);

    void errorCleanupNode(AstNodeRef nodeRef, AstNode& node);

    void   processDeferredPopsPostChild(AstNodeRef nodeRef, AstNodeRef childRef);
    void   processDeferredPopsPostNode(AstNodeRef nodeRef);
    Result processDeferredPostNodeActions(AstNodeRef nodeRef);

    TaskContext*        ctx_                = nullptr;
    NodePayloadContext* nodePayloadContext_ = nullptr;
    AstVisit            visit_;

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

    struct DeferredPostNodeAction
    {
        AstNodeRef                               nodeRef;
        std::function<Result(Sema&, AstNodeRef)> callback;
    };
    std::vector<DeferredPostNodeAction> deferredPostNodeActions_;
};

SWC_END_NAMESPACE();
