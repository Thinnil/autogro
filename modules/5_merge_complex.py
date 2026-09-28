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
