using System.Diagnostics;
using System.Collections.Concurrent;

namespace XpsToPdfService;

public class Worker : BackgroundService
{
    private const string XpsFolder = @"C:\XPS_OUT";
    private const string PdfFolder = @"C:\PDF";

    // GhostXPS is the XPS interpreter. Ghostscript (gswin64c.exe) alone is
    // not the executable that should receive an .xps file.
    private const string GhostXps =
        @"C:\Users\Ibai\Downloads\ghostxps-10.08.0-win64\ghostxps-10.08.0-win64\gxpswin64.exe";

    private readonly ConcurrentDictionary<string, bool> processing = new();

    protected override async Task ExecuteAsync(
        CancellationToken stoppingToken)
    {
        using FileSystemWatcher watcher = new FileSystemWatcher();

        watcher.Path = XpsFolder;
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
            Console.WriteLine($"XPS detectado: {xpsFile}");

            if (!File.Exists(GhostXps))
            {
                Console.Error.WriteLine($"No se encuentra GhostXPS: {GhostXps}");
                return;
            }

            if (!await WaitForFileReadyAsync(xpsFile))
            {
                Console.Error.WriteLine($"El XPS no terminó de escribirse: {xpsFile}");
                return;
            }

            Directory.CreateDirectory(PdfFolder);

            string pdfFile = Path.Combine(
                PdfFolder,
                Path.GetFileNameWithoutExtension(xpsFile) + ".pdf"
            );
            string temporaryPdfFile = Path.Combine(
                PdfFolder,
                Path.GetFileNameWithoutExtension(xpsFile) + ".tmp.pdf"
            );

            Console.WriteLine($"Convirtiendo: {xpsFile}");
            Console.WriteLine($"PDF destino: {pdfFile}");

            ProcessStartInfo psi = new ProcessStartInfo
            {
                FileName = GhostXps,
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

            Console.WriteLine($"GhostXPS terminó con código: {process.ExitCode}");
            if (!string.IsNullOrWhiteSpace(output))
                Console.WriteLine(output);
            if (!string.IsNullOrWhiteSpace(error))
                Console.Error.WriteLine(error);

            if (process.ExitCode != 0)
            {
                Console.Error.WriteLine(
                    $"No se publicó el PDF porque GhostXPS terminó con código {process.ExitCode}."
                );
                return;
            }

            if (!File.Exists(temporaryPdfFile))
            {
                Console.Error.WriteLine(
                    $"GhostXPS terminó con código 0, pero no creó el archivo temporal: {temporaryPdfFile}"
                );
                return;
            }

            File.Move(temporaryPdfFile, pdfFile, true);
            Console.WriteLine($"PDF creado: {pdfFile}");

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
                $"Tiempo del trabajo XPS: {totalTimer.Elapsed.TotalSeconds:F2} s | {xpsFile}"
            );
            processing.TryRemove(xpsFile, out _);
        }
    }

    private static async Task<bool> WaitForFileReadyAsync(string filePath)
    {
        const int maxAttempts = 30;
        // Two stable checks are enough once the writer has released the file.
        // The shorter interval avoids adding several seconds to every job.
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
                    throw new IOException("El archivo aún no existe o está vacío.");

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

            await Task.Delay(TimeSpan.FromMilliseconds(300));
        }

        return false;
    }
}
