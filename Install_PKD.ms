/*
================================================================================
  PKD Kitchen Unit Builder - One-Click Installer & Activator
  Author: Eng. Yaser Gewily
================================================================================
*/
(
    local thisDir = getFilenamePath (getThisScriptFilename())
    if thisDir == "" do thisDir = @"d:\Social\Plugin\AI Agent\3ds Max Plugin\"
    local macroFile = thisDir + @"files\PKD_Macro.ms"
    local v14File   = thisDir + @"files\PKD_KitchenUnit_V14.0_Modular.ms"
    
    -- 1. Evaluate MacroScript to register in current 3ds Max session
    if doesFileExist macroFile then
    (
        fileIn macroFile
    )
    else
    (
        messageBox ("Could not find Macro file at:\n" + macroFile) title:"PKD Installer Error"
        return false
    )
    
    -- 2. Deploy auto-loader to Startup folder of current 3ds Max
    local startupDir = getDir #userStartupScripts
    if startupDir != undefined and doesFileExist startupDir do
    (
        local startupFile = startupDir + @"\PKD_Startup.ms"
        local fs = createFile startupFile
        if fs != undefined do
        (
            format "(\n" to:fs
            format "    try (\n" to:fs
            format "        fileIn @\"%\"\n" macroFile to:fs
            format "    ) catch ()\n" to:fs
            format ")\n" to:fs
            close fs
        )
    )
    
    -- 3. Copy to UserMacros folder
    local userMacroDir = getDir #userMacros
    if userMacroDir != undefined and doesFileExist userMacroDir do
    (
        local targetMcr = userMacroDir + @"\Pro Kitchen Design-PKD_KitchenUnit.mcr"
        copyFile macroFile targetMcr
    )
    
    -- 4. Open UI immediately
    if doesFileExist v14File do
    (
        try ( destroyDialog PKD_MainUI ) catch ()
        fileIn v14File
    )
    
    messageBox "تم تثبيت وتفعيل أيقونة سكربت PKD بنجاح!\nالأيقونة جاهزة وستعمل دائماً حتى بعد إعادة تشغيل الماكس." title:"Pro Kitchen Design"
)
