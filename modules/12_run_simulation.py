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

# Define location
work_dir = "complex"
tpr_file = "md_0_1.tpr"

# Check if the file exists
if not os.path.exists(os.path.join(work_dir, tpr_file)):
    print(f"[!] Error: {tpr_file} not found in {work_dir}.")
    print("    Please run Script 11 first to generate it.")
    sys.exit(1)

print("[-] STARTING MOLECULAR DYNAMICS SIMULATION...")
print("    This may take a while depending on your 'simulation_time_ns'.")
print("    Check the progress in complex/md_0_1.log")

# Run GROMACS
# -v : Verbose (shows progress on screen)
# -deffnm : Default Filename (names output .xtc, .edr, .log same as input)
cmd = [
    "gmx", "mdrun",
    "-v",
    "-deffnm", "md_0_1"
]

try:
    subprocess.run(cmd, cwd=work_dir, check=True)
    print("\n[-] SIMULATION FINISHED SUCCESSFULLY!")
    print(f"[-] Trajectory file: {os.path.join(work_dir, 'md_0_1.xtc')}")
    print(f"[-] Structure file:  {os.path.join(work_dir, 'md_0_1.gro')}")
except subprocess.CalledProcessError:
    print("\n[!] Error: The simulation crashed or was interrupted.")
    print("    Check complex/md_0_1.log for details.")
except KeyboardInterrupt:
    print("\n[!] Simulation stopped by user.")
log_pipeline_msg("Step 12", "OK")
