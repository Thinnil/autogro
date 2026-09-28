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
import shutil
from pathlib import Path

config = {}
with open("simulation_settings.txt") as f:
    for line in f:
        if "=" in line and not line.strip().startswith("#"):
            key, val = line.strip().split("=", 1)
            config[key.strip()] = val.strip()

lig_dir = "ligand"
lig_file = config['ligand_file']
import sys
os.makedirs(lig_dir, exist_ok=True)

if not os.path.exists(os.path.join(lig_dir, lig_file)):
    if os.path.exists(lig_file):
        print(f"[-] Auto-copying {lig_file} into {lig_dir}/ ...")
        shutil.copy(lig_file, os.path.join(lig_dir, lig_file))
    else:
        print(f"[!] Error: {lig_file} not found in current directory!")
        sys.exit(1)

charge = config['ligand_charge']
mult = config['ligand_multiplicity']
resname = config['ligand_resname']

_BINARY_CACHE = {}
_CONDA_ENVS_CACHE = None
_ENV_LD_PATH_CACHE = {}
_BASE_DIRS_CACHE = None

def _get_existing_base_dirs():
    global _BASE_DIRS_CACHE
    if _BASE_DIRS_CACHE is not None:
        return _BASE_DIRS_CACHE
    home = Path.home()
    standard = [
        home / ".micromamba" / "envs",
        home / "miniconda3" / "envs",
        home / "anaconda3" / "envs",
        home / ".conda" / "envs",
        Path("/opt/conda/envs"),
        Path("/data1/mgs/micromamba/envs")
    ]
    _BASE_DIRS_CACHE = [d for d in standard if d.is_dir()]
    return _BASE_DIRS_CACHE

def _get_conda_env_entries():
    global _CONDA_ENVS_CACHE
    if _CONDA_ENVS_CACHE is not None:
        return _CONDA_ENVS_CACHE
    home = Path.home()
    env_entries = []
    envs_txt = home / ".conda" / "environments.txt"
    if envs_txt.is_file():
        try:
            with open(envs_txt, "r") as f:
                for line in f:
                    path_str = line.strip()
                    if path_str and os.path.exists(path_str):
                        env_path = Path(path_str)
                        env_name = env_path.name
                        env_entries.append((env_name, env_path, "conda"))
            if env_entries:
                _CONDA_ENVS_CACHE = env_entries
                return _CONDA_ENVS_CACHE
        except Exception:
            pass
    for conda_exe_name in ['micromamba', 'mamba', 'conda']:
        conda_exe = shutil.which(conda_exe_name)
        if not conda_exe:
            for fallback in [
                home / ".local" / "bin" / conda_exe_name,
                home / "miniconda3" / "bin" / conda_exe_name,
                home / "anaconda3" / "bin" / conda_exe_name,
                home / ".micromamba" / "bin" / conda_exe_name,
                Path("/opt/conda/bin") / conda_exe_name,
                Path("/data1/mgs/micromamba/bin") / conda_exe_name
            ]:
                if fallback.is_file():
                    conda_exe = str(fallback)
                    break
        if conda_exe:
            try:
                res = subprocess.run([conda_exe, "env", "list"], capture_output=True, text=True, timeout=10)
                if res.returncode == 0:
                    for line in res.stdout.splitlines():
                        line = line.strip()
                        if line and not line.startswith('#'):
                            parts = line.split()
                            path_part = parts[-1]
                            if os.path.exists(path_part):
                                env_name = parts[0] if (len(parts) > 1 and parts[0] != '*') else os.path.basename(path_part)
                                env_entries.append((env_name, Path(path_part), conda_exe))
                    if env_entries:
                        break
            except Exception:
                pass
    _CONDA_ENVS_CACHE = env_entries
    return _CONDA_ENVS_CACHE

def resolve_binary(binary_name, preferred_envs=('ambertools', 'acpype', 'autogro', 'base')):
    cache_key = (binary_name, tuple(preferred_envs) if isinstance(preferred_envs, (list, tuple)) else preferred_envs)
    if cache_key in _BINARY_CACHE:
        return list(_BINARY_CACHE[cache_key])
    path_bin = shutil.which(binary_name)
    if path_bin:
        result = [path_bin]
        _BINARY_CACHE[cache_key] = result
        return list(result)
    standard_base_dirs = _get_existing_base_dirs()
    def check_env_dir(env_dir):
        for sub in ['bin', 'Scripts']:
            candidate = env_dir / sub / binary_name
            if candidate.is_file():
                return str(candidate)
        return None
    for env_name in preferred_envs:
        for base_dir in standard_base_dirs:
            env_dir = base_dir / env_name
            if env_dir.is_dir():
                binary_path = check_env_dir(env_dir)
                if binary_path:
                    result = [binary_path]
                    _BINARY_CACHE[cache_key] = result
                    return list(result)
    for base_dir in standard_base_dirs:
        try:
            for env_dir in base_dir.iterdir():
                if env_dir.is_dir():
                    binary_path = check_env_dir(env_dir)
                    if binary_path:
                        result = [binary_path]
                        _BINARY_CACHE[cache_key] = result
                        return list(result)
        except Exception:
            pass
    env_entries = _get_conda_env_entries()
    if env_entries:
        fallback_cmd = None
        for pref in preferred_envs:
            for name, path, conda_exe in env_entries:
                if name == pref or path.name == pref:
                    binary_path = check_env_dir(path)
                    if binary_path:
                        result = [binary_path]
                        _BINARY_CACHE[cache_key] = result
                        return list(result)
                    if fallback_cmd is None:
                        fallback_cmd = [conda_exe, "run", "-n", name, binary_name]
        for name, path, conda_exe in env_entries:
            binary_path = check_env_dir(path)
            if binary_path:
                result = [binary_path]
                _BINARY_CACHE[cache_key] = result
                return list(result)
        if fallback_cmd:
            _BINARY_CACHE[cache_key] = fallback_cmd
            return list(fallback_cmd)
    return [binary_name]

