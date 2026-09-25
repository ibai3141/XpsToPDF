using System.Diagnostics;
using System.Collections.Concurrent;
using System.Text;

namespace XpsToPdfService;

public class Worker : BackgroundService
{
    private readonly string xpsFolder;
    private readonly string pdfFolder;
    private readonly string ghostXps;

    private readonly ConcurrentDictionary<string, bool> processing = new();
    private readonly object logLock = new();

    private string ServiceLogPath => Path.Combine(xpsFolder, "xpstoservice.log");

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
                LogError("Another instance of XpsToPdfService is already running.");
                return;
            }
        }
        catch (AbandonedMutexException)
        {
            // The previous process ended unexpectedly; this instance owns the mutex.
        }

        Directory.CreateDirectory(xpsFolder);
        Directory.CreateDirectory(pdfFolder);

        LogInfo($"Service started. XPS input folder: {xpsFolder}");
        LogInfo($"PDF output folder: {pdfFolder}");
        LogInfo($"GhostXPS executable: {ghostXps}");

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

        // Recover files that were created before the service started or while
        // the FileSystemWatcher was unavailable.
        foreach (string existingFile in Directory.EnumerateFiles(xpsFolder, "*.*"))
        {
            QueueXps(existingFile);
        }


        while (!stoppingToken.IsCancellationRequested)
        {
            await Task.Delay(1000, stoppingToken);
        }
    }

    private void OnXpsCreated(
        object sender,
        FileSystemEventArgs e)
    {
        QueueXps(e.FullPath);
    }

    private void QueueXps(string filePath)
    {
        if (!filePath.EndsWith(".xps", StringComparison.OrdinalIgnoreCase) &&
            !filePath.EndsWith(".oxps", StringComparison.OrdinalIgnoreCase))
            return;

        if (!processing.TryAdd(filePath, true))
            return;

        _ = ConvertXpsToPdf(filePath);
    }

    private async Task ConvertXpsToPdf(string xpsFile)
    {
        Stopwatch totalTimer = Stopwatch.StartNew();
        try
        {
            LogInfo($"XPS detected: {xpsFile}");

            if (!File.Exists(ghostXps))
            {
                LogError($"PDF not created. GhostXPS was not found: {ghostXps}");
                return;
            }

            if (!await WaitForFileReadyAsync(xpsFile))
            {
                LogError($"PDF not created. The XPS file was not completely written: {xpsFile}");
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

            LogInfo($"Converting: {xpsFile}");
            LogInfo($"PDF destination: {pdfFile}");

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

            LogInfo($"GhostXPS exited with code: {process.ExitCode}");
            if (!string.IsNullOrWhiteSpace(output))
                LogInfo($"GhostXPS output: {output.Trim()}");
            if (!string.IsNullOrWhiteSpace(error))
                LogError($"GhostXPS error: {error.Trim()}");

            if (process.ExitCode != 0)
            {
                LogError($"PDF not created. GhostXPS exited with code {process.ExitCode}. Expected output: {pdfFile}");
                return;
            }

            if (!File.Exists(temporaryPdfFile))
            {
                LogError($"PDF not created. GhostXPS exited with code 0 but did not create the temporary file: {temporaryPdfFile}. Expected output: {pdfFile}");
                return;
            }

            File.Move(temporaryPdfFile, pdfFile, true);
            LogInfo($"PDF created: {pdfFile}");

        }
        catch (Exception ex)
        {
            LogError($"PDF not created for XPS '{xpsFile}': {ex.Message}");
        }
        finally
        {
            if (totalTimer.IsRunning)
                totalTimer.Stop();

            LogInfo($"XPS job time: {totalTimer.Elapsed.TotalSeconds:F2} s | {xpsFile}");
            processing.TryRemove(xpsFile, out _);
        }
    }

    private void LogInfo(string message) => WriteLog(message, isError: false);

    private void LogError(string message) => WriteLog(message, isError: true);

    private void WriteLog(string message, bool isError)
    {
        string line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {message}";

        if (isError)
            Console.Error.WriteLine(line);
        else
            Console.WriteLine(line);

        // The Windows service normally has no visible console. Keep a plain
        // UTF-8 log beside the XPS files so support can verify every output.
        try
        {
            Directory.CreateDirectory(xpsFolder);
            lock (logLock)
            {
                File.AppendAllText(ServiceLogPath, line + Environment.NewLine, Encoding.UTF8);
            }
        }
        catch
        {
            // Logging must never stop XPS conversion if the log file is locked.
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
