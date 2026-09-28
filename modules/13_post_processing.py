import subprocess
_orig_run = subprocess.run
def _safe_run(*args, **kwargs):
    kwargs.setdefault("check", True)
    return _orig_run(*args, **kwargs)
subprocess.run = _safe_run

import os
import subprocess
import sys
import glob
import re

def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    # Writes to the current working directory, which will be the project root
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")

# --- CONFIGURATION ---
work_dir = "complex"

# 1. Discover replicas
replicas = []
replica_tpr_map = {}
tpr_files = glob.glob(os.path.join(work_dir, "replica_*.tpr"))
tpr_files += glob.glob(os.path.join(work_dir, "04_Production", "replica_*.tpr"))
tpr_files += glob.glob(os.path.join(work_dir, "05_Results", "replica_*.tpr"))
tpr_files += glob.glob(os.path.join(work_dir, "05_Results", "Ensemble", "replica_*.tpr"))

for t_path in tpr_files:
    basename = os.path.basename(t_path)
    try:
        rep_num = int(basename.split('_')[1].split('.')[0])
        if rep_num not in replica_tpr_map:
            replicas.append(rep_num)
            replica_tpr_map[rep_num] = os.path.relpath(t_path, work_dir).replace('\\', '/')
    except: pass
replicas.sort()

# --- Dynamic Ligand Detection & Custom Index Generation ---
out_group_idx = "1"
out_group = "Protein"
ndx_args = []
ligand_file = ""
ligand_resname = ""
settings_path = "../simulation_settings.txt" if os.path.exists("../simulation_settings.txt") else "simulation_settings.txt"
try:
    with open(settings_path) as f:
        for line in f:
            if "=" in line and not line.strip().startswith("#"):
                key, val = line.strip().split("=", 1)
                if key.strip() == "ligand_file":
                    ligand_file = val.strip()
                elif key.strip() == "ligand_resname":
                    # Sanitize to prevent GROMACS prompt injection via ! operator
                    ligand_resname = re.sub(r'[^a-zA-Z0-9_]', '', val.strip())
except Exception:
    pass

if ligand_file and ligand_file.lower() != "none":
    ref_tpr = ""
    if replicas:
        ref_tpr = replica_tpr_map[replicas[0]]
    else:
        for d in [work_dir, os.path.join(work_dir, "04_Production"), os.path.join(work_dir, "05_Results")]:
            cand = os.path.join(d, "md_0_1.tpr")
            if os.path.exists(cand):
                ref_tpr = os.path.relpath(cand, work_dir).replace('\\', '/')
                break

    if ref_tpr:
        try:
            true_resname = ligand_resname if ligand_resname else "LIG"
            itp_path = os.path.join(work_dir, "ligand.itp")
            if not os.path.exists(itp_path):
                itp_path = os.path.join(work_dir, "01_Setup", "ligand.itp")

            if not os.path.exists(itp_path) and os.path.exists(os.path.join(work_dir, "01_Setup.tar")):
                subprocess.run(["tar", "-xf", "01_Setup.tar", "01_Setup/ligand.itp"], cwd=work_dir, stderr=subprocess.DEVNULL)

            if os.path.exists(itp_path):
                with open(itp_path, "r") as f:
                    in_atoms = False
                    for line in f:
                        if line.strip().startswith("[ atoms ]"):
                            in_atoms = True
                            continue
                        if in_atoms:
                            if line.strip().startswith("["):
                                break
                            if line.strip() and not line.strip().startswith(";"):
                                parts = line.split()
                                if len(parts) >= 4:
                                    true_resname = re.sub(r'[^a-zA-Z0-9_]', '', parts[3])
                                    break

            print(f"[-] Generating custom index for Protein + {true_resname}...")
            ndx_input = f"1 | r {true_resname}\nq\n"
            subprocess.run(["gmx", "make_ndx", "-f", ref_tpr, "-o", "clean.ndx"], cwd=work_dir, input=ndx_input, universal_newlines=True, check=True)
            if os.path.exists(os.path.join(work_dir, "clean.ndx")):
                with open(os.path.join(work_dir, "clean.ndx")) as f:
                    content = f.read()
                    matches = re.findall(r'\[(.*?)\]', content)
                    if matches:
                        out_group = matches[-1].strip()
                        out_group_idx = str(len(matches) - 1)
                ndx_args = ["-n", "clean.ndx"]
                print(f"[-] Custom output group identified: {out_group} (Index {out_group_idx})")
        except Exception as e:
            print(f"[!] Warning: Custom index generation failed ({e}).")

