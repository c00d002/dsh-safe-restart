@echo off
chcp 65001 >nul
title 清理 DSH 登录缓存（防 431 打不开）
set "NET=%APPDATA%\@deepseek-ai\dsh-desktop\Network"

echo ============================================
echo  清理 DeepSeek Harness 的登录 cookie 缓存
echo ============================================
echo.
echo 说明：DSH 每次启动都会写一条登录 cookie，从不清理。
echo      攒到请求头 16KB 后会报 Web authentication failed，
echo      表现为「双击打不开」。删掉这两个文件即可恢复，
echo      聊天记录/工作区都在 .dsh 目录里，不受影响。
echo.

tasklist /FI "IMAGENAME eq DeepSeek Harness.exe" 2>nul | find /I "DeepSeek Harness.exe" >nul
if not errorlevel 1 goto :running

:clean
echo 当前 DSH 未运行，开始清理...
if exist "%NET%\Cookies" (
    del /f /q "%NET%\Cookies" 2>nul && echo   [OK] 已删除 Cookies
) else (
    echo   [--] Cookies 不存在
)
if exist "%NET%\Cookies-journal" (
    del /f /q "%NET%\Cookies-journal" 2>nul && echo   [OK] 已删除 Cookies-journal
) else (
    echo   [--] Cookies-journal 不存在
)
echo.
echo 清理完成。现在可以正常启动 DSH 了。
pause
exit /b 0

:running
echo DSH 正在运行。
echo 请先【彻底退出】它（托盘图标右键退出 / 任务管理器结束），
echo 本窗口会自动继续。
echo.
:wait
timeout /t 2 /nobreak >nul
tasklist /FI "IMAGENAME eq DeepSeek Harness.exe" 2>nul | find /I "DeepSeek Harness.exe" >nul
if not errorlevel 1 goto :wait
echo DSH 已退出。
echo.
goto :clean
