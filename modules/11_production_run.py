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
dt = 0.001
total_steps = int((time_ns * 1000) / dt)

# Calculate Saving Frequency (nstxout-compressed) to hit the target frame count
# Logic: Total Steps / Desired Frames = Interval
save_interval = int(total_steps / frames)

# Safety: Don't save every step (files become gigabytes in seconds)
if save_interval < 1000:
    print(f"[!] Warning: Requested frames require saving every {save_interval} steps.")
    print("    -> Clamping to minimum safe interval (500 steps) to prevent disk fill.")
    save_interval = 1000
    expected_frames = int(total_steps / 1000)
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
constraints             = all-bonds
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
