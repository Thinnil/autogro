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
os.environ["GMX_MAXBACKUP"] = "-1"

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
subprocess.run(cmd_mdrun, cwd="complex")

print("[-] Minimization complete. Output: complex/em.gro")
log_pipeline_msg("Step 9", "OK")
