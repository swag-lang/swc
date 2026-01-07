#include "pch.h"
#include "Parser/AstVisit.h"
#include "Main/Stats.h"
#include "Parser/Ast.h"
#include "Parser/AstNodes.h"

SWC_BEGIN_NAMESPACE()

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
    stack_.push_back(fr);
}

AstVisitResult AstVisit::step(const TaskContext& ctx)
{
    if (stack_.empty())
        return AstVisitResult::Stop;

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

            // Pre-order callback
            if (preNodeVisitor_)
            {
                const Result result = preNodeVisitor_(*fr.node);
                fr.firstPass        = false;

                if (result == Result::Stop)
                    return AstVisitResult::Stop;
                if (result == Result::Pause)
                    return AstVisitResult::Pause;

                if (result == Result::SkipChildren)
                {
                    fr.stage     = Frame::Stage::Post;
                    fr.firstPass = true;
                    return AstVisitResult::Continue;
                }
            }

            const auto& info = Ast::nodeIdInfos(fr.node->id());
            fr.firstChildIx  = children_.size32();
            info.collectChildren(children_, *ast_, *fr.node);
            fr.numChildren = children_.size32() - fr.firstChildIx;
            fr.nextChildIx = 0;

            fr.stage     = Frame::Stage::Children;
            fr.firstPass = true;
            return AstVisitResult::Continue;
        }

        case Frame::Stage::Children:
        {
            while (true)
            {
                if (fr.firstPass && fr.nextChildIx > 0)
                {
                    if (postChildVisitor_)
                    {
                        AstNodeRef   lastChildRef = children_[fr.firstChildIx + fr.nextChildIx - 1];
                        const Result result       = postChildVisitor_(*fr.node, lastChildRef);
                        if (result == Result::Stop)
                            return AstVisitResult::Stop;
                        if (result == Result::Pause)
                            return AstVisitResult::Pause;
                    }

                    fr.firstPass = false;
                }

                if (fr.nextChildIx >= fr.numChildren)
                    break;

                const uint32_t localIdx = fr.nextChildIx;
                const uint32_t globalIx = fr.firstChildIx + localIdx;

                AstNodeRef childRef = children_[globalIx];
                if (preChildVisitor_)
                {
                    const Result result = preChildVisitor_(*fr.node, childRef);
                    fr.firstPass        = false;

                    if (result == Result::Stop)
                        return AstVisitResult::Stop;
                    if (result == Result::Pause)
                        return AstVisitResult::Pause;
                    if (result == Result::SkipChildren)
                    {
                        fr.nextChildIx++;
                        fr.firstPass = true;
                        continue;
                    }
                }

                if (childRef.isInvalid())
                {
                    fr.nextChildIx++;
                    fr.firstPass = true;
                    continue;
                }

                Frame childFr;
                childFr.nodeRef = childRef;
                childFr.stage   = Frame::Stage::Pre;

                stack_.push_back(childFr);
                fr.nextChildIx++;
                fr.firstPass = true;
                return AstVisitResult::Continue;
            }

            fr.stage     = Frame::Stage::Post;
            fr.firstPass = true;
            return AstVisitResult::Continue;
        }

        case Frame::Stage::Post:
        {
            // Post-order callback
            if (postNodeVisitor_)
            {
                const Result result = postNodeVisitor_(*fr.node);
                fr.firstPass        = false;

                if (result == Result::Stop)
                    return AstVisitResult::Stop;
                if (result == Result::Pause)
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
