#include "pch.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE();

void AstVisit::start(Ast& ast, AstNodeRef root)
{
    SWC_ASSERT(root.isValid());

    ast_     = &ast;
    rootRef_ = root;

    stack_.clear();
    children_.clear();

    Frame fr;
    fr.nodeRef = root;
    fr.stage   = Frame::Stage::Pre;

    // Reset per-frame state (important if Frame is not POD-zeroed)
    fr.firstPass = true;

    fr.preNodeState  = Frame::CallState::NotCalled;
    fr.postNodeState = Frame::CallState::NotCalled;

    fr.pendingPostChild = false;
    fr.postChildState   = Frame::CallState::NotCalled;

    fr.preChildState = Frame::CallState::NotCalled;

    stack_.push_back(fr);
}

AstVisitResult AstVisit::step(const TaskContext& ctx)
{
    if (stack_.empty())
        return AstVisitResult::Error;

    Frame& fr = stack_.back();

#if SWC_HAS_VISIT_DEBUG_INFO
    dbgNode    = &ast_->node(fr.nodeRef);
    dbgTokRef  = dbgNode->tokRef();
    dbgTok     = dbgTokRef.isValid() ? &ast_->srcView().token(dbgTokRef) : nullptr;
    dbgTokView = dbgTok ? dbgTok->string(ast_->srcView()) : "";
    dbgSrcFile = ast_->srcView().file();
    dbgLoc     = dbgTok ? dbgTok->location(ctx, ast_->srcView()) : SourceCodeLocation{};
#endif

    switch (fr.stage)
    {
        case Frame::Stage::Pre:
        {
            if (fr.node == nullptr)
            {
                SWC_ASSERT(fr.nodeRef.isValid());
                fr.node = &ast_->node(fr.nodeRef);
                SWC_ASSERT(fr.node->isNot(AstNodeId::Invalid));
                SWC_ASSERT(fr.node->id() < AstNodeId::Count);

#if SWC_HAS_STATS
                Stats::get().numVisitedAstNodes.fetch_add(1);
#endif
            }

            // Pre-order callback (may be called multiple times on Pause)
            if (preNodeVisitor_ && fr.preNodeState != Frame::CallState::Done)
            {
                fr.firstPass        = (fr.preNodeState == Frame::CallState::NotCalled);
                const Result result = preNodeVisitor_(*fr.node);

                if (result == Result::Error)
                    return AstVisitResult::Error;
                if (result == Result::Pause)
                {
                    fr.preNodeState = Frame::CallState::Paused;
                    return AstVisitResult::Pause;
                }

                // Completed (Continue or SkipChildren)
                fr.preNodeState = Frame::CallState::Done;

                if (result == Result::SkipChildren)
                {
                    fr.stage = Frame::Stage::Post;
                    return AstVisitResult::Continue;
                }
            }

            // Collect children once we've completed preNode (or if no preNodeVisitor_)
            const auto& info = Ast::nodeIdInfos(fr.node->id());
            fr.firstChildIx  = children_.size32();
            info.collectChildren(children_, *ast_, *fr.node);
            fr.numChildren = children_.size32() - fr.firstChildIx;
            fr.nextChildIx = 0;

            // Prepare child-site states for the first child
            fr.preChildState    = Frame::CallState::NotCalled;
            fr.pendingPostChild = false;
            fr.postChildState   = Frame::CallState::NotCalled;

            fr.stage = Frame::Stage::Children;
            return AstVisitResult::Continue;
        }

        case Frame::Stage::Children:
        {
            while (true)
            {
                // If we just returned from a child, we owe one postChild callback.
                // It may Pause and be retried; firstPass must reflect first attempt vs retry.
                if (fr.pendingPostChild)
                {
                    if (postChildVisitor_ && fr.postChildState != Frame::CallState::Done)
                    {
                        SWC_ASSERT(fr.nextChildIx > 0);
                        AstNodeRef lastChildRef = children_[fr.firstChildIx + fr.nextChildIx - 1];

                        fr.firstPass        = (fr.postChildState == Frame::CallState::NotCalled);
                        const Result result = postChildVisitor_(*fr.node, lastChildRef);

                        if (result == Result::Error)
                            return AstVisitResult::Error;
                        if (result == Result::Pause)
                        {
                            fr.postChildState = Frame::CallState::Paused;
                            return AstVisitResult::Pause;
                        }

                        fr.postChildState = Frame::CallState::Done;
                    }

                    // postChild is completed (or no visitor)
                    fr.pendingPostChild = false;
                    fr.postChildState   = Frame::CallState::NotCalled;

                    // continue to process next child
                    continue;
                }

                // All children processed?
                if (fr.nextChildIx >= fr.numChildren)
                    break;

                const uint32_t localIdx = fr.nextChildIx;
                const uint32_t globalIx = fr.firstChildIx + localIdx;

                AstNodeRef childRef = children_[globalIx];

                // preChild callback for THIS child index (may be called multiple times on Pause)
                if (preChildVisitor_ && fr.preChildState != Frame::CallState::Done)
                {
                    fr.firstPass        = (fr.preChildState == Frame::CallState::NotCalled);
                    const Result result = preChildVisitor_(*fr.node, childRef);

                    if (result == Result::Error)
                        return AstVisitResult::Error;
                    if (result == Result::Pause)
                    {
                        fr.preChildState = Frame::CallState::Paused;
                        return AstVisitResult::Pause;
                    }

                    fr.preChildState = Frame::CallState::Done;

                    if (result == Result::SkipChildren)
                    {
                        // Move to next child
                        fr.nextChildIx++;
                        fr.preChildState = Frame::CallState::NotCalled;
                        continue;
                    }
                }

                // Invalid child ref => skip it (and advance)
                if (childRef.isInvalid())
                {
                    fr.nextChildIx++;
                    fr.preChildState = Frame::CallState::NotCalled;
                    continue;
                }

                // Push child frame
                Frame childFr;
                childFr.nodeRef = childRef;
                childFr.stage   = Frame::Stage::Pre;

                childFr.firstPass = true;

                childFr.preNodeState  = Frame::CallState::NotCalled;
                childFr.postNodeState = Frame::CallState::NotCalled;

                childFr.pendingPostChild = false;
                childFr.postChildState   = Frame::CallState::NotCalled;

                childFr.preChildState = Frame::CallState::NotCalled;

                stack_.push_back(childFr);

                // Mark that this child is now "the last visited child" once it completes,
                // and that we owe exactly one postChild callback when we return here.
                fr.nextChildIx++;
                fr.pendingPostChild = true;
                fr.postChildState   = Frame::CallState::NotCalled;

                // Next child index (when we get to it) should have its own fresh preChild state.
                fr.preChildState = Frame::CallState::NotCalled;

                return AstVisitResult::Continue;
            }

            fr.stage = Frame::Stage::Post;
            return AstVisitResult::Continue;
        }

        case Frame::Stage::Post:
        {
            // Post-order callback (may be called multiple times on Pause)
            if (postNodeVisitor_ && fr.postNodeState != Frame::CallState::Done)
            {
                fr.firstPass        = (fr.postNodeState == Frame::CallState::NotCalled);
                const Result result = postNodeVisitor_(*fr.node);

                if (result == Result::Error)
                    return AstVisitResult::Error;
                if (result == Result::Pause)
                {
                    fr.postNodeState = Frame::CallState::Paused;
                    return AstVisitResult::Pause;
                }

                fr.postNodeState = Frame::CallState::Done;
            }

            stack_.pop_back();
            if (stack_.empty())
                return AstVisitResult::Stop;

            return AstVisitResult::Continue;
        }
    }

    SWC_UNREACHABLE();
}

AstNode* AstVisit::parentNodeInternal(size_t up) const
{
    // stack_.back() is the current node's frame.
    // Direct parent: up = 0 -> stack_[size-2]
    if (stack_.size() <= 1) // root has no parent
        return nullptr;

    const size_t selfIdx = stack_.size() - 1; // current frame index
    if (up >= selfIdx)                        // going above root
        return nullptr;

    const Frame& fr = stack_[selfIdx - 1 - up];
    return fr.node;
}

AstNodeRef AstVisit::parentNodeRefInternal(size_t up) const
{
    // stack_.back() is the current node's frame.
    // Direct parent: up = 0 -> stack_[size-2]
    if (stack_.size() <= 1) // root has no parent
        return AstNodeRef::invalid();

    const size_t selfIdx = stack_.size() - 1; // current frame index
    if (up >= selfIdx)                        // going above root
        return AstNodeRef::invalid();

    const Frame& fr = stack_[selfIdx - 1 - up];
    return fr.nodeRef;
}

SWC_END_NAMESPACE();
