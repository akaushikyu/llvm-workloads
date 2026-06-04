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

