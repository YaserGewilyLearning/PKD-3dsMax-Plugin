import re

file_path = r'd:\Social\Plugin\AI Agent\3ds Max Plugin\files\PKD_KitchenUnit_V125.ms'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add PKD_AutoUpdate at the top
if 'global PKD_AutoUpdate' not in content:
    auto_update_code = '''
global PKD_AutoUpdate
fn PKD_AutoUpdate =
(
    if PKD_MainUI != undefined and selection.count > 0 do
    (
        local g = PKD_GetHead selection[1]
        if g != undefined do
        (
            local p = PKD_MainUI.readUI()
            p.doorSides = (PKD_LoadProps g).doorSides
            undo "PKD Auto Update" on ( with redraw off ( PKD_Build p oldGroup:g ) )
        )
    )
)
'''
    insert_pos = content.find('global PKD_MainUI')
    if insert_pos != -1:
        content = content[:insert_pos] + auto_update_code + '\n' + content[insert_pos:]
    else:
        content = auto_update_code + content

# 2. Add carcassD
content = re.sub(
    r'(local W = p\.W, H = p\.H, D = p\.D, t = p\.t, tb = p\.tb)',
    r'\1\n    local carcassD = if p.backMode == 1 then (D - tb) else D',
    content
)

# Replace D with carcassD for sides, base, stretchers, top
# Targeted replacements in PKD_Build
content = re.sub(
    r'(PKD_Part "Side_Left".*?) t D ',
    r'\1 t carcassD ',
    content
)
content = re.sub(
    r'(PKD_Part "Side_Right".*?) t D ',
    r'\1 t carcassD ',
    content
)
content = re.sub(
    r'(PKD_Part "Base".*?) W D t ',
    r'\1 W carcassD t ',
    content
)
# Top_Full replacement
content = re.sub(
    r'(PKD_Part "Top_Full" mTop W) D (t 0 0 \(fTopZ - t\))',
    r'\1 (carcassD - p.frontStSet) \2',
    content
)
content = re.sub(
    r'(PKD_Part "Top_Full" mTop \(W - 2\*t\)) D (t t 0 \(fTopZ - t\))',
    r'\1 (carcassD - p.frontStSet) \2',
    content
)
# Top_Full position tfSet (Y position)
content = re.sub(
    r'(PKD_Part "Top_Full" mTop W \(carcassD - p\.frontStSet\) t 0 )0( \(fTopZ - t\))',
    r'\1p.frontStSet\2',
    content
)
content = re.sub(
    r'(PKD_Part "Top_Full" mTop \(W - 2\*t\) \(carcassD - p\.frontStSet\) t t )0( \(fTopZ - t\))',
    r'\1p.frontStSet\2',
    content
)

# bsY limit replacements
content = re.sub(
    r'default: bsY = D - bStD',
    r'default: bsY = carcassD - bStD',
    content
)
content = re.sub(
    r'if \(bsY \+ bStD\) > D do bsY = D - bStD',
    r'if (bsY + bStD) > carcassD do bsY = carcassD - bStD',
    content
)

# Fix backMode == 1 dimensions
content = re.sub(
    r'(if p\.backMode == 2 then \( backW = \(W - 2\*t\) \+ \(2 \* p\.grooveDepth\); backX = t - p\.grooveDepth \))\n(\s*)else\s*\( backW = W - 2\*t;\s*backX = t \)',
    r'\1\n\2else if p.backMode == 1 then ( backW = W; backX = 0 )\n\2else                    ( backW = W - 2*t;                          backX = t )',
    content
)

content = re.sub(
    r'(local backBottomZ = usableBottom)\n(\s*)(if p\.backMode == 2 do backBottomZ = usableBottom - p\.grooveDepth)\n\s*(local backTopZ)',
    r'\1\n\2\3\n\2if p.backMode == 1 do backBottomZ = baseZMin\n\2\4',
    content
)

content = re.sub(
    r'(local backH = backTopZ - backBottomZ)\n(\s*)(if backH > 0 do)',
    r'\1\n\2if p.backMode == 1 do backH = H\n\2\3',
    content
)

# rAssembly syncVis changes
content = re.sub(
    r'(spnFrontSet\.visible = )isStretch(; lc_spnFrontSet\.visible = )isStretch',
    r'\1true\2true',
    content
)

content = re.sub(
    r'(label lc_spnFrontSet ")رجوع الشداد الأمامي \(سم\):(")',
    r'\1رجوع الشداد / السقف (سم):\2',
    content
)

# AutoUpdate binding
lines = content.split('\n')
in_rollout = False
for i, line in enumerate(lines):
    if line.strip().startswith('rollout r'):
        in_rollout = True
    if in_rollout and line.strip().startswith('on ') and (' changed ' in line or ' selected ' in line):
        if 'PKD_AutoUpdate()' not in line:
            if ' do ' in line:
                parts = line.split(' do ', 1)
                before = parts[0] + ' do '
                after = parts[1].strip()
                if after == '':
                    pass
                elif after.startswith('(') and after.endswith(')'):
                    after = '( ' + after[1:-1].strip() + '; PKD_AutoUpdate() )'
                else:
                    after = '( ' + after + '; PKD_AutoUpdate() )'
                lines[i] = before + after

content = '\n'.join(lines)

with open(file_path, 'w', encoding='utf-8-sig') as f:
    f.write(content)
print('Done!')
