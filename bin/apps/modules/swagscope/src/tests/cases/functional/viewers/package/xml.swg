#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

#test
{
    var scan = Package.Scanner.create("<?xml version='1.0'?><root><!-- note --><x:item id='a&amp;b' href=\"a&gt;b\"/><x:text>One &#xE9; &lt; two</x:text></root>")
    var token: Package.Token
    Swag.require(scan.next(&token) and token.isElement("root") and token.kind == .Start)
    Swag.require(scan.next(&token) and token.isElement("item") and token.empty)
    Swag.require(token.attribute("id") == "a&b" and token.attribute("href") == "a>b")
    Swag.require(scan.next(&token) and token.isElement("text") and token.kind == .Start)
    Swag.require(scan.next(&token) and token.kind == .Text and token.text == "One é < two")
    Swag.require(scan.next(&token) and token.isElement("text") and token.kind == .End)
    Swag.require(scan.next(&token) and token.isElement("root") and token.kind == .End)
    Swag.require(not scan.next(&token) and not scan.damaged)
}

#test
{
    var scan = Package.Scanner.create("<p:sldId id='256' r:id='rId2'/>")
    var token: Package.Token
    Swag.require(scan.next(&token) and token.isElement("sldId"))
    Swag.require(token.attribute("id") == "256")
    Swag.require(token.attribute("r:id") == "rId2")
}

#test
{
    var scan = Package.Scanner.create("<!DOCTYPE root [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><root/>")
    var token: Package.Token
    Swag.require(not scan.next(&token) and scan.damaged)
}

#test
{
    Swag.require(Package.resolvePath("OEBPS/Text", "../Images/cover.png") == "OEBPS/Images/cover.png")
    Swag.require(Package.resolvePath("", "../outside.txt").isEmpty())
    Swag.require(Package.resolvePath("", "https://elsewhere/image.png").isEmpty())
    Swag.require(Package.resolveRelationshipTarget("xl", "/xl/worksheets/sheet1.xml") == "xl/worksheets/sheet1.xml")
    Swag.require(Package.resolveRelationshipTarget("ppt", "slides/slide1.xml") == "ppt/slides/slide1.xml")
    Swag.require(Package.resolveRelationshipTarget("ppt", "/../escape.xml").isEmpty())
}
