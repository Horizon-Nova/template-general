@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ===================== 使用者可調整 =====================
set "MAX_BACKUPS=15"
:: =======================================================

:: ================== 初始化 ==================
call :init

:: =============== [步驟 0] 先進行備份 ===============
call :backup

:: =============== [步驟 1] 拉取 ===============
call :gitPull

:: =============== [步驟 2] 推送 ===============
call :gitPush

:: =============== 結尾 ======================
goto :end

:: =====================================================
:init
echo [Init] 初始化變數...
set "script_dir=%~dp0"
set "script_dir=%script_dir:~0,-1%"

for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "[DateTime]::Now.ToString('yyyyMMddHHmmss')"`) do set "timestamp=%%i"

for /f "tokens=*" %%b in ('git rev-parse --abbrev-ref HEAD') do set "CUR_BRANCH=%%b"
echo [Init] 目前分支 = %CUR_BRANCH%

for %%f in ("%script_dir%") do set "project_name=%%~nxf"
for %%f in ("%script_dir%\..") do set "root_dir=%%~f"
set "backup_root=%root_dir%\.project-backup"
exit /b

:: =====================================================
:backup
set "bk_stamp=%timestamp%_%random%"
set "backup_path=%backup_root%\%project_name%_backup_%bk_stamp%"

if not exist "%backup_root%" mkdir "%backup_root%"
echo [備份] 複製專案資料夾到 %backup_path%

robocopy "%script_dir%" "%backup_path%" /MIR /XD .git node_modules .vs bin obj packages HNB\Areas\Backoffice\storage /NFL /NDL /NJH /NJS
if %errorlevel% GEQ 8 (
    echo [錯誤] 備份失敗：robocopy 發生錯誤（等級 %errorlevel%）
    exit /b 1
)

echo [成功] 備份完成：%backup_path%
call :cleanupBackups
exit /b

:: =====================================================
:cleanupBackups
if not exist "%backup_root%" exit /b
set "count=0"
for /f "delims=" %%d in ('dir "%backup_root%\%project_name%_backup_*" /B /AD /O-D') do (
    set /a count+=1
    if !count! gtr %MAX_BACKUPS% (
        echo [清理] 刪除舊備份 %%d
        rmdir /s /q "%backup_root%\%%d"
    )
)
exit /b

:: =====================================================
:gitPull
echo [Git] 嘗試 git pull...
git config --global --add safe.directory "%cd%"
git pull origin %CUR_BRANCH%
if %errorlevel% neq 0 (
    echo [錯誤] Pull 失敗，請手動檢查版本衝突或網路錯誤。
    goto :fatalError
)
exit /b

:: =====================================================
:gitPush
echo [Git] 準備 commit 與 push...
set "hasCommits=false"
for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "[DateTime]::Now.ToString('yyyy-MM-dd_HH-mm-ss')"`) do set "commit_msg=%%i"

git add .
git commit -m "%commit_msg%" >nul 2>&1
if %errorlevel% equ 0 (
    echo [Git] 有變更已提交
    set "hasCommits=true"
) else (
    echo [警告] 無變更可提交，略過 commit
)

git push origin %CUR_BRANCH%
if %errorlevel% neq 0 (
    echo [錯誤] Push 失敗，備份後進入強制同步
    call :gitReset
)
exit /b

:: =====================================================
:gitReset
echo [嚴重錯誤] 重設本地至遠端最新狀態...
git fetch origin || goto :fatalError
git reset --hard origin/%CUR_BRANCH% || goto :fatalError
git clean -fdx
git pull origin %CUR_BRANCH% || goto :fatalError
echo [成功] 強制同步完成
exit /b

:: =====================================================
:fatalError
echo [嚴重錯誤] 無法完成同步，請手動處理！
pause
exit /b

:: =====================================================
:end
echo.
echo [成功] 所有流程完成！
pause
exit /b