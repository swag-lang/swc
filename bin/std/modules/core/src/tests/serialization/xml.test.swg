#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

struct XmlPair
{
    x: s32
    y: s32
}

struct XmlPayload
{
    id:     u32
    active: bool
    name:   String
    counts: Array's32
    pair:   XmlPair
}

// Fields are elements in declaration order, a sequence holds blank-separated values, and text
// decodes the predefined entities.
#test
{
    let source: String = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<payload>\n  <id>7</id>\n  <active>true</active>\n  <name>a &lt;b&gt; &amp; &quot;c&apos;</name>\n  <counts> -1 0 4 </counts>\n  <pair><x>3</x><y>-2</y></pair>\n</payload>\n"

    var decoder: Serialization.Decoder'Serialization.Read.Xml
    let decoded = expect decoder.readAll'XmlPayload(source.toSlice())!
    defer Memory.delete(decoded)
    Swag.assert(decoded.id == 7)
    Swag.assert(decoded.active)
    Swag.assert(decoded.name == "a <b> & \"c'")
    Swag.assert(Slice.equals(decoded.counts.toSlice(), [-1, 0, 4]))
    Swag.assert(decoded.pair.x == 3 and decoded.pair.y == -2)
}

// A reordered element, a mismatched end tag, an unknown entity, and a bad value all fail.
#test
{
    const InvalidXml = [
        "<p><active>true</active><id>7</id><name></name><counts></counts><pair><x>0</x><y>0</y></pair></p>",
        "<p><id>7</id><active>true</active><name>n</nom><counts></counts><pair><x>0</x><y>0</y></pair></p>",
        "<p><id>7</id><active>true</active><name>&nbsp;</name><counts></counts><pair><x>0</x><y>0</y></pair></p>",
        "<p><id>-7</id><active>true</active><name></name><counts></counts><pair><x>0</x><y>0</y></pair></p>"]

    for input in InvalidXml
    {
        var decoder: Serialization.Decoder'Serialization.Read.Xml
        let decoded = catch decoder.readAll'XmlPayload(cast(const [..] u8) input) as err
        Swag.assert(decoded == null)
        Swag.assert(err != null)
    }
}
