[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Compiler,
    [Parameter(Mandatory)][string]$Launcher
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$fixture = [IO.Path]::GetFullPath((Join-Path $tempRoot ('Civ6Start_' + [Guid]::NewGuid().ToString('N'))))
if (-not $fixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
    -not [IO.Path]::GetFileName($fixture).StartsWith('Civ6Start_', [StringComparison]::Ordinal)) {
    throw 'Unsafe launcher test fixture path.'
}

try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $source = Join-Path $fixture 'Stub.cs'
    # Harmless stand-ins: no game, Steam, network, or process-memory access.
    @'
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
internal static class Stub {
    private static int Main(string[] args) {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        if (Path.GetFileName(Process.GetCurrentProcess().MainModule.FileName) == "Civ6_2K_Online_Fix.exe") {
            File.WriteAllText(Path.Combine(dir, "helper-pid.txt"), Process.GetCurrentProcess().Id.ToString());
            File.WriteAllLines(Path.Combine(dir, "helper-args.txt"), args);
            if (File.ReadAllText(Path.Combine(dir, "mode.txt")) == "early") return 9;
            Thread.Sleep(250);
            File.WriteAllText(Path.Combine(dir, "ready.txt"), "ready");
            Console.WriteLine("{\"event\":\"listener_ready\"}");
            Thread.Sleep(500);
            return 0;
        }
        File.WriteAllLines(args[0], args.Skip(2));
        if (args[1] == "ready" && !File.Exists(Path.Combine(dir, "ready.txt"))) return 24;
        return 23;
    }
}
'@ | Set-Content -LiteralPath $source -Encoding utf8NoBOM
    $stub = Join-Path $fixture 'Stub.exe'
    & $Compiler /nologo /target:exe /platform:x64 /optimize+ /warnaserror+ "/out:$stub" $source
    if ($LASTEXITCODE -ne 0) { throw 'Launcher test stub compilation failed.' }
    $testLauncher = Join-Path $fixture 'Civ6-Start.exe'
    Copy-Item -LiteralPath $Launcher -Destination $testLauncher
    $helper = Join-Path $fixture 'Civ6_2K_Online_Fix.exe'
    $expected = @('', 'two words', '引号"和中文', 'C:\folder with space\',
        'slashes\\"quote', '%command% & $literal', '\')
    foreach ($mode in @('missing', 'early', 'ready')) {
        if ($mode -ne 'missing') { Copy-Item -LiteralPath $stub -Destination $helper -Force }
        Set-Content -LiteralPath (Join-Path $fixture 'mode.txt') -Value $mode -NoNewline
        foreach ($gameName in @('CivilizationVI.exe', 'CivilizationVI_DX12.exe')) {
            $game = Join-Path $fixture $gameName
            Copy-Item -LiteralPath $stub -Destination $game
            $capture = Join-Path $fixture 'captured arguments 中文.txt'
            $ready = Join-Path $fixture 'ready.txt'
            if (Test-Path -LiteralPath $ready) { Remove-Item -LiteralPath $ready }
            $start = [Diagnostics.ProcessStartInfo]::new($testLauncher)
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            foreach ($argument in @($game, $capture, $mode) + $expected) { $start.ArgumentList.Add($argument) }
            $process = [Diagnostics.Process]::Start($start)
            try {
                if (-not $process.WaitForExit(15000)) {
                    $process.Kill($true)
                    throw "Launcher test timed out: $mode/$gameName"
                }
                if ($process.ExitCode -ne 23) {
                    throw "Child exit code or listener ordering lost: $mode/$gameName = $($process.ExitCode)"
                }
            }
            finally { $process.Dispose() }
            if ($mode -ne 'missing') {
                $helperProcess = $null
                try {
                    $helperProcess = [Diagnostics.Process]::GetProcessById(
                        [int][IO.File]::ReadAllText((Join-Path $fixture 'helper-pid.txt')))
                    if (-not $helperProcess.WaitForExit(3000)) {
                        $helperProcess.Kill()
                        throw 'Fixture helper did not finish.'
                    }
                }
                catch [ArgumentException] { } # The fixture may have already exited.
                finally { if ($null -ne $helperProcess) { $helperProcess.Dispose() } }
            }
            $actual = @([IO.File]::ReadAllLines($capture))
            if ($actual.Count -ne $expected.Count) { throw 'Launcher changed the argument count.' }
            for ($i = 0; $i -lt $expected.Count; $i++) {
                if ($actual[$i] -cne $expected[$i]) { throw "Launcher changed argument $i in $mode/$gameName" }
            }
            Write-Output "PASS: launcher $mode/$gameName preserves arguments, ordering, and child exit code"
        }
        $log = Get-Content -LiteralPath (Join-Path $fixture 'logs\Civ6-Start.log') -Raw
        if ($mode -eq 'ready' -and -not $log.Contains('修复监听已就绪')) {
            throw 'Readiness fixture unexpectedly took the fallback path.'
        }
        if ($mode -ne 'missing') {
            $helperArguments = @([IO.File]::ReadAllLines((Join-Path $fixture 'helper-args.txt')))
            if (($helperArguments -join ' ') -cne '--no-gui --watch-only') {
                throw 'Launcher must start the helper in headless watch-only mode.'
            }
        }
    }
}
finally {
    # The absolute path and fixed prefix were checked before creating the fixture.
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
