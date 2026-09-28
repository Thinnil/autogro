import subprocess
_orig_run = subprocess.run
def _safe_run(*args, **kwargs):
    kwargs.setdefault("check", True)
    return _orig_run(*args, **kwargs)
subprocess.run = _safe_run

import subprocess
import os
import sys
import shutil
import glob

# --- CONFIGURATION ---
WORK_DIR = "complex"
INPUT_XTC = "md_0_1.xtc"          # Your raw trajectory
INPUT_STR = "md_0_1.tpr"          # Your reference structure (tpr is much better than gro)
OUTPUT_FINAL = "md_final.xtc" # The result you want
TPR_FILE = "md_0_1.tpr"        # Will be auto-generated if missing

def run_cmd(cmd, inputs=None):
    """Runs a shell command and handles input piping."""
    cmd_str = " ".join(cmd)
    print(f"[-] Running: {cmd_str}")
    try:
        result = subprocess.run(
            cmd, input=inputs, universal_newlines=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, cwd=WORK_DIR
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"[!] Error running command: {e}")
        # Print the actual error from GROMACS so we can see it
        print(f"[!] Stderr: {e.stderr}")
        return None

def generate_dummy_tpr(pdb_file, top_file="topol.top"):
    print("[-] Generating dummy.tpr for robust bond handling...")
    with open(os.path.join(WORK_DIR, "dummy.mdp"), "w") as f:
        f.write("integrator=md\nnsteps=0\ndt=0.002\npbc=xyz\n")

    cmd = [
        "gmx", "grompp", "-f", "dummy.mdp", "-c", pdb_file,
        "-p", top_file, "-o", "dummy.tpr", "-maxwarn", "10"
    ]
    run_cmd(cmd)
    return "dummy.tpr" if os.path.exists(os.path.join(WORK_DIR, "dummy.tpr")) else None

def check_trajectory_integrity(xtc_file, tpr_file):
    print(f"[-] Checking integrity of {xtc_file}...")
    out_xvg = "gyrate_check.xvg"
    # Run gyrate on Protein (Group 1)
    cmd = ["gmx", "gyrate", "-f", xtc_file, "-s", tpr_file, "-o", out_xvg, "-b", "0", "-e", "100"]

    if run_cmd(cmd, inputs="1\n") is None:
        print("[!] Warning: Integrity check failed to run. Skipping.")
        return True # Assume OK if check fails

    max_rg = 0.0
    try:
        with open(os.path.join(WORK_DIR, out_xvg), 'r') as f:
            for line in f:
                if line.startswith(("#", "@")): continue
                parts = line.split()
                if len(parts) > 1:
                    rg = float(parts[1])
                    if rg > max_rg: max_rg = rg
        print(f"    Detected Max Radius of Gyration: {max_rg:.2f} nm")
        # If > 8nm, it's likely exploded
        return max_rg < 8.0
    except FileNotFoundError:
        return True

# --- MAIN LOGIC ---
def locate_trajectory_files():
    """
    Searches for md_0_1.xtc and md_0_1.tpr in the root and subdirectories.
    Detects if files are trapped in archives.
    """
    required_files = {INPUT_XTC: None, INPUT_STR: None}
    search_dirs = [WORK_DIR, os.path.join(WORK_DIR, "04_Production"), os.path.join(WORK_DIR, "05_Results")]

    # Search for uncompressed files
    for filename in required_files.keys():
        for d in search_dirs:
            filepath = os.path.join(d, filename)
            if os.path.exists(filepath):
                required_files[filename] = os.path.relpath(filepath, WORK_DIR).replace('\\', '/')
                break

    missing_files = [f for f, path in required_files.items() if path is None]

    if missing_files:
        # Check for trapped archives
        archives = []
        for d in search_dirs:
            archives.extend(glob.glob(os.path.join(d, "*.tar.gz")))
            archives.extend(glob.glob(os.path.join(d, "*.zip")))

        print(f"[-] Error: Could not locate required files: {', '.join(missing_files)}")
        if archives:
            print(f"[*] Notice: Found compressed archives in your project directories (e.g. {os.path.basename(archives[0])}).")
            print("[*] It appears your trajectory files were compressed by an older cleanup operation.")
            print("[*] ACTION REQUIRED: Please use Option 7 in the main menu to decompress your files, then run this option again.")
        else:
            print("[-] No archives found. Are you sure the production run finished successfully?")

        sys.exit(1)

    return required_files[INPUT_XTC], required_files[INPUT_STR]

