#requires -Version 5.1

function Assert-RuntimeName([string]$Name, [string]$Pattern) {
    if ($Name -notmatch $Pattern -or $Name -match '\.\.|^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])\.') {
        throw "Invalid runtime dependency name: $Name"
    }
}

function Get-RegularRuntimeItem([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Runtime dependency is a reparse point: $Path"
    }
    return $item
}

function Get-RuntimeTreeDigest([string]$Root) {
    $item = Get-RegularRuntimeItem $Root
    if (!$item.PSIsContainer) { throw "Expected runtime directory: $Root" }
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($item.FullName)
    $files = while ($pending.Count) {
        foreach ($entry in Get-ChildItem -LiteralPath ($pending.Pop()) -Force) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Runtime data contains a reparse point: $($entry.FullName)"
            }
            if ($entry.PSIsContainer) { $pending.Push($entry.FullName) }
            else { $entry }
        }
    }
    if (!$files) { throw "Empty runtime directory: $Root" }
    $rows = foreach ($file in $files | Sort-Object FullName) {
        $relative = $file.FullName.Substring($item.FullName.Length + 1)
        '{0}|{1}|{2}' -f $relative, $file.Length, (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    }
    return Get-RuntimeDigest ($rows -join [char]10)
}

function Get-RuntimeDigest([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) |
            ForEach-Object { $_.ToString('x2') })
    } finally { $sha.Dispose() }
}

function Get-RuntimeClosure($Files, [string[]]$Roots) {
    $visited = @{}
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    foreach ($name in $Roots) { $pending.Push($name) }
    while ($pending.Count) {
        $name = $pending.Pop()
        if ($visited.ContainsKey($name)) { continue }
        if (!$Files.ContainsKey($name)) { throw "Unrecorded runtime dependency: $name" }
        $visited[$name] = $true
        foreach ($import in $Files[$name].BundledImports) { $pending.Push($import) }
    }
    return $visited.Keys | Sort-Object
}

