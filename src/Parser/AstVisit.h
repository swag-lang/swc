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
    void           setPreNodeVisitor(const std::function<Result(AstNode&)>& visitor) { preNodeVisitor_ = visitor; }
    void           setPostNodeVisitor(const std::function<Result(AstNode&)>& visitor) { postNodeVisitor_ = visitor; }
    void           setPreChildVisitor(const std::function<Result(AstNode&, AstNodeRef&)>& visitor) { preChildVisitor_ = visitor; }
    AstVisitResult step(const TaskContext& ctx);

    AstNode*       parentNode(size_t up = 0) { return parentNodeInternal(up); }
    const AstNode* parentNode(size_t up = 0) const { return parentNodeInternal(up); }
    AstNode*       currentNode() { return stack_.back().node; }
    const AstNode* currentNode() const { return stack_.back().node; }
    AstNodeRef     currentNodeRef() const { return stack_.back().nodeRef; }
    bool           enteringState() const { return stack_.back().firstPass; }

    AstNodeRef root() const { return rootRef_; }
    const Ast& ast() const { return *ast_; }
    Ast&       ast() { return *ast_; }

#if SWC_HAS_VISIT_DEBUG_INFO
    const SourceFile*  dbgSrcFile = nullptr;
    const AstNode*     dbgNode    = nullptr;
    const Token*       dbgTok     = nullptr;
    std::string_view   dbgTokView;
    TokenRef           dbgTokRef = TokenRef::invalid();
    SourceCodeLocation dbgLoc;
#endif

private:
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
        bool       firstPass    = true;
    };

    Ast*                                         ast_     = nullptr;
    AstNodeRef                                   rootRef_ = AstNodeRef::invalid();
    std::function<Result(AstNode&)>              preNodeVisitor_;
    std::function<Result(AstNode&)>              postNodeVisitor_;
    std::function<Result(AstNode&, AstNodeRef&)> preChildVisitor_;

    SmallVector<Frame, 64>  stack_;
    SmallVector<AstNodeRef> children_;

    AstNode* parentNodeInternal(size_t up) const;
};

SWC_END_NAMESPACE()
