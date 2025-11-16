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

    explicit AstVisit(const Callbacks& cb = {}) :
        cb_(std::move(cb))
    {
    }

    void start(const Ast& ast);
    bool step();
    void run();
    void reset(const LexerOutput* initialLex = nullptr);

private:
    Callbacks  cb_{};
    const Ast* ast_ = nullptr;

    struct Frame
    {
        enum class Stage : uint8_t
        {
            Pre,
            Children,
            Post
        };

        const LexerOutput*      sourceAtPush = nullptr;
        AstNodeRef              nodeRef      = AstNodeRef::invalid();
        SmallVector<AstNodeRef> children;
        size_t                  nextChildIx = 0;
        Stage                   stage       = Stage::Pre;
    };

    const LexerOutput*     currentLex_ = nullptr;
    SmallVector<Frame, 64> stack_;

    void           collectChildren(SmallVector<AstNodeRef>& out, const AstNode* node) const;
    const AstNode* resolveNode(const Frame& fr) const;
};

SWC_END_NAMESPACE()
