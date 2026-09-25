using XpsToPdfService;

HostApplicationBuilder builder =
    Host.CreateApplicationBuilder(args);

builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "TytanXpsToPdf";
});

builder.Services.AddHostedService<Worker>();

IHost host = builder.Build();

host.Run();
