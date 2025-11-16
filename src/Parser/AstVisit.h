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
        std::function<Action(const AstNode* node)> pre  = {};
        std::function<Action(const AstNode* node)> post = {};
    };

    explicit AstVisit(const Callbacks& cb = {}) :
        cb_(std::move(cb))
    {
    }

    void start(const Ast& ast);
    bool step();
    void run();

    void reset(const LexerOutput* initialLex = nullptr)
    {
        currentLex_ = initialLex;
        stack_.clear();
    }

private:
    Callbacks  cb_{};
    const Ast* ast_ = nullptr;

    struct Frame
    {
        // Snapshot of the SourceFile* when this frame was created
        const LexerOutput* sourceAtPush = nullptr;

        // Store a stable reference
        AstNodeRef              nodeRef = AstNodeRef::invalid();
        SmallVector<AstNodeRef> children;
        size_t                  nextChildIx = 0;

        enum class Stage : uint8_t
        {
            Pre,
            Children,
            Post
        };
        Stage stage = Stage::Pre;
    };

    // Active file scope used to resolve AstNodeRef / SpanRef
    const LexerOutput* currentLex_ = nullptr;

    // The explicit traversal stack (top is back())
    SmallVector<Frame, 64> stack_;

    void           collectChildren(SmallVector<AstNodeRef>& out, const AstNode* node) const;
    const AstNode* resolveNode(const Frame& fr) const;
};

SWC_END_NAMESPACE()
