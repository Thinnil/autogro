# 1. Load the files (Adjust filenames if needed)
load complex/md_centered.pdb
load complex/density_ligand_ALL.dx

# 2. visual clean up
hide everything
show cartoon, protein
show sticks, resn MOL
bg_color white

# 3. Create the Volume Object
# We name it "lig_fog"
volume lig_fog, density_ligand_ALL

# 4. RESET THE RAMP (The Magic Part)
# We define a "Color Ramp" manually.
# Format: [ value, color, opacity ]
# We use very low numbers because density maps are often sparse.

volume_ramp_new lig_fog, \
    0.005, blue, 0.0, \
    0.02,  blue, 0.1, \
    0.05,  cyan, 0.3, \
    0.10,  yellow, 0.6, \
    0.30,  red, 1.0

# EXPLANATION OF THE NUMBERS:
# 0.005 -> Everything below this is INVISIBLE (Alpha 0.0)
# 0.02  -> Low density areas appear as FAINT BLUE mist (Alpha 0.1)
# 0.05  -> Medium-low areas appear CYAN and distinct (Alpha 0.3)
# 0.10  -> Dense areas appear YELLOW and solid (Alpha 0.6)
# 0.30  -> The "Core" (highest density) is solid RED (Alpha 1.0)

# 5. Zoom to the ligand so you don't get lost
zoom resn MOL
