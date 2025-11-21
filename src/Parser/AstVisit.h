#pragma once
#include "Core/SmallVector.h"

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

enum class AstVisitStepResult
{
    Continue,     // normal flow
    SkipChildren, // don't descend, go straight to post()
    Pause,        // abort traversal immediately, but we are not finished
    Stop          // abort traversal immediately
};

class AstVisit
{
    struct Frame
    {
        enum class Stage : uint8_t
        {
            Pre,
            Children,
            Post
        };

        const SourceView* srcViewAtPush = nullptr;
        AstNode*          node          = nullptr;
        uint32_t          nextChildIx   = 0; // index within this frame's child range
        uint32_t          firstChildIx  = 0; // offset into AstVisit::children_
        uint32_t          numChildren   = 0; // number of children in that range
        AstNodeRef        nodeRef       = AstNodeRef::invalid();
        Stage             stage         = Stage::Pre;
    };

    Ast*                                                     ast_  = nullptr;
    AstNodeRef                                               root_ = AstNodeRef::invalid();
    std::function<AstVisitStepResult(AstNode&)>              preNodeVisitor_;
    std::function<AstVisitStepResult(AstNode&)>              postNodeVisitor_;
    std::function<AstVisitStepResult(AstNode&, AstNodeRef&)> preChildVisitor_;

    const SourceView*       curSrcView_ = nullptr;
    SmallVector<Frame, 64>  stack_;
    SmallVector<AstNodeRef> children_;

    AstNode* parentNodeInternal(size_t up) const;

public:
    void           start(Ast& ast, AstNodeRef root);
    void           setPreNodeVisitor(const std::function<AstVisitStepResult(AstNode&)>& visitor) { preNodeVisitor_ = visitor; }
    void           setPostNodeVisitor(const std::function<AstVisitStepResult(AstNode&)>& visitor) { postNodeVisitor_ = visitor; }
    void           setPreChildVisitor(const std::function<AstVisitStepResult(AstNode&, AstNodeRef&)>& visitor) { preChildVisitor_ = visitor; }
    AstVisitResult step();
    AstNode*       parentNode(size_t up = 0) { return parentNodeInternal(up); }
    const AstNode* parentNode(size_t up = 0) const { return parentNodeInternal(up); }

    const Ast&        ast() const { return *ast_; }
    Ast&              ast() { return *ast_; }
    const SourceView& curSrcView() const { return *curSrcView_; }
};

SWC_END_NAMESPACE()
