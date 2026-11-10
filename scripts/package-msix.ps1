[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [string]$ExpectedPublicVersion = '0.6.3',
    [int]$ExpectedBuildNumber = 1,
    [string]$ExpectedSourceCommit = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'MSIX packaging must run on a Windows host.'
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$scriptRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$pathComparison = [StringComparison]::OrdinalIgnoreCase
if (-not $scriptRoot.StartsWith("$root$([IO.Path]::DirectorySeparatorChar)", $pathComparison)) {
    throw 'The packaging script must belong to the same source revision as ProjectRoot.'
}
$bundle = Join-Path $root 'build\windows\x64\runner\Release'
$pubspecPath = Join-Path $root 'pubspec.yaml'

$identityName = 'IgnacioSanguina.DenucziTV'
$publisher = 'CN=055E0D46-1999-438C-9CDB-4069928369ED'
$publisherDisplayName = 'Ignacio Sanguina'
$displayName = 'DenucziTV'
$packageVersion = '1.6.3.0'
$architecture = 'x64'
$expectedOutputPath = 'build/store_msix'
$expectedOutputName = 'DenucziTV-0.6.3-x64'
$storeBuildDefine = 'DENUCZI_STORE_BUILD=true'
$storeName = "$expectedOutputName-store"
$qaName = "$expectedOutputName-qa"

function Read-MsixConfig {
    param([string]$Path)

    $config = [ordered]@{}
    $inSection = $false

    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if (-not $inSection) {
            if ($line -match '^msix_config:\s*(#.*)?$') {
                $inSection = $true
            }
            continue
        }

        if ($line -match '^\S') {
            break
        }

        if ($line -match '^  ([A-Za-z0-9_]+):\s*(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()
            if ($value -match '^"(.*)"$') {
                $value = $Matches[1]
            } elseif ($value -match "^'(.*)'$") {
                $value = $Matches[1]
            }
            $value = ($value -replace '\s+#.*$', '').Trim()
            $config[$key] = $value
        }
    }

    return $config
}

function Assert-ConfigValue {
    param(
        [System.Collections.IDictionary]$Config,
        [string]$Key,
        [string]$Expected
    )

    if ($Config.Keys -notcontains $Key) {
        throw "msix_config is missing '$Key' in pubspec.yaml."
    }
    if ([string]$Config[$Key] -cne $Expected) {
        throw "msix_config '$Key' must be '$Expected'."
    }
}

function Assert-PeX64 {
    param([string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw 'Invalid Windows executable header.'
        }
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
}

function Get-ReleaseCrtPath {
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ([string]::IsNullOrWhiteSpace($programFilesX86)) {
        throw 'The Program Files (x86) directory was not found.'
    }
    $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'Visual Studio Installer was not found.'
    }
    $vsPath = & $vswhere -latest -products '*' -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($vsPath)) {
        throw 'A Visual Studio 2022 installation with the C++ toolchain is required.'
    }
    $vsPath = $vsPath.Trim()
    $redistRoot = Join-Path $vsPath 'VC\Redist\MSVC'
    if (-not (Test-Path -LiteralPath $redistRoot)) {
        throw 'The Visual C++ redistributable directory was not found.'
    }
    $redistVersions = Get-ChildItem -LiteralPath $redistRoot -Directory |
        Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
        Sort-Object { [version]$_.Name } -Descending
    foreach ($directory in $redistVersions) {
        $archDirectory = Join-Path $directory.FullName 'x64'
        if (-not (Test-Path -LiteralPath $archDirectory -PathType Container)) {
            continue
        }
        # Match the msix tool selection: newest version directory, then the
        # highest Microsoft.VC*.CRT directory for x64.
        $crtDirectories = Get-ChildItem -LiteralPath $archDirectory -Directory |
            Where-Object { $_.Name -like '*.CRT' } |
            Sort-Object Name -Descending
        foreach ($crtDirectory in $crtDirectories) {
            return $crtDirectory.FullName
        }
    }
    throw 'The official Visual C++ x64 release runtime was not found.'
}

function Copy-ReleaseCrt {
    param(
        [string]$Bundle,
        [string]$CrtPath
    )

    Copy-Item -Path (Join-Path $CrtPath '*.dll') -Destination $Bundle -Force
    foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Bundle $name) -PathType Leaf)) {
            throw "Missing runtime library: $name."
        }
    }
    return (Get-Item -LiteralPath (Join-Path $Bundle 'vcruntime140.dll')).VersionInfo.FileVersion
}

function Assert-ReleaseCrt {
    param(
        [string]$Bundle,
        [string]$CrtPath,
        [string]$ExpectedVersion
    )

    foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        $source = Join-Path $CrtPath $name
        $target = Join-Path $Bundle $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "The official Visual C++ runtime is missing $name."
        }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "The release bundle is missing $name."
        }
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($sourceHash -cne $targetHash) {
            throw "The release bundle contains a different $name than the official x64 runtime."
        }
    }

    $actualVersion = (Get-Item -LiteralPath (Join-Path $Bundle 'vcruntime140.dll')).VersionInfo.FileVersion
    if ($actualVersion -cne $ExpectedVersion) {
        throw "Unexpected Visual C++ runtime version in the bundle: $actualVersion."
    }
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

