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
    sys_prep_text += "Ligand parameters were generated using ACPYPE (AnteChamber PYthon Parser interfacE), implementing the General Amber Force Field (GAFF) with AM1-BCC partial charges. The complex was solvated "
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
Long-range electrostatic interactions were calculated using the Particle Mesh Ewald (PME) method with a real-space cutoff of 1.2 nm. Van der Waals interactions were treated with a cutoff of 1.2 nm. Bond lengths involving hydrogen atoms were constrained using the LINCS algorithm, allowing for an integration time step of 2 fs. Periodic boundary conditions (PBC) were applied in all three dimensions.{mmpbsa_text}
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
