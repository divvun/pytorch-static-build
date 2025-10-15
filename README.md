# PyTorch Static Build

Cross-platform build scripts for compiling PyTorch C++ libraries as static binaries. This project provides a unified interface for building PyTorch for macOS, iOS, Android, Linux, and Windows using standard target triples.

## Features

- **Unified Build Interface**: Single `build.sh` script using Rust-style target triples
- **Static Libraries**: Optimized for embedding PyTorch in applications
- **Cross-Platform**: Supports macOS, iOS, Android, Linux, and Windows
- **Multiple Architectures**: ARM64, x86_64, ARMv7, and more
- **Lite Interpreter**: Minimal PyTorch runtime for inference
- **Platform-Specific Optimizations**: Metal (iOS/macOS), Vulkan (Android), distributed training (Linux)

## Prerequisites

### All Platforms
- **[uv](https://github.com/astral-sh/uv)**: Python environment manager
  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```

### macOS / iOS
- Xcode Command Line Tools
- Homebrew
- CMake and Ninja:
  ```bash
  brew install cmake ninja
  ```

### Linux
- Clang/LLVM toolchain
- CMake and Ninja
- Build essentials
  ```bash
  # Ubuntu/Debian
  sudo apt install clang cmake ninja-build

  # Fedora/RHEL
  sudo dnf install clang cmake ninja-build
  ```

### Android
- [Android NDK](https://developer.android.com/ndk/downloads)
- Set `ANDROID_NDK` environment variable:
  ```bash
  export ANDROID_NDK=/path/to/android-ndk
  ```

### Windows
- [MSYS2](https://www.msys2.org/)
- Visual Studio or Visual Studio Build Tools
- CMake and Ninja (via MSYS2):
  ```bash
  pacman -S mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
  ```
- MSVC must be available in PATH when running build

## Quick Start

```bash
# Clone PyTorch source (or your fork)
git clone https://github.com/pytorch/pytorch.git
cd pytorch

# Copy build scripts to PyTorch root
cp /path/to/build*.sh .

# Build for your platform
./build.sh --target aarch64-apple-darwin        # macOS Apple Silicon
./build.sh --target x86_64-unknown-linux-gnu    # Linux x86_64
./build.sh --target aarch64-apple-ios           # iOS device
./build.sh --target aarch64-linux-android       # Android arm64
```

Built libraries will be in `target/<target-triple>/lib/` and headers in `target/<target-triple>/include/`.

## Supported Target Triples

### macOS
| Target Triple | Description |
|--------------|-------------|
| `aarch64-apple-darwin` | macOS on Apple Silicon (M1/M2/M3) |
| `x86_64-apple-darwin` | macOS on Intel |

### iOS
| Target Triple | Description |
|--------------|-------------|
| `aarch64-apple-ios` | iOS device (iPhone/iPad) |
| `aarch64-apple-ios-sim` | iOS Simulator on Apple Silicon |
| `x86_64-apple-ios-sim` | iOS Simulator on Intel |
| `arm64_32-apple-watchos` | watchOS (Apple Watch) |

### Android
| Target Triple | Description | ABI |
|--------------|-------------|-----|
| `aarch64-linux-android` | Android ARM64 | arm64-v8a |
| `armv7-linux-androideabi` | Android ARMv7 | armeabi-v7a |
| `x86_64-linux-android` | Android x86_64 | x86_64 |
| `i686-linux-android` | Android x86 | x86 |

### Linux
| Target Triple | Description |
|--------------|-------------|
| `x86_64-unknown-linux-gnu` | Linux x86_64 |
| `aarch64-unknown-linux-gnu` | Linux ARM64 |

### Windows
| Target Triple | Description |
|--------------|-------------|
| `x86_64-pc-windows-msvc` | Windows x64 (MSVC) |
| `i686-pc-windows-msvc` | Windows x86 (MSVC) |

## Build Options

### Common Options (All Platforms)

```bash
--target <triple>        # Target platform (required)
--debug                  # Build with debug symbols
--release                # Optimized release build (default)
--relwithdebinfo         # Optimized with debug symbols
--minsize                # Optimize for binary size
--no-clean               # Skip cleaning build directory
--verbose, -v            # Verbose build output
--help                   # Show help
```

### Platform-Specific Options

#### macOS / Linux
```bash
--static                 # Build static libraries (default)
--shared                 # Build shared libraries
--distributed            # Enable distributed training (Linux default)
--no-distributed         # Disable distributed training (macOS default)
--lite                   # Build lite interpreter (default)
--full                   # Build full interpreter
```

#### iOS
```bash
--device                 # Build for iOS device (default)
--simulator              # Build for iOS simulator (x86_64)
--simulator-arm64        # Build for iOS simulator (Apple Silicon)
--watchos                # Build for watchOS
--metal                  # Enable Metal GPU support (default)
--no-metal               # Disable Metal
--coreml                 # Enable Core ML delegate
--bitcode                # Enable bitcode embedding
```

#### Android
```bash
--abi <abi>              # arm64-v8a, armeabi-v7a, x86, x86_64
--api <level>            # Minimum Android API level (default: 21)
--vulkan                 # Enable Vulkan GPU support
--vulkan-fp16            # Enable Vulkan with FP16 inference
--stl-shared             # Use shared C++ STL (static by default)
```

#### Windows
```bash
--arch <arch>            # x64 or x86 (default: x64)
--x64                    # Build for x64
--x86                    # Build for x86 (32-bit)
```

## Usage Examples

### Build for Multiple Platforms

```bash
# macOS development build with debug symbols
./build.sh --target aarch64-apple-darwin --relwithdebinfo

# iOS production build with Metal
./build.sh --target aarch64-apple-ios --release --metal

# Android build with Vulkan for multiple ABIs
./build.sh --target aarch64-linux-android --vulkan --api 24
./build.sh --target armv7-linux-androideabi --vulkan --api 24

# Linux server build with distributed training
./build.sh --target x86_64-unknown-linux-gnu --distributed

# Windows release build
./build.sh --target x86_64-pc-windows-msvc --release
```

### Direct Script Usage

You can also call platform-specific scripts directly:

```bash
# macOS with custom options
./build-macos.sh --distributed --relwithdebinfo

# iOS for simulator on Apple Silicon
./build-ios.sh --simulator-arm64 --debug

# Android with specific settings
./build-android.sh --abi arm64-v8a --vulkan-fp16 --api 26

# Linux optimized for size
./build-linux.sh --minsize --no-distributed
```

### Environment Variables

Control build behavior with environment variables:

```bash
# Custom build output directory
BUILD_ROOT=/tmp/pytorch-build ./build.sh --target aarch64-apple-darwin

# Limit parallel jobs
MAX_JOBS=4 ./build.sh --target x86_64-unknown-linux-gnu

# Android NDK location
export ANDROID_NDK=/path/to/ndk
./build.sh --target aarch64-linux-android
```

## Output Structure

After a successful build:

```
target/<target-triple>/
├── include/              # C++ headers
│   ├── torch/
│   ├── ATen/
│   ├── c10/
│   └── ...
└── lib/                  # Static libraries
    ├── libtorch.a
    ├── libc10.a
    ├── libcaffe2_protos.a
    └── ...
```

## Integration Examples

### CMake Project

```cmake
set(TORCH_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/target/aarch64-apple-darwin")

include_directories(${TORCH_ROOT}/include)
link_directories(${TORCH_ROOT}/lib)

add_executable(myapp main.cpp)
target_link_libraries(myapp
    torch
    c10
    # Add other PyTorch libraries as needed
)
```

### Xcode (iOS)

1. Add header search path: `target/aarch64-apple-ios/include`
2. Add library search path: `target/aarch64-apple-ios/lib`
3. Link against static libraries
4. Add required frameworks: `Accelerate`, `Metal`, `MetalPerformanceShaders`

### Android (Gradle)

```gradle
android {
    sourceSets {
        main {
            jniLibs.srcDirs = ['libs']
        }
    }
}
```

Copy libraries to `app/src/main/jniLibs/<abi>/` and configure CMakeLists.txt.

## Troubleshooting

### Python Environment Issues

If you see Python-related errors:

```bash
# Clean virtual environment and rebuild
rm -rf .venv
uv venv
./build.sh --target <your-target>
```

### CMake Not Found (macOS)

Ensure Homebrew CMake is installed and in PATH:

```bash
brew install cmake ninja
which cmake  # Should show /opt/homebrew/bin/cmake or /usr/local/bin/cmake
```

### Android NDK Issues

Verify NDK environment variable:

```bash
echo $ANDROID_NDK
ls $ANDROID_NDK/build/cmake/android.toolchain.cmake  # Should exist
```

### Windows MSVC Not Found

Run from MSYS2 shell with MSVC in PATH:

```bash
# Example: Add MSVC to PATH
export PATH="/c/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/<version>/bin/Hostx64/x64:$PATH"
```

### Build Failures

Try a clean build:

```bash
./build.sh --target <your-target> --no-clean  # Remove --no-clean flag
# Or manually clean:
rm -rf target/<target-triple>
```

Enable verbose output for debugging:

```bash
./build.sh --target <your-target> --verbose
```

## Performance Tips

- **Parallel Jobs**: Set `MAX_JOBS` to number of CPU cores or slightly higher
- **Incremental Builds**: Use `--no-clean` after first successful build
- **Build Type**: Use `--release` for production, `--minsize` for size-constrained targets

## What's Included

- **Core PyTorch**: Tensor operations, autograd (lite interpreter mode)
- **ATen**: PyTorch's tensor library
- **c10**: Core abstractions and utilities
- **QNNPACK**: Optimized quantized neural network operators (ARM)
- **XNNPACK**: Optimized operators for mobile
- **Eigen**: Linear algebra library
- **mimalloc**: High-performance allocator

## What's Excluded (to reduce size)

- Python bindings
- Tests and benchmarks
- CUDA support
- Training features (in lite interpreter mode)
- Kineto profiler
- OpenCV, MPI, GFLAGS
- Full JIT compiler (lite interpreter mode)

## License

These build scripts are dedicated to the public domain under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/).

To the extent possible under law, the author(s) have waived all copyright and related or neighboring rights to this work. You can copy, modify, distribute and perform the work, even for commercial purposes, all without asking permission.

PyTorch itself is licensed under the BSD-3-Clause license. See the [PyTorch repository](https://github.com/pytorch/pytorch) for details.

