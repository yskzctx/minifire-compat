param([string]$SdkRoot=$env:ANDROID_SDK_ROOT)
$ErrorActionPreference='Stop'
if(-not $SdkRoot){$SdkRoot=Join-Path $env:USERPROFILE 'Android/Sdk'}
$TaskProject=Split-Path -Parent $MyInvocation.MyCommand.Path
$TaskCmake=Join-Path $SdkRoot 'cmake/3.22.1/bin/cmake.exe'
$TaskNinja=Join-Path $SdkRoot 'cmake/3.22.1/bin/ninja.exe'
$TaskToolchain=Join-Path $SdkRoot 'ndk/26.3.11579264/build/cmake/android.toolchain.cmake'
& $TaskCmake -S $TaskProject -B (Join-Path $TaskProject 'build') -G Ninja "-DCMAKE_TOOLCHAIN_FILE=$TaskToolchain" '-DANDROID_ABI=arm64-v8a' '-DANDROID_PLATFORM=android-26' '-DANDROID_STL=c++_static' '-DCMAKE_BUILD_TYPE=Release' "-DCMAKE_MAKE_PROGRAM=$TaskNinja"
if($LASTEXITCODE -ne 0){throw 'CMake configure failed'}
& $TaskCmake --build (Join-Path $TaskProject 'build') --parallel 4
if($LASTEXITCODE -ne 0){throw 'Native module build failed'}
$TaskStrip=Join-Path $SdkRoot 'ndk/26.3.11579264/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe'
& $TaskStrip --strip-unneeded -o (Join-Path $TaskProject 'build/libminifire_minimal.release.so') (Join-Path $TaskProject 'build/libminifire_minimal.so')
if($LASTEXITCODE -ne 0){throw 'Release binary strip failed'}
& uv run python (Join-Path $TaskProject 'tools/package.py') (Join-Path $TaskProject '../../outputs/Minifire-Minimal-Hook-2.0.0-candidate.zip')
if($LASTEXITCODE -ne 0){throw 'Packaging failed'}
