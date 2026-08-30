global PKD_ActiveUnit
﻿/*
================================================================================
  Pro Kitchen Design - Base Unit Builder
  Version : 12.7 (Refactored + Geometry Fixes + UI Regroup)
  Original: Eng. Yaser Gewily
  Units   : All internal logic is in CENTIMETERS, converted to system units
            automatically at draw time (works in cm / mm / m / inch scenes).
================================================================================
  CHANGE LOG vs V7
  ----------------
  [FIX 01] Partition no longer intersects Base / Top / Stretchers.
  [FIX 02] Shelves are now generated PER BAY (respect partitions).
  [FIX 03] Inset door top limited to underside of top panel (usableTop).
  [FIX 04] Shelf depth clamped to available internal depth.
  [FIX 05] Back panel no longer intersects Base / Top / Back stretcher.
  [FIX 06] Leg count scales with unit width (max 60cm spacing).
  [FIX 07] Custom door width now advances cursor correctly (no overlap).
  [FIX 08] Rebuild deletes ALL descendants (no orphan panels left in scene).
  [FIX 09] Unit-independent (units.decodeValue) - no more silent wrong sizes.
  [FIX 10] Materials are reused, not duplicated on every build.
  [FIX 11] undo context + redraw off (single Ctrl+Z, much faster build).
  [FIX 12] CSV: BOM, quoting, hardware filtered out, QTY aggregation,
           dimensions read from stored logical props (scale-safe).
  [FIX 13] Scoping fixed - rollouts are true globals, no ::name mismatch.
  [FIX 14] Hebrew typo in Arabic messagebox removed.
  [FIX 15] Transform preserved correctly on Update (position AND rotation).
================================================================================
*/

try ( destroyDialog PKD_MainUI ) catch ()

global PKD_IsEnglish = false
global PKD_SCALE     = 1.0     -- system units per 1 cm


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
            
            local wasIsolated = false
            try ( wasIsolated = IsolateSelection.IsolateSelectionModeActive() ) catch ( wasIsolated = false )
            if wasIsolated do
            (
                try ( IsolateSelection.ExitIsolateSelectionMode() ) catch ()
            )
            
            local newG = undefined
            disableSceneRedraw()
            try (
                with undo off ( with redraw off ( newG = PKD_Build p oldGroup:g ) )
            ) catch ( format "PKD AutoUpdate Exception: %\n" (getCurrentException()) )
            enableSceneRedraw()
            completeRedraw()
            
            if newG != undefined do
            (
                select newG
                if wasIsolated do
                (
                    try ( IsolateSelection.EnterIsolateSelectionMode() ) catch ()
                )
            )
        )
    )
)

global PKD_MainUI
global rBasic, rAssembly, rBack, rLegs, rShelves, rParts, rDoors, rMat, rHandles
global PKD_ShowPanel, PKD_PullPanel, PKD_PushPanel, PKD_LangPanel, PKD_CatNames


-------------------------------------------------------------------------------
-- 1. PARAMETER STRUCT  (pure data - no UI dependency)
--    Lengths in CM. Thicknesses converted from mm at the UI boundary.
-------------------------------------------------------------------------------
struct PKD_Params
(
    W = 60.0, H = 76.0, D = 60.0,
    t = 1.8,  tb = 0.8,

    topMode = 2,        -- 1 = Full Top , 2 = Stretchers   (default = Stretchers)
    fullTopType = 1,    -- 1 = Between Sides , 2 = Over Sides
    stretch = 7.0,
    fDir = 1,           -- 1 = Horizontal , 2 = Vertical
    bDir = 1,
    frontStSet = 0.0,   -- front stretcher pushed back from the front face (cm)
    backStPos = 1,      -- 1 = over back (back inset 8mm) , 2 = in front of back , 3 = behind back

    backMode = 2,       -- 1 = Nailed , 2 = Grooved   (default = Grooved)
    grooveDepth = 0.8,
    setback = 1.8,

    legH = 10.0,
    legName = "PVC Leg 100mm",
    shelves = 1,
    shelfD = 50.0,
    shelfClear = 0.1,

    partActive = false,
    partCount = 1,
    partPos = 2,        -- 2 = Right (+X) , 3 = Left
    partMode = 1,       -- 1 = stops under top/stretchers , 2 = full side height + notch

    doorType = 3,       -- 1 = Inset (ركبة) , 3 = Full Overlay (عدلة)  -> default عدلة
    doors = 1,
    doorGap = 1.5,     -- MM (stored 1:1 with the spinner, converted in the build)
    doorThick = 1.8,
    hingeSide = 2,      -- 1 = Auto , 2 = Right (+X) , 3 = Left (-X)
    doorSides = "",     -- per-door override, e.g. "0,2,3"  (0 = follow hingeSide)

    unitType = 1,       -- 1 = Base , 2 = Wall , 3 = Corner , 4 = Tall
    matCarcass = "Counter White HPL",
    matDoor    = "Poly-Lac Red",
    matBack    = "HDF 8mm White",
    bandWidth  = 2.2,   -- edge banding tape width (cm)
    bandPrice  = 0.0,   -- price per metre
    sheetL = 244.0, sheetW = 122.0,
    waste  = 15.0,      -- %
    sheetPrice = 0.0,
    openAfter = true,

    handleKind = 1,     -- 1 = built-in box , 2 = from the handle library
    handleLib  = "",    -- library entry name
    handleAxis = 1,     -- 1 = vertical (length on Z) , 2 = horizontal (length on X)
    handleAsIs = false, -- keep the model's own orientation, only move it into place
    golaFit = 1,        -- 2D section fit: 1 = standing (tall) , 2 = lying (deep) , 3 = as drawn
    handleLen  = 12.0,  -- length (cm) - used to extrude a PROFILE
    handleRot  = 0.0,   -- extra spin about the mounting axis (degrees)
    builtInH   = 0.0,   -- 0 = measure the section automatically ; >0 = manual override
    handleTop  = 4.0,   -- distance from the TOP edge of the door (cm)
    handleEdge = 4.0,   -- distance from the hinge-opposite EDGE of the door (cm)
    customDoor = false,
    customDoorW = 40.0,
    customDoorH = 70.0,
    handleFlipH = false,
    handleFlipV = false,
    golaAlign = 1,
    handleType = 1,
    headlessMaterial = 1,
    headlessDepth = 2.6,
    headlessHeight = 5.7,
    headlessGap = 3.0,
    golaBetweenSides = 1,
    golaDrop = 1
)

global PKD_State    = PKD_Params()
global PKD_CurPanel = 1


-------------------------------------------------------------------------------
-- 2. LOW LEVEL HELPERS
-------------------------------------------------------------------------------
fn PKD_CalcScale =
(
    local s = 1.0
    try ( s = units.decodeValue "1cm" ) catch ( s = 1.0 )
    if s == undefined or s <= 0 do s = 1.0
    s
)

fn PKD_Mat nm col rough met =
(
    local m = undefined
    for x in sceneMaterials while m == undefined do ( if x.name == nm do m = x )
    if m == undefined do
    (
        try ( m = PhysicalMaterial name:nm Base_Color:col roughness:rough metalness:met )
        catch ( m = StandardMaterial name:nm diffuse:col )
    )
    m
)

/*  2-slot Multi/Sub-Object material.
    Slot 1 = the two BIG faces of the panel   (white / red ...)
    Slot 2 = the four EDGE faces (the thickness / edge banding)
    Face IDs are assigned from the real face NORMALS, not from the Box's
    built-in ID order (which is not reliable across Max versions).        */
fn PKD_PanelMat nm faceCol edgeCol =
(
    local m = undefined
    for x in sceneMaterials while m == undefined do ( if x.name == nm do m = x )
    if m == undefined do
    (
        local fm = PKD_Mat (nm + "_Face") faceCol 0.5 0.0
        local em = PKD_Mat (nm + "_Edge") edgeCol 0.4 0.0
        m = MultiMaterial numsubs:2 name:nm
        m.materialList[1] = fm
        m.materialList[2] = em
    )
    m
)

/* Creates one panel. All args in CM. Stores logical cut-list dims as props. */
fn PKD_Part nm mat dx dy dz px py pz role:"PANEL" grain:"L" matLabel:"" band:0.0 bandCode:"-" hw:"" =
(
    local s = PKD_SCALE
    local b = Box width:(dx * s) length:(dy * s) height:(dz * s) lengthsegs:1 widthsegs:1 heightsegs:1
    b.pos  = [ (px + dx / 2.0) * s, (py + dy / 2.0) * s, pz * s ]
    b.name = nm
    b.material = mat

    if role == "PANEL" do
    (
        -- thickness axis = the smallest dimension
        local ax = if (dx <= dy and dx <= dz) then 1 else (if dy <= dz then 2 else 3)
        b = convertToPoly b
        local nf = polyop.getNumFaces b
        for f = 1 to nf do
        (
            local n = polyop.getFaceNormal b f
            local isBigFace = case ax of
            (
                1: ((abs n.x) > 0.7)
                2: ((abs n.y) > 0.7)
                default: ((abs n.z) > 0.7)
            )
            polyop.setFaceMatID b f (if isBigFace then 1 else 2)
        )
    )

    local d = #(dx, dy, dz)
    sort d
    setUserProp b "pkdRole"  role
    setUserProp b "pkdT"     d[1]
    setUserProp b "pkdW"     d[2]
    setUserProp b "pkdL"     d[3]
    setUserProp b "pkdGrain" grain
    setUserProp b "pkdMatName" (if matLabel == "" then mat.name else matLabel)
    setUserProp b "pkdBand"     band        -- banded edge length per piece, in CM
    setUserProp b "pkdBandCode" bandCode
    if hw != "" do setUserProp b "pkdHw" hw
    b
)

fn PKD_CutGroove panelObj dx dy dz px py pz =
(
    if panelObj == undefined do return undefined
    if dx < 0.01 or dy < 0.01 or dz < 0.01 do return panelObj
    local s = PKD_SCALE
    local cutter = undefined
    try
    (
        cutter = Box width:(dx * s) length:(dy * s) height:(dz * s) lengthsegs:1 widthsegs:1 heightsegs:1
        cutter.pos = [ (px + dx / 2.0) * s, (py + dy / 2.0) * s, pz * s ]
        cutter = convertToPoly cutter
        local ncf = polyop.getNumFaces cutter
        for f = 1 to ncf do polyop.setFaceMatID cutter f 1
        
        if classOf panelObj != Editable_Poly do convertToPoly panelObj
        ProBoolean.CreateBooleanObjects panelObj #(cutter) 2 0 0
        convertToPoly panelObj
    )
    catch
    (
        try (delete cutter) catch ()
    )
    panelObj
)

/*  Assigns face IDs on an already-poly object.
    axis: 1 = X , 2 = Y , 3 = Z  (object space thickness direction)          */
fn PKD_SetPanelIDs obj axis =
(
    local nf = polyop.getNumFaces obj
    for f = 1 to nf do
    (
        local n = polyop.getFaceNormal obj f
        local isBig = case axis of
        (
            1: ((abs n.x) > 0.7)
            2: ((abs n.y) > 0.7)
            default: ((abs n.z) > 0.7)
        )
        polyop.setFaceMatID obj f (if isBig then 1 else 2)
    )
)

/*  Builds a vertical panel of depth Ymax and height H with NOTCHES cut out of
    its TOP edge, then places it at world X = px, Y = 0, Z = pz with thickness
    thk along world X.  notches = array of #(u0, u1, depth).
    Falls back to a plain box if anything goes wrong.                        */
fn PKD_NotchedPanel nm mat thk Ymax H px pz notches matLabel:"" band:0.0 bandCode:"F" =
(
    local s = PKD_SCALE
    local obj = undefined
    try
    (
        -- step 1 : collect the u breakpoints
        local bs = #(0.0, Ymax)
        for n in notches do
        (
            local a = amax 0.0 (amin Ymax n[1])
            local b = amax 0.0 (amin Ymax n[2])
            appendIfUnique bs a
            appendIfUnique bs b
        )
        sort bs

        -- step 2 : height of every sub-interval
        local iv = #()
        for k = 1 to (bs.count - 1) do
        (
            local a = bs[k], b = bs[k+1]
            if (b - a) > 0.01 do
            (
                local mid = (a + b) / 2.0
                local hh = H
                for n in notches do
                    if mid > n[1] and mid < n[2] do hh = amin hh (H - n[3])
                if hh < 0.5 do hh = 0.5
                append iv #(a, b, hh)
            )
        )
        if iv.count == 0 do throw "empty profile"

        -- step 3 : outline points  , u = depth , v = height
        local pts = #()
        append pts [0.0, 0.0]
        append pts [0.0, iv[1][3]]
        for k = 1 to iv.count do
        (
            append pts [iv[k][2], iv[k][3]]
            if k < iv.count do append pts [iv[k][2], iv[k+1][3]]
        )
        append pts [Ymax, 0.0]

        -- step 4 : spline -> extrude -> poly
        local sh = SplineShape()
        addNewSpline sh
        for pt in pts do addKnot sh 1 #corner #line [pt[1] * s, pt[2] * s, 0]
        close sh 1
        updateShape sh
        addModifier sh (Extrude amount:(thk * s) capStart:true capEnd:true)
        obj = convertToPoly sh
        PKD_SetPanelIDs obj 3                       -- thickness = local Z
        obj.transform = (matrix3 [0,1,0] [0,0,1] [1,0,0] [px * s, 0, pz * s])
    )
    catch
    (
        try (delete obj) catch ()
        obj = undefined
    )

    if obj == undefined do
        return (PKD_Part nm mat thk Ymax H px 0 pz matLabel:matLabel band:band bandCode:bandCode)

    obj.name = nm
    obj.material = mat
    local d = #(thk, Ymax, H)
    sort d
    setUserProp obj "pkdRole"  "PANEL"
    setUserProp obj "pkdT"     d[1]
    setUserProp obj "pkdW"     d[2]
    setUserProp obj "pkdL"     d[3]
    setUserProp obj "pkdGrain" "L"
    setUserProp obj "pkdMatName" (if matLabel == "" then mat.name else matLabel)
    setUserProp obj "pkdBand"     band
    setUserProp obj "pkdBandCode" bandCode
    obj
)