function Get-Evox2RuntimeDependencies {
    [CmdletBinding()]
    param([string]$BinDir, [string]$BuildDir, [string]$Backend, [object]$Runtime, [bool]$Built)

    $ErrorActionPreference = 'Stop'
    $cache = @{}
    $cacheFile = Join-Path $BuildDir 'CMakeCache.txt'
    if ($Built -or (Test-Path -LiteralPath $cacheFile -PathType Leaf)) {
        foreach ($line in Get-Content -LiteralPath $cacheFile) {
            if ($line -match '^([A-Z0-9_]+):[^=]+=(.*)$') { $cache[$Matches[1]] = $Matches[2] }
        }
    }
    $inspector = Get-Command dumpbin.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $dumpbin = if ($inspector) { $inspector.Source } else {
        $programFiles = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        Join-Path $programFiles 'Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe'
    }
    if (!(Test-Path -LiteralPath $dumpbin -PathType Leaf)) { throw 'VS dumpbin.exe is required to inventory PE dependencies.' }

    $folder = Get-RegularRuntimeItem $BinDir
    if (!$folder.PSIsContainer) { throw "Expected binary directory: $BinDir" }
    $images = @(Get-ChildItem -LiteralPath $BinDir -File -Force |
        Where-Object { $_.Extension -ieq '.dll' -or $_.Name -match '^llama-(cli|bench|server)\.exe$' } |
        Sort-Object Name)
    $files = @{}
    $external = @{}
    $sdk = @($Runtime.RuntimeDlls | ForEach-Object { $_.Name })
    if ($cache['GGML_OPENMP_FETCH'] -eq 'ON') { $sdk += 'libomp.dll' }
    foreach ($image in $images) {
        Assert-RuntimeName $image.Name '^[a-z0-9_-][a-z0-9_.+-]*\.(dll|exe)$'
        $null = Get-RegularRuntimeItem $image.FullName
        $category = if ($sdk -contains $image.Name) { 'BundledRuntime' } else { 'Product' }
        $files[$image.Name] = [ordered]@{
            Name = $image.Name
            Kind = $category
            Sha256 = (Get-FileHash -LiteralPath $image.FullName).Hash.ToLowerInvariant()
            BundledImports = @()
            ExternalImports = @()
        }
    }
    foreach ($image in $images) {
        $output = @(& $dumpbin /NOLOGO /DEPENDENTS $image.FullName)
        if ($LASTEXITCODE -ne 0 -or !($output -match '^Dump of file ')) { throw "PE inspection failed: $($image.Name)" }
        $imports = @(foreach ($line in $output) {
            if ($line -match '^\s+([a-z0-9_.+-]+\.dll)\s*$') { $Matches[1].ToLowerInvariant() }
        })
        foreach ($name in $imports | Sort-Object -Unique) {
            Assert-RuntimeName $name '^[a-z0-9_-][a-z0-9_.+-]*\.dll$'
            if ($files.ContainsKey($name)) {
                $files[$image.Name].BundledImports += $name
            } else {
                if ($name -match '^(llama|ggml|mtmd)([-.]|$)' -or $sdk -contains $name) {
                    throw "Missing bundled import $name for $($image.Name)"
                }
                $files[$image.Name].ExternalImports += $name
                if (!$external.ContainsKey($name)) {
                    $candidate = Join-Path ([Environment]::SystemDirectory) $name
                    $observed = if (Test-Path -LiteralPath $candidate -PathType Leaf) { Get-Item -LiteralPath $candidate }
                    $record = [ordered]@{
                        Name = $name; ObservedPath = $null; FileVersion = $null; Sha256 = $null
                        Evidence = 'ImportNameOnly'
                    }
                    if ($observed) {
                        $record.ObservedPath = $observed.FullName
                        $record.FileVersion = $observed.VersionInfo.FileVersion
                        $record.Sha256 = (Get-FileHash -LiteralPath $candidate).Hash.ToLowerInvariant()
                        $record.Evidence = 'SystemDirectoryCandidate'
                    }
                    $external[$name] = $record
                }
            }
        }
    }
    $required = @()
    $cpu = @()
    $dynamic = $cache['GGML_BACKEND_DL'] -eq 'ON'
    if ($dynamic) {
        if ($cache['GGML_VULKAN'] -eq 'ON') { $required += 'ggml-vulkan.dll' }
        if ($cache['GGML_HIP'] -eq 'ON') { $required += 'ggml-hip.dll' }
        if ($cache['GGML_CPU'] -ne 'OFF') {
            if ($cache['GGML_CPU_ALL_VARIANTS'] -eq 'ON') {
                $cpu = @($files.Keys | Where-Object { $_ -match '^ggml-cpu-.*\.dll$' } | Sort-Object)
                if (!$cpu.Count) { throw 'No CPU variant plugins were built.' }
            } else { $required += 'ggml-cpu.dll' }
        }
    }
    $required += $sdk
    $required = @($required | Sort-Object -Unique)
    $entries = @(foreach ($image in $images | Where-Object Extension -eq '.exe') {
        [ordered]@{ Name = $image.Name; Required = @(Get-RuntimeClosure $files (@($image.Name) + $required)) }
    })
    $trees = @(foreach ($tree in $Runtime.RuntimeDataTrees) {
        Assert-RuntimeName $tree.Name '^(rocblas|hipblaslt)$'
        $digest = Get-RuntimeTreeDigest (Join-Path $BinDir $tree.Name)
        if ($digest -ne $tree.Destination.DigestSha256) { throw "Runtime data changed: $($tree.Name)" }
        [ordered]@{ Name = $tree.Name; Sha256 = $digest; Target = $tree.Target }
    })
    [ordered]@{
        Version = 1
        Provenance = if ($Built) { 'BuildCompleted' } else { 'Observed' }
        Inspection = 'PEImportsAndConfiguredBackends'
        Backend = $Backend
        Files = @($files.Values | Sort-Object { $_.Name })
        ConfigurationRequired = $required
        CpuVariants = $cpu
        Executables = $entries
        External = @($external.Values | Sort-Object { $_.Name })
        DataTrees = $trees
    }
}

