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

The goal is to configure LLD to produce binaries compatible with QNX.

TODO...