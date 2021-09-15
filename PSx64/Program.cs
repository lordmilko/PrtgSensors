using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Xml.Linq;

namespace PSx64
{
    class Program
    {
        static void Main(string[] args)
        {
            if (args.Length < 1)
                Error("Please specify a script to execute");
            else
            {
                Directory.SetCurrentDirectory("C:\\Program Files (x86)\\PRTG Network Monitor\\Custom Sensors\\EXEXML");

                var arguments = $"-file {args[0]}";

                if (args.Length > 1)
                {
                    var temp = args.Skip(1);

                    arguments += " \"" + string.Join("\" \"", temp) + "\"";
                }

                var info = new ProcessStartInfo("powershell", arguments)
                {
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };

                using (var process = Process.Start(info))
                {
                    if (process == null)
                    {
                        Error($"Could not start PowerShell with arguments {arguments}");
                    }
                    else
                    {
                        using (var o = process.StandardOutput)
                        using (var e = process.StandardError)
                        {
                            var @out = o.ReadToEnd();
                            var err = e.ReadToEnd();

                            if (err != string.Empty)
                            {
                                Error(err);
                            }
                            else
                            {
                                Console.Write(@out);
                            }
                        }
                    }
                }
            }
        }

        static void Error(string message)
        {
            var xml = new XElement("Prtg",
                new XElement("Error", 1),
                new XElement("Text", message)
            );

            Console.Write(xml);
        }
    }
}
