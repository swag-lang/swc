#global private

func extract()
{
    let value = unwrap pointer
    let member = unwrap node.next
    let element = unwrap items[index]
    let called = unwrap factory()
    let result = unwrap expect load()
    let parenthesized = (unwrap pointer).member
    let sum = unwrap pointer + offset
    consume(unwrap pointer)
    pointer!.member = element
    buffer![index] = sum
    pointer![] = value
    handler!()
}
