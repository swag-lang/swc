// The workloads of allocbench.swg, against mimalloc (built with USE_MIMALLOC) or the C runtime heap.
// Sizes, seeds, live-set shapes and touched bytes match the Swag program exactly.
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef USE_MIMALLOC
#include "mimalloc.h"
#define ALLOC(n) mi_malloc(n)
#define FREE(p) mi_free(p)
#define REALLOC(p, n) mi_realloc(p, n)
#else
#define ALLOC(n) malloc(n)
#define FREE(p) free(p)
#define REALLOC(p, n) realloc(p, n)
#endif

#define CHURN_SLOTS 50000
#define LARGE_SLOTS 32
#define MEDIUM_SLOTS 256
#define XFER_COUNT 2000000
#define XFER_RING 4096

static uint64_t next(uint64_t* state)
{
    uint64_t x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    return x;
}

static uint64_t smallSize(uint64_t* state)
{
    uint64_t r = next(state);
    uint64_t k = r & 0xFF;
    if (k < 160)
        return 8 + ((r >> 8) & 63);
    if (k < 230)
        return 16 + ((r >> 8) & 255);
    if (k < 252)
        return 64 + ((r >> 8) & 2047);
    return 1024 + ((r >> 8) & 16383);
}

static uint64_t mediumSize(uint64_t* state) { return 4096 + next(state) % 61440; }
static uint64_t largeSize(uint64_t* state) { return 65536 + next(state) % (1024 * 1024 - 65536); }

typedef struct Node
{
    struct Node* left;
    struct Node* right;
} Node;

static Node* buildTree(int depth)
{
    Node* node  = (Node*)ALLOC(sizeof(Node));
    node->left  = depth > 0 ? buildTree(depth - 1) : NULL;
    node->right = depth > 0 ? buildTree(depth - 1) : NULL;
    return node;
}

static void freeTree(Node* node)
{
    if (node->left && node->right)
    {
        freeTree(node->left);
        freeTree(node->right);
    }
    FREE(node);
}

static void churn(uint64_t* state, uint64_t slots, uint64_t operations, uint64_t (*nextSize)(uint64_t*), int touchEveryPage)
{
    char**    addresses = (char**)ALLOC(slots * sizeof(char*));
    uint64_t* sizes     = (uint64_t*)ALLOC(slots * sizeof(uint64_t));
    for (uint64_t i = 0; i < slots; i++)
    {
        sizes[i]     = nextSize(state);
        addresses[i] = (char*)ALLOC(sizes[i]);
    }

    for (uint64_t op = 0; op < operations; op++)
    {
        uint64_t i = next(state) % slots;
        FREE(addresses[i]);
        sizes[i]                 = nextSize(state);
        volatile char* block     = (char*)ALLOC(sizes[i]);
        block[0]                 = 1;
        block[sizes[i] - 1]      = 1;
        if (touchEveryPage)
        {
            for (uint64_t page = 0; page < sizes[i] / 4096; page++)
                block[page * 4096] = 1;
        }
        addresses[i] = (char*)block;
    }

    for (uint64_t i = 0; i < slots; i++)
        FREE(addresses[i]);
    FREE(addresses);
    FREE(sizes);
}

static const uint64_t spreadSizes[12] = {16, 48, 100, 200, 500, 1000, 3000, 6000, 12000, 20000, 40000, 60000};