if not replicas:
    # Standard Non-Replica Logic
    search_dirs = [work_dir, os.path.join(work_dir, "04_Production"), os.path.join(work_dir, "05_Results")]

    tpr_file = "md_0_1.tpr"
    for d in search_dirs:
        if os.path.exists(os.path.join(d, "md_0_1.tpr")):
            tpr_file = os.path.relpath(os.path.join(d, "md_0_1.tpr"), work_dir).replace('\\', '/')
            break

    traj_file = "md_0_1.xtc"
    for d in search_dirs:
        if os.path.exists(os.path.join(d, "md_0_1.xtc")):
            traj_file = os.path.relpath(os.path.join(d, "md_0_1.xtc"), work_dir).replace('\\', '/')
            break

    out_xtc = "md_centered.xtc"
    out_gro = "md_centered.gro"
    out_pdb = "md_centered.pdb"

    if not os.path.exists(os.path.join(work_dir, traj_file)):
        print(f"[!] Error: md_0_1.xtc not found. Run the simulation first.")
        if os.path.exists(os.path.join(work_dir, "md_0_1.trr")):
            print("    (Found .trr file instead. Please edit this script to read .trr)")
        log_pipeline_msg("Step 13", "PDBs were skipped because there was no detection.")
        sys.exit(1)

    print("[-] 0. Generating raw PDB from md_0_1.gro (if needed)...")
    if os.path.exists(os.path.join(work_dir, "md_0_1.gro")) and not os.path.exists(os.path.join(work_dir, "md_0_1.pdb")):
        subprocess.run(["gmx", "editconf", "-f", "md_0_1.gro", "-o", "md_0_1.pdb"], cwd=work_dir, check=True)

    print("[-] 1. Creating Optimized Trajectory (Cluster, Center, and Fit)...")
    subprocess.run(["gmx", "trjconv", "-s", tpr_file, "-f", traj_file, "-o", "temp_cluster.xtc", "-pbc", "cluster"] + ndx_args, cwd=work_dir, input=f"{out_group_idx}\n0\n", universal_newlines=True, check=True)
    subprocess.run(["gmx", "trjconv", "-s", tpr_file, "-f", "temp_cluster.xtc", "-o", "temp_centered.xtc", "-center", "-pbc", "mol"] + ndx_args, cwd=work_dir, input=f"{out_group_idx}\n0\n", universal_newlines=True, check=True)
    subprocess.run(["gmx", "trjconv", "-s", tpr_file, "-f", "temp_centered.xtc", "-o", out_xtc, "-fit", "rot+trans"] + ndx_args, cwd=work_dir, input=f"4\n{out_group_idx}\n", universal_newlines=True, check=True)
    if os.path.exists(os.path.join(work_dir, "temp_cluster.xtc")):
        os.remove(os.path.join(work_dir, "temp_cluster.xtc"))
    if os.path.exists(os.path.join(work_dir, "temp_centered.xtc")):
        os.remove(os.path.join(work_dir, "temp_centered.xtc"))

    print("[-] 1.5 Extracting stripped structure for further processing...")
    subprocess.run(["gmx", "trjconv", "-s", tpr_file, "-f", traj_file, "-dump", "0", "-o", "stripped.gro"] + ndx_args, cwd=work_dir, input=f"{out_group_idx}\n", universal_newlines=True, check=True)

    print("[-] 2. Extracting Final Centered Structure (.gro)...")
    subprocess.run(["gmx", "trjconv", "-s", "stripped.gro", "-f", out_xtc, "-dump", "9999999", "-o", out_gro], cwd=work_dir, input=f"0\n", universal_newlines=True, check=True)
    print("[-] 3. Converting Structure to PDB (.pdb)...")
    subprocess.run(["gmx", "editconf", "-f", out_gro, "-o", out_pdb], cwd=work_dir, check=True)
    print("\n[-] SUCCESS! Files ready for visualization:")
    print(f"    Structure:  {os.path.join(work_dir, out_pdb)}")
    print(f"    Trajectory: {os.path.join(work_dir, out_xtc)}")
    log_pipeline_msg("Step 13", "OK")
    sys.exit(0)

