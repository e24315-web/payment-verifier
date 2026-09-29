// "Payment Verifier.exe": runs installer\start.ps1 next to it, so the user only double-clicks.
// Build: installer\build_exe.ps1
using System;
using System.Diagnostics;
using System.IO;

class Launcher
{
    static int Main()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(root, "installer", "start.ps1");
        if (!File.Exists(script))
        {
            Console.WriteLine("Cannot find " + script);
            Console.WriteLine("Keep \"Payment Verifier.exe\" inside the payment-verifier folder.");
            Console.ReadLine();
            return 1;
        }
        var psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"");
        psi.UseShellExecute = false;
        psi.WorkingDirectory = root;
        using (var p = Process.Start(psi))
        {
            p.WaitForExit();
            return p.ExitCode;
        }
    }
}
