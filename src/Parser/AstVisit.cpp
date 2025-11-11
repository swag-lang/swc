#include "pch.h"
#include "Parser/AstVisit.h"
#include "Lexer/SourceFile.h"
#include "Parser/AstNodes.h"

SWC_BEGIN_NAMESPACE()

void AstVisit::start(AstVisitContext& ctx, const AstNode* root, SourceFile* rootFile)
{
    if (!root)
        return;
    if (!ctx.currentSource)
        ctx.currentSource = rootFile;

    AstVisitContext::Frame fr;
    fr.node         = root;
    fr.stage        = AstVisitContext::Frame::Stage::Pre;
    fr.nextChildIx  = 0;
    fr.sourceAtPush = ctx.currentSource;
    ctx.stack.push_back(std::move(fr));
}

bool AstVisit::step(AstVisitContext& ctx) const
{
    if (ctx.stack.empty())
        return false;

    auto& fr = ctx.stack.back();
    switch (fr.stage)
    {
        case AstVisitContext::Frame::Stage::Pre:
        {
            // Pre-order callback (can modify ctx.currentSource)
            if (cb_.pre)
            {
                const Action a = cb_.pre(ctx, fr.node);
                if (a == Action::Stop)
                {
                    ctx.stack.clear();
                    return false;
                }
                if (a == Action::SkipChildren)
                {
                    fr.stage = AstVisitContext::Frame::Stage::Post;
                    return true; // made progress
                }
            }

            // Collect children once, resolved with the *current* source
            collectResolvedChildren(ctx, fr);

            // Move to children stage
            fr.stage = AstVisitContext::Frame::Stage::Children;
            return true; // progress
        }

        case AstVisitContext::Frame::Stage::Children:
        {
            // Still have a child to descend into?
            if (fr.nextChildIx < fr.children.size())
            {
                const AstNode* child = fr.children[fr.nextChildIx++];
                if (child)
                {
                    AstVisitContext::Frame childFr;
                    childFr.node         = child;
                    childFr.stage        = AstVisitContext::Frame::Stage::Pre;
                    childFr.nextChildIx  = 0;
                    childFr.sourceAtPush = ctx.currentSource; // inherit scope now
                    ctx.stack.push_back(std::move(childFr));
                    return true;
                }

                // If child is nullptr just continue to the next one
                return true;
            }

            // No more children -> go to post
            fr.stage = AstVisitContext::Frame::Stage::Post;
            return true;
        }

        case AstVisitContext::Frame::Stage::Post:
        {
            // Post-order callback (can modify ctx.currentSource)
            if (cb_.post)
            {
                const Action a = cb_.post(ctx, fr.node);
                if (a == Action::Stop)
                {
                    ctx.stack.clear();
                    return false;
                }
            }

            // Pop this frame
            ctx.stack.pop_back();
            return !ctx.stack.empty(); // progress (and tell caller if more remains)
        }
    }

    // Shouldn't get here
    return false;
}

void AstVisit::run(AstVisitContext& ctx) const
{
    while (step(ctx))
    {
    }
}

void AstVisit::collectResolvedChildren(const AstVisitContext& ctx, AstVisitContext::Frame& fr)
{
    fr.children.clear();

    // Gather raw AstNodeRef children with your generator-provided function
    SmallVector<AstNodeRef, 16> childRefs;
    collectChildRefs(fr.node, childRefs);

    // Resolve them with the current SourceFile *
    for (auto r : childRefs)
    {
        if (r.isInvalid())
            continue;
        const auto cn = ctx.currentSource->parserOut().ast().node(r);
        fr.children.push_back(cn);
    }
}

void AstVisit::collectChildRefs(const AstNode* node, SmallVector<AstNodeRef, 16>& out)
{
    // We assume AstNode exposes its id as 'nodeId' (adapt if your name differs)
    const auto id = node->id;

    // Index into the constexpr table; if your enum isn't 0-based/contiguous,
    // adapt with a mapping function.
    const size_t idx  = static_cast<size_t>(id);
    const auto&  info = AST_NODE_ID_INFOS[idx];

    // Call the type-erased collector: it will invoke node->collectChildren(out)
    info.collect(node, out);
}

SWC_END_NAMESPACE()
