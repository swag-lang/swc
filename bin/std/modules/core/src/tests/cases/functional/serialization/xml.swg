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

struct XmlTextPayload
{
    value: String
}

// Fields are elements in declaration order, a sequence holds blank-separated values, and text
// decodes predefined entities and XML character references.
#test
{
    let source: String = "\uFEFF<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<payload>\n  <id>7</id>\n  <active>true</active>\n  <name>a &lt;b&gt; &amp; &quot;c&apos;</name>\n  <counts> -1 0 4 </counts>\n  <pair><x>3</x><y>-2</y></pair>\n</payload>\n"

    var decoder: Serialization.Decoder'Serialization.Read.Xml
    let decoded = expect decoder.readAll'XmlPayload(source.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.id == 7)
    Swag.require(decoded.active)
    Swag.require(decoded.name == "a <b> & \"c'")
    Swag.require(Slice.equals(decoded.counts.toSlice(), [-1, 0, 4]))
    Swag.require(decoded.pair.x == 3 and decoded.pair.y == -2)
}

// A reordered element, a mismatched end tag, an unknown entity, and a bad value all fail.
#test
{
    const InvalidXml = [
        "<p><active>true</active><id>7</id><name></name><counts></counts><pair><x>0</x><y>0</y></pair></p>",
        "<p><id>7</id><active>true</active><name>n</nom><counts></counts><pair><x>0</x><y>0</y></pair></p>",
        "<p><id>7</id><active>true</active><name>&nbsp;</name><counts></counts><pair><x>0</x><y>0</y></pair></p>",
        "<p><id>-7</id><active>true</active><name></name><counts></counts><pair><x>0</x><y>0</y></pair></p>",
        "<p><id>7</id><active>true</active><name></name><counts></counts><pair><x>0</x><y>0</y></pair></p> trailing"]

    for input in InvalidXml
    {
        var decoder:    Serialization.Decoder'Serialization.Read.Xml
        var errOutcome: Swag.Error
        catch CoreTests.readAndDelete'(XmlPayload, Serialization.Read.Xml)(&decoder, cast(const [..] u8, input)) as errOutcome
        let err = errOutcome.value()
        Swag.require(err != null)
    }
}

#test
{
    let invalidXml: String = "<p>\n<id>7</id>\n<active>true</active>\n<name>x\ny&nbsp;</name><counts></counts><pair><x>0</x><y>0</y></pair></p>"
    var decoder:    Serialization.Decoder'Serialization.Read.Xml
    var errOutcome: Swag.Error
    discard catch CoreTests.readAndDelete'(XmlPayload, Serialization.Read.Xml)(&decoder, invalidXml.toSlice()) as errOutcome
    let syntax = expect cast(*SyntaxError, errOutcome.value())
    Swag.require(syntax.line == 5 and syntax.col == 3)
}

// XML input is rejected at the boundary when its bytes are not valid UTF-8.
#test
{
    let invalidXml:   [4] u8 = ['<'u8, 'p', '>', 0xFF]
    var decoder:      Serialization.Read.Xml
    var errorOutcome: Swag.Error
    catch decoder.startRead(invalidXml) as errorOutcome
    Swag.require(errorOutcome.value() is SyntaxError)
}

#test
{
    let numericEntities: String = "<p><value>&#233;&#x1F600;</value></p>"
    var decoder: Serialization.Decoder'Serialization.Read.Xml
    let decoded = expect decoder.readAll'XmlTextPayload(numericEntities.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.value == "é😀")

    const InvalidReferences = [
        "&#;", "&#x;", "&#0;", "&#1;", "&#xD800;", "&#xDFFF;", "&#x110000;", "&#999999999999999999999999;", "&#233"]
    for reference in InvalidReferences
    {
        let invalidXml = Format.toString("<p><value>[[%]]</value></p>", reference)
        var errorOutcome: Swag.Error
        catch CoreTests.readAndDelete'(XmlTextPayload, Serialization.Read.Xml)(&decoder, cast(const [..] u8, invalidXml)) as errorOutcome
        Swag.require(errorOutcome.value() is SyntaxError)
    }
}

// XML 1.0 rejects forbidden controls but permits tab, line feed, and carriage return in text.
#test
{
    let invalidXml: String = "<p><value>before\x01after</value></p>"
    var decoder:    Serialization.Decoder'Serialization.Read.Xml
    var errorOutcome: Swag.Error
    catch CoreTests.readAndDelete'(XmlTextPayload, Serialization.Read.Xml)(&decoder, invalidXml.toSlice()) as errorOutcome
    Swag.require(errorOutcome.value() is SyntaxError)

    let validXml: String = "<p><value>a\tb\nc\rd</value></p>"
    let decoded = expect decoder.readAll'XmlTextPayload(validXml.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.value.count == 7)

    let lineEndXml: String = "<p><value>a\r\nb\rc</value></p>"
    let normalized = expect decoder.readAll'XmlTextPayload(lineEndXml.toSlice())
    defer Memory.delete(normalized)
    Swag.require(normalized.value == "a\nb\nc")
}

// Numeric dispatch keeps the value width and leaves the following tag unread.
func(T) xmlAssertNative(input: string, expected: T)
{
    var reader: Serialization.Read.Xml
    expect reader.startRead(input)
    let value = expect reader.readNative'T()
    Swag.require(value == expected)
    Swag.require(reader.stream.position() == input.count - 1)
    Swag.require(reader.stream.peekU8() == '<')
}

func(T) xmlRejectsOverflow(input: string)->bool
{
    var reader: Serialization.Read.Xml
    expect reader.startRead(input)
    var outcome: Swag.Error
    discard catch reader.readNative'T() as outcome
    return outcome.value() != null
}

#test
{
    xmlAssertNative(" 1.5<", 1.5'f32)
    xmlAssertNative(" -2.5<", -2.5'f64)
    xmlAssertNative(" -7<", -7's8)
    xmlAssertNative(" -700<", -700's16)
    xmlAssertNative(" -70000<", -70000's32)
    xmlAssertNative(" -7000000000<", -7000000000's64)
    xmlAssertNative(" 250<", 250'u8)
    xmlAssertNative(" 65000<", 65000'u16)
    xmlAssertNative(" 4000000000<", 4000000000'u32)
    xmlAssertNative(" 18000000000000000000<", 18000000000000000000'u64)
}

// Numeric overflow must fail instead of returning the parser's saturated value.
#test
{
    Swag.require(xmlRejectsOverflow'u8("256<"))
    Swag.require(xmlRejectsOverflow's8("-129<"))
    Swag.require(xmlRejectsOverflow'f32("1e39<"))
    Swag.require(xmlRejectsOverflow'f32("-1e39<"))
    Swag.require(xmlRejectsOverflow'f64("1e309<"))
    Swag.require(xmlRejectsOverflow'f64("-1e309<"))
}
