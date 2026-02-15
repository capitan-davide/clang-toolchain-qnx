CC = clang

# The `--gcc-toolchain` option expects a path where the GCC toolchain is
# located. The path is in the form:
# 
#   lib{,32,64}/gcc{,-cross}/$triple/$version
#
# In QNX SDP, this is found in $QNX_HOST/usr, for example:
#
#  $QNX_HOST/usr/lib/gcc/x86_64-pc-nto-qnx8.0.0/12.2.0
#
# The problem is that we are using the `x86_64-unknown-nto-gnu` triple so the
# GCC toolchain path does not match. We should specify the triple as
# `x86_64-pc-nto-qnx8.0.0` instead, but Clang does not support that.

CFLAGS = --sysroot=$(QNX_TARGET) --target=x86_64-unknown-nto-gnu -march=x86-64 \
		 -Wno-builtin-macro-redefined

.PHONY: all
all: a.o

.PHONY: clean
clean:
	rm -f *.o *.out qcc_macros.h

a.o: a.c qcc_macros.h
	$(CC) -c $(CFLAGS) -undef -imacros qcc_macros.h $< -o $@

qcc_macros.h:
	qcc -Vgcc_ntox86_64 -dM -E - < /dev/null > $@
