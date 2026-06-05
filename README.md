# A collection of LLVM bitcodes for testing

This repository holds a collection of workloads for testing and analyzing with custom `llc`.
These workloads can be programs and LLVM bitcodes.

## LLVM Bitcodes
Using the `wllvm` framework available [here](https://github.com/travitch/whole-program-llvm) to create bitcodes of large programs.

## Workloads
- [llvm-libc](tests/bitcodes/llvm-libc.bca)
    - LLVM libc 
    - To extract the individual bitcode files, execute `llvm-ar x llvm-libc.bca`. 
    - The individual bitcode files are hidden. To expose them, execute `ls -la`

- [musl-libc](tests/bitodes/musl-libc.bca)
    - Use WLLVM to generate bitcode
    - Run the following command to configure and build the `musl-libc`:
        ```
         WLLVM_CONFIGURE_ONLY=1 CC="wllvm --target=riscv64-unknown-linux-musl -march=rv64gc -mabi=lp64d -fuse-ld=lld" \
         AR="/opt/riscv-llvm/bin/llvm-ar" RANLIB="/opt/riscv-llvm/bin/llvm-ranlib" \
         ./configure --prefix=/home/kaushika/REPOS/libc-versions/musl-1.2.6/build/ --target=riscv64-unknown-linux-musl
        ```
    - Followed by `make`
    - To package the bitcode archive of `musl-libc`, navigate to `lib` directory and run `extract-bc -a /opt/riscv-llvm/bin/llvm-ar libc.a`. This will generate a `libc.bca`
    - To extract the individual bitcode files, execute `llvm-ar x musl-libc.bca`. 
- [uclibc](tests/bits/uclibc-libc.bca)
   - First install the linux cross headers for riscv -- `sudo apt install gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu linux-libc-dev-riscv64-cross`
   - Clone the uclibc-ng repo and run the following command to configure uclibc for RISC-V: 'make menuconfig', select `riscv64` in target architecture.
   - Open the `.config` file, and update the `KERNEL_HEADERS=` to `KERNEL_HEADERS=/usr/riscv64-linux-gnu/include`, which is the location of the riscv linux kernel headers 
   - To compile uclibc with LLVM, a few changes a required. These changes do the following: (1) convert nested functions that are unacceptable by clang but fine by gcc, and (2) remove GNU assembler directive. Apply the `clang-uclibc.patch` using `git apply clang-uclibc.patch`.
   - Before using `wllvm`, first compile uclibc using `clang` to generate the `bits/` include files by running
   ```
    make VERBOSE=1  CROSS_COMPILE=riscv64-linux-gnu- \
    CC="clang --target=riscv64-linux-gnu" \
    AR=/opt/riscv-llvm/bin/llvm-ar   \
    RANLIB=/opt/riscv-llvm/bin/llvm-ranlib \
    NM=/opt/riscv-llvm/bin/llvm-nm \
    STRIP=llvm-strip
   ```
   - Once the `include/bits/` directory is created, we can run `wllvm` by changing `CC="clang..` to `CC="wllvm..`
   - Follow the same steps for the above libc to package the bitcode archive and extract the individual bitcode files

