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

        AstNode*   node         = nullptr;
        uint32_t   nextChildIx  = 0; // index within this frame's child range
        uint32_t   firstChildIx = 0; // offset into AstVisit::children_
        uint32_t   numChildren  = 0; // number of children in that range
        AstNodeRef nodeRef      = AstNodeRef::invalid();
        Stage      stage        = Stage::Pre;
    };

    Ast*                                                     ast_     = nullptr;
    AstNodeRef                                               rootRef_ = AstNodeRef::invalid();
    std::function<void(AstNode&)>                            enterNodeVisitor_;
    std::function<AstVisitStepResult(AstNode&)>              preNodeVisitor_;
    std::function<AstVisitStepResult(AstNode&)>              postNodeVisitor_;
    std::function<AstVisitStepResult(AstNode&, AstNodeRef&)> preChildVisitor_;

    SmallVector<Frame, 64>  stack_;
    SmallVector<AstNodeRef> children_;

    AstNode* parentNodeInternal(size_t up) const;

public:
    void           start(Ast& ast, AstNodeRef root);
    void           setEnterNodeVisitor(const std::function<void(AstNode&)>& visitor) { enterNodeVisitor_ = visitor; }
    void           setPreNodeVisitor(const std::function<AstVisitStepResult(AstNode&)>& visitor) { preNodeVisitor_ = visitor; }
    void           setPostNodeVisitor(const std::function<AstVisitStepResult(AstNode&)>& visitor) { postNodeVisitor_ = visitor; }
    void           setPreChildVisitor(const std::function<AstVisitStepResult(AstNode&, AstNodeRef&)>& visitor) { preChildVisitor_ = visitor; }
    AstVisitResult step();

    AstNode*       parentNode(size_t up = 0) { return parentNodeInternal(up); }
    const AstNode* parentNode(size_t up = 0) const { return parentNodeInternal(up); }
    AstNode*       currentNode() { return stack_.back().node; }
    const AstNode* currentNode() const { return stack_.back().node; }
    AstNodeRef     currentNodeRef() { return stack_.back().nodeRef; }

    AstNodeRef root() const { return rootRef_; }
    const Ast& ast() const { return *ast_; }
    Ast&       ast() { return *ast_; }
};

SWC_END_NAMESPACE()
