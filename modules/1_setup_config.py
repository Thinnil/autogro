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
