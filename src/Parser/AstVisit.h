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
    struct Callbacks
    {
        std::function<Action(const AstVisit* visit, const AstNode* node)> pre  = {};
        std::function<Action(const AstVisit* visit, const AstNode* node)> post = {};
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

        const LexerOutput*      sourceAtPush = nullptr;
        AstNode*                node         = nullptr;
        SmallVector<AstNodeRef> children;
        AstNodeRef              nodeRef     = AstNodeRef::invalid();
        size_t                  nextChildIx = 0;
        Stage                   stage       = Stage::Pre;
    };

    const LexerOutput*     currentLex_ = nullptr;
    SmallVector<Frame, 64> stack_;

public:
    void start(Ast& ast, const Callbacks& cb = {});
    bool step();
    void run();
    void clear();

    const Ast* ast() const { return ast_; }
    Ast*       ast() { return ast_; }
};

SWC_END_NAMESPACE()
