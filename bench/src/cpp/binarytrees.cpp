#include "common.h"

static const s32 MIN_DEPTH = 4;
static const s32 MAX_DEPTH = 12;

struct Node
{
    Node* left;
    Node* right;
};

static Node* bottomUp(s32 depth)
{
    Node* node = new Node;
    if (depth > 0)
    {
        node->left  = bottomUp(depth - 1);
        node->right = bottomUp(depth - 1);
    }
    else
    {
        node->left  = nullptr;
        node->right = nullptr;
    }
    return node;
}

static u64 check(const Node* node)
{
    if (!node->left)
        return 1;
    return 1 + check(node->left) + check(node->right);
}

static void release(Node* node)
{
    if (node->left)
    {
        release(node->left);
        release(node->right);
    }
    delete node;
}

int main()
{
    // ---- timed work (no input data) ----
    double t0 = now();

    u64 total = 0;

    Node* stretch = bottomUp(MAX_DEPTH + 1);
    total += check(stretch);
    release(stretch);

    Node* longLived = bottomUp(MAX_DEPTH);

    for (s32 d = MIN_DEPTH; d <= MAX_DEPTH; d += 2)
    {
        u64 iterations = 1ull << (MAX_DEPTH - d + MIN_DEPTH);
        for (u64 i = 0; i < iterations; i++)
        {
            Node* tree = bottomUp(d);
            total += check(tree);
            release(tree);
        }
    }

    total += check(longLived);
    release(longLived);

    double t1 = now();
    report(total, t0, t1);
    return 0;
}
