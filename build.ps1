[CmdletBinding()]
param(
    [switch]$SkipTests,
    [switch]$Analyze,
    [switch]$Mingw
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$sourceRoot = Join-Path $projectRoot 'src'
$testRoot = Join-Path $projectRoot 'tests'
$buildRoot = Join-Path $projectRoot 'build'
$generatedRoot = Join-Path $buildRoot 'generated'
$buildFlavor = 'community-mixed-support'
$appExecutableName = 'Civ6_2K_Online_Fix.exe'
$versionFile = Join-Path $projectRoot 'version.json'
if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
    throw "Version source was not found: $versionFile"
}
$productIdentity = Get-Content -LiteralPath $versionFile -Raw | ConvertFrom-Json
$productVersion = [string]$productIdentity.Version
$windowsVersion = [string]$productIdentity.WindowsVersion
$packageBaseName = [string]$productIdentity.PackageBaseName
if ($productVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$' -or
    $windowsVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' -or
    $packageBaseName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$') {
    throw 'version.json contains an invalid product identity.'
}
$windowsVersionParts = @($windowsVersion.Split('.') | ForEach-Object {
    $component = 0
    if (-not [int]::TryParse($_, [ref]$component) -or
        $component -lt 0 -or $component -gt 65535) {
        throw "Invalid Windows version component: $_"
    }
    $component
})
if ($windowsVersionParts.Count -ne 4) {
    throw 'WindowsVersion must contain exactly four numeric components.'
}

New-Item -ItemType Directory -Path $buildRoot,$generatedRoot -Force | Out-Null
$generatedIdentityHeader = Join-Path $generatedRoot 'ProductIdentity.generated.h'
$numericVersion = $windowsVersionParts -join ','
$generatedIdentity = @"
#pragma once

#define CIV6FIX_VERSION_NUMERIC $numericVersion
#define CIV6FIX_VERSION_SEMVER "$productVersion"
#define CIV6FIX_VERSION_SEMVER_WIDE L"$productVersion"

