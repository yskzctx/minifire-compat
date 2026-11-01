param([string]$SdkRoot=$env:ANDROID_SDK_ROOT)
$ErrorActionPreference='Stop'
if (-not $SdkRoot) { $SdkRoot=$env:ANDROID_HOME }
if (-not $SdkRoot) { throw 'Set ANDROID_SDK_ROOT or pass -SdkRoot.' }
$TaskProject=Split-Path -Parent $MyInvocation.MyCommand.Path
$TaskCmake=Join-Path $SdkRoot 'cmake/3.22.1/bin/cmake.exe'
$TaskNinja=Join-Path $SdkRoot 'cmake/3.22.1/bin/ninja.exe'
$TaskToolchain=Join-Path $SdkRoot 'ndk/26.3.11579264/build/cmake/android.toolchain.cmake'
foreach($TaskFile in @($TaskCmake,$TaskNinja,$TaskToolchain)) { if(-not (Test-Path -LiteralPath $TaskFile)) { throw "Missing tool: $TaskFile" } }
& $TaskCmake -S $TaskProject -B (Join-Path $TaskProject 'build') -G Ninja "-DCMAKE_TOOLCHAIN_FILE=$TaskToolchain" '-DANDROID_ABI=arm64-v8a' '-DANDROID_PLATFORM=android-26' '-DCMAKE_BUILD_TYPE=Release' "-DCMAKE_MAKE_PROGRAM=$TaskNinja"
if($LASTEXITCODE -ne 0){throw 'CMake configuration failed'}
& $TaskCmake --build (Join-Path $TaskProject 'build') --parallel 4
if($LASTEXITCODE -ne 0){throw 'Native build failed'}
& uv run python (Join-Path $TaskProject 'tools/package.py') (Join-Path $TaskProject '../../outputs/Minifire-Zygisk-No-LSP-Scope-0.5.4-candidate.zip')
if($LASTEXITCODE -ne 0){throw 'Packaging failed'}
