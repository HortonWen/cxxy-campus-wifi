using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace CXXYNet
{
    static class Program
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool SetDllDirectory(string lpPathName);

        static string ExtractNativeLoader()
        {
            string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CXXYNet", "bin");
            Directory.CreateDirectory(dir);
            string loader = Path.Combine(dir, "WebView2Loader.dll");
            try
            {
                if (!File.Exists(loader))
                {
                    using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("CXXYNet.Res.Loader.dll"))
                    using (var f = File.Create(loader))
                        s.CopyTo(f);
                }
                SetDllDirectory(dir);
            }
            catch { }
            return dir;
        }

        static Assembly CurrentDomain_AssemblyResolve(object sender, ResolveEventArgs args)
        {
            string simpleName = new AssemblyName(args.Name).Name;
            string res = null;
            if (simpleName == "Microsoft.Web.WebView2.Core") res = "CXXYNet.Res.Core.dll";
            else if (simpleName == "Microsoft.Web.WebView2.WinForms") res = "CXXYNet.Res.WinForms.dll";
            if (res == null) return null;
            try
            {
                using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream(res))
                {
                    if (s == null) return null;
                    var bytes = new byte[s.Length];
                    s.Read(bytes, 0, bytes.Length);
                    return Assembly.Load(bytes);
                }
            }
            catch { return null; }
        }

        [STAThread]
        static void Main()
        {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            ExtractNativeLoader();
            AppDomain.CurrentDomain.AssemblyResolve += CurrentDomain_AssemblyResolve;
            Application.Run(new MainForm());
        }
    }

    public class MainForm : Form
    {
        const string UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";
        WebView2 webView;
        JavaScriptSerializer json = new JavaScriptSerializer();

        [DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        [DllImport("user32.dll")]
        static extern bool ReleaseCapture();

        [DllImport("user32.dll")]
        static extern IntPtr SendMessage(IntPtr hWnd, int msg, int wParam, int lParam);

        public MainForm()
        {
            Text = "成贤校园网助手";
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(580, 820);
            MinimumSize = new Size(500, 700);
            BackColor = Color.FromArgb(13, 18, 32);

            try
            {
                using (var iconStream = Assembly.GetExecutingAssembly().GetManifestResourceStream("CXXYNet.Res.Icon"))
                {
                    if (iconStream != null) Icon = new System.Drawing.Icon(iconStream);
                }
            }
            catch { }

            webView = new WebView2();
            webView.DefaultBackgroundColor = Color.FromArgb(13, 18, 32);
            webView.Bounds = new Rectangle(8, 8, ClientSize.Width - 16, ClientSize.Height - 16);
            webView.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            Controls.Add(webView);

            Shown += async (s, e) => { await InitWebViewAsync(); };
        }

        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            if (m.Msg == 0x84) // WM_NCHITTEST: 让无边框窗口可以拖边缩放
            {
                int sx = (short)(m.LParam.ToInt64() & 0xFFFF);
                int sy = (short)((m.LParam.ToInt64() >> 16) & 0xFFFF);
                var p = PointToClient(new Point(sx, sy));
                const int M = 8;
                bool l = p.X <= M, r = p.X >= ClientSize.Width - M, t = p.Y <= M, b = p.Y >= ClientSize.Height - M;
                if (l && t) m.Result = new IntPtr(13);
                else if (r && t) m.Result = new IntPtr(14);
                else if (l && b) m.Result = new IntPtr(16);
                else if (r && b) m.Result = new IntPtr(17);
                else if (l) m.Result = new IntPtr(10);
                else if (r) m.Result = new IntPtr(11);
                else if (t) m.Result = new IntPtr(12);
                else if (b) m.Result = new IntPtr(15);
            }
        }

        async Task InitWebViewAsync()
        {
            try
            {
                string userData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CXXYNet", "wv2");
                var env = await CoreWebView2Environment.CreateAsync(null, userData, null);
                await webView.EnsureCoreWebView2Async(env);
                webView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
                webView.CoreWebView2.Settings.AreDevToolsEnabled = false;
                webView.CoreWebView2.WebMessageReceived += OnWebMessage;
                webView.NavigateToString(LoadHtml());
                ApplyRoundedCorners();
            }
            catch (Exception ex)
            {
                MessageBox.Show("初始化失败：" + ex.Message + "\n\n请确认系统已安装 Microsoft Edge WebView2 运行时。",
                    "成贤校园网助手", MessageBoxButtons.OK, MessageBoxIcon.Error);
                Close();
            }
        }

        void ApplyRoundedCorners()
        {
            try { int pref = 2; DwmSetWindowAttribute(Handle, 33, ref pref, sizeof(int)); } catch { }
        }

        string LoadHtml()
        {
            using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("CXXYNet.Res.index.html"))
            using (var r = new StreamReader(s, Encoding.UTF8))
                return r.ReadToEnd();
        }

        void OnWebMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            try
            {
                var msg = json.Deserialize<Dictionary<string, object>>(e.WebMessageAsJson);
                HandleMessage(msg);
            }
            catch { }
        }

        string Get(Dictionary<string, object> m, string key)
        {
            object o;
            if (m != null && m.TryGetValue(key, out o) && o != null) return o.ToString();
            return "";
        }

        void Post(Dictionary<string, object> obj)
        {
            try { webView.CoreWebView2.PostWebMessageAsJson(json.Serialize(obj)); } catch { }
        }

        async void HandleMessage(Dictionary<string, object> msg)
        {
            switch (Get(msg, "t"))
            {
                case "load": LoadCredentialToUi(); break;
                case "win": WindowCommand(msg); break;
                case "openPortal": OpenPortal(); break;
                case "openSelf": OpenSelf(); break;
                case "clear": ClearCredential(); break;
                case "check": await CheckAsync(); break;
                case "connect": await ConnectOnlyAsync(Get(msg, "ssid")); break;
                case "autoLogin": await AutoLoginAsync(msg); break;
            }
        }

        void WindowCommand(Dictionary<string, object> msg)
        {
            string c = Get(msg, "c");
            if (c == "min") WindowState = FormWindowState.Minimized;
            else if (c == "close") Close();
            else if (c == "startMove")
            {
                ReleaseCapture();
                SendMessage(Handle, 0xA1, 2, 0); // WM_NCLBUTTONDOWN + HTCAPTION
            }
        }

        // ---------------- UI helpers ----------------
        void Log(string m, string cls = "")
        {
            var d = new Dictionary<string, object> { { "t", "progress" }, { "m", m } };
            if (!string.IsNullOrEmpty(cls)) d["cls"] = cls;
            Post(d);
        }

        void Status(string cls, string text)
        {
            Post(new Dictionary<string, object> { { "t", "status" }, { "cls", cls }, { "text", text } });
        }

        void Result()
        {
            Post(new Dictionary<string, object> { { "t", "result" } });
        }

        // ---------------- credentials (DPAPI) ----------------
        string CredFile { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CXXYNet", "cred.bin"); } }

        string[] ReadCredential()
        {
            try
            {
                if (!File.Exists(CredFile)) return null;
                byte[] enc = File.ReadAllBytes(CredFile);
                byte[] plain = ProtectedData.Unprotect(enc, null, DataProtectionScope.CurrentUser);
                string s = Encoding.UTF8.GetString(plain);
                var parts = s.Split(new[] { '\n' }, 3);
                if (parts.Length >= 2) return new[] { parts[0], parts[1], parts.Length >= 3 ? parts[2] : "校园内网" };
            }
            catch { }
            return null;
        }

        void SaveCredential(string user, string pass, string isp)
        {
            try
            {
                string dir = Path.GetDirectoryName(CredFile);
                Directory.CreateDirectory(dir);
                byte[] plain = Encoding.UTF8.GetBytes(user + "\n" + pass + "\n" + isp);
                byte[] enc = ProtectedData.Protect(plain, null, DataProtectionScope.CurrentUser);
                File.WriteAllBytes(CredFile, enc);
            }
            catch { }
        }

        void ClearCredential()
        {
            try { if (File.Exists(CredFile)) File.Delete(CredFile); } catch { }
            Post(new Dictionary<string, object> { { "t", "cleared" } });
        }

        void LoadCredentialToUi()
        {
            var c = ReadCredential();
            if (c != null)
            {
                Post(new Dictionary<string, object> { { "t", "cred" }, { "user", c[0] }, { "pass", c[1] }, { "isp", c[2] } });
            }
        }

        // ---------------- network ----------------
        void OpenPortal() { try { Process.Start(new ProcessStartInfo("http://cxxy.seu.edu.cn/") { UseShellExecute = true }); } catch { } }
        void OpenSelf() { try { Process.Start(new ProcessStartInfo("http://211.65.40.6:8080/Self") { UseShellExecute = true }); } catch { } }

        string RunNetsh(params string[] args)
        {
            try
            {
                var psi = new ProcessStartInfo("netsh", string.Join(" ", args.Select(a => "\"" + a + "\"")))
                {
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    StandardOutputEncoding = Encoding.GetEncoding(936)
                };
                using (var p = Process.Start(psi))
                {
                    string o = p.StandardOutput.ReadToEnd();
                    p.WaitForExit(15000);
                    return o;
                }
            }
            catch { return ""; }
        }

        string GetSsid()
        {
            string o = RunNetsh("wlan", "show", "interfaces");
            var m = Regex.Match(o, @"(?im)^\s*SSID\s*:\s*(.+?)\s*$");
            return m.Success ? m.Groups[1].Value.Trim() : "";
        }

        bool IsWlanConnected(string ssid)
        {
            string o = RunNetsh("wlan", "show", "interfaces");
            var s = Regex.Match(o, @"(?im)^\s*SSID\s*:\s*(.+?)\s*$");
            var st = Regex.Match(o, @"(?im)^\s*State\s*:\s*(.+?)\s*$");
            return s.Success && s.Groups[1].Value.Trim() == ssid && st.Success && st.Groups[1].Value.IndexOf("connected", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        bool ConnectWifi(string ssid)
        {
            if (IsWlanConnected(ssid)) return true;
            string profiles = RunNetsh("wlan", "show", "profiles");
            if (profiles.IndexOf(ssid, StringComparison.OrdinalIgnoreCase) < 0)
            {
                string esc = ssid.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;").Replace("'", "&apos;");
                string xml = "<?xml version=\"1.0\"?>\r\n<WLANProfile xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v1\">\r\n  <name>" + esc + "</name>\r\n  <SSIDConfig><SSID><name>" + esc + "</name></SSID></SSIDConfig>\r\n  <connectionType>ESS</connectionType>\r\n  <connectionMode>auto</connectionMode>\r\n  <MSM><security><authEncryption><authentication>open</authentication><encryption>none</encryption></authEncryption></security></MSM>\r\n</WLANProfile>";
                string tmp = Path.Combine(Path.GetTempPath(), "cxxy-wlan-" + Guid.NewGuid().ToString("N") + ".xml");
                File.WriteAllText(tmp, xml, Encoding.UTF8);
                RunNetsh("wlan", "add", "profile", "filename=" + tmp, "user=all");
                try { File.Delete(tmp); } catch { }
            }
            RunNetsh("wlan", "connect", "name=" + ssid, "ssid=" + ssid);
            for (int i = 0; i < 25; i++)
            {
                System.Threading.Thread.Sleep(800);
                if (IsWlanConnected(ssid)) return true;
            }
            return false;
        }

        class HttpResult { public int Status; public string FinalUrl; public string Body; public bool Success; }

        HttpResult Fetch(string url, string postData = null, string referer = null, int timeoutMs = 10000)
        {
            HttpResult r = new HttpResult { Status = 0, FinalUrl = url, Body = "", Success = false };
            try
            {
                var req = (HttpWebRequest)WebRequest.Create(url);
                req.UserAgent = UA;
                req.Timeout = timeoutMs;
                req.ReadWriteTimeout = timeoutMs;
                req.AllowAutoRedirect = true;
                req.MaximumAutomaticRedirections = 8;
                req.ServicePoint.Expect100Continue = false;
                if (referer != null) req.Referer = referer;
                if (postData != null)
                {
                    req.Method = "POST";
                    req.ContentType = "application/x-www-form-urlencoded";
                    byte[] b = Encoding.UTF8.GetBytes(postData);
                    req.ContentLength = b.Length;
                    using (var s = req.GetRequestStream()) s.Write(b, 0, b.Length);
                }
                try
                {
                    using (var resp = (HttpWebResponse)req.GetResponse())
                        return ReadResponse(resp, url);
                }
                catch (WebException ex)
                {
                    var er = ex.Response as HttpWebResponse;
                    if (er != null) return ReadResponse(er, url);
                    r.Success = false; r.FinalUrl = url; return r;
                }
            }
            catch { r.Success = false; r.FinalUrl = url; return r; }
        }

        HttpResult ReadResponse(HttpWebResponse resp, string fallback)
        {
            var r = new HttpResult();
            r.Status = (int)resp.StatusCode;
            r.FinalUrl = resp.ResponseUri != null ? resp.ResponseUri.ToString() : fallback;
            r.Success = r.Status >= 200 && r.Status < 400;
            try
            {
                using (var stream = resp.GetResponseStream())
                using (var sr = new StreamReader(stream, Encoding.UTF8))
                    r.Body = sr.ReadToEnd();
            }
            catch { r.Body = ""; }
            return r;
        }

        bool TestOnline()
        {
            var r1 = Fetch("http://connect.rom.miui.com/generate_204", null, null, 6000);
            if (r1.Status == 204) return true;
            var r2 = Fetch("http://www.msftconnecttest.com/connecttest.txt", null, null, 6000);
            if (r2.Success && r2.Body.Contains("Microsoft Connect Test")) return true;
            var r3 = Fetch("https://www.baidu.com/", null, null, 6000);
            if (r3.Success && r3.Body.Length > 0) return true;
            return false;
        }

        HttpResult GetPortalPage()
        {
            foreach (var u in new[] { "http://6.6.6.6/", "http://cxxy.seu.edu.cn/" })
            {
                var r = Fetch(u, null, null, 10000);
                if (r.Success && !string.IsNullOrWhiteSpace(r.Body)) return r;
            }
            return null;
        }

        string Attr(string tag, string name)
        {
            var m = Regex.Match(tag, "(?is)\\b" + Regex.Escape(name) + "\\s*=\\s*[\"']([^\"']*)[\"']");
            return m.Success ? m.Groups[1].Value : "";
        }

        string ResolveUrl(string baseUrl, string rel)
        {
            if (string.IsNullOrWhiteSpace(rel)) return baseUrl;
            if (rel.StartsWith("http://") || rel.StartsWith("https://")) return rel;
            var b = new Uri(baseUrl);
            if (rel.StartsWith("/")) return b.Scheme + "://" + b.Authority + rel;
            string path = b.AbsolutePath;
            int idx = path.LastIndexOf('/');
            path = idx < 0 ? "/" : path.Substring(0, idx + 1);
            return b.Scheme + "://" + b.Authority + path + rel;
        }

        string UrlEncode(string s) { return Uri.EscapeDataString(s ?? ""); }

        bool SubmitForm(HttpResult portal, string user, string pass, string isp, out string detail)
        {
            detail = "";
            string html = portal.Body ?? "";
            var forms = Regex.Matches(html, "(?is)<form\\b[^>]*>.*?</form\\s*>");
            foreach (Match fm in forms)
            {
                var open = Regex.Match(fm.Value, "(?is)<form\\b[^>]*>").Value;
                string action = Attr(open, "action");
                string inner = Regex.Replace(fm.Value, "(?is)^.*?<form\\b[^>]*>", "");
                inner = Regex.Replace(inner, "(?is)</form\\s*>.*$", "");

                var fields = new Dictionary<string, string>();
                string passwordName = "";
                var textNames = new List<string>();
                string selectName = "";
                var selectOptions = new List<KeyValuePair<string, string>>();

                foreach (Match ctrl in Regex.Matches(inner, "(?is)<(input|select|textarea)\\b[^>]*>"))
                {
                    string tag = ctrl.Value;
                    string type = Attr(tag, "type");
                    string name = Attr(tag, "name");
                    string value = Attr(tag, "value");
                    if (type.ToLower() == "hidden") { if (name != "") fields[name] = value; continue; }
                    if (type.ToLower() == "password") { passwordName = name; fields[name] = pass; continue; }
                    if (Regex.IsMatch(type, "(?i)submit|button|image|reset")) continue;
                    if (tag.StartsWith("<select", StringComparison.OrdinalIgnoreCase))
                    {
                        selectName = name;
                        var sel = Regex.Match(inner, "(?is)<select\\b[^>]*name\\s*=\\s*[\"']" + Regex.Escape(name) + "[\"'][^>]*>(.*?)</select\\s*>");
                        if (sel.Success)
                        {
                            foreach (Match o in Regex.Matches(sel.Groups[1].Value, "(?is)<option\\b[^>]*value\\s*=\\s*[\"']([^\"']*)[\"'][^>]*>(.*?)</option\\s*>"))
                            {
                                string txt = Regex.Replace(o.Groups[2].Value, "(?s)<.*?>", "").Trim();
                                selectOptions.Add(new KeyValuePair<string, string>(o.Groups[1].Value, txt));
                            }
                        }
                        continue;
                    }
                    if (name != "") { textNames.Add(name); fields[name] = value; }
                }

                if (passwordName == "") continue;

                string userField = "";
                foreach (var n in textNames)
                    if (Regex.IsMatch(n, "(?i)(user|name|account|login|id|mobile|phone|uname|ddd)")) { userField = n; break; }
                if (userField == "" && textNames.Count >= 1) userField = textNames[0];
                if (userField != "") fields[userField] = user;

                if (selectName != "" && !string.IsNullOrEmpty(isp))
                {
                    string val = "";
                    foreach (var o in selectOptions)
                        if (o.Value.IndexOf(isp, StringComparison.OrdinalIgnoreCase) >= 0) { val = o.Key; break; }
                    if (val == "" && selectOptions.Count > 0) val = selectOptions[0].Key;
                    if (val != "") fields[selectName] = val;
                }

                string postUri = ResolveUrl(portal.FinalUrl, action);
                string body = string.Join("&", fields.Select(kv => UrlEncode(kv.Key) + "=" + UrlEncode(kv.Value)));
                var resp = Fetch(postUri, body, portal.FinalUrl, 12000);
                detail = "已按认证页表单提交";
                if (resp.Success) return true;
                detail = "表单提交失败: HTTP " + resp.Status;
            }
            return false;
        }

        string[] GetLanInfo()
        {
            string ip = "", mac = "";
            try
            {
                var nics = NetworkInterface.GetAllNetworkInterfaces()
                    .Where(n => n.OperationalStatus == OperationalStatus.Up &&
                                n.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
                                n.NetworkInterfaceType != NetworkInterfaceType.Tunnel)
                    .OrderBy(n => (n.NetworkInterfaceType == NetworkInterfaceType.Wireless80211 ? 0 : 1));
                foreach (var nic in nics)
                {
                    foreach (var addr in nic.GetIPProperties().UnicastAddresses)
                    {
                        if (addr.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork &&
                            !addr.Address.ToString().StartsWith("169.254."))
                        {
                            ip = addr.Address.ToString();
                            mac = string.Concat(nic.GetPhysicalAddress().GetAddressBytes().Select(b => b.ToString("X2")));
                            return new[] { ip, mac };
                        }
                    }
                }
            }
            catch { }
            return new[] { ip, mac };
        }

        string Query(string url, string key)
        {
            var m = Regex.Match(url, "(?i)[?&]" + Regex.Escape(key) + "=([^&]*)");
            return m.Success ? Uri.UnescapeDataString(m.Groups[1].Value) : "";
        }

        bool TryDrcom(HttpResult portal, string user, string pass, out string detail)
        {
            detail = "";
            try
            {
                var b = new Uri(portal.FinalUrl);
                var lan = GetLanInfo();
                string ip = Query(portal.FinalUrl, "wlan_user_ip"); if (ip == "") ip = lan[0];
                string mac = Query(portal.FinalUrl, "wlan_user_mac"); if (mac == "") mac = lan[1];
                string ac = Query(portal.FinalUrl, "wlan_ac_ip");
                string q = "c=Portal&a=login&callback=dr1003&login_method=1&user_account=" + UrlEncode(user) +
                           "&user_password=" + UrlEncode(pass) + "&wlan_user_ip=" + UrlEncode(ip) +
                           "&wlan_user_ipv6=&wlan_user_mac=" + UrlEncode(mac) + "&wlan_ac_ip=" + UrlEncode(ac) +
                           "&wlan_ac_name=&jsVersion=3.3.3&v=10000";
                foreach (var port in new[] { 801, 80, 8080 })
                {
                    string url = "http://" + b.Host + ":" + port + "/eportal/?" + q;
                    var r = Fetch(url, null, portal.FinalUrl, 10000);
                    if (r.Body.Contains("\"result\":\"1\"") || Regex.IsMatch(r.Body, "result[\"']?\\s*[:=]\\s*[\"']?1"))
                    {
                        detail = "Dr.COM ePortal 登录成功 (端口 " + port + ")";
                        return true;
                    }
                }
            }
            catch { }
            detail = "Dr.COM ePortal 接口尝试未成功";
            return false;
        }

        async Task ConnectOnlyAsync(string ssid)
        {
            if (ssid == "") ssid = "Student_CX";
            Log("正在连接 " + ssid + " …");
            bool ok = await Task.Run(() => ConnectWifi(ssid));
            if (ok) { Log("已连上 " + ssid, "ok"); Status("busy", "已连接，正在检查认证…"); }
            else { Log("连接失败，请确认能搜到该信号", "err"); Status("err", "连接失败"); }
            Result();
        }

        async Task CheckAsync()
        {
            var ssid = await Task.Run(() => GetSsid());
            bool online = await Task.Run(() => TestOnline());
            Log("当前无线: " + (ssid == "" ? "未连接" : ssid));
            if (online) { Log("网络状态: 已通过认证，可以上网", "ok"); Status("ok", "已通过认证，可正常上网"); }
            else { Log("网络状态: 未认证或无法访问外网", "err"); Status("err", "未认证，需要登录"); }
            Result();
        }

        async Task AutoLoginAsync(Dictionary<string, object> msg)
        {
            string ssid = Get(msg, "ssid"); if (ssid == "") ssid = "Student_CX";
            string user = Get(msg, "user");
            string pass = Get(msg, "pass");
            string isp = Get(msg, "isp"); if (isp == "") isp = "校园内网";
            bool remember = Get(msg, "remember") == "True" || Get(msg, "remember") == "true";

            if (user == "" || pass == "")
            {
                Log("缺少账号或密码，无法自动登录", "err");
                Status("err", "请填写账号和密码");
                Result(); return;
            }
            if (remember) SaveCredential(user, pass, isp);

            Log("正在连接 " + ssid + " …");
            bool connected = await Task.Run(() => ConnectWifi(ssid));
            if (!connected) { Log("连接失败", "err"); Status("err", "连接失败"); OpenPortal(); Result(); return; }
            Log("已连上 " + ssid, "ok");

            bool online = await Task.Run(() => TestOnline());
            if (online) { Log("当前已通过认证，可直接上网", "ok"); Status("ok", "已通过认证，可正常上网"); Result(); return; }

            Log("获取认证页面 …");
            var portal = await Task.Run(() => GetPortalPage());
            if (portal == null)
            {
                Log("无法读取认证页，已打开登录页请手动登录", "err");
                Status("err", "已打开登录页");
                OpenPortal(); Result(); return;
            }
            Log("认证页地址: " + portal.FinalUrl);

            Status("busy", "正在自动登录…");
            bool ok1 = await Task.Run(() => { string d; return SubmitForm(portal, user, pass, isp, out d); });
            if (ok1)
            {
                await Task.Delay(1500);
                online = await Task.Run(() => TestOnline());
                if (online) { Log("自动登录成功，网络已通", "ok"); Status("ok", "登录成功，可正常上网"); Result(); return; }
            }

            bool ok2 = await Task.Run(() => { string d; return TryDrcom(portal, user, pass, out d); });
            if (ok2)
            {
                await Task.Delay(1500);
                online = await Task.Run(() => TestOnline());
                if (online) { Log("Dr.COM 自动登录成功，网络已通", "ok"); Status("ok", "登录成功，可正常上网"); Result(); return; }
            }

            Log("自动登录未成功，已打开认证页，请手动登录", "err");
            Status("err", "需手动登录");
            OpenPortal();
            Result();
        }
    }
}
