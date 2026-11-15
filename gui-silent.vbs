' 静默启动「重启前检查」图形界面（不弹控制台黑框）
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""D:\dpsk\projects\dsh-safe-restart\dsh-safe-restart-gui.ps1""", 0, False
