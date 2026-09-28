import subprocess
_orig_run = subprocess.run
def _safe_run(*args, **kwargs):
    kwargs.setdefault("check", True)
    return _orig_run(*args, **kwargs)
subprocess.run = _safe_run

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
