# Behavior checks for the bundle and package integrity helpers used by
# scripts/package-msix.ps1. This file does not build, sign, or install MSIX
# packages; it exercises the pure file and ZIP verification functions.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '../../scripts/package-msix.ps1')).Path
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw 'The packaging script contains PowerShell syntax errors.'
}

foreach ($function in $ast.FindAll(
    { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
    $true
)) {
    . ([scriptblock]::Create($function.Extent.Text))
}

$vcRuntimeDllNames = @(
    'concrt140.dll',
    'msvcp140.dll',
    'msvcp140_1.dll',
    'msvcp140_2.dll',
    'msvcp140_atomic_wait.dll',
    'msvcp140_codecvt_ids.dll',
    'vccorlib140.dll',
    'vcruntime140.dll',
    'vcruntime140_1.dll',
    'vcruntime140_threads.dll'
)

function Assert-Throws {
    param(
        [scriptblock]$Action,
        [string]$Pattern
    )

    $threw = $false
    try {
        & $Action
    } catch {
        $threw = $true
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "Expected an error matching '$Pattern', got: $($_.Exception.Message)"
        }
    }
    if (-not $threw) {
        throw "Expected an error matching '$Pattern', but no error was thrown."
    }
}

function Write-TestFile {
    param([string]$Path, [string]$Content)

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Content)
}

