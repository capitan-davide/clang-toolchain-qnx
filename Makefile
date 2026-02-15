CC = clang

# The `--gcc-toolchain` option expects a path where the GCC toolchain is
# located. The path is in the form:
# 
#   lib{,32,64}/gcc{,-cross}/$triple/$version
#
# In QNX SDP, this is found in $(QNX_HOST)/usr, for example:
#
#  $(QNX_HOST)/usr/lib/gcc/x86_64-pc-nto-qnx8.0.0/12.2.0
#
# The problem is that we are using the `x86_64-pc-nto-gnu` triple so the GCC
# toolchain path does not match. We should specify the triple as
# `x86_64-pd-nto-qnx8.0.0` instead, but Clang does not support that.

CFLAGS = --sysroot=$(QNX_TARGET) --target=x86_64-pc-nto-gnu \
	 -march=x86-64 -Wno-builtin-macro-redefined

LD = ld.lld

LDFLAGS = --sysroot=$(QNX_TARGET) --dynamic-linker=/usr/lib/ldqnx-64.so.2 \
	  --no-rosegment -m elf_x86_64 \
	  -rpath-link $(QNX_TARGET)/x86_64/lib:$(QNX_TARGET)/x86_64/usr/lib:$(QNX_TARGET)/opt/lib:$(QNX_TARGET)/x86_64/lib/gcc/12.2.0

LIBDIRS = -L$(QNX_TARGET)/x86_64/lib -L$(QNX_TARGET)/x86_64/usr/lib \
	  -L$(QNX_TARGET)/x86_64/opt/lib -L$(QNX_TARGET)/x86_64/lib/gcc/12.2.0 \
	  -L$(QNX_HOST)/usr/lib/gcc/x86_64-pc-nto-qnx8.0.0/12.2.0 \

LIBS = -lc -lcS -lgcc -lgcc_s

CRT1     = $(QNX_TARGET)/x86_64/lib/crt1.o
CRTI     = $(QNX_TARGET)/x86_64/lib/crti.o
CRTBEGIN = $(QNX_HOST)/usr/lib/gcc/x86_64-pc-nto-qnx8.0.0/12.2.0/crtbegin.o
CRTEND   = $(QNX_HOST)/usr/lib/gcc/x86_64-pc-nto-qnx8.0.0/12.2.0/crtend.o
CRTN     = $(QNX_TARGET)/x86_64/lib/crtn.o

.PHONY: all
all: a.out

.PHONY: clean
clean:
	rm -f *.o *.out qcc_macros.h

a.o: a.c qcc_macros.h
	$(CC) $(CFLAGS) -c -undef -imacros qcc_macros.h $< -o $@

a.out: a.o
	$(LD) $(LDFLAGS) $(CRT1) $(CRTI) $< $(LIBDIRS) $(LIBS) $(CRTEND) $(CRTN) -o $@

qcc_macros.h:
	qcc -Vgcc_ntox86_64 -dM -E - < /dev/null > $@

.PHONY: image-build
image-build:
	mkqnximage --type=qemu --cpu=2 --ram=1G --arch=x86_64 --force --build

.PHONY: image-run
image-run:
	mkqnximage --run
