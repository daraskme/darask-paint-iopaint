param(
    [string]$Uv = "uv",
    [string]$Python = "3.12"
)

$ErrorActionPreference = "Stop"
$launcher = (Resolve-Path (Join-Path $PSScriptRoot "..\darask-plugin.bat")).Path
$root = Join-Path $env:USERPROFILE ("darask launcher test " + [guid]::NewGuid())
$venv = Join-Path $root "IOPaint\env"
$dist = Join-Path $venv "Lib\site-packages\iopaint-2.0.0rc2.dist-info"
$saved = @{}
foreach ($name in @("LOCALAPPDATA", "PATH", "PROBE_LOG", "HIDE_PLUGIN_MODE")) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
}

function Assert-Contains([string]$Text, [string]$Value) {
    if (-not $Text.Contains($Value)) { throw "Missing '$Value' in:`n$Text" }
}

function Invoke-Launcher {
    [IO.File]::WriteAllText($env:PROBE_LOG, "")
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $env:ComSpec
    $info.Arguments = '/d /c ""' + $launcher + '""'
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(20000)) {
        $process.Kill()
        throw "Launcher timed out"
    }
    $output = $stdout.Result + $stderr.Result
    $calls = [IO.File]::ReadAllText($env:PROBE_LOG)
    $process.Dispose()
    return @{ Output = $output; Calls = $calls }
}

try {
    New-Item -ItemType Directory -Path $root | Out-Null
    $setup = Start-Process -FilePath $Uv -ArgumentList @(
        "venv", ('"' + $venv + '"'), "--python", ('"' + $Python + '"')
    ) -Wait -NoNewWindow -PassThru
    if ($setup.ExitCode -ne 0) { throw "Could not create isolated Python environment" }
    New-Item -ItemType Directory -Path $dist | Out-Null
    Set-Content (Join-Path $dist "METADATA") "Name: iopaint`nVersion: 2.0.0rc2" -Encoding ASCII
    Set-Content (Join-Path $dist "RECORD") "initial" -Encoding ASCII
    $stub = Join-Path $venv "Scripts\iopaint.exe"
    Add-Type -OutputAssembly $stub -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
using System.Diagnostics;
public class LauncherFixture {
    public static int Main(string[] args) {
        string name = Path.GetFileNameWithoutExtension(Process.GetCurrentProcess().MainModule.FileName);
        File.AppendAllText(Environment.GetEnvironmentVariable("PROBE_LOG"), name + " " + string.Join(" ", args) + "\n");
        if (name == "uv") { Console.WriteLine("INSTALL_REQUESTED"); return 1; }
        if (args.Length == 1 && args[0] == "--version") { Console.WriteLine("2.0.0rc2"); return 0; }
        if (args.Length == 2 && args[1] == "--help") {
            if (Environment.GetEnvironmentVariable("HIDE_PLUGIN_MODE") != "1") Console.WriteLine("--darask-plugin-mode");
            return 0;
        }
        Console.WriteLine("SERVER_START");
        return 0;
    }
}
'@
    Copy-Item $stub (Join-Path $root "uv.exe")
    $env:LOCALAPPDATA = $root
    $env:PATH = $root + ";" + $env:PATH
    $env:PROBE_LOG = Join-Path $root "calls.txt"
    $env:HIDE_PLUGIN_MODE = ""
    # Importing the package must not be necessary to read its installed version.
    Set-Content (Join-Path $venv "Lib\site-packages\iopaint.py") "raise RuntimeError('package was imported')" -Encoding ASCII

    $cold = Invoke-Launcher
    Assert-Contains $cold.Output "SERVER_START"
    Assert-Contains $cold.Calls "iopaint start --help"
    Assert-Contains $cold.Calls "--host 127.0.0.1 --port 8423 --darask-plugin-mode"
    if ($cold.Calls.Contains("--version") -or $cold.Calls.Contains("uv ")) { throw $cold.Calls }
    Write-Host "PASS: metadata-only cold check, paths with spaces, restricted server flags"

    $warm = Invoke-Launcher
    Assert-Contains $warm.Output "SERVER_START"
    if ($warm.Calls.Contains("--help") -or $warm.Calls.Contains("--version")) { throw $warm.Calls }
    Write-Host "PASS: warm start skips probes"

    Add-Content (Join-Path $dist "RECORD") "changed record"
    $env:HIDE_PLUGIN_MODE = "1"
    $unsupported = Invoke-Launcher
    Assert-Contains $unsupported.Calls "iopaint start --help"
    Assert-Contains $unsupported.Output "refuses to start"
    if ($unsupported.Output.Contains("SERVER_START")) { throw "Unrestricted start" }
    Write-Host "PASS: changed install requires restricted-mode probe and refuses unsupported mode"

    Set-Content (Join-Path $dist "METADATA") "Name: iopaint`nVersion: 1.0.0" -Encoding ASCII
    $mismatch = Invoke-Launcher
    Assert-Contains $mismatch.Output "INSTALL_REQUESTED"
    Assert-Contains $mismatch.Calls "git+https://github.com/daraskme/IOpaint@v2.0.0-rc2"
    if ($mismatch.Output.Contains("SERVER_START")) { throw "Wrong version started" }
    Write-Host "PASS: mismatched version requests pinned installation"

    Remove-Item (Join-Path $dist "METADATA")
    $missing = Invoke-Launcher
    Assert-Contains $missing.Output "INSTALL_REQUESTED"
    if ($missing.Output.Contains("SERVER_START")) { throw "Missing metadata accepted" }
    Write-Host "PASS: missing metadata requests installation"
} finally {
    foreach ($name in $saved.Keys) {
        [Environment]::SetEnvironmentVariable($name, $saved[$name])
    }
    if (Test-Path $root) { Remove-Item -Recurse -Force $root }
}
