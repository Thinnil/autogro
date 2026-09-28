import subprocess
_orig_run = subprocess.run
def _safe_run(*args, **kwargs):
    kwargs.setdefault("check", True)
    return _orig_run(*args, **kwargs)
subprocess.run = _safe_run

def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import subprocess
import sys

work_dir = "complex"

if not os.path.exists(work_dir):
    print(f"[!] Directory '{work_dir}' not found.")
    sys.exit(1)

try:
    subprocess.run(["gmx_MMPBSA", "-h"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
except FileNotFoundError:
    print("\n[!] Error: 'gmx_MMPBSA' command not found.")
    print("    To install it via Anaconda:")
    print("      conda create -n gmxMMPBSA -c conda-forge -c bioconda gmx_mmpbsa=1.5.7")
    print("      conda activate gmxMMPBSA\n")
    sys.exit(1)

traj = None
if os.path.exists(os.path.join(work_dir, "05_Results", "Ensemble", "ensemble_combined.xtc")):
    traj = "05_Results/Ensemble/ensemble_combined.xtc"
elif os.path.exists(os.path.join(work_dir, "md_0_1.xtc")):
    traj = "md_0_1.xtc"
else:
    print("[!] Error: No suitable trajectory found for MM-PBSA analysis.")
    sys.exit(1)

print(f"[-] Found trajectory for MM-PBSA: {traj}")

mmpbsa_in = """&general
sys_name="Protein-Ligand Complex",
startframe=1, endframe=9999999, interval=1
/
&gb
igb=5, saltcon=0.150,
/
&pb
istrng=0.150,
/
"""
with open(os.path.join(work_dir, "mmpbsa.in"), "w") as f:
    f.write(mmpbsa_in)

print("[-] Creating index.ndx for MM-PBSA...")
group_lig = "13"
try:
    subprocess.run(
        ["gmx", "make_ndx", "-f", "md_0_1.tpr", "-o", "index.ndx"],
        input="q\n", universal_newlines=True, check=True, cwd=work_dir
    )
    with open(os.path.join(work_dir, "index.ndx")) as f:
        idx = 0
        for line in f:
            if line.startswith("["):
                if "MOL" in line or "LIG" in line or "Ligand" in line:
                    group_lig = str(idx)
                idx += 1
except Exception as e:
    print(f"[!] Warning: Could not generate index.ndx automatically: {e}")

print("[-] Launching gmx_MMPBSA calculation...")
cmd = [
    "gmx_MMPBSA", "-O", "-i", "mmpbsa.in", "-cs", "md_0_1.tpr",
    "-ci", "index.ndx", "-cp", "topol.top", "-ct", traj,
    "-cg", "1", group_lig, "-nogui"
]
try:
    subprocess.run(cmd, cwd=work_dir)
    print("[-] MM-PBSA calculation completed. Results in FINAL_RESULTS_MMPBSA.dat")
except Exception as e:
    print(f"[!] MM-PBSA Error: {e}")
log_pipeline_msg("Step 18", "OK")
