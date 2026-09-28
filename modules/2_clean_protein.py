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
