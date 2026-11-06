using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

// Steam launch options: "<this folder>\Civ6-Start.exe" %command%
// Wait for the same-directory helper before running Steam's exact game command.
// Helper failure falls back to the base game; this does not guarantee online access.
internal static class Civ6Start
{
    private static void Log(string message)
    {
        try
        {
            string logs = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "logs");
            Directory.CreateDirectory(logs);
            File.AppendAllText(Path.Combine(logs, "Civ6-Start.log"),
                DateTime.Now.ToString("s") + " " + message + Environment.NewLine, Encoding.UTF8);
        }
        catch { }
    }

    // Windows CommandLineToArgvW / C runtime quoting, including empty arguments,
    // embedded quotes, and backslashes immediately before a quote or the end.
    private static string Quote(string value)
    {
        string escaped = Regex.Replace(value, "(\\\\*)\"", "$1$1\\\"");
        return "\"" + Regex.Replace(escaped, "(\\\\+)$", "$1$1") + "\"";
    }

    [STAThread]
    private static int Main(string[] args)
    {
        Process fix = null;
        Process game = null;
        bool gameStarted = false;
        var listening = new ManualResetEvent(false);
        var output = new StringBuilder();
        try
        {
            if (args.Length == 0 || !File.Exists(args[0]))
                throw new Exception("请从 Steam 或原来的文明 VI 桌面图标启动游戏。");
            string gameName = Path.GetFileName(args[0]);
            if (!gameName.Equals("CivilizationVI.exe", StringComparison.OrdinalIgnoreCase) &&
                !gameName.Equals("CivilizationVI_DX12.exe", StringComparison.OrdinalIgnoreCase))
                throw new Exception("Steam 传来的启动项不是文明 VI 游戏程序，请检查启动设置。");

            string directory = AppDomain.CurrentDomain.BaseDirectory;
            string fixPath = Path.Combine(directory, "Civ6_2K_Online_Fix.exe");
            try
            {
                if (!File.Exists(fixPath)) throw new FileNotFoundException("找不到修复工具", fixPath);
                fix = new Process();
                fix.StartInfo = new ProcessStartInfo(fixPath, "--no-gui --watch-only")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WorkingDirectory = directory,
                    RedirectStandardOutput = true,
                    StandardOutputEncoding = Encoding.UTF8
                };
                fix.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e)
                {
                    if (e.Data == null) return;
                    lock (output)
                    {
                        output.AppendLine(e.Data);
                        if (output.Length > 6000) output.Remove(0, output.Length - 6000);
                    }
                    if (e.Data.Contains("\"event\":\"listener_ready\"") ||
                        e.Data.StartsWith("正在等待文明 VI", StringComparison.Ordinal)) listening.Set();
                };
                fix.Start();
                fix.BeginOutputReadLine();
                var wait = Stopwatch.StartNew();
                while (!listening.WaitOne(100))
                {
                    if (fix.HasExited || wait.Elapsed.TotalSeconds > 60)
                    {
                        string detail;
                        lock (output) detail = output.ToString();
                        throw new Exception("修复工具未进入监听，本次继续原生启动。" + detail);
                    }
                }
                Log("修复监听已就绪，启动 " + gameName);
            }
            catch (Exception error)
            {
                Log(error.Message);
                if (fix != null) { try { if (!fix.HasExited) fix.Kill(); } catch { } }
            }

            var start = new ProcessStartInfo(args[0], string.Join(" ", args.Skip(1).Select(Quote)))
            {
                UseShellExecute = false,
                WorkingDirectory = Path.GetDirectoryName(args[0])
            };
            game = Process.Start(start);
            gameStarted = true;
            // Steam tracks the wrapper until the game exits; preserve its exit code.
            game.WaitForExit();
            return game.ExitCode;
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "文明 VI 自动联机启动", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            if (fix != null && !gameStarted)
            {
                try { if (!fix.HasExited) fix.Kill(); } catch { }
            }
            if (game != null) game.Dispose();
            // Output callbacks can continue until the helper exits. The OS releases
            // this event at wrapper exit; do not dispose it underneath a callback.
        }
    }
}