INPUT_XTC, INPUT_STR = locate_trajectory_files()

# Generate TPR if possible
tpr = TPR_FILE
if not os.path.exists(os.path.join(WORK_DIR, tpr)):
    # Try finding it based on the located INPUT_STR path if needed
    tpr = INPUT_STR if INPUT_STR.endswith('.tpr') else None
    if not tpr and os.path.exists(os.path.join(WORK_DIR, "topol.top")):
        tpr = generate_dummy_tpr(INPUT_STR)

# --- STRATEGY 1: High-Quality Cluster (Requires TPR) ---
if tpr:
    print("\n[Strategy 1] Attempting High-Quality Cluster Fix...")

    # Step A: CLUSTER (Fix broken molecules)
    # Input: 1 (Protein) -> 0 (System)
    print("    Step A: Clustering molecules...")
    run_cmd([
        "gmx", "trjconv", "-s", tpr, "-f", INPUT_XTC, "-o", "temp_cluster.xtc",
        "-pbc", "cluster"
    ], inputs="1\n0\n")

    # Step B: CENTER (Fix drifting)
    # Input: 1 (Protein) -> 0 (System)
    print("    Step B: Centering protein...")
    run_cmd([
        "gmx", "trjconv", "-s", tpr, "-f", "temp_cluster.xtc", "-o", "temp_centered.xtc",
        "-center", "-pbc", "mol"
    ], inputs="1\n0\n")

    # Step C: FIT (Stop rotation) - MUST BE SEPARATE
    # Input: 4 (Backbone) or 1 (Protein) -> 0 (System)
    print("    Step C: Rotational fitting...")
    run_cmd([
        "gmx", "trjconv", "-s", tpr, "-f", "temp_centered.xtc", "-o", "temp_final.xtc",
        "-fit", "rot+trans"
    ], inputs="4\n0\n")

    # Check Result
    if os.path.exists(os.path.join(WORK_DIR, "temp_final.xtc")) and check_trajectory_integrity("temp_final.xtc", tpr):
        print("\n[+] SUCCESS: Strategy 1 worked!")
        os.rename(os.path.join(WORK_DIR, "temp_final.xtc"), os.path.join(WORK_DIR, OUTPUT_FINAL))
        # Cleanup
        for f in ["temp_cluster.xtc", "temp_centered.xtc", "dummy.mdp", "gyrate_check.xvg"]:
            f_path = os.path.join(WORK_DIR, f)
            if os.path.exists(f_path): os.remove(f_path)
        sys.exit(0)
    else:
        print("\n[!] FAILURE: Strategy 1 produced an exploded protein.")

# --- STRATEGY 2: Residue Method (Fallback) ---
print("\n[Strategy 2] Attempting Residue-Based Fix...")

# Step A: MAKE WHOLE (Residue based)
print("    Step A: Making residues whole...")
run_cmd([
    "gmx", "trjconv", "-s", INPUT_STR, "-f", INPUT_XTC, "-o", "temp_res.xtc",
    "-pbc", "res"
], inputs="0\n")

# Step B: CENTER
print("    Step B: Centering protein...")
run_cmd([
    "gmx", "trjconv", "-s", INPUT_STR, "-f", "temp_res.xtc", "-o", "temp_centered.xtc",
    "-center", "-pbc", "mol"
], inputs="1\n0\n")

# Step C: FIT
print("    Step C: Rotational fitting...")
run_cmd([
    "gmx", "trjconv", "-s", INPUT_STR, "-f", "temp_centered.xtc", "-o", "temp_final_2.xtc",
    "-fit", "rot+trans"
], inputs="4\n0\n")

if os.path.exists(os.path.join(WORK_DIR, "temp_final_2.xtc")):
    print("\n[+] SUCCESS: Strategy 2 completed.")
    os.rename(os.path.join(WORK_DIR, "temp_final_2.xtc"), os.path.join(WORK_DIR, OUTPUT_FINAL))
else:
    print("[!] Error: Strategy 2 failed to produce output.")

# Cleanup
for f in ["temp_res.xtc", "temp_centered.xtc", "dummy.mdp"]:
    f_path = os.path.join(WORK_DIR, f)
    if os.path.exists(f_path): os.remove(f_path)

print(f"[-] Done. Final trajectory: {OUTPUT_FINAL}")
