#global if #command == Swag.CompilerCommand.Test
#global private

var borrowedCopies: u32

struct BorrowedCopyProbe
{
    value:   u64
    padding: u64
}

impl BorrowedCopyProbe
{
    mtd opPostCopy() { borrowedCopies += 1 }
}

// Borrowed insertion performs the one requested element copy, including when storage moves.
#test
{
    var values: Array'BorrowedCopyProbe
    values.add({7, 11})
    Swag.assert(values.count == values.capacity)
    borrowedCopies = 0
    values.addBorrowed(&values[0])
    Swag.assert(borrowedCopies == 1 and values.count == 2)
    Swag.assert(values[0].value == 7 and values[1].padding == 11)

    values.reserve(8)
    borrowedCopies = 0
    values.addBorrowed(&values[0])
    Swag.assert(borrowedCopies == 1)
    borrowedCopies = 0
    values.insertBorrowedAt(0, &values[2])
    Swag.assert(borrowedCopies == 1 and values[0].value == 7)
    borrowedCopies = 0
    values.insertBorrowedAt(values.count, &values[0])
    Swag.assert(borrowedCopies == 1)

    var fixed: StaticArray'(BorrowedCopyProbe, 8)
    fixed.add({17, 19})
    borrowedCopies = 0
    fixed.insertBorrowedAt(0, &fixed[0])
    Swag.assert(borrowedCopies == 1 and fixed[0].value == 17 and fixed[1].padding == 19)
    borrowedCopies = 0
    fixed.insertBorrowedAt(fixed.count, &fixed[0])
    Swag.assert(borrowedCopies == 1)

    var table: HashTable'(u64, BorrowedCopyProbe)
    table.add(1, {23, 29})
    let key = 2'u64
    borrowedCopies = 0
    table.addBorrowed(&key, &table.find(1).value)
    Swag.assert(borrowedCopies == 1 and table.find(2).value.padding == 29)
    let existing = table.find(1)
    borrowedCopies = 0
    table.addBorrowed(&existing.key, &existing.value)
    Swag.assert(borrowedCopies == 0 and table.count == 2)

    // Fill to the growth threshold, then borrow across rehashing.
    for index in 14'u64 do
        table.add(index + 3, BorrowedCopyProbe{index, index})
    let growKey = 20'u64
    borrowedCopies = 0
    table.addBorrowed(&growKey, &table.find(1).value)
    Swag.assert(borrowedCopies == 1 and table.find(20).value.value == 23)
}

#test
{
    var values: Array'String
    values.add("one")
    values.addOnceBorrowed(&values[0])
    Swag.assert(values.count == 1)
    let external = String.from("two")
    values.addOnceBorrowed(&external)
    Swag.assert(values.count == 2 and values[1] == "two")
}

// Pointer-valued elements keep their existing overload behavior.
#test
{
    var number = 31
    var values: Array'(*s32)
    values.add(&number)
    values.addBorrowed(&values[0])
    Swag.assert(values.count == 2 and values[0] == &number and values[1] == &number)

    var table: HashTable'(u64, *s32)
    table.add(1, &number)
    let key = 2'u64
    table.addBorrowed(&key, &table.find(1).value)
    Swag.assert(table.find(2).value == &number)
}
