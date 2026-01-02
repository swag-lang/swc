#pragma once
#include "Core/SmallVector.h"
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE()

class Ast;
class SourceView;
struct AstNode;

enum class AstVisitResult
{
    Continue, // normal flow
    Pause,    // abort traversal immediately, but we are not finished
    Stop      // abort traversal immediately
};

class AstVisit
{
public:
    void           start(Ast& ast, AstNodeRef root);
    void           setEnterNodeVisitor(const std::function<void(AstNode&)>& visitor) { enterNodeVisitor_ = visitor; }
    void           setPreNodeVisitor(const std::function<AstStepResult(AstNode&)>& visitor) { preNodeVisitor_ = visitor; }
    void           setPostNodeVisitor(const std::function<AstStepResult(AstNode&)>& visitor) { postNodeVisitor_ = visitor; }
    void           setPreChildVisitor(const std::function<AstStepResult(AstNode&, AstNodeRef&)>& visitor) { preChildVisitor_ = visitor; }
    AstVisitResult step(const TaskContext& ctx);

    AstNode*       parentNode(size_t up = 0) { return parentNodeInternal(up); }
    const AstNode* parentNode(size_t up = 0) const { return parentNodeInternal(up); }
    AstNode*       currentNode() { return stack_.back().node; }
    const AstNode* currentNode() const { return stack_.back().node; }
    AstNodeRef     currentNodeRef() const { return stack_.back().nodeRef; }

    AstNodeRef root() const { return rootRef_; }
    const Ast& ast() const { return *ast_; }
    Ast&       ast() { return *ast_; }

private:
    struct Frame
    {
        enum class Stage : uint8_t
        {
            Enter,
            Pre,
            Children,
            Post
        };

        AstNode*   node         = nullptr;
        uint32_t   nextChildIx  = 0; // index within this frame's child range
        uint32_t   firstChildIx = 0; // offset into AstVisit::children_
        uint32_t   numChildren  = 0; // number of children in that range
        AstNodeRef nodeRef      = AstNodeRef::invalid();
        Stage      stage        = Stage::Enter;
    };

    Ast*                                                ast_     = nullptr;
    AstNodeRef                                          rootRef_ = AstNodeRef::invalid();
    std::function<void(AstNode&)>                       enterNodeVisitor_;
    std::function<AstStepResult(AstNode&)>              preNodeVisitor_;
    std::function<AstStepResult(AstNode&)>              postNodeVisitor_;
    std::function<AstStepResult(AstNode&, AstNodeRef&)> preChildVisitor_;

    SmallVector<Frame, 64>  stack_;
    SmallVector<AstNodeRef> children_;

    AstNode* parentNodeInternal(size_t up) const;

#if SWC_HAS_DEBUG_INFO
    const SourceFile*  dbgSrcFile_ = nullptr;
    const AstNode*     dbgNode_    = nullptr;
    const Token*       dbgTok_     = nullptr;
    std::string_view   dbgTokView_;
    TokenRef           dbgTokRef_ = TokenRef::invalid();
    SourceCodeLocation dbgLoc_;
#endif
};

SWC_END_NAMESPACE()
