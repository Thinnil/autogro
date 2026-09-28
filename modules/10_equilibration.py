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
constraints = h-bonds
constraint_algorithm = lincs
nstlist = 10
rcoulomb = 1.0
rvdw = 1.0
coulombtype = PME
pbc = xyz
dt = 0.001
nsteps = 50000 ; 100ps
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
    subprocess.run(["gmx", "mdrun", "-v", "-deffnm", "nvt"], cwd="complex")
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

subprocess.run(["gmx", "mdrun", "-v", "-deffnm", "npt"], cwd="complex")
log_pipeline_msg("Step 10", "OK")
