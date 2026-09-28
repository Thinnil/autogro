#!/usr/bin/env python3
import os, sys, subprocess, glob, math, signal
try: import psutil
except ImportError: psutil = None
try:
    import readline
    def path_completer(text, state):
        return (glob.glob(text+'*')+[None])[state]
    readline.set_completer_delims(' \t\n;')
    readline.parse_and_bind("tab: complete")
    readline.set_completer(path_completer)
except ImportError: pass

MODULES_DIR = os.path.join(os.path.dirname(__file__), 'modules')

def load_config(filepath="simulation_settings.txt"):
    config = {}
    if os.path.exists(filepath):
        try:
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    if "=" in line and not line.strip().startswith("#"):
                        parts = line.split("=", 1)
                        config[parts[0].strip()] = parts[1].strip()
        except Exception:
            pass
    return config

def print_header():
    print("\n" + "="*42)
    print("           A U T O G R O  v2.9            ")
    print("="*42)

def get_cpu_threads_from_user():
    config_percent = None
    if os.path.exists("simulation_settings.txt"):
        with open("simulation_settings.txt") as f:
            for line in f:
                if line.startswith("allocated_cpu_percent ="):
                    try:
                        config_percent = int(line.split("=")[1].strip())
                    except: pass

    if config_percent and 1 <= config_percent <= 100:
        total_threads = os.cpu_count() or 1
        threads = max(1, math.floor(total_threads * (config_percent / 100.0)))
        print(f"[-] Using saved CPU allocation ({config_percent}%) -> {threads} threads (Out of {total_threads})")
        return threads

    print("\n[ CPU Performance Allocation ]")
    print("How much of your PC do you want to dedicate to this simulation?")
    print("Options: 15, 30, 45, 60, 75, 100 (Type the number)")
    while True:
        ans = input("Percentage (e.g. 75): ").strip()
        try:
            val = int(ans)
            if 1 <= val <= 100:
                total_threads = os.cpu_count() or 1
                threads = max(1, math.floor(total_threads * (val / 100.0)))
                print(f"[-] Allocating {val}% -> {threads} threads (Out of {total_threads})")
                return threads
        except ValueError: pass
        print("Invalid input. Please enter a number between 1 and 100.")

def start_mdrun(work_dir, append=False, threads=None):
    if threads is None:
        threads = get_cpu_threads_from_user()

    config = {}
    if os.path.exists("simulation_settings.txt"):
        with open("simulation_settings.txt") as f:
            for line in f:
                if "=" in line and not line.strip().startswith("#"):
                    parts = line.split("=", 1)
                    config[parts[0].strip()] = parts[1].strip()

    sim_mode = config.get("simulation_mode", "standard").lower()


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


reps = sorted(glob.glob("replica_*.tpr"))
num_reps = len(reps)
if num_reps == 0:
    sys.exit(0)