-------------------------------------------------------------------------------
--  HANDLE LIBRARY
--  Entries live in an INI next to the user scripts, and the geometry itself is
--  kept as a .max file inside a PKD_Handles folder, so the library survives
--  between sessions and between scenes.
--
--  MODELLING CONVENTION (the importer auto-corrects most of it):
--    * the LONGEST axis of the model is treated as the handle length
--    * the side of the model facing +Y is the face that touches the door
--    * a 2D shape (spline) is treated as a PROFILE and gets extruded to length
-------------------------------------------------------------------------------
global PKD_HandleIni = (getDir #userScripts) + "\\PKD_HandleLib.ini"
global PKD_HandleDir = (getDir #userScripts) + "\\PKD_Handles\\"

fn PKD_HandleNames =
(
    local res = #()
    try ( if doesFileExist PKD_HandleIni do res = getINISetting PKD_HandleIni ) catch ( res = #() )
    if res == undefined do res = #()
    res
)

fn PKD_HandleInfo nm =
(
    if nm == "" do return undefined
    local fp = ""
    local kd = "MODEL"
    try ( fp = getINISetting PKD_HandleIni nm "path" ) catch ()
    try ( kd = getINISetting PKD_HandleIni nm "kind" ) catch ()
    if fp == "" or fp == undefined do return undefined
    if not (doesFileExist fp) do return undefined
    if kd == "" or kd == undefined do kd = "MODEL"
    #(fp, kd)
)

fn PKD_HandleAddFromScene =
(
    local sel = selection as array
    if sel.count == 0 do
    ( messagebox "حدد المقبض (أو القطاع) في المشهد أولاً." title:"تنبيه"; return undefined )

    local nm = sel[1].name
    local kd = if superClassOf sel[1] == shape then "PROFILE" else "MODEL"
    try ( makeDir PKD_HandleDir all:true ) catch ()
    local fp = PKD_HandleDir + nm + ".max"
    local ok = false
    try ( ok = saveNodes sel fp quiet:true ) catch ( ok = false )
    if not ok do ( messagebox "فشل حفظ المقبض في المكتبة." title:"خطأ"; return undefined )
    setINISetting PKD_HandleIni nm "path" fp
    setINISetting PKD_HandleIni nm "kind" kd
    nm
)

fn PKD_HandleAddFromDisk =
(
    local src = getOpenFileName caption:"اختر ملف المقبض" types:"Max Files (*.max)|*.max|"
    if src == undefined do return undefined
    try ( makeDir PKD_HandleDir all:true ) catch ()
    local nm = getFilenameFile src
    local fp = PKD_HandleDir + nm + ".max"
    if src != fp do ( try ( copyFile src fp ) catch ( fp = src ) )
    setINISetting PKD_HandleIni nm "path" fp
    setINISetting PKD_HandleIni nm "kind" "AUTO"
    nm
)

fn PKD_HandleDelete nm =
(
    if nm == "" do return false
    try ( delIniSetting PKD_HandleIni nm ) catch ()
    true
)

/*  Merges the library entry once and returns a single node to clone from.  */
fn PKD_HandleTemplate nm =
(
    local inf = PKD_HandleInfo nm
    if inf == undefined do return undefined
    local before = #()
    for o in objects do append before o
    local ok = false
    try ( ok = mergeMAXFile inf[1] #select #useSceneMtlDups #neverReparent quiet:true )
    catch ( ok = false )
    if not ok do return undefined

    local merged = #()
    for o in objects do ( if (findItem before o) == 0 do append merged o )
    if merged.count == 0 do return undefined

    local base = merged[1]
    if merged.count > 1 do
    (
        if superClassOf base == GeometryClass then
        (
            try
            (
                base = convertToPoly base
                for i = merged.count to 2 by -1 do ( try ( polyop.attach base merged[i] ) catch () )
            ) catch ()
        )
        else for i = 2 to merged.count do ( try ( delete merged[i] ) catch () )
    )
    base
)

fn PKD_AxisOf obj =
(
    local d = obj.max - obj.min
    if d.x >= d.y and d.x >= d.z then 1 else (if d.y >= d.z then 2 else 3)
)

/*  Spins an object so that its local Z (the extrusion direction) points along
    world +X, while keeping world +Z as "up" as the maths allows.
    Self-correcting: if the first guess turns the wrong way it flips back.   */
fn PKD_AlignExtrusionToX obj =
(
    local zd = normalize obj.transform.row3
    local d  = dot zd [1,0,0]
    if d > 0.999 do return true
    if d < -1.0 do d = -1.0
    if d >  1.0 do d =  1.0
    local axv = cross zd [1,0,0]
    if (length axv) < 0.0001 then axv = [0,0,1] else axv = normalize axv
    local ang = acos d
    rotate obj (quat ang axv)
    if (dot (normalize obj.transform.row3) [1,0,0]) < 0.999 do
        rotate obj (quat (-2.0 * ang) axv)
    true
)

fn PKD_AxisRot fromA toA =
(
    if fromA == toA do return (matrix3 1)
    if fromA == 1 and toA == 3 do return (rotateYMatrix -90)
    if fromA == 3 and toA == 1 do return (rotateYMatrix 90)
    if fromA == 2 and toA == 3 do return (rotateXMatrix 90)
    if fromA == 3 and toA == 2 do return (rotateXMatrix -90)
    if fromA == 2 and toA == 1 do return (rotateZMatrix -90)
    if fromA == 1 and toA == 2 do return (rotateZMatrix 90)
    matrix3 1
)

/*  Extrudes a throw-away copy of the section, orients it exactly the way the
    real handle will be oriented, measures its HEIGHT, then deletes it.
    This is what the door must be shortened by - guessing a number instead is
    what leaves a gap between the door and the handle.
    Returns the height in CM.                                                */
fn PKD_GolaProbe tmpl rotDeg =
(
    local h = undefined
    local res = #(0.0, 0.0)          -- #(height cm, depth cm)
    try
    (
        h = copy tmpl
        addModifier h (Extrude amount:1.0 capStart:true capEnd:true)
        h = convertToPoly h
        PKD_AlignExtrusionToX h
        if rotDeg != 0.0 do rotate h (quat rotDeg [1,0,0])
        res = #( (h.max.z - h.min.z) / PKD_SCALE, (h.max.y - h.min.y) / PKD_SCALE )
    )
    catch ( res = #(0.0, 0.0) )
    try ( if h != undefined do delete h ) catch ()
    res
)

/*  Works out the extra 90 degree kick the section needs so that it stands the
    way the user asked, then reports the final height.
    Returns #(totalRotation, heightCm).                                       */
fn PKD_GolaFit tmpl baseRot fitMode =
(
    local extra = 0.0
    local pr = PKD_GolaProbe tmpl baseRot
    if fitMode == 1 and pr[1] < pr[2] do extra = 90.0      -- standing: height must be the bigger one
    if fitMode == 2 and pr[1] > pr[2] do extra = 90.0      -- lying:    depth must be the bigger one
    local total = baseRot + extra
    if extra != 0.0 do pr = PKD_GolaProbe tmpl total
    #(total, pr[1])
)

/*  Seats a 2D section on the TOP EDGE of a door as a built-in (gola) handle.
    It is extruded to the exact door width, its front is flush with the door
    front, and its underside rests on the (already shortened) door top.       */
fn PKD_PlaceGola tmpl widthSys rotDeg leftX frontY topZ nm libName doorT:1.8 golaAlign:1 handleFlipH:false handleFlipV:false =
(
    local h = undefined
    local isProfile = (superClassOf tmpl == shape)
    try
    (
        h = copy tmpl
        if isProfile then
        (
            addModifier h (Extrude amount:widthSys capStart:true capEnd:true)
            h = convertToPoly h
            if handleFlipH do
            (
                local m1 = Mirror axis:1
                addModifier h m1
                h = convertToPoly h
            )
            if handleFlipV do
            (
                local m2 = Mirror axis:2
                addModifier h m2
                h = convertToPoly h
            )
            PKD_AlignExtrusionToX h
            if rotDeg != 0.0 do rotate h (quat rotDeg [1,0,0])
        )
        else
        (
            -- 3D Mesh / Group mode: scale along its longest axis to match widthSys
            local axis = PKD_AxisOf h
            local currentLen = if axis == 1 then (h.max.x - h.min.x) else (if axis == 2 then (h.max.y - h.min.y) else (h.max.z - h.min.z))
            if currentLen > 0.001 do
            (
                local scaleFactor = widthSys / currentLen
                if axis == 1 then h.scale = h.scale * [scaleFactor, 1.0, 1.0]                 else if axis == 2 then h.scale = h.scale * [1.0, scaleFactor, 1.0]                 else h.scale = h.scale * [1.0, 1.0, scaleFactor]
            )
            if handleFlipH do
            (
                local m1 = Mirror axis:1
                addModifier h m1
            )
            if handleFlipV do
            (
                local m2 = Mirror axis:2
                addModifier h m2
            )
        )
    )
    catch ( return undefined )
    if h == undefined do return undefined

    local bmin = h.min, bmax = h.max
    local s = PKD_SCALE
    local dlt = [0, 0, 0]
    dlt.x = leftX  - bmin.x
    if golaAlign == 2 then
        dlt.y = (frontY + doorT * s) - bmax.y  -- Back Flush (extends forward)
    else
        dlt.y = frontY - bmin.y                -- Front Flush (extends backward)
    dlt.z = topZ   - bmin.z
    h.pos = h.pos + dlt

    h.name = nm
    setUserProp h "pkdRole" "HARDWARE"
    setUserProp h "pkdHw" "HANDLE"
    setUserProp h "pkdHwName" libName
    h
)
fn PKD_PlaceHandle tmpl isProfile isVert lenSys rotDeg faceY topZ edgeX rightSide nm libName asIs:false =
(
    local h = undefined
    try
    (
        if isProfile then
        (
            h = copy tmpl
            addModifier h (Extrude amount:lenSys capStart:true capEnd:true)
            h = convertToPoly h
        )
        else h = instance tmpl
    )
    catch ( return undefined )
    if h == undefined do return undefined

    if asIs then
    (
        -- keep whatever orientation the model was built in
        if rotDeg != 0.0 do rotate h (quat rotDeg [0,1,0])
    )
    else
    (
        -- auto: treat the longest axis as the handle length
        local srcAxis = if isProfile then 3 else (PKD_AxisOf tmpl)
        local tgtAxis = if isVert then 3 else 1
        h.transform = (PKD_AxisRot srcAxis tgtAxis) * (rotateYMatrix rotDeg)
    )

    -- snap: mounting face on the door, then top / edge alignment
    local bmin = h.min, bmax = h.max
    local ctr  = (bmin + bmax) / 2.0
    local dlt  = [0, 0, 0]
    dlt.y = faceY - bmax.y
    dlt.z = topZ  - bmax.z
    if isVert then
        dlt.x = if rightSide then (edgeX - bmax.x) else (edgeX - bmin.x)
    else
        dlt.x = edgeX - ctr.x
    h.pos = h.pos + dlt

    h.name = nm
    setUserProp h "pkdRole" "HARDWARE"
    setUserProp h "pkdHw" "HANDLE"
    setUserProp h "pkdHwName" libName
    h
)

fn PKD_Leg nm mat cx cy h r legName:"" =
(
    local s = PKD_SCALE
    local c = Cylinder radius:(r * s) height:(h * s) sides:20
    c.pos  = [ cx * s, cy * s, 0 ]
    c.name = nm
    c.material = mat
    setUserProp c "pkdRole" "HARDWARE"
    setUserProp c "pkdHw" "LEG"
    setUserProp c "pkdHwName" legName
    c
)

fn PKD_CollectNodes node arr =
(
    append arr node
    for c in node.children do PKD_CollectNodes c arr
)

/* Finds the unit group head starting from any selected sub-object */
fn PKD_GetHead node =
(
    if node == undefined do return undefined
    local curr = node
    local top  = undefined
    if (getUserProp curr "pkdUnit") != undefined do top = curr
    while curr.parent != undefined do
    (
        curr = curr.parent
        if (getUserProp curr "pkdUnit") != undefined do top = curr
    )
    top
)

fn PKD_Q s = "\"" + (substituteString (s as string) "\"" "\"\"") + "\""


-------------------------------------------------------------------------------
-- 3. PROPERTY I/O  (struct  <->  node userProps)
-------------------------------------------------------------------------------
fn PKD_SaveProps node p =
(
    setUserProp node "pkdUnit" 1
    setUserProp node "uW" p.W;             setUserProp node "uH" p.H
    setUserProp node "uD" p.D;             setUserProp node "uT" p.t
    setUserProp node "uTB" p.tb
    setUserProp node "uTopMode" p.topMode; setUserProp node "uFullTopType" p.fullTopType
    setUserProp node "uStretch" p.stretch; setUserProp node "uFDir" p.fDir
    setUserProp node "uBDir" p.bDir
    setUserProp node "uBackMode" p.backMode
    setUserProp node "uFrontStSet" p.frontStSet
    setUserProp node "uBackStPos" p.backStPos
    setUserProp node "uPartMode" p.partMode
    setUserProp node "uLegName" p.legName
    setUserProp node "uGroove" p.grooveDepth
    setUserProp node "uSetback" p.setback
    setUserProp node "uLegH" p.legH;       setUserProp node "uShelves" p.shelves
    setUserProp node "uShelfD" p.shelfD;   setUserProp node "uShelfClear" p.shelfClear
    setUserProp node "uPartActive" p.partActive
    setUserProp node "uPartCount" p.partCount
    setUserProp node "uPartPos" p.partPos
    setUserProp node "uDoorType" p.doorType
    setUserProp node "uDoors" p.doors
    setUserProp node "uDoorGap" p.doorGap
    setUserProp node "uDoorThick" p.doorThick
    setUserProp node "uHingeSide" p.hingeSide
    setUserProp node "uBuiltInH"   p.builtInH
    setUserProp node "uHandleKind" p.handleKind
    setUserProp node "uHandleLib"  (if p.handleLib == "" then "-" else p.handleLib)
    setUserProp node "uHandleAxis" p.handleAxis
    setUserProp node "uHandleAsIs" p.handleAsIs
    setUserProp node "uGolaFit"    p.golaFit
    setUserProp node "uHandleLen"  p.handleLen
    setUserProp node "uHandleRot"  p.handleRot
    setUserProp node "uHandleTop"  p.handleTop
    setUserProp node "uHandleEdge" p.handleEdge
    setUserProp node "uDoorSides" (if p.doorSides == "" then "-" else p.doorSides)
    setUserProp node "uUnitType"   p.unitType
    setUserProp node "uMatCarcass" p.matCarcass
    setUserProp node "uMatDoor"    p.matDoor
    setUserProp node "uMatBack"    p.matBack
    setUserProp node "uBandWidth"  p.bandWidth
    setUserProp node "uBandPrice"  p.bandPrice
    setUserProp node "uSheetL"     p.sheetL
    setUserProp node "uSheetW"     p.sheetW
    setUserProp node "uWaste"      p.waste
    setUserProp node "uSheetPrice" p.sheetPrice
    setUserProp node "uCustomDoor" p.customDoor
    setUserProp node "uCustomDoorW" p.customDoorW
    setUserProp node "uCustomDoorH" p.customDoorH
    setUserProp node "uHandleFlipH" p.handleFlipH
    setUserProp node "uHandleFlipV" p.handleFlipV
    setUserProp node "uGolaAlign" p.golaAlign
    setUserProp node "uHandleType" p.handleType
    setUserProp node "uHeadlessMaterial" p.headlessMaterial
    setUserProp node "uHeadlessDepth" p.headlessDepth
    setUserProp node "uHeadlessHeight" p.headlessHeight
    setUserProp node "uHeadlessGap" p.headlessGap
)

fn PKD_LoadProps node =
(
    local p = PKD_Params()
    fn gf n k dv = ( local v = getUserProp n k; if v == undefined then dv else (try (v as float) catch dv) )
    fn gi n k dv = ( local v = getUserProp n k; if v == undefined then dv else (try (v as integer) catch dv) )
    fn gb n k dv = ( local v = getUserProp n k; if v == undefined then dv else ((v as string) == "true") )

    p.W = gf node "uW" p.W;   p.H = gf node "uH" p.H;   p.D = gf node "uD" p.D
    p.t = gf node "uT" p.t;   p.tb = gf node "uTB" p.tb
    p.topMode = gi node "uTopMode" p.topMode
    p.fullTopType = gi node "uFullTopType" p.fullTopType
    p.stretch = gf node "uStretch" p.stretch
    p.fDir = gi node "uFDir" p.fDir;  p.bDir = gi node "uBDir" p.bDir
    p.backMode = gi node "uBackMode" p.backMode
    p.frontStSet = gf node "uFrontStSet" p.frontStSet
    p.backStPos = gi node "uBackStPos" p.backStPos
    p.partMode = gi node "uPartMode" p.partMode
    p.grooveDepth = gf node "uGroove" p.grooveDepth
    p.setback = gf node "uSetback" p.setback
    p.legH = gf node "uLegH" p.legH
    p.shelves = gi node "uShelves" p.shelves
    p.shelfD = gf node "uShelfD" p.shelfD
    p.shelfClear = gf node "uShelfClear" p.shelfClear
    p.partActive = gb node "uPartActive" p.partActive
    p.partCount = gi node "uPartCount" p.partCount
    p.partPos = gi node "uPartPos" p.partPos
    p.doorType = gi node "uDoorType" p.doorType
    p.doors = gi node "uDoors" p.doors
    p.doorGap = gf node "uDoorGap" p.doorGap
    if p.doorGap < 0.5 and p.doorGap > 0.0 do p.doorGap = p.doorGap * 10.0   -- migrate old cm value
    p.doorThick = gf node "uDoorThick" p.doorThick
    p.hingeSide = gi node "uHingeSide" p.hingeSide
    p.builtInH   = gf node "uBuiltInH"   p.builtInH
    p.handleKind = gi node "uHandleKind" p.handleKind
    p.handleAxis = gi node "uHandleAxis" p.handleAxis
    p.handleAsIs = gb node "uHandleAsIs" p.handleAsIs
    p.golaFit    = gi node "uGolaFit"    p.golaFit
    p.handleLen  = gf node "uHandleLen"  p.handleLen
    p.handleRot  = gf node "uHandleRot"  p.handleRot
    p.handleTop  = gf node "uHandleTop"  p.handleTop
    p.handleEdge = gf node "uHandleEdge" p.handleEdge
    local ds = getUserProp node "uDoorSides"
    p.doorSides = if ds == undefined or (ds as string) == "-" then "" else (ds as string)

    fn gs n k dv = ( local v = getUserProp n k; if v == undefined then dv else (v as string) )
    p.unitType   = gi node "uUnitType" p.unitType
    p.matCarcass = gs node "uMatCarcass" p.matCarcass
    p.matDoor    = gs node "uMatDoor"    p.matDoor
    p.matBack    = gs node "uMatBack"    p.matBack
    p.legName    = gs node "uLegName"    p.legName
    local hl = gs node "uHandleLib" "-"
    p.handleLib = if hl == "-" then "" else hl
    p.bandWidth  = gf node "uBandWidth"  p.bandWidth
    p.bandPrice  = gf node "uBandPrice"  p.bandPrice
    p.sheetL     = gf node "uSheetL"     p.sheetL
    p.sheetW     = gf node "uSheetW"     p.sheetW
    p.waste      = gf node "uWaste"      p.waste
    p.sheetPrice = gf node "uSheetPrice" p.sheetPrice
    p.customDoor = gb node "uCustomDoor" p.customDoor
    p.customDoorW = gf node "uCustomDoorW" p.customDoorW
    p.customDoorH = gf node "uCustomDoorH" p.customDoorH
    p.handleFlipH = gb node "uHandleFlipH" p.handleFlipH
    p.handleFlipV = gb node "uHandleFlipV" p.handleFlipV
    p.golaAlign = gi node "uGolaAlign" p.golaAlign
    p.handleType = gi node "uHandleType" p.handleType
    p.headlessMaterial = gi node "uHeadlessMaterial" p.headlessMaterial
    p.headlessDepth = gf node "uHeadlessDepth" p.headlessDepth
    p.headlessHeight = gf node "uHeadlessHeight" p.headlessHeight
    p.headlessGap = gf node "uHeadlessGap" p.headlessGap
    p.golaBetweenSides = gi node "uGolaBetween" p.golaBetweenSides
    p.golaDrop = gi node "uGolaDrop" p.golaDrop
    p
)


-------------------------------------------------------------------------------
-- 4. THE BUILDER  (pure logic - takes a struct, returns a group)
-------------------------------------------------------------------------------
fn PKD_Build p oldGroup:undefined =
(
    local wasIsolated = false
    try ( wasIsolated = IsolateSelection.IsolateSelectionModeActive() ) catch ( wasIsolated = false )
    if wasIsolated do
    (
        try ( IsolateSelection.ExitIsolateSelectionMode() ) catch ()
    )
    local oldPanelMode = getCommandPanelTaskMode()
    setCommandPanelTaskMode #create
    PKD_SCALE = PKD_CalcScale()

    local W = p.W, H = p.H, D = p.D, t = p.t, tb = p.tb
    local carcassD = D
    local doorT = p.doorThick, doorGap = p.doorGap / 10.0   -- mm -> cm

    ---------------------------------------------------------------- validation
    local err = undefined
    if W <= (2 * t + 2)            do err = "العرض صغير جداً بالنسبة لسمك الجنب."
    if D <= (tb + 5)               do err = "العمق صغير جداً."
    if H <= 10                     do err = "الارتفاع صغير جداً."
    if p.topMode == 2 and H <= (p.stretch + t + 2) do err = "الارتفاع لا يكفي لعرض الشداد."
    if p.backMode == 2 and (D - p.setback - tb) <= (t + 2) do err = "مسافة الرجوع كبيرة بالنسبة للعمق."
    if err != undefined do ( messagebox err title:"مقاسات غير منطقية"; return undefined )

    ---------------------------------------------------------- base transform
    -- Preserve the old unit's placement (position + rotation) exactly,
    -- even if the user moved the group after it was created.
    local baseTM = matrix3 1
    if oldGroup != undefined do
    (
        try
        (
            local sb = getUserProp oldGroup "pkdBaseTM"
            local sg = getUserProp oldGroup "pkdGrpTM"
            if sb != undefined and sg != undefined do
            (
                local b  = execute (sb as string)
                local g0 = execute (sg as string)
                if classof b == Matrix3 and classof g0 == Matrix3 do
                    baseTM = b * (inverse g0) * oldGroup.transform
            )
        )
        catch ( baseTM = matrix3 1 )
        
        -- Delete the old unit immediately to keep the scene clean and speed up calculations
        local dead = #()
        PKD_CollectNodes oldGroup dead
        delete dead
    )

    ------------------------------------------------------------------ materials
    -- Chassis (sides / base / shelves / partitions) : WHITE face , BLUE edges
    local mInt    = PKD_PanelMat "PKD_Chassis" (color 245 245 245) (color  30  90 210)
    -- Stretchers / full top                          : WHITE face , PURPLE edges
    local mTop    = PKD_PanelMat "PKD_TopSys"  (color 245 245 245) (color 140  55 195)
    -- Doors                                          : RED face   , YELLOW edges (all 4)
    local mDoor   = PKD_PanelMat "PKD_Door"    (color 190  30  30) (color 240 205  40)
    -- Back panel (8mm, not edge-banded)              : LIGHT GREEN, flat
    local mBack   = PKD_Mat "PKD_Back"         (color 10 10 10) 0.6 0.0
    local mLeg    = PKD_Mat "PKD_PVC_Leg"      (color  15  15  15) 0.6 0.0
    local mHandle = PKD_Mat "PKD_Metal_Handle" (color  80  80  80) 0.3 1.0

    local parts = #()

    ------------------------------------------------------------------ carcass Z
    local baseZMin   = p.legH                 -- underside of the sides
    local fTopZ      = p.legH + H             -- overall top of the carcass
    local golaTopZ   = if p.golaDrop == 2 then (fTopZ - t) else fTopZ
    local panelsTopZ = fTopZ                  -- top of the SIDE panels
    if p.topMode == 1 and p.fullTopType == 2 do panelsTopZ = fTopZ - t
    local sideH = panelsTopZ - baseZMin

    local fStD = 0.0, fStH = 0.0, bStD = 0.0, bStH = 0.0
    if p.topMode == 2 do
    (
        if p.fDir == 1 then ( fStD = p.stretch; fStH = t ) else ( fStD = t; fStH = p.stretch )
        if p.bDir == 1 then ( bStD = p.stretch; bStH = t ) else ( bStD = t; bStH = p.stretch )
    )
    local usableTop = if p.topMode == 2 then (fTopZ - (amax fStH bStH)) else (fTopZ - t)
    local usableBottom = baseZMin + t

    local backBottomZ = usableBottom
    if p.backMode == 2 do backBottomZ = usableBottom - p.grooveDepth
    if p.backMode == 1 do backBottomZ = baseZMin
    
    local backTopZ    = panelsTopZ
    if p.topMode == 1 do
    (
        backTopZ = fTopZ - t
        if p.backMode == 2 do backTopZ = (fTopZ - t) + p.grooveDepth
    )
    if p.topMode == 2 do
    (
        case p.backStPos of
        (
            1: (
                if p.bDir == 2 then (
                    backTopZ = panelsTopZ
                ) else (
                    backTopZ = if p.backMode == 2 then ((fTopZ - bStH) + p.grooveDepth) else (fTopZ - bStH)
                )
            )
            default: backTopZ = panelsTopZ
        )
        if backTopZ > panelsTopZ do backTopZ = panelsTopZ
    )

    local overlapY = 0.0
    local golaH = 0.0
    local hasGola = false
    local isGolaProfile = false
    local hTmpl = undefined, hIsProfile = false, golaRot = 0.0
    local hTmplGlobal = undefined
    
    local actualBIH = 0.0
    local actualSetback = p.frontStSet

    local doorGap = p.doorGap / 10.0
    local dzMin = 0.0, dzMax = 0.0
    case p.doorType of
    (
        1: (
                dzMin = usableBottom + doorGap
                dzMax = usableTop - doorGap
           )
        2: (
                local ov = t / 2.0
                dzMin = baseZMin + ov + doorGap; dzMax = fTopZ - ov - doorGap
           )
        default: (
                dzMin = baseZMin + doorGap;     dzMax = fTopZ - doorGap
           )
    )

    local isGolaActive = (p.handleType == 3 and p.handleKind == 2 and p.handleLib != "")
    if p.handleType == 3 then
    (
        actualBIH = p.headlessHeight
        overlapY = p.headlessDepth
        
        if p.handleKind == 2 and p.handleLib != "" do
        (
            hTmpl = PKD_HandleTemplate p.handleLib
            if hTmpl != undefined then
            (
                hIsProfile = (superClassOf hTmpl == shape)
                hTmplGlobal = hTmpl
                isGolaProfile = true
                if hIsProfile then
                (
                    hasGola = true
                    local baseRot = p.handleRot
                    local fit = PKD_GolaFit hTmpl baseRot p.golaFit
                    golaRot = fit[1]
                    actualBIH = if p.builtInH > 0.0 then p.builtInH else fit[2]
                    
                    local pr = PKD_GolaProbe hTmpl golaRot
                    overlapY = pr[2]
                )
                else
                (
                    -- 3D model/mesh or Group. Probe its bounding box.
                    local d = (hTmpl.max - hTmpl.min) / PKD_SCALE
                    local axis = PKD_AxisOf hTmpl
                    local hVal = 0.0, dVal = 0.0
                    case axis of
                    (
                        1: ( hVal = d.z; dVal = d.y )
                        2: ( hVal = d.z; dVal = d.x )
                        default: ( hVal = d.y; dVal = d.x )
                    )
                    actualBIH = if hVal > 0.1 then hVal else p.headlessHeight
                    overlapY = if dVal > 0.1 then dVal else p.headlessDepth
                    golaRot = 0.0
                )
            )
        )
        if isGolaActive and p.golaDrop == 1 do actualSetback = amax actualSetback p.headlessDepth
    )
    else if p.handleType == 2 then
    (
        if p.handleKind == 2 and p.handleLib != "" do
        (
            hTmpl = PKD_HandleTemplate p.handleLib
            if hTmpl != undefined then
            (
                hIsProfile = (superClassOf hTmpl == shape)
                hTmplGlobal = hTmpl
                if hIsProfile do
                (
                    hasGola = true
                    isGolaProfile = true
                    local baseRot = p.handleRot
                    local fit = PKD_GolaFit hTmpl baseRot p.golaFit
                    golaRot = fit[1]
                    actualBIH = if p.builtInH > 0.0 then p.builtInH else fit[2]
                )
            )
        )
    )
    
    
    local doorH = dzMax - dzMin
    if p.handleType == 2 do actualBIH = amax 0.0 (amin (doorH - 5.0) actualBIH)

    ------------------------------------------------------------------ back plane
    local backFrontY = if p.backMode == 2 then (D - p.setback - tb) else D

    ------------------------------------------------------------------ sides+base
    local mcName = p.matCarcass
    local leftSide = PKD_Part "Side_Left"  mInt t carcassD (sideH - t) 0       0 (baseZMin + t) \
                  matLabel:mcName band:(sideH - t) bandCode:"F"
    if p.backMode == 2 do
    (
        local grooveH = amax 0.0 (backTopZ - (baseZMin + t))
        leftSide = PKD_CutGroove leftSide p.grooveDepth p.tb grooveH (t - p.grooveDepth) (D - p.setback - p.tb) (baseZMin + t)
    )

    if p.handleType == 3 and isGolaActive and p.golaBetweenSides == 1 do
    (
        local notchH = if p.golaDrop == 2 then p.headlessHeight else (p.headlessHeight + 0.1)
        leftSide = PKD_CutGroove leftSide (t + 0.2) (p.headlessDepth + 0.05) notchH -0.1 -0.05 (golaTopZ - p.headlessHeight)
    )
    append parts leftSide

    local rightSide = PKD_Part "Side_Right" mInt t carcassD (sideH - t) (W - t) 0 (baseZMin + t) \
                   matLabel:mcName band:(sideH - t) bandCode:"F"
    if p.backMode == 2 do
    (
        local grooveH = amax 0.0 (backTopZ - (baseZMin + t))
        rightSide = PKD_CutGroove rightSide p.grooveDepth p.tb grooveH (W - t) (D - p.setback - p.tb) (baseZMin + t)
    )

    if p.handleType == 3 and isGolaActive and p.golaBetweenSides == 1 do
    (
        local notchH = if p.golaDrop == 2 then p.headlessHeight else (p.headlessHeight + 0.1)
        rightSide = PKD_CutGroove rightSide (t + 0.2) (p.headlessDepth + 0.05) notchH (W - t - 0.1) -0.05 (golaTopZ - p.headlessHeight)
    )
    append parts rightSide

    local basePanel = PKD_Part "Base"       mInt W carcassD t   0 0 baseZMin \
                  matLabel:mcName band:W bandCode:"F"
    if p.backMode == 2 do
        basePanel = PKD_CutGroove basePanel (W - 2*t + 2*p.grooveDepth) p.tb p.grooveDepth (t - p.grooveDepth) (D - p.setback - p.tb) (baseZMin + t - p.grooveDepth)
    append parts basePanel

    ------------------------------------------------------------------ top system
    local fsb = 0.0, bsY = 0.0

    if p.topMode == 2 then
    (
        if p.fDir == 1 then ( fStD = p.stretch; fStH = t ) else ( fStD = t; fStH = p.stretch )
        if p.bDir == 1 then ( bStD = p.stretch; bStH = t ) else ( bStD = t; bStH = p.stretch )

        -- front stretcher may be pushed back (space for an aluminium built-in handle)
        fsb = actualSetback
        if fsb < 0.0 do fsb = 0.0
        if (fsb + fStD) > (backFrontY - 1.0) do fsb = amax 0.0 (backFrontY - fStD - 1.0)
        append parts (PKD_Part "Stretcher_Front" mTop (W - 2*t) fStD fStH t fsb (fTopZ - fStH) \
                      matLabel:p.matCarcass band:(W - 2*t) bandCode:"F")

        -- back stretcher position
        -- a VERTICAL stretcher cannot sit over the back panel -> use "in front of"
        local bsp = p.backStPos
        if p.bDir == 2 and bsp == 1 do bsp = 2
        case bsp of
        (
            2: bsY = backFrontY - bStD                 -- in front of the back panel, touching
            3: bsY = backFrontY + tb                   -- behind the back panel
            default: bsY = carcassD - bStD                    -- over the back panel (back inset 8mm)
        )
        if bsY < 0.0 do bsY = 0.0
        if (bsY + bStD) > carcassD do bsY = carcassD - bStD
        local backSt = PKD_Part "Stretcher_Back" mTop (W - 2*t) bStD bStH t bsY (fTopZ - bStH) \
                      matLabel:p.matCarcass band:0.0 bandCode:"-"
        if p.backMode == 2 and p.bDir == 1 and p.backStPos == 1 do
            backSt = PKD_CutGroove backSt (W - 2*t) p.tb p.grooveDepth t (D - p.setback - p.tb) (fTopZ - bStH)
        append parts backSt

        -- [FIX 01] clear BOTH stretchers, not just the front one
        usableTop = fTopZ - (amax fStH bStH)
    )
    else
    (
        local topFull = undefined
        if p.fullTopType == 2 then
            topFull = PKD_Part "Top_Full" mTop W (carcassD - actualSetback) t 0 actualSetback (fTopZ - t) \
                      matLabel:p.matCarcass band:W bandCode:"F"
        else
            topFull = PKD_Part "Top_Full" mTop (W - 2*t) (carcassD - actualSetback) t t actualSetback (fTopZ - t) \
                      matLabel:p.matCarcass band:(W - 2*t) bandCode:"F"
        
        if p.backMode == 2 and topFull != undefined do
        (
            local topW = if p.fullTopType == 2 then W else (W - 2*t)
            local topX = if p.fullTopType == 2 then 0 else t
            local grooveXMin = amax topX (t - p.grooveDepth)
            local grooveXMax = amin (topX + topW) (W - t + p.grooveDepth)
            local grooveW = grooveXMax - grooveXMin
            topFull = PKD_CutGroove topFull grooveW p.tb p.grooveDepth grooveXMin (D - p.setback - p.tb) (fTopZ - t)
        )
        if topFull != undefined do append parts topFull
        usableTop = fTopZ - t
    )
    
    -- usableBottom is pre-calculated
    if usableTop <= usableBottom + 2 do
    ( messagebox "الفراغ الداخلي صفر - راجع الارتفاع / عرض الشداد." title:"تنبيه"; delete parts; return undefined )

    ------------------------------------------------------------------ back panel
    -- [FIX 05] back sits ON the base and stops UNDER the top / back stretcher
    local backW = 0.0, backX = 0.0
    if p.backMode == 2 then ( backW = (W - 2*t) + (2 * p.grooveDepth); backX = t - p.grooveDepth )
    else if p.backMode == 1 then ( backW = W; backX = 0 )
    else                    ( backW = W - 2*t;                          backX = t )

    -- backBottomZ and backTopZ are pre-calculated at the top of the function
    local backH = backTopZ - backBottomZ
    if p.backMode == 1 do backH = H
    if backH > 0 do
        append parts (PKD_Part "Back_Panel" mBack backW tb backH backX backFrontY backBottomZ \
                      matLabel:p.matBack band:0.0 bandCode:"-")

    ------------------------------------------------------------------ door span
    local dxMin = 0.0, dxMax = 0.0, dzMin = 0.0, dzMax = 0.0, dyMin = 0.0
    case p.doorType of
    (
        1: (    -- Inset
                dxMin = t + doorGap;            dxMax = W - t - doorGap
                dzMin = usableBottom + doorGap
                dzMax = usableTop - doorGap     -- [FIX 03]
                dyMin = 0.0
           )
        2: (    -- Half Overlay
                local ov = t / 2.0
                dxMin = ov + doorGap;           dxMax = W - ov - doorGap
                dzMin = baseZMin + ov + doorGap; dzMax = fTopZ - ov - doorGap
                dyMin = -doorT
           )
        default: (  -- Full Overlay
                dxMin = doorGap;                dxMax = W - doorGap
                dzMin = baseZMin + doorGap;     dzMax = fTopZ - doorGap
                dyMin = -doorT
           )
    )
    
    local doorSpanW = dxMax - dxMin
    local doorH     = dzMax - dzMin
    local hTmplGlobal = undefined

    ------------------------------------------------------------------ partitions
    local partXs = #()
    if p.partActive do
    (
        local n = p.partCount
        if n < 1 do n = 1

        if p.doors > 1 then
        (
            -- align partitions with the gaps between doors
            if n > (p.doors - 1) do n = p.doors - 1
            local sDoorW = (doorSpanW - doorGap * (p.doors - 1)) / p.doors
            for i = 1 to n do
            (
                -- CONVENTION: "يمين / Right" = towards Side_Right = +X = high gap index
                local gapIdx = 1
                case p.partPos of
                (
                    2: gapIdx = p.doors - i              -- right  -> near Side_Right
                    3: gapIdx = i                        -- left   -> near Side_Left
                    default: (
                        gapIdx = ((p.doors / 2) as integer) + i - 1
                    )
                )
                if gapIdx < 1 do gapIdx = 1
                if gapIdx > (p.doors - 1) do gapIdx = p.doors - 1

                local gapCenter = dxMin + (gapIdx * sDoorW) + ((gapIdx - 1) * doorGap) + (doorGap / 2.0)
                appendIfUnique partXs (gapCenter - t / 2.0)
            )
        )
        else
        (
            -- no doors (or single door): distribute evenly across the inner width
            local innerW = W - 2 * t
            for i = 1 to n do
                appendIfUnique partXs (t + innerW * (i as float / (n + 1)) - t / 2.0)
        )

        -- clamp inside the carcass and sort
        for i = 1 to partXs.count do
        (
            if partXs[i] < (t + 1)         do partXs[i] = t + 1
            if partXs[i] > (W - 2*t - 1)   do partXs[i] = W - 2*t - 1
        )
        sort partXs

        /*  MODE 1 : partition stops flush under the top / stretchers.
            MODE 2 : partition is the FULL side height and gets a notch cut out
                     for every stretcher it runs into (front and back).        */
        local partH = if p.partMode == 2 then (panelsTopZ - usableBottom) else (usableTop - usableBottom)
        local hasGolaNotch = (p.handleType == 3 and isGolaActive and p.golaBetweenSides == 1)
        local golaNotchH = if hasGolaNotch then ((usableBottom + partH) - (golaTopZ - p.headlessHeight)) else 0.0
        local hasStretcherNotches = (p.partMode == 2 and p.topMode == 2)
        local useNotch = hasStretcherNotches or (hasGolaNotch and golaNotchH > 0.05)

        if useNotch then
        (
            local notches = #()
            -- Gola notch (only in Headless mode with notched sides)
            if hasGolaNotch and golaNotchH > 0.05 do
            (
                append notches #(0.0, p.headlessDepth, golaNotchH)
            )
            -- front stretcher notch (only if partMode == 2)
            if hasStretcherNotches and p.topMode == 2 do
                append notches #(fsb, fsb + fStD, fStH)
            -- back stretcher notch
            if hasStretcherNotches and p.topMode == 2 and bsY < backFrontY do
                append notches #(bsY, amin backFrontY (bsY + bStD), bStH)

            for i = 1 to partXs.count do
                append parts (PKD_NotchedPanel ("Partition_" + i as string) mInt t backFrontY partH \
                              partXs[i] usableBottom notches \
                              matLabel:p.matCarcass band:partH bandCode:"F")
        )
        else
        (
            for i = 1 to partXs.count do
                append parts (PKD_Part ("Partition_" + i as string) mInt t backFrontY partH partXs[i] 0 usableBottom \
                              matLabel:p.matCarcass band:partH bandCode:"F")
        )
    )

    ------------------------------------------------------------------ bays
    -- [FIX 02] shelves are generated per bay, not across the whole unit
    local bays = #()
    local cursor = t
    for x in partXs do ( append bays #(cursor, x); cursor = x + t )
    append bays #(cursor, W - t)

    ------------------------------------------------------------------ shelves
    if p.shelves > 0 do
    (
        -- [FIX 04] clamp shelf depth to what actually fits
        local shelfD = p.shelfD
        local maxD = backFrontY - 0.5
        if shelfD > maxD do shelfD = maxD
        if shelfD < 5.0  do shelfD = 5.0
        local shelfY = backFrontY - shelfD
        if shelfY < 0 do ( shelfY = 0; shelfD = backFrontY )

        local usableH = usableTop - usableBottom
        for b = 1 to bays.count do
        (
            local bw = bays[b][2] - bays[b][1] - p.shelfClear
            if bw > 1.0 do
            (
                local sx = bays[b][1] + p.shelfClear / 2.0
                for i = 1 to p.shelves do
                (
                    local cz = usableBottom + usableH * (i as float / (p.shelves + 1))
                    append parts (PKD_Part ("Shelf_B" + b as string + "_" + i as string) \
                                  mInt bw shelfD t sx shelfY (cz - t / 2.0) \
                                  matLabel:p.matCarcass band:bw bandCode:"F")
                )
            )
        )
    )

    if p.handleType == 3 and isGolaActive do
    (
        if p.golaBetweenSides == 2 then
        (
            for b = 1 to bays.count do
            (
                local golaX = bays[b][1]
                local golaW = bays[b][2] - bays[b][1]
                if p.handleKind == 2 then
                (
                    if hTmpl != undefined do
                    (
                        local gh = PKD_PlaceGola hTmpl (golaW * PKD_SCALE) golaRot \
                                   (golaX * PKD_SCALE) 0.0 ((golaTopZ - actualBIH) * PKD_SCALE) \
                                   ("Carcass_Gola_B" + b as string) p.handleLib doorT:0.0 golaAlign:1 \
                                   handleFlipH:p.handleFlipH handleFlipV:p.handleFlipV
                        if gh != undefined do append parts gh
                    )
                )
                else
                (
                    if p.headlessMaterial == 2 then
                    (
                        append parts (PKD_Part ("Gola_Wood_H_B" + b as string) mInt golaW overlapY t t golaX (golaTopZ - actualBIH) \
                                      matLabel:p.matCarcass band:golaW bandCode:"F")
                        if (actualBIH - t) > 0.1 do
                            append parts (PKD_Part ("Gola_Wood_V_B" + b as string) mInt golaW t (actualBIH - t) golaX (overlapY - t) (golaTopZ - actualBIH + t) \
                                          matLabel:p.matCarcass band:golaW bandCode:"F")
                    )
                    else
                    (
                        append parts (PKD_Part ("Carcass_Gola_B" + b as string) mHandle golaW overlapY actualBIH golaX 0 (golaTopZ - actualBIH) role:"HARDWARE" hw:"HANDLE")
                    )
                )
            )
        )
        else
        (
            local golaX = 0.0
            local golaW = W
            if p.handleKind == 2 then
            (
                if hTmpl != undefined do
                (
                    local gh = PKD_PlaceGola hTmpl (golaW * PKD_SCALE) golaRot \
                               (golaX * PKD_SCALE) 0.0 ((golaTopZ - actualBIH) * PKD_SCALE) \
                               "Carcass_Gola" p.handleLib doorT:0.0 golaAlign:1 \
                               handleFlipH:p.handleFlipH handleFlipV:p.handleFlipV
                    if gh != undefined do append parts gh
                )
            )
            else
            (
                if p.headlessMaterial == 2 then
                (
                    append parts (PKD_Part "Gola_Wood_H" mInt (W - 2*t) overlapY t t t (golaTopZ - actualBIH) \
                                  matLabel:p.matCarcass band:(W - 2*t) bandCode:"F")
                    if (actualBIH - t) > 0.1 do
                        append parts (PKD_Part "Gola_Wood_V" mInt (W - 2*t) t (actualBIH - t) t (overlapY - t) (t + overlapY - t) (golaTopZ - actualBIH + t) \
                                      matLabel:p.matCarcass band:(W - 2*t) bandCode:"F")
                )
                else
                (
                    append parts (PKD_Part "Carcass_Gola" mHandle golaW overlapY actualBIH golaX 0 (golaTopZ - actualBIH) role:"HARDWARE" hw:"HANDLE")
                )
            )
        )
    )

    
    ------------------------------------------------------------------ doors
    if p.doors > 0 and doorSpanW > 0 and doorH > 0 do
    (
        local singleW = (doorSpanW - doorGap * (p.doors - 1)) / p.doors
        local doorOvr = if p.doorSides == "" then #() else (filterString p.doorSides ",")
        local headlessSubtract = if isGolaActive then (p.headlessGap + (if p.golaDrop == 2 then t else 0.0)) else 0.0
        local bih = if p.handleType == 2 then actualBIH else (if p.handleType == 3 then headlessSubtract else 0.0)
        local cx = dxMin
        for i = 1 to p.doors do
        (
            local dw = if p.customDoor then p.customDoorW else singleW
            local dh = (if p.customDoor then p.customDoorH else doorH) - bih

            if dw > 0.5 and dh > 0.5 do
            (
                append parts (PKD_Part ("Door_" + i as string) mDoor dw doorT dh cx dyMin dzMin \
                              grain:"V" matLabel:p.matDoor band:(2.0 * (dw + dh)) bandCode:"4S")

                /*  CONVENTION: "يمين / Right" = towards Side_Right = +X
                    hingeRight = hinges on the +X edge  ->  handle on the -X edge
                    Auto = hinges on the OUTER edges so handles meet in the middle. */
                local hs = p.hingeSide
                if doorOvr.count >= i do
                (
                    local v = try (doorOvr[i] as integer) catch (0)
                    if v == 2 or v == 3 do hs = v
                )
                local hingeRight = case hs of
                (
                    2: true
                    3: false
                    default: (mod i 2 == 0)
                )
                local handleRight = not hingeRight

                -- handle
                if p.handleType != 3 do
                (
                    local hT = 1.5, hProt = 3.0
                    local hTop = amax 0.0 (amin (dh - 3.0) p.handleTop)
                    local hEdg = amax 0.0 (amin (dw - hT - 0.5) p.handleEdge)

                    if hTmpl != undefined then
                    (
                        -- BUILT-IN (gola) section: extruded to the DOOR WIDTH and seated
                        -- on the top edge of the door, which was shortened by bih.
                        local hh = PKD_PlaceGola hTmpl (dw * PKD_SCALE) golaRot \
                                   (cx * PKD_SCALE) (dyMin * PKD_SCALE) ((dzMin + dh) * PKD_SCALE) \
                                   ("Handle_" + i as string) p.handleLib doorT:doorT golaAlign:p.golaAlign handleFlipH:p.handleFlipH handleFlipV:p.handleFlipV
                        if hh != undefined do append parts hh
                    )
                    else if hTmpl != undefined then
                    (
                        -- 3D model handle from the library
                        local sc = PKD_SCALE
                        local hh = PKD_PlaceHandle hTmpl false (p.handleAxis == 1) \
                                   (p.handleLen * sc) p.handleRot \
                                   (dyMin * sc) ((dzMin + dh - hTop) * sc) \
                                   ((if handleRight then (cx + dw - hEdg) else (cx + hEdg)) * sc) \
                                   handleRight ("Handle_" + i as string) p.handleLib \
                                   asIs:p.handleAsIs
                        if hh != undefined do append parts hh
                    )
                    else
                    (
                        local hLen = amin 12.0 (dh - hTop - 2.0)
                        if hLen > 3.0 do
                        (
                            local hx = if handleRight then (cx + dw - hEdg - hT) else (cx + hEdg)
                            append parts (PKD_Part ("Handle_" + i as string) mHandle hT hProt hLen \
                                          hx (dyMin - hProt) (dzMin + dh - hTop - hLen) role:"HARDWARE" hw:"HANDLE")
                        )
                    )
                )


            )
            -- [FIX 07] advance by the ACTUAL door width
            cx += dw + doorGap
        )
    )

    if hTmplGlobal != undefined do ( try ( delete hTmplGlobal ) catch () )

    ------------------------------------------------------------------ legs
    if p.legH > 0 do
    (
        local r = 1.5, ins = 3.0
        local x1 = ins + r, x2 = W - ins - r
        local y1 = ins + r, y2 = D - ins - r
        -- [FIX 06] add intermediate leg rows so spacing never exceeds 60 cm
        local rows = (ceil ((x2 - x1) / 60.0)) + 1
        if rows < 2 do rows = 2
        local n = 0
        for i = 1 to rows do
        (
            local fx = x1 + (x2 - x1) * ((i - 1) as float / (rows - 1))
            n += 1; append parts (PKD_Leg ("Leg_" + n as string) mLeg fx y1 p.legH r legName:p.legName)
            n += 1; append parts (PKD_Leg ("Leg_" + n as string) mLeg fx y2 p.legH r legName:p.legName)
        )
    )

    ------------------------------------------------------------------ finalize
    if parts.count == 0 do ( messagebox "لم يتم توليد أي أجزاء." title:"خطأ"; return undefined )

    for o in parts do o.transform = o.transform * baseTM

    local typeTag = #("Base", "Wall", "Corner", "Tall")
    local ti = p.unitType
    if ti < 1 or ti > 4 do ti = 1
    local gName = "PKD_" + typeTag[ti] + "_Unit_" + (W as integer) as string
    local grp = group parts name:gName

    PKD_SaveProps grp p
    setUserProp grp "pkdBaseTM" (baseTM as string)
    setUserProp grp "pkdGrpTM"  (grp.transform as string)
    PKD_ActiveUnit = grp

    -- [FIX 08] purge the whole old hierarchy, not just the group head
    select grp
    setCommandPanelTaskMode oldPanelMode
    if wasIsolated do
    (
        try ( IsolateSelection.EnterIsolateSelectionMode() ) catch ()
    )
    grp
)


-------------------------------------------------------------------------------
-- 5. CUT LIST EXPORT
-------------------------------------------------------------------------------
fn PKD_TypeName idx =
(
    local t = #("Base Unit", "Wall Unit", "Corner Unit", "Tall Unit")
    if idx >= 1 and idx <= 4 then t[idx] else t[1]
)

/*  Writes a string as real UTF-8 (with BOM) so Arabic material names open
    correctly in Excel. MaxScript's createFile writes ANSI, which mangles them. */
fn PKD_WriteUTF8 path str =
(
    local f = fopen path "wb"
    if f == undefined do return false
    WriteByte f 239 #unsigned
    WriteByte f 187 #unsigned
    WriteByte f 191 #unsigned
    for i = 1 to str.count do
    (
        local c = bit.charAsInt str[i]
        if c < 128 then WriteByte f c #unsigned
        else if c < 2048 then
        (
            WriteByte f (bit.or 192 (bit.shift c -6)) #unsigned
            WriteByte f (bit.or 128 (bit.and c 63)) #unsigned
        )
        else
        (
            WriteByte f (bit.or 224 (bit.shift c -12)) #unsigned
            WriteByte f (bit.or 128 (bit.and (bit.shift c -6) 63)) #unsigned
            WriteByte f (bit.or 128 (bit.and c 63)) #unsigned
        )
    )
    fclose f
    true
)

fn PKD_SelectedUnits =
(
    local res = #()
    for o in selection do
    (
        local g = PKD_GetHead o
        if g != undefined do appendIfUnique res g
    )
    res
)

/*  Full cutting list + material + edge-banding report for ONE or MANY units. */
fn PKD_ExportCSV grps filePath =
(
    local f1 = ".1f", f2 = ".2f", f3 = ".3f"

    -- rows: 1 unit 2 part 3 qty 4 L 5 W 6 T 7 mat 8 grain 9 bandCode 10 bandPerPc(cm)
    local keys = #(), rows = #()
    local unitLines = #()
    local hwKeys = #(), hwRows = #()   -- 1 unit 2 item 3 name 4 qty

    for g in grps do
    (
        local p = PKD_LoadProps g
        append unitLines #(g.name, PKD_TypeName p.unitType, p.W, p.H, p.D, p)

        local all = #()
        PKD_CollectNodes g all
        for o in all do
        (
            local role = getUserProp o "pkdRole"
            if role != undefined and (role as string) == "PANEL" do
            (
                local L  = (getUserProp o "pkdL") as float
                local Wd = (getUserProp o "pkdW") as float
                local Th = (getUserProp o "pkdT") as float
                local gr = getUserProp o "pkdGrain";     if gr == undefined do gr = "L"
                local bc = getUserProp o "pkdBandCode";  if bc == undefined do bc = "-"
                local bd = getUserProp o "pkdBand"
                bd = if bd == undefined then 0.0 else (bd as float)
                local mt = getUserProp o "pkdMatName"
                if mt == undefined do mt = (if o.material != undefined then o.material.name else "None")

                local nb = trimRight o.name "0123456789_"
                local key = g.name + "|" + nb + "|" + (formattedPrint L format:f1) + "|" + \
                            (formattedPrint Wd format:f1) + "|" + (formattedPrint Th format:f1) + "|" + (mt as string)
                local idx = findItem keys key
                if idx == 0 then
                (
                    append keys key
                    append rows #(g.name, nb, 1, L, Wd, Th, (mt as string), (gr as string), (bc as string), bd)
                )
                else rows[idx][3] += 1
            )

            if role != undefined and (role as string) == "HARDWARE" do
            (
                local hwt = getUserProp o "pkdHw"
                if hwt != undefined do
                (
                    local item = case (hwt as string) of
                    (
                        "LEG":    "Leg"
                        "HANDLE": "Handle"
                        "HINGE":  "Hinge 35mm Cup"
                        default:  (hwt as string)
                    )
                    local hnm = getUserProp o "pkdHwName"
                    hnm = if hnm == undefined then "-" else (hnm as string)
                    local hk = g.name + "|" + item + "|" + hnm
                    local hi = findItem hwKeys hk
                    if hi == 0 then ( append hwKeys hk; append hwRows #(g.name, item, hnm, 1) )
                    else hwRows[hi][4] += 1
                )
            )
        )
    )

    if rows.count == 0 do ( messagebox "لا توجد ألواح للتصدير." title:"تنبيه"; return false )

    ------------------------------------------------------------------ build text
    local out = StringStream ""
    format "PKD CUTTING LIST\r\n" to:out
    format "Generated,%\r\n" (PKD_Q (localTime as string)) to:out
    format "Units in list,%\r\n\r\n" grps.count to:out

    format "UNITS\r\n" to:out
    format "Unit Name,Type,Width(cm),Height(cm),Depth(cm)\r\n" to:out
    for u in unitLines do
        format "%,%,%,%,%\r\n" (PKD_Q u[1]) (PKD_Q u[2]) \
            (formattedPrint u[3] format:f1) (formattedPrint u[4] format:f1) (formattedPrint u[5] format:f1) to:out

    format "\r\nPANELS\r\n" to:out
    format "No,Unit,Part,Qty,Length(cm),Width(cm),Thk(cm),Material,Grain,EdgeBand,Band/pc(m),Band Total(m)\r\n" to:out
    local n = 0, grandBand = 0.0
    for r in rows do
    (
        n += 1
        local bpc = r[10] / 100.0
        local btot = bpc * r[3]
        grandBand += btot
        format "%,%,%,%,%,%,%,%,%,%,%,%\r\n" n (PKD_Q r[1]) (PKD_Q r[2]) r[3] \
            (formattedPrint r[4] format:f1) (formattedPrint r[5] format:f1) (formattedPrint r[6] format:f1) \
            (PKD_Q r[7]) (PKD_Q r[8]) (PKD_Q r[9]) \
            (formattedPrint bpc format:f3) (formattedPrint btot format:f3) to:out
    )

    ------------------------------------------------------------------ materials
    local mk = #(), mr = #()   -- 1 mat 2 thk 3 pieces 4 area(m2) 5 band(m)
    for r in rows do
    (
        local key = r[7] + "|" + (formattedPrint r[6] format:f1)
        local i = findItem mk key
        local area = (r[4] * r[5] / 10000.0) * r[3]
        local band = (r[10] / 100.0) * r[3]
        if i == 0 then ( append mk key; append mr #(r[7], r[6], r[3], area, band) )
        else ( mr[i][3] += r[3]; mr[i][4] += area; mr[i][5] += band )
    )

    local pRef = unitLines[1][6]
    local sheetArea = (pRef.sheetL * pRef.sheetW) / 10000.0
    local wf = 1.0 + (pRef.waste / 100.0)
    local totalSheets = 0

    format "\r\nMATERIAL SUMMARY\r\n" to:out
    format "Material,Thk(cm),Pieces,Net Area(m2),With Waste (m2),Sheet Size(cm),Sheets Needed,Sheet Price,Cost\r\n" to:out
    for m in mr do
    (
        local withWaste = m[4] * wf
        local sheets = if sheetArea > 0 then (ceil (withWaste / sheetArea)) as integer else 0
        totalSheets += sheets
        format "%,%,%,%,%,%,%,%,%\r\n" (PKD_Q m[1]) (formattedPrint m[2] format:f1) m[3] \
            (formattedPrint m[4] format:f2) (formattedPrint withWaste format:f2) \
            (PKD_Q ((formattedPrint pRef.sheetL format:f1) + " x " + (formattedPrint pRef.sheetW format:f1))) \
            sheets (formattedPrint pRef.sheetPrice format:f2) \
            (formattedPrint (sheets * pRef.sheetPrice) format:f2) to:out
    )
    format "TOTAL,,,,,,%,,%\r\n" totalSheets (formattedPrint (totalSheets * pRef.sheetPrice) format:f2) to:out

    ------------------------------------------------------------------ banding
    format "\r\nEDGE BANDING SUMMARY\r\n" to:out
    format "Material,Tape Width(mm),Length(m),Price/m,Cost\r\n" to:out
    local bandCost = 0.0
    for m in mr do
    (
        if m[5] > 0.0001 do
        (
            local c = m[5] * pRef.bandPrice
            bandCost += c
            format "%,%,%,%,%\r\n" (PKD_Q m[1]) (formattedPrint (pRef.bandWidth * 10.0) format:f1) \
                (formattedPrint m[5] format:f2) (formattedPrint pRef.bandPrice format:f2) \
                (formattedPrint c format:f2) to:out
        )
    )
    format "TOTAL,,%,,%\r\n" (formattedPrint grandBand format:f2) (formattedPrint bandCost format:f2) to:out

    ------------------------------------------------------------------ hardware
    format "\r\nHARDWARE\r\n" to:out
    format "Unit,Item,Name / Model,Qty\r\n" to:out
    local totKeys = #(), totRows = #()
    for h in hwRows do
    (
        format "%,%,%,%\r\n" (PKD_Q h[1]) (PKD_Q h[2]) (PKD_Q h[3]) h[4] to:out
        local tk = h[2] + "|" + h[3]
        local ti2 = findItem totKeys tk
        if ti2 == 0 then ( append totKeys tk; append totRows #(h[2], h[3], h[4]) )
        else totRows[ti2][3] += h[4]
    )
    format "\r\nHARDWARE TOTAL (all units)\r\n" to:out
    format "Item,Name / Model,Qty\r\n" to:out
    for h in totRows do
        format "%,%,%\r\n" (PKD_Q h[1]) (PKD_Q h[2]) h[3] to:out

    format "\r\nGRAND TOTAL COST,%\r\n" \
        (formattedPrint ((totalSheets * pRef.sheetPrice) + bandCost) format:f2) to:out

    local txt = out as string
    close out
    local ok = PKD_WriteUTF8 filePath txt
    if ok != true do ( messagebox "تعذر كتابة الملف. تأكد أن الملف غير مفتوح في الإكسل." title:"خطأ"; return false )
    true
)


-------------------------------------------------------------------------------
-- 5b. SINGLE-ELEMENT EDIT  (enter the group, pick ONE door, change only it)
-------------------------------------------------------------------------------
fn PKD_DoorIndexFromNode node =
(
    if node == undefined do return 0
    local nm = node.name
    local pre = #("Door_", "Handle_", "Hinge_")
    for pfx in pre do
    (
        if (matchPattern nm pattern:(pfx + "*")) do
        (
            local rest = substring nm (pfx.count + 1) -1
            local parts = filterString rest "_"
            if parts.count > 0 do ( local v = try (parts[1] as integer) catch (0)
                                    if v != undefined and v > 0 do return v )
        )
    )
    0
)

/*  side: 1 = follow the global setting , 2 = Right (+X) , 3 = Left (-X)  */
fn PKD_ApplyDoorSide side =
(
    local sel = if selection.count > 0 then selection[1] else undefined
    local g = PKD_GetHead sel
    if g == undefined do
    ( messagebox "ادخل جوه الجروب (Open Group) وحدد دلفة واحدة." title:"تنبيه"; return false )

    local idx = PKD_DoorIndexFromNode sel
    if idx == 0 do
    ( messagebox "حدد دلفة (Door_x) أو مقبضها أو مفصلتها من داخل الجروب." title:"تنبيه"; return false )

    local p = PKD_LoadProps g
    if idx > p.doors do
    ( messagebox "رقم الدلفة خارج نطاق الوحدة." title:"تنبيه"; return false )

    -- 1. persist the override on the group
    local old = if p.doorSides == "" then #() else (filterString p.doorSides ",")
    local o = #()
    for i = 1 to p.doors do
    (
        local v = 0
        if old.count >= i do ( v = try (old[i] as integer) catch (0) )
        if v == undefined do v = 0
        o[i] = v
    )
    o[idx] = if side == 1 then 0 else side
    local str = ""
    for i = 1 to p.doors do ( str += (o[i] as string); if i < p.doors do str += "," )
    setUserProp g "uDoorSides" (if str == "" then "-" else str)

    -- 2. fast path: just MIRROR the handle + hinge cups of that one door.
    --    (a full rebuild is far slower and is not needed here)
    local all = #()
    PKD_CollectNodes g all
    local doorNode = undefined, movers = #(), hNode = undefined
    local dName = "Door_" + idx as string
    local hName = "Handle_" + idx as string
    for n in all do
    (
        if n.name == dName do doorNode = n
        if n.name == hName do ( hNode = n; append movers n )
    )
    if doorNode == undefined or hNode == undefined do
    ( messagebox "لم يتم العثور على الدلفة أو مقبضها." title:"تنبيه"; return false )

    local ax = normalize doorNode.transform.row1     -- door local X, in world
    local c  = doorNode.center

    local hs = if side == 1 then p.hingeSide else side
    local hingeRight = case hs of
    (
        2: true
        3: false
        default: (mod idx 2 == 0)
    )
    local wantHandleRight = not hingeRight
    local curHandleRight  = (dot (hNode.center - c) ax) > 0

    if curHandleRight != wantHandleRight then
    (
        undo "PKD Door Side" on
        (
            for n in movers do
            (
                local d = dot (n.center - c) ax
                n.pos = n.pos + (ax * (-2.0 * d))
            )
        )
    )
    else
        ( PKD_MainUI.lblInfo.text = "الدلفة " + idx as string + " بالفعل في هذا الاتجاه" )
    true
)


-------------------------------------------------------------------------------
-- 6. UI  -  SUB ROLLOUTS
-------------------------------------------------------------------------------
rollout rBasic "مقاس الوحدة السفلية (سم)"
(
    dropdownlist ddlUnitType "نوع الوحدة:" items:#("سفلية", "علوية", "كورنر", "طويلة") align:#right
    spinner spnW "" range:[15.0, 10000.0, 60.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnW "عرض الوحدة السفلية:" align:#right
    spinner spnH "" range:[30.0, 150.0, 76.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnH "ارتفاع الجنب بالقاعدة (بدون الرجل):" align:#right
    spinner spnD "" range:[20.0, 120.0, 60.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnD "عمق الوحدة السفلية (بدون الدلفة):" align:#right
    spinner spnT "" range:[10.0, 40.0, 18.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnT "سمك اللوح (مم):" align:#right

    on ddlUnitType selected val do PKD_AutoUpdate()
    on spnW changed val do PKD_AutoUpdate()
    on spnH changed val do PKD_AutoUpdate()
    on spnD changed val do PKD_AutoUpdate()
    on spnT changed val do PKD_AutoUpdate()
)

rollout rAssembly "تجميع الجنبين"
(
    checkbox chkTopFull "سقف كامل"        checked:false width:100 align:#left across:3
    checkbox chkTopStr  "شدادات (مرايات)" checked:true  width:120 align:#left
    label lblTopMode "نوع التجميع:" width:100 align:#right
    dropdownlist ddlFullTopType "نظام السقف:" items:#("بين الجنبين", "فوق الجنبين") align:#right

    checkbox chkFrontV "رأسي" checked:false width:90 align:#left across:3
    checkbox chkFrontH "أفقي" checked:true  width:90 align:#left
    label lblFrontSt "وضع الشداد أمامي" width:120 align:#right
    checkbox chkBackV "رأسي" checked:false width:90 align:#left across:3
    checkbox chkBackH "أفقي" checked:true  width:90 align:#left
    label lblBackSt "وضع الشداد الخلفي" width:120 align:#right

    spinner spnStretch "" range:[5.0, 30.0, 7.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnStretch "عرض الشداد (سم):" align:#right
    spinner spnFrontSet "" range:[0.0, 30.0, 0.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnFrontSet "رجوع الشداد / السقف (سم):" align:#right

    checkbox chkBsp3 "خلف الظهر"  checked:false width:75 align:#left across:4
    checkbox chkBsp2 "أمام الظهر" checked:false width:75 align:#left
    checkbox chkBsp1 "فوق الظهر"  checked:true  width:75 align:#left
    label lblBackStPos "وضع الشداد الخلفي:" width:110 align:#right

    fn syncVis =
    (
        local isStretch = chkTopStr.checked
        spnStretch.visible = isStretch;  lc_spnStretch.visible = isStretch
        lblFrontSt.visible = isStretch; chkFrontH.visible = isStretch; chkFrontV.visible = isStretch
        lblBackSt.visible  = isStretch; chkBackH.visible  = isStretch; chkBackV.visible  = isStretch
        spnFrontSet.visible = true; lc_spnFrontSet.visible = true
        lblBackStPos.visible = isStretch
        chkBsp1.visible = isStretch; chkBsp2.visible = isStretch; chkBsp3.visible = isStretch
        ddlFullTopType.visible = not isStretch
        
        if isStretch then
        (
            local isV = chkBackV.checked
            chkBsp1.enabled = not isV  -- enabled only for horizontal
            chkBsp2.enabled = true     -- always enabled
            chkBsp3.enabled = isV      -- enabled only for vertical
        )
    )
    fn setTopMode isStr = ( chkTopStr.checked = isStr; chkTopFull.checked = not isStr; syncVis() )
    fn setBsp k =
    (
        chkBsp1.checked = (k == 1); chkBsp2.checked = (k == 2); chkBsp3.checked = (k == 3)
    )
    fn setFront isV = ( chkFrontV.checked = isV; chkFrontH.checked = not isV )
    fn setBack  isV =
    (
        chkBackV.checked = isV; chkBackH.checked = not isV
        if isV then
        (
            if chkBsp1.checked do setBsp 2
        )
        else
        (
            if chkBsp3.checked do setBsp 2
        )
        syncVis()
    )
    fn bspValue = ( if chkBsp2.checked then 2 else (if chkBsp3.checked then 3 else 1) )

    on chkTopStr  changed st do ( setTopMode true; PKD_AutoUpdate() )
    on chkTopFull changed st do ( setTopMode false; PKD_AutoUpdate() )
    on chkFrontH changed st do ( setFront false; PKD_AutoUpdate() )
    on chkFrontV changed st do ( setFront true; PKD_AutoUpdate() )
    on chkBackH  changed st do ( setBack false; PKD_AutoUpdate() )
    on chkBackV  changed st do ( setBack true; PKD_AutoUpdate() )
    on chkBsp1 changed st do ( if chkBackV.checked then setBsp 2 else setBsp 1; PKD_AutoUpdate() )
    on chkBsp2 changed st do ( setBsp 2; PKD_AutoUpdate() )
    on chkBsp3 changed st do ( setBsp 3; PKD_AutoUpdate() )
    on rAssembly open do syncVis()

    on ddlFullTopType selected val do PKD_AutoUpdate()
    on spnStretch changed val do PKD_AutoUpdate()
    on spnFrontSet changed val do PKD_AutoUpdate()
)

rollout rBack "الظهر"
(
    label    lblBackType "نوع الظهر:" width:100 align:#right across:3
    checkbox chkGroove   "مفحار"      checked:true  width:100
    checkbox chkNoGroove "بدون مفحار" checked:false width:110
    spinner spnTB "" range:[ 3.0, 20.0, 8.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnTB "سمك الظهر (مم):" align:#right
    spinner spnGrooveDepth "" range:[ 0.1, 5.0, 0.8] type:#float fieldwidth:60 align:#left across:2
    label lc_spnGrooveDepth "عمق المفحار (سم):" align:#right
    spinner spnSetback "" range:[ 0.0, 15.0, 1.8] type:#float fieldwidth:60 align:#left across:2
    label lc_spnSetback "مسافة الرجوع (سم):" align:#right

    fn syncEn =
    (
        local g = chkGroove.checked
        spnGrooveDepth.enabled = g;  lc_spnGrooveDepth.enabled = g
        spnSetback.enabled = g;      lc_spnSetback.enabled = g
    )
    /* the two checkboxes behave as a radio pair */
    fn setMode isGroove =
    (
        chkGroove.checked   = isGroove
        chkNoGroove.checked = not isGroove
        syncEn()
    )
    on chkGroove   changed st do ( setMode true; PKD_AutoUpdate() )
    on chkNoGroove changed st do ( setMode false; PKD_AutoUpdate() )
    on rBack open do syncEn()

    on spnTB changed val do PKD_AutoUpdate()
    on spnGrooveDepth changed val do PKD_AutoUpdate()
    on spnSetback changed val do PKD_AutoUpdate()
)

rollout rLegs "الأرجل"
(
    edittext txtLegName "اسم / موديل الرجل:" text:"PVC Leg 100mm" fieldwidth:170 align:#right
    spinner spnLeg "" range:[0.0, 30.0, 10.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnLeg "ارتفاع الرجل (سم):" align:#right
    label   lblLegNote "صفر = بدون أرجل | الصفوف تزيد تلقائياً كل 60سم" align:#center

    on txtLegName entered txt do PKD_AutoUpdate()
    on spnLeg changed val do PKD_AutoUpdate()
)

rollout rShelves "الأرفف"
(
    spinner spnShelves "" range:[0, 15, 1] type:#integer fieldwidth:60 align:#left across:2
    label lc_spnShelves "عدد الأرفف بكل خانة:" align:#right
    spinner spnShelfD "" range:[10.0, 100.0, 50.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnShelfD "عمق الرف (سم):" align:#right
    spinner spnShelfClear "" range:[0.0, 20.0, 1.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnShelfClear "خلوص الرف (مم):" align:#right

    on spnShelves changed val do PKD_AutoUpdate()
    on spnShelfD changed val do PKD_AutoUpdate()
    on spnShelfClear changed val do PKD_AutoUpdate()
)

rollout rParts "القواطيع الداخلية"
(
    checkbox chkPartitions "تفعيل الفواصل الداخلية" checked:false align:#right
    spinner spnPartitions "" range:[1, 5, 1] type:#integer fieldwidth:60 enabled:false align:#left across:2
    label lc_spnPartitions "عدد القواطيع:" align:#right
    label lblPartSide "مكان القاطوع:" align:#center
    checkbox chkPartR "يمين" checked:true  align:#center across:2 enabled:false
    checkbox chkPartL "شمال" checked:false align:#center enabled:false
    dropdownlist ddlPartMode "امتداد القاطوع:" \
        items:#("القاطوع أسفل الشداد / السقف", "بارتفاع الجنب مع خلع للشدادات") align:#right enabled:false
    label lblPartNote "يمين = ناحية Side_Right (+X)" align:#center

    fn setPartSide isR = ( chkPartR.checked = isR; chkPartL.checked = not isR )
    on chkPartR changed st do ( setPartSide true; PKD_AutoUpdate() )
    on chkPartL changed st do ( setPartSide false; PKD_AutoUpdate() )
    on chkPartitions changed state do
    (
        spnPartitions.enabled = state; lc_spnPartitions.enabled = state
        ddlPartMode.enabled = state
        chkPartR.enabled = state; chkPartL.enabled = state
        PKD_AutoUpdate()
    )

    on spnPartitions changed val do PKD_AutoUpdate()
    on ddlPartMode selected val do PKD_AutoUpdate()
)

rollout rDoors "الدلف والمقابض"
(
    checkbox chkDoorIn  "داخل الوحدة (ركبة)" checked:false width:110 align:#left across:3
    checkbox chkDoorOut "خارج الوحدة (عدلة)" checked:true  width:110 align:#left
    label lblDoorPos "وضع الدلفة:" width:80 align:#right
    spinner spnDoors "" range:[0, 10, 1] type:#integer fieldwidth:60 align:#left across:2
    label lc_spnDoors "عدد الدلف:" align:#right
    spinner spnDoorGap "" range:[0.0, 30.0, 1.5] type:#float fieldwidth:60 align:#left across:2
    label lc_spnDoorGap "خلوص الدلف (مم):" align:#right
    spinner spnDoorThick "" range:[10.0, 40.0, 18.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnDoorThick "سمك الدلفة (مم):" align:#right
    label lblSepD1 "----------------------------------------" align:#center
    label lblHingeSide "جهة المفصلات:" align:#center
    checkbox chkHingeR "يمين" checked:true  align:#center across:2
    checkbox chkHingeL "شمال" checked:false align:#center
    label lblHingeNote "المقبض في الناحية المقابلة | يمين = ناحية Side_Right" align:#center
    button btnApplyDoor "تطبيق على الدلفة المحددة فقط" width:230 height:24 align:#center
    label lblSepD2 "----------------------------------------" align:#center
    label lblHandlePos "مكان المقبض:" align:#center
    spinner spnHandleTop "" range:[0.0, 150.0, 4.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnHandleTop "من أعلى الدلفة (سم):" align:#right
    spinner spnHandleEdge "" range:[0.0, 100.0, 4.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnHandleEdge "من حرف الدلفة (سم):" align:#right
    label lblSepD3 "----------------------------------------" align:#center
    checkbox chkCustomDoor "تفعيل دلفة مخصصة المقاس" checked:false align:#right
    spinner spnCustomDoorW "" range:[1.0, 300.0, 40.0] type:#float fieldwidth:60 enabled:false align:#left across:2
    label lc_spnCustomDoorW "العرض (سم):" align:#right
    spinner spnCustomDoorH "" range:[1.0, 150.0, 70.0] type:#float fieldwidth:60 enabled:false align:#left across:2
    label lc_spnCustomDoorH "الارتفاع (سم):" align:#right

    fn setDoorPos isOut = ( chkDoorOut.checked = isOut; chkDoorIn.checked = not isOut )
    fn setHinge   isR   = ( chkHingeR.checked = isR;   chkHingeL.checked = not isR )

    on chkDoorOut changed st do ( setDoorPos true; PKD_AutoUpdate() )
    on chkDoorIn  changed st do ( setDoorPos false; PKD_AutoUpdate() )
    on chkHingeR  changed st do ( setHinge true; PKD_AutoUpdate() )
    on chkHingeL  changed st do ( setHinge false; PKD_AutoUpdate() )
    on btnApplyDoor pressed do PKD_ApplyDoorSide (if chkHingeR.checked then 2 else 3)
    on chkCustomDoor changed state do
    (
        spnCustomDoorW.enabled = state; lc_spnCustomDoorW.enabled = state
        spnCustomDoorH.enabled = state; lc_spnCustomDoorH.enabled = state
        PKD_AutoUpdate()
    )

    on spnDoors changed val do PKD_AutoUpdate()
    on spnDoorGap changed val do PKD_AutoUpdate()
    on spnDoorThick changed val do PKD_AutoUpdate()
    on spnHandleTop changed val do PKD_AutoUpdate()
    on spnHandleEdge changed val do PKD_AutoUpdate()
    on spnCustomDoorW changed val do PKD_AutoUpdate()
    on spnCustomDoorH changed val do PKD_AutoUpdate()
)

rollout rMat "الخامات وشريط الحرف"
(
    edittext txtMatCarcass "خامة الشاسيه:" text:"Counter White HPL" fieldwidth:180 align:#right
    edittext txtMatDoor    "خامة الدلف:"   text:"Poly-Lac Red"      fieldwidth:180 align:#right
    edittext txtMatBack    "خامة الظهر:"   text:"HDF 8mm White"     fieldwidth:180 align:#right
    label lblSep2 "----------------------------------------" align:#center
    spinner spnBandWidth "" range:[10.0, 60.0, 22.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnBandWidth "عرض شريط الحرف (مم):" align:#right
    spinner spnBandPrice "" range:[0.0, 10000.0, 0.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnBandPrice "سعر متر الشريط:" align:#right
    label lblSep3 "----------------------------------------" align:#center
    spinner spnSheetL "" range:[50.0, 600.0, 244.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnSheetL "طول اللوح (سم):" align:#right
    spinner spnSheetW "" range:[50.0, 400.0, 122.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnSheetW "عرض اللوح (سم):" align:#right
    spinner spnWaste "" range:[0.0, 60.0, 15.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnWaste "نسبة الهالك (%):" align:#right
    spinner spnSheetPrice "" range:[0.0, 1000000.0, 0.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnSheetPrice "سعر اللوح:" align:#right
    checkbox chkOpenAfter "فتح الملف بعد الحفظ" checked:true align:#center
    label lblMatNote "التصدير يشمل كل الوحدات المحددة" align:#center

    on txtMatCarcass entered txt do PKD_AutoUpdate()
    on txtMatDoor entered txt do PKD_AutoUpdate()
    on txtMatBack entered txt do PKD_AutoUpdate()
)


rollout rHandles "مكتبة المقابض"
(
    dropdownlist ddlHandleType "نظام المقابض:" items:#("مقبض عادي", "مقبض بيلت إن", "بدون مقبض (Headless)") align:#right

    -- Group 1 & 2 controls
    label lblHKind "نوع المقبض:" align:#center
    checkbox chkHDefault "افتراضي (بوكس)" checked:true  align:#center across:2
    checkbox chkHLib     "من المكتبة"      checked:false align:#center
    dropdownlist ddlHLib "المقبض:" items:#() align:#right
    label lblSepH1 "----------------------------------------" align:#center
    button btnHAddSel  "إضافة المحدد في الماكس كمقبض" width:250 height:24 align:#center
    button btnHAddFile "تحميل مقبض من الهارد (.max)"  width:250 height:24 align:#center
    button btnHDel     "حذف المقبض المحدد من المكتبة" width:250 height:24 align:#center
    button btnHRefresh "تحديث القائمة"                width:250 height:22 align:#center
    label lblSepH2 "----------------------------------------" align:#center
    
    label lblGFit "اتجاه القطاع 2D:" width:120 align:#right across:3
    checkbox chkGFit1 "رأسي" checked:true  width:90
    checkbox chkGFit2 "أفقي" checked:false width:90
    
    label lblHAxis "اتجاه المقبض 3D:" width:120 align:#right across:3
    checkbox chkHVert "رأسي" checked:true  width:90
    checkbox chkHHorz "أفقي" checked:false width:90

    checkbox chkHFlipH "عكس اتجاه افقى" checked:false align:#left across:2
    checkbox chkHFlipV "عكس اتجاه راسى" checked:false align:#right
    dropdownlist ddlGolaAlign "محاذاة المقبض البيلت إن:" items:#("مطابق للأمام (بروز للخلف)", "مطابق للخلف (بروز للأمام)") align:#right
    
    spinner spnHLen "" range:[1.0, 300.0, 12.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnHLen "طول القطاع (سم):" align:#right
    spinner spnHRot "" range:[-180.0, 180.0, 0.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnHRot "دوران (درجة):" align:#right
    spinner spnBIH "" range:[0.0, 30.0, 0.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnBIH "ارتفاع مقبض بيلت إن (سم):" align:#right

    -- Group 3 (Headless) controls
    dropdownlist ddlHeadlessMat "خامة المقبض:" items:#("خشب", "ألومنيوم") align:#right
    spinner spnHeadlessDepth "" range:[1.0, 15.0, 2.6] type:#float fieldwidth:60 align:#left across:2
    label lc_spnHeadlessDepth "عمق الخلع (سم):" align:#right
    spinner spnHeadlessHeight "" range:[1.0, 20.0, 5.7] type:#float fieldwidth:60 align:#left across:2
    label lc_spnHeadlessHeight "ارتفاع الخلع (سم):" align:#right
    spinner spnHeadlessGap "" range:[0.0, 10.0, 3.0] type:#float fieldwidth:60 align:#left across:2
    label lc_spnHeadlessGap "مسافة فتح الدلفه (سم):" align:#right
    radiobuttons rdoGolaType "" labels:#("غاطس بخلع", "بين الجنبين") default:1 columns:2 align:#left across:2
    label lblGolaType "طريقة التركيب:" align:#right
    radiobuttons rdoGolaDrop "" labels:#("على الوش", "أسفل السقف") default:1 columns:2 align:#left across:2
    label lblGolaDrop "ارتفاع المقبض:" align:#right

    label lblHNote1 "القطاع (شكل 2D) يتمدد للطول المحدد" align:#center
    label lblHNote2 "الموديل 3D يستخدم بمقاسه كما هو" align:#center

    fn refreshList =
    (
        local nm = PKD_HandleNames()
        local cur = ""
        if ddlHLib.items.count > 0 and ddlHLib.selection > 0 do cur = ddlHLib.items[ddlHLib.selection]
        ddlHLib.items = nm
        local i = findItem nm cur
        if nm.count > 0 do ddlHLib.selection = (if i > 0 then i else 1)
    )

    fn syncVis =
    (
        local t = ddlHandleType.selection
        local isNormal  = (t == 1)
        local isBuiltIn = (t == 2)
        local isHeadless = (t == 3)

        -- Shared Default vs Library choice
        lblHKind.visible = true; chkHDefault.visible = true; chkHLib.visible = true
        lblSepH1.visible = true
        
        local isLib = chkHLib.checked

        -- Show library controls only if Library is selected
        local showLib = (isLib and (isNormal or isBuiltIn or isHeadless))
        ddlHLib.visible = showLib
        btnHAddSel.visible = showLib; btnHAddFile.visible = showLib; btnHDel.visible = showLib; btnHRefresh.visible = showLib
        lblSepH2.visible = showLib

        -- Normal handle controls (only if Default is checked)
        local showNormalDef = (isNormal and not isLib)
        lblHAxis.visible = showNormalDef; chkHVert.visible = showNormalDef; chkHHorz.visible = showNormalDef
        lblHNote2.visible = showNormalDef

        -- Built-in controls
        local showBuiltIn = (isBuiltIn)
        lblGFit.visible = (showBuiltIn and isLib)
        chkGFit1.visible = (showBuiltIn and isLib)
        chkGFit2.visible = (showBuiltIn and isLib)
        ddlGolaAlign.visible = showBuiltIn
        spnHLen.visible = (showBuiltIn and not isLib)
        lc_spnHLen.visible = (showBuiltIn and not isLib)
        spnHRot.visible = showBuiltIn
        lc_spnHRot.visible = showBuiltIn
        spnBIH.visible = (showBuiltIn and not isLib)
        lc_spnBIH.visible = (showBuiltIn and not isLib)
        lblHNote1.visible = (showBuiltIn and isLib)

        -- Headless controls (always visible)
        ddlHeadlessMat.visible = isHeadless
        spnHeadlessDepth.visible = isHeadless
        lc_spnHeadlessDepth.visible = isHeadless
        spnHeadlessHeight.visible = isHeadless
        lc_spnHeadlessHeight.visible = isHeadless

        -- Opening gap is always visible in Headless mode
        spnHeadlessGap.visible = isHeadless
        lc_spnHeadlessGap.visible = isHeadless

        -- Flips are visible for Built-in & Headless in Library mode
        local needsFlips = ((isBuiltIn or isHeadless) and isLib)
        chkHFlipH.visible = needsFlips; chkHFlipV.visible = needsFlips
    )

    fn setKind isLib = ( chkHLib.checked = isLib; chkHDefault.checked = not isLib; syncVis() )
    fn setGFit k = ( chkGFit1.checked = (k != 2); chkGFit2.checked = (k == 2) )
    fn gfitValue = ( if chkGFit2.checked then 2 else 1 )
    fn setAxis isV   = ( chkHVert.checked = isV; chkHHorz.checked = not isV )
    fn curName = ( if ddlHLib.items.count > 0 and ddlHLib.selection > 0 then ddlHLib.items[ddlHLib.selection] else "" )

    on ddlHandleType selected val do ( syncVis(); PKD_AutoUpdate() )
    on ddlHeadlessMat selected val do PKD_AutoUpdate()
    on spnHeadlessDepth changed val do PKD_AutoUpdate()
    on spnHeadlessHeight changed val do PKD_AutoUpdate()
    on spnHeadlessGap changed val do PKD_AutoUpdate()
    on rdoGolaType changed val do PKD_AutoUpdate()
    on rdoGolaDrop changed val do PKD_AutoUpdate()

    on chkHDefault changed st do ( setKind false; PKD_AutoUpdate() )
    on chkHLib     changed st do ( setKind true; PKD_AutoUpdate() )
    on chkGFit1 changed st do ( setGFit 1; PKD_AutoUpdate() )
    on chkGFit2 changed st do ( setGFit 2; PKD_AutoUpdate() )
    on chkHVert    changed st do ( setAxis true; PKD_AutoUpdate() )
    on chkHHorz    changed st do ( setAxis false; PKD_AutoUpdate() )
    on chkHFlipH   changed st do PKD_AutoUpdate()
    on chkHFlipV   changed st do PKD_AutoUpdate()
    on ddlGolaAlign selected val do PKD_AutoUpdate()
    on btnHRefresh pressed do refreshList()
    on btnHAddSel pressed do
    (
        local n = PKD_HandleAddFromScene()
        if n != undefined do
        ( refreshList(); local i = findItem ddlHLib.items n; if i > 0 do ddlHLib.selection = i
          setKind true
          messagebox ("تمت إضافة المقبض للمكتبة:\n" + n) title:"تم" )
    )
    on btnHAddFile pressed do
    (
        local n = PKD_HandleAddFromDisk()
        if n != undefined do
        ( refreshList(); local i = findItem ddlHLib.items n; if i > 0 do ddlHLib.selection = i
          setKind true
          messagebox ("تم تحميل المقبض:\n" + n) title:"تم" )
    )
    on btnHDel pressed do
    (
        local n = curName()
        if n == "" then messagebox "لا يوجد مقبض محدد." title:"تنبيه"
        else if (queryBox ("حذف \"" + n + "\" من المكتبة؟") title:"تأكيد") do
        ( PKD_HandleDelete n; refreshList() )
    )
    on rHandles open do ( refreshList(); syncVis() )

    on ddlHLib selected val do PKD_AutoUpdate()
    on spnHLen changed val do PKD_AutoUpdate()
    on spnHRot changed val do PKD_AutoUpdate()
    on spnBIH changed val do PKD_AutoUpdate()
)


-------------------------------------------------------------------------------
-- 7. PANEL STATE  (values live in PKD_State, not in the rollout controls, so
--    nothing is lost when a panel is swapped out of the sub-rollout)
-------------------------------------------------------------------------------
fn PKD_PanelList = #(rBasic, rAssembly, rBack, rLegs, rShelves, rParts, rDoors, rMat, rHandles)

fn PKD_PullPanel idx =
(
    local p = PKD_State
    case idx of
    (
        1: (
            p.unitType = rBasic.ddlUnitType.selection
            p.W = rBasic.spnW.value
            p.H = rBasic.spnH.value
            p.D = rBasic.spnD.value
            p.t = rBasic.spnT.value / 10.0
        )
        2: (
            p.topMode     = if rAssembly.chkTopStr.checked then 2 else 1
            p.fullTopType = rAssembly.ddlFullTopType.selection
            p.stretch     = rAssembly.spnStretch.value
            p.fDir        = if rAssembly.chkFrontV.checked then 2 else 1
            p.bDir        = if rAssembly.chkBackV.checked  then 2 else 1
            p.frontStSet  = rAssembly.spnFrontSet.value
            p.backStPos   = rAssembly.bspValue()
        )
        3: (
            p.backMode    = if rBack.chkGroove.checked then 2 else 1
            p.tb          = rBack.spnTB.value / 10.0
            p.grooveDepth = rBack.spnGrooveDepth.value
            p.setback     = rBack.spnSetback.value
        )
        4: (
            p.legName = rLegs.txtLegName.text
            p.legH    = rLegs.spnLeg.value
        )
        5: (
            p.shelves    = rShelves.spnShelves.value
            p.shelfD     = rShelves.spnShelfD.value
            p.shelfClear = rShelves.spnShelfClear.value / 10.0
        )
        6: (
            p.partActive = rParts.chkPartitions.checked
            p.partCount  = rParts.spnPartitions.value
            p.partPos    = if rParts.chkPartR.checked then 2 else 3
            p.partMode   = rParts.ddlPartMode.selection
        )
        7: (
            p.doorType    = if rDoors.chkDoorIn.checked then 1 else 3
            p.doors       = rDoors.spnDoors.value
            p.doorGap     = rDoors.spnDoorGap.value
            p.doorThick   = rDoors.spnDoorThick.value / 10.0
            p.hingeSide   = if rDoors.chkHingeR.checked then 2 else 3
            p.handleTop   = rDoors.spnHandleTop.value
            p.handleEdge  = rDoors.spnHandleEdge.value
            p.customDoor  = rDoors.chkCustomDoor.checked
            p.customDoorW = rDoors.spnCustomDoorW.value
            p.customDoorH = rDoors.spnCustomDoorH.value
        )
        8: (
            p.matCarcass = rMat.txtMatCarcass.text
            p.matDoor    = rMat.txtMatDoor.text
            p.matBack    = rMat.txtMatBack.text
            p.bandWidth  = rMat.spnBandWidth.value / 10.0
            p.bandPrice  = rMat.spnBandPrice.value
            p.sheetL     = rMat.spnSheetL.value
            p.sheetW     = rMat.spnSheetW.value
            p.waste      = rMat.spnWaste.value
            p.sheetPrice = rMat.spnSheetPrice.value
            p.openAfter  = rMat.chkOpenAfter.checked
        )
        9: (
            p.handleType = rHandles.ddlHandleType.selection
            p.headlessMaterial = rHandles.ddlHeadlessMat.selection
            p.headlessDepth = rHandles.spnHeadlessDepth.value
            p.headlessHeight = rHandles.spnHeadlessHeight.value
            p.headlessGap = rHandles.spnHeadlessGap.value
            p.golaBetweenSides = rHandles.rdoGolaType.state
            p.golaDrop = rHandles.rdoGolaDrop.state
            p.handleKind = if rHandles.chkHLib.checked then 2 else 1
            p.handleLib  = rHandles.curName()
            p.handleAxis = if rHandles.chkHVert.checked then 1 else 2
            p.handleAsIs = false
            p.golaFit    = rHandles.gfitValue()
            p.handleLen  = rHandles.spnHLen.value
            p.handleRot  = rHandles.spnHRot.value
            p.builtInH   = rHandles.spnBIH.value
            p.handleFlipH = rHandles.chkHFlipH.checked
            p.handleFlipV = rHandles.chkHFlipV.checked
            p.golaAlign  = rHandles.ddlGolaAlign.selection
        )
        default: ()
    )
    true
)

fn PKD_PushPanel idx =
(
    local p = PKD_State
    case idx of
    (
        1: (
            rBasic.ddlUnitType.selection = p.unitType
            rBasic.spnW.value = p.W
            rBasic.spnH.value = p.H
            rBasic.spnD.value = p.D
            rBasic.spnT.value = p.t * 10.0
        )
        2: (
            rAssembly.setTopMode (p.topMode == 2)
            rAssembly.ddlFullTopType.selection = p.fullTopType
            rAssembly.spnStretch.value         = p.stretch
            rAssembly.setFront (p.fDir == 2)
            rAssembly.setBack  (p.bDir == 2)
            rAssembly.spnFrontSet.value        = p.frontStSet
            rAssembly.setBsp p.backStPos
            rAssembly.syncVis()
        )
        3: (
            rBack.spnTB.value          = p.tb * 10.0
            rBack.spnGrooveDepth.value = p.grooveDepth
            rBack.spnSetback.value     = p.setback
            rBack.setMode (p.backMode == 2)
        )
        4: (
            rLegs.txtLegName.text = p.legName
            rLegs.spnLeg.value    = p.legH
        )
        5: (
            rShelves.spnShelves.value    = p.shelves
            rShelves.spnShelfD.value     = p.shelfD
            rShelves.spnShelfClear.value = p.shelfClear * 10.0
        )
        6: (
            rParts.chkPartitions.checked = p.partActive
            rParts.spnPartitions.value   = p.partCount
            rParts.setPartSide (p.partPos != 3)
            rParts.ddlPartMode.selection = p.partMode
            rParts.spnPartitions.enabled = p.partActive
            rParts.lc_spnPartitions.enabled = p.partActive
            rParts.chkPartR.enabled      = p.partActive
            rParts.chkPartL.enabled      = p.partActive
            rParts.ddlPartMode.enabled   = p.partActive
        )
        7: (
            rDoors.setDoorPos (p.doorType != 1)
            rDoors.spnDoors.value         = p.doors
            rDoors.spnDoorGap.value       = p.doorGap
            rDoors.spnDoorThick.value     = p.doorThick * 10.0
            rDoors.setHinge (p.hingeSide != 3)
            rDoors.spnHandleTop.value     = p.handleTop
            rDoors.spnHandleEdge.value    = p.handleEdge
            rDoors.chkCustomDoor.checked  = p.customDoor
            rDoors.spnCustomDoorW.enabled = p.customDoor
            rDoors.spnCustomDoorH.enabled = p.customDoor
            rDoors.lc_spnCustomDoorW.enabled = p.customDoor
            rDoors.lc_spnCustomDoorH.enabled = p.customDoor
            rDoors.spnCustomDoorW.value   = p.customDoorW
            rDoors.spnCustomDoorH.value   = p.customDoorH
        )
        8: (
            rMat.txtMatCarcass.text  = p.matCarcass
            rMat.txtMatDoor.text     = p.matDoor
            rMat.txtMatBack.text     = p.matBack
            rMat.spnBandWidth.value  = p.bandWidth * 10.0
            rMat.spnBandPrice.value  = p.bandPrice
            rMat.spnSheetL.value     = p.sheetL
            rMat.spnSheetW.value     = p.sheetW
            rMat.spnWaste.value      = p.waste
            rMat.spnSheetPrice.value = p.sheetPrice
            rMat.chkOpenAfter.checked = p.openAfter
        )
        9: (
            rHandles.refreshList()
            rHandles.ddlHandleType.selection = p.handleType
            rHandles.ddlHeadlessMat.selection = p.headlessMaterial
            rHandles.spnHeadlessDepth.value = p.headlessDepth
            rHandles.spnHeadlessHeight.value = p.headlessHeight
            rHandles.spnHeadlessGap.value = p.headlessGap
            rHandles.rdoGolaType.state = p.golaBetweenSides
            rHandles.rdoGolaDrop.state = p.golaDrop
            rHandles.setKind (p.handleKind == 2)
            rHandles.setAxis (p.handleAxis == 1)
            rHandles.setGFit p.golaFit
            rHandles.spnHLen.value = p.handleLen
            rHandles.spnHRot.value = p.handleRot
            rHandles.spnBIH.value  = p.builtInH
            rHandles.chkHFlipH.checked = p.handleFlipH
            rHandles.chkHFlipV.checked = p.handleFlipV
            rHandles.ddlGolaAlign.selection = p.golaAlign
            rHandles.syncVis()
            local i = findItem rHandles.ddlHLib.items p.handleLib
            if i > 0 do rHandles.ddlHLib.selection = i
        )
        default: ()
    )
    true
)


-------------------------------------------------------------------------------
-- 8. LANGUAGE  (applied per panel, so captions survive a panel swap)
-------------------------------------------------------------------------------
fn PKD_SetDDL ddl newItems =
( local s = ddl.selection; ddl.items = newItems; if s > 0 and s <= newItems.count do ddl.selection = s )

fn PKD_CatNames isEN =
(
    -- BUTTON order (not panel order):  1=Dims 2=Doors 3=Assembly 4=Back
    --                                   5=Legs 6=Shelves 7=Partitions 8=Materials
    if isEN then #("Unit Size", "Doors", "Unit Top", "Back", "Legs", "Shelves", "Partitions", "Materials", "Handles")
    else         #("مقاس الوحدة", "الدلف", "سقف الوحده", "الظهر", "الأرجل", "الأرفف", "القواطيع", "الخامات", "المقابض")
)

fn PKD_LangPanel idx isEN =
(
    case idx of
    (
    1: (
        if isEN then
        (
            rBasic.title = "Base Unit Size (cm)"
            PKD_SetDDL rBasic.ddlUnitType #("Base", "Wall", "Corner", "Tall")
            rBasic.ddlUnitType.caption = "Unit Type:"
            rBasic.lc_spnW.caption = "Unit Width:"
            rBasic.lc_spnH.caption = "Side + Base Height (no legs):"
            rBasic.lc_spnD.caption = "Unit Depth (without door):"
            rBasic.lc_spnT.caption = "Panel Thickness (mm):"
        )
        else
        (
            rBasic.title = "مقاس الوحدة السفلية (سم)"
            PKD_SetDDL rBasic.ddlUnitType #("سفلية", "علوية", "كورنر", "طويلة")
            rBasic.ddlUnitType.caption = "نوع الوحدة:"
            rBasic.lc_spnW.caption = "عرض الوحدة السفلية:"
            rBasic.lc_spnH.caption = "ارتفاع الجنب بالقاعدة (بدون الرجل):"
            rBasic.lc_spnD.caption = "عمق الوحدة السفلية (بدون الدلفة):"
            rBasic.lc_spnT.caption = "سمك اللوح (مم):"
        )
    )
    2: (
        if isEN then
        (
            rAssembly.title = "Unit Top"
            rAssembly.lblTopMode.caption = "Assembly Type:"
            rAssembly.chkTopStr.caption = "Stretchers"; rAssembly.chkTopFull.caption = "Full Top"
            rAssembly.lc_spnStretch.caption = "Stretcher W (cm):"
            rAssembly.lblFrontSt.caption = "Front Stretcher"
            rAssembly.chkFrontV.caption = "Vertical"; rAssembly.chkFrontH.caption = "Horizontal"
            rAssembly.lblBackSt.caption = "Back Stretcher"
            rAssembly.chkBackV.caption = "Vertical";  rAssembly.chkBackH.caption = "Horizontal"
            rAssembly.lc_spnFrontSet.caption = "Front Str. Setback (cm):"
            rAssembly.lblBackStPos.caption = "Back Str. Position:"
            rAssembly.chkBsp1.caption = "Over back"
            rAssembly.chkBsp2.caption = "Front of back"
            rAssembly.chkBsp3.caption = "Behind back"
            PKD_SetDDL rAssembly.ddlFullTopType #("Between Sides", "Over Sides"); rAssembly.ddlFullTopType.caption = "Top Type:"
        )
        else
        (
            rAssembly.title = "سقف الوحده"
            rAssembly.lblTopMode.caption = "نوع التجميع:"
            rAssembly.chkTopStr.caption = "شدادات (مرايات)"; rAssembly.chkTopFull.caption = "سقف كامل"
            rAssembly.lc_spnStretch.caption = "عرض الشداد (سم):"
            rAssembly.lblFrontSt.caption = "وضع الشداد أمامي"
            rAssembly.chkFrontV.caption = "رأسي"; rAssembly.chkFrontH.caption = "أفقي"
            rAssembly.lblBackSt.caption = "وضع الشداد الخلفي"
            rAssembly.chkBackV.caption = "رأسي";  rAssembly.chkBackH.caption = "أفقي"
            rAssembly.lc_spnFrontSet.caption = "رجوع الشداد الأمامي (سم):"
            rAssembly.lblBackStPos.caption = "وضع الشداد الخلفي:"
            rAssembly.chkBsp1.caption = "فوق الظهر"
            rAssembly.chkBsp2.caption = "أمام الظهر"
            rAssembly.chkBsp3.caption = "خلف الظهر"
            PKD_SetDDL rAssembly.ddlFullTopType #("بين الجنبين", "فوق الجنبين"); rAssembly.ddlFullTopType.caption = "نظام السقف:"
        )
    )
    3: (
        if isEN then
        (
            rBack.title = "Back Panel"
            rBack.lblBackType.caption = "Back Type:"
            rBack.chkGroove.caption   = "Grooved"
            rBack.chkNoGroove.caption = "Nailed"
            rBack.lc_spnTB.caption = "Back Thk (mm):"
            rBack.lc_spnGrooveDepth.caption = "Groove Depth (cm):"
            rBack.lc_spnSetback.caption = "Setback (cm):"
        )
        else
        (
            rBack.title = "الظهر"
            rBack.lblBackType.caption = "نوع الظهر:"
            rBack.chkGroove.caption   = "مفحار"
            rBack.chkNoGroove.caption = "بدون مفحار"
            rBack.lc_spnTB.caption = "سمك الظهر (مم):"
            rBack.lc_spnGrooveDepth.caption = "عمق المفحار (سم):"
            rBack.lc_spnSetback.caption = "مسافة الرجوع (سم):"
        )
    )
    4: (
        if isEN then
        (
            rLegs.title = "Legs"
            rLegs.txtLegName.caption = "Leg Name / Model:"
            rLegs.lc_spnLeg.caption = "Leg Height (cm):"
            rLegs.lblLegNote.caption = "0 = no legs | rows auto-added every 60cm"
        )
        else
        (
            rLegs.title = "الأرجل"
            rLegs.txtLegName.caption = "اسم / موديل الرجل:"
            rLegs.lc_spnLeg.caption = "ارتفاع الرجل (سم):"
            rLegs.lblLegNote.caption = "صفر = بدون أرجل | الصفوف تزيد تلقائياً كل 60سم"
        )
    )
    5: (
        if isEN then
        (
            rShelves.title = "Shelves"
            rShelves.lc_spnShelves.caption = "Shelves per Bay:"
            rShelves.lc_spnShelfD.caption = "Shelf Depth (cm):"
            rShelves.lc_spnShelfClear.caption = "Clearance (mm):"
        )
        else
        (
            rShelves.title = "الأرفف"
            rShelves.lc_spnShelves.caption = "عدد الأرفف بكل خانة:"
            rShelves.lc_spnShelfD.caption = "عمق الرف (سم):"
            rShelves.lc_spnShelfClear.caption = "خلوص الرف (مم):"
        )
    )
    6: (
        if isEN then
        (
            rParts.title = "Internal Partitions"
            rParts.chkPartitions.caption = "Enable Internal Partitions"
            rParts.lc_spnPartitions.caption = "Count:"
            rParts.lblPartSide.caption = "Partition Side:"
            rParts.chkPartR.caption = "Right"; rParts.chkPartL.caption = "Left"
            PKD_SetDDL rParts.ddlPartMode #("Partition under stretcher / top", "Full side height + notch")
            rParts.ddlPartMode.caption = "Partition Reach:"
            rParts.lblPartNote.caption = "Right = towards Side_Right (+X)"
        )
        else
        (
            rParts.title = "القواطيع الداخلية"
            rParts.chkPartitions.caption = "تفعيل الفواصل الداخلية"
            rParts.lc_spnPartitions.caption = "عدد القواطيع:"
            rParts.lblPartSide.caption = "مكان القاطوع:"
            rParts.chkPartR.caption = "يمين"; rParts.chkPartL.caption = "شمال"
            PKD_SetDDL rParts.ddlPartMode #("القاطوع أسفل الشداد / السقف", "بارتفاع الجنب مع خلع للشدادات")
            rParts.ddlPartMode.caption = "امتداد القاطوع:"
            rParts.lblPartNote.caption = "يمين = ناحية Side_Right (+X)"
        )
    )
    7: (
        if isEN then
        (
            rDoors.title = "Doors & Handles"
            rDoors.lblDoorPos.caption = "Door Position:"
            rDoors.chkDoorOut.caption = "Outside (overlay)"
            rDoors.chkDoorIn.caption  = "Inside (inset)"
            rDoors.lc_spnDoors.caption = "Doors Count:"
            rDoors.lblHingeSide.caption = "Hinge Side:"
            rDoors.chkHingeR.caption = "Right"; rDoors.chkHingeL.caption = "Left"
            rDoors.lblHingeNote.caption = "Handle goes on the opposite edge | Right = Side_Right"
            rDoors.btnApplyDoor.text = "Apply to the SELECTED door only"
            rDoors.lblHandlePos.caption = "Handle Position:"
            rDoors.lc_spnHandleTop.caption  = "From door top (cm):"
            rDoors.lc_spnHandleEdge.caption = "From door edge (cm):"
            rDoors.lc_spnDoorGap.caption = "Door Clearance (mm):"; rDoors.lc_spnDoorThick.caption = "Door Thickness (mm):"
            rDoors.chkCustomDoor.caption = "Custom Door Size"
            rDoors.lc_spnCustomDoorW.caption = "Width (cm):"; rDoors.lc_spnCustomDoorH.caption = "Height (cm):"
        )
        else
        (
            rDoors.title = "الدلف والمقابض"
            rDoors.lblDoorPos.caption = "وضع الدلفة:"
            rDoors.chkDoorOut.caption = "خارج الوحدة (عدلة)"
            rDoors.chkDoorIn.caption  = "داخل الوحدة (ركبة)"
            rDoors.lc_spnDoors.caption = "عدد الدلف:"
            rDoors.lblHingeSide.caption = "جهة المفصلات:"
            rDoors.chkHingeR.caption = "يمين"; rDoors.chkHingeL.caption = "شمال"
            rDoors.lblHingeNote.caption = "المقبض في الناحية المقابلة | يمين = ناحية Side_Right"
            rDoors.btnApplyDoor.text = "تطبيق على الدلفة المحددة فقط"
            rDoors.lblHandlePos.caption = "مكان المقبض:"
            rDoors.lc_spnHandleTop.caption  = "من أعلى الدلفة (سم):"
            rDoors.lc_spnHandleEdge.caption = "من حرف الدلفة (سم):"
            rDoors.lc_spnDoorGap.caption = "خلوص الدلف (مم):"; rDoors.lc_spnDoorThick.caption = "سمك الدلفة (مم):"
            rDoors.chkCustomDoor.caption = "تفعيل دلفة مخصصة المقاس"
            rDoors.lc_spnCustomDoorW.caption = "العرض (سم):"; rDoors.lc_spnCustomDoorH.caption = "الارتفاع (سم):"
        )
    )
    8: (
        if isEN then
        (
            rMat.title = "Materials & Edge Banding"
            rMat.txtMatCarcass.caption = "Carcass Mat:"
            rMat.txtMatDoor.caption    = "Door Mat:"
            rMat.txtMatBack.caption    = "Back Mat:"
            rMat.lc_spnBandWidth.caption  = "Tape Width (mm):"
            rMat.lc_spnBandPrice.caption  = "Price / metre:"
            rMat.lc_spnSheetL.caption     = "Sheet Length (cm):"
            rMat.lc_spnSheetW.caption     = "Sheet Width (cm):"
            rMat.lc_spnWaste.caption      = "Waste (%):"
            rMat.lc_spnSheetPrice.caption = "Sheet Price:"
            rMat.chkOpenAfter.caption  = "Open the file after saving"
            rMat.lblMatNote.caption    = "Export covers every selected unit"
        )
        else
        (
            rMat.title = "الخامات وشريط الحرف"
            rMat.txtMatCarcass.caption = "خامة الشاسيه:"
            rMat.txtMatDoor.caption    = "خامة الدلف:"
            rMat.txtMatBack.caption    = "خامة الظهر:"
            rMat.lc_spnBandWidth.caption  = "عرض شريط الحرف (مم):"
            rMat.lc_spnBandPrice.caption  = "سعر متر الشريط:"
            rMat.lc_spnSheetL.caption     = "طول اللوح (سم):"
            rMat.lc_spnSheetW.caption     = "عرض اللوح (سم):"
            rMat.lc_spnWaste.caption      = "نسبة الهالك (%):"
            rMat.lc_spnSheetPrice.caption = "سعر اللوح:"
            rMat.chkOpenAfter.caption  = "فتح الملف بعد الحفظ"
            rMat.lblMatNote.caption    = "التصدير يشمل كل الوحدات المحددة"
        )
    )
    9: (
        if isEN then
        (
            rHandles.title = "Handle Library"
            rHandles.lblHKind.caption = "Handle Type:"
            rHandles.chkHDefault.caption = "Built-in (box)"
            rHandles.chkHLib.caption = "From library"
            rHandles.ddlHLib.caption = "Handle:"
            rHandles.btnHAddSel.text  = "Add SELECTED object as a handle"
            rHandles.btnHAddFile.text = "Load a handle from disk (.max)"
            rHandles.btnHDel.text     = "Remove selected from library"
            rHandles.btnHRefresh.text = "Refresh list"
            rHandles.lblGFit.caption = "2D Section Direction:"
            rHandles.chkGFit1.caption = "Vertical"; rHandles.chkGFit2.caption = "Horizontal"
            rHandles.lblHAxis.caption = "3D Handle Direction:"
            rHandles.chkHVert.caption = "Vertical"; rHandles.chkHHorz.caption = "Horizontal"
            rHandles.chkHFlipH.caption = "Reverse Horiz. Dir"
            rHandles.chkHFlipV.caption = "Reverse Vert. Dir"
            PKD_SetDDL rHandles.ddlGolaAlign #("Flush Front (Extends Back)", "Flush Back (Extends Front)")
            rHandles.ddlGolaAlign.caption = "Built-in Align:"
            rHandles.lblGolaType.caption = "Mounting:"
            rHandles.rdoGolaType.labels = #("Notched Sides", "Between Sides")
            rHandles.lblGolaDrop.caption = "Gola Height Pos:"
            rHandles.rdoGolaDrop.labels = #("Flush with Top", "Dropped by 18mm")
            rHandles.lc_spnHLen.caption = "Profile Length (cm):"
            rHandles.lc_spnHRot.caption = "Spin (deg):"
            rHandles.lc_spnBIH.caption = "Built-in Height (0 = auto):"
            rHandles.lblHNote1.caption = "Draw the 2D section in the Left / Right viewport"
            rHandles.lblHNote2.caption = "Door + handle = the original door height"
        )
        else
        (
            rHandles.title = "مكتبة المقابض"
            rHandles.lblHKind.caption = "نوع المقبض:"
            rHandles.chkHDefault.caption = "افتراضي (بوكس)"
            rHandles.chkHLib.caption = "من المكتبة"
            rHandles.ddlHLib.caption = "المقبض:"
            rHandles.btnHAddSel.text  = "إضافة المحدد في الماكس كمقبض"
            rHandles.btnHAddFile.text = "تحميل مقبض من الهارد (.max)"
            rHandles.btnHDel.text     = "حذف المقبض المحدد من المكتبة"
            rHandles.btnHRefresh.text = "تحديث القائمة"
            rHandles.lblGFit.caption = "اتجاه القطاع 2D:"
            rHandles.chkGFit1.caption = "رأسي"; rHandles.chkGFit2.caption = "أفقي"
            rHandles.title = "مكتبة المقابض"
            PKD_SetDDL rHandles.ddlHandleType #("مقبض عادي", "مقبض بيلت إن", "بدون مقبض (Headless)")
            rHandles.ddlHandleType.caption = "نظام المقابض:"
            rHandles.lblHKind.caption = "نوع المقبض:"
            rHandles.chkHDefault.caption = "افتراضي (بوكس)"
            rHandles.chkHLib.caption = "من المكتبة"
            rHandles.ddlHLib.caption = "المقبض:"
            rHandles.btnHAddSel.text  = "إضافة المحدد في الماكس كمقبض"
            rHandles.btnHAddFile.text = "تحميل مقبض من الهارد (.max)"
            rHandles.btnHDel.text     = "حذف المقبض المحدد من المكتبة"
            rHandles.btnHRefresh.text = "تحديث القائمة"
            rHandles.lblGFit.caption = "اتجاه القطاع 2D:"
            rHandles.chkGFit1.caption = "رأسي"; rHandles.chkGFit2.caption = "أفقي"
            rHandles.lblHAxis.caption = "اتجاه المقبض 3D:"
            rHandles.chkHVert.caption = "رأسي"; rHandles.chkHHorz.caption = "أفقي"
            rHandles.chkHFlipH.caption = "عكس اتجاه افقى"
            rHandles.chkHFlipV.caption = "عكس اتجاه راسى"
            PKD_SetDDL rHandles.ddlGolaAlign #("مطابق للأمام (بروز للخلف)", "مطابق للخلف (بروز للأمام)")
            rHandles.ddlGolaAlign.caption = "محاذاة المقبض البيلت إن:"
            rHandles.lc_spnHLen.caption = "طول القطاع (سم):"
            rHandles.lc_spnHRot.caption = "دوران (درجة):"
            rHandles.lc_spnBIH.caption = "ارتفاع البيلت إن (0 = تلقائي):"
            PKD_SetDDL rHandles.ddlHeadlessMat #("ألومنيوم (إكسسوار)", "خشبي (ألواح تقطيع)")
            rHandles.ddlHeadlessMat.caption = "خامة المقبض:"
            rHandles.lc_spnHeadlessDepth.caption = "عمق الخلع (سم):"
            rHandles.lc_spnHeadlessHeight.caption = "ارتفاع الخلع (سم):"
            rHandles.lc_spnHeadlessGap.caption = "مسافة فتح الدلفه (سم):"
            rHandles.lblGolaType.caption = "طريقة التركيب:"
            rHandles.rdoGolaType.labels = #("غاطس بخلع", "بين الجنبين")
            rHandles.lblGolaDrop.caption = "ارتفاع المقبض:"
            rHandles.rdoGolaDrop.labels = #("على الوش", "أسفل السقف")
            rHandles.lblHNote1.caption = "ارسم القطاع 2D في منظر Left / Right"
            rHandles.lblHNote2.caption = "الدلفة + المقبض = ارتفاع الدلفة الأصلي"
        )
    )
    default: ()
    )
    true
)


-------------------------------------------------------------------------------
-- 9. PANEL SWITCHING  (Object-Type style: one button = one parameter panel)
-------------------------------------------------------------------------------
fn PKD_ShowPanel idx force:false =
(
    if idx < 1 or idx > 9 do return false
    if idx == PKD_CurPanel and not force do
    ( PKD_MainUI.syncCatButtons idx; return true )

    local L = PKD_PanelList()
    try ( PKD_PullPanel PKD_CurPanel ) catch ()
    for r in L do ( try ( RemoveSubRollout PKD_MainUI.subPanels r ) catch () )

    PKD_CurPanel = idx
    AddSubRollout PKD_MainUI.subPanels L[idx] rolledUp:false
    try ( PKD_LangPanel idx PKD_IsEnglish ) catch ()
    try ( PKD_PushPanel idx ) catch ()
    PKD_MainUI.syncCatButtons idx
    true
)


-------------------------------------------------------------------------------
-- 10. MAIN DIALOG
-------------------------------------------------------------------------------
rollout PKD_MainUI "Eng: Yaser Gewily | PKD Tool v12.7" width:380 height:748
(
    checkbutton chkLang "تبديل اللغة | Switch Language (EN/AR)" width:352 height:26 pos:[14,8] checked:PKD_IsEnglish

    groupBox grpCat "أقسام الوحدة" pos:[12,42] width:356 height:158
    checkbutton cb1 "مقاس الوحدة" pos:[20,60]   width:170 height:26
    checkbutton cb2 "الدلف"       pos:[190,60]  width:170 height:26
    checkbutton cb3 "سقف الوحده"     pos:[20,88]   width:170 height:26
    checkbutton cb4 "الظهر"       pos:[190,88]  width:170 height:26
    checkbutton cb5 "الأرجل"      pos:[20,116]  width:170 height:26
    checkbutton cb6 "الأرفف"      pos:[190,116] width:170 height:26
    checkbutton cb7 "القواطيع"    pos:[20,144]  width:170 height:26
    checkbutton cb8 "الخامات"     pos:[190,144] width:170 height:26
    checkbutton cb9 "المقابض"     pos:[20,172]  width:170 height:26

    subRollout subPanels "" width:352 height:366 pos:[14,208]

    button btnRead   "1. سحب الإعدادات من المحدد" width:352 height:32 pos:[14,580]
    button btnUpdate "تعديل الوحدة المحددة" width:172 height:42 pos:[14,617]
    button btnCreate "رسم وحدة جديدة"       width:172 height:42 pos:[194,617]
    button btnExport "تصدير إكسيل (CSV)" width:172 height:38 pos:[14,664]
    button btnExportSKP "تصدير سكتش اب" width:172 height:38 pos:[194,664]
    label  lblInfo   "" width:352 height:18 pos:[14,710] align:#center

    fn catButtons = #(cb1, cb2, cb3, cb4, cb5, cb6, cb7, cb8, cb9)

    fn btnPanelMap = #(1, 7, 2, 3, 4, 5, 6, 8, 9)   -- button index -> panel index

    fn syncCatButtons idx =
    (
        local b = catButtons(), m = btnPanelMap()
        for i = 1 to b.count do b[i].checked = (m[i] == idx)
    )

    fn applyCatLabels =
    (
        local nm = PKD_CatNames PKD_IsEnglish
        local b = catButtons()
        for i = 1 to b.count do b[i].text = nm[i]
        grpCat.text = if PKD_IsEnglish then "Unit Sections" else "أقسام الوحدة"
        btnRead.text   = if PKD_IsEnglish then "1. Read Settings from Selected" else "1. سحب الإعدادات من المحدد"
        btnUpdate.text = if PKD_IsEnglish then "Update Selected" else "تعديل الوحدة المحددة"
        btnCreate.text = if PKD_IsEnglish then "Create New Unit" else "رسم وحدة جديدة"
        btnExport.text = if PKD_IsEnglish then "Export Cabinet to Excel (CSV)" else "تصدير إكسيل (CSV)"
        btnExportSKP.text = if PKD_IsEnglish then "Export to SketchUp (SKP)" else "تصدير سكتش اب (SKP)"
    )

    ------------------------------------------------------ state <-> full struct
    fn readUI =
    (
        PKD_PullPanel PKD_CurPanel
        copy PKD_State
    )

    fn writeUI p =
    (
        PKD_State = copy p
        PKD_PushPanel PKD_CurPanel
    )

    ---------------------------------------------------------------- handlers
    on cb1 changed st do PKD_ShowPanel 1     -- rBasic
    on cb2 changed st do PKD_ShowPanel 7     -- rDoors
    on cb3 changed st do PKD_ShowPanel 2     -- rAssembly
    on cb4 changed st do PKD_ShowPanel 3     -- rBack
    on cb5 changed st do PKD_ShowPanel 4     -- rLegs
    on cb6 changed st do PKD_ShowPanel 5     -- rShelves
    on cb7 changed st do PKD_ShowPanel 6     -- rParts
    on cb8 changed st do PKD_ShowPanel 8     -- rMat
    on cb9 changed st do PKD_ShowPanel 9     -- rHandles

    on chkLang changed state do
    (
        PKD_IsEnglish = state
        applyCatLabels()
        try ( PKD_LangPanel PKD_CurPanel PKD_IsEnglish ) catch ()
    )

    on PKD_MainUI open do
    (
        PKD_SCALE = PKD_CalcScale()
        PKD_CurPanel = 0
        applyCatLabels()
        PKD_ShowPanel 1 force:true
        lblInfo.text = "System Unit Scale: 1cm = " + (formattedPrint PKD_SCALE format:".4f")
    )

    on btnCreate pressed do
    (
        local p = readUI()
        undo "PKD Create Unit" on ( with redraw off ( PKD_Build p oldGroup:undefined ) )
    )

    on btnUpdate pressed do
    (
        local g = PKD_GetHead (if selection.count > 0 then selection[1] else undefined)
        if g == undefined then
            messagebox "يرجى تحديد وحدة معدلة أولاً." title:"تنبيه"
        else
        (
            local p = readUI()
            p.doorSides = (PKD_LoadProps g).doorSides   -- keep per-door hinge overrides
            
            local wasIsolated = false
            try ( wasIsolated = IsolateSelection.IsolateSelectionModeActive() ) catch ( wasIsolated = false )
            if wasIsolated do
            (
                try ( IsolateSelection.ExitIsolateSelectionMode() ) catch ()
            )
            
            local newG = undefined
            disableSceneRedraw()
            try ( undo "PKD Update Unit" on ( with redraw off ( newG = PKD_Build p oldGroup:g ) ) ) catch ()
            enableSceneRedraw()
            completeRedraw()
            
            if newG != undefined do
            (
                select newG
                if wasIsolated do
                (
                    try ( IsolateSelection.EnterIsolateSelectionMode() ) catch ()
                )
            )
        )
    )

    on btnRead pressed do
    (
        local g = PKD_GetHead (if selection.count > 0 then selection[1] else undefined)
        if g == undefined then
            messagebox "يرجى تحديد وحدة تم رسمها بالأداة لقراءة إعداداتها." title:"تنبيه"
        else
        (
            PKD_ActiveUnit = g
            writeUI (PKD_LoadProps g)
            lblInfo.text = "Loaded: " + g.name
        )
    )

    on btnExport pressed do
    (
        local gs = PKD_SelectedUnits()
        if gs.count == 0 then
            messagebox "يرجى تحديد وحدة للتصدير أولاً." title:"تنبيه"
        else
        (
            local defName = if gs.count == 1 then ("Cutlist_" + gs[1].name + ".csv") else "Cutlist_Project.csv"
            local sp = getSaveFileName caption:"تصدير إكسيل" \
                        filename:defName types:"CSV Files (*.csv)|*.csv|"
            if sp != undefined do
            (
                local okFlag = false
                try ( okFlag = PKD_ExportCSV gs sp )
                catch
                (
                    okFlag = false
                    messagebox ("حدث خطأ أثناء التصدير:\n\n" + (getCurrentException())) title:"خطأ"
                )
                if okFlag do
                (
                    lblInfo.text = "تم التصدير: " + gs.count as string + " وحدة"
                    if rMat.chkOpenAfter.checked do
                        try ( ShellLaunch sp "" ) catch ()
                )
            )
        )
    )

    on btnExportSKP pressed do
    (
        local g = PKD_GetHead (if selection.count > 0 then selection[1] else undefined)
        if g == undefined then
            messagebox "يرجى تحديد وحدة للتصدير أولاً." title:"تنبيه"
        else
        (
            local f = getSaveFileName caption:"Export to SketchUp" types:"SketchUp (*.skp)|*.skp" filename:(g.name + ".skp")
            if f != undefined do
            (
                select g
                exportFile f #noPrompt selectedOnly:true
            )
        )
    )
)


-------------------------------------------------------------------------------
-- 11. LAUNCHER
-------------------------------------------------------------------------------
macroScript PKD_BaseUnit_V10
    category:"Pro Kitchen Design"
    buttonText:"PKD Base Unit"
    tooltip:"رسم وحدة سفلية - ثنائي اللغة v10"
(
    try ( destroyDialog PKD_MainUI ) catch ()
    createDialog PKD_MainUI
)

try ( destroyDialog PKD_MainUI ) catch ()
createDialog PKD_MainUI
