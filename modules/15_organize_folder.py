import subprocess
_orig_run = subprocess.run
def _safe_run(*args, **kwargs):
    kwargs.setdefault("check", True)
    return _orig_run(*args, **kwargs)
subprocess.run = _safe_run

import os
import shutil
import sys
import glob

def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    # Writes to the current working directory, which will be the project root
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")

# --- CONFIGURATION ---
work_dir = "complex"

# Define the category map
structure_map = {
    "01_Setup": [
        "topol", "itp", "posre", "box.gro", "solvated", "ions", "ligand", "#topol"
    ],
    "02_Minimization": [
        "em."
    ],
    "03_Equilibration": [
        "nvt.", "npt."
    ],
    "04_Production": [
        "md_0_1.log", "md_0_1.edr", "md_0_1.cpt", "#md_0_1", ".mdp", ".tpr"
    ],
    "05_Results": [
        "md_centered", "md_final", "dry_", "fep_lambda_", "ensemble_", "binding_affinity_", "mmpbsa", "FINAL_RESULTS",
        "md_0_1.xtc", "md_0_1.gro", "md_0_1.pdb", "mixed_frames"
    ],
    "06_Analysis": [
        "density_", ".dx", ".xvg"
    ]
}

# --- MAIN SCRIPT ---
if not os.path.exists(work_dir):
    print(f"[!] Directory '{work_dir}' not found.")
    sys.exit(1)

print(f"[-] Organizing files in '{work_dir}'...")

# 1. Create the subfolders
for folder in structure_map:
    folder_path = os.path.join(work_dir, folder)
    if not os.path.exists(folder_path):
        os.makedirs(folder_path)

# 2. Move the files
files = os.listdir(work_dir)
moved_count = 0

for f in files:
    safe_f = os.path.basename(f)
    src_path = os.path.join(work_dir, safe_f)

    # Skip our own category directories
    if os.path.isdir(src_path) and safe_f in structure_map:
        continue

    # Handle RAW replica directories and files (mdrun outputs)
    if os.path.isdir(src_path) and safe_f.startswith("replica_") and "centered" not in safe_f:
        prod_dest = os.path.join(work_dir, "04_Production", safe_f)
        res_dest = os.path.join(work_dir, "05_Results", safe_f)
        os.makedirs(prod_dest, exist_ok=True)
        os.makedirs(res_dest, exist_ok=True)

        for rep_f in os.listdir(src_path):
            safe_rep_f = os.path.basename(rep_f)
            rep_f_path = os.path.join(src_path, safe_rep_f)
            if not os.path.isfile(rep_f_path):
                continue

            if safe_rep_f.endswith(".xtc") or safe_rep_f.endswith(".gro") or safe_rep_f.endswith(".pdb"):
                os.rename(rep_f_path, os.path.join(res_dest, safe_rep_f))
            else:
                os.rename(rep_f_path, os.path.join(prod_dest, safe_rep_f))

        try:
            os.rmdir(src_path)
        except OSError:
            pass

        moved_count += 1
        print(f"    Splitting {safe_f}/ -> 04_Production/ and 05_Results/")
        continue

    # Handle raw inputs (tpr, mdp) for replicas
    if safe_f.startswith("md_replica_") or (safe_f.startswith("replica_") and safe_f.endswith(".tpr")):
        dest = os.path.join(work_dir, "04_Production", safe_f)
        os.rename(src_path, dest)
        moved_count += 1
        print(f"    Moving {safe_f} -> 04_Production/")
        continue

    # Handle replica centered outputs (from 13_post_processing)
    if safe_f.startswith("replica_") and ("_centered." in safe_f):
        try:
            rep_num = int(safe_f.split('_')[1])
            rep_dir = os.path.join(work_dir, "05_Results", f"replica_{rep_num}")
            os.makedirs(rep_dir, exist_ok=True)
            dest = os.path.join(rep_dir, safe_f)
            os.rename(src_path, dest)
            moved_count += 1
            print(f"    Moving {safe_f} -> 05_Results/replica_{rep_num}/")
            continue
        except (IndexError, ValueError):
            pass

    # Find which folder this file belongs to
    destination_folder = None
    if os.path.isfile(src_path):
        for folder, patterns in structure_map.items():
            for pat in patterns:
                if pat in safe_f:
                    destination_folder = folder
                    break
            if destination_folder:
                break

    # Move the file if a category was found
    if destination_folder:
        dst_path = os.path.join(work_dir, destination_folder, safe_f)
        print(f"    Moving {safe_f} -> {destination_folder}/")
        try:
            os.rename(src_path, dst_path)
            moved_count += 1
        except Exception as e:
            print(f"    [ERROR-ORG-2] Failed to move {safe_f} to {destination_folder}: {e}")
    else:
        print(f"    [?] Skipping {safe_f} (No category fits)")

# Retroactive cleanup: Fix stranded files from previous runs
results_dir = os.path.join(work_dir, "05_Results")
prod_dir = os.path.join(work_dir, "04_Production")
if os.path.exists(results_dir):
    # Fixed indentation
    for ext in ("*.mdp", "*.tpr"):
        for src_path in glob.iglob(os.path.join(results_dir, "**", ext), recursive=True):
            if os.path.isfile(src_path):
                safe_f = os.path.basename(src_path)
                dest_path = os.path.join(prod_dir, safe_f)
                try:
                    os.rename(src_path, dest_path)
                    moved_count += 1
                    print(f"    [Cleanup] Moving {safe_f} from {os.path.relpath(os.path.dirname(src_path), work_dir)}/ -> 04_Production/")
                except Exception as e:
                    print(f"    [ERROR-ORG-1] Failed to move {safe_f}: {e}")

print("-" * 40)
print(f"[-] Done. {moved_count} files organized.")
print("[-] Your 'complex' folder is now clean.")
log_pipeline_msg("Step 15", "OK")
