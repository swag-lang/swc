#global export
using Swag

// Represents a single node in a doubly-linked 'List'.
struct(T) ListEntry
{
    prev:      #null *ListEntry     // Pointer to the previous node in the list.
    next:      #null *ListEntry     // Pointer to the next node in the list.
    value:     T              // The value stored in the node.
}

// A generic, doubly-linked list.
// Provides efficient insertion and deletion of elements.
struct(T) List
{
    head:      #null *ListEntry     // Pointer to the first node in the list.
    tail:      #null *ListEntry     // Pointer to the last node in the list.
    count:     u64            // The total number of elements in the list.
}

impl List
{
    mtd opPostCopy()
    {
        if .head == null do
            return

        let oldHead = .head
        .head, .tail = null
        .count = 0

        var n = oldHead
        while n
        {
            discard .addBack(n.value)
            n = n.next
        }
    }

    // Ensures all nodes are deallocated when the list goes out of scope.
    mtd opDrop()
    {
        .clear()
    }

    // Provides a way to iterate over each element in the list.
    // This is a macro that accepts a code block to execute for each element.
    // Visiting by pointer and in reverse order is supported.
    // Block parameters:
    // - 'item':  The value of the element (or a pointer to it).
    // - 'node':  A pointer to the list node ('ListEntry').
    // - 'index': The index of the element.
    #[Macro]
    mtd(ptr: bool, back: bool) opVisit(stmt: #code(item, node, index: u64))
    {
        #if back do
            var n = .tail
            #else do
            var n = .head
        var ordinal: u64 = 0
        #scope(Up)
            while n
        {
            let node = n orelse cast(*ListEntry'(T)) 1'u64
            #scope(Down)
            {
                #if ptr do
                    #inject(stmt, item = cast(&T) &node.value, node = node, index = ordinal, break = break to Up, continue = break to Down)
                    #elif Reflection.isStruct(T) do
                    #inject(stmt, item = cast(const &T) &node.value, node = node, index = ordinal, break = break to Up, continue = break to Down)
                    #else do
                    #inject(stmt, item = node.value, node = node, index = ordinal, break = break to Up, continue = break to Down)
            }

            #if back do
                n = node.prev
                #else do
                n = node.next
            ordinal += 1
        }
    }

    // Removes and deallocates all elements from the list.
    mtd clear()
    {
        var n = .head
        while n
        {
            let next = n.next
            Memory.delete(n)
            n = next
        }

        .head, .tail = null
        .count = 0
    }

    // Adds a new element to the front of the list.
    // The value is copied; pass it with '#move' to move it instead.
    // Returns a pointer to the newly created list node.
    #[Discardable]
    mtd addFront(value: #fwd T)->*ListEntry
    {
        let n = Memory.new'ListEntry()
        n.value = #fwd value
        .count += 1

        if .head
        {
            n.next = .head
            .head.prev, .head = n
        }
        else
        {
            .head, .tail = n
        }

        return n
    }

    // Adds a new element to the back of the list.
    // The value is copied; pass it with '#move' to move it instead.
    // Returns a pointer to the newly created list node.
    #[Discardable]
    mtd addBack(value: #fwd T)->*ListEntry
    {
        let n = Memory.new'ListEntry()
        n.value = #fwd value
        .count += 1

        if .tail
        {
            n.prev = .tail
            .tail.next, .tail = n
        }
        else
        {
            .head, .tail = n
        }

        return n
    }

    // Inserts a new element before a specified node.
    // The value is copied; pass it with '#move' to move it instead.
    // Returns a pointer to the newly created list node.
    #[Discardable]
    mtd insertBefore(node: *ListEntry, value: #fwd T)->*ListEntry
    {
        let n = Memory.new'ListEntry()
        n.value = #fwd value
        .count += 1

        n.next = node
        n.prev = node.prev
        if !n.prev do
            .head = n
        else do
            n.prev.next = n
        node.prev = n
        return n
    }

    // Inserts a new element after a specified node.
    // The value is copied; pass it with '#move' to move it instead.
    // Returns a pointer to the newly created list node.
    #[Discardable]
    mtd insertAfter(node: *ListEntry, value: #fwd T)->*ListEntry
    {
        let n = Memory.new'ListEntry()
        n.value = #fwd value
        .count += 1

        n.prev = node
        n.next = node.next
        if !n.next do
            .tail = n
        else do
            n.next.prev = n
        node.next = n
        return n
    }
}