function Get-BundleProtectedSnapshot {
    param([string]$Bundle)

    $managedNames = @(
        'AppxManifest.xml',
        'priconfig.xml',
        'resources.pri',
        'resources.scale-125.pri',
        'resources.scale-150.pri',
        'resources.scale-200.pri',
        'resources.scale-400.pri',
        'installCertificate.ps1',
        'InstallTestCertificate.exe',
        'test_certificate.pfx'
    )
    $snapshot = [ordered]@{}

    foreach ($file in (Get-ChildItem -LiteralPath $Bundle -Recurse -File)) {
        $relativePath = $file.FullName.Substring($Bundle.Length)
        $relative = $relativePath.TrimStart([char[]]@('\', '/')).Replace('\', '/')
        if ($managedNames -contains $relative) {
            continue
        }
        if ($relative.StartsWith('Images/', [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if ($vcRuntimeDllNames -contains $relative) {
            continue
        }
        if ($relative -match '(?i)\.msix$') {
            continue
        }
        $snapshot[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }

    return $snapshot
}

function Assert-BundleUnchanged {
    param(
        [string]$Bundle,
        [System.Collections.IDictionary]$Snapshot
    )

    $current = Get-BundleProtectedSnapshot -Bundle $Bundle
    foreach ($key in $Snapshot.Keys) {
        if (-not $current.Contains($key)) {
            throw "MSIX packaging removed a protected bundle file: $key."
        }
        if ($current[$key] -cne $Snapshot[$key]) {
            throw "MSIX packaging modified a protected bundle file: $key."
        }
    }
    foreach ($key in $current.Keys) {
        if (-not $Snapshot.Contains($key)) {
            throw "MSIX packaging added an unexpected bundle file: $key."
        }
    }
}

function Assert-BundlePolicy {
    param([string]$Bundle)

    $jniFiles = @(Get-ChildItem -LiteralPath $Bundle -Recurse -File -Filter 'dartjni.dll')
    if ($jniFiles.Count -gt 0) {
        throw 'The bundle contains an unused JNI runtime. Rebuild with the Windows toolchain policy.'
    }
    $pdbFiles = @(Get-ChildItem -LiteralPath $Bundle -Recurse -File -Filter '*.pdb')
    if ($pdbFiles.Count -gt 0) {
        throw 'PDB debug symbols remain in the release bundle.'
    }
}

function Invoke-MsixCreate {
    param(
        [string]$Root,
        [string]$OutputPath,
        [string]$OutputName,
        [switch]$Store
    )

    $arguments = @(
        'run', 'msix:create',
        '--sign-msix', 'false',
        '--install-certificate', 'false',
        '--build-windows', 'false',
        '--architecture', 'x64',
        '--output-path', $OutputPath,
        '--output-name', $OutputName
    )
    if ($Store) {
        $arguments += '--store'
    }

    Push-Location -LiteralPath $Root
    try {
        & dart @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "MSIX packaging failed for $OutputName."
        }
    } finally {
        Pop-Location
    }
}

function Get-MsixEntryNames {
    param([string]$Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        return @($archive.Entries | ForEach-Object { $_.FullName })
    } finally {
        $archive.Dispose()
    }
}

function Get-Sha256String {
    param([string]$Text)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-MsixPayloadHashes {
    param([string]$Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    $hashes = [ordered]@{}
    try {
        foreach ($entry in $archive.Entries) {
            if ([string]::IsNullOrEmpty($entry.Name)) {
                continue
            }
            # MSIX signing can add the signature and PE code-integrity
            # catalog. Both are package footprint files, not app payload.
            # Compare every other file, including resources.pri and images.
            $name = $entry.FullName.Replace('\', '/')
            if ($name -in @(
                'AppxManifest.xml',
                'AppxBlockMap.xml',
                '[Content_Types].xml',
                'AppxSignature.p7x',
                'AppxMetadata/CodeIntegrity.cat'
            )) {
                continue
            }
            if ($hashes.Contains($name)) {
                throw "Duplicate MSIX payload path: $name."
            }

            $stream = $entry.Open()
            try {
                $sha = [Security.Cryptography.SHA256]::Create()
                try {
                    $hash = $sha.ComputeHash($stream)
                } finally {
                    $sha.Dispose()
                }
            } finally {
                $stream.Dispose()
            }
            $hashes[$name] = (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
        }
    } finally {
        $archive.Dispose()
    }

    return $hashes
}

function Get-HashDictionaryDigest {
    param([System.Collections.IDictionary]$Hashes)

    $lines = @($Hashes.Keys | Sort-Object | ForEach-Object { "$_=$($Hashes[$_])" }) -join "`n"
    return Get-Sha256String -Text $lines
}

function Assert-MsixPayloadMatches {
    param(
        [System.Collections.IDictionary]$Store,
        [System.Collections.IDictionary]$Qa
    )

    # Report the actual paths on failure. A file-count-only error hides
    # whether SignTool added metadata or a real application file diverged.
    $missing = @($Store.Keys | Where-Object { -not $Qa.Contains($_) })
    $extra = @($Qa.Keys | Where-Object { -not $Store.Contains($_) })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        throw "The Store and QA payload file lists differ (missing from QA: $($missing -join ', '); unexpected in QA: $($extra -join ', '))."
    }
    foreach ($key in $Store.Keys) {
        if ($Store[$key] -cne $Qa[$key]) {
            throw "The Store and QA packages contain different content for: $key."
        }
    }
}

function Assert-MsixCrtPayload {
    param(
        [System.Collections.IDictionary]$Hashes,
        [string]$CrtPath,
        [string]$Label
    )

    foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not $Hashes.Contains($name)) {
            throw "The $Label package is missing $name."
        }
        $expected = (Get-FileHash -LiteralPath (Join-Path $CrtPath $name) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($Hashes[$name] -cne $expected) {
            throw "The $Label package contains a different $name than the official x64 runtime."
        }
    }
}

function Get-MsixManifest {
    param([string]$Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $archive.GetEntry('AppxManifest.xml')
        if ($null -eq $entry) {
            throw 'The MSIX package does not contain AppxManifest.xml.'
        }
        $stream = $entry.Open()
        try {
            $reader = [IO.StreamReader]::new($stream)
            try {
                $text = $reader.ReadToEnd()
            } finally {
                $reader.Dispose()
            }
        } finally {
            $stream.Dispose()
        }
    } finally {
        $archive.Dispose()
    }

    $document = [Xml.XmlDocument]::new()
    $document.LoadXml($text)
    return $document
}

function Assert-MsixVisualAssets {
    param(
        [xml]$Manifest,
        [string[]]$Entries
    )

    $namespaces = [Xml.XmlNamespaceManager]::new($Manifest.NameTable)
    $namespaces.AddNamespace('f', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    $namespaces.AddNamespace('uap', 'http://schemas.microsoft.com/appx/manifest/uap/windows10')

    $logo = $Manifest.SelectSingleNode('/f:Package/f:Properties/f:Logo', $namespaces)
    if ($null -eq $logo -or [string]::IsNullOrWhiteSpace($logo.InnerText)) {
        throw 'The MSIX manifest is missing its Store logo reference.'
    }
    $visual = $Manifest.SelectSingleNode('/f:Package/f:Applications/f:Application/uap:VisualElements', $namespaces)
    if ($null -eq $visual) {
        throw 'The MSIX manifest is missing uap:VisualElements.'
    }

    $references = @($logo.InnerText)
    foreach ($required in @('Square44x44Logo', 'Square150x150Logo')) {
        $value = $visual.GetAttribute($required)
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "The MSIX manifest is missing its $required reference."
        }
    }

    # Validate all declared icon/tile/splash images, not just a hard-coded
    # filename. MakePRI can package qualified image variants without an
    # unqualified StoreLogo.png entry.
    foreach ($element in @($visual) + @($visual.SelectNodes('.//*'))) {
        foreach ($attribute in $element.Attributes) {
            if ($attribute.LocalName -match 'Logo$' -or
                ($element.LocalName -eq 'SplashScreen' -and $attribute.LocalName -eq 'Image')) {
                $references += $attribute.Value
            }
        }
    }

    foreach ($reference in ($references | Sort-Object -Unique)) {
        $relative = $reference.Trim().Replace('\', '/')
        if ($relative.StartsWith('/') -or
            $relative -match '(^|/)\.\.?(/|$)' -or
            $relative -notmatch '(?i)\.png$') {
            throw "Invalid MSIX visual asset reference: $reference."
        }

        $stem = $relative.Substring(0, $relative.Length - 4)
        $pattern = '^' + [regex]::Escape($stem) +
            '(?:\.(?:scale-\d+|targetsize-\d+|contrast-[a-z0-9-]+|theme-[a-z0-9-]+)(?:_[a-z0-9-]+)*)?\.png$'
        $matches = @($Entries | Where-Object { $_.Replace('\', '/') -match $pattern })
        if ($matches.Count -eq 0) {
            $available = @($Entries | Where-Object { $_ -match '(?i)\.png$' } | Select-Object -First 20)
            throw "The MSIX package is missing the manifest image '$reference' (including qualified variants). Found PNG entries: $($available -join ', ')."
        }
    }
}

function Assert-MsixPackage {
    param(
        [string]$Path,
        [bool]$ExpectSigned
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "The MSIX package was not created: $Path."
    }

    $file = Get-Item -LiteralPath $Path
    if ($file.Length -lt 10MB) {
        throw "The MSIX package is unexpectedly small: $($file.Length) bytes."
    }

    $entries = @(Get-MsixEntryNames -Path $Path)
    foreach ($required in @(
        'AppxManifest.xml',
        'AppxBlockMap.xml',
        '[Content_Types].xml',
        'denuczi_tv.exe',
        'flutter_windows.dll',
        'libmpv-2.dll',
        'data/app.so',
        'data/icudtl.dat',
        'resources.pri',
        'vcruntime140.dll',
        'vcruntime140_1.dll',
        'msvcp140.dll'
    )) {
        if ($entries -notcontains $required) {
            throw "The MSIX package is missing required content: $required."
        }
    }

    $forbidden = @($entries | Where-Object {
        $_ -match '(?i)\.pdb$' -or
        $_ -match '(?i)(^|/)dartjni\.dll$' -or
        $_ -match '(?i)(^|/)jvm\.dll$' -or
        $_ -match '(?i)\.(pfx|p12|pem|key)$'
    })
    if ($forbidden.Count -gt 0) {
        throw "The MSIX package contains forbidden files: $($forbidden -join ', ')."
    }

    $hasSignature = $entries -contains 'AppxSignature.p7x'
    if ($ExpectSigned -and -not $hasSignature) {
        throw 'The QA MSIX package is not signed.'
    }
    if (-not $ExpectSigned -and $hasSignature) {
        throw 'The Store MSIX package must be unsigned.'
    }

    $manifest = Get-MsixManifest -Path $Path
    Assert-MsixVisualAssets -Manifest $manifest -Entries $entries
    $namespaces = [Xml.XmlNamespaceManager]::new($manifest.NameTable)
    $namespaces.AddNamespace('f', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    $namespaces.AddNamespace('rescap', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities')
    $identity = $manifest.SelectSingleNode('/f:Package/f:Identity', $namespaces)
    if ($null -eq $identity) {
        throw 'The MSIX manifest has no Identity element.'
    }
    if ($identity.Name -cne $identityName) {
        throw "Unexpected MSIX identity name: $($identity.Name)."
    }
    if ($identity.Publisher -cne $publisher) {
        throw "Unexpected MSIX publisher: $($identity.Publisher)."
    }
    if ($identity.Version -cne $packageVersion) {
        throw "Unexpected MSIX package version: $($identity.Version)."
    }
    if ($identity.ProcessorArchitecture -cne $architecture) {
        throw "Unexpected MSIX architecture: $($identity.ProcessorArchitecture)."
    }

    $properties = $manifest.SelectSingleNode('/f:Package/f:Properties', $namespaces)
    if ($null -eq $properties) {
        throw 'The MSIX manifest has no Properties element.'
    }
    if ($properties.DisplayName -cne $displayName) {
        throw "Unexpected MSIX display name: $($properties.DisplayName)."
    }
    if ($properties.PublisherDisplayName -cne $publisherDisplayName) {
        throw "Unexpected MSIX publisher display name: $($properties.PublisherDisplayName)."
    }

    $application = $manifest.SelectSingleNode('/f:Package/f:Applications/f:Application', $namespaces)
    if ($null -eq $application) {
        throw 'The MSIX manifest has no Application element.'
    }
    if ($application.Executable -cne 'denuczi_tv.exe') {
        throw "Unexpected MSIX executable: $($application.Executable)."
    }
    if ($application.EntryPoint -cne 'Windows.FullTrustApplication') {
        throw "Unexpected MSIX entry point: $($application.EntryPoint)."
    }

    $capability = $manifest.SelectSingleNode('/f:Package/f:Capabilities/rescap:Capability[@Name="runFullTrust"]', $namespaces)
    if ($null -eq $capability) {
        throw 'The MSIX package must declare the runFullTrust capability.'
    }

    $languages = @($manifest.SelectNodes('/f:Package/f:Resources/f:Resource', $namespaces) | ForEach-Object { $_.Language })
    foreach ($language in @('en-US', 'es-ES')) {
        if ($languages -notcontains $language) {
            throw "The MSIX package is missing the '$language' language resource."
        }
    }

    $manifestSha256 = Get-Sha256String -Text $manifest.OuterXml
    return [pscustomobject]@{
        file = $file.Name
        sizeBytes = $file.Length
        manifestIdentity = $identity.Name
        manifestPublisher = $identity.Publisher
        manifestVersion = $identity.Version
        manifestArchitecture = $identity.ProcessorArchitecture
        manifestSha256 = $manifestSha256
        displayName = $properties.DisplayName
        publisherDisplayName = $properties.PublisherDisplayName
        executable = $application.Executable
        entryPoint = $application.EntryPoint
        capabilities = @('runFullTrust')
        languages = $languages
        signed = $hasSignature
    }
}

function Write-Sha256Sidecar {
    param([string]$Path)

    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(
        "$Path.sha256",
        "$hash  $([IO.Path]::GetFileName($Path))`n",
        [Text.Encoding]::ASCII
    )
    return $hash
}

function Write-JsonFile {
    param(
        [string]$Path,
        $Data
    )

    $json = $Data | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($Path, "$json`n", [Text.UTF8Encoding]::new($false))
}

function Get-AuthenticodeStatus {
    param([string]$Path)

    try {
        return (Get-AuthenticodeSignature -LiteralPath $Path).Status.ToString()
    } catch {
        return 'Unavailable'
    }
}

function Assert-QaCertificatePurposes {
    param([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    # Read the standard X.509 extensions directly. The PowerShell certificate
    # provider exposes EnhancedKeyUsageList as a provider-specific projection,
    # whose elements do not necessarily have a Value property.
    $codeSigningOid = '1.3.6.1.5.5.7.3.3'
    $hasCodeSigning = $false
    $hasDigitalSignature = $false

    foreach ($extension in $Certificate.Extensions) {
        if ($extension -is [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) {
            foreach ($oid in $extension.EnhancedKeyUsages) {
                if ($oid.Value -ceq $codeSigningOid) {
                    $hasCodeSigning = $true
                }
            }
        } elseif ($extension -is [Security.Cryptography.X509Certificates.X509KeyUsageExtension]) {
            if ($extension.KeyUsages -band [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature) {
                $hasDigitalSignature = $true
            }
        }
    }

    if (-not $hasCodeSigning) {
        throw 'The QA certificate does not allow code signing.'
    }
    if (-not $hasDigitalSignature) {
        throw 'The QA certificate does not allow digital signatures.'
    }
}

function New-QaCertificate {
    param(
        [string]$Subject,
        [string]$CerPath
    )

    $certificate = New-SelfSignedCertificate `
        -Type Custom `
        -Subject $Subject `
        -KeyAlgorithm RSA `
        -KeyLength 3072 `
        -HashAlgorithm SHA256 `
        -KeySpec Signature `
        -KeyUsage DigitalSignature `
        -KeyExportPolicy NonExportable `
        -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3') `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -NotAfter (Get-Date).AddDays(365)

    try {
        if ($certificate.Subject -cne $Subject) {
            throw "Unexpected QA certificate subject: $($certificate.Subject)."
        }
        if (-not $certificate.HasPrivateKey) {
            throw 'The QA certificate has no private key.'
        }
        Assert-QaCertificatePurposes -Certificate $certificate

        Export-Certificate -Cert $certificate -FilePath $CerPath | Out-Null
        return $certificate
    } catch {
        try {
            Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($certificate.Thumbprint)" -DeleteKey -Force
        } catch {
            Write-Warning 'Could not remove an incomplete temporary QA certificate.'
        }
        throw
    }
}

function Find-SignTool {
    $roots = @()
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $roots += Join-Path $programFilesX86 'Windows Kits\10\bin'
    }
    $programFiles = [Environment]::GetEnvironmentVariable('ProgramFiles')
    if (-not [string]::IsNullOrWhiteSpace($programFiles)) {
        $roots += Join-Path $programFiles 'Windows Kits\10\bin'
    }

    foreach ($rootPath in $roots) {
        if (-not (Test-Path -LiteralPath $rootPath)) {
            continue
        }
        $direct = Join-Path $rootPath 'x64\signtool.exe'
        if (Test-Path -LiteralPath $direct) {
            return $direct
        }
        $candidates = Get-ChildItem -LiteralPath $rootPath -Directory |
            Where-Object { $_.Name -match '^\d+(\.\d+){3}$' } |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\signtool.exe' }
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    throw 'signtool.exe from the Windows SDK was not found.'
}

function New-QaTrustStore {
    # Windows App Installer checks the local-machine TrustedPeople store for
    # self-signed MSIX package certificates. Never add the QA leaf certificate
    # to a trusted root CA store.
    return [Security.Cryptography.X509Certificates.X509Store]::new(
        [Security.Cryptography.X509Certificates.StoreName]::TrustedPeople,
        [Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
}

function Assert-QaTrustStoreWritable {
    $store = New-QaTrustStore
    try {
        $store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    } catch {
        throw "QA signing requires write access to LocalMachine\TrustedPeople. Run on an administrator-enabled Windows runner. $($_.Exception.Message)"
    } finally {
        $store.Close()
    }
}

function Add-TrustedPeopleCertificate {
    param([string]$CerPath)

    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($CerPath)
    $store = New-QaTrustStore
    $store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    try {
        $matching = $store.Certificates.Find(
            [Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
            $certificate.Thumbprint,
            $false
        )
        if ($matching.Count -ne 0) {
            throw 'The QA certificate is already in LocalMachine\TrustedPeople; refusing to manage an existing trust entry.'
        }

        try {
            $store.Add($certificate)
            $matching = $store.Certificates.Find(
                [Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
                $certificate.Thumbprint,
                $false
            )
            if ($matching.Count -ne 1) {
                throw 'Could not confirm temporary QA trust in LocalMachine\TrustedPeople.'
            }
        } catch {
            # If an error occurs after insertion, remove only the certificate
            # generated for this build. Never remove a pre-existing entry.
            $matching = $store.Certificates.Find(
                [Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
                $certificate.Thumbprint,
                $false
            )
            foreach ($entry in $matching) {
                $store.Remove($entry)
            }
            throw
        }
    } finally {
        $store.Close()
    }
    return $certificate
}

function Remove-TrustedPeopleCertificate {
    param([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    if ($null -eq $Certificate) {
        return
    }
    $store = New-QaTrustStore
    $store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    try {
        $matching = $store.Certificates.Find(
            [Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
            $Certificate.Thumbprint,
            $false
        )
        foreach ($entry in $matching) {
            $store.Remove($entry)
        }
    } finally {
        $store.Close()
    }
}

$pubspecText = Get-Content -LiteralPath $pubspecPath -Raw
$versionMatch = [regex]::Match($pubspecText, '(?m)^version:\s*((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))\+([0-9]+)\s*$')
if (-not $versionMatch.Success) {
    throw 'Expected a stable application version and numeric build number in pubspec.yaml.'
}
$publicVersion = $versionMatch.Groups[1].Value
$buildNumber = [int]$versionMatch.Groups[2].Value
if ($publicVersion -cne $ExpectedPublicVersion) {
    throw "The public application version must remain $ExpectedPublicVersion."
}
if ($buildNumber -ne $ExpectedBuildNumber) {
    throw "The application build number must remain $ExpectedBuildNumber."
}

$versionParts = $publicVersion.Split('.')
$expectedPackageVersion = "1.$($versionParts[1]).$($versionParts[2]).0"
if ($packageVersion -cne $expectedPackageVersion) {
    throw "The MSIX package version must be $expectedPackageVersion."
}

$dependencyParts = $pubspecText -split '(?m)^dev_dependencies:\s*$', 2
if ($dependencyParts.Count -ne 2) {
    throw 'dev_dependencies were not found in pubspec.yaml.'
}
if ($dependencyParts[0] -match '(?m)^  msix:') {
    throw 'msix must remain a dev dependency and must not be bundled with the app.'
}
if ($dependencyParts[1] -notmatch '(?m)^  msix:\s*\^3\.18\.0\s*$') {
    throw 'pubspec.yaml must pin msix ^3.18.0 in dev_dependencies.'
}
$lockText = Get-Content -LiteralPath (Join-Path $root 'pubspec.lock') -Raw
$msixLock = [regex]::Match($lockText, '(?ms)^  msix:\s*$.*?^    version:\s*"([^"]+)"')
if (-not $msixLock.Success -or $msixLock.Groups[1].Value -cne '3.18.0') {
    throw 'pubspec.lock must resolve msix 3.18.0. Run flutter pub get and commit the lockfile.'
}

$config = Read-MsixConfig -Path $pubspecPath
if ($config.Keys.Count -eq 0) {
    throw 'msix_config is missing in pubspec.yaml. The selected source must include the Microsoft Store configuration.'
}
Assert-ConfigValue -Config $config -Key 'identity_name' -Expected $identityName
Assert-ConfigValue -Config $config -Key 'publisher' -Expected $publisher
Assert-ConfigValue -Config $config -Key 'publisher_display_name' -Expected $publisherDisplayName
Assert-ConfigValue -Config $config -Key 'display_name' -Expected $displayName
Assert-ConfigValue -Config $config -Key 'msix_version' -Expected $packageVersion
Assert-ConfigValue -Config $config -Key 'architecture' -Expected $architecture
Assert-ConfigValue -Config $config -Key 'build_windows' -Expected 'false'
Assert-ConfigValue -Config $config -Key 'languages' -Expected 'en-US,es-ES'
Assert-ConfigValue -Config $config -Key 'capabilities' -Expected 'runFullTrust'
Assert-ConfigValue -Config $config -Key 'output_path' -Expected $expectedOutputPath
Assert-ConfigValue -Config $config -Key 'output_name' -Expected $expectedOutputName
if ($config.Keys -contains 'store' -and ([string]$config['store']).ToLowerInvariant() -eq 'true') {
    throw 'msix_config must not store store: true. The --store flag is used only for the Store package.'
}
foreach ($secretKey in @('certificate_path', 'certificate_password')) {
    if ($config.Keys -contains $secretKey) {
        throw "msix_config must not contain $secretKey. QA certificates are created temporarily by the packager."
    }
}
$logoPath = Join-Path $root ([string]$config['logo_path'])
if (-not (Test-Path -LiteralPath $logoPath -PathType Leaf)) {
    throw 'The configured MSIX logo does not exist.'
}

$sourceCommit = & git -C $root rev-parse HEAD
$gitExitCode = $LASTEXITCODE
if ($gitExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($sourceCommit)) {
    throw "Could not determine the application source commit (git exit code: $gitExitCode)."
}
$sourceCommit = $sourceCommit.Trim()
if ($sourceCommit -notmatch '^[0-9a-f]{40}$') {
    throw 'The application source commit is not a full SHA-1.'
}
$expectedCommit = $ExpectedSourceCommit.Trim()
if (-not [string]::IsNullOrWhiteSpace($expectedCommit)) {
    if ($expectedCommit -notmatch '^[0-9a-f]{40}$') {
        throw 'ExpectedSourceCommit is not a full SHA-1.'
    }
    if ($sourceCommit -cne $expectedCommit) {
        throw "The packaging script and application source are not from the same revision ($sourceCommit vs $expectedCommit)."
    }
}
$status = & git -C $root status --porcelain
$sourceDirty = -not [string]::IsNullOrWhiteSpace(($status -join "`n"))
$sourceDescribe = & git -C $root describe --always --tags --dirty
$gitExitCode = $LASTEXITCODE
if ($gitExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($sourceDescribe)) {
    throw "Could not describe the application source revision (git exit code: $gitExitCode)."
}
$sourceDescribe = $sourceDescribe.Trim()
$sourceRef = [Environment]::GetEnvironmentVariable('SOURCE_REF')
if ([string]::IsNullOrWhiteSpace($sourceRef)) {
    $sourceRef = $sourceDescribe
}

$outputRoot = [IO.Path]::GetFullPath((Join-Path $root $expectedOutputPath))
$buildRoot = [IO.Path]::GetFullPath((Join-Path $root 'build'))
if (-not $outputRoot.StartsWith("$buildRoot$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The configured MSIX output path must stay under build/.'
}
$qaDirectory = Join-Path $outputRoot 'qa'
if (Test-Path -LiteralPath $outputRoot) {
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $outputRoot, $qaDirectory | Out-Null

$toolchain = (Resolve-Path -LiteralPath (Join-Path $root 'packaging\windows\flutter-toolchain.cmake')).Path
$env:CMAKE_TOOLCHAIN_FILE = $toolchain
$flutterVersion = 'unknown'
try {
    $flutterInfo = (& flutter --version --machine 2>$null | ConvertFrom-Json)
    if ($flutterInfo.frameworkVersion) {
        $flutterVersion = [string]$flutterInfo.frameworkVersion
    }
} catch {
    $flutterVersion = 'unknown'
}
$crtPath = Get-ReleaseCrtPath

# Check trust-store permissions before the expensive Flutter Windows build.
Assert-QaTrustStoreWritable

$qaCertificate = $null
$trustedCertificate = $null
$temporaryDirectory = $null

try {
    Push-Location -LiteralPath $root
    try {
        if (Test-Path -LiteralPath (Join-Path $root 'build\windows')) {
            Remove-Item -LiteralPath (Join-Path $root 'build\windows') -Recurse -Force
        }
        & flutter build windows --release "--dart-define=$storeBuildDefine"
        if ($LASTEXITCODE -ne 0) {
            throw 'The Windows Store build failed.'
        }
    } finally {
        Pop-Location
    }

    foreach ($name in @('denuczi_tv.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'data\app.so', 'data\icudtl.dat')) {
        if (-not (Test-Path -LiteralPath (Join-Path $bundle $name) -PathType Leaf)) {
            throw "The release bundle is incomplete: missing $name."
        }
    }
    Get-ChildItem -LiteralPath $bundle -Recurse -File -Filter '*.pdb' | Remove-Item -Force
    Assert-BundlePolicy -Bundle $bundle

    $exe = Get-Item -LiteralPath (Join-Path $bundle 'denuczi_tv.exe')
    $exeInfo = $exe.VersionInfo
    $actualVersion = "$($exeInfo.FileMajorPart).$($exeInfo.FileMinorPart).$($exeInfo.FileBuildPart).$($exeInfo.FilePrivatePart)"
    if ($actualVersion -ne "$publicVersion.$buildNumber") {
        throw 'The release executable is stale: its version differs from pubspec.yaml.'
    }
    Assert-PeX64 -Path $exe.FullName
    $runtimeVersion = Copy-ReleaseCrt -Bundle $bundle -CrtPath $crtPath
    Assert-ReleaseCrt -Bundle $bundle -CrtPath $crtPath -ExpectedVersion $runtimeVersion
    $bundleSnapshot = Get-BundleProtectedSnapshot -Bundle $bundle

    Invoke-MsixCreate -Root $root -OutputPath $outputRoot -OutputName $storeName -Store
    Assert-BundleUnchanged -Bundle $bundle -Snapshot $bundleSnapshot
    Assert-BundlePolicy -Bundle $bundle
    $storeMsix = Join-Path $outputRoot "$storeName.msix"
    $storeManifest = Assert-MsixPackage -Path $storeMsix -ExpectSigned $false
    $storeHash = Write-Sha256Sidecar -Path $storeMsix
    $storeSignature = 'NotSigned'
    $storeAuthenticodeStatus = Get-AuthenticodeStatus -Path $storeMsix

    # Keep the QA package byte-for-byte identical to the Store package until
    # signing. A second msix:create run could regenerate or change resources.
    $qaMsix = Join-Path $qaDirectory "$qaName.msix"
    Copy-Item -LiteralPath $storeMsix -Destination $qaMsix -ErrorAction Stop
    $unsignedQaHash = (Get-FileHash -LiteralPath $qaMsix -Algorithm SHA256).Hash
    $unsignedStoreHash = (Get-FileHash -LiteralPath $storeMsix -Algorithm SHA256).Hash
    if ($unsignedQaHash -cne $unsignedStoreHash) {
        throw 'The unsigned QA copy differs from the Store package.'
    }
    $qaManifest = Assert-MsixPackage -Path $qaMsix -ExpectSigned $false

    $temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) "denuczitv-msix-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $temporaryDirectory | Out-Null
    $cerPath = Join-Path $temporaryDirectory 'qa-signing.cer'
    $qaCertificate = New-QaCertificate -Subject $publisher -CerPath $cerPath

    $signTool = Find-SignTool
    $signOutput = & $signTool sign /fd SHA256 /s My /sha1 $qaCertificate.Thumbprint $qaMsix 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "signtool could not sign the QA package: $($signOutput -join ' ')"
    }

    $trustedCertificate = Add-TrustedPeopleCertificate -CerPath $cerPath
    try {
        Write-Output "QA certificate temporarily trusted in LocalMachine\TrustedPeople: $($qaCertificate.Thumbprint)"
        $verifyOutput = & $signTool verify /pa /v $qaMsix 2>&1
        $verifyExitCode = $LASTEXITCODE
        if ($verifyExitCode -ne 0) {
            throw "signtool could not verify the QA package with temporary LocalMachine\TrustedPeople trust (exit code: $verifyExitCode): $($verifyOutput -join ' ')"
        }
        $qaAuthenticodeStatus = Get-AuthenticodeStatus -Path $qaMsix
    } finally {
        Remove-TrustedPeopleCertificate -Certificate $trustedCertificate
        $trustedCertificate = $null
    }

    $qaManifest = Assert-MsixPackage -Path $qaMsix -ExpectSigned $true
    $qaHash = Write-Sha256Sidecar -Path $qaMsix
    $qaPublicCertificate = Join-Path $qaDirectory "$qaName.cer"
    Copy-Item -LiteralPath $cerPath -Destination $qaPublicCertificate -Force
    $publicCertificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($qaPublicCertificate)
    if ($publicCertificate.Subject -cne $publisher) {
        throw "Unexpected public QA certificate subject: $($publicCertificate.Subject)."
    }
    # The QA certificate is trusted only temporarily during verification.
    $qaSignature = 'VerifiedWithTemporaryMachineTrust'

    if ($storeManifest.manifestSha256 -cne $qaManifest.manifestSha256) {
        throw 'The Store and QA packages contain different manifests.'
    }
    $storePayload = Get-MsixPayloadHashes -Path $storeMsix
    $qaPayload = Get-MsixPayloadHashes -Path $qaMsix
    Assert-MsixPayloadMatches -Store $storePayload -Qa $qaPayload
    Assert-MsixCrtPayload -Hashes $storePayload -CrtPath $crtPath -Label 'Store'
    Assert-MsixCrtPayload -Hashes $qaPayload -CrtPath $crtPath -Label 'QA'
    $payloadSha256 = Get-HashDictionaryDigest -Hashes $storePayload
    $storeHashAfterQaSigning = (Get-FileHash -LiteralPath $storeMsix -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($storeHashAfterQaSigning -cne $storeHash) {
        throw 'Signing the QA copy modified the unsigned Store package.'
    }

    $leaks = @(Get-ChildItem -LiteralPath $outputRoot -Recurse -File | Where-Object {
        $_.Extension -in @('.pfx', '.p12', '.pem', '.key')
    })
    if ($leaks.Count -gt 0) {
        throw 'Private key material was found in the MSIX output directory.'
    }

    $commonInfo = [ordered]@{
        applicationVersion = $publicVersion
        buildNumber = $buildNumber
        publicVersion = "$publicVersion+$buildNumber"
        packageVersion = $packageVersion
        identityName = $identityName
        publisher = $publisher
        publisherDisplayName = $publisherDisplayName
        displayName = $displayName
        architecture = $architecture
        sourceRef = $sourceRef
        sourceCommit = $sourceCommit
        sourceDescribe = $sourceDescribe
        sourceDirty = $sourceDirty
        sourceCommitVerified = $true
        storeBuild = $true
        storeBuildDefine = $storeBuildDefine
        flutterVersion = $flutterVersion
        msixToolVersion = '3.18.0'
        runtimeVersion = $runtimeVersion
        runtimeMatchesOfficial = $true
        payloadMatched = $true
        payloadSha256 = $payloadSha256
        qaSigningMethod = 'signtool-certificate-store'
        privateKeyExported = $false
        pdbExcluded = $true
        jniExcluded = $true
        bundleIntegrity = [ordered]@{
            protectedFiles = $bundleSnapshot.Count
            verifiedBeforeAndAfterPackaging = $true
            payloadMatched = $true
            payloadSha256 = $payloadSha256
        }
        createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }

    $storeInfo = [ordered]@{}
    foreach ($key in $commonInfo.Keys) {
        $storeInfo[$key] = $commonInfo[$key]
    }
    $storeInfo['kind'] = 'store'
    $storeInfo['package'] = $storeManifest.file
    $storeInfo['sizeBytes'] = $storeManifest.sizeBytes
    $storeInfo['sha256'] = $storeHash
    $storeInfo['signatureStatus'] = $storeSignature
    $storeInfo['authenticodeStatus'] = $storeAuthenticodeStatus
    $storeInfo['signed'] = $false
    $storeInfo['manifest'] = $storeManifest
    $storeInfo['publicCertificate'] = $null
    Write-JsonFile -Path (Join-Path $outputRoot "$storeName.build-info.json") -Data $storeInfo

    $qaInfo = [ordered]@{}
    foreach ($key in $commonInfo.Keys) {
        $qaInfo[$key] = $commonInfo[$key]
    }
    $qaInfo['kind'] = 'qa'
    $qaInfo['package'] = $qaManifest.file
    $qaInfo['sizeBytes'] = $qaManifest.sizeBytes
    $qaInfo['sha256'] = $qaHash
    $qaInfo['signatureStatus'] = $qaSignature
    $qaInfo['authenticodeStatus'] = $qaAuthenticodeStatus
    $qaInfo['signed'] = $true
    $qaInfo['manifest'] = $qaManifest
    $qaInfo['publicCertificate'] = [IO.Path]::GetFileName($qaPublicCertificate)
    $qaInfo['certificateSubject'] = $publicCertificate.Subject
    $qaInfo['certificateThumbprint'] = $publicCertificate.Thumbprint
    $qaInfo['certificateStore'] = 'CurrentUser\My'
    $qaInfo['verificationTrustStore'] = 'LocalMachine\TrustedPeople'
    $qaInfo['trustTemporary'] = $true
    $qaInfo['certificateNotAfter'] = $publicCertificate.NotAfter.ToUniversalTime().ToString('o')
    Write-JsonFile -Path (Join-Path $qaDirectory "$qaName.build-info.json") -Data $qaInfo

    Write-Output "Store MSIX: $storeMsix"
    Write-Output "Store SHA256: $storeHash"
    Write-Output "QA MSIX: $qaMsix"
    Write-Output "QA SHA256: $qaHash"
} finally {
    if ($null -ne $trustedCertificate) {
        try {
            Remove-TrustedPeopleCertificate -Certificate $trustedCertificate
        } catch {
            Write-Warning 'Could not remove the temporary QA certificate from LocalMachine\TrustedPeople.'
        }
    }
    if ($null -ne $qaCertificate) {
        try {
            Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($qaCertificate.Thumbprint)" -DeleteKey -Force
        } catch {
            Write-Warning 'Could not remove the temporary QA certificate and its private key.'
        }
    }
    if ($null -ne $temporaryDirectory -and (Test-Path -LiteralPath $temporaryDirectory)) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
    if (Test-Path -LiteralPath $bundle) {
        try {
            Copy-ReleaseCrt -Bundle $bundle -CrtPath $crtPath | Out-Null
        } catch {
            Write-Warning 'Could not restore the Visual C++ runtime in the build bundle.'
        }
    }
}