def _get_env_with_ld_path(binary_cmd):
    cache_key = tuple(str(x) for x in binary_cmd) if isinstance(binary_cmd, (list, tuple)) else (str(binary_cmd),)
    if cache_key in _ENV_LD_PATH_CACHE:
        return _ENV_LD_PATH_CACHE[cache_key].copy()

    env = os.environ.copy()
    if not binary_cmd:
        _ENV_LD_PATH_CACHE[cache_key] = env
        return env.copy()

    found_lib = None
    for item in binary_cmd:
        p = Path(item)
        bin_path = p if p.is_file() else None
        if not bin_path:
            w = shutil.which(item)
            if w:
                bin_path = Path(w)
        if bin_path:
            parent_dir = bin_path.parent
            if parent_dir.name.lower() in ('bin', 'scripts'):
                lib_dir = parent_dir.parent / 'lib'
            else:
                lib_dir = parent_dir / 'lib'
            if lib_dir.is_dir():
                found_lib = lib_dir
                break

    if not found_lib:
        standard_base_dirs = _get_existing_base_dirs()
        preferred_envs = ('ambertools', 'acpype', 'autogro', 'base')
        for item in list(binary_cmd) + list(preferred_envs):
            item_name = Path(item).name if isinstance(item, (str, Path)) else str(item)
            for base_dir in standard_base_dirs:
                env_lib = base_dir / item_name / "lib"
                if env_lib.is_dir():
                    found_lib = env_lib
                    break
            if found_lib:
                break

    if found_lib:
        amber_home = found_lib.parent
        amber_home_str = str(amber_home)
        env["AMBERHOME"] = amber_home_str

        lib_str = str(found_lib)
        ld_path = env.get("LD_LIBRARY_PATH", "")
        if ld_path:
            if lib_str not in ld_path.split(os.pathsep):
                env["LD_LIBRARY_PATH"] = f"{lib_str}{os.pathsep}{ld_path}"
        else:
            env["LD_LIBRARY_PATH"] = lib_str

        bin_str = str(amber_home / "bin")
        path_str = env.get("PATH", "")
        if path_str:
            if bin_str not in path_str.split(os.pathsep):
                env["PATH"] = f"{bin_str}{os.pathsep}{path_str}"
        else:
            env["PATH"] = bin_str

    _ENV_LD_PATH_CACHE[cache_key] = env
    return env.copy()

antechamber_cmd = resolve_binary("antechamber")
acpype_cmd = resolve_binary("acpype")

print(f"[-] Antechamber resolved as: {' '.join(antechamber_cmd)}")
print(f"[-] ACPYPE resolved as: {' '.join(acpype_cmd)}")

ligand_ext = lig_file.split(".")[-1].lower()
in_format = "mol2"
if ligand_ext in ["sdf", "mdl"]:
    in_format = "sdf"

# Step 1: Antechamber
cmd_ac = antechamber_cmd + [
    "-i", lig_file, "-fi", in_format,
    "-o", "ligand_out.mol2", "-fo", "mol2",
    "-c", "bcc", "-s", "2", "-nc", charge, "-m", mult
]
res_ac = subprocess.run(cmd_ac, cwd=lig_dir, env=_get_env_with_ld_path(antechamber_cmd), check=False)

# Fallback to gasteiger if am1-bcc fails
if res_ac.returncode != 0:
    print("\n[!] ACPYPE AM1-BCC charge calculation failed! The ligand geometry might be strained.")
    print("[-] FALLBACK: Attempting to calculate empirical Gasteiger charges instead...")
    cmd_ac = antechamber_cmd + [
        "-i", lig_file, "-fi", in_format,
        "-o", "ligand_out.mol2", "-fo", "mol2",
        "-c", "gas", "-s", "2", "-nc", charge, "-m", mult
    ]
    res_ac = subprocess.run(cmd_ac, cwd=lig_dir, env=_get_env_with_ld_path(antechamber_cmd), check=False)
if res_ac.returncode != 0:
    print("[!] ERROR during Antechamber execution.")
    log_pipeline_msg("Step 4", "Antechamber execution failed.", is_error=True)
    sys.exit(1)

# Step 2: ACPYPE
cmd_pype = acpype_cmd + [
    "-i", "ligand_out.mol2", "-c", "user", "-n", charge
]
res_pype = subprocess.run(cmd_pype, cwd=lig_dir, env=_get_env_with_ld_path(acpype_cmd))
if res_pype.returncode != 0:
    print("[!] ERROR during ACPYPE execution.")
    log_pipeline_msg("Step 4", "ACPYPE execution failed.", is_error=True)
    sys.exit(1)

print("[-] ACPYPE finished. Renaming output files...")
acpype_out_dir = os.path.join(lig_dir, "ligand_out.acpype")
try:
    shutil.copy(os.path.join(acpype_out_dir, "ligand_out_GMX.gro"), os.path.join(lig_dir, "ligand.gro"))
    shutil.copy(os.path.join(acpype_out_dir, "ligand_out_GMX.itp"), os.path.join(lig_dir, "ligand.itp"))
except Exception as e:
    print(f"[!] ERROR during file copying: {e}")
    sys.exit(1)

log_pipeline_msg("Step 4", "OK")
