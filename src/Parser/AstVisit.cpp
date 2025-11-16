#include "pch.h"
#include "Parser/AstVisit.h"
#include "Lexer/SourceFile.h"
#include "Parser/AstNodes.h"

SWC_BEGIN_NAMESPACE()

void AstVisit::start(Ast& ast, const Callbacks& cb)
{
    ast_ = &ast;
    cb_  = cb;
    if (ast_->root().isInvalid())
        return;

    currentLex_ = &ast_->lexOut();

    Frame fr;
    fr.nodeRef      = ast_->root();
    fr.stage        = Frame::Stage::Pre;
    fr.nextChildIx  = 0;
    fr.sourceAtPush = currentLex_;
    stack_.push_back(std::move(fr));
}

bool AstVisit::step()
{
    if (stack_.empty())
        return false;

    auto& fr = stack_.back();
    switch (fr.stage)
    {
        case Frame::Stage::Pre:
        {
            SWC_ASSERT(fr.nodeRef.isValid());
            SWC_ASSERT(fr.sourceAtPush);
            fr.node = ast_->node(fr.nodeRef);
            SWC_ASSERT(fr.node->id != AstNodeId::Invalid);
            SWC_ASSERT(fr.node->id < AstNodeId::Count);

#if SWC_HAS_STATS
            Stats::get().numVisitedAstNodes.fetch_add(1);
#endif

            // Pre-order callback
            if (cb_.pre)
            {
                const Action a = cb_.pre(this, fr.node);
                if (a == Action::Stop)
                {
                    stack_.clear();
                    return false;
                }
                if (a == Action::SkipChildren)
                {
                    fr.stage = Frame::Stage::Post;
                    return true;
                }
            }

            // Collect children
            const auto& info = Ast::nodeIdInfos(fr.node->id);
            info.collectChildren(fr.children, ast_, fr.node);

            fr.stage = Frame::Stage::Children;
            return true;
        }

        case Frame::Stage::Children:
        {
            // Still have a child to descend into?
            while (fr.nextChildIx < fr.children.size())
            {
                const AstNodeRef childRef = fr.children[fr.nextChildIx++];
                if (childRef.isInvalid())
                    continue;

                Frame childFr;
                childFr.nodeRef      = childRef;
                childFr.stage        = Frame::Stage::Pre;
                childFr.nextChildIx  = 0;
                childFr.sourceAtPush = currentLex_;
                stack_.push_back(std::move(childFr));
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
                const Action a = cb_.post(this, fr.node);
                if (a == Action::Stop)
                {
                    stack_.clear();
                    return false;
                }
            }

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

void AstVisit::clear()
{
    stack_.clear();
}

SWC_END_NAMESPACE()
