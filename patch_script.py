import os
import re

def main():
    text = open("install.sh").read()

    # 1. Version Bump
    text = text.replace("v2.4", "v2.9")

    # 2. Add MAMBA_ROOT_PREFIX fix
    mamba_replacement = r'''        if [ "$pkg_mgr" == "micromamba" ]; then
            export MAMBA_ROOT_PREFIX=${MAMBA_ROOT_PREFIX:-"$HOME/micromamba"}
        fi
        "$pkg_mgr" create'''
    text = text.replace('        "$pkg_mgr" create', mamba_replacement)

    # 3. GMX_MAXBACKUP
    text = re.sub(
        r'#!/bin/bash\nexport PATH="\$PATH:\$PATH"\nexport LD_LIBRARY_PATH="\$LD_LIBRARY_PATH:\$\{LD_LIBRARY_PATH:-\}"',
        r'#!/bin/bash\nexport PATH="\\$PATH"\nexport LD_LIBRARY_PATH="\\$LD_LIBRARY_PATH"\nexport GMX_MAXBACKUP=-1',
        text
    )

    text = text.replace('import os\nimport subprocess\n\n', 'import os\nimport subprocess\nos.environ["GMX_MAXBACKUP"] = "-1"\n\n')

    # 4. SDF support in ligand param
    sdf_replace = r'''    ligand_ext = ligand_file.split(".")[-1].lower()
    in_format = "mol2"
    if ligand_ext in ["sdf", "mdl"]:
        in_format = "sdf"

    print(f"[-] Processing ligand {ligand_file} with format {in_format}...")

    # Define standard commands
    acpype_cmd = [
        "acpype",
        "-i", ligand_file,
        "-b", "ligand",
        "-c", "bcc",   # AM1-BCC charge method (standard)
        "-n", str(ligand_charge),
        "-m", str(ligand_multiplicity),
        "-a", "amber", # Atom type (amber/gaff2 is standard)
        "-f", "-y"     # Force overwrite, ignore errors
    ]

    # Run ACPYPE
    result = subprocess.run(acpype_cmd)

    # 1) Fallback if AM1-BCC fails due to complex/strained ligand topologies
    if result.returncode != 0:
        print("\n[!] ACPYPE AM1-BCC charge calculation failed! The ligand geometry might be strained.")
        print("[-] FALLBACK: Attempting to calculate empirical Gasteiger charges instead...")
        fallback_cmd = acpype_cmd.copy()
        fallback_cmd[fallback_cmd.index("bcc")] = "gas"  # Switch charge method to Gasteiger
        result = subprocess.run(fallback_cmd)'''

    text = re.sub(r'    # Define standard commands.*?result = subprocess\.run\(acpype_cmd\)', sdf_replace, text, flags=re.DOTALL)

    # 5. dt and constraints
    text = text.replace('dt = 0.002', 'dt = 0.001')
    text = text.replace('constraints             = h-bonds', 'constraints             = all-bonds')
    text = text.replace('save_interval < 500', 'save_interval < 1000')
    text = text.replace('save_interval = 500', 'save_interval = 1000')
    text = text.replace('expected_frames = int(total_steps / 500)', 'expected_frames = int(total_steps / 1000)')

    text = text.replace('cutoff-scheme           = Verlet\nns_type                 = grid\nnstlist                 = 10', 'cutoff-scheme           = Verlet\nverlet-buffer-tolerance = 0.005\nns_type                 = grid\nnstlist                 = 20')

    # 6. interactive wizard sync
    wiz_replace = r'''    ans = input(f"Simulation Time ({config.get('simulation_time_ns', '10.0')} ns): ").strip()
    if ans:
        try: sim_time = str(float(ans))
        except: pass

    sim_frames = config.get('output_frames', '100')
    ans = input(f"Output Movie Frames ({config.get('output_frames', '100')} frames): ").strip()
    if ans:
        try:
            int(ans)
            sim_frames = ans
        except: pass
'''
    text = re.sub(r"    ans = input\(f\"Simulation Time \(\{config.get\('simulation_time_ns', '10\.0'\)\}\ ns\): \"\)\.strip\(\)\n    if ans:\n        try: sim_time = str\(float\(ans\)\)\n        except: pass\n", wiz_replace, text)

    # 7. Write settings correctly
    settings_write_replace = r'''
    with open("simulation_settings.txt", "w") as f:
        f.write("# ==========================================\n")
        f.write("# AutoGRO Configuration File\n")
        f.write("# ==========================================\n\n")

        f.write("# ------------------------------------------------------------------------------\n")
        f.write("# 1. SYSTEM DEFINITION\n")
        f.write("# ------------------------------------------------------------------------------\n")
        f.write(f"receptor_file = {rec_file}\n")
        f.write(f"ligand_file = {lig_file}\n\n")

        f.write("# ------------------------------------------------------------------------------\n")
        f.write("# 2. SIMULATION CONTROLS\n")
        f.write("# ------------------------------------------------------------------------------\n")
        f.write(f"simulation_mode = {sim_mode}\n")
        if sim_mode == "ensemble":
            f.write(f"ensemble_replicas = {ens_reps}\n")
            f.write(f"replica_time_ns = {ens_time}\n")
        f.write(f"simulation_time_ns = {sim_time}\n")
        f.write(f"output_frames = {sim_frames}\n")
        f.write(f"temperature = {temp}\n\n")
'''
    text = re.sub(r'    with open\("simulation_settings\.txt", "w"\) as f:.*?        f\.write\(f"temperature = \{temp\}\\n\\n"\)', settings_write_replace, text, flags=re.DOTALL)

    # 8. Background runner fix
    bg_runner_replace = r'''
    prep_code = ""
    if not append:
        root_dir = os.getcwd()
        modules_dir = MODULES_DIR
        prep_code = f"""
import subprocess
import os
import sys

def run_step(step_script):
    print(f"[-] Running Step {{step_script}}...")
    root_dir = {repr(root_dir)}
    modules_dir = {repr(modules_dir)}
    script_path = os.path.join(modules_dir, step_script)
    if subprocess.run([sys.executable, script_path], cwd=root_dir).returncode != 0:
        with open("ERROR_PREP.txt", "w") as f: f.write(f"Error in {{step_script}}")
        sys.exit(1)

run_step("9_minimization.py")
run_step("10_equilibration.py")
run_step("11_production_run.py")
"""

    if sim_mode == "ensemble":
        print("\n[-] Launching Multi-Replica Ensemble MDRun in background...")
        runner_code = f"""
import subprocess
import glob
import os
import sys
from concurrent.futures import ThreadPoolExecutor
{prep_code}
'''
    text = re.sub(r'    if sim_mode == "ensemble":\n        print\("\\n\[-\] Launching Multi-Replica Ensemble MDRun in background\.\.\."\)\n        runner_code = f"""\nimport subprocess\nimport glob\nimport os\nimport sys\nfrom concurrent\.futures import ThreadPoolExecutor', bg_runner_replace, text)
    text = text.replace('from concurrent.futures import ThreadPoolExecutor\n\nlambdas', 'from concurrent.futures import ThreadPoolExecutor\n{prep_code}\n\nlambdas')
    text = text.replace('import sys\n\ncmd = ["gmx", "mdrun"', 'import sys\n{prep_code}\n\ncmd = ["gmx", "mdrun"')

    # 9. modify run steps
    text = text.replace('steps.extend([6, 7, 8, 9, 10, 11])', 'steps.extend([6, 7, 8])')

    # 10. Debug messages
    debug_replace = r'''            with open("ERROR_PREP.txt", "w") as f:
                f.write(f"Error in {step_script}: The system may have exploded due to steric clashes. Check the log files.")'''
    text = text.replace('with open("ERROR_PREP.txt", "w") as f: f.write(f"Error in {step_script}")', debug_replace)

    # 11. Error prep checking in main menu
    main_menu_replace = r'''
    while True:
        print_header()

        # Check for prep errors
        if os.path.exists(os.path.join("complex", "ERROR_PREP.txt")):
            print("\n[!] WARNING: A background preparation step (Minimization/Equilibration) failed!")
            print("    Check complex/ERROR_PREP.txt or the respective logs for details.")
            with open(os.path.join("complex", "ERROR_PREP.txt"), "r") as f:
                print("    Error Message: " + f.read().strip())
            print("    Please resolve the issue before starting a new run.\n")

        print("1. Setup New Project (Create config)")'''
    text = text.replace('    while True:\n        print_header()\n        print("1. Setup New Project (Create config)")', main_menu_replace)

    # 12. Fix the missing modules bug where they were using dt=0.002
    text = text.replace('An integration time step of 1 fs was used for initial NVT equilibration, and 2 fs for production.', 'An integration time step of 1 fs was used for both equilibration and production phases to enhance the stability of the complexes.')

    # Write back
    open("install.sh", "w").write(text)

if __name__ == "__main__":
    main()
