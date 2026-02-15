# Cross-compilation for QNX using Clang <!-- omit in toc -->

Clang/LLVM is natively a cross-compiler, meaning it can compile for different
targets by setting the `--target` option. This guide documents how to configure
Clang and LLD (the LLVM's linker) to produce executables compatible with QNX
8.0.

 ## Table of Contents <!-- omit in toc -->

- [1. Prerequisites](#1-prerequisites)
- [2. The Target Triple](#2-the-target-triple)
- [3. Discover GCC the Options](#3-discover-gcc-the-options)
  - [3.1. Step 1: Preprocessor Macros](#31-step-1-preprocessor-macros)
  - [3.2. Step 2: Compiler Options](#32-step-2-compiler-options)
  - [3.3. Step 3: Linker Options](#33-step-3-linker-options)
    - [3.3.1. Fix the Program Headers](#331-fix-the-program-headers)
    - [3.3.2. Final LLD Command](#332-final-lld-command)
- [4. Option Reference](#4-option-reference)
  - [4.1. Compiler Options (CFLAGS)](#41-compiler-options-cflags)
  - [4.2. Linker Options (LDFLAGS)](#42-linker-options-ldflags)
  - [4.3. C Runtime Startup Files](#43-c-runtime-startup-files)
  - [4.4. Libraries](#44-libraries)

 ## 1. Prerequisites

You can request a free copy of the QNX SDP 8.0 for non-commercial use from
https://www.qnx.com/products/everywhere.

## 2. The Target Triple

The target triple format is `<arch>-<vendor>-<sys>-<env>`. Here we use
`x86_64-unknown-nto-gnu`, where:

- `x86_64`: tells the compiler to generate machine code for x86 64-bit
            architecture.
- `unknown`: mostly informational, has no significant effect on code generation.
- `nto`: itentifies the Neutrino operating system. This is not officially 
         supported by Clang and will simply fallback to
         `llvm::Triple::UnknownOS`. This option affects the ABI, calling
         conventions, system call interface, executable format, etc.
- `gnu`: specifies which C library and runtime to use. We cannot specify `qnx`
         here as Clang will reject it so, we use `gnu` as a close relative.

## 3. Discover GCC the Options

The QNX SDK comes with the `qcc` compiler which is actually GCC under the hood.
We want to examine what options GCC uses to produce working binaries, then
replicate them in Clang.

### 3.1. Step 1: Preprocessor Macros

In `qcc`, we can dump all the `#define` directives with:

```bash
qcc -Vgcc_ntox86_64 -dM -E - < /dev/null > qcc_macros.h
```

And subsequently included in Clang using the `-imacros` option. Here we
also specify `-undef` to make Clang undefine (almost) all system defines, and
`-Wno-builtin-macro-redefined` to suppress the remaining warnings.

```bash
clang -c --sysroot=$QNX_TARGET --target=x86_64-unknown-nto-gnu -march=x86-64 \
  -Wno-builtin-macro-redefined -undef -imacros qcc_macros.h a.c
```

### 3.2. Step 2: Compiler Options

Our baseline is code compiled with `qcc -Vgcc_ntox86_64 -c a.c`. We can find out
what options are being passed to GCC by looking at the *gcc_ntox86_64.conf*
file, located in `$QNX_HOST`. The `cc_opt` variable defines all default GCC
options used when invoking `qcc`. Considering that all `#define`s were already
dumped in Step 1, no other critical options are found.

This is already sufficient for Clang to compile source files for QNX x86_64
targets. If we are only interested in running Clang tools (such as
Clang-Tidy, Clang-Query, the Clang Static Analyzer, etc.) we can stop at Step 2.
Keep in mind that these tools are based on the Clang AST, which is generated
early on in the toolchain.

> **Brief: The Clang Frontend**
>
> The Clang frontend is responsible for generating LLVM IR from source code. It
> consists of several stages:
>
> 1. `clang::Lexer`: tokenizes the source code into a stream of `clang::Token`s
> 2. `clang::Preprocessor`: handles includes, macros expansions, etc. produces
>    the final token stream
> 3. `clang::Parser`: builds the Abstract Syntax Tree (AST) from the token stream
> 4. `clang::Sema`: checks types, resolves names, etc. annotates the AST with
>    semantic information
> 5. `clang::ASTConsumer`: consumes the AST for analysis or transformation
>
> There are several AST consumers available in Clang. When compiling a source
> file, the default consumer is `clang::CodeGenerator`. Tools like Clang-Tidy
> are also implemented as AST consumers! For example, calling
> `clang -c -Xclang -ast-dump a.c` will call the `clang::ASTPrinter` consumer.

If we want to generate executable files, the tricky part now is to configure the
linker.

### 3.3. Step 3: Linker Options

The goal is to configure LLD to produce binaries compatible with QNX.  Again, we
can use *gcc_ntox86_64.conf* for reference. Important options include:

- the C runtime startup files (`crt1.o`, `crti.o`, `crtbegin.o`, etc.)
- the `-rpath-link` directories, for searching indirect shared library
  dependencies
- the `-Y` and `-L` library search paths
- the linked libraries (`-lgcc`, `-lc`, etc.)
- the linker options such as `-zrelro`, `-znow`, `-pie`, `--eh-frame-hdr`, etc.

Now we can try link the object file compiled earlier using LLD.

```bash
ld.lld --sysroot=$QNX_TARGET --dynamic-linker=/usr/lib/ldqnx-64.so.2 \
  $QNX_TARGET/x86_64/lib/crt1.o \
  $QNX_TARGET/x86_64/lib/crti.o \
  $QNX_HOST/usr/lib/gcc/x86_64-pc-nto-qnx8.0.0/12.2.0/crtbegin.o \
  a.o \
  -L$QNX_TARGET/x86_64/lib \
  -L$QNX_TARGET/x86_64/usr/lib \
  -L$QNX_TARGET/x86_64/opt/lib \
  -L$QNX_TARGET/x86_64/lib/gcc/12.2.0 \
  -L$QNX_HOST/usr/lib/gcc/x86_64-pc-nto-qnx8.0.0/12.2.0 \
  -rpath-link $QNX_TARGET/x86_64/lib:$QNX_TARGET/x86_64/usr/lib:$QNX_TARGET/opt/lib:$QNX_TARGET/x86_64/lib/gcc/12.2.0 \
  -lc -lcS -lgcc -lgcc_s \
  $QNX_HOST/usr/lib/gcc/x86_64-pc-nto-qnx8.0.0/12.2.0/crtend.o \
  $QNX_TARGET/x86_64/lib/crtn.o \
  -o a.out
```

#### 3.3.1. Fix the Program Headers

We can check the program headers using:

```bash
$ readelf -Wl a.out

Elf file type is EXEC (Executable file)
Entry point 0x210600
There are 10 program headers, starting at offset 64

Program Headers:
  Type           Offset   VirtAddr           PhysAddr           FileSiz  MemSiz   Flg Align
  PHDR           0x000040 0x0000000000200040 0x0000000000200040 0x000230 0x000230 R   0x8
  INTERP         0x000270 0x0000000000200270 0x0000000000200270 0x000017 0x000017 R   0x1
      [Requesting program interpreter: /usr/lib/ldqnx-64.so.2]
  LOAD           0x000000 0x0000000000200000 0x0000000000200000 0x0005f4 0x0005f4 R   0x10000
  LOAD           0x000600 0x0000000000210600 0x0000000000210600 0x0001c0 0x0001c0 R E 0x10000
  LOAD           0x0007c0 0x00000000002207c0 0x00000000002207c0 0x000140 0x000840 RW  0x10000
  LOAD           0x000900 0x0000000000230900 0x0000000000230900 0x000060 0x000061 RW  0x10000
  DYNAMIC        0x0007c8 0x00000000002207c8 0x00000000002207c8 0x000130 0x000130 RW  0x8
  GNU_RELRO      0x0007c0 0x00000000002207c0 0x00000000002207c0 0x000140 0x000840 R   0x1
  GNU_STACK      0x000000 0x0000000000000000 0x0000000000000000 0x000000 0x000000 RW  0
  NOTE           0x000287 0x0000000000200287 0x0000000000200287 0x00001c 0x00001c R   0x1

 Section to Segment mapping:
  Segment Sections...
   00
   01     .interp
   02     .interp .note .dynsym .gnu.hash .hash .dynstr .rela.dyn .rela.plt .rodata .eh_frame
   03     .text .plt
   04     .fini_array .dynamic .got .relro_padding
   05     .data .got.plt .bss
   06     .dynamic
   07     .fini_array .dynamic .got .relro_padding
   08
   09     .note
```

When compared to the program headers of a native QNX binary (e.g.,
`readelf -Wl $QNX_TARGET/x86_64/bin/ksh`) we can see that the `LOAD` segments
are setup differently; LLD creates four by default, and puts the `.text` section
in a separate segment.

| Offset   | Flags | Content                     |
|----------|-------|-----------------------------|
| 0x000000 | R     | Code (`.text`)              |
| 0x000600 | R E   | Read-only data (`.rodata`)  |
| 0x0007c0 | RW    | Initialized data (`.data`)  |
| 0x000900 | RW    | Uninitialized data (`.bss`) |

While, the QNX linker only creates two segments and stores `.text` and `.rodata`
in the same one.

| Offset   | Flags | Content                                                    |
|----------|-------|------------------------------------------------------------|
| 0x000000 | R E   | Code (`.text`) and read-only data (`.rodata`)              |
| 0x03c018 | RW    | Initialized data (`.data`) and uninitialized data (`.bss`) |

This we can fix this with the `--no-rosegment` option.

#### 3.3.2. Final LLD Command

```bash
ld.lld --sysroot=$QNX_TARGET --dynamic-linker=/usr/lib/ldqnx-64.so.2 \
  $QNX_TARGET/x86_64/lib/crt1.o \
  $QNX_TARGET/x86_64/lib/crti.o \
  $QNX_HOST/usr/lib/gcc/x86_64-pc-nto-qnx8.0.0/12.2.0/crtbegin.o \
  a.o \
  -L$QNX_TARGET/x86_64/lib \
  -L$QNX_TARGET/x86_64/usr/lib \
  -L$QNX_TARGET/x86_64/opt/lib \
  -L$QNX_TARGET/x86_64/lib/gcc/12.2.0 \
  -L$QNX_HOST/usr/lib/gcc/x86_64-pc-nto-qnx8.0.0/12.2.0 \
  -rpath-link $QNX_TARGET/x86_64/lib:$QNX_TARGET/x86_64/usr/lib:$QNX_TARGET/opt/lib:$QNX_TARGET/x86_64/lib/gcc/12.2.0 \
  -lc -lcS -lgcc -lgcc_s \
  $QNX_HOST/usr/lib/gcc/x86_64-pc-nto-qnx8.0.0/12.2.0/crtend.o \
  $QNX_TARGET/x86_64/lib/crtn.o \
  -o a.out
```

This finally produces a working QNX binary! 

## 4. Option Reference

### 4.1. Compiler Options (CFLAGS)

| Option | Description |
|--------|-------------|
| `--target=x86_64-pc-nto-gnu` | Target triple for QNX on AArch64 with GNU C library |
| `--sysroot=$QNX_TARGET` | Path to QNX target filesystem (headers and libraries) |
| `-D__LITTLEENDIAN__=1` | Define little-endian byte order (required by QNX headers) |
| `-D__QNXNTO__=1` | Define QNX Neutrino OS (required by QNX headers) |

### 4.2. Linker Options (LDFLAGS)

| Option | Description |
|--------|-------------|
| `-fuse-ld=lld` | Use LLVM's LLD linker instead of system linker |
| `-nostdlib` | Don't link standard startup files/libraries automatically (we specify them manually) |
| `-Wl,-m,elf_x86_64` | Set LLD emulation mode to x86_64 ELF |
| `-Wl,--dynamic-linker=/usr/lib/ldqnx-64.so.2` | QNX dynamic linker (interpreter) path |
| `-Wl,--build-id=md5` | Embed MD5 build ID in binary (matches GCC behavior) |
| `-Wl,--eh-frame-hdr` | Generate `.eh_frame_hdr` section for exception handling |
| `-Wl,-z,relro` | Mark relocation sections as read-only after relocation (security) |
| `-Wl,-z,now` | Resolve all symbols at load time (full RELRO, security) |
| `-Wl,-z,max-page-size=0x1000` | Set page size to 4KB (QNX default, vs LLD's 64KB default) |
| `-Wl,-z,noseparate-code` | Don't create separate segment for code (matches QNX layout) |
| `-Wl,-z,nognustack` | Don't emit `GNU_STACK` segment (QNX doesn't recognize it) |
| `-Wl,--no-rosegment` | Merge read-only data with code segment (matches QNX layout) |
| `-Wl,--rpath-link=...` | Search paths for indirect shared library dependencies |

### 4.3. C Runtime Startup Files

These must be linked in the correct order:

| File | Location | Purpose |
|------|----------|---------|
| `crt1.o` | `$QNX_TARGET/x86_64/lib/` | Program entry point (`_start`), calls `main()` |
| `crti.o` | `$QNX_TARGET/x86_64/lib/` | Prologue for `.init`/`.fini` sections |
| `crtbegin.o` | `$QNX_HOST/usr/lib/gcc/.../` | GCC's constructor/destructor handling (before user code) |
| `crtend.o` | `$QNX_HOST/usr/lib/gcc/.../` | GCC's constructor/destructor handling (after user code) |
| `crtn.o` | `$QNX_TARGET/x86_64/lib/` | Epilogue for `.init`/`.fini` sections |

**Link order:** `crt1.o` → `crti.o` → `crtbegin.o` → *user code* → *libraries* → `crtend.o` → `crtn.o`

### 4.4. Libraries

| Library | Description |
|---------|-------------|
| `-lgcc` | GCC runtime support (software division, etc.) |
| `-lgcc_s` | GCC shared runtime (linked as-needed) |
| `-lc` | QNX C library |
| `-lcS` | QNX C library supplement |
