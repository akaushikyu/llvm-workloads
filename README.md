# A collection of LLVM bitcodes for testing

This repository holds a collection of workloads for testing and analyzing with custom `llc`.
These workloads can be programs and LLVM bitcodes.

## LLVM Bitcodes
Using the `wllvm` framework available [here](https://github.com/travitch/whole-program-llvm) to create bitcodes of large programs.

## Workloads
- [libc](tests/bitcodes/libc.bca)
    - To extract the individual bitcode files, execute `llvm-ar x libc.bca`. 
    - The individual bitcode files are hidden. To expose them, execute `ls -la`
