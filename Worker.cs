using System.Diagnostics;
using System.Collections.Concurrent;

namespace XpsToPdfService;

public class Worker : BackgroundService
{
    private readonly string xpsFolder;
    private readonly string pdfFolder;
    private readonly string ghostXps;

    private readonly ConcurrentDictionary<string, bool> processing = new();

    public Worker(IConfiguration configuration)
    {
        xpsFolder = configuration["XpsToPdf:XpsFolder"] ?? @"C:\XPS_OUT";
        pdfFolder = configuration["XpsToPdf:PdfFolder"] ?? @"C:\PDF";
        ghostXps = configuration["XpsToPdf:GhostXpsPath"]
            ?? @"C:\Program Files\GhostXPS\gxpswin64.exe";
    }

    protected override async Task ExecuteAsync(
        CancellationToken stoppingToken)
    {
        // Only one service instance may watch and convert the XPS folder.
        // Without this guard, two processes can race over the same temporary PDF.
        using Mutex instanceMutex = new(false, "Global\\XpsToPdfService");
        try
        {
            if (!instanceMutex.WaitOne(0))
            {
                Console.Error.WriteLine("Another instance of XpsToPdfService is already running.");
                return;
            }
        }
        catch (AbandonedMutexException)
        {
            // The previous process ended unexpectedly; this instance owns the mutex.
        }

        Directory.CreateDirectory(xpsFolder);
        Directory.CreateDirectory(pdfFolder);

        using FileSystemWatcher watcher = new FileSystemWatcher();

        watcher.Path = xpsFolder;
        // The Microsoft writer can produce either classic XPS or OpenXPS.
        // Filter is broad because FileSystemWatcher accepts only one pattern;
        // the handler below performs the actual extension check.
        watcher.Filter = "*.*";

        watcher.NotifyFilter =
            NotifyFilters.FileName |
            NotifyFilters.LastWrite;

        watcher.Created += OnXpsCreated;

        watcher.EnableRaisingEvents = true;


        while (!stoppingToken.IsCancellationRequested)
        {
            await Task.Delay(1000, stoppingToken);
        }
    }

    private void OnXpsCreated(
        object sender,
        FileSystemEventArgs e)
    {
        if (!e.FullPath.EndsWith(".xps", StringComparison.OrdinalIgnoreCase) &&
            !e.FullPath.EndsWith(".oxps", StringComparison.OrdinalIgnoreCase))
            return;

        if (!processing.TryAdd(e.FullPath, true))
            return;

        _ = ConvertXpsToPdf(e.FullPath);
    }

    private async Task ConvertXpsToPdf(string xpsFile)
    {
        Stopwatch totalTimer = Stopwatch.StartNew();
        try
        {
            Console.WriteLine($"XPS detected: {xpsFile}");

            if (!File.Exists(ghostXps))
            {
                Console.Error.WriteLine($"GhostXPS was not found: {ghostXps}");
                return;
            }

            if (!await WaitForFileReadyAsync(xpsFile))
            {
                Console.Error.WriteLine($"The XPS file was not completely written: {xpsFile}");
                return;
            }

            Directory.CreateDirectory(pdfFolder);

            string pdfFile = Path.Combine(
                pdfFolder,
                Path.GetFileNameWithoutExtension(xpsFile) + ".pdf"
            );
            string temporaryPdfFile = Path.Combine(
                pdfFolder,
                Path.GetFileNameWithoutExtension(xpsFile) + ".tmp.pdf"
            );

            Console.WriteLine($"Converting: {xpsFile}");
            Console.WriteLine($"PDF destination: {pdfFile}");

            ProcessStartInfo psi = new ProcessStartInfo
            {
                FileName = ghostXps,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            psi.ArgumentList.Add("-dSAFER");
            psi.ArgumentList.Add("-dBATCH");
            psi.ArgumentList.Add("-dNOPAUSE");
            psi.ArgumentList.Add("-sDEVICE=pdfwrite");
            // GhostXPS treats '%' as an output-file pattern marker. Escape it
            // for the command-line argument so names such as "%_2026_..."
            // remain literal filenames on disk.
            string ghostOutputFile = temporaryPdfFile.Replace("%", "%%");
            psi.ArgumentList.Add($"-sOutputFile={ghostOutputFile}");
            psi.ArgumentList.Add(xpsFile);

            using Process process = new Process
            {
                StartInfo = psi
            };

            process.Start();

            string output =
                await process.StandardOutput.ReadToEndAsync();

            string error =
                await process.StandardError.ReadToEndAsync();

            await process.WaitForExitAsync();

            Console.WriteLine($"GhostXPS exited with code: {process.ExitCode}");
            if (!string.IsNullOrWhiteSpace(output))
                Console.WriteLine(output);
            if (!string.IsNullOrWhiteSpace(error))
                Console.Error.WriteLine(error);

            if (process.ExitCode != 0)
            {
                Console.Error.WriteLine(
                    $"PDF was not published because GhostXPS exited with code {process.ExitCode}."
                );
                return;
            }

            if (!File.Exists(temporaryPdfFile))
            {
                Console.Error.WriteLine(
                    $"GhostXPS exited with code 0 but did not create the temporary file: {temporaryPdfFile}"
                );
                return;
            }

            File.Move(temporaryPdfFile, pdfFile, true);
            Console.WriteLine($"PDF created: {pdfFile}");

        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error: {ex.Message}");
        }
        finally
        {
            if (totalTimer.IsRunning)
                totalTimer.Stop();

            Console.WriteLine(
                $"XPS job time: {totalTimer.Elapsed.TotalSeconds:F2} s | {xpsFile}"
            );
            processing.TryRemove(xpsFile, out _);
        }
    }

    private static async Task<bool> WaitForFileReadyAsync(string filePath)
    {
        // Keep enough retries for slower XPS jobs while polling more often.
        const int maxAttempts = 60;
        // Two quick checks balance startup latency with protection against
        // reading an XPS while the writer is still closing it.
        const int stableChecksRequired = 2;
        long previousLength = -1;
        DateTime previousWriteTime = DateTime.MinValue;
        int stableChecks = 0;

        for (int attempt = 0; attempt < maxAttempts; attempt++)
        {
            try
            {
                FileInfo file = new(filePath);
                file.Refresh();

                if (!file.Exists || file.Length == 0)
                    throw new IOException("The file does not exist yet or is empty.");

                // FileShare.None confirms that the writer has closed the XPS.
                using FileStream stream = new(filePath, FileMode.Open, FileAccess.Read, FileShare.None);

                if (file.Length == previousLength && file.LastWriteTimeUtc == previousWriteTime)
                    stableChecks++;
                else
                    stableChecks = 1;

                if (stableChecks >= stableChecksRequired)
                    return true;

                previousLength = file.Length;
                previousWriteTime = file.LastWriteTimeUtc;
            }
            catch (IOException)
            {
                stableChecks = 0;
            }

            await Task.Delay(TimeSpan.FromMilliseconds(100));
        }

        return false;
    }
}
