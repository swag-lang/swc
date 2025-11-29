#include "pch.h"
#include "Parser/AstVisit.h"
#include "Main/Stats.h"
#include "Parser/Ast.h"
#include "Parser/AstNodes.h"

SWC_BEGIN_NAMESPACE()

void AstVisit::start(Ast& ast, AstNodeRef root)
{
    SWC_ASSERT(root.isValid());

    ast_  = &ast;
    rootRef_ = root;

    stack_.clear();
    children_.clear();

    Frame fr;
    fr.nodeRef = root;
    fr.stage   = Frame::Stage::Pre;
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

            fr.node = &ast_->node(fr.nodeRef);

            SWC_ASSERT(fr.node->isNot(AstNodeId::Invalid));
            SWC_ASSERT(fr.node->id() < AstNodeId::Count);

#if SWC_HAS_STATS
            Stats::get().numVisitedAstNodes.fetch_add(1);
#endif

            // Pre-order callback
            if (preNodeVisitor_)
            {
                const AstVisitStepResult result = preNodeVisitor_(*fr.node);
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

            const auto& info = Ast::nodeIdInfos(fr.node->id());
            fr.firstChildIx  = children_.size32();
            info.collectChildren(children_, *ast_, *fr.node);
            fr.numChildren = children_.size32() - fr.firstChildIx;
            fr.nextChildIx = 0;

            fr.stage = Frame::Stage::Children;
            return AstVisitResult::Continue;
        }

        case Frame::Stage::Children:
        {
            // Still have a child to descend into?
            while (fr.nextChildIx < fr.numChildren)
            {
                const uint32_t localIdx = fr.nextChildIx;
                const uint32_t globalIx = fr.firstChildIx + localIdx;

                AstNodeRef childRef = children_[globalIx];
                if (preChildVisitor_)
                {
                    const AstVisitStepResult result = preChildVisitor_(*fr.node, childRef);
                    if (result == AstVisitStepResult::Stop)
                        return AstVisitResult::Stop;
                    if (result == AstVisitStepResult::Pause)
                        return AstVisitResult::Pause;
                    if (result == AstVisitStepResult::SkipChildren)
                    {
                        fr.nextChildIx++;
                        continue;
                    }
                }

                if (childRef.isInvalid())
                {
                    fr.nextChildIx++;
                    continue;
                }

                Frame childFr;
                childFr.nodeRef = childRef;
                childFr.stage   = Frame::Stage::Pre;

                stack_.push_back(childFr);
                fr.nextChildIx++;
                return AstVisitResult::Continue;
            }

            fr.stage = Frame::Stage::Post;
            return AstVisitResult::Continue;
        }

        case Frame::Stage::Post:
        {
            // Post-order callback
            if (postNodeVisitor_)
            {
                const AstVisitStepResult result = postNodeVisitor_(*fr.node);
                if (result == AstVisitStepResult::Stop)
                    return AstVisitResult::Stop;
                if (result == AstVisitStepResult::Pause)
                    return AstVisitResult::Pause;
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

SWC_END_NAMESPACE()