function New-TestZip {
    param([string]$Path, [System.Collections.IDictionary]$Entries)

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($key in $Entries.Keys) {
            $entry = $archive.CreateEntry($key)
            $writer = [IO.StreamWriter]::new($entry.Open())
            try {
                $writer.Write([string]$Entries[$key])
            } finally {
                $writer.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) "denuczitv-msix-tests-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $root | Out-Null

try {
    # Bundle protection: application files are tracked, msix-managed files are not.
    $bundle = Join-Path $root 'bundle'
    Write-TestFile (Join-Path $bundle 'denuczi_tv.exe') 'executable'
    Write-TestFile (Join-Path $bundle 'flutter_windows.dll') 'flutter'
    Write-TestFile (Join-Path $bundle 'data/app.so') 'app'
    Write-TestFile (Join-Path $bundle 'data/icudtl.dat') 'icu'
    Write-TestFile (Join-Path $bundle 'msvcp140.dll') 'runtime'
    Write-TestFile (Join-Path $bundle 'resources.pri') 'resource index'
    Write-TestFile (Join-Path $bundle 'Images/StoreLogo.png') 'logo'
    Write-TestFile (Join-Path $bundle 'AppxManifest.xml') 'manifest'

    $snapshot = Get-BundleProtectedSnapshot -Bundle $bundle
    foreach ($required in @('denuczi_tv.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat')) {
        if (-not $snapshot.Contains($required)) {
            throw "The protected snapshot is missing $required."
        }
    }
    foreach ($managed in @('msvcp140.dll', 'resources.pri', 'Images/StoreLogo.png', 'AppxManifest.xml')) {
        if ($snapshot.Contains($managed)) {
            throw "The protected snapshot must ignore msix-managed file $managed."
        }
    }
    Assert-BundleUnchanged -Bundle $bundle -Snapshot $snapshot

    Write-TestFile (Join-Path $bundle 'data/app.so') 'changed'
    Assert-Throws { Assert-BundleUnchanged -Bundle $bundle -Snapshot $snapshot } 'modified a protected bundle file'
    Write-TestFile (Join-Path $bundle 'data/app.so') 'app'

    Remove-Item -LiteralPath (Join-Path $bundle 'flutter_windows.dll')
    Assert-Throws { Assert-BundleUnchanged -Bundle $bundle -Snapshot $snapshot } 'removed a protected bundle file'
    Write-TestFile (Join-Path $bundle 'flutter_windows.dll') 'flutter'

    Write-TestFile (Join-Path $bundle 'unexpected.dll') 'unexpected'
    Assert-Throws { Assert-BundleUnchanged -Bundle $bundle -Snapshot $snapshot } 'added an unexpected bundle file'
    Remove-Item -LiteralPath (Join-Path $bundle 'unexpected.dll')

    # Package payload parity ignores signature and package metadata only.
    $crt = Join-Path $root 'crt'
    Write-TestFile (Join-Path $crt 'msvcp140.dll') 'msvcp'
    Write-TestFile (Join-Path $crt 'vcruntime140.dll') 'vcruntime'
    Write-TestFile (Join-Path $crt 'vcruntime140_1.dll') 'vcruntime1'

    $commonEntries = [ordered]@{
        'AppxManifest.xml' = 'manifest'
        'AppxBlockMap.xml' = 'block map'
        '[Content_Types].xml' = 'content types'
        'denuczi_tv.exe' = 'executable'
        'data/app.so' = 'app'
        'resources.pri' = 'resource data'
        'msvcp140.dll' = 'msvcp'
        'vcruntime140.dll' = 'vcruntime'
        'vcruntime140_1.dll' = 'vcruntime1'
    }
    $storeEntries = [ordered]@{}
    $qaEntries = [ordered]@{}
    foreach ($key in $commonEntries.Keys) {
        $storeEntries[$key] = $commonEntries[$key]
        $qaEntries[$key] = $commonEntries[$key]
    }
    $qaEntries['AppxSignature.p7x'] = 'signature'

    $storeMsix = Join-Path $root 'store.msix'
    $qaMsix = Join-Path $root 'qa.msix'
    New-TestZip -Path $storeMsix -Entries $storeEntries
    New-TestZip -Path $qaMsix -Entries $qaEntries

    $storePayload = Get-MsixPayloadHashes -Path $storeMsix
    $qaPayload = Get-MsixPayloadHashes -Path $qaMsix
    Assert-MsixPayloadMatches -Store $storePayload -Qa $qaPayload
    Assert-MsixCrtPayload -Hashes $storePayload -CrtPath $crt -Label 'Store'
    Assert-MsixCrtPayload -Hashes $qaPayload -CrtPath $crt -Label 'QA'
    if ($storePayload.Contains('AppxSignature.p7x') -or $storePayload.Contains('AppxManifest.xml')) {
        throw 'Package metadata must not be treated as application payload.'
    }

    $qaEntries['data/app.so'] = 'different app'
    New-TestZip -Path $qaMsix -Entries $qaEntries
    $qaPayload = Get-MsixPayloadHashes -Path $qaMsix
    Assert-Throws { Assert-MsixPayloadMatches -Store $storePayload -Qa $qaPayload } 'different content'

    $qaEntries.Remove('denuczi_tv.exe')
    New-TestZip -Path $qaMsix -Entries $qaEntries
    $qaPayload = Get-MsixPayloadHashes -Path $qaMsix
    Assert-Throws { Assert-MsixPayloadMatches -Store $storePayload -Qa $qaPayload } 'different number of payload files'

    $qaEntries['denuczi_tv.exe'] = 'executable'
    $qaEntries['data/app.so'] = 'app'
    $qaEntries['resources.pri'] = 'modified resource index'
    New-TestZip -Path $qaMsix -Entries $qaEntries
    $qaPayload = Get-MsixPayloadHashes -Path $qaMsix
    Assert-Throws { Assert-MsixPayloadMatches -Store $storePayload -Qa $qaPayload } 'different content for: resources.pri'

    $qaEntries['resources.pri'] = 'resource data'
    $qaEntries['vcruntime140.dll'] = 'wrong runtime'
    New-TestZip -Path $qaMsix -Entries $qaEntries
    $qaPayload = Get-MsixPayloadHashes -Path $qaMsix
    Assert-Throws { Assert-MsixCrtPayload -Hashes $qaPayload -CrtPath $crt -Label 'QA' } 'different vcruntime140.dll'

    Write-Output 'MSIX packager behavior checks passed.'
} finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