# Multi-Replica Logic
centered_xtcs = []
for r in replicas:
    tpr_file = replica_tpr_map.get(r)
    if not tpr_file or not os.path.exists(os.path.join(work_dir, tpr_file)):
        print(f"[!] Warning: replica_{r}.tpr not found. Skipping Replica {r}.")
        continue

    # Trajectories are generated INSIDE the replica_X directory by mdrun!
    traj_file = f"replica_{r}/replica_{r}.xtc"
    traj_candidates = [
        traj_file,
        f"05_Results/replica_{r}/replica_{r}.xtc",
        f"04_Production/replica_{r}/replica_{r}.xtc",
        f"05_Results/Ensemble/replica_{r}.xtc",
        f"04_Production/replica_{r}.xtc",
        f"05_Results/replica_{r}.xtc",
        f"replica_{r}.xtc"
    ]
    for cand in traj_candidates:
        if os.path.exists(os.path.join(work_dir, cand)):
            traj_file = cand
            break

    out_xtc = f"replica_{r}_centered.xtc"
    out_gro = f"replica_{r}_centered.gro"
    out_pdb = f"replica_{r}_centered.pdb"

    if not os.path.exists(os.path.join(work_dir, traj_file)):
        print(f"[!] Warning: {traj_file} not found. Skipping Replica {r}.")
        log_pipeline_msg("Step 13", "PDBs were skipped because there was no detection.")
        continue

    print(f"\n[-] Processing Replica {r}...")
    try:
        res = subprocess.run(["gmx", "trjconv", "-s", tpr_file, "-f", traj_file, "-o", "temp_cluster.xtc", "-pbc", "cluster"] + ndx_args, cwd=work_dir, input=f"{out_group_idx}\n0\n", universal_newlines=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        print(f"[ERROR-POST-1] trjconv (cluster) failed for replica {r}:")
        print(f"STDOUT:\n{e.stdout}\nSTDERR:\n{e.stderr}")
        log_pipeline_msg("Step 13", f"Process failed: {e}", is_error=True)
        continue

    try:
        res = subprocess.run(["gmx", "trjconv", "-s", tpr_file, "-f", "temp_cluster.xtc", "-o", "temp_centered.xtc", "-center", "-pbc", "mol"] + ndx_args, cwd=work_dir, input=f"{out_group_idx}\n0\n", universal_newlines=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        print(f"[ERROR-POST-2] trjconv (center) failed for replica {r}:")
        print(f"STDOUT:\n{e.stdout}\nSTDERR:\n{e.stderr}")
        log_pipeline_msg("Step 13", f"Process failed: {e}", is_error=True)
        continue

    try:
        res = subprocess.run(["gmx", "trjconv", "-s", tpr_file, "-f", "temp_centered.xtc", "-o", out_xtc, "-fit", "rot+trans"] + ndx_args, cwd=work_dir, input=f"4\n{out_group_idx}\n", universal_newlines=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        print(f"[ERROR-POST-3] trjconv (fit) failed for replica {r}:")
        print(f"STDOUT:\n{e.stdout}\nSTDERR:\n{e.stderr}")
        log_pipeline_msg("Step 13", f"Process failed: {e}", is_error=True)
        continue

    if os.path.exists(os.path.join(work_dir, "temp_cluster.xtc")):
        os.remove(os.path.join(work_dir, "temp_cluster.xtc"))
    if os.path.exists(os.path.join(work_dir, "temp_centered.xtc")):
        os.remove(os.path.join(work_dir, "temp_centered.xtc"))

    try:
        res = subprocess.run(["gmx", "trjconv", "-s", tpr_file, "-f", traj_file, "-dump", "0", "-o", f"stripped_rep{r}.gro"] + ndx_args, cwd=work_dir, input=f"{out_group_idx}\n", universal_newlines=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        print(f"[ERROR-POST-3.5] trjconv (extract stripped) failed for replica {r}:")
        print(f"STDOUT:\n{e.stdout}\nSTDERR:\n{e.stderr}")
        log_pipeline_msg("Step 13", f"Process failed: {e}", is_error=True)
        continue

    try:
        subprocess.run(["gmx", "trjconv", "-s", f"stripped_rep{r}.gro", "-f", out_xtc, "-dump", "9999999", "-o", out_gro], cwd=work_dir, input=f"0\n", universal_newlines=True, check=True)
        subprocess.run(["gmx", "editconf", "-f", out_gro, "-o", out_pdb], cwd=work_dir, check=True)
    except subprocess.CalledProcessError as e:
        print(f"[ERROR-POST-4] trjconv/editconf final structure extraction failed for replica {r}: {e}")
        log_pipeline_msg("Step 13", f"Process failed: {e}", is_error=True)
        continue

    centered_xtcs.append(out_xtc)

if centered_xtcs:
    print("\n[-] Concatenating Replicas end-to-end into mixed_frames.xtc...")
    trjcat_cmd = ["gmx", "trjcat", "-f"] + centered_xtcs + ["-o", "mixed_frames.xtc", "-cat"]
    try:
        subprocess.run(trjcat_cmd, cwd=work_dir, universal_newlines=True, check=True)
    except subprocess.CalledProcessError as e:
        print(f"[ERROR-POST-5] trjcat failed for mixed_frames: {e}")
        log_pipeline_msg("Step 13", f"Process failed: {e}", is_error=True)

    print("[-] Extracting final structure for mixed frames...")
    try:
        ref_gro = f"stripped_rep{replicas[0]}.gro"
        subprocess.run(["gmx", "trjconv", "-s", ref_gro, "-f", "mixed_frames.xtc", "-dump", "9999999", "-o", "mixed_frames.gro"], cwd=work_dir, input=f"0\n", universal_newlines=True, check=True)
        subprocess.run(["gmx", "editconf", "-f", "mixed_frames.gro", "-o", "mixed_frames.pdb"], cwd=work_dir, check=True)
    except subprocess.CalledProcessError as e:
        print(f"[ERROR-POST-6] trjconv/editconf failed for mixed_frames: {e}")
        log_pipeline_msg("Step 13", f"Process failed: {e}", is_error=True)

    print("[-] Writing metadata CSV...")
    with open(os.path.join(work_dir, "mixed_frames_metadata.csv"), "w") as f:
        f.write("Replica,Status\n")
        for r in replicas:
            f.write(f"{r},Included in mixed_frames sequentially\n")

print("\n[-] SUCCESS! Multi-replica post-processing completed.")
log_pipeline_msg("Step 13", "OK")
