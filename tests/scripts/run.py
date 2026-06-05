import sys
import glob
import subprocess

def run(llcPath):
    llcBinary = llcPath + "/llc"
    bcFiles = glob.glob(".*.bc")
    for i in bcFiles:
        print (i)
        try:
            subprocess.run([llcBinary, "-dump-insn-stats-json", "-march=riscv64", "-o", "-", str(i)], check=True)
        except subprocess.CalledProcessError as e:
            print(f"Command failed with error: {e}")

    print ("All completed")

if __name__ == "__main__":
    if (len(sys.argv) < 2):
        print ("Error: no llc binary path provided")
    else:
        run(sys.argv[1])
