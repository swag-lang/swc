#include "pch.h"
#include "Parser/AstVisit.h"
#include "Lexer/SourceFile.h"
#include "Parser/AstNodes.h"

SWC_BEGIN_NAMESPACE()

void AstVisit::start(Ast& ast, const Callbacks& cb)
{
    ast_        = &ast;
    cb_         = cb;
    currentLex_ = &ast_->lexOut();

    stack_.clear();
    children_.clear();

    if (ast_->root().isInvalid())
        return;

    Frame fr;
    fr.nodeRef      = ast_->root();
    fr.stage        = Frame::Stage::Pre;
    fr.sourceAtPush = currentLex_;
    stack_.push_back(fr);
}

bool AstVisit::step()
{
    if (stack_.empty())
        return false;

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
            if (cb_.pre)
            {
                const Action result = cb_.pre(*this, fr.node);
                if (result == Action::Stop)
                    return false;

                if (result == Action::SkipChildren)
                {
                    fr.stage = Frame::Stage::Post;
                    return true;
                }
            }

            // Collect children into shared storage
            const auto& info = Ast::nodeIdInfos(fr.node->id);

            fr.firstChildIx = static_cast<uint32_t>(children_.size());
            info.collectChildren(children_, ast_, fr.node);
            fr.numChildren = static_cast<uint32_t>(children_.size()) - fr.firstChildIx;
            fr.nextChildIx = 0;

            fr.stage = Frame::Stage::Children;
            return true;
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
                childFr.nodeRef      = childRef;
                childFr.stage        = Frame::Stage::Pre;
                childFr.sourceAtPush = currentLex_;

                stack_.push_back(childFr);
                return true;
            }

            fr.stage = Frame::Stage::Post;
            return true;
        }

        case Frame::Stage::Post:
        {
            // Post-order callback
            if (cb_.post)
            {
                const Action result = cb_.post(*this, fr.node);
                if (result == Action::Stop)
                    return false;
            }

            currentLex_ = fr.sourceAtPush;
            stack_.pop_back();
            return !stack_.empty();
        }
    }

    SWC_UNREACHABLE();
}

void AstVisit::run()
{
    while (step())
    {
    }
}

AstNode* AstVisit::parentNode(size_t up) const
{
    // stack_.back() is the current node's frame.
    // Direct parent: up = 0  → stack_[size-2]
    if (stack_.size() <= 1) // root has no parent
        return nullptr;

    const size_t selfIdx = stack_.size() - 1; // current frame index
    if (up >= selfIdx)                        // going above root
        return nullptr;

    const Frame& fr = stack_[selfIdx - 1 - up];
    return fr.node;
}

SWC_END_NAMESPACE()
