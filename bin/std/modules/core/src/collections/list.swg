#global export

using Swag

// A node of a doubly linked [[Core.List]], holding one value.
struct(T) ListEntry
{
    public readonly
    {
        prev: *ListEntry?     // Pointer to the previous node in the list.
        next: *ListEntry?     // Pointer to the next node in the list.
    }

    public value: T     // The value stored in the node.
}

// A doubly linked list that owns its nodes and their values.
//
// Insertion and removal at a known node take constant time, and a node stays at the same address
// until it is removed, so node pointers survive changes to the rest of the list.
struct(T) List
{
    public readonly
    {
        head:  *ListEntry?     // Pointer to the first node in the list.
        tail:  *ListEntry?     // Pointer to the last node in the list.
        count: u64             // The total number of elements in the list.
    }
}

// Iterates a borrowed list from its tail to its head.
#[Swag.Opaque]
struct(T) ReversedList
{
    source: const *List'T
}

impl ReversedList
{
    // Visits borrowed list elements from tail to head, with a zero-based traversal index.
    #[Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item, node, index: u64))
    {
        var node = .source.tail
        var index: u64
        #scope(Up)
        while node
        {
            let current = node orelse cast(*ListEntry'T) 1'u64
            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, item = cast(*T) &current.value, node = current, index = index, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(T) do
                    #inject(stmt, item = cast(const *T) &current.value, node = current, index = index, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, item = current.value, node = current, index = index, break = break to Up, continue = break to Down)
            }

            node  = current.prev
            index += 1
        }
    }
}

impl List
{
    // Returns the number of elements in the list.
    #[Swag.Inline]
    mtd const opCount()->u64 => .count

    // Returns whether the list contains no elements.
    #[Swag.Inline]
    mtd const isEmpty()->bool => .count == 0

    // Copies the nodes into independently owned storage while preserving their order.
    mtd opPostCopy()
    {
        if not .head do
            return

        let oldHead = .head
        .head, .tail = null
        .count       = 0

        var n = oldHead
        while n
        {
            discard .addBack(n.value)
            n = n.next
        }
    }

    // Deletes every node.
    mtd opDrop()
    {
        .clear()
    }

    // Visits every element from head to tail.
    //
    // The visited code receives:
    // - `item`, the value, or a pointer to it when visiting by address or when it is a struct.
    // - `node`, the address of the [[Core.ListEntry]] holding it.
    // - `index`, its zero-based position.
    #[Macro]
    mtd(ptr: bool) opVisit(stmt: #code(item, node, index: u64))
    {
        var n = .head
        var ordinal: u64 = 0
        #scope(Up)
        while n
        {
            let node = n orelse cast(*ListEntry'(T)) 1'u64
            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, item = cast(*T) &node.value, node = node, index = ordinal, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(T) do
                    #inject(stmt, item = cast(const *T) &node.value, node = node, index = ordinal, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, item = node.value, node = node, index = ordinal, break = break to Up, continue = break to Down)
            }

            n       = node.next
            ordinal += 1
        }
    }

    // Returns an immutable zero-allocation view that traverses the list from tail to head.
    mtd const reversed()->ReversedList'T => {source: me}

    // Deletes every node and leaves the list empty.
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
        .count       = 0
    }

    // Unlinks and deletes `node`, which must belong to this list.
    mtd remove(node: *ListEntry)
    {
        if node.prev do
            node.prev.next = node.next
        else do
            .head = node.next

        if node.next do
            node.next.prev = node.prev
        else do
            .tail = node.prev

        .count -= 1
        Memory.delete(node)
    }

    // Adds `value` in a new node at the head of the list and returns that node.
    //
    // The value is copied; pass it with `#move` to move it instead.
    #[Discardable]
    mtd addFront(value: #fwd T)->*ListEntry
    {
        let n = Memory.new'ListEntry()
        n.value = #fwd value
        .count  += 1

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

    // Adds `value` in a new node at the tail of the list and returns that node.
    //
    // The value is copied; pass it with `#move` to move it instead.
    #[Discardable]
    mtd addBack(value: #fwd T)->*ListEntry
    {
        let n = Memory.new'ListEntry()
        n.value = #fwd value
        .count  += 1

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

    // Inserts `value` in a new node before `node` and returns the new node.
    //
    // `node` must belong to this list. The value is copied; pass it with `#move` to move it instead.
    #[Discardable]
    mtd insertBefore(node: *ListEntry, value: #fwd T)->*ListEntry
    {
        let n = Memory.new'ListEntry()
        n.value = #fwd value
        .count  += 1

        n.next = node
        n.prev = node.prev
        if not n.prev do
            .head = n
        else do
            n.prev.next = n
        node.prev = n
        return n
    }

    // Inserts `value` in a new node after `node` and returns the new node.
    //
    // `node` must belong to this list. The value is copied; pass it with `#move` to move it instead.
    #[Discardable]
    mtd insertAfter(node: *ListEntry, value: #fwd T)->*ListEntry
    {
        let n = Memory.new'ListEntry()
        n.value = #fwd value
        .count  += 1

        n.prev = node
        n.next = node.next
        if not n.next do
            .tail = n
        else do
            n.next.prev = n
        node.next = n
        return n
    }
}
