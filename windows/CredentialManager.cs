using System.Runtime.InteropServices;
using System.Text;

namespace Brink;

/// Minimal read-only access to Windows Credential Manager generic credentials —
/// the Windows counterpart of the macOS Keychain lookup in the original app.
public static class CredentialManager
{
    private const int CRED_TYPE_GENERIC = 1;

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, int type, int flags, out IntPtr credential);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr credential);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CREDENTIAL
    {
        public int Flags;
        public int Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public long LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }

    /// Returns the credential blob of the given generic credential as UTF-8
    /// text, or null when the entry doesn't exist.
    public static string? ReadGeneric(string target)
    {
        if (!CredRead(target, CRED_TYPE_GENERIC, 0, out var handle)) return null;
        try
        {
            var cred = Marshal.PtrToStructure<CREDENTIAL>(handle);
            if (cred.CredentialBlob == IntPtr.Zero || cred.CredentialBlobSize == 0) return null;
            var bytes = new byte[cred.CredentialBlobSize];
            Marshal.Copy(cred.CredentialBlob, bytes, 0, bytes.Length);
            // Blobs written by different tools are either UTF-8 or UTF-16.
            var utf8 = Encoding.UTF8.GetString(bytes);
            if (utf8.Contains('�') || (bytes.Length > 1 && bytes[1] == 0))
                return Encoding.Unicode.GetString(bytes);
            return utf8;
        }
        catch { return null; }
        finally { CredFree(handle); }
    }
}