#ifndef RC_INVOKED
namespace civ6fix {

inline constexpr char kProductVersion[] = CIV6FIX_VERSION_SEMVER;
inline constexpr wchar_t kProductVersionWide[] =
    L"Civ6 2K Online Fix " CIV6FIX_VERSION_SEMVER_WIDE;

}  // namespace civ6fix
#endif
"@
Set-Content -LiteralPath $generatedIdentityHeader -Value $generatedIdentity `
    -Encoding utf8NoBOM

$manifestTemplatePath = Join-Path $sourceRoot 'Civ6_2K_Online_Fix.manifest.in'
if (-not (Test-Path -LiteralPath $manifestTemplatePath -PathType Leaf)) {
    throw "Manifest template was not found: $manifestTemplatePath"
}
$manifestTemplate = Get-Content -LiteralPath $manifestTemplatePath -Raw
$manifestVersionPlaceholder = '@WINDOWS_VERSION@'
if (($manifestTemplate.Split($manifestVersionPlaceholder).Count - 1) -ne 1) {
    throw 'Manifest template must contain exactly one Windows version placeholder.'
}
$generatedManifest = Join-Path $generatedRoot 'ProductManifest.generated.manifest'
$manifestTemplate.Replace($manifestVersionPlaceholder, $windowsVersion) |
    Set-Content -LiteralPath $generatedManifest -Encoding utf8NoBOM

$launcherExe = Join-Path $buildRoot 'Civ6-Start.exe'
function Build-Launcher([string]$CSharpCompiler, [bool]$Deterministic) {
    if (-not (Test-Path -LiteralPath $CSharpCompiler -PathType Leaf)) {
        throw "C# compiler was not found: $CSharpCompiler"
    }
    $identityFile = Join-Path $generatedRoot 'LauncherIdentity.generated.cs'
    @"
using System.Reflection;
[assembly: AssemblyTitle("Civ6 Steam launch wrapper")]
[assembly: AssemblyVersion("$windowsVersion")]
[assembly: AssemblyFileVersion("$windowsVersion")]
[assembly: AssemblyInformationalVersion("$productVersion")]
"@ | Set-Content -LiteralPath $identityFile -Encoding utf8NoBOM
    $arguments = @('/nologo', '/target:winexe', '/platform:x64', '/optimize+',
        '/warn:4', '/warnaserror+', '/codepage:65001',
        '/reference:System.Windows.Forms.dll', "/out:$launcherExe",
        "/win32manifest:$generatedManifest")
    if ($Deterministic) {
        $arguments += @('/deterministic+', "/pathmap:$projectRoot=.")
    }
    & $CSharpCompiler @arguments $identityFile (Join-Path $projectRoot 'launcher\Civ6-Start.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Steam launcher compilation failed.' }
}

function Invoke-ProjectTests([string]$TestExecutable, [string]$CSharpCompiler) {
    if ($SkipTests) { return 0 }
    $lines = @(& $TestExecutable 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Core tests failed: $($lines -join [Environment]::NewLine)" }
    $lines | ForEach-Object { Write-Host $_ }
    $count = @($lines | Where-Object { $_ -like 'PASS:*' }).Count
    foreach ($scriptTest in @('VerifyHashes.Tests.ps1', 'VersionSource.Tests.ps1', 'ReleasePolicy.Tests.ps1')) {
        $lines = @(& (Join-Path $testRoot $scriptTest) 2>&1)
        $lines | ForEach-Object { Write-Host $_ }
        $count += @($lines | Where-Object { $_ -like 'PASS:*' }).Count
    }
    $lines = @(& (Join-Path $testRoot 'Civ6Start.Tests.ps1') -Compiler $CSharpCompiler -Launcher $launcherExe 2>&1)
    $lines | ForEach-Object { Write-Host $_ }
    $count += @($lines | Where-Object { $_ -like 'PASS:*' }).Count
    if ($count -le 0) { throw 'Tests reported success without counted assertions.' }
    return $count
}

function Write-BuildManifest([string]$Toolchain, [int]$TestCount,
                            [string]$CompilerVersion, [string]$SdkVersion) {
    $appExe = Join-Path $buildRoot $appExecutableName
    $appItem = Get-Item -LiteralPath $appExe
    if ($appItem.VersionInfo.FileVersion -ne $productVersion -or
        $appItem.VersionInfo.ProductVersion -ne $productVersion) {
        throw 'Helper version resource does not match version.json.'
    }
    $msvcBuild = $Toolchain -eq 'MSVC'
    $manifest = [ordered]@{
        Product = 'Civ6 2K Online Fix (community fork)'
        Version = $productVersion
        WindowsVersion = $windowsVersion
        PackageBaseName = $packageBaseName
        BuildFlavor = $buildFlavor
        Dx12WriteEnabled = $true
        BuiltAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Configuration = 'Release'
        Architecture = 'x64'
        Executable = $appItem.Name
        Length = $appItem.Length
        SHA256 = (Get-FileHash -LiteralPath $appExe -Algorithm SHA256).Hash
        Launcher = [ordered]@{
            Executable = 'Civ6-Start.exe'
            Length = (Get-Item -LiteralPath $launcherExe).Length
            SHA256 = (Get-FileHash -LiteralPath $launcherExe -Algorithm SHA256).Hash
            Deterministic = $msvcBuild
        }
        BuildProfiles = @(
            [ordered]@{
                Id = 'civ6-win64steam-1.0.12.68-dx11'; Renderer = 'DX11'
                SupportState = 'Verified'; Evidence = 'Upstream'
                SHA256 = 'E7450823CC8E00468CFF7B9D7B97C63140EAE38AE1D774BA4EFA437556C42D63'
            }
            [ordered]@{
                Id = 'civ6-win64steam-1.0.12.68-dx12'; Renderer = 'DX12'
                SupportState = 'Verified'; Evidence = 'Upstream'
                SHA256 = 'C2C3D40B86260A541D8A4D38CB70D50D3406AE1DE374AFC382D1E42BC1342F1E'
            }
            [ordered]@{
                Id = 'civ6-win64steam-1.0.12.72-dx11'; Renderer = 'DX11'
                SupportState = 'ReadOnlyCandidate'; Evidence = 'StaticOnly'
                SHA256 = 'D1A0CFD439E7451BE515F47595CFA0B6B983F56D1FAF4EA434A4CE3B21491EBE'
            }
            [ordered]@{
                Id = 'civ6-win64steam-1.0.12.72-dx12'; Renderer = 'DX12'
                SupportState = 'Verified'; Evidence = 'LocalRuntimeAndLobbyList'
                SHA256 = '1ADB1A2BCA31F9DB6BE14D6E22D30D2DFCB6DCD8DE3ABD9A81E7BEA396B39417'
            }
        )
        Toolchain = $Toolchain
        CompilerVersion = $CompilerVersion
        WindowsSDKVersion = $SdkVersion
        NativeAnalysis = ($msvcBuild -and [bool]$Analyze)
        TestsRun = (-not $SkipTests)
        TestCount = $TestCount
        ReproducibleBuild = $msvcBuild
        SourcePathMapping = if ($msvcBuild) { '.' } else { $null }
        VersionSource = 'version.json'
        SecurityProperties = if ($msvcBuild) {
            @('asInvoker', 'NXCOMPAT', 'HIGHENTROPYVA', 'CFG', 'CETCOMPAT',
              'StaticMSVCRuntime', 'DeterministicCompilation', 'SourcePathMapping',
              'ReproducibleLink', 'SingleSourceVersion')
        } else {
            @('asInvoker', 'NXCOMPAT', 'HIGHENTROPYVA', 'StaticMinGWRuntime', 'SingleSourceVersion')
        }
    }
    $manifest | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $buildRoot 'build_manifest.json') -Encoding utf8NoBOM
    $manifest
}

if ($Mingw) {
    if ($Analyze) { throw 'MSVC /analyze is not available in a MinGW local build.' }
    $compiler = (Get-Command g++.exe -ErrorAction Stop).Source
    $resourceCompiler = Join-Path (Split-Path $compiler) 'windres.exe'
    $csharpCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    Build-Launcher $csharpCompiler $false
    $flags = @("-B$(Split-Path $compiler)\", '-std=c++17', '-O2', '-Wall', '-Wextra', '-Wno-unknown-pragmas',
        '-Wno-missing-field-initializers', '-DUNICODE', '-D_UNICODE',
        '-D_WIN32_WINNT=0x0A00', '-static', "-I$generatedRoot", "-I$sourceRoot")
    $coreSources = @('FixSession', 'SessionPresentation', 'SteamDiscovery') |
        ForEach-Object { Join-Path $sourceRoot "$_.cpp" }
    $testExe = Join-Path $buildRoot 'Civ6FixCoreTests.exe'
    & $compiler @flags (Join-Path $testRoot 'Civ6FixCoreTests.cpp') @coreSources -o $testExe
    if ($LASTEXITCODE -ne 0) { throw 'MinGW test compilation failed.' }
    $testCount = Invoke-ProjectTests $testExe $csharpCompiler
    $resourceFile = Join-Path $buildRoot 'Civ6_2K_Online_Fix.resource.o'
    & $resourceCompiler "-I$generatedRoot" -O coff (Join-Path $sourceRoot 'Civ6_2K_Online_Fix.rc') $resourceFile
    if ($LASTEXITCODE -ne 0) { throw 'MinGW resource compilation failed.' }
    $sources = Get-ChildItem -LiteralPath $sourceRoot -Filter '*.cpp' | ForEach-Object FullName
    $appExe = Join-Path $buildRoot $appExecutableName
    & $compiler @flags -municode -mwindows @sources $resourceFile -o $appExe `
        -ladvapi32 -lbcrypt -lcomctl32 -lgdi32 -lpsapi -lshell32 -luser32 `
        '-Wl,--dynamicbase,--nxcompat,--high-entropy-va'
    if ($LASTEXITCODE -ne 0) { throw 'MinGW application compilation failed.' }
    Write-BuildManifest 'MinGW' $testCount ((& $compiler -dumpfullversion) -join '') ''
    return
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw "Visual Studio Installer discovery tool was not found: $vswhere"
}
$visualStudioRoot = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($visualStudioRoot)) {
    throw 'No Visual Studio installation with the x64 C++ toolchain was found.'
}
$vcVersionFile = Join-Path $visualStudioRoot 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt'
if (-not (Test-Path -LiteralPath $vcVersionFile -PathType Leaf)) {
    throw "MSVC version marker was not found: $vcVersionFile"
}
$msvcVersion = (Get-Content -LiteralPath $vcVersionFile -Raw).Trim()
$msvc = Join-Path $visualStudioRoot "VC\Tools\MSVC\$msvcVersion"

$sdkRegistryPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Kits\Installed Roots'
$sdk = Get-ItemPropertyValue -LiteralPath $sdkRegistryPath -Name KitsRoot10 -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($sdk)) {
    $sdk = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
}
$sdkIncludeRoot = Join-Path $sdk 'Include'
$sdkVersionItem = Get-ChildItem -LiteralPath $sdkIncludeRoot -Directory |
    Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName 'um\Windows.h') -PathType Leaf
    } |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
if ($null -eq $sdkVersionItem) {
    throw "No usable Windows 10/11 SDK was found under: $sdkIncludeRoot"
}
$sdkVersion = $sdkVersionItem.Name
$compiler = Join-Path $msvc 'bin\Hostx64\x64\cl.exe'
$resourceCompiler = Join-Path $sdk "bin\$sdkVersion\x64\rc.exe"
foreach ($tool in @($compiler, $resourceCompiler)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Required build tool was not found: $tool"
    }
}
$csharpCompiler = Join-Path $visualStudioRoot 'MSBuild\Current\Bin\Roslyn\csc.exe'
Build-Launcher $csharpCompiler $true

$commonCompilerArgs = @(
    '/nologo'
    '/std:c++17'
    '/EHsc'
    '/permissive-'
    '/W4'
    '/WX'
    '/MT'
    '/O2'
    '/sdl'
    '/guard:cf'
    '/experimental:deterministic'
    "/pathmap:$projectRoot=."
    '/utf-8'
    '/Zc:__cplusplus'
    '/Zc:preprocessor'
    '/DUNICODE'
    '/D_UNICODE'
    "/I$generatedRoot"
    "/I$sourceRoot"
    "/I$(Join-Path $msvc 'include')"
    "/I$(Join-Path $sdk "Include\$sdkVersion\ucrt")"
    "/I$(Join-Path $sdk "Include\$sdkVersion\shared")"
    "/I$(Join-Path $sdk "Include\$sdkVersion\um")"
)
if ($Analyze) {
    $commonCompilerArgs += @(
        '/analyze'
        # Windows SDK 10.0.26100 winreg.h emits C6553 from its own SAL annotation.
        '/wd6553'
    )
}
$libraryArgs = @(
    "/LIBPATH:$(Join-Path $msvc 'lib\x64')"
    "/LIBPATH:$(Join-Path $sdk "Lib\$sdkVersion\ucrt\x64")"
    "/LIBPATH:$(Join-Path $sdk "Lib\$sdkVersion\um\x64")"
)

$objects = @{}
foreach ($name in @('FixSession', 'SessionPresentation', 'SteamDiscovery', 'Logger', 'Win32FixPlatform', 'AppWindow')) {
    $object = Join-Path $buildRoot "$name.obj"
    $compileArgs = @($commonCompilerArgs) + @(
        '/c'
        "/Fo$object"
        (Join-Path $sourceRoot "$name.cpp")
    )
    & $compiler @compileArgs
    if ($LASTEXITCODE -ne 0) {
        throw "$name compilation failed with exit code $LASTEXITCODE"
    }
    $objects[$name] = $object
}

$testExe = Join-Path $buildRoot 'Civ6FixCoreTests.exe'
$testObject = Join-Path $buildRoot 'Civ6FixCoreTests.obj'
$testArgs = @($commonCompilerArgs) + @(
    "/Fo$testObject"
    "/Fe$testExe"
    (Join-Path $testRoot 'Civ6FixCoreTests.cpp')
    $objects['FixSession']
    $objects['SessionPresentation']
    $objects['SteamDiscovery']
    '/link'
) + $libraryArgs

& $compiler @testArgs
if ($LASTEXITCODE -ne 0) {
    throw "Unit test compilation failed with exit code $LASTEXITCODE"
}

$testCount = Invoke-ProjectTests $testExe $csharpCompiler

$resourceFile = Join-Path $buildRoot 'Civ6_2K_Online_Fix.res'
$resourceArgs = @(
    '/nologo'
    '/i'
    $generatedRoot
    '/i'
    (Join-Path $sdk "Include\$sdkVersion\um")
    '/i'
    (Join-Path $sdk "Include\$sdkVersion\shared")
    '/i'
    (Join-Path $sdk "Include\$sdkVersion\ucrt")
    "/fo$resourceFile"
    (Join-Path $sourceRoot 'Civ6_2K_Online_Fix.rc')
)
Push-Location $sourceRoot
try {
    & $resourceCompiler @resourceArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Resource compilation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$appExe = Join-Path $buildRoot $appExecutableName
$appObject = Join-Path $buildRoot 'Civ6_2K_Online_Fix.obj'
$appArgs = @($commonCompilerArgs) + @(
    "/Fo$appObject"
    "/Fe$appExe"
    (Join-Path $sourceRoot 'Civ6_2K_Online_Fix.cpp')
    $objects['FixSession']
    $objects['SessionPresentation']
    $objects['SteamDiscovery']
    $objects['Logger']
    $objects['Win32FixPlatform']
    $objects['AppWindow']
    $resourceFile
    '/link'
    '/SUBSYSTEM:WINDOWS'
    '/INCREMENTAL:NO'
    '/OPT:REF'
    '/OPT:ICF'
    '/BREPRO'
    '/experimental:deterministic'
    '/DYNAMICBASE'
    '/HIGHENTROPYVA'
    '/NXCOMPAT'
    '/guard:cf'
    '/CETCOMPAT'
    'advapi32.lib'
    'bcrypt.lib'
    'comctl32.lib'
    'gdi32.lib'
    'psapi.lib'
    'shell32.lib'
    'user32.lib'
) + $libraryArgs

& $compiler @appArgs
if ($LASTEXITCODE -ne 0) {
    throw "Application compilation failed with exit code $LASTEXITCODE"
}

Write-BuildManifest 'MSVC' $testCount $msvcVersion $sdkVersion