function Test-Evox2RuntimeDependencies {
    [CmdletBinding()]
    param([string]$Executable, [object]$Manifest)

    $ErrorActionPreference = 'Stop'
    $extension = $Manifest.RuntimeDependencies
    $bin = Split-Path -Parent $Executable
    $exeName = [IO.Path]::GetFileName($Executable)
    $verified = @()
    $digestRows = @()
    try {
        if (!$extension -or $extension.Version -isnot [int] -or $extension.Version -ne 1 -or
            $extension.Backend -cnotin @('Vulkan', 'ROCm') -or $extension.Backend -cne $Manifest.Backend -or
            $extension.Provenance -cnotin @('BuildCompleted', 'Observed') -or
            $extension.Inspection -cne 'PEImportsAndConfiguredBackends') { throw 'Invalid runtime dependency header.' }
        foreach ($field in 'Files','Executables','ConfigurationRequired','CpuVariants','External','DataTrees') {
            if ($extension.$field -isnot [array]) { throw "Invalid runtime dependency collection: $field" }
        }
        $directory = Get-RegularRuntimeItem $bin
        if (!$directory.PSIsContainer) { throw 'Invalid binary directory.' }
        $files = @{}
        foreach ($file in $extension.Files) {
            Assert-RuntimeName $file.Name '^[a-z0-9_-][a-z0-9_.+-]*\.(dll|exe)$'
            if ($files.ContainsKey($file.Name) -or $file.Sha256 -isnot [string] -or $file.Sha256 -notmatch '\A[0-9a-f]{64}\z' -or
                $file.Kind -cnotin @('Product','BundledRuntime') -or
                $file.BundledImports -isnot [array] -or $file.ExternalImports -isnot [array]) {
                throw "Invalid or duplicated runtime file: $($file.Name)"
            }
            $files[$file.Name] = $file
        }
        $external = @{}
        foreach ($entry in $extension.External) {
            Assert-RuntimeName $entry.Name '^[a-z0-9_-][a-z0-9_.+-]*\.dll$'
            if ($external.ContainsKey($entry.Name) -or $files.ContainsKey($entry.Name) -or
                $entry.Evidence -cnotin @('SystemDirectoryCandidate','ImportNameOnly') -or
                ($entry.Evidence -eq 'SystemDirectoryCandidate' -and
                    ($entry.ObservedPath -isnot [string] -or $entry.ObservedPath -notmatch '\A[A-Za-z]:[\\/]' -or
                     $entry.ObservedPath -match '(?:^|[\\/])\.\.?([\\/]|$)' -or
                     $entry.Sha256 -isnot [string] -or $entry.Sha256 -notmatch '\A[0-9a-f]{64}\z' -or
                     [IO.Path]::GetFileName($entry.ObservedPath) -ine $entry.Name)) -or
                ($entry.Evidence -eq 'ImportNameOnly' -and ($entry.ObservedPath -or $entry.Sha256))) {
                throw "Invalid external runtime information: $($entry.Name)"
            }
            $external[$entry.Name] = $true
        }
        foreach ($file in $extension.Files) {
            $imports = @($file.BundledImports) + @($file.ExternalImports)
            if (@($imports | Sort-Object -Unique).Count -ne $imports.Count) { throw "Duplicate imports: $($file.Name)" }
            foreach ($name in $file.BundledImports) {
                if ($name -isnot [string] -or !$files.ContainsKey($name) -or $name -notlike '*.dll') {
                    throw "Invalid bundled import: $name"
                }
            }
            foreach ($name in $file.ExternalImports) {
                if ($name -isnot [string] -or !$external.ContainsKey($name)) { throw "Invalid external import: $name" }
            }
        }
        $entries = @{}
        foreach ($entry in $extension.Executables) {
            Assert-RuntimeName $entry.Name '^llama-(cli|bench|server)\.exe$'
            if ($entries.ContainsKey($entry.Name) -or $entry.Required -isnot [array]) { throw "Invalid executable entry: $($entry.Name)" }
            $expected = @(Get-RuntimeClosure $files (@($entry.Name) + $extension.ConfigurationRequired))
            if ($expected.Count -ne $entry.Required.Count -or
                ($expected -join '|') -ine (@($entry.Required | Sort-Object) -join '|')) {
                throw "Invalid executable dependency closure: $($entry.Name)"
            }
            $entries[$entry.Name] = $entry.Required
        }
        if (!$entries.ContainsKey($exeName) -or !$entries.ContainsKey('llama-cli.exe')) { throw "Missing dependency entry for $exeName or llama-cli.exe." }
        foreach ($name in $files.Keys | Where-Object { $_ -like '*.exe' }) {
            if (!$entries.ContainsKey($name)) { throw "Missing executable entry: $name" }
        }
        foreach ($list in 'ConfigurationRequired','CpuVariants') {
            $names = $extension.$list
            if (@($names | Sort-Object -Unique).Count -ne $names.Count) { throw "Duplicate names in $list" }
            foreach ($name in $names) {
                if ($name -isnot [string] -or $name -notlike '*.dll' -or !$files.ContainsKey($name)) { throw "Invalid $list entry: $name" }
                if ($list -eq 'CpuVariants' -and $name -notmatch '^ggml-cpu-.*\.dll$') { throw "Invalid CPU variant: $name" }
            }
        }
        $present = @{}
        foreach ($item in Get-ChildItem -LiteralPath $bin -File -Force | Where-Object { $_.Extension -ieq '.dll' -or $_.Name -match '^llama-(cli|bench|server)\.exe$' }) {
            if (!$files.ContainsKey($item.Name)) { throw "Unrecorded runtime image: $($item.Name)" }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Runtime image is a reparse point: $($item.Name)" }
            $present[$item.Name] = $true
            if ($item.Extension -ieq '.exe' -and $item.Name -ine $exeName) { continue }
            $hash = (Get-FileHash -LiteralPath $item.FullName).Hash.ToLowerInvariant()
            if ($hash -ne $files[$item.Name].Sha256) { throw "Runtime artifact hash mismatch: $($item.Name)" }
            $verified += [pscustomobject]@{ Name = $item.Name; Path = $item.FullName; Sha256 = $hash; LengthBytes = $item.Length }
            $digestRows += "$($item.Name.ToLowerInvariant())=$hash"
        }
        $roots = @($entries[$exeName]) + @($present.Keys | Where-Object { $_ -like '*.dll' })
        foreach ($name in Get-RuntimeClosure $files $roots) {
            if (!$present.ContainsKey($name)) { throw "Missing required runtime artifact: $name" }
        }
        if ($extension.CpuVariants.Count -and !($extension.CpuVariants | Where-Object { $present.ContainsKey($_) })) {
            throw 'No recorded CPU variant is present.'
        }
        $trees = @{}
        if ($extension.Backend -ne 'ROCm' -and $extension.DataTrees.Count) { throw 'Unexpected ROCm data trees for this backend.' }
        foreach ($entry in $extension.DataTrees) {
            Assert-RuntimeName $entry.Name '^(rocblas|hipblaslt)$'
            if ($trees.ContainsKey($entry.Name) -or $entry.Sha256 -notmatch '\A[0-9a-f]{64}\z' -or
                $entry.Target -notmatch '\Agfx[0-9a-f]+\z') { throw "Invalid runtime tree: $($entry.Name)" }
            $trees[$entry.Name] = $entry
            $root = Join-Path $bin $entry.Name
            $actual = Get-RuntimeTreeDigest $root
            if ($actual -ne $entry.Sha256 -or
                !(Test-Path -LiteralPath (Join-Path $root "library\$($entry.Target)") -PathType Container)) {
                throw "Runtime tree verification failed: $($entry.Name)"
            }
            $digestRows += "$($entry.Name)/=$actual"
        }
        if ($Manifest.Runtime.RuntimePolicy.Verification -eq 'DllAndRuntimeDataHashesVerified') {
            foreach ($tree in $Manifest.Runtime.RuntimeDataTrees) {
                if (!$trees.ContainsKey($tree.Name) -or $trees[$tree.Name].Sha256 -ne $tree.Destination.DigestSha256 -or
                    $trees[$tree.Name].Target -ne $tree.Target) { throw "Missing or inconsistent ROCm runtime tree: $($tree.Name)" }
            }
            foreach ($dll in $Manifest.Runtime.RuntimeDlls) {
                if (!$files.ContainsKey($dll.Name) -or $extension.ConfigurationRequired -notcontains $dll.Name -or
                    $files[$dll.Name].Sha256 -ne $dll.Destination.Sha256) { throw "Missing or inconsistent ROCm runtime DLL: $($dll.Name)" }
            }
        }
        $status = if ($extension.Provenance -eq 'BuildCompleted') { 'Verified' } else { 'Unverified' }
        [pscustomobject]@{
            Status = $status; Scope = 'RuntimeDependenciesV1'; Provenance = $extension.Provenance
            Digest = Get-RuntimeDigest (($digestRows | Sort-Object) -join [char]10)
            Artifacts = $verified; Issues = @()
        }
    } catch {
        [pscustomobject]@{
            Status = 'Mismatch'; Scope = 'RuntimeDependenciesV1'; Provenance = $null
            Digest = $null; Artifacts = @(); Issues = @($_.Exception.Message)
        }
    }
}

Export-ModuleMember -Function Get-Evox2RuntimeDependencies, Test-Evox2RuntimeDependencies
