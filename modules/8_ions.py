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
