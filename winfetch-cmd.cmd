@echo off
rem Wrapper so winfetch can be called from cmd.exe / Run dialog.
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\winfetch.ps1" %*