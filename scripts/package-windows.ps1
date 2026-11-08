[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedTag,
    [Parameter(Mandatory = $true)]
    [string]$InnoCompiler,
    [string]$OutputDirectory = 'dist'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Windows packaging must run on a Windows host.'
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$compiler = (Resolve-Path -LiteralPath $InnoCompiler).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
$bundle = Join-Path $root 'build\windows\x64\runner\Release'
$installerScript = Join-Path $PSScriptRoot '..\packaging\windows\DenucziTV.iss'
$versionLine = (Get-Content -LiteralPath (Join-Path $root 'pubspec.yaml') | Select-String '^version:').Line
if ($versionLine -notmatch '^version:\s*((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))\+([0-9]+)\s*$') {
    throw 'Expected a stable application version and numeric build number in pubspec.yaml.'
}
$version = $Matches[1]
$buildNumber = $Matches[2]
if ($ExpectedTag -cne "v$version") {
    throw 'The requested release tag does not match pubspec.yaml.'
}
$sourceTag = & git -C $root describe --tags --exact-match
if ($LASTEXITCODE -ne 0 -or $sourceTag -cne $ExpectedTag) {
    throw 'Application source must be checked out at the requested release tag.'
}
$sourceCommit = & git -C $root rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not determine the application source commit.' }

foreach ($name in @('denuczi_tv.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'data\app.so', 'data\icudtl.dat')) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundle $name) -PathType Leaf)) {
        throw "The release bundle is incomplete: missing $name."
    }
}
if (Test-Path -LiteralPath (Join-Path $bundle 'dartjni.dll')) {
    throw 'The bundle contains an unused JNI runtime. Rebuild with the Windows toolchain policy.'
}
$exe = Get-Item -LiteralPath (Join-Path $bundle 'denuczi_tv.exe')
$info = $exe.VersionInfo
$actualVersion = "$($info.FileMajorPart).$($info.FileMinorPart).$($info.FileBuildPart).$($info.FilePrivatePart)"
if ($actualVersion -ne "$version.$buildNumber") {
    throw 'The release executable is stale: its version differs from pubspec.yaml.'
}

# Validate the PE machine before naming the output as an x64 installer.
$stream = [IO.File]::OpenRead($exe.FullName)
$reader = [IO.BinaryReader]::new($stream)
try {
    if ($reader.ReadUInt16() -ne 0x5A4D) { throw 'Invalid Windows executable header.' }
    $stream.Position = 0x3C
    $peOffset = $reader.ReadInt32()
    if ($peOffset -lt 0 -or $peOffset -gt ($stream.Length - 6)) {
        throw 'Invalid PE header offset.'
    }
    $stream.Position = $peOffset
    if ($reader.ReadUInt32() -ne 0x00004550 -or $reader.ReadUInt16() -ne 0x8664) {
        throw 'The application executable must be a Windows x64 PE image.'
    }
} finally {
    $reader.Dispose()
    $stream.Dispose()
}

# Copy the matching official release CRT, not libraries from System32 or Debug.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio Installer was not found.' }
$vsPath = & $vswhere -latest -products '*' -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vsPath) {
    throw 'A Visual Studio 2022 installation with the C++ toolchain is required.'
}
$redistRoot = Join-Path $vsPath 'VC\Redist\MSVC'
$redistVersions = Get-ChildItem -LiteralPath $redistRoot -Directory | Where-Object { $_.Name -match '^\d+(\.\d+)+$' } | Sort-Object { [version]$_.Name } -Descending
$crt = $null
foreach ($directory in $redistVersions) {
    $candidate = Join-Path $directory.FullName 'x64\Microsoft.VC143.CRT'
    if (Test-Path -LiteralPath $candidate -PathType Container) {
        $crt = $candidate
        break
    }
}
if (-not $crt) { throw 'The official Visual C++ x64 release runtime was not found.' }
Copy-Item -Path (Join-Path $crt '*.dll') -Destination $bundle -Force
foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundle $name))) {
        throw "Missing runtime library: $name."
    }
}

New-Item -ItemType Directory -Force -Path $output | Out-Null
& $compiler "--define=ProjectRoot=$root" "--define=AppVersion=$version" "--output-dir=$output" $installerScript
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
$installer = Get-Item -LiteralPath (Join-Path $output "DenucziTV-Setup-$version-x64.exe")
$hash = (Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$($installer.FullName).sha256", "$hash  $($installer.Name)`n", [Text.Encoding]::ASCII)

$buildInfo = [ordered]@{
    applicationVersion = $version
    buildNumber = $buildNumber
    sourceTag = $sourceTag
    sourceCommit = $sourceCommit
    architecture = 'x64'
    installer = $installer.Name
    sha256 = $hash
    signatureStatus = (Get-AuthenticodeSignature -LiteralPath $installer.FullName).Status.ToString()
    runtimeVersion = (Get-Item -LiteralPath (Join-Path $bundle 'vcruntime140.dll')).VersionInfo.FileVersion
}
$buildInfoPath = Join-Path $output "DenucziTV-Setup-$version-x64.build-info.json"
[IO.File]::WriteAllText($buildInfoPath, ($buildInfo | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Output "Created: $($installer.FullName)"
Write-Output "SHA256: $hash"
