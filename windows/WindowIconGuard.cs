using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace CodexUsageCard {
    // Retains the HICON handles for as long as a target window uses them.
    // No launch commands, app files, or user input are changed. For packaged
    // windows without an explicit ID, bind the client's registered package ID
    // (or inherited process ID) so Windows honours its taskbar icon property.
    public sealed class WindowIconSession : IDisposable {
        private delegate bool EnumWindowProc(IntPtr window, IntPtr data);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowProc callback, IntPtr data);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr window, uint command);
        [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr window);
        [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr window);
        [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern IntPtr LoadImage(IntPtr module, string name, uint type, int width, int height, uint flags);
        [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr icon);
        [DllImport("user32.dll", SetLastError=true)]
        private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr kind, IntPtr icon, uint flags, uint timeout, out UIntPtr result);
        [StructLayout(LayoutKind.Sequential)] private struct PropertyKey { public Guid format; public uint id; }
        [StructLayout(LayoutKind.Explicit, Size=24)] private struct PropVariant {
            [FieldOffset(0)] public ushort type;
            [FieldOffset(8)] public IntPtr text;
        }
        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IPropertyStore {
            [PreserveSig] int GetCount(out uint count);
            [PreserveSig] int GetAt(uint index, out PropertyKey key);
            [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
            [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
            [PreserveSig] int Commit();
        }
        [DllImport("shell32.dll", PreserveSig=true)]
        private static extern int SHGetPropertyStoreForWindow(IntPtr window, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);
        [DllImport("ole32.dll")] private static extern int PropVariantClear(ref PropVariant value);
        private sealed class Previous {
            public uint pid;
            public IntPtr small, large;
            public string taskbarIcon;
            public string originalAppId, boundAppId;
        }
        private readonly Dictionary<IntPtr, Previous> previous = new Dictionary<IntPtr, Previous>();
        private readonly IntPtr smallIcon, largeIcon;
        private readonly string iconResource;
        private readonly string inheritedAppId;
        public int Applied { get; private set; }
        public int WindowCount { get; private set; }

        public WindowIconSession(string iconPath, string effectiveAppId = null) {
            inheritedAppId = effectiveAppId;
            iconResource = Path.GetFullPath(iconPath) + ",0";
            smallIcon = LoadImage(IntPtr.Zero, iconPath, 1, 32, 32, 0x10);
            largeIcon = LoadImage(IntPtr.Zero, iconPath, 1, 64, 64, 0x10);
            if (smallIcon == IntPtr.Zero || largeIcon == IntPtr.Zero) {
                if (smallIcon != IntPtr.Zero) DestroyIcon(smallIcon);
                if (largeIcon != IntPtr.Zero) DestroyIcon(largeIcon);
                throw new IOException("Unable to load the official window icons.");
            }
        }

        public static IntPtr ReadIcon(IntPtr window, int kind) {
            UIntPtr result;
            if (SendMessageTimeout(window, 0x7f, (UIntPtr)(uint)kind, IntPtr.Zero, 2, 300, out result) == IntPtr.Zero)
                throw new IOException("Window icon query timed out.");
            return (IntPtr)(long)result.ToUInt64();
        }
        private static void WriteIcon(IntPtr window, int kind, IntPtr icon) {
            UIntPtr result;
            if (SendMessageTimeout(window, 0x80, (UIntPtr)(uint)kind, icon, 2, 300, out result) == IntPtr.Zero)
                throw new IOException("Window icon update timed out.");
        }
        private static IPropertyStore OpenProperties(IntPtr window) {
            Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
            IPropertyStore store;
            Marshal.ThrowExceptionForHR(SHGetPropertyStoreForWindow(window, ref iid, out store));
            return store;
        }
        private static PropertyKey Key(uint id) {
            return new PropertyKey { format = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), id = id };
        }
        public static string ReadProperty(IntPtr window, uint id) {
            IPropertyStore store = OpenProperties(window);
            PropVariant value;
            PropertyKey key = Key(id);
            try {
                Marshal.ThrowExceptionForHR(store.GetValue(ref key, out value));
                try { return value.type == 31 ? Marshal.PtrToStringUni(value.text) : null; }
                finally { PropVariantClear(ref value); }
            } finally { Marshal.ReleaseComObject(store); }
        }
        private static void WriteProperty(IntPtr window, uint id, string icon) {
            IPropertyStore store = OpenProperties(window);
            PropertyKey key = Key(id);
            PropVariant value = new PropVariant();
            if (icon != null) { value.type = 31; value.text = Marshal.StringToCoTaskMemUni(icon); }
            try {
                Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref value));
                Marshal.ThrowExceptionForHR(store.Commit());
            } finally {
                if (value.text != IntPtr.Zero) Marshal.FreeCoTaskMem(value.text);
                Marshal.ReleaseComObject(store);
            }
        }

        public void Update(int targetPid) {
            int count = 0;
            EnumWindows(delegate(IntPtr window, IntPtr unused) {
                uint pid;
                GetWindowThreadProcessId(window, out pid);
                if (pid != (uint)targetPid || GetWindow(window, 4) != IntPtr.Zero || GetWindowTextLength(window) == 0) return true;
                try {
                    IntPtr small = ReadIcon(window, 0), large = ReadIcon(window, 1);
                    string taskbar = ReadProperty(window, 3);
                    Previous saved;
                    if (!previous.TryGetValue(window, out saved) || saved.pid != pid) {
                        saved = new Previous { pid = pid, small = small, large = large, taskbarIcon = taskbar };
                        previous[window] = saved;
                    }
                    // A theme update may replace the client's own icons. Remember
                    // its latest choice before applying the official white icon again.
                    if (small != smallIcon) { saved.small = small; WriteIcon(window, 0, smallIcon); Applied++; }
                    if (large != largeIcon) { saved.large = large; WriteIcon(window, 1, largeIcon); Applied++; }
                    if (taskbar != iconResource) { saved.taskbarIcon = taskbar; WriteProperty(window, 3, iconResource); Applied++; }
                    if (!String.IsNullOrEmpty(inheritedAppId) && String.IsNullOrEmpty(ReadProperty(window, 5))) {
                        saved.originalAppId = ReadProperty(window, 5);
                        // Set the icon before the ID, as required by the shell.
                        WriteProperty(window, 5, inheritedAppId);
                        saved.boundAppId = inheritedAppId;
                        Applied++;
                    }
                    count++;
                } catch { /* Retry a busy or newly-created window on the next tick. */ }
                return true;
            }, IntPtr.Zero);
            WindowCount = count;
            List<IntPtr> closed = new List<IntPtr>();
            foreach (IntPtr window in previous.Keys) if (!IsWindow(window)) closed.Add(window);
            foreach (IntPtr window in closed) previous.Remove(window);
        }
        public void Dispose() {
            foreach (KeyValuePair<IntPtr, Previous> entry in previous) {
                uint pid;
                if (!IsWindow(entry.Key)) continue;
                GetWindowThreadProcessId(entry.Key, out pid);
                if (pid != entry.Value.pid) continue;
                try {
                    if (ReadIcon(entry.Key, 0) == smallIcon) WriteIcon(entry.Key, 0, entry.Value.small);
                    if (ReadIcon(entry.Key, 1) == largeIcon) WriteIcon(entry.Key, 1, entry.Value.large);
                    if (ReadProperty(entry.Key, 3) == iconResource) WriteProperty(entry.Key, 3, entry.Value.taskbarIcon);
                    if (entry.Value.boundAppId != null && ReadProperty(entry.Key, 5) == entry.Value.boundAppId)
                        WriteProperty(entry.Key, 5, entry.Value.originalAppId);
                } catch { }
            }
            previous.Clear();
            DestroyIcon(smallIcon); DestroyIcon(largeIcon);
        }
    }

    public static class WindowIconGuard {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
        private static extern int GetApplicationUserModelId(IntPtr process, ref uint length, StringBuilder id);
        public static string EffectiveAppId(Process process) {
            uint length = 0;
            if (GetApplicationUserModelId(process.Handle, ref length, null) != 122 || length == 0) return null;
            StringBuilder value = new StringBuilder((int)length);
            return GetApplicationUserModelId(process.Handle, ref length, value) == 0 ? value.ToString() : null;
        }
        private static void Status(string path, string state, int pid, int windows, int applied) {
            try {
                string data = "{\"state\":\"" + state + "\",\"targetPid\":" + pid + ",\"windows\":" + windows + ",\"applied\":" + applied + ",\"checkedAt\":\"" + DateTime.UtcNow.ToString("o") + "\"}";
                string temp = path + ".tmp";
                File.WriteAllText(temp, data, new UTF8Encoding(false));
                if (File.Exists(path)) File.Replace(temp, path, null); else File.Move(temp, path);
            } catch { }
        }
        public static void Run(int agentPid, int targetPid, string appPath, string iconPath, string statePath, string registeredAppId) {
            using (Process agent = Process.GetProcessById(agentPid))
            using (Process target = Process.GetProcessById(targetPid)) {
                // Bind to actual process handles, not just reusable PID numbers.
                if (!String.Equals(Path.GetFullPath(target.MainModule.FileName), Path.GetFullPath(appPath), StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Icon target executable does not match the selected client.");
                string name = "Local\\CodexUsageCard.WindowIcon." + targetPid + "." + target.StartTime.ToUniversalTime().Ticks;
                bool created;
                using (Mutex singleton = new Mutex(true, name, out created)) {
                    bool owns = created;
                    if (!owns) {
                        try { owns = singleton.WaitOne(2000); }
                        catch (AbandonedMutexException) { owns = true; }
                    }
                    if (!owns) return;
                    try {
                        int applied = 0;
                        string identity = EffectiveAppId(target);
                        if (String.IsNullOrEmpty(identity)) identity = registeredAppId;
                        using (WindowIconSession session = new WindowIconSession(iconPath, identity)) {
                            while (!agent.HasExited && !target.HasExited) {
                                session.Update(targetPid);
                                applied = session.Applied;
                                Status(statePath, "watching", targetPid, session.WindowCount, applied);
                                Thread.Sleep(750);
                            }
                        }
                        Status(statePath, "stopped", targetPid, 0, applied);
                    } finally { singleton.ReleaseMutex(); }
                }
            }
        }
    }
}
