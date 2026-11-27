#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Check {
    param(
        [string] $Executable,
        [string[]] $Arguments
    )

    $command = Get-Command $Executable -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (!$command) { throw "$Executable is missing from PATH." }
    # Capture native diagnostics without treating stderr itself as a failed check.
    $ErrorActionPreference = 'Continue'
    $output = & $command.Source @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $detail = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        if (!$detail) { $detail = "Exited with code $code." }
        throw $detail
    }
}

$project = Split-Path -Parent $PSScriptRoot
$build = Join-Path ([IO.Path]::GetTempPath()) ("pba-check-{0}.rbxlx" -f [guid]::NewGuid())
$step = 'project directory'
$pushed = $false
$result = 0

try {
    Push-Location -LiteralPath $project
    $pushed = $true

    $step = 'Rojo build'
    Invoke-Check -Executable 'rojo.exe' -Arguments @('build', 'default.project.json', '--output', $build)

    $step = 'luau-analyze'
    $sources = @(Get-ChildItem -Path 'src/shared', 'tests' -Recurse -File -Filter '*.luau' |
        Sort-Object FullName | ForEach-Object FullName)
    if ($sources.Count -eq 0) { throw 'No shared modules or tests were found.' }
    Invoke-Check -Executable 'luau-analyze.exe' -Arguments $sources

    $step = 'Lune suite discovery'
    $suites = @(Get-ChildItem -LiteralPath 'tests' -File -Filter '*.luau' | Sort-Object Name)
    if ($suites.Count -eq 0) { throw 'No suites were found in tests/.' }
    foreach ($suite in $suites) {
        $step = "Lune tests/$($suite.Name)"
        Invoke-Check -Executable 'lune.exe' -Arguments @('run', $suite.FullName)
    }
    [Console]::WriteLine("PASS: Rojo + luau-analyze + $($suites.Count)/$($suites.Count) Lune suites")
}
catch {
    [Console]::Error.WriteLine("FAIL: $step")
    [Console]::Error.WriteLine($_.Exception.Message)
    $result = 1
}
finally {
    if ($pushed) { Pop-Location }
    if (Test-Path -LiteralPath $build -PathType Leaf) {
        Remove-Item -LiteralPath $build -ErrorAction SilentlyContinue
    }
}

exit $result