static uint64_t run(int workload, uint64_t seed)
{
    uint64_t state = seed;
    switch (workload)
    {
    case 0:
        for (int i = 0; i < 20000000; i++)
        {
            volatile char* block = (char*)ALLOC(32);
            block[0]             = 1;
            FREE((void*)block);
        }
        return 20000000;
    case 1:
        for (int i = 0; i < 40; i++)
            freeTree(buildTree(14));
        return 40 * (1 << 15);
    case 2:
        churn(&state, CHURN_SLOTS, 10000000, smallSize, 0);
        return 10000000;
    case 3:
        churn(&state, MEDIUM_SLOTS, 2000000, mediumSize, 0);
        return 2000000;
    case 4:
        churn(&state, LARGE_SLOTS, 200000, largeSize, 1);
        return 200000;
    case 5:
    {
        uint64_t operations = 0;
        for (int i = 0; i < 2000; i++)
        {
            uint64_t size  = 16;
            char*    block = (char*)ALLOC(size);
            while (size < 4 * 1024 * 1024)
            {
                block = (char*)REALLOC(block, size * 2);
                size *= 2;
                block[size - 1] = 1;
                operations++;
            }
            FREE(block);
        }
        return operations;
    }
    case 8:
    {
        const uint64_t count     = 4000000;
        char**         addresses = (char**)ALLOC(count * sizeof(char*));
        for (uint64_t i = 0; i < count; i++)
        {
            addresses[i]    = (char*)ALLOC(32);
            addresses[i][0] = 1;
        }
        for (uint64_t i = 0; i < count; i++)
            FREE(addresses[i]);
        FREE(addresses);
        return count * 2;
    }
    case 6:
    {
        char* addresses[120];
        for (int i = 0; i < 120; i++)
        {
            addresses[i]    = (char*)ALLOC(spreadSizes[i / 10]);
            addresses[i][0] = 1;
        }
        for (int i = 0; i < 120; i++)
            FREE(addresses[i]);
        return 120;
    }
    }
    return 0;
}

typedef struct
{
    void* volatile    slots[XFER_RING];
    volatile uint64_t head;
    volatile uint64_t tail;
} Ring;

typedef struct
{
    int      workload;
    uint64_t seed;
    uint64_t operations;
    Ring*    ring;
    int      producer;
} Job;

static Ring rings[16];

static void produce(Ring* ring, uint64_t seed)
{
    uint64_t state = seed;
    for (int i = 0; i < XFER_COUNT; i++)
    {
        char* block = (char*)ALLOC(smallSize(&state));
        block[0]    = 1;
        while (ring->head - ring->tail >= XFER_RING) {}
        ring->slots[ring->head % XFER_RING] = block;
        InterlockedExchange64((volatile LONG64*)&ring->head, ring->head + 1);
    }
}

static void consume(Ring* ring)
{
    for (int i = 0; i < XFER_COUNT; i++)
    {
        while (ring->head == ring->tail) {}
        FREE(ring->slots[ring->tail % XFER_RING]);
        InterlockedExchange64((volatile LONG64*)&ring->tail, ring->tail + 1);
    }
}

static DWORD WINAPI threadEntry(void* param)
{
    Job* job = (Job*)param;
    if (job->workload != 7)
        job->operations = run(job->workload, job->seed);
    else if (job->producer)
        produce(job->ring, job->seed);
    else
    {
        consume(job->ring);
        job->operations = XFER_COUNT;
    }
    return 0;
}

int main(int argc, char** argv)
{
    static const char* names[] = {"pair", "trees", "churn", "medium", "large", "realloc", "spread", "xfer", "grow"};
    int                workload = -1;
    for (int i = 0; i < 9; i++)
    {
        if (argc > 1 && !strcmp(argv[1], names[i]))
            workload = i;
    }

    int threads = argc > 2 ? atoi(argv[2]) : 1;
    if (workload < 0 || threads < 1 || threads > 16)
    {
        printf("usage: allocbench <pair|trees|churn|medium|large|realloc|spread|grow|xfer> [threads 1-16]\n");
        return 0;
    }

    Job    jobs[32];
    HANDLE handles[32];
    int    count = workload == 7 ? threads * 2 : threads;

    LARGE_INTEGER frequency, start, stop;
    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&start);
    for (int i = 0; i < count; i++)
    {
        jobs[i].workload   = workload;
        jobs[i].seed       = 1000 + (uint64_t)i * 7919;
        jobs[i].operations = 0;
        jobs[i].ring       = workload == 7 ? &rings[i / 2] : NULL;
        jobs[i].producer   = i % 2 == 0;
        handles[i]         = CreateThread(NULL, 0, threadEntry, &jobs[i], 0, NULL);
    }

    WaitForMultipleObjects(count, handles, TRUE, INFINITE);
    QueryPerformanceCounter(&stop);

    uint64_t operations = 0;
    for (int i = 0; i < count; i++)
        operations += jobs[i].operations;
    double ns = (double)(stop.QuadPart - start.QuadPart) * 1e9 / (double)frequency.QuadPart / (double)operations;
    printf("allocbench workload=%s threads=%d operations=%llu ns/op=%f\n", argv[1], threads, (unsigned long long)operations, ns);
    return 0;
}
