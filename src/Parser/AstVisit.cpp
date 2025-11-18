#include "pch.h"
#include "Parser/AstVisit.h"
#include "Main/Stats.h"
#include "Parser/Ast.h"
#include "Parser/AstNodes.h"

SWC_BEGIN_NAMESPACE()

void AstVisit::start(Ast& ast, AstNodeRef root)
{
    SWC_ASSERT(root.isValid());

    ast_        = &ast;
    root_       = root;
    currentLex_ = &ast_->lexOut();

    stack_.clear();
    children_.clear();

    Frame fr;
    fr.nodeRef   = root;
    fr.stage     = Frame::Stage::Pre;
    fr.lexAtPush = currentLex_;
    stack_.push_back(fr);
}

AstVisitResult AstVisit::step()
{
    if (stack_.empty())
        return AstVisitResult::Stop;

    Frame& fr = stack_.back();

    switch (fr.stage)
    {
        case Frame::Stage::Pre:
        {
            SWC_ASSERT(fr.nodeRef.isValid());

            fr.node = ast_->node(fr.nodeRef);

            SWC_ASSERT(fr.node->id != AstNodeId::Invalid);
            SWC_ASSERT(fr.node->id < AstNodeId::Count);

#if SWC_HAS_STATS
            Stats::get().numVisitedAstNodes.fetch_add(1);
#endif

            // Pre-order callback
            if (pre_)
            {
                const AstVisitStepResult result = pre_(*fr.node);
                if (result == AstVisitStepResult::Stop)
                    return AstVisitResult::Stop;
                if (result == AstVisitStepResult::Pause)
                    return AstVisitResult::Pause;

                if (result == AstVisitStepResult::SkipChildren)
                {
                    fr.stage = Frame::Stage::Post;
                    return AstVisitResult::Continue;
                }
            }

            // Collect children into shared storage
            const auto& info = Ast::nodeIdInfos(fr.node->id);

            fr.firstChildIx = static_cast<uint32_t>(children_.size());
            info.collectChildren(children_, ast_, fr.node);
            fr.numChildren = static_cast<uint32_t>(children_.size()) - fr.firstChildIx;
            fr.nextChildIx = 0;

            fr.stage = Frame::Stage::Children;
            return AstVisitResult::Continue;
        }

        case Frame::Stage::Children:
        {
            // Still have a child to descend into?
            while (fr.nextChildIx < fr.numChildren)
            {
                const AstNodeRef childRef = children_[fr.firstChildIx + fr.nextChildIx++];
                if (childRef.isInvalid())
                    continue;

                Frame childFr;
                childFr.nodeRef   = childRef;
                childFr.stage     = Frame::Stage::Pre;
                childFr.lexAtPush = currentLex_;

                stack_.push_back(childFr);
                return AstVisitResult::Continue;
            }

            fr.stage = Frame::Stage::Post;
            return AstVisitResult::Continue;
        }

        case Frame::Stage::Post:
        {
            // Post-order callback
            if (post_)
            {
                const AstVisitStepResult result = post_(*fr.node);
                if (result == AstVisitStepResult::Stop)
                    return AstVisitResult::Stop;
                if (result == AstVisitStepResult::Pause)
                    return AstVisitResult::Pause;
            }

            currentLex_ = fr.lexAtPush;
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

SWC_END_NAMESPACE()
