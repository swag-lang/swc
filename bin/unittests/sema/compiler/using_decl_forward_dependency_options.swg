#global public

using UsingDeclForwardProperties

struct UsingDeclForwardOptions
{
    public enabled: bool
}

func semaTest001()
{
    var app: UsingDeclForwardApplication
    app.options.enabled = true
}
