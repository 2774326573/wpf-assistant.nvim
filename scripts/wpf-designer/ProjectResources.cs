using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Markup;
using System.Xml.Linq;

namespace ICSharpCode.XamlDesigner
{
    internal static class ProjectResources
    {
        static bool loaded;
        static ResourceDictionary projectDictionary;
        internal static void Apply(object view)
        {
            if (view is not FrameworkElement root || projectDictionary == null) return;
            root.Resources.MergedDictionaries.Add(projectDictionary);
            File.AppendAllText(Path.Combine(Path.GetTempPath(), "nvim-wpf-resources.log"), "Root=" + root.GetType().FullName + " Background=" + root.TryFindResource("ApplicationBackgroundBrush") + Environment.NewLine);
            if (root is System.Windows.Controls.Page || root is ICSharpCode.WpfDesign.Designer.Controls.PageClone)
            {
                root.SetResourceReference(System.Windows.Controls.Page.BackgroundProperty, "ApplicationBackgroundBrush");
                root.SetResourceReference(System.Windows.Controls.Page.ForegroundProperty, "TextFillColorPrimaryBrush");
            }
        }
        internal static string Prepare(string text)
        {
            var assemblyPath = Environment.GetEnvironmentVariable("NVIM_WPF_ASSEMBLY");
            var appPath = Environment.GetEnvironmentVariable("NVIM_WPF_APP_XAML");
            if (string.IsNullOrEmpty(assemblyPath)) return text;
            var name = AssemblyName.GetAssemblyName(assemblyPath).Name;
            if (!loaded && File.Exists(appPath))
            {
                loaded = true;
                try
                {
                    var app = XElement.Load(appPath);
                    var dictionary = app.Descendants().FirstOrDefault(x => x.Name.LocalName == "ResourceDictionary");
                    if (dictionary != null)
                    {
                        foreach (var attr in app.Attributes().Where(a => a.IsNamespaceDeclaration))
                            if (dictionary.Attribute(attr.Name) == null) dictionary.SetAttributeValue(attr.Name, attr.Value);
                        foreach (var attr in dictionary.DescendantsAndSelf().Attributes().Where(a => a.IsNamespaceDeclaration).ToList())
                            if (attr.Value.StartsWith("clr-namespace:") && !attr.Value.Contains(";assembly=")) attr.Value += ";assembly=" + name;
                        var internalResources = new System.Collections.Generic.Dictionary<string, object>();
                        foreach (var element in dictionary.DescendantsAndSelf().ToList())
                        {
                            if (element.Name.NamespaceName.StartsWith("clr-namespace:") && !element.Name.NamespaceName.Contains(";assembly=")) element.Name = XName.Get(element.Name.LocalName, element.Name.NamespaceName + ";assembly=" + name);
                            if (element.Name.NamespaceName == "http://schemas.microsoft.com/winfx/2006/xaml/presentation") continue;
                            foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
                            {
                                var mapping = asm.GetCustomAttributes<XmlnsDefinitionAttribute>().FirstOrDefault(a => a.XmlNamespace == element.Name.NamespaceName && asm.GetType(a.ClrNamespace + "." + element.Name.LocalName) != null);
                                if (mapping != null) { element.Name = XName.Get(element.Name.LocalName, "clr-namespace:" + mapping.ClrNamespace + ";assembly=" + asm.GetName().Name); break; }
                            }
                        }
                        foreach (var element in dictionary.Elements().ToList())
                        {
                            var ns = element.Name.NamespaceName;
                            if (!ns.StartsWith("clr-namespace:")) continue;
                            var parts = ns.Substring(14).Split(new[] { ";assembly=" }, StringSplitOptions.None);
                            if (parts.Length != 2) continue;
                            var type = Assembly.Load(parts[1]).GetType(parts[0] + "." + element.Name.LocalName);
                            var key = (string)element.Attribute(XName.Get("Key", "http://schemas.microsoft.com/winfx/2006/xaml"));
                            if (type != null && !type.IsPublic && key != null && !element.HasElements && element.Attributes().All(a => a.IsNamespaceDeclaration || a.Name.LocalName == "Key"))
                            { internalResources[key] = Activator.CreateInstance(type, true); element.Remove(); }
                        }
                        var context = new ParserContext { BaseUri = new Uri("pack://application:,,,/" + name + ";component/") };
                        var resources = (ResourceDictionary)XamlReader.Parse(dictionary.ToString(), context);
                        foreach (var item in internalResources) resources[item.Key] = item.Value;
                        projectDictionary = resources;
                        Application.Current.Resources.MergedDictionaries.Add(resources);
                        File.AppendAllText(Path.Combine(Path.GetTempPath(), "nvim-wpf-resources.log"), "Loaded resources: " + appPath + Environment.NewLine);
                    }
                }
                catch (Exception ex)
                {
                    File.AppendAllText(Path.Combine(Path.GetTempPath(), "nvim-wpf-resources.log"), ex + Environment.NewLine);
                }
            }
            return text.Replace("pack://application:,,,/Assets/", "pack://application:,,,/" + name + ";component/Assets/");
        }
    }
}
