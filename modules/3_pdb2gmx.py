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
