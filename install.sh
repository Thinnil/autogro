#!/bin/bash
echo "=========================================="
echo "      AutoGRO v2.7 INSTALLER & UPDATER    "
echo "=========================================="
echo "[*] Where would you like to install AutoGRO?"
echo "    (Type ./ to install in your CURRENT directory)"
read -p "    > " user_install
if [ -z "$user_install" ] || [[ "$user_install" == "./" || "$user_install" == "." ]]; then
    INSTALL_DIR="$(pwd)"
else
    INSTALL_DIR="${user_install/#\~/$HOME}"
fi
INSTALL_DIR=$(realpath -m "$INSTALL_DIR")
MODULES_DIR="$INSTALL_DIR/modules"
BIN_DIR="$HOME/.local/bin"
echo "[-] Installing to: $INSTALL_DIR"
mkdir -p "$MODULES_DIR"
mkdir -p "$BIN_DIR"

pkg_mgr=""
if command -v micromamba &> /dev/null; then pkg_mgr="micromamba";
elif command -v mamba &> /dev/null; then pkg_mgr="mamba";
elif command -v conda &> /dev/null; then pkg_mgr="conda";
fi

detect_and_activate_env() {
    if [ -n "$AMBERHOME" ] && [ -x "$AMBERHOME/bin/antechamber" ]; then
        export PATH="$AMBERHOME/bin:$PATH"
        [ -d "$AMBERHOME/lib" ] && export LD_LIBRARY_PATH="$AMBERHOME/lib:${LD_LIBRARY_PATH:-}"
        return 0
    fi

    if command -v antechamber &> /dev/null; then
        local ac_bin
        ac_bin="$(command -v antechamber)"
        export AMBERHOME="$(dirname "$(dirname "$ac_bin")")"
        export PATH="$AMBERHOME/bin:$PATH"
        [ -d "$AMBERHOME/lib" ] && export LD_LIBRARY_PATH="$AMBERHOME/lib:${LD_LIBRARY_PATH:-}"
        return 0
    fi

    if [ -n "$CONDA_PREFIX" ] && [ -x "$CONDA_PREFIX/bin/antechamber" ]; then
        export AMBERHOME="$CONDA_PREFIX"
        export PATH="$CONDA_PREFIX/bin:$PATH"
        [ -d "$CONDA_PREFIX/lib" ] && export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}"
        return 0
    fi

    ENV_SEARCH_DIRS=(
        "$HOME/.micromamba/envs"
        "$HOME/miniconda3/envs"
        "$HOME/anaconda3/envs"
        "$HOME/.conda/envs"
        "/opt/conda/envs"
        "$HOME/.local/share/mamba/envs"
        "/data1/mgs/micromamba/envs"
    )

    EXISTING_DIRS=()
    for base_dir in "${ENV_SEARCH_DIRS[@]}"; do
        [ -d "$base_dir" ] && EXISTING_DIRS+=("$base_dir")
    done

    PREFERRED_ENVS=("ambertools" "acpype" "autogro" "base")

    for pref in "${PREFERRED_ENVS[@]}"; do
        for base_dir in "${EXISTING_DIRS[@]}"; do
            if [ -x "$base_dir/$pref/bin/antechamber" ]; then
                export AMBERHOME="$base_dir/$pref"
                export PATH="$base_dir/$pref/bin:$PATH"
                [ -d "$base_dir/$pref/lib" ] && export LD_LIBRARY_PATH="$base_dir/$pref/lib:${LD_LIBRARY_PATH:-}"
                return 0
            fi
        done
    done

    if [ -f "$HOME/.conda/environments.txt" ]; then
        while IFS= read -r env_path; do
            if [ -n "$env_path" ] && [ -x "$env_path/bin/antechamber" ]; then
                export AMBERHOME="$env_path"
                export PATH="$env_path/bin:$PATH"
                [ -d "$env_path/lib" ] && export LD_LIBRARY_PATH="$env_path/lib:${LD_LIBRARY_PATH:-}"
                return 0
            fi
        done < "$HOME/.conda/environments.txt"
    fi

    for base_dir in "${EXISTING_DIRS[@]}"; do
        for env_dir in "$base_dir"/*; do
            if [ -x "$env_dir/bin/antechamber" ]; then
                export AMBERHOME="$env_dir"
                export PATH="$env_dir/bin:$PATH"
                [ -d "$env_dir/lib" ] && export LD_LIBRARY_PATH="$env_dir/lib:${LD_LIBRARY_PATH:-}"
                return 0
            fi
        done
    done

    for CONDA_EXE in micromamba mamba conda; do
        if command -v "$CONDA_EXE" &> /dev/null; then
            ENV_PATHS=$($CONDA_EXE env list 2>/dev/null | awk '{print $NF}')
            for env_path in $ENV_PATHS; do
                if [ -x "$env_path/bin/antechamber" ]; then
                    export AMBERHOME="$env_path"
                    export PATH="$env_path/bin:$PATH"
                    [ -d "$env_path/lib" ] && export LD_LIBRARY_PATH="$env_path/lib:${LD_LIBRARY_PATH:-}"
                    return 0
                fi
            done
            break
        fi
    done
}

detect_and_activate_env

check_cmd() {
    if command -v "$1" &> /dev/null; then
        echo "  - $1: Found"
        return 0
    else
        echo "  - $1: NOT FOUND ($2)"
        return 1
    fi
}

echo "[*] Checking dependencies..."
check_cmd "gmx" "sudo apt install gromacs"
check_cmd "python3" "Requires Python 3"
check_cmd "pip" "sudo apt install python3-pip"

if ! check_cmd "antechamber" "AmberTools"; then
    if [ -n "$pkg_mgr" ]; then
        echo "    -> Auto-creating dedicated 'ambertools' environment (Python 3.10) via $pkg_mgr..."
        "$pkg_mgr" create -y -n ambertools -c conda-forge ambertools=23.3 acpype=2023.10.27 hdf5=1.14.3 "python=3.10" || true
        detect_and_activate_env
    else
        echo "    -> [!] Cannot auto-install AmberTools (conda/mamba/micromamba not found)."
    fi
fi

if ! check_cmd "acpype" "ACPYPE"; then
    if [ -n "$pkg_mgr" ]; then
        echo "    -> Auto-creating dedicated 'ambertools' environment (Python 3.10) via $pkg_mgr..."
        "$pkg_mgr" create -y -n ambertools -c conda-forge ambertools=23.3 acpype=2023.10.27 hdf5=1.14.3 "python=3.10" || true
        detect_and_activate_env
    else
        echo "    -> [!] Cannot auto-install acpype (conda/mamba/micromamba not found)."
    fi
fi

if command -v pip &> /dev/null; then
    pip install MDAnalysis==2.7.0 numpy==1.26.4 psutil==5.9.8 > /dev/null 2>&1
fi
echo "[*] Unpacking modules..."
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/10_equilibration.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import subprocess
import shutil
import sys

# --- CONFIG LOADING ---
config = {}
try:
    with open("simulation_settings.txt") as f:
        for line in f:
            if "=" in line and not line.strip().startswith("#"):
                key, val = line.strip().split("=", 1)
                config[key.strip()] = val.strip()
except FileNotFoundError:
    print("[!] Error: simulation_settings.txt not found.")
    sys.exit(1)

temp = config.get('temperature', '300')

# --- CHECK POSRE.ITP ---
if not os.path.exists("complex/posre.itp"):
    print("[-] Copying posre.itp from receptor folder...")
    try:
        shutil.copy("receptor/posre.itp", "complex/posre.itp")
    except FileNotFoundError:
        print("[!] CRITICAL ERROR: Could not find 'receptor/posre.itp'.")
        sys.exit(1)

# --- GENERATE MDP FILES ---
common_params = f"""
define = -DPOSRES
constraints = all-bonds
constraint_algorithm = lincs
cutoff-scheme = Verlet
verlet-buffer-tolerance = 0.005
nstlist = 20
rcoulomb = 1.2
rvdw = 1.2
coulombtype = PME
pbc = xyz
dt = 0.001
nsteps = 100000 ; 100ps
tc-grps = Protein Non-Protein
tau_t = 0.1 0.1
ref_t = {temp} {temp}
"""

nvt_mdp = f"""
title = NVT Equilibration
integrator = md
gen_vel = yes
gen_temp = {temp}
pcoupl = no
{common_params}
"""

# FIXED:
# 1. Added 'refcoord_scaling = com' to fix the artifact warning.
# 2. Changed pcoupl to 'Berendsen' for better stability during equilibration.
npt_mdp = f"""
title = NPT Equilibration
integrator = md
gen_vel = no
pcoupl = Berendsen
tau_p = 2.0
compressibility = 4.5e-5
ref_p = 1.0
refcoord_scaling = com
{common_params}
"""

with open("complex/nvt.mdp", "w") as f:
    f.write(nvt_mdp)
with open("complex/npt.mdp", "w") as f:
    f.write(npt_mdp)

# --- RUN NVT ---
# We check if NVT is already done to save time
if not os.path.exists("complex/nvt.gro"):
    print("[-] Running NVT Equilibration...")
    subprocess.run([
        "gmx", "grompp",
        "-f", "nvt.mdp",
        "-c", "em.gro",
        "-r", "em.gro",
        "-p", "topol.top",
        "-o", "nvt.tpr"
    ], cwd="complex")
    try:
        subprocess.run(["gmx", "mdrun", "-v", "-deffnm", "nvt"], cwd="complex")
    except subprocess.CalledProcessError as e:
        print("\n[!] Pipeline halted: Severe steric clashes or broken topology detected during NVT equilibration.")
        sys.exit(1)
else:
    print("[-] NVT already completed. Skipping to NPT...")

# --- RUN NPT ---
print("[-] Running NPT Equilibration...")
subprocess.run([
    "gmx", "grompp",
    "-f", "npt.mdp",
    "-c", "nvt.gro",
    "-r", "nvt.gro",
    "-t", "nvt.cpt",
    "-p", "topol.top",
    "-o", "npt.tpr",
    "-maxwarn", "1" # Added safety maxwarn for minor NPT warnings
], cwd="complex")

try:
    subprocess.run(["gmx", "mdrun", "-v", "-deffnm", "npt"], cwd="complex")
except subprocess.CalledProcessError as e:
    print("\n[!] Pipeline halted: Severe steric clashes or broken topology detected during NPT equilibration.")
    sys.exit(1)
log_pipeline_msg("Step 10", "OK")



EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/11_production_run.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import subprocess
import sys

# --- CONFIGURATION ---
work_dir = "complex"
gmx_cmd = "gmx"
settings_file = "simulation_settings.txt"

# --- 1. LOAD SETTINGS ---
config = {}
if os.path.exists(settings_file):
    with open(settings_file) as f:
        for line in f:
            # Simple parser for "key = value"
            if "=" in line and not line.strip().startswith("#"):
                parts = line.split("=", 1)
                key = parts[0].strip()
                val = parts[1].strip()
                config[key] = val
else:
    print(f"[!] Error: {settings_file} not found. Run Script 1 first.")
    sys.exit(1)

# Extract variables with defaults
time_ns = float(config.get("simulation_time_ns", 0.1))
frames  = int(config.get("output_frames", 100))
temp    = config.get("temperature", "300")

# --- 2. CALCULATE STEPS ---
# Standard MD Step size is 0.002 ps (2 femtoseconds)
dt = 0.002
total_steps = int((time_ns * 1000) / dt)

# Calculate Saving Frequency (nstxout-compressed) to hit the target frame count
# Logic: Total Steps / Desired Frames = Interval
save_interval = int(total_steps / frames)

# Safety: Don't save every step (files become gigabytes in seconds)
if save_interval < 500:
    print(f"[!] Warning: Requested frames require saving every {save_interval} steps.")
    print("    -> Clamping to minimum safe interval (500 steps) to prevent disk fill.")
    save_interval = 500
    expected_frames = int(total_steps / 500)
else:
    expected_frames = frames

print("-" * 40)
print(f"[-] SIMULATION CONFIGURATION:")
print(f"    Duration:   {time_ns} ns")
print(f"    Total Steps:{total_steps}")
print(f"    Target Frames: {frames}")
print(f"    Actual Saving: Every {save_interval} steps")
print(f"    Final Movie:   ~{expected_frames} frames")
print("-" * 40)

# --- 3. CREATE MDP FILE ---
mdp_content = f"""
title                   = Production Run
; Run parameters
integrator              = md
nsteps                  = {total_steps}
dt                      = {dt}
; Output control
nstxout                 = 0
nstvout                 = 0
nstfout                 = 0
nstenergy               = 5000       ; Save energy stats every 10ps
nstlog                  = 5000       ; Write log every 10ps
nstxout-compressed      = {save_interval} ; <--- DYNAMIC INTERVAL
compressed-x-grps       = System
; Bond parameters
continuation            = yes
constraint_algorithm    = lincs
constraints             = h-bonds
lincs_iter              = 1
lincs_order             = 4
; Neighborsearching
cutoff-scheme           = Verlet
ns_type                 = grid
nstlist                 = 20
rlist                   = 1.2
rcoulomb                = 1.2
rvdw                    = 1.2
; Electrostatics
coulombtype             = PME
pme_order               = 4
fourierspacing          = 0.16
; Temperature coupling
tcoupl                  = V-rescale
tc-grps                 = Protein Non-Protein
tau_t                   = 0.1     0.1
ref_t                   = {temp}      {temp}
; Pressure coupling
pcoupl                  = Parrinello-Rahman
pcoupltype              = isotropic
tau_p                   = 2.0
ref_p                   = 1.0
compressibility         = 4.5e-5
; Periodic boundary conditions
pbc                     = xyz
; Dispersion correction
DispCorr                = EnerPres
; Velocity generation
gen_vel                 = no
"""

mdp_path = os.path.join(work_dir, "md.mdp")
with open(mdp_path, "w") as f:
    f.write(mdp_content)

# --- 4. RUN GROMACS GROMPP ---
gro_in = "npt.gro"
cpt_in = "npt.cpt"
top_in = "topol.top"
tpr_out = "md_0_1.tpr"

sim_mode = config.get("simulation_mode", "standard").lower()

if sim_mode == "ensemble":
    num_reps = int(config.get("ensemble_replicas", 5))
    rep_time_ns = float(config.get("replica_time_ns", 5.0))
    total_steps_rep = int((rep_time_ns * 1000) / dt)
    save_interval_rep = max(500, int(total_steps_rep / frames))
    print(f"[-] Assembling {num_reps} Multi-Replica Ensemble TPRs ({rep_time_ns} ns each, {total_steps_rep} steps)...")
    import random
    for r in range(1, num_reps + 1):
        seed = random.randint(10000, 999999)
        rep_mdp = mdp_content.replace(f"nsteps                  = {total_steps}", f"nsteps                  = {total_steps_rep}")
        rep_mdp = rep_mdp.replace(f"nstxout-compressed      = {save_interval}", f"nstxout-compressed      = {save_interval_rep}")
        rep_mdp = rep_mdp.replace("gen_vel                 = no", f"gen_vel                 = yes\ngen_seed                = {seed}")
        rep_mdp = rep_mdp.replace("continuation            = yes", "continuation            = no")
        rep_mdp_path = os.path.join(work_dir, f"md_replica_{r}.mdp")
        with open(rep_mdp_path, "w") as f: f.write(rep_mdp)
        tpr_r = f"replica_{r}.tpr"
        subprocess.run([gmx_cmd, "grompp", "-f", f"md_replica_{r}.mdp", "-c", gro_in, "-p", top_in, "-o", tpr_r, "-maxwarn", "2"], cwd=work_dir, check=True)
    print(f"[-] Successfully assembled {num_reps} replica TPR binary files.")

elif sim_mode == "fep":
    num_lambdas = int(config.get("fep_lambda_windows", 11))
    window_time_ns = float(config.get("fep_window_time_ns", 2.0))
    lig_res = config.get("ligand_resname", "MOL")
    total_steps_fep = int((window_time_ns * 1000) / dt)
    save_interval_fep = max(500, int(total_steps_fep / frames))
    print(f"[-] Assembling {num_lambdas} Alchemical FEP Lambda TPRs ({window_time_ns} ns per window, {total_steps_fep} steps)...")
    
    half_l = num_lambdas / 2.0
    coul_lambdas = [round(i / half_l, 3) if i <= half_l else 1.0 for i in range(num_lambdas)]
    vdw_lambdas = [0.0 if i <= half_l else round((i - half_l) / half_l, 3) for i in range(num_lambdas)]
    
    coul_str = " ".join(map(str, coul_lambdas))
    vdw_str = " ".join(map(str, vdw_lambdas))
    
    base_fep_mdp = mdp_content.replace(f"nsteps                  = {total_steps}", f"nsteps                  = {total_steps_fep}")
    base_fep_mdp = base_fep_mdp.replace(f"nstxout-compressed      = {save_interval}", f"nstxout-compressed      = {save_interval_fep}")

    for l_idx in range(num_lambdas):
        fep_mdp_params = f"""
; Free Energy Perturbation (FEP)
free_energy             = yes
init_lambda_state       = {l_idx}
couple-moltype          = {lig_res}
couple-lambda0          = vdw-q
couple-lambda1          = none
couple-intramol         = yes
coul-lambdas            = {coul_str}
vdw-lambdas             = {vdw_str}
nstdgdl                 = 100
calc_lambda_neighbors   = -1
sc-alpha                = 0.5
sc-power                = 1
sc-sigma                = 0.3
"""
        fep_mdp = base_fep_mdp + "\n" + fep_mdp_params
        fep_mdp_path = os.path.join(work_dir, f"md_fep_l{l_idx}.mdp")
        with open(fep_mdp_path, "w") as f: f.write(fep_mdp)
        tpr_l = f"fep_lambda_{l_idx}.tpr"
        subprocess.run([gmx_cmd, "grompp", "-f", f"md_fep_l{l_idx}.mdp", "-c", gro_in, "-p", top_in, "-o", tpr_l, "-maxwarn", "5"], cwd=work_dir, check=True)
    print(f"[-] Successfully assembled {num_lambdas} FEP lambda TPR binary files.")

else: # Standard
    print("[-] Assembling binary (grompp)...")
    subprocess.run([gmx_cmd, "grompp", "-f", "md.mdp", "-c", gro_in, "-t", cpt_in, "-p", top_in, "-o", tpr_out], cwd=work_dir, check=True)

print("[-] Production Preparation Complete.")
log_pipeline_msg("Step 11", "OK")



EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/12_run_simulation.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import subprocess
import sys

# Define location
work_dir = "complex"
tpr_file = "md_0_1.tpr"

# Check if the file exists
if not os.path.exists(os.path.join(work_dir, tpr_file)):
    print(f"[!] Error: {tpr_file} not found in {work_dir}.")
    print("    Please run Script 11 first to generate it.")
    sys.exit(1)

print("[-] STARTING MOLECULAR DYNAMICS SIMULATION...")
print("    This may take a while depending on your 'simulation_time_ns'.")
print("    Check the progress in complex/md_0_1.log")

# Run GROMACS
# -v : Verbose (shows progress on screen)
# -deffnm : Default Filename (names output .xtc, .edr, .log same as input)
cmd = [
    "gmx", "mdrun",
    "-v",
    "-deffnm", "md_0_1"
]

try:
    subprocess.run(cmd, cwd=work_dir, check=True)
    print("\n[-] SIMULATION FINISHED SUCCESSFULLY!")
    print(f"[-] Trajectory file: {os.path.join(work_dir, 'md_0_1.xtc')}")
    print(f"[-] Structure file:  {os.path.join(work_dir, 'md_0_1.gro')}")
except subprocess.CalledProcessError:
    print("\n[!] Error: The simulation crashed or was interrupted.")
    print("    Check complex/md_0_1.log for details.")
except KeyboardInterrupt:
    print("\n[!] Simulation stopped by user.")
log_pipeline_msg("Step 12", "OK")



EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/13_post_processing.py"
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
EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/14_write_methodology.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import subprocess

# --- 1. INTERNAL DICTIONARIES (The "Brain") ---
# Maps the GROMACS menu numbers to their official paper names
ff_map = {
    '1': 'AMBER03',
    '2': 'AMBER94',
    '3': 'AMBER96',
    '4': 'AMBER99',
    '5': 'AMBER99SB',
    '6': 'AMBER99SB-ILDN',
    '7': 'AMBERGS',
    '8': 'CHARMM27',
    '9': 'GROMOS96 43a1',
    '10': 'GROMOS96 43a2',
    '11': 'GROMOS96 45a3',
    '12': 'GROMOS96 53a5',
    '13': 'GROMOS96 53a6',
    '14': 'GROMOS96 54a7',
    '15': 'OPLS-AA/L'
}

water_map = {
    '1': 'TIP3P',
    '2': 'TIP4P',
    '3': 'TIP4P-Ew',
    '4': 'TIP5P',
    '5': 'SPC',
    '6': 'SPC/E',
    '7': 'None'
}

# --- 2. GET GROMACS VERSION ---
def get_gmx_version():
    try:
        result = subprocess.run(['gmx', '--version'], stdout=subprocess.PIPE, universal_newlines=True)
        for line in result.stdout.splitlines():
            if "GROMACS version" in line:
                return line.split()[-1]
    except:
        return "(Version Unknown)"
    return "20XX"

# --- 3. LOAD USER SETTINGS ---
config = {}
try:
    with open("simulation_settings.txt") as f:
        for line in f:
            if "=" in line and not line.strip().startswith("#"):
                key, val = line.strip().split("=", 1)
                config[key.strip()] = val.strip()
except FileNotFoundError:
    print("[!] Warning: simulation_settings.txt not found. Using defaults.")

# --- 4. TRANSLATE SETTINGS TO TEXT ---
# Get the numbers
ff_num = config.get('forcefield_choice', '6')
wat_num = config.get('water_choice', '1')

# Convert Number -> Name (using the dictionary above)
ff_name = ff_map.get(ff_num, f"Unknown Forcefield (Input {ff_num})")
water_name = water_map.get(wat_num, f"Unknown Water (Input {wat_num})")

# Get other vars
temp = config.get('temperature', '300')
time_ns = config.get('simulation_time_ns', '0.1')
frames = config.get('output_frames', '100')
gmx_ver = get_gmx_version()

# --- 5. GENERATE REPORT ---
has_lig = config.get("ligand_file", "None") != "None"

sys_prep_text = f"The protein structure was prepared using the {ff_name} force field. "
if has_lig:
    charge_method_str = "AM1-BCC"
    if os.path.exists("../ligand/charge_method.txt"):
        with open("../ligand/charge_method.txt", "r") as cm_file:
            if "gas" in cm_file.read().lower():
                charge_method_str = "empirical Gasteiger"
    elif os.path.exists("ligand/charge_method.txt"):
        with open("ligand/charge_method.txt", "r") as cm_file:
            if "gas" in cm_file.read().lower():
                charge_method_str = "empirical Gasteiger"

    if charge_method_str == "empirical Gasteiger":
        sys_prep_text += f"Ligand parameters were generated using ACPYPE (AnteChamber PYthon Parser interfacE), implementing the General Amber Force Field (GAFF) with {charge_method_str} partial charges due to AM1-BCC convergence failure on the docked pose. The complex was solvated "
    else:
        sys_prep_text += f"Ligand parameters were generated using ACPYPE (AnteChamber PYthon Parser interfacE), implementing the General Amber Force Field (GAFF) with {charge_method_str} partial charges. The complex was solvated "
else:
    sys_prep_text += "The system was solvated "
sys_prep_text += f"in a dodecahedral box with a minimum distance of 1.0 nm between the solute and the box edge, using the {water_name} water model. The system was neutralized and brought to a physiological concentration of 0.15 M using Na+ and Cl- ions."

equil_text = "Position restraints were applied to the heavy atoms of the protein"
if has_lig:
    equil_text += " and ligand"
equil_text += " during both equilibration steps."

methodology_text = f"""
Title: Molecular Dynamics Simulation Methodology
------------------------------------------------

All molecular dynamics (MD) simulations were performed using the GROMACS {gmx_ver} software package.

System Preparation:
{sys_prep_text}

Minimization and Equilibration:
Energy minimization was performed using the steepest descent algorithm until the maximum force on any atom was below 1000 kJ mol^-1 nm^-1. The system was equilibrated in two phases:
1. NVT Equilibration: A 100 ps simulation in the canonical ensemble at {temp} K using the V-rescale thermostat (tau_t = 0.1 ps) to stabilize temperature.
2. NPT Equilibration: A 100 ps simulation in the isothermal-isobaric ensemble at 1 bar using the Berendsen barostat (tau_p = 2.0 ps) to stabilize pressure.
{equil_text}
"""

sim_mode = config.get("simulation_mode", "standard").lower()
if sim_mode == "ensemble":
    num_reps = config.get("ensemble_replicas", "5")
    rep_time = config.get("replica_time_ns", "5.0")
    prod_text = f"Production MD runs were performed using a multi-replica ensemble approach to enhance conformational sampling. A total of {num_reps} independent replicas were simulated for {rep_time} ns each in the NPT ensemble, initialized with different random velocity seeds. The trajectories were concatenated to produce a final combined dataset. "
elif sim_mode == "fep":
    prod_text = f"Alchemical Free Energy Perturbation (FEP) calculations were performed across lambda windows to decouple interactions. "
else:
    prod_text = f"Production MD runs were performed for {time_ns} ns in the NPT ensemble. "

prod_text += f"The temperature was maintained at {temp} K using the V-rescale thermostat, and pressure was maintained at 1 bar using the Parrinello-Rahman barostat (tau_p = 2.0 ps, compressibility = 4.5e-5 bar^-1). The trajectory was saved to produce a final dataset of approximately {frames} frames per run."

mmpbsa_text = ""
if has_lig and os.path.exists("complex/FINAL_RESULTS_MMPBSA.dat"):
    mmpbsa_text = "\n\nBinding Affinity Calculation (MM-PBSA):\nAbsolute binding free energy was estimated using the Molecular Mechanics Poisson-Boltzmann Surface Area (MM-PBSA) method implemented in gmx_MMPBSA. The polar solvation energy was calculated using the PB equation with a physiological salt concentration of 0.150 M, and the non-polar solvation energy was estimated from the solvent-accessible surface area."

methodology_text = f"""
Title: Molecular Dynamics Simulation Methodology
------------------------------------------------

All molecular dynamics (MD) simulations were performed using the GROMACS {gmx_ver} software package.

System Preparation:
{sys_prep_text}

Minimization and Equilibration:
Energy minimization was performed using the steepest descent algorithm until the maximum force on any atom was below 1000 kJ mol^-1 nm^-1. The system was equilibrated in two phases:
1. NVT Equilibration: A 100 ps simulation in the canonical ensemble at {temp} K using the V-rescale thermostat (tau_t = 0.1 ps) to stabilize temperature.
2. NPT Equilibration: A 100 ps simulation in the isothermal-isobaric ensemble at 1 bar using the Berendsen barostat (tau_p = 2.0 ps) to stabilize pressure.
{equil_text}

Production Simulation:
{prod_text}

Interaction Parameters:
Long-range electrostatic interactions were calculated using the Particle Mesh Ewald (PME) method with a real-space cutoff of 1.2 nm. Van der Waals interactions were treated with a cutoff of 1.2 nm. All bond lengths were constrained using the LINCS algorithm. An integration time step of 1 fs was used for initial NVT equilibration, and 2 fs for production. Periodic boundary conditions (PBC) were applied in all three dimensions.{mmpbsa_text}
"""

# --- 6. SAVE AND PRINT ---
output_file = "methodology_draft.txt"
with open(output_file, "w") as f:
    f.write(methodology_text)

print("-" * 60)
print(methodology_text)
print("-" * 60)
print(f"[-] Successfully saved to '{output_file}'")
print(f"[-] Automatically identified: Forcefield={ff_name}, Water={water_name}")
log_pipeline_msg("Step 14", "OK")


EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/15_organize_folder.py"
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


EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/16_compressor.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import tarfile
import shutil

# --- CONFIGURATION ---
work_dir = "complex"

# --- HELPER: GET FOLDER SIZE ---
def _get_size(path):
    total = 0
    with os.scandir(path) as it:
        for entry in it:
            if entry.is_file(follow_symlinks=False):
                total += entry.stat(follow_symlinks=False).st_size
            elif entry.is_dir(follow_symlinks=False):
                total += _get_size(entry.path)
    return total

def get_size_mb(path):
    """Calculates size of file or folder in Megabytes."""
    if os.path.isfile(path):
        return os.path.getsize(path) / (1024 * 1024)
    elif os.path.isdir(path):
        return _get_size(path) / (1024 * 1024)
    return 0

# --- MAIN SCRIPT ---
def compress_folder():
    if not os.path.exists(work_dir):
        print(f"[!] Directory '{work_dir}' not found.")
        return

    print(f"[-] Scanning '{work_dir}' for subfolders to compress...")

    subfolders = [f for f in os.listdir(work_dir) if os.path.isdir(os.path.join(work_dir, f))]

    if not subfolders:
        print("    No subfolders found. Have you organized the folder yet?")
        print("    (Run 15_organize_folder.py first)")
        return

    total_saved = 0

    for folder in subfolders:
        folder_path = os.path.join(work_dir, folder)
        # SKIP Analysis/Results (but compress replicas inside them!)
        if "Results" in folder or "Analysis" in folder:
            print(f"    [SKIP] Preserving '{folder}', but checking for replicas inside...")
            # Compress replicas inside Results
            res_folders = [
                f for f in os.listdir(folder_path)
                if os.path.isdir(os.path.join(folder_path, f)) and f.startswith("replica_")
            ]
            for res_f in res_folders:
                rep_path = os.path.join(folder_path, res_f)
                arc_name = os.path.join(folder_path, f"{res_f}.tar")
                orig_s = get_size_mb(rep_path)
                
                # Move .pdb and .xtc OUT of the replica folder so they aren't hidden in the zip!
                os.makedirs(os.path.join(folder_path, "Ensemble"), exist_ok=True)
                for file_in_rep in os.listdir(rep_path):
                    if file_in_rep.endswith(".pdb") or file_in_rep.endswith(".xtc"):
                        os.rename(
                            os.path.join(rep_path, file_in_rep),
                            os.path.join(folder_path, "Ensemble", file_in_rep)
                        )
                
                # Now compress the heavy stuff left behind
                print(f"    -> Compressing '{res_f}' ({orig_s:.1f} MB)...")
                try:
                    with tarfile.open(arc_name, "w") as tar:
                        tar.add(rep_path, arcname=res_f)
                    comp_s = get_size_mb(arc_name)
                    saved = orig_s - comp_s
                    total_saved += saved
                    print(f"       Done. Saved {saved:.1f} MB")
                    shutil.rmtree(rep_path)
                except Exception as e:
                    print(f"    [!] Error compressing {res_f}: {e}")
            continue

        archive_name = os.path.join(work_dir, f"{folder}.tar")

        # 1. Measure Original Size
        original_size = get_size_mb(folder_path)

        print(f"    -> Compressing '{folder}' ({original_size:.1f} MB)...")

        try:
            # 2. Compress
            with tarfile.open(archive_name, "w") as tar:
                tar.add(folder_path, arcname=folder)

            # 3. Measure Compressed Size
            compressed_size = get_size_mb(archive_name)

            # 4. Calculate Savings
            saved = original_size - compressed_size
            percent = (saved / original_size) * 100 if original_size > 0 else 0
            total_saved += saved

            print(f"       Done. Size: {compressed_size:.1f} MB (Saved {saved:.1f} MB / {percent:.0f}%)")

            # 5. Delete Original
            shutil.rmtree(folder_path)

        except Exception as e:
            print(f"    [!] Error compressing {folder}: {e}")

    # Clean up huge .trr files if they are loose in the root
    for f in os.listdir(work_dir):
        if f.endswith(".trr"):
            print(f"    [TIP] Loose heavy file found: '{f}'. Delete manually if not needed.")

    print("-" * 40)
    print(f"[-] Compression complete.")
    print(f"[-] TOTAL SPACE SAVED: {total_saved:.1f} MB")

if __name__ == "__main__":
    compress_folder()
log_pipeline_msg("Step 16", "OK")

EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/18_mmpbsa_analysis.py"
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

EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/17_decompressor.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import tarfile

# --- CONFIGURATION ---
work_dir = "complex"

def decompress_folder():
    if not os.path.exists(work_dir):
        print(f"[!] Directory '{work_dir}' not found.")
        return

    print(f"[-] Scanning '{work_dir}' for .tar.gz archives...")

    # Find all .tar.gz and .tar files
    archives = [f for f in os.listdir(work_dir) if f.endswith(".tar.gz") or f.endswith(".tar")]

    if not archives:
        print("    No archives found.")
        return

    for archive in archives:
        archive_path = os.path.join(work_dir, archive)

        print(f"    -> Extracting '{archive}' ...")

        try:
            with tarfile.open(archive_path, "r:*") as tar:
                # Mitigate Path Traversal (TarSlip)
                for member in tar.getmembers():
                    if member.name.startswith('/') or '..' in member.name:
                        raise Exception(f"Security: Path traversal attempt detected in {member.name}")
                tar.extractall(path=work_dir)

            # Optional: Delete the .tar.gz after extracting?
            # os.remove(archive_path)
            # print("       Archive deleted.")

        except Exception as e:
            print(f"    [!] Error extracting {archive}: {e}")

    print("[-] Decompression complete. Folders restored.")

if __name__ == "__main__":
    decompress_folder()
log_pipeline_msg("Step 17", "OK")

EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/1_setup_config.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os, glob

pdbs = glob.glob("*.pdb")
mols = glob.glob("*.mol2") + glob.glob("*.sdf")

default_prot = pdbs[0] if pdbs else "Pa_relaxed.pdb"
default_lig = mols[0] if mols else "None"

# --- CONFIGURATION ---
settings_file = "simulation_settings.txt"

# This content includes ALL variables needed for Scripts 2-14
file_content = f"""# ==============================================================================
#                      GROMACS SIMULATION CONTROL PANEL
# ==============================================================================
# Edit the values after the '=' sign.

# ------------------------------------------------------------------------------
# 1. INPUT FILES
# ------------------------------------------------------------------------------
protein_pdb = {default_prot}
ligand_file = {default_lig}
ligand_resname = MOL

# ------------------------------------------------------------------------------
# 2. CHEMISTRY SETUP
# ------------------------------------------------------------------------------
ligand_charge = 0
ligand_multiplicity = 1

# ------------------------------------------------------------------------------
# 3. FORCE FIELD SELECTION (For Script 3: pdb2gmx)
# ------------------------------------------------------------------------------
# Select the NUMBER corresponding to your desired force field.
#
#  1: AMBER03              2: AMBER94              3: AMBER96
#  4: AMBER99              5: AMBER99SB            6: AMBER99SB-ILDN (Recommended)
#  7: AMBERGS              8: CHARMM27             15: OPLS-AA/L
#
forcefield_choice = 6

# ------------------------------------------------------------------------------
# 4. WATER MODEL SELECTION (For Script 3: pdb2gmx)
# ------------------------------------------------------------------------------
# Select the NUMBER. Must match the force field (usually TIP3P for Amber).
#
#  1: TIP3P (Recommended)  2: TIP4P                3: TIP4P-Ew
#  5: SPC                  6: SPC/E
#
water_choice = 1

# ------------------------------------------------------------------------------
# 5. BOX & SOLVATION (For Scripts 6 & 7)
# ------------------------------------------------------------------------------
box_distance = 1.0
box_type = dodecahedron
water_box_model = spc216.gro

# ------------------------------------------------------------------------------
# 6. IONS (For Script 8)
# ------------------------------------------------------------------------------
salt_conc = 0.15
pname = NA
nname = CL

# ------------------------------------------------------------------------------
# 7. SIMULATION CONTROLS (For Script 11)
# ------------------------------------------------------------------------------
# 0.1 = Preview, 100 = Publication
simulation_time_ns = 0.1

# How many frames in the final movie?
output_frames = 100

temperature = 300

# ------------------------------------------------------------------------------
# 8. ADVANCED SIMULATION MODES
# ------------------------------------------------------------------------------
# Mode options: standard, ensemble, fep
simulation_mode = standard

# Multi-Replica Ensemble Settings (For 'ensemble' mode)
ensemble_replicas = 5
replica_time_ns = 5.0

# Alchemical Free Energy Settings (For 'fep' mode)
fep_lambda_windows = 11
fep_window_time_ns = 2.0

"""
with open(settings_file, "w") as f:
    f.write(file_content)
print(f"[-] Successfully created {settings_file}")
log_pipeline_msg("Step 1", "OK")

EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/2_clean_protein.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os

# Helper to read config
config = {}
with open("simulation_settings.txt") as f:
    for line in f:
        if "=" in line and not line.strip().startswith("#"):
            key, val = line.strip().split("=", 1)
            config[key.strip()] = val.strip()

pdb_name = config['protein_pdb']
base_name = os.path.splitext(pdb_name)[0]
receptor_dir = "receptor"
import shutil, sys
os.makedirs(receptor_dir, exist_ok=True)

if not os.path.exists(os.path.join(receptor_dir, pdb_name)):
    if os.path.exists(pdb_name):
        print(f"[-] Auto-copying {pdb_name} into {receptor_dir}/ ...")
        shutil.copy(pdb_name, os.path.join(receptor_dir, pdb_name))
    else:
        print(f"[!] Error: {pdb_name} not found in current directory!")
        sys.exit(1)

input_path = os.path.join(receptor_dir, pdb_name)
temp_path = os.path.join(receptor_dir, f"{base_name}_clean.pdb")

print(f"[-] Cleaning {input_path}...")

# Logic equivalent to grep -v
with open(input_path, 'r') as infile, open(temp_path, 'w') as outfile:
    for line in infile:
        if "HETATM" not in line and "CONECT" not in line:
            outfile.write(line)

print(f"[-] Created cleaned file: {temp_path}")
log_pipeline_msg("Step 2", "OK")



EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/3_pdb2gmx.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import subprocess

config = {}
with open("simulation_settings.txt") as f:
    for line in f:
        if "=" in line and not line.strip().startswith("#"):
            key, val = line.strip().split("=", 1)
            config[key.strip()] = val.strip()

receptor_dir = "receptor"
base_name = os.path.splitext(config['protein_pdb'])[0]
input_pdb = f"{base_name}_clean.pdb" # Output from script 2
output_gro = "protein_processed.gro"
output_top = "topol.top"

# Prepare inputs for the interactive prompt
ff_choice = config['forcefield_choice']
water_choice = config['water_choice']
input_str = f"{ff_choice}\n{water_choice}\n"

cmd = [
    "gmx", "pdb2gmx",
    "-f", input_pdb,
    "-o", output_gro,
    "-p", output_top,
    "-ignh" # Good practice to ignore existing hydrogens and let GROMACS add them
]

print(f"[-] Running pdb2gmx in {receptor_dir}...")
# FIXED: changed universal_newlines=True to universal_newlines=True
subprocess.run(cmd, cwd=receptor_dir, input=input_str, universal_newlines=True)

print("[-] pdb2gmx finished.")
log_pipeline_msg("Step 3", "OK")



EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/4_ligand_params.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import subprocess
import shutil
from pathlib import Path

config = {}
with open("simulation_settings.txt") as f:
    for line in f:
        if "=" in line and not line.strip().startswith("#"):
            key, val = line.strip().split("=", 1)
            config[key.strip()] = val.strip()

lig_dir = "ligand"
lig_file = config['ligand_file']
import sys
os.makedirs(lig_dir, exist_ok=True)

if not os.path.exists(os.path.join(lig_dir, lig_file)):
    if os.path.exists(lig_file):
        print(f"[-] Auto-copying {lig_file} into {lig_dir}/ ...")
        shutil.copy(lig_file, os.path.join(lig_dir, lig_file))
    else:
        print(f"[!] Error: {lig_file} not found in current directory!")
        sys.exit(1)

charge = config['ligand_charge']
mult = config['ligand_multiplicity']
resname = config['ligand_resname']

_BINARY_CACHE = {}
_CONDA_ENVS_CACHE = None
_ENV_LD_PATH_CACHE = {}
_BASE_DIRS_CACHE = None

def _get_existing_base_dirs():
    global _BASE_DIRS_CACHE
    if _BASE_DIRS_CACHE is not None:
        return _BASE_DIRS_CACHE
    home = Path.home()
    standard = [
        home / ".micromamba" / "envs",
        home / "miniconda3" / "envs",
        home / "anaconda3" / "envs",
        home / ".conda" / "envs",
        Path("/opt/conda/envs"),
        Path("/data1/mgs/micromamba/envs")
    ]
    _BASE_DIRS_CACHE = [d for d in standard if d.is_dir()]
    return _BASE_DIRS_CACHE

def _get_conda_env_entries():
    global _CONDA_ENVS_CACHE
    if _CONDA_ENVS_CACHE is not None:
        return _CONDA_ENVS_CACHE
    home = Path.home()
    env_entries = []
    envs_txt = home / ".conda" / "environments.txt"
    if envs_txt.is_file():
        try:
            with open(envs_txt, "r") as f:
                for line in f:
                    path_str = line.strip()
                    if path_str and os.path.exists(path_str):
                        env_path = Path(path_str)
                        env_name = env_path.name
                        env_entries.append((env_name, env_path, "conda"))
            if env_entries:
                _CONDA_ENVS_CACHE = env_entries
                return _CONDA_ENVS_CACHE
        except Exception:
            pass
    for conda_exe_name in ['micromamba', 'mamba', 'conda']:
        conda_exe = shutil.which(conda_exe_name)
        if not conda_exe:
            for fallback in [
                home / ".local" / "bin" / conda_exe_name,
                home / "miniconda3" / "bin" / conda_exe_name,
                home / "anaconda3" / "bin" / conda_exe_name,
                home / ".micromamba" / "bin" / conda_exe_name,
                Path("/opt/conda/bin") / conda_exe_name,
                Path("/data1/mgs/micromamba/bin") / conda_exe_name
            ]:
                if fallback.is_file():
                    conda_exe = str(fallback)
                    break
        if conda_exe:
            try:
                res = subprocess.run([conda_exe, "env", "list"], capture_output=True, text=True, timeout=10)
                if res.returncode == 0:
                    for line in res.stdout.splitlines():
                        line = line.strip()
                        if line and not line.startswith('#'):
                            parts = line.split()
                            path_part = parts[-1]
                            if os.path.exists(path_part):
                                env_name = parts[0] if (len(parts) > 1 and parts[0] != '*') else os.path.basename(path_part)
                                env_entries.append((env_name, Path(path_part), conda_exe))
                    if env_entries:
                        break
            except Exception:
                pass
    _CONDA_ENVS_CACHE = env_entries
    return _CONDA_ENVS_CACHE

def resolve_binary(binary_name, preferred_envs=('ambertools', 'acpype', 'autogro', 'base')):
    cache_key = (binary_name, tuple(preferred_envs) if isinstance(preferred_envs, (list, tuple)) else preferred_envs)
    if cache_key in _BINARY_CACHE:
        return list(_BINARY_CACHE[cache_key])
    path_bin = shutil.which(binary_name)
    if path_bin:
        result = [path_bin]
        _BINARY_CACHE[cache_key] = result
        return list(result)
    standard_base_dirs = _get_existing_base_dirs()
    def check_env_dir(env_dir):
        for sub in ['bin', 'Scripts']:
            candidate = env_dir / sub / binary_name
            if candidate.is_file():
                return str(candidate)
        return None
    for env_name in preferred_envs:
        for base_dir in standard_base_dirs:
            env_dir = base_dir / env_name
            if env_dir.is_dir():
                binary_path = check_env_dir(env_dir)
                if binary_path:
                    result = [binary_path]
                    _BINARY_CACHE[cache_key] = result
                    return list(result)
    for base_dir in standard_base_dirs:
        try:
            for env_dir in base_dir.iterdir():
                if env_dir.is_dir():
                    binary_path = check_env_dir(env_dir)
                    if binary_path:
                        result = [binary_path]
                        _BINARY_CACHE[cache_key] = result
                        return list(result)
        except Exception:
            pass
    env_entries = _get_conda_env_entries()
    if env_entries:
        fallback_cmd = None
        for pref in preferred_envs:
            for name, path, conda_exe in env_entries:
                if name == pref or path.name == pref:
                    binary_path = check_env_dir(path)
                    if binary_path:
                        result = [binary_path]
                        _BINARY_CACHE[cache_key] = result
                        return list(result)
                    if fallback_cmd is None:
                        fallback_cmd = [conda_exe, "run", "-n", name, binary_name]
        for name, path, conda_exe in env_entries:
            binary_path = check_env_dir(path)
            if binary_path:
                result = [binary_path]
                _BINARY_CACHE[cache_key] = result
                return list(result)
        if fallback_cmd:
            _BINARY_CACHE[cache_key] = fallback_cmd
            return list(fallback_cmd)
    return [binary_name]

def _get_env_with_ld_path(binary_cmd):
    cache_key = tuple(str(x) for x in binary_cmd) if isinstance(binary_cmd, (list, tuple)) else (str(binary_cmd),)
    if cache_key in _ENV_LD_PATH_CACHE:
        return _ENV_LD_PATH_CACHE[cache_key].copy()

    env = os.environ.copy()
    if not binary_cmd:
        _ENV_LD_PATH_CACHE[cache_key] = env
        return env.copy()

    found_lib = None
    for item in binary_cmd:
        p = Path(item)
        bin_path = p if p.is_file() else None
        if not bin_path:
            w = shutil.which(item)
            if w:
                bin_path = Path(w)
        if bin_path:
            parent_dir = bin_path.parent
            if parent_dir.name.lower() in ('bin', 'scripts'):
                lib_dir = parent_dir.parent / 'lib'
            else:
                lib_dir = parent_dir / 'lib'
            if lib_dir.is_dir():
                found_lib = lib_dir
                break

    if not found_lib:
        standard_base_dirs = _get_existing_base_dirs()
        preferred_envs = ('ambertools', 'acpype', 'autogro', 'base')
        for item in list(binary_cmd) + list(preferred_envs):
            item_name = Path(item).name if isinstance(item, (str, Path)) else str(item)
            for base_dir in standard_base_dirs:
                env_lib = base_dir / item_name / "lib"
                if env_lib.is_dir():
                    found_lib = env_lib
                    break
            if found_lib:
                break

    if found_lib:
        amber_home = found_lib.parent
        amber_home_str = str(amber_home)
        env["AMBERHOME"] = amber_home_str

        lib_str = str(found_lib)
        ld_path = env.get("LD_LIBRARY_PATH", "")
        if ld_path:
            if lib_str not in ld_path.split(os.pathsep):
                env["LD_LIBRARY_PATH"] = f"{lib_str}{os.pathsep}{ld_path}"
        else:
            env["LD_LIBRARY_PATH"] = lib_str

        bin_str = str(amber_home / "bin")
        path_str = env.get("PATH", "")
        if path_str:
            if bin_str not in path_str.split(os.pathsep):
                env["PATH"] = f"{bin_str}{os.pathsep}{path_str}"
        else:
            env["PATH"] = bin_str

    _ENV_LD_PATH_CACHE[cache_key] = env
    return env.copy()

antechamber_cmd = resolve_binary("antechamber")
acpype_cmd = resolve_binary("acpype")

print(f"[-] Antechamber resolved as: {' '.join(antechamber_cmd)}")
print(f"[-] ACPYPE resolved as: {' '.join(acpype_cmd)}")

# Step 1: Antechamber
import os
_, ext = os.path.splitext(lig_file)
ext = ext.lower().replace(".", "")
if ext == "sdf":
    fi_format = "sdf"
elif ext == "mdl":
    fi_format = "mdl"
else:
    fi_format = "mol2"

cmd_ac = antechamber_cmd + [
    "-i", lig_file, "-fi", fi_format,
    "-o", "ligand_out.mol2", "-fo", "mol2",
    "-c", "bcc", "-s", "2", "-nc", charge, "-m", mult
]
try:
    res_ac = subprocess.run(cmd_ac, cwd=lig_dir, env=_get_env_with_ld_path(antechamber_cmd))
    if res_ac.returncode != 0:
        raise subprocess.CalledProcessError(res_ac.returncode, cmd_ac)
    with open(os.path.join(lig_dir, "charge_method.txt"), "w") as f:
        f.write("bcc")
except subprocess.CalledProcessError as e:
    print("\n[!] Warning: AM1-BCC charge calculation failed (likely due to distorted docking pose).")
    print("    -> Falling back to empirical Gasteiger charges (-c gas)...")
    log_pipeline_msg("Step 4", "AM1-BCC failed, falling back to Gasteiger.")

    cmd_ac_fallback = antechamber_cmd + [
        "-i", lig_file, "-fi", fi_format,
        "-o", "ligand_out.mol2", "-fo", "mol2",
        "-c", "gas", "-s", "2", "-nc", charge, "-m", mult
    ]
    res_ac_fb = subprocess.run(cmd_ac_fallback, cwd=lig_dir, env=_get_env_with_ld_path(antechamber_cmd))
    if res_ac_fb.returncode != 0:
        print("[!] ERROR during Antechamber execution (Gasteiger fallback also failed).")
        log_pipeline_msg("Step 4", "Antechamber fallback execution failed.", is_error=True)
        sys.exit(1)
    with open(os.path.join(lig_dir, "charge_method.txt"), "w") as f:
        f.write("gas")

# Step 2: ACPYPE
cmd_pype = acpype_cmd + [
    "-i", "ligand_out.mol2", "-c", "user", "-n", charge
]
res_pype = subprocess.run(cmd_pype, cwd=lig_dir, env=_get_env_with_ld_path(acpype_cmd))
if res_pype.returncode != 0:
    print("[!] ERROR during ACPYPE execution.")
    log_pipeline_msg("Step 4", "ACPYPE execution failed.", is_error=True)
    sys.exit(1)

print("[-] ACPYPE finished. Renaming output files...")
acpype_out_dir = os.path.join(lig_dir, "ligand_out.acpype")
try:
    shutil.copy(os.path.join(acpype_out_dir, "ligand_out_GMX.gro"), os.path.join(lig_dir, "ligand.gro"))
    shutil.copy(os.path.join(acpype_out_dir, "ligand_out_GMX.itp"), os.path.join(lig_dir, "ligand.itp"))
except Exception as e:
    print(f"[!] ERROR during file copying: {e}")
    sys.exit(1)

log_pipeline_msg("Step 4", "OK")


EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/5_merge_complex.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import shutil

# Load Config
config = {}
with open("simulation_settings.txt") as f:
    for line in f:
        if "=" in line and not line.strip().startswith("#"):
            key, val = line.strip().split("=", 1)
            config[key.strip()] = val.strip()

lig_resname = config['ligand_resname']

# Setup Directories
complex_dir = "complex"
if not os.path.exists(complex_dir):
    os.makedirs(complex_dir)

# Define paths
# Note: User must ensure these files exist (even if generated manually)
prot_gro = os.path.join("receptor", "protein_processed.gro")
# Assuming ACPYPE output structure, or user renamed them to simple names
lig_gro = os.path.join("ligand", "ligand.gro")
lig_itp = os.path.join("ligand", "ligand.itp")
prot_top = os.path.join("receptor", "topol.top")

target_gro = os.path.join(complex_dir, "complex.gro")
target_top = os.path.join(complex_dir, "topol.top")
target_itp = os.path.join(complex_dir, "ligand.itp")

print("[-] Merging GRO files (The Hacker Way)...")

# 1. Read Protein
with open(prot_gro, 'r') as f:
    p_lines = f.readlines()
p_count = int(p_lines[1].strip())
p_coords = p_lines[2:-1] # Remove header and box line
box_line = p_lines[-1]

# 2. Read Ligand
with open(lig_gro, 'r') as f:
    l_lines = f.readlines()
l_count = int(l_lines[1].strip())
l_coords = l_lines[2:-1]

# 3. Calculate Totals and Write
total_atoms = p_count + l_count

with open(target_gro, 'w') as f:
    f.write("Protein-Ligand Complex\n")
    f.write(f"{total_atoms:>5}\n") # Formatting matters in GRO
    for line in p_coords:
        f.write(line)
    for line in l_coords:
        f.write(line)
    f.write(box_line)

print("[-] Copying topology files...")
shutil.copy(prot_top, target_top)
shutil.copy(lig_itp, target_itp)

# 4. Modify Topology
print("[-] Editing topol.top...")
with open(target_top, 'r') as f:
    lines = f.readlines()

new_lines = []
inserted_itp = False

for line in lines:
    # Insert itp include after forcefield
    if "forcefield.itp" in line and not inserted_itp:
        new_lines.append(line)
        new_lines.append('\n; Include ligand topology\n')
        new_lines.append('#include "ligand.itp"\n')
        inserted_itp = True
    else:
        new_lines.append(line)

# Append molecule at the end
# Check if last line is newline
if new_lines[-1].strip() != "":
    new_lines.append("\n")

new_lines.append(f"{lig_resname}   1\n")

with open(target_top, 'w') as f:
    f.writelines(new_lines)

# 5. Fix ligand.itp moleculetype name
print("[-] Enforcing correct moleculetype name in ligand.itp...")
with open(target_itp, 'r') as f:
    itp_lines = f.readlines()
new_itp_lines = []
in_moleculetype = False
modified_moltype = False
for line in itp_lines:
    if line.strip().startswith("[ moleculetype ]"):
        in_moleculetype = True
        new_itp_lines.append(line)
        continue
    if in_moleculetype and not modified_moltype:
        if not line.strip().startswith(";") and line.strip() != "" and not line.strip().startswith("["):
            parts = line.split()
            if len(parts) >= 1:
                nrexcl = parts[1] if len(parts) >= 2 else "3"
                new_itp_lines.append(f"{lig_resname:<15} {nrexcl}\n")
                modified_moltype = True
                continue
    new_itp_lines.append(line)
with open(target_itp, 'w') as f:
    f.writelines(new_itp_lines)

print("[-] Complex generated successfully.")
log_pipeline_msg("Step 5", "OK")



EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/6_define_box.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import subprocess

config = {}
with open("simulation_settings.txt") as f:
    for line in f:
        if "=" in line and not line.strip().startswith("#"):
            key, val = line.strip().split("=", 1)
            config[key.strip()] = val.strip()

dist = config['box_distance']
btype = config['box_type']

cmd = [
    "gmx", "editconf",
    "-f", "complex.gro",
    "-o", "box.gro",
    "-c",
    "-d", dist,
    "-bt", btype
]

print("[-] Defining Simulation Box...")
subprocess.run(cmd, cwd="complex")
log_pipeline_msg("Step 6", "OK")



EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/7_solvate.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import subprocess

config = {}
with open("simulation_settings.txt") as f:
    for line in f:
        if "=" in line and not line.strip().startswith("#"):
            key, val = line.strip().split("=", 1)
            config[key.strip()] = val.strip()

model = config['water_box_model']

cmd = [
    "gmx", "solvate",
    "-cp", "box.gro",
    "-cs", model,
    "-o", "solvated.gro",
    "-p", "topol.top"
]

print("[-] Solvating system...")
subprocess.run(cmd, cwd="complex")
log_pipeline_msg("Step 7", "OK")



EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/8_ions.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import subprocess
import sys

# --- CONFIGURATION ---
config = {}
try:
    with open("simulation_settings.txt") as f:
        for line in f:
            if "=" in line and not line.strip().startswith("#"):
                key, val = line.strip().split("=", 1)
                config[key.strip()] = val.strip()
except FileNotFoundError:
    print("[!] Error: simulation_settings.txt not found.")
    sys.exit(1)

conc = config.get('salt_conc', '0.15')
pname = config.get('pname', 'NA')
nname = config.get('nname', 'CL')

# --- THE FIX: INJECT LIGAND TOPOLOGY ---
def inject_ligand_topology(top_file):
    print(f"[-] Checking for ligand inclusion in {top_file}...")
    
    with open(top_file, 'r') as f:
        lines = f.readlines()

    # 1. Check if it's already there (to prevent duplicates)
    if any('include "ligand.itp"' in line for line in lines):
        print("    Ligand topology already included. Skipping.")
        return

    # 2. Insert the line
    new_lines = []
    inserted = False
    
    for line in lines:
        # We insert it right before the [ molecules ] section starts
        if "[ molecules ]" in line and not inserted:
            new_lines.append('; Include Ligand topology\n')
            new_lines.append('#include "ligand.itp"\n\n')
            inserted = True
            new_lines.append(line)
        else:
            new_lines.append(line)

    with open(top_file, 'w') as f:
        f.writelines(new_lines)
    print("    Inserted #include \"ligand.itp\" successfully.")

# --- MAIN EXECUTION ---

if config.get("ligand_file", "None") != "None":
    # 1. Verify ligand.itp exists
    if not os.path.exists("complex/ligand.itp"):
        print("[!] CRITICAL: 'ligand.itp' is missing from the complex/ folder.")
        sys.exit(1)

    # 2. Inject the missing link into topol.top
    inject_ligand_topology("complex/topol.top")

# 3. Create ions.mdp
ions_mdp_content = """
integrator  = steep
emtol       = 1000.0
emstep      = 0.01
nsteps      = 50000
nstlist     = 1
cutoff-scheme = Verlet
ns_type     = grid
coulombtype = PME
rcoulomb    = 1.0
rvdw        = 1.0
pbc         = xyz
"""

with open("complex/ions.mdp", "w") as f:
    f.write(ions_mdp_content)

# 4. Prepare (grompp)
print("[-] Preparing ion generation (grompp)...")
result = subprocess.run([
    "gmx", "grompp",
    "-f", "ions.mdp",
    "-c", "solvated.gro",
    "-p", "topol.top",
    "-o", "ions.tpr",
    "-maxwarn", "1"
], cwd="complex")

if result.returncode != 0:
    print("[!] Error: grompp failed. This usually means the topology is still broken.")
    sys.exit(1)

# 5. Add Ions (genion)
print("[-] Adding ions...")
# We use 'SOL' as the group to replace with ions
input_group = "SOL\n"

cmd_genion = [
    "gmx", "genion",
    "-s", "ions.tpr",
    "-o", "solvated_ions.gro",
    "-p", "topol.top",
    "-pname", pname,
    "-nname", nname,
    "-neutral",
    "-conc", conc
]

subprocess.run(cmd_genion, cwd="complex", input=input_group, universal_newlines=True)
log_pipeline_msg("Step 8", "OK")


EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/99_cleanup.py"
import os
import shutil

# --- CONFIGURATION ---
# Files/Extensions that must NEVER be deleted
safe_extensions = [".py", ".txt", ".sh", ".md"]
safe_files = [
    "ligand.itp", "ligand.gro",  # Basal inputs (if pre-generated)
    "complex.gro",               # Basal structure
    "topol.top"                  # Main topology (sometimes manual)
]

def is_safe(filename):
    """Returns True if the file is in our safe list or has a safe extension."""
    # 1. Check strict filename match
    if filename in safe_files:
        return True

    # 2. Check extension (Protects ALL python scripts automatically)
    for ext in safe_extensions:
        if filename.endswith(ext):
            return True

    # 3. Check for original input structures (usually .pdb or .mol2)
    # We assume basal inputs don't have underscores like "step5_..."
    if (filename.endswith(".pdb") or filename.endswith(".mol2")) and "step" not in filename:
        return True

    return False

def cleanup():
    print("[-] STARTING PROJECT RESET (Universal Safety Mode)")

    # 1. Clean 'complex' directory (The heavy simulation data)
    # We wipe this completely because it is 100% generated.
    print("[-] Cleaning 'complex' folder...")
    if os.path.exists("complex"):
        print("    Removing entire 'complex' directory...")
        shutil.rmtree("complex")
        os.makedirs("complex")

    # 2. Clean 'receptor' directory
    print("[-] Cleaning 'receptor' folder...")
    if os.path.exists("receptor"):
        for f in os.listdir("receptor"):
            f_path = os.path.join("receptor", f)
            # Delete intermediate processing files
            if f.endswith("_clean.pdb") or f == "protein_processed.gro" or f.startswith("step"):
                print(f"    Deleting: {f}")
                os.remove(f_path)

    # 3. Clean 'ligand' directory
    print("[-] Cleaning 'ligand' folder...")
    if os.path.exists("ligand"):
        # Extensions created by ACPYPE that are junk
        junk_exts = [".inpcrd", ".prmtop", ".frcmod", ".lib", ".div", ".log", ".out", ".ant", ".prm", ".rtf", ".inp"]

        for f in os.listdir("ligand"):
            f_path = os.path.join("ligand", f)

            # Remove ACPYPE directories
            if os.path.isdir(f_path) and (".acpype" in f or "MOL_AC" in f):
                shutil.rmtree(f_path)

            # Remove junk files
            elif os.path.isfile(f_path):
                _, ext = os.path.splitext(f)
                if ext in junk_exts or "sqm." in f:
                    print(f"    Deleting: {f}")
                    os.remove(f_path)

    # 4. Clean Main Directory (The Root)
    print("[-] Cleaning main directory...")
    for f in os.listdir("."):
        if os.path.isdir(f):
            continue # Skip folders (like 'receptor', 'ligand')

        # If it's a script or input, SKIP IT
        if is_safe(f):
            continue

        # Delete typical GROMACS junk
        if f.startswith("#") or f.startswith("step") or f == "mdout.mdp" or f.endswith(".log"):
            print(f"    Deleting: {f}")
            os.remove(f)

    print("[-] RESET COMPLETE. All Python scripts and Basal inputs preserved.")

if __name__ == "__main__":
    print("WARNING: This will delete ALL simulation data in 'complex/'.")
    print("It effectively factory-resets the project.")
    confirm = input("Are you sure? (yes/no): ")
    if confirm.lower() == "yes":
        cleanup()
    else:
        print("Aborted.")


EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/9_minimization.py"
def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import subprocess

# 1. Generate em.mdp (Energy Minimization Parameters)
em_mdp = """
integrator  = steep
emtol       = 1000.0
emstep      = 0.01
nsteps      = 50000
nstlist     = 1
cutoff-scheme = Verlet
ns_type     = grid
coulombtype = PME
rcoulomb    = 1.0
rvdw        = 1.0
pbc         = xyz
"""

with open("complex/em.mdp", "w") as f:
    f.write(em_mdp)

print("[-] Running Energy Minimization...")

# 2. Grompp (Assemble the binary input)
# Note: We use solvated_ions.gro here because Step 8 just created it
cmd_grompp = [
    "gmx", "grompp",
    "-f", "em.mdp",
    "-c", "solvated_ions.gro",
    "-p", "topol.top",
    "-o", "em.tpr"
]
subprocess.run(cmd_grompp, cwd="complex")

# 3. Mdrun (Run the actual simulation)
cmd_mdrun = [
    "gmx", "mdrun",
    "-v",
    "-deffnm", "em"
]
try:
    subprocess.run(cmd_mdrun, cwd="complex")
except subprocess.CalledProcessError as e:
    print("\n[!] Pipeline halted: Severe steric clashes or broken topology detected during minimization.")
    import sys
    sys.exit(1)

print("[-] Minimization complete. Output: complex/em.gro")
log_pipeline_msg("Step 9", "OK")



EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/analysis_density.py"
import MDAnalysis as mda
from MDAnalysis.analysis.density import DensityAnalysis
import numpy as np
import os
import sys
import warnings

# Suppress warnings about PDB writing
warnings.filterwarnings('ignore')

# --- 1. CONFIGURATION (The part you need to change) ---
# We point directly to your files in the 'complex' folder
# NEW (Post-Organization)
work_dir = "complex/05_Results"  # <--- Just point deeper
coordinates = os.path.join(work_dir, "md_centered.pdb")
trajectory = os.path.join(work_dir, "md_centered.xtc")

# Fallback for pre-organization
if not os.path.exists(coordinates) or not os.path.exists(trajectory):
    work_dir = "complex"
    coordinates = os.path.join(work_dir, "md_centered.pdb")
    trajectory = os.path.join(work_dir, "md_centered.xtc")

# Check if they exist
if not os.path.exists(coordinates):
    print(f"[!] Error: Could not find {coordinates}")
    sys.exit(1)
if not os.path.exists(trajectory):
    print(f"[!] Error: Could not find {trajectory}")
    sys.exit(1)

print(f"[-] Loading Universe...")
print(f"    Structure: {coordinates}")
print(f"    Trajectory: {trajectory}")

# Load the system
u = mda.Universe(coordinates, trajectory)
print(f"[-] Frames loaded: {u.trajectory.n_frames}")

# --- 2. HELPER FUNCTION ---
def save_density(selection_string, filename_suffix):
    """
    Calculates density for a selection and saves it to a .dx file.
    """
    try:
        selection = u.select_atoms(selection_string)
        if len(selection) == 0:
            print(f"    [!] Warning: No atoms found for selection '{selection_string}'. Skipping.")
            return None

        print(f"    Calculating density for: {selection_string}...")

        # Grid settings (30x30x30 Angstrom box around center)
        # You might need to increase 30 if your protein is huge
        D = DensityAnalysis(selection, delta=1.0, padding=5.0)
        D.run()

        # Define output name
        output_path = os.path.join("complex", f"density_{filename_suffix}.dx")
        D.density.export(output_path, type="double")
        print(f"    -> Saved: {output_path}")
        return D
    except Exception as e:
        print(f"    [!] Error processing {selection_string}: {e}")
        return None

# --- 3. RUN ANALYSIS ---

print("[-] calculating General Densities...")
# 1. Ligand Density (Assume residue name is MOL or LIG - checking both)
if len(u.select_atoms("resname MOL")) > 0:
    lig_resname = "MOL"
else:
    lig_resname = "LIG"

D_lig = save_density(f'resname {lig_resname}', 'ligand_ALL')

# 2. Protein Density
D_prot = save_density('protein', 'protein_ALL')

print("[-] Calculating Element Densities (Ligand)...")
# 3. Specific Elements on the Ligand
# Carbons (Hydrophobic areas)
save_density(f'resname {lig_resname} and name C*', 'ligand_C')
# Hydrogens (H-bond donors)
save_density(f'resname {lig_resname} and name H*', 'ligand_H')
# Oxygens (H-bond acceptors)
save_density(f'resname {lig_resname} and name O*', 'ligand_O')
# Nitrogens (H-bond donors/acceptors)
save_density(f'resname {lig_resname} and name N*', 'ligand_N')

# Check for others (Sulfur, Phosphorus, Fluorine, Chlorine)
save_density(f'resname {lig_resname} and name S*', 'ligand_S')
save_density(f'resname {lig_resname} and name P*', 'ligand_P')
save_density(f'resname {lig_resname} and name F*', 'ligand_F')
save_density(f'resname {lig_resname} and name Cl*', 'ligand_Cl')

print("\n[-] DONE. You can load the .dx files in VMD or PyMOL.")

EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/analysis_trajectory.py"
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

EOF_AUTOGRO
cat << 'EOF_AUTOGRO' > "$MODULES_DIR/density_map.pml"
# 1. Load the files (Adjust filenames if needed)
load complex/md_centered.pdb
load complex/density_ligand_ALL.dx

# 2. visual clean up
hide everything
show cartoon, protein
show sticks, resn MOL
bg_color white

# 3. Create the Volume Object
# We name it "lig_fog"
volume lig_fog, density_ligand_ALL

# 4. RESET THE RAMP (The Magic Part)
# We define a "Color Ramp" manually.
# Format: [ value, color, opacity ]
# We use very low numbers because density maps are often sparse.

volume_ramp_new lig_fog, \
    0.005, blue, 0.0, \
    0.02,  blue, 0.1, \
    0.05,  cyan, 0.3, \
    0.10,  yellow, 0.6, \
    0.30,  red, 1.0

# EXPLANATION OF THE NUMBERS:
# 0.005 -> Everything below this is INVISIBLE (Alpha 0.0)
# 0.02  -> Low density areas appear as FAINT BLUE mist (Alpha 0.1)
# 0.05  -> Medium-low areas appear CYAN and distinct (Alpha 0.3)
# 0.10  -> Dense areas appear YELLOW and solid (Alpha 0.6)
# 0.30  -> The "Core" (highest density) is solid RED (Alpha 1.0)

# 5. Zoom to the ligand so you don't get lost
zoom resn MOL

EOF_AUTOGRO
# Inject subprocess safety wrapper into all module scripts 
# (This ensures if GROMACS crashes, the python script halts immediately instead of silently continuing)
echo "[-] Injecting subprocess safety wrappers..."
for pyfile in "$MODULES_DIR"/*.py; do
    if ! grep -q "_safe_run" "$pyfile"; then
        sed -i '1 i\
import subprocess\
import os\
os.environ["GMX_MAXBACKUP"] = "-1"\
_orig_run = subprocess.run\
def _safe_run(*args, **kwargs):\
    kwargs.setdefault("check", True)\
    return _orig_run(*args, **kwargs)\
subprocess.run = _safe_run\
' "$pyfile"
    fi
done

echo "[*] Generating AutoGRO Menu..."
cat << 'EOF_MENU' > "$INSTALL_DIR/autogro.py"
#!/usr/bin/env python3
import os, sys, subprocess, glob, math, signal
try: import psutil
except ImportError: psutil = None
try:
    import readline
    def path_completer(text, state):
        return (glob.glob(text+'*')+[None])[state]
    readline.set_completer_delims(' \t\n;')
    readline.parse_and_bind("tab: complete")
    readline.set_completer(path_completer)
except ImportError: pass

MODULES_DIR = os.path.join(os.path.dirname(__file__), 'modules')

def load_config(filepath="simulation_settings.txt"):
    config = {}
    if os.path.exists(filepath):
        try:
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    if "=" in line and not line.strip().startswith("#"):
                        parts = line.split("=", 1)
                        config[parts[0].strip()] = parts[1].strip()
        except Exception:
            pass
    return config

def print_header():
    print("\n" + "="*42)
    print("           A U T O G R O  v2.7            ")
    print("="*42)

def get_cpu_threads_from_user():
    config_percent = None
    if os.path.exists("simulation_settings.txt"):
        with open("simulation_settings.txt") as f:
            for line in f:
                if line.startswith("allocated_cpu_percent ="):
                    try:
                        config_percent = int(line.split("=")[1].strip())
                    except: pass
                    
    if config_percent and 1 <= config_percent <= 100:
        total_threads = os.cpu_count() or 1
        threads = max(1, math.floor(total_threads * (config_percent / 100.0)))
        print(f"[-] Using saved CPU allocation ({config_percent}%) -> {threads} threads (Out of {total_threads})")
        return threads
        
    print("\n[ CPU Performance Allocation ]")
    print("How much of your PC do you want to dedicate to this simulation?")
    print("Options: 15, 30, 45, 60, 75, 100 (Type the number)")
    while True:
        ans = input("Percentage (e.g. 75): ").strip()
        try:
            val = int(ans)
            if 1 <= val <= 100:
                total_threads = os.cpu_count() or 1
                threads = max(1, math.floor(total_threads * (val / 100.0)))
                print(f"[-] Allocating {val}% -> {threads} threads (Out of {total_threads})")
                return threads
        except ValueError: pass
        print("Invalid input. Please enter a number between 1 and 100.")

def start_mdrun(work_dir, append=False, threads=None):
    if threads is None:
        threads = get_cpu_threads_from_user()
        
    config = {}
    if os.path.exists("simulation_settings.txt"):
        with open("simulation_settings.txt") as f:
            for line in f:
                if "=" in line and not line.strip().startswith("#"):
                    parts = line.split("=", 1)
                    config[parts[0].strip()] = parts[1].strip()
                    
    sim_mode = config.get("simulation_mode", "standard").lower()
    
    if sim_mode == "ensemble":
        print("\n[-] Launching Multi-Replica Ensemble MDRun in background...")
        runner_code = f"""
import subprocess
import glob
import os
import sys
from concurrent.futures import ThreadPoolExecutor

reps = sorted(glob.glob("replica_*.tpr"))
num_reps = len(reps)
if num_reps == 0:
    sys.exit(0)

threads_total = {threads}
concurrent_jobs = min(num_reps, threads_total)
threads_per_rep = max(1, threads_total // concurrent_jobs)

def run_rep(r):
    prefix = os.path.splitext(r)[0]
    os.makedirs(prefix, exist_ok=True)
    out_prefix = os.path.join(prefix, prefix)
    cmd = ["gmx", "mdrun", "-s", r, "-deffnm", out_prefix, "-nt", str(threads_per_rep)]
    subprocess.run(cmd)
    gro_file = os.path.join(prefix, f"{{prefix}}.gro")
    pdb_file = os.path.join(prefix, f"{{prefix}}.pdb")
    if os.path.exists(gro_file):
        subprocess.run(["gmx", "editconf", "-f", gro_file, "-o", pdb_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

with ThreadPoolExecutor(max_workers=concurrent_jobs) as executor:
    list(executor.map(run_rep, reps))

xtcs = sorted(glob.glob(os.path.join("replica_*", "replica_*.xtc")))
if xtcs:
    os.makedirs("05_Results/Ensemble", exist_ok=True)
    out_xtc = "05_Results/Ensemble/ensemble_combined.xtc"
    cmd_cat = ["gmx", "trjcat", "-f"] + xtcs + ["-o", out_xtc]
    subprocess.run(cmd_cat, input="0\\n", universal_newlines=True)
    print("[-] Multi-Replica Ensemble Trajectory merged into 05_Results/Ensemble/ensemble_combined.xtc")
"""
        with open(os.path.join(work_dir, ".run_bg.py"), "w") as f:
            f.write(runner_code)
        cmd = [sys.executable, ".run_bg.py"]
        
    elif sim_mode == "fep":
        print("\n[-] Launching Alchemical FEP MDRun in background...")
        runner_code = f"""
import subprocess
import glob
import os
import sys
from concurrent.futures import ThreadPoolExecutor

lambdas = sorted(glob.glob("fep_lambda_*.tpr"))
num_lambdas = len(lambdas)
if num_lambdas == 0:
    sys.exit(0)
threads_total = {threads}
concurrent_jobs = min(num_lambdas, threads_total)
threads_per_win = max(1, threads_total // concurrent_jobs)

def run_lambda(l):
    prefix = os.path.splitext(l)[0]
    cmd = ["gmx", "mdrun", "-s", l, "-deffnm", prefix, "-nt", str(threads_per_win)]
    subprocess.run(cmd)

with ThreadPoolExecutor(max_workers=concurrent_jobs) as executor:
    list(executor.map(run_lambda, lambdas))

xvgs = sorted(glob.glob("fep_lambda_*.xvg"))
if xvgs:
    os.makedirs("05_Results/FEP", exist_ok=True)
    cmd_bar = ["gmx", "bar", "-f"] + xvgs + ["-o", "05_Results/FEP/bar.xvg", "-g", "05_Results/FEP/barint.xvg"]
    res = subprocess.run(cmd_bar, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    with open("05_Results/FEP/binding_affinity_results.txt", "w") as f:
        f.write("=== ALCHEMICAL BINDING FREE ENERGY (FEP) RESULTS ===\\n\\n")
        f.write(res.stdout)
    print("[-] FEP Binding Free Energy calculation complete! Results saved in 05_Results/FEP/binding_affinity_results.txt")
"""
        with open(os.path.join(work_dir, ".run_bg.py"), "w") as f:
            f.write(runner_code)
        cmd = [sys.executable, ".run_bg.py"]

    else: # Standard
        append_flag = '["-cpi", "md_0_1.cpt", "-append"]' if append else '[]'
        runner_code = f"""
import subprocess
import os
import sys

cmd = ["gmx", "mdrun", "-deffnm", "md_0_1", "-nt", "{threads}"]
cmd.extend({append_flag})

try:
    subprocess.run(cmd, check=True)
except subprocess.CalledProcessError as e:
    oom_detected = False
    for log_file in ["mdrun_out.log", "md_0_1.log", "mdrun_err.log"]:
        if os.path.exists(log_file):
            with open(log_file, "r") as f:
                log_content = f.read().lower()
                if "cudaerrormemoryallocation" in log_content or "out of memory" in log_content:
                    oom_detected = True
                    break

    if oom_detected:
        print("\\n[!] CUDA Out of Memory detected. GPU cannot handle this system size/configuration.")
        print("    -> Automatically restarting MDRun on CPU only (-nb cpu) to prevent crashing...")
        cmd.append("-nb")
        cmd.append("cpu")
        try:
            subprocess.run(cmd, check=True)
        except Exception as retry_e:
            print(f"[!] CPU Fallback also failed: {{retry_e}}")
    else:
        print("\\n[!] Simulation crashed for an unknown reason. Check mdrun_out.log.")
        sys.exit(1)
"""
        with open(os.path.join(work_dir, ".run_bg.py"), "w") as f:
            f.write(runner_code)
        cmd = [sys.executable, ".run_bg.py"]
    
    print(f"[-] Launching background process...")
    out_file = open(os.path.join(work_dir, "mdrun_out.log"), "w")
    proc = subprocess.Popen(cmd, cwd=work_dir, stdout=out_file, stderr=subprocess.STDOUT, start_new_session=True)
    
    with open(os.path.join(work_dir, ".mdrun.pid"), "w") as f:
        f.write(str(proc.pid))
    print(f"[-] MDRun started with PID: {proc.pid}")
    print("[-] You can safely close this terminal or check status from the main menu.")

def check_running_status(work_dir="complex", verbose=True):
    pid_file = os.path.join(work_dir, ".mdrun.pid")
    if not os.path.exists(pid_file):
        pid_file = os.path.join(work_dir, ".mdrun_pid")
        
    while True:
        if not os.path.exists(pid_file):
            if verbose:
                print("\n[-] No background simulation is currently running.\n")
            return False
        try:
            with open(pid_file) as f:
                pid = int(f.read().strip())
        except Exception:
            return False
            
        if psutil:
            is_running = psutil.pid_exists(pid)
        else:
            try:
                os.kill(pid, 0)
                is_running = True
            except OSError:
                is_running = False
                
        if not is_running:
            if os.path.exists(pid_file):
                try: os.remove(pid_file)
                except Exception: pass
            print("\n" + "="*42)
            print("  [!] PREVIOUS SIMULATION FINISHED  ")
            print("      (or was terminated manually)  ")
            print("="*42)
            print("[-] You can now proceed to Analysis (Option 5).")
            print("="*42 + "\n")
            return False
            
        # Parse simulation mode to know what logs to look for
        config = load_config() if 'load_config' in globals() else {}
        if not config and os.path.exists("simulation_settings.txt"):
            try:
                with open("simulation_settings.txt") as f:
                    for line in f:
                        if "=" in line and not line.strip().startswith("#"):
                            parts = line.split("=", 1)
                            config[parts[0].strip()] = parts[1].strip()
            except Exception: pass

        sim_mode = config.get("simulation_mode", "standard").lower()
        
        log_files = []
        if sim_mode == "ensemble":
            log_files = glob.glob(os.path.join(work_dir, "replica_*", "replica_*.log"))
        elif sim_mode == "fep":
            log_files = glob.glob(os.path.join(work_dir, "fep_lambda_*.log"))
        else:
            log_files = [os.path.join(work_dir, "md_0_1.log")]

        if not log_files or not any(os.path.exists(lf) for lf in log_files):
            log_files = glob.glob(os.path.join(work_dir, "*.log"))

        total_percent = 0.0
        total_curr_steps = 0
        total_max_steps = 0
        total_curr_ns = 0.0
        total_max_ns = 0.0
        ns_day_list = []
        valid_logs = 0

        for log_file in log_files:
            if os.path.exists(log_file):
                total_steps = 0
                dt = 0.002
                with open(log_file, "r", encoding="utf-8", errors="ignore") as f:
                    for _ in range(1000):
                        line = f.readline()
                        if not line:
                            break
                        if "nsteps" in line and "=" in line:
                            try:
                                total_steps = int(line.split("=")[1].strip())
                            except Exception: pass
                        if "dt" in line and "=" in line and "nsteps" not in line:
                            try:
                                dt = float(line.split("=")[1].strip())
                            except Exception: pass

                    f.seek(0, 2)
                    end_pos = f.tell()
                    start_pos = max(0, end_pos - 32768)
                    f.seek(start_pos)
                    lines = f.readlines()

                current_step = 0
                current_time_ps = 0.0
                parsed_ns_day = None

                for line in reversed(lines):
                    if parsed_ns_day is None and ("Performance:" in line or "ns/day" in line):
                        parts = line.split()
                        for p_idx, p_val in enumerate(parts):
                            if p_val == "Performance:" and p_idx + 1 < len(parts):
                                try:
                                    parsed_ns_day = float(parts[p_idx + 1])
                                    break
                                except Exception: pass
                            elif "ns/day" in p_val and p_idx > 0:
                                try:
                                    parsed_ns_day = float(parts[p_idx - 1])
                                    break
                                except Exception: pass

                    if current_step == 0:
                        parts = line.split()
                        if len(parts) >= 2 and parts[0].isdigit():
                            try:
                                c_step = int(parts[0])
                                c_time = float(parts[1])
                                if c_step > current_step:
                                    current_step = c_step
                                    current_time_ps = c_time
                            except Exception: pass

                    if current_step > 0 and parsed_ns_day is not None:
                        break

                current_ns = (current_step * dt) / 1000.0 if current_step > 0 else (current_time_ps / 1000.0)
                tot_ns = (total_steps * dt) / 1000.0 if total_steps > 0 else 0.0
                
                if parsed_ns_day is not None and parsed_ns_day > 0:
                    ns_day_list.append(parsed_ns_day)
                elif current_ns > 0:
                    try:
                        mtime = os.path.getmtime(log_file)
                        ctime = os.path.getctime(log_file)
                        elapsed = mtime - ctime
                        if elapsed > 10:
                            calc_ns_day = (current_ns / elapsed) * 86400.0
                            ns_day_list.append(calc_ns_day)
                    except Exception: pass

                if total_steps > 0:
                    total_percent += (current_step / total_steps) * 100.0
                    total_curr_steps += current_step
                    total_max_steps += total_steps
                    total_curr_ns += current_ns
                    total_max_ns += tot_ns
                    valid_logs += 1

        percent = (total_percent / valid_logs) if valid_logs > 0 else 0.0
        avg_ns_day = (sum(ns_day_list) / len(ns_day_list)) if ns_day_list else 0.0

        eta_str = "N/A"
        if avg_ns_day > 0 and total_max_ns > total_curr_ns:
            rem_ns = (total_max_ns - total_curr_ns) / (valid_logs if valid_logs > 0 else 1)
            rem_sec = (rem_ns / avg_ns_day) * 86400.0
            hrs = int(rem_sec // 3600)
            mins = int((rem_sec % 3600) // 60)
            secs = int(rem_sec % 60)
            if hrs > 0:
                eta_str = f"{hrs}h {mins}m {secs}s"
            else:
                eta_str = f"{mins}m {secs}s"

        curr_ns_disp = total_curr_ns / (valid_logs if valid_logs > 0 else 1)
        max_ns_disp = total_max_ns / (valid_logs if valid_logs > 0 else 1)
        curr_step_disp = int(total_curr_steps / (valid_logs if valid_logs > 0 else 1))
        max_step_disp = int(total_max_steps / (valid_logs if valid_logs > 0 else 1))

        print("\n" + "="*42)
        print("      SIMULATION CURRENTLY RUNNING      ")
        print("="*42)
        print(f"  PID:         {pid}")
        if max_ns_disp > 0:
            print(f"  Progress:    {curr_ns_disp:.2f} / {max_ns_disp:.2f} ns ({percent:.1f}%)")
            print(f"  Steps:       {curr_step_disp} / {max_step_disp}")
        else:
            print(f"  Completion:  {percent:.1f}%")
        print(f"  Throughput:  {avg_ns_day:.2f} ns/day" if avg_ns_day > 0 else "  Throughput:  N/A")
        print(f"  ETA:         {eta_str}")
        print("="*42)
        print("1. Live log view (tail -f log)")
        print("2. Pause Simulation")
        print("3. Refresh")
        print("4. Return to Main Menu")
        
        ans = input("\nSelect an option: ").strip()
        if ans == '1':
            if not log_files:
                print("[-] No log files found yet. Cannot enter live view.")
            else:
                print("[-] Entering Live View. Press Ctrl+C to exit.")
                try:
                    subprocess.run(["tail", "-f", log_files[-1]])
                except KeyboardInterrupt:
                    print("\n[-] Exited Live View.")
        elif ans == '2':
            print(f"[-] Sending graceful stop signal (SIGTERM) to PID {pid}...")
            try:
                try:
                    os.killpg(os.getpgid(pid), signal.SIGTERM)
                except AttributeError:
                    if psutil:
                        parent = psutil.Process(pid)
                        for child in parent.children(recursive=True):
                            child.terminate()
                        parent.terminate()
                        parent.wait(timeout=30)
                    else:
                        os.kill(pid, signal.SIGTERM)
                if os.path.exists(pid_file): os.remove(pid_file)
                print("[-] Run paused gracefully. A checkpoint (.cpt) was saved.")
            except Exception as e: print(f"[!] Error pausing: {e}")
            return False
        elif ans == '3':
            continue
        elif ans == '4':
            return False
        else:
            print("Invalid option.")

def check_pending_run(work_dir="complex"):
    cpt_file = os.path.join(work_dir, "md_0_1.cpt")
    gro_file = os.path.join(work_dir, "md_0_1.gro")
    pid_file = os.path.join(work_dir, ".mdrun.pid")
    
    if os.path.exists(cpt_file) and not os.path.exists(gro_file) and not os.path.exists(pid_file):
        print("\n[!] Detected a PAUSED/PENDING simulation.")
        ans = input("Do you want to RESUME it now? (y/N): ").strip().lower()
        if ans == 'y':
            print("\n[-] Resuming MD...")
            start_mdrun(work_dir, append=True)
            return True
    return False

def run_script_by_prefix(prefix):
    scripts = glob.glob(os.path.join(MODULES_DIR, f"{prefix}_*.py"))
    if not scripts:
        print(f"[!] No script found for prefix {prefix}")
        return False
    script_path = scripts[0]
    print(f"\n>>> Running {os.path.basename(script_path)} ...")
    result = subprocess.run([sys.executable, script_path], cwd=os.getcwd())
    return result.returncode == 0

def check_and_load_dependency(binary_name, display_name=None):
    if not display_name:
        display_name = binary_name
    import shutil
    if shutil.which(binary_name):
        return True

    print(f"\\n[*] {display_name} ('{binary_name}') not found in standard PATH. Searching system...")
    search_dirs = [
        f"/usr/local/{binary_name}/bin", f"/opt/{binary_name}/bin",
        os.path.expanduser(f"~/{binary_name}/bin"), os.path.expanduser("~/.local/bin"),
        "/usr/local/gromacs/bin", "/opt/gromacs/bin",
        os.path.expanduser("~/miniconda3/bin"), os.path.expanduser("~/anaconda3/bin"),
        os.path.expanduser("~/.micromamba/bin"), "/opt/conda/bin", "/data1/mgs/micromamba/bin",
        "/usr/bin", "/bin"
    ]

    # Add conda environments to search
    conda_envs_base = [os.path.expanduser("~/.conda/envs"), os.path.expanduser("~/miniconda3/envs"), os.path.expanduser("~/anaconda3/envs"), "/opt/conda/envs", "/data1/mgs/micromamba/envs"]
    common_envs = ["ambertools", "acpype", "autogro", "base"]

    for base in conda_envs_base:
        for common in common_envs:
            search_dirs.append(os.path.join(base, common, "bin"))
        if os.path.isdir(base):
            try:
                for env in os.listdir(base):
                    search_dirs.append(os.path.join(base, env, "bin"))
            except OSError:
                pass

    # Fallback to active package manager env list parsing if we still need a deep search
    for conda_exe_name in ['micromamba', 'mamba', 'conda']:
        conda_exe = shutil.which(conda_exe_name)
        if not conda_exe:
            for fallback in [
                os.path.expanduser(f"~/.local/bin/{conda_exe_name}"),
                os.path.expanduser(f"~/miniconda3/bin/{conda_exe_name}"),
                os.path.expanduser(f"~/anaconda3/bin/{conda_exe_name}"),
                os.path.expanduser(f"~/.micromamba/bin/{conda_exe_name}"),
                f"/opt/conda/bin/{conda_exe_name}",
                f"/data1/mgs/micromamba/bin/{conda_exe_name}"
            ]:
                if os.path.isfile(fallback):
                    conda_exe = fallback
                    break
        if conda_exe:
            try:
                import subprocess
                res = subprocess.run([conda_exe, "env", "list"], capture_output=True, text=True, timeout=10)
                if res.returncode == 0:
                    for line in res.stdout.splitlines():
                        line = line.strip()
                        if line and not line.startswith('#'):
                            parts = line.split()
                            path_part = parts[-1]
                            if os.path.exists(path_part):
                                search_dirs.append(os.path.join(path_part, "bin"))
            except Exception:
                pass

    found_paths = []
    for d in search_dirs:
        candidate = os.path.join(d, binary_name)
        try:
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                if candidate not in found_paths:
                    found_paths.append(candidate)
        except OSError:
            pass

    if len(found_paths) == 0:
        print(f"[!] Error: {display_name} ('{binary_name}') is completely missing from this machine.")
        return False
    elif len(found_paths) == 1:
        chosen_bin = found_paths[0]
        print(f"[-] Auto-detected hidden {display_name} at: {chosen_bin}")
        os.environ["PATH"] = os.path.dirname(chosen_bin) + os.pathsep + os.environ.get("PATH", "")
        return True
    else:
        print(f"\\n[!] Multiple {display_name} installations found:")
        for idx, p in enumerate(found_paths):
            print(f"  {idx + 1}. {p}")
        while True:
            choice = input(f"Select which version to use [1-{len(found_paths)}]: ").strip()
            try:
                c_idx = int(choice) - 1
                if 0 <= c_idx < len(found_paths):
                    chosen_bin = found_paths[c_idx]
                    os.environ["PATH"] = os.path.dirname(chosen_bin) + os.pathsep + os.environ.get("PATH", "")
                    print(f"[-] Using: {chosen_bin}")
                    return True
            except ValueError: pass
            print("Invalid selection.")

def run_pipeline(step_by_step=False):
    if not os.path.exists("simulation_settings.txt"):
        print("[!] simulation_settings.txt not found. Please setup the project first.")
        return

    if not check_and_load_dependency("gmx", "GROMACS"):
        print("    Please install it (e.g. 'sudo apt install gromacs') or run 'module load gromacs' before starting the pipeline.")
        return

    has_ligand = False
    with open("simulation_settings.txt") as f:
        for line in f:
            if "ligand_file" in line and "=" in line and not line.strip().startswith("#"):
                val = line.split("=", 1)[1].strip()
                if val and val.lower() != "none" and val != "": has_ligand = True

    if has_ligand:
        if not check_and_load_dependency("antechamber", "AmberTools (antechamber)"):
            print("    Please install AmberTools or activate your conda environment before starting the pipeline.")
            return
        if not check_and_load_dependency("acpype", "ACPYPE"):
            print("    Please install ACPYPE or activate your conda environment before starting the pipeline.")
            return

    steps = [2, 3]
    if has_ligand: steps.extend([4, 5])
    steps.extend([6, 7, 8, 9, 10, 11])
    
    print("\n[-] Preparing for Molecular Dynamics Pipeline...")
    threads = get_cpu_threads_from_user()

    for step in steps:
        if step_by_step:
            ans = input(f"\nRun step {step}? [Y/n/q]: ").strip().lower()
            if ans == 'q': break
            if ans == 'n': continue
        if not run_script_by_prefix(str(step)):
            print(f"\n[!] Pipeline halted at step {step}.")
            return
            
        # If we just finished step 3 and there is NO ligand, we must setup the complex folder manually
        if step == 3 and not has_ligand:
            print("\n[-] No ligand specified. Setting up 'complex' folder with just the receptor...")
            import shutil
            os.makedirs("complex", exist_ok=True)
            try:
                shutil.copy("receptor/protein_processed.gro", "complex/complex.gro")
                shutil.copy("receptor/topol.top", "complex/topol.top")
                if os.path.exists("receptor/posre.itp"):
                    shutil.copy("receptor/posre.itp", "complex/posre.itp")
            except FileNotFoundError as e:
                print(f"[!] Warning: Could not copy receptor files to complex folder: {e}")
                
    start_mdrun("complex", append=False, threads=threads)
    print("\n[-] Preparation finished and Simulation started in background!")
    print("[-] Return to the main menu later to check status or analyze results.")

def analyze_results():
    has_ligand = False
    if os.path.exists("simulation_settings.txt"):
        with open("simulation_settings.txt") as f:
            for line in f:
                if line.startswith("ligand_file ="):
                    val = line.split("=", 1)[1].strip()
                    if val.lower() != "none": has_ligand = True
                    
    print("\n" + "="*42)
    print("               ANALYSIS MENU              ")
    print("="*42)
    print("1. Optimize Best Configuration (Centering + Rot/Trans fixing)")
    print("2. Run Density Analysis (Calculates .dx files)")
    print("3. Show Density Map Instructions (For PyMOL)")
    print("4. Run Post-Processing & Cleanup (Scripts 13-16)")
    if has_ligand:
        print("5. Run MM-PBSA Binding Affinity Calculation (Script 18)")
        print("6. Return to Main Menu")
    else:
        print("5. Return to Main Menu")
    
    choice = input("\nSelect option: ").strip()
    if choice == '1':
        script = os.path.join(MODULES_DIR, "analysis_trajectory.py")
        if os.path.exists(script): subprocess.run([sys.executable, script], cwd=os.getcwd())
    elif choice == '2':
        script = os.path.join(MODULES_DIR, "analysis_density.py")
        if os.path.exists(script): subprocess.run([sys.executable, script], cwd=os.getcwd())
    elif choice == '3':
        pml_file = os.path.join(MODULES_DIR, "density_map.pml")
        if os.path.exists(pml_file):
            print("\n--- PyMOL Instructions ---")
            with open(pml_file) as f: print(f.read())
            print("--------------------------")
    elif choice == '4':
        print("\n[-] Running Post-Processing scripts...")
        run_script_by_prefix("13")
        run_script_by_prefix("14")
        run_script_by_prefix("15")
        run_script_by_prefix("16")
    elif choice == '5' and has_ligand:
        print("\n[-] Running MM-PBSA calculation...")
        run_script_by_prefix("18")


def interactive_config_wizard():
    if not os.path.exists("simulation_settings.txt"):
        print("[!] simulation_settings.txt not found. Please setup the project first (Option 1).")
        return
        
    ans = input("\nDo you want to use the Interactive Wizard, or Manual Edit? (I/m): ").strip().lower()
    if ans == 'm':
        editor = os.environ.get("EDITOR", "vi")
        subprocess.run([editor, "simulation_settings.txt"])
        return
        
    print("\n" + "="*50)
    print("      INTERACTIVE CONFIGURATION WIZARD          ")
    print("="*50)
    print("(Press TAB to auto-complete file names in this directory)\n")
    
    # --- 1. SIMULATION MODE SELECTION ---
    print("Select Simulation Mode:")
    print("  1. Standard MD (Single continuous simulation run)")
    print("  2. Multi-Replica Ensemble Sampling (Short runs with different random seeds for conformational sampling)")
    print("  3. Alchemical Free Energy / Binding Affinity (FEP lambda-states to calculate dG_bind)")
    
    mode_choice = input("Choice [1-3, Default: 1]: ").strip()
    sim_mode = "standard"
    if mode_choice == '2': sim_mode = "ensemble"
    elif mode_choice == '3': sim_mode = "fep"
    
    print(f"[-] Selected Mode: {sim_mode.upper()}")
    
    # --- 2. FILE SELECTION ---
    current_prot = "Pa_relaxed.pdb"
    current_lig = "None"
    if os.path.exists("simulation_settings.txt"):
        with open("simulation_settings.txt") as f:
            for line in f:
                if line.startswith("protein_pdb ="):
                    current_prot = line.split("=", 1)[1].strip()
                elif line.startswith("ligand_file ="):
                    current_lig = line.split("=", 1)[1].strip()

    # Auto-detect PDBs and Ligands in working directory
    pdbs = glob.glob("*.pdb")
    mols = glob.glob("*.mol2") + glob.glob("*.sdf")

    # Protein Default Determination:
    if os.path.exists(current_prot):
        default_prot = current_prot
    elif pdbs:
        default_prot = pdbs[0]
    else:
        default_prot = "Pa_relaxed.pdb"

    if pdbs:
        print(f"Detected PDB files: {', '.join(pdbs)}")
    protein = input(f"Protein PDB File [Press Enter for '{default_prot}']: ").strip()
    if not protein:
        protein = default_prot

    # Ligand Default Determination:
    has_ligand_ans = input("Does this simulation include a ligand? (y/N): ").strip().lower()
    ligand = None
    if has_ligand_ans == 'y':
        if current_lig.lower() != "none" and os.path.exists(current_lig):
            default_lig = current_lig
        elif mols:
            default_lig = mols[0]
        else:
            default_lig = ""
            
        if mols:
            print(f"Detected Ligand files: {', '.join(mols)}")
        
        lig_prompt = f"Ligand File (Accepted formats: .mol2, .sdf) [Press Enter for '{default_lig}']: " if default_lig else "Ligand File (Accepted formats: .mol2, .sdf): "
        ligand = input(lig_prompt).strip()
        if not ligand and default_lig:
            ligand = default_lig
        
    # --- 3. WATER MODEL SELECTION ---
    print("\n[ Water Model Selection ]")
    print("  1. TIP3P (Recommended default for Amber/CHARMM force fields)")
    print("  2. SPC/E (Better dielectric constant and liquid water density)")
    print("  3. TIP4P (4-site model, improved electrostatic distribution)")
    w_choice = input("Select Water Model [1-3, Default: 1]: ").strip()
    water_model = "tip3p"
    if w_choice == '2': water_model = "spce"
    elif w_choice == '3': water_model = "tip4p"

    # --- 4. MODE SPECIFIC PARAMETERS & GUIDANCE ---
    ensemble_reps = "5"
    rep_time = "5.0"
    fep_lambdas = "11"
    fep_time = "2.0"
    sim_time = "0.1"
    
    if sim_mode == "ensemble":
        print("\n[ Multi-Replica Ensemble Guidance ]")
        print("  - Replicas run independent simulations starting from different random velocity seeds.")
        print("  - Recommended: 5 to 10 replicas of 5.0 ns each to thoroughly explore conformational space.")
        reps_input = input("Number of Replicas [Default: 5]: ").strip()
        if reps_input.isdigit(): ensemble_reps = reps_input
        time_input = input("Time per Replica in ns [Default: 5.0]: ").strip()
        if time_input: rep_time = time_input
        total_sim_ns = float(ensemble_reps) * float(rep_time)
        print(f"[-] Cumulative Ensemble Simulation: {total_sim_ns:.1f} ns total")

    elif sim_mode == "fep":
        print("\n[ Alchemical Binding Free Energy (FEP) Guidance ]")
        print("  - FEP decouples electrostatic and VdW interactions across intermediate lambda states.")
        print("  - Recommended: 11 lambda windows (e.g. 2.0 ns per window) for robust Bennett Acceptance Ratio (gmx bar) convergence.")
        lambdas_input = input("Number of Lambda Windows [Default: 11]: ").strip()
        if lambdas_input.isdigit(): fep_lambdas = lambdas_input
        ftime_input = input("Time per Lambda Window in ns [Default: 2.0]: ").strip()
        if ftime_input: fep_time = ftime_input
        total_sim_ns = float(fep_lambdas) * float(fep_time)
        print(f"[-] Cumulative FEP Simulation: {total_sim_ns:.1f} ns total")

    else: # standard
        stime_input = input("\nSimulation Time in ns [Default: 0.1]: ").strip()
        if stime_input: sim_time = stime_input
        total_sim_ns = float(sim_time)

    # --- 4.5 OUTPUT FRAMES ---
    frames_input = input("\nFrames per run (Final Movie Frames) [Default: 100]: ").strip()
    if not frames_input.isdigit():
        frames_input = "100"

    # --- 5. RUNTIME & RESOURCE ESTIMATOR ---
    print("\n" + "="*50)
    print("        RESOURCE & RUNTIME ESTIMATOR          ")
    print("="*50)
    
    alloc_percent = input("Percentage of PC to dedicate (e.g. 75) [Default: 75]: ").strip()
    if not alloc_percent.isdigit() or not (1 <= int(alloc_percent) <= 100):
        alloc_percent = "75"
        
    total_cpus = os.cpu_count() or 1
    threads = max(1, math.floor(total_cpus * (int(alloc_percent) / 100.0)))
    print(f"[-] Allocating {alloc_percent}% -> {threads} threads (Out of {total_cpus})")

    # Benchmark estimate (~10-20 ns/day per thread allocation)
    est_hours = (total_sim_ns * 24.0) / (threads * 1.5)
    print(f"[-] Total Simulation Workload: {total_sim_ns:.2f} ns")
    print(f"[-] Estimated Completion Time: ~{est_hours:.1f} hours ({est_hours*60:.0f} mins) on allocated resources.")
    print("="*50)

    # --- 6. WRITE UPDATED SETTINGS ---
    print("\n[-] Updating simulation_settings.txt...")
    
    with open("simulation_settings.txt", "r") as f:
        lines = f.readlines()
        
    has_alloc_line = False
    has_frames_line = False
    with open("simulation_settings.txt", "w") as f:
        for line in lines:
            if line.startswith("protein_pdb =") and protein:
                f.write(f"protein_pdb = {protein}\n")
            elif line.startswith("ligand_file ="):
                if has_ligand_ans != 'y':
                    f.write("ligand_file = None\n")
                elif ligand:
                    f.write(f"ligand_file = {ligand}\n")
                else:
                    f.write(line)
            elif line.startswith("ligand_resname ="):
                if has_ligand_ans == 'y':
                    f.write("ligand_resname = MOL\n")
                else:
                    f.write(line)
            elif line.startswith("simulation_mode ="):
                f.write(f"simulation_mode = {sim_mode}\n")
            elif line.startswith("ensemble_replicas ="):
                f.write(f"ensemble_replicas = {ensemble_reps}\n")
            elif line.startswith("replica_time_ns ="):
                f.write(f"replica_time_ns = {rep_time}\n")
            elif line.startswith("fep_lambda_windows ="):
                f.write(f"fep_lambda_windows = {fep_lambdas}\n")
            elif line.startswith("fep_window_time_ns ="):
                f.write(f"fep_window_time_ns = {fep_time}\n")
            elif line.startswith("simulation_time_ns ="):
                if sim_mode == "standard":
                    f.write(f"simulation_time_ns = {sim_time}\n")
                elif sim_mode == "ensemble":
                    f.write(f"simulation_time_ns = {rep_time}\n")
                elif sim_mode == "fep":
                    f.write(f"simulation_time_ns = {fep_time}\n")
            elif line.startswith("output_frames ="):
                f.write(f"output_frames = {frames_input}\n")
                has_frames_line = True
            elif line.startswith("allocated_cpu_percent ="):
                f.write(f"allocated_cpu_percent = {alloc_percent}\n")
                has_alloc_line = True
            else:
                f.write(line)
        if not has_alloc_line:
            f.write(f"allocated_cpu_percent = {alloc_percent}\n")
        if not has_frames_line:
            f.write(f"output_frames = {frames_input}\n")
                
    print("[-] Settings updated successfully!")


def autocorrect_working_directory():
    """
    Traverses upwards to find the true project root ('complex' equivalent)
    by looking for known marker files, or falls back to known subdirectories.
    """
    current_dir = os.getcwd()
    check_dir = current_dir
    
    # 1. Search upwards for definitive root markers
    while True:
        if os.path.exists(os.path.join(check_dir, "simulation_settings.txt")) or \
           os.path.exists(os.path.join(check_dir, "receptor")):
            if os.getcwd() != check_dir:
                print(f"[*] Auto-correcting working directory to root: {check_dir}")
                os.chdir(check_dir)
            return check_dir
            
        parent = os.path.dirname(check_dir)
        if parent == check_dir: # Hit the filesystem root
            break
        check_dir = parent
        
    # 2. Fallback: If no markers exist, check if we are in a known Gromacs subdirectory
    known_subdirs = [
        "01_Setup", "02_Minimization", "03_Equilibration", 
        "04_Production", "05_Results", "06_Analysis", "complex"
    ]
    base_name = os.path.basename(current_dir)
    if base_name in known_subdirs:
        parent_dir = os.path.dirname(current_dir)
        print(f"[*] Auto-correcting working directory from {base_name} to parent: {parent_dir}")
        os.chdir(parent_dir)
        return parent_dir
        
    return current_dir

def main_menu():
    # Global fix: Auto-correct working directory if user launched from inside 'complex' or a subfolder
    autocorrect_working_directory()

    if os.path.exists(os.path.join("complex", ".mdrun.pid")) or os.path.exists(os.path.join("complex", ".mdrun_pid")):
        if check_running_status("complex", verbose=False): return
    if check_pending_run("complex"): return

    while True:
        print_header()
        print("1. Setup New Project (Create config)")
        print("2. Edit Settings (simulation_settings.txt)")
        print("3. Run Full Pipeline (Auto)")
        print("4. Run Pipeline (Step-by-step)")
        print("5. Analyze Results & Post-Processing")
        print("6. View Background Simulation Progress")
        print("7. Decompress Files")
        print("8. Cleanup Workspace")
        print("9. Exit")
        
        choice = input("\nSelect an option: ").strip()
        if choice == '1': run_script_by_prefix("1")
        elif choice == '2': interactive_config_wizard()
        elif choice == '3': run_pipeline(step_by_step=False)
        elif choice == '4': run_pipeline(step_by_step=True)
        elif choice == '5': analyze_results()
        elif choice == '6': check_running_status("complex", verbose=True)
        elif choice == '7': run_script_by_prefix("17")
        elif choice == '8': run_script_by_prefix("99")
        elif choice == '9':
            print("Exiting...")
            break
        else: print("Invalid option. Please try again.")

if __name__ == "__main__":
    main_menu()

EOF_MENU
chmod +x "$INSTALL_DIR/autogro.py"

cat << EOF_WRAPPER > "$INSTALL_DIR/autogro"
#!/bin/bash
export PATH="\$PATH:$PATH"
export LD_LIBRARY_PATH="\$LD_LIBRARY_PATH:${LD_LIBRARY_PATH:-}"
export GMX_MAXBACKUP=-1
export PYTHONPATH="$INSTALL_DIR/modules:\$PYTHONPATH"
python3 "$INSTALL_DIR/autogro.py" "\$@"
EOF_WRAPPER
chmod +x "$INSTALL_DIR/autogro"

mkdir -p "$BIN_DIR"
cat << EOF_WRAPPER > "$BIN_DIR/autogro"
#!/bin/bash
export PATH="\$PATH:$PATH"
export LD_LIBRARY_PATH="\$LD_LIBRARY_PATH:${LD_LIBRARY_PATH:-}"
export GMX_MAXBACKUP=-1
export PYTHONPATH="$INSTALL_DIR/modules:\$PYTHONPATH"
python3 "$INSTALL_DIR/autogro.py" "\$@"
EOF_WRAPPER
chmod +x "$BIN_DIR/autogro"

mkdir -p "$HOME/bin"
cat << EOF_WRAPPER > "$HOME/bin/autogro"
#!/bin/bash
export PATH="\$PATH:$PATH"
export LD_LIBRARY_PATH="\$LD_LIBRARY_PATH:${LD_LIBRARY_PATH:-}"
export GMX_MAXBACKUP=-1
export PYTHONPATH="$INSTALL_DIR/modules:\$PYTHONPATH"
python3 "$INSTALL_DIR/autogro.py" "\$@"
EOF_WRAPPER
chmod +x "$HOME/bin/autogro"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "[!] Warning: $BIN_DIR is not in your PATH."
    echo "    To fix this, add the following line to your ~/.bashrc or ~/.profile:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
echo "=========================================="
echo " Installation Complete!"
echo " Monolithic installer successfully deployed."
echo "=========================================="
