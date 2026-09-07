@echo off
echo Starting Daily GitHub Sync for PKD 3ds Max Plugin...
cd /d "d:\Social\Plugin\AI Agent\3ds Max Plugin"

:: Check if there are any changes
git status --porcelain > %temp%\git_status.txt
set /p GIT_CHANGES=<%temp%\git_status.txt

if "%GIT_CHANGES%"=="" (
    echo No changes found. Skipping sync.
) else (
    echo Changes found. Syncing to GitHub...
    git add .
    git commit -m "Daily auto-sync backup: %date% %time%"
    git push origin main
    echo Sync complete!
)

del %temp%\git_status.txt
