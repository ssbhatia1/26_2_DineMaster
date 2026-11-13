@echo off
rem ============================================================================
rem DineMaster — Isolated Environment Setup & Provisioning Script (CMD)
rem ============================================================================

set "PROJECT_ROOT=%~dp0"
set "VENV_DIR=%PROJECT_ROOT%.venv"
set "JDK_DIR=%VENV_DIR%\jdk"
set "FLUTTER_DIR=%VENV_DIR%\flutter"

echo ==================================================================
echo        DineMaster - Isolated Environment Provisioning (CMD)
echo ==================================================================

if not exist "%VENV_DIR%" mkdir "%VENV_DIR%"
if not exist "%VENV_DIR%\Scripts" mkdir "%VENV_DIR%\Scripts"

echo [1/4] Checking Isolated JDK 21...
if exist "%JDK_DIR%\bin\java.exe" (
    echo   -^> JDK 21 present at: %JDK_DIR%
) else (
    echo   -^> Copying JDK 21 to %JDK_DIR%...
    if exist "C:\Users\ssbha\Desktop\acccount\26_2_DineMaster\.venv\jdk" (
        xcopy /E /I /Q /Y "C:\Users\ssbha\Desktop\acccount\26_2_DineMaster\.venv\jdk" "%JDK_DIR%"
    )
)

echo [2/4] Checking Isolated Flutter SDK...
if exist "%FLUTTER_DIR%\bin\flutter.bat" (
    echo   -^> Flutter SDK present at: %FLUTTER_DIR%
) else (
    echo   -^> Linking Flutter SDK to %FLUTTER_DIR%...
    if exist "C:\Flutter\flutter_windows_3.41.3-stable\flutter" (
        mklink /J "%FLUTTER_DIR%" "C:\Flutter\flutter_windows_3.41.3-stable\flutter"
    )
)

echo [3/4] Resolving Frontend Dependencies...
cd "%PROJECT_ROOT%frontend"
call "%FLUTTER_DIR%\bin\flutter.bat" pub get
cd "%PROJECT_ROOT%"

echo [4/4] Verifying Backend Maven Dependencies...
cd "%PROJECT_ROOT%backend"
set "JAVA_HOME=%JDK_DIR%"
call mvnw.cmd test-compile
cd "%PROJECT_ROOT%"

echo ==================================================================
echo   DineMaster Environment Ready! Run 'activate.bat' to activate.
echo ==================================================================
