#pragma once
#include "Core/SmallVector.h"

SWC_BEGIN_NAMESPACE()

#pragma once

class SourceFile;
struct AstNode;

struct AstVisitContext
{
    struct Frame
    {
        const AstNode* node = nullptr;

        // We collect children once (as strong pointers) using the current SourceFile*
        SmallVector<const AstNode*, 8> children;
        size_t                         nextChildIx = 0;

        enum class Stage : uint8_t
        {
            Pre,
            Children,
            Post
        };
        Stage stage = Stage::Pre;

        // Snapshot of the SourceFile* when this frame was created (useful if you want
        // to restore on exit or debug file-scope changes while descending)
        SourceFile* sourceAtPush = nullptr;
    };

    // Active file scope used to resolve AstNodeRef / SpanRef
    SourceFile* currentSource = nullptr;

    // The explicit traversal stack (top is back())
    SmallVector<Frame, 64> stack;

    void reset(SourceFile* initialFile = nullptr)
    {
        currentSource = initialFile;
        stack.clear();
    }
};

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
        std::function<Action(AstVisitContext& ctx, const AstNode* node)> pre  = {};
        std::function<Action(AstVisitContext& ctx, const AstNode* node)> post = {};
    };

    explicit AstVisit(const Callbacks& cb = {}) :
        cb_(std::move(cb))
    {
    }

    static void start(AstVisitContext& ctx, const AstNode* root, SourceFile* rootFile);
    bool        step(AstVisitContext& ctx) const;
    void        run(AstVisitContext& ctx) const;

private:
    Callbacks cb_{};

    static void collectResolvedChildren(const AstVisitContext& ctx, AstVisitContext::Frame& fr);
    static void collectChildRefs(const AstNode* node, SmallVector<AstNodeRef>& out);
};

SWC_END_NAMESPACE()
