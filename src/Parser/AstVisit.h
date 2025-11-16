#pragma once
#include "Core/SmallVector.h"

SWC_BEGIN_NAMESPACE()

class Ast;
class LexerOutput;
struct AstNode;

class AstVisit
{
public:
    enum class Action : uint8_t
    {
        Continue,     // normal flow
        SkipChildren, // don't descend, go straight to post()
        Stop          // abort traversal immediately
    };

    // Both callbacks are optional; if unset, they're no-ops.
    using Callback = Action (*)(AstVisit&, AstNode&);
    struct Callbacks
    {
        Callback pre  = nullptr;
        Callback post = nullptr;
    };

private:
    Callbacks cb_{};
    Ast*      ast_ = nullptr;

    struct Frame
    {
        enum class Stage : uint8_t
        {
            Pre,
            Children,
            Post
        };

        const LexerOutput* lexAtPush    = nullptr;
        AstNode*           node         = nullptr;
        uint32_t           nextChildIx  = 0; // index within this frame's child range
        uint32_t           firstChildIx = 0; // offset into AstVisit::children_
        uint32_t           numChildren  = 0; // number of children in that range
        AstNodeRef         nodeRef      = AstNodeRef::invalid();
        Stage              stage        = Stage::Pre;
    };

    const LexerOutput*      currentLex_ = nullptr;
    SmallVector<Frame, 64>  stack_;
    SmallVector<AstNodeRef> children_; // shared pool of children

    AstNode* parentNodeInternal(size_t up) const;

public:
    void           start(Ast& ast, const Callbacks& cb = {});
    bool           step();
    void           run();
    AstNode*       parentNode(size_t up = 0) { return parentNodeInternal(up); }
    const AstNode* parentNode(size_t up = 0) const { return parentNodeInternal(up); }

    const Ast* ast() const { return ast_; }
    Ast*       ast() { return ast_; }
};

SWC_END_NAMESPACE()
