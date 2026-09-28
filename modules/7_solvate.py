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

model = config['water_box_model']

cmd = [
    "gmx", "solvate",
    "-cp", "box.gro",
    "-cs", model,
    "-o", "solvated.gro",
    "-p", "topol.top"
]

print("[-] Solvating system...")
subprocess.run(cmd, cwd="complex")
log_pipeline_msg("Step 7", "OK")
