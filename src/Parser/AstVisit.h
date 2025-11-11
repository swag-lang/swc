#pragma once
#include "Core/SmallVector.h"
#include <cstdint>
#include <functional>
#include <utility>

SWC_BEGIN_NAMESPACE()

class SourceFile;
struct AstNode;

struct AstVisitContext
{
    struct Frame
    {
        // Snapshot of the SourceFile* when this frame was created
        const SourceFile* sourceAtPush = nullptr;

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
    const SourceFile* currentSource = nullptr;

    // The explicit traversal stack (top is back())
    SmallVector<Frame, 64> stack;

    void reset(const SourceFile* initialFile = nullptr)
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

    static void start(AstVisitContext& ctx, const SourceFile* rootFile, AstNodeRef rootRef);
    bool        step(AstVisitContext& ctx) const;
    void        run(AstVisitContext& ctx) const;

private:
    Callbacks cb_{};

    static void           collectChildRefs(const AstNode* node, SmallVector<AstNodeRef>& out);
    static const AstNode* resolveNode(const AstVisitContext::Frame& fr);
};

SWC_END_NAMESPACE()
