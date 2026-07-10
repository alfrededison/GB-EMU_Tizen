@echo off
echo ================================================
echo Building and extracting GBEmu.wgt from Docker
echo ================================================
echo.

echo [1/6] Building Docker image...
docker build -t gbemu-tizen .
if errorlevel 1 (
    echo ERROR: Docker image build failed!
    pause
    exit /b 1
)

echo [2/6] Creating temporary container...
docker create --name gbemu-tmp gbemu-tizen
if errorlevel 1 (
    echo ERROR: Failed to create container!
    pause
    exit /b 1
)

echo [3/6] Starting container...
docker start gbemu-tmp
if errorlevel 1 (
    echo ERROR: Failed to start container!
    docker rm gbemu-tmp
    pause
    exit /b 1
)

echo [4/6] Waiting...
timeout /t 2 /nobreak >nul

echo [5/6] Copying GBEmu.wgt...
docker cp gbemu-tmp:/home/gbemu/GBEmu.wgt .
if errorlevel 1 (
    echo ERROR: Failed to copy file!
    docker stop gbemu-tmp
    docker rm gbemu-tmp
    pause
    exit /b 1
)

echo [6/6] Cleaning up...
docker stop gbemu-tmp
docker rm gbemu-tmp

echo.
echo ================================================
echo SUCCESS! GBEmu.wgt extracted successfully.
echo ================================================
pause
