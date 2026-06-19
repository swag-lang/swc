#global public

using UsingDeclForwardProperties

struct UsingDeclForwardOptions
{
    enabled: bool
}

func semaTest001()
{
    var app: UsingDeclForwardApplication
    app.options.enabled = true
}