threads_total = {threads}
concurrent_jobs = min(num_reps, threads_total)
threads_per_rep = max(1, threads_total // concurrent_jobs)

def run_rep(r):
    prefix = os.path.splitext(r)[0]
    os.makedirs(prefix, exist_ok=True)
    out_prefix = os.path.join(prefix, prefix)
    cmd = ["gmx", "mdrun", "-s", r, "-deffnm", out_prefix, "-nt", str(threads_per_rep)]
    subprocess.run(cmd)
    gro_file = os.path.join(prefix, f"{{prefix}}.gro")
    pdb_file = os.path.join(prefix, f"{{prefix}}.pdb")
    if os.path.exists(gro_file):
        subprocess.run(["gmx", "editconf", "-f", gro_file, "-o", pdb_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

with ThreadPoolExecutor(max_workers=concurrent_jobs) as executor:
    list(executor.map(run_rep, reps))

xtcs = sorted(glob.glob(os.path.join("replica_*", "replica_*.xtc")))
if xtcs:
    os.makedirs("05_Results/Ensemble", exist_ok=True)
    out_xtc = "05_Results/Ensemble/ensemble_combined.xtc"
    cmd_cat = ["gmx", "trjcat", "-f"] + xtcs + ["-o", out_xtc]
    subprocess.run(cmd_cat, input="0\\n", universal_newlines=True)
    print("[-] Multi-Replica Ensemble Trajectory merged into 05_Results/Ensemble/ensemble_combined.xtc")
"""
        with open(os.path.join(work_dir, ".run_bg.py"), "w") as f:
            f.write(runner_code)
        cmd = [sys.executable, ".run_bg.py"]

    elif sim_mode == "fep":
        print("\n[-] Launching Alchemical FEP MDRun in background...")
        runner_code = f"""
import subprocess
import glob
import os
import sys
from concurrent.futures import ThreadPoolExecutor
{prep_code}

lambdas = sorted(glob.glob("fep_lambda_*.tpr"))
num_lambdas = len(lambdas)
if num_lambdas == 0:
    sys.exit(0)
threads_total = {threads}
concurrent_jobs = min(num_lambdas, threads_total)
threads_per_win = max(1, threads_total // concurrent_jobs)

def run_lambda(l):
    prefix = os.path.splitext(l)[0]
    cmd = ["gmx", "mdrun", "-s", l, "-deffnm", prefix, "-nt", str(threads_per_win)]
    subprocess.run(cmd)

with ThreadPoolExecutor(max_workers=concurrent_jobs) as executor:
    list(executor.map(run_lambda, lambdas))

xvgs = sorted(glob.glob("fep_lambda_*.xvg"))
if xvgs:
    os.makedirs("05_Results/FEP", exist_ok=True)
    cmd_bar = ["gmx", "bar", "-f"] + xvgs + ["-o", "05_Results/FEP/bar.xvg", "-g", "05_Results/FEP/barint.xvg"]
    res = subprocess.run(cmd_bar, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    with open("05_Results/FEP/binding_affinity_results.txt", "w") as f:
        f.write("=== ALCHEMICAL BINDING FREE ENERGY (FEP) RESULTS ===\\n\\n")
        f.write(res.stdout)
    print("[-] FEP Binding Free Energy calculation complete! Results saved in 05_Results/FEP/binding_affinity_results.txt")
"""
        with open(os.path.join(work_dir, ".run_bg.py"), "w") as f:
            f.write(runner_code)
        cmd = [sys.executable, ".run_bg.py"]

    else: # Standard
        cmd = ["gmx", "mdrun", "-deffnm", "md_0_1", "-nt", str(threads)]
        if append:
            cmd.extend(["-cpi", "md_0_1.cpt", "-append"])

    print(f"[-] Launching background process...")
    out_file = open(os.path.join(work_dir, "mdrun_out.log"), "w")
    proc = subprocess.Popen(cmd, cwd=work_dir, stdout=out_file, stderr=subprocess.STDOUT, start_new_session=True)

    with open(os.path.join(work_dir, ".mdrun.pid"), "w") as f:
        f.write(str(proc.pid))
    print(f"[-] MDRun started with PID: {proc.pid}")
    print("[-] You can safely close this terminal or check status from the main menu.")

def check_running_status(work_dir="complex", verbose=True):
    pid_file = os.path.join(work_dir, ".mdrun.pid")
    if not os.path.exists(pid_file):
        pid_file = os.path.join(work_dir, ".mdrun_pid")

    while True:
        if not os.path.exists(pid_file):
            if verbose:
                print("\n[-] No background simulation is currently running.\n")
            return False
        try:
            with open(pid_file) as f:
                pid = int(f.read().strip())
        except Exception:
            return False

        if psutil:
            is_running = psutil.pid_exists(pid)
        else:
            try:
                os.kill(pid, 0)
                is_running = True
            except OSError:
                is_running = False

        if not is_running:
            if os.path.exists(pid_file):
                try: os.remove(pid_file)
                except Exception: pass
            print("\n" + "="*42)
            print("  [!] PREVIOUS SIMULATION FINISHED  ")
            print("      (or was terminated manually)  ")
            print("="*42)
            print("[-] You can now proceed to Analysis (Option 5).")
            print("="*42 + "\n")
            return False

        # Parse simulation mode to know what logs to look for
        config = load_config() if 'load_config' in globals() else {}
        if not config and os.path.exists("simulation_settings.txt"):
            try:
                with open("simulation_settings.txt") as f:
                    for line in f:
                        if "=" in line and not line.strip().startswith("#"):
                            parts = line.split("=", 1)
                            config[parts[0].strip()] = parts[1].strip()
            except Exception: pass

        sim_mode = config.get("simulation_mode", "standard").lower()

        log_files = []
        if sim_mode == "ensemble":
            log_files = glob.glob(os.path.join(work_dir, "replica_*", "replica_*.log"))
        elif sim_mode == "fep":
            log_files = glob.glob(os.path.join(work_dir, "fep_lambda_*.log"))
        else:
            log_files = [os.path.join(work_dir, "md_0_1.log")]

        if not log_files or not any(os.path.exists(lf) for lf in log_files):
            log_files = glob.glob(os.path.join(work_dir, "*.log"))

        total_percent = 0.0
        total_curr_steps = 0
        total_max_steps = 0
        total_curr_ns = 0.0
        total_max_ns = 0.0
        ns_day_list = []
        valid_logs = 0

        for log_file in log_files:
            if os.path.exists(log_file):
                total_steps = 0
                dt = 0.001
                with open(log_file, "r", encoding="utf-8", errors="ignore") as f:
                    for _ in range(1000):
                        line = f.readline()
                        if not line:
                            break
                        if "nsteps" in line and "=" in line:
                            try:
                                total_steps = int(line.split("=")[1].strip())
                            except Exception: pass
                        if "dt" in line and "=" in line and "nsteps" not in line:
                            try:
                                dt = float(line.split("=")[1].strip())
                            except Exception: pass

                    f.seek(0, 2)
                    end_pos = f.tell()
                    start_pos = max(0, end_pos - 32768)
                    f.seek(start_pos)
                    lines = f.readlines()

                current_step = 0
                current_time_ps = 0.0
                parsed_ns_day = None

                for line in reversed(lines):
                    if parsed_ns_day is None and ("Performance:" in line or "ns/day" in line):
                        parts = line.split()
                        for p_idx, p_val in enumerate(parts):
                            if p_val == "Performance:" and p_idx + 1 < len(parts):
                                try:
                                    parsed_ns_day = float(parts[p_idx + 1])
                                    break
                                except Exception: pass
                            elif "ns/day" in p_val and p_idx > 0:
                                try:
                                    parsed_ns_day = float(parts[p_idx - 1])
                                    break
                                except Exception: pass

                    if current_step == 0:
                        parts = line.split()
                        if len(parts) >= 2 and parts[0].isdigit():
                            try:
                                c_step = int(parts[0])
                                c_time = float(parts[1])
                                if c_step > current_step:
                                    current_step = c_step
                                    current_time_ps = c_time
                            except Exception: pass

                    if current_step > 0 and parsed_ns_day is not None:
                        break

                current_ns = (current_step * dt) / 1000.0 if current_step > 0 else (current_time_ps / 1000.0)
                tot_ns = (total_steps * dt) / 1000.0 if total_steps > 0 else 0.0

                if parsed_ns_day is not None and parsed_ns_day > 0:
                    ns_day_list.append(parsed_ns_day)
                elif current_ns > 0:
                    try:
                        mtime = os.path.getmtime(log_file)
                        ctime = os.path.getctime(log_file)
                        elapsed = mtime - ctime
                        if elapsed > 10:
                            calc_ns_day = (current_ns / elapsed) * 86400.0
                            ns_day_list.append(calc_ns_day)
                    except Exception: pass

                if total_steps > 0:
                    total_percent += (current_step / total_steps) * 100.0
                    total_curr_steps += current_step
                    total_max_steps += total_steps
                    total_curr_ns += current_ns
                    total_max_ns += tot_ns
                    valid_logs += 1

        percent = (total_percent / valid_logs) if valid_logs > 0 else 0.0
        avg_ns_day = (sum(ns_day_list) / len(ns_day_list)) if ns_day_list else 0.0

        eta_str = "N/A"
        if avg_ns_day > 0 and total_max_ns > total_curr_ns:
            rem_ns = (total_max_ns - total_curr_ns) / (valid_logs if valid_logs > 0 else 1)
            rem_sec = (rem_ns / avg_ns_day) * 86400.0
            hrs = int(rem_sec // 3600)
            mins = int((rem_sec % 3600) // 60)
            secs = int(rem_sec % 60)
            if hrs > 0:
                eta_str = f"{hrs}h {mins}m {secs}s"
            else:
                eta_str = f"{mins}m {secs}s"

        curr_ns_disp = total_curr_ns / (valid_logs if valid_logs > 0 else 1)
        max_ns_disp = total_max_ns / (valid_logs if valid_logs > 0 else 1)
        curr_step_disp = int(total_curr_steps / (valid_logs if valid_logs > 0 else 1))
        max_step_disp = int(total_max_steps / (valid_logs if valid_logs > 0 else 1))

        print("\n" + "="*42)
        print("      SIMULATION CURRENTLY RUNNING      ")
        print("="*42)
        print(f"  PID:         {pid}")
        if max_ns_disp > 0:
            print(f"  Progress:    {curr_ns_disp:.2f} / {max_ns_disp:.2f} ns ({percent:.1f}%)")
            print(f"  Steps:       {curr_step_disp} / {max_step_disp}")
        else:
            print(f"  Completion:  {percent:.1f}%")
        print(f"  Throughput:  {avg_ns_day:.2f} ns/day" if avg_ns_day > 0 else "  Throughput:  N/A")
        print(f"  ETA:         {eta_str}")
        print("="*42)
        print("1. Live log view (tail -f log)")
        print("2. Pause Simulation")
        print("3. Refresh")
        print("4. Return to Main Menu")

        ans = input("\nSelect an option: ").strip()
        if ans == '1':
            if not log_files:
                print("[-] No log files found yet. Cannot enter live view.")
            else:
                print("[-] Entering Live View. Press Ctrl+C to exit.")
                try:
                    subprocess.run(["tail", "-f", log_files[-1]])
                except KeyboardInterrupt:
                    print("\n[-] Exited Live View.")
        elif ans == '2':
            print(f"[-] Sending graceful stop signal (SIGTERM) to PID {pid}...")
            try:
                try:
                    os.killpg(os.getpgid(pid), signal.SIGTERM)
                except AttributeError:
                    if psutil:
                        parent = psutil.Process(pid)
                        for child in parent.children(recursive=True):
                            child.terminate()
                        parent.terminate()
                        parent.wait(timeout=30)
                    else:
                        os.kill(pid, signal.SIGTERM)
                if os.path.exists(pid_file): os.remove(pid_file)
                print("[-] Run paused gracefully. A checkpoint (.cpt) was saved.")
            except Exception as e: print(f"[!] Error pausing: {e}")
            return False
        elif ans == '3':
            continue
        elif ans == '4':
            return False
        else:
            print("Invalid option.")

def check_pending_run(work_dir="complex"):
    cpt_file = os.path.join(work_dir, "md_0_1.cpt")
    gro_file = os.path.join(work_dir, "md_0_1.gro")
    pid_file = os.path.join(work_dir, ".mdrun.pid")

    if os.path.exists(cpt_file) and not os.path.exists(gro_file) and not os.path.exists(pid_file):
        print("\n[!] Detected a PAUSED/PENDING simulation.")
        ans = input("Do you want to RESUME it now? (y/N): ").strip().lower()
        if ans == 'y':
            print("\n[-] Resuming MD...")
            start_mdrun(work_dir, append=True)
            return True
    return False

def run_script_by_prefix(prefix):
    scripts = glob.glob(os.path.join(MODULES_DIR, f"{prefix}_*.py"))
    if not scripts:
        print(f"[!] No script found for prefix {prefix}")
        return False
    script_path = scripts[0]
    print(f"\n>>> Running {os.path.basename(script_path)} ...")
    result = subprocess.run([sys.executable, script_path], cwd=os.getcwd())
    return result.returncode == 0

def run_pipeline(step_by_step=False):
    if not os.path.exists("simulation_settings.txt"):
        print("[!] simulation_settings.txt not found. Please setup the project first.")
        return
    has_ligand = False
    with open("simulation_settings.txt") as f:
        for line in f:
            if "ligand_file" in line and "=" in line and not line.strip().startswith("#"):
                val = line.split("=", 1)[1].strip()
                if val and val.lower() != "none" and val != "": has_ligand = True

    steps = [2, 3]
    if has_ligand: steps.extend([4, 5])
    steps.extend([6, 7, 8])

    print("\n[-] Preparing for Molecular Dynamics Pipeline...")
    threads = get_cpu_threads_from_user()

    for step in steps:
        if step_by_step:
            ans = input(f"\nRun step {step}? [Y/n/q]: ").strip().lower()
            if ans == 'q': break
            if ans == 'n': continue
        if not run_script_by_prefix(str(step)):
            print(f"\n[!] Pipeline halted at step {step}.")
            return

        # If we just finished step 3 and there is NO ligand, we must setup the complex folder manually
        if step == 3 and not has_ligand:
            print("\n[-] No ligand specified. Setting up 'complex' folder with just the receptor...")
            import shutil
            os.makedirs("complex", exist_ok=True)
            try:
                shutil.copy("receptor/protein_processed.gro", "complex/complex.gro")
                shutil.copy("receptor/topol.top", "complex/topol.top")
                if os.path.exists("receptor/posre.itp"):
                    shutil.copy("receptor/posre.itp", "complex/posre.itp")
            except FileNotFoundError as e:
                print(f"[!] Warning: Could not copy receptor files to complex folder: {e}")

    start_mdrun("complex", append=False, threads=threads)
    print("\n[-] Preparation finished and Simulation started in background!")
    print("[-] Return to the main menu later to check status or analyze results.")

def analyze_results():
    has_ligand = False
    if os.path.exists("simulation_settings.txt"):
        with open("simulation_settings.txt") as f:
            for line in f:
                if line.startswith("ligand_file ="):
                    val = line.split("=", 1)[1].strip()
                    if val.lower() != "none": has_ligand = True

    print("\n" + "="*42)
    print("               ANALYSIS MENU              ")
    print("="*42)
    print("1. Optimize Best Configuration (Centering + Rot/Trans fixing)")
    print("2. Run Density Analysis (Calculates .dx files)")
    print("3. Show Density Map Instructions (For PyMOL)")
    print("4. Run Post-Processing & Cleanup (Scripts 13-16)")
    if has_ligand:
        print("5. Run MM-PBSA Binding Affinity Calculation (Script 18)")
        print("6. Return to Main Menu")
    else:
        print("5. Return to Main Menu")

    choice = input("\nSelect option: ").strip()
    if choice == '1':
        script = os.path.join(MODULES_DIR, "analysis_trajectory.py")
        if os.path.exists(script): subprocess.run([sys.executable, script], cwd=os.getcwd())
    elif choice == '2':
        script = os.path.join(MODULES_DIR, "analysis_density.py")
        if os.path.exists(script): subprocess.run([sys.executable, script], cwd=os.getcwd())
    elif choice == '3':
        pml_file = os.path.join(MODULES_DIR, "density_map.pml")
        if os.path.exists(pml_file):
            print("\n--- PyMOL Instructions ---")
            with open(pml_file) as f: print(f.read())
            print("--------------------------")
    elif choice == '4':
        print("\n[-] Running Post-Processing scripts...")
        run_script_by_prefix("13")
        run_script_by_prefix("14")
        run_script_by_prefix("15")
        run_script_by_prefix("16")
    elif choice == '5' and has_ligand:
        print("\n[-] Running MM-PBSA calculation...")
        run_script_by_prefix("18")


def interactive_config_wizard():
    if not os.path.exists("simulation_settings.txt"):
        print("[!] simulation_settings.txt not found. Please setup the project first (Option 1).")
        return

    ans = input("\nDo you want to use the Interactive Wizard, or Manual Edit? (I/m): ").strip().lower()
    if ans == 'm':
        editor = os.environ.get("EDITOR", "vi")
        subprocess.run([editor, "simulation_settings.txt"])
        return

    print("\n" + "="*50)
    print("      INTERACTIVE CONFIGURATION WIZARD          ")
    print("="*50)
    print("(Press TAB to auto-complete file names in this directory)\n")

    # --- 1. SIMULATION MODE SELECTION ---
    print("Select Simulation Mode:")
    print("  1. Standard MD (Single continuous simulation run)")
    print("  2. Multi-Replica Ensemble Sampling (Short runs with different random seeds for conformational sampling)")
    print("  3. Alchemical Free Energy / Binding Affinity (FEP lambda-states to calculate dG_bind)")

    mode_choice = input("Choice [1-3, Default: 1]: ").strip()
    sim_mode = "standard"
    if mode_choice == '2': sim_mode = "ensemble"
    elif mode_choice == '3': sim_mode = "fep"

    print(f"[-] Selected Mode: {sim_mode.upper()}")

    # --- 2. FILE SELECTION ---
    current_prot = "Pa_relaxed.pdb"
    current_lig = "None"
    if os.path.exists("simulation_settings.txt"):
        with open("simulation_settings.txt") as f:
            for line in f:
                if line.startswith("protein_pdb ="):
                    current_prot = line.split("=", 1)[1].strip()
                elif line.startswith("ligand_file ="):
                    current_lig = line.split("=", 1)[1].strip()

    # Auto-detect PDBs and Ligands in working directory
    pdbs = glob.glob("*.pdb")
    mols = glob.glob("*.mol2") + glob.glob("*.sdf")

    # Protein Default Determination:
    if os.path.exists(current_prot):
        default_prot = current_prot
    elif pdbs:
        default_prot = pdbs[0]
    else:
        default_prot = "Pa_relaxed.pdb"

    if pdbs:
        print(f"Detected PDB files: {', '.join(pdbs)}")
    protein = input(f"Protein PDB File [Press Enter for '{default_prot}']: ").strip()
    if not protein:
        protein = default_prot

    # Ligand Default Determination:
    has_ligand_ans = input("Does this simulation include a ligand? (y/N): ").strip().lower()
    ligand = None
    if has_ligand_ans == 'y':
        if current_lig.lower() != "none" and os.path.exists(current_lig):
            default_lig = current_lig
        elif mols:
            default_lig = mols[0]
        else:
            default_lig = ""

        if mols:
            print(f"Detected Ligand files: {', '.join(mols)}")

        lig_prompt = f"Ligand File (Accepted formats: .mol2, .sdf) [Press Enter for '{default_lig}']: " if default_lig else "Ligand File (Accepted formats: .mol2, .sdf): "
        ligand = input(lig_prompt).strip()
        if not ligand and default_lig:
            ligand = default_lig

    # --- 3. WATER MODEL SELECTION ---
    print("\n[ Water Model Selection ]")
    print("  1. TIP3P (Recommended default for Amber/CHARMM force fields)")
    print("  2. SPC/E (Better dielectric constant and liquid water density)")
    print("  3. TIP4P (4-site model, improved electrostatic distribution)")
    w_choice = input("Select Water Model [1-3, Default: 1]: ").strip()
    water_model = "tip3p"
    if w_choice == '2': water_model = "spce"
    elif w_choice == '3': water_model = "tip4p"

    # --- 4. MODE SPECIFIC PARAMETERS & GUIDANCE ---
    ensemble_reps = "5"
    rep_time = "5.0"
    fep_lambdas = "11"
    fep_time = "2.0"
    sim_time = "0.1"

    if sim_mode == "ensemble":
        print("\n[ Multi-Replica Ensemble Guidance ]")
        print("  - Replicas run independent simulations starting from different random velocity seeds.")
        print("  - Recommended: 5 to 10 replicas of 5.0 ns each to thoroughly explore conformational space.")
        reps_input = input("Number of Replicas [Default: 5]: ").strip()
        if reps_input.isdigit(): ensemble_reps = reps_input
        time_input = input("Time per Replica in ns [Default: 5.0]: ").strip()
        if time_input: rep_time = time_input
        total_sim_ns = float(ensemble_reps) * float(rep_time)
        print(f"[-] Cumulative Ensemble Simulation: {total_sim_ns:.1f} ns total")

    elif sim_mode == "fep":
        print("\n[ Alchemical Binding Free Energy (FEP) Guidance ]")
        print("  - FEP decouples electrostatic and VdW interactions across intermediate lambda states.")
        print("  - Recommended: 11 lambda windows (e.g. 2.0 ns per window) for robust Bennett Acceptance Ratio (gmx bar) convergence.")
        lambdas_input = input("Number of Lambda Windows [Default: 11]: ").strip()
        if lambdas_input.isdigit(): fep_lambdas = lambdas_input
        ftime_input = input("Time per Lambda Window in ns [Default: 2.0]: ").strip()
        if ftime_input: fep_time = ftime_input
        total_sim_ns = float(fep_lambdas) * float(fep_time)
        print(f"[-] Cumulative FEP Simulation: {total_sim_ns:.1f} ns total")

    else: # standard
        stime_input = input("\nSimulation Time in ns [Default: 0.1]: ").strip()
        if stime_input: sim_time = stime_input
        total_sim_ns = float(sim_time)

    # --- 5. RUNTIME & RESOURCE ESTIMATOR ---
    print("\n" + "="*50)
    print("        RESOURCE & RUNTIME ESTIMATOR          ")
    print("="*50)

    alloc_percent = input("Percentage of PC to dedicate (e.g. 75) [Default: 75]: ").strip()
    if not alloc_percent.isdigit() or not (1 <= int(alloc_percent) <= 100):
        alloc_percent = "75"

    total_cpus = os.cpu_count() or 1
    threads = max(1, math.floor(total_cpus * (int(alloc_percent) / 100.0)))
    print(f"[-] Allocating {alloc_percent}% -> {threads} threads (Out of {total_cpus})")

    # Benchmark estimate (~10-20 ns/day per thread allocation)
    est_hours = (total_sim_ns * 24.0) / (threads * 1.5)
    print(f"[-] Total Simulation Workload: {total_sim_ns:.2f} ns")
    print(f"[-] Estimated Completion Time: ~{est_hours:.1f} hours ({est_hours*60:.0f} mins) on allocated resources.")
    print("="*50)

    # --- 6. WRITE UPDATED SETTINGS ---
    print("\n[-] Updating simulation_settings.txt...")

    with open("simulation_settings.txt", "r") as f:
        lines = f.readlines()

    has_alloc_line = False
    with open("simulation_settings.txt", "w") as f:
        for line in lines:
            if line.startswith("protein_pdb =") and protein:
                f.write(f"protein_pdb = {protein}\n")
            elif line.startswith("ligand_file ="):
                if has_ligand_ans != 'y':
                    f.write("ligand_file = None\n")
                elif ligand:
                    f.write(f"ligand_file = {ligand}\n")
                else:
                    f.write(line)
            elif line.startswith("ligand_resname ="):
                if has_ligand_ans == 'y':
                    f.write("ligand_resname = MOL\n")
                else:
                    f.write(line)
            elif line.startswith("simulation_mode ="):
                f.write(f"simulation_mode = {sim_mode}\n")
            elif line.startswith("ensemble_replicas ="):
                f.write(f"ensemble_replicas = {ensemble_reps}\n")
            elif line.startswith("replica_time_ns ="):
                f.write(f"replica_time_ns = {rep_time}\n")
            elif line.startswith("fep_lambda_windows ="):
                f.write(f"fep_lambda_windows = {fep_lambdas}\n")
            elif line.startswith("fep_window_time_ns ="):
                f.write(f"fep_window_time_ns = {fep_time}\n")
            elif line.startswith("simulation_time_ns =") and sim_mode == "standard":
                f.write(f"simulation_time_ns = {sim_time}\n")
            elif line.startswith("allocated_cpu_percent ="):
                f.write(f"allocated_cpu_percent = {alloc_percent}\n")
                has_alloc_line = True
            else:
                f.write(line)
        if not has_alloc_line:
            f.write(f"allocated_cpu_percent = {alloc_percent}\n")

    print("[-] Settings updated successfully!")


def autocorrect_working_directory():
    """
    Traverses upwards to find the true project root ('complex' equivalent)
    by looking for known marker files, or falls back to known subdirectories.
    """
    current_dir = os.getcwd()
    check_dir = current_dir

    # 1. Search upwards for definitive root markers
    while True:
        if os.path.exists(os.path.join(check_dir, "simulation_settings.txt")) or \
           os.path.exists(os.path.join(check_dir, "receptor")):
            if os.getcwd() != check_dir:
                print(f"[*] Auto-correcting working directory to root: {check_dir}")
                os.chdir(check_dir)
            return check_dir

        parent = os.path.dirname(check_dir)
        if parent == check_dir: # Hit the filesystem root
            break
        check_dir = parent

    # 2. Fallback: If no markers exist, check if we are in a known Gromacs subdirectory
    known_subdirs = [
        "01_Setup", "02_Minimization", "03_Equilibration",
        "04_Production", "05_Results", "06_Analysis", "complex"
    ]
    base_name = os.path.basename(current_dir)
    if base_name in known_subdirs:
        parent_dir = os.path.dirname(current_dir)
        print(f"[*] Auto-correcting working directory from {base_name} to parent: {parent_dir}")
        os.chdir(parent_dir)
        return parent_dir

    return current_dir

def main_menu():
    # Global fix: Auto-correct working directory if user launched from inside 'complex' or a subfolder
    autocorrect_working_directory()

    if os.path.exists(os.path.join("complex", ".mdrun.pid")) or os.path.exists(os.path.join("complex", ".mdrun_pid")):
        if check_running_status("complex", verbose=False): return
    if check_pending_run("complex"): return


    while True:
        print_header()

        # Check for prep errors
        if os.path.exists(os.path.join("complex", "ERROR_PREP.txt")):
            print("\n[!] WARNING: A background preparation step (Minimization/Equilibration) failed!")
            print("    Check complex/ERROR_PREP.txt or the respective logs for details.")
            with open(os.path.join("complex", "ERROR_PREP.txt"), "r") as f:
                print("    Error Message: " + f.read().strip())
            print("    Please resolve the issue before starting a new run.\n")

        print("1. Setup New Project (Create config)")
        print("2. Edit Settings (simulation_settings.txt)")
        print("3. Run Full Pipeline (Auto)")
        print("4. Run Pipeline (Step-by-step)")
        print("5. Analyze Results & Post-Processing")
        print("6. View Background Simulation Progress")
        print("7. Decompress Files")
        print("8. Cleanup Workspace")
        print("9. Exit")

        choice = input("\nSelect an option: ").strip()
        if choice == '1': run_script_by_prefix("1")
        elif choice == '2': interactive_config_wizard()
        elif choice == '3': run_pipeline(step_by_step=False)
        elif choice == '4': run_pipeline(step_by_step=True)
        elif choice == '5': analyze_results()
        elif choice == '6': check_running_status("complex", verbose=True)
        elif choice == '7': run_script_by_prefix("17")
        elif choice == '8': run_script_by_prefix("99")
        elif choice == '9':
            print("Exiting...")
            break
        else: print("Invalid option. Please try again.")

if __name__ == "__main__":
    main_menu()
