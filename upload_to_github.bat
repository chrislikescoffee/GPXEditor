@echo off
echo This script will help you upload your project to GitHub.
echo.

REM Check if git is installed
git --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Git is not installed or not in your PATH.
    echo Please install Git from https://git-scm.com/ and try again.
    pause
    exit /b
)

REM Check if a git repository is already initialized
if not exist ".git" (
    echo Initializing a new Git repository...
    git init
    git branch -m main
) else (
    echo A Git repository already exists.
)

REM Check if a remote named origin already exists
git remote get-url origin >nul 2>&1
if %errorlevel% == 0 (
    echo Remote 'origin' already exists.
) else (
    echo.
    echo Please go to https://github.com/new to create a new, empty repository.
    echo After creating the repository, copy its URL.
    echo It will look like: https://github.com/your-username/your-repo-name.git
    echo.
    set /p repo_url="Enter the repository URL and press Enter: "
    git remote add origin "%repo_url%"
)

echo Adding all files for commit...
git add .

echo Committing files...
git commit -m "Initial commit"

echo Pushing to GitHub...
git push -u origin main

echo.
echo Your project should now be on GitHub!
pause
