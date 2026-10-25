#global private

#test
{
    let tupleType   = #typeof((1, 2))
    let recordType  = #typeof({x: 1, y: 2})
    var value: {x: s32, y: s32}
    let typedRecord = #typeof(value)
    Swag.assert(tupleType.flags & .Tuple)
    Swag.assert(not (tupleType.flags & .Record))
    Swag.assert(recordType.flags & .Record)
    Swag.assert(not (recordType.flags & .Tuple))
    Swag.assert(typedRecord.flags & .Record)
    Swag.assert(not Swag.typeCmp(tupleType, recordType, .Strict))
    Swag.assert(not Swag.typeCmp(#typeof({x: 1's64}), #typeof({x: 1, y: 2}), .Strict))
    let padded = #typeof({x: 1's32, y: 2's16})
    let full = #typeof({x: 1's32, y: 2's16, z: 3's16})
    Swag.assert(not Swag.typeCmp(full, padded, .Strict))
    Swag.assert(not Swag.typeCmp(padded, full, .Strict))
}
