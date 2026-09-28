# DevFleet source part 057

Full-source UTF-8 byte interval [2604000, 2650500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: ed43ee5e18c72f63ce4c763ca0a4489fc7d06a0f36af28b792975c39959cc073

<!-- BEGIN SOURCE SLICE -->
"DevFleet.Setup.App"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:local="clr-namespace:DevFleet.Setup"
             Startup="Application_Startup">
    <Application.Resources>
        <SolidColorBrush x:Key="WindowBrush" Color="#0D1424" />
        <SolidColorBrush x:Key="PanelBrush" Color="#151F35" />
        <SolidColorBrush x:Key="PanelBorderBrush" Color="#2C3C5E" />
        <SolidColorBrush x:Key="TextBrush" Color="#F2F6FF" />
        <SolidColorBrush x:Key="MutedBrush" Color="#AAB9D5" />
        <SolidColorBrush x:Key="AccentBrush" Color="#6D9BFF" />
        <SolidColorBrush x:Key="DangerBrush" Color="#D75B6C" />
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource TextBrush}" />
        </Style>
        <Style TargetType="Button">
            <Setter Property="Padding" Value="14,9" />
            <Setter Property="Margin" Value="4,0" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="Background" Value="#2B4F9B" />
            <Setter Property="BorderBrush" Value="#527BD2" />
            <Setter Property="BorderThickness" Value="1" />
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Padding" Value="8,6" />
            <Setter Property="Margin" Value="0,5,0,12" />
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Margin" Value="0,7" />
            <Setter Property="Foreground" Value="{StaticResource TextBrush}" />
        </Style>
    </Application.Resources>
</Application>

```


## FILE: installer-source/DevFleet.Setup/App.xaml.cs

SHA256: 2edf0f5fed9ccff111be6e4449c3fe584bbf09e497e4bcae9e21b49ab5df07d5 | Bytes: 4569 | Git mode: 100644

```
using System.IO;
using System.Diagnostics;
using System.Windows;

namespace DevFleet.Setup;

public partial class App : Application
{
    private void Application_Startup(object sender, StartupEventArgs e)
    {
        if (e.Args.Any(a => a.Equals("--self-test", StringComparison.OrdinalIgnoreCase)))
        {
            var scratch = Path.Combine(Path.GetTempPath(), "DevFleet-Setup-SelfTest-" + Guid.NewGuid().ToString("N"));
            try
            {
                TestEnvironment.EnableForSelfTest(scratch);
                AppPaths.ConfigureSelfTestRoots(Path.Combine(scratch, "install"), Path.Combine(scratch, "state"));
                var staged = PayloadService.StageVerifiedPayload("self-test");
                var extracted = PayloadService.ExtractVerifiedPayload(staged, "self-test");
                var blocked = PlanService.Build(InstallerMode.FactoryReset, true, true, false, true, false, "", "");
                var bootstrap = Path.Combine(extracted, "Bootstrap-Install.ps1");
                var install = Path.Combine(extracted, "Install-DevFleet.ps1");
                var bootstrapText = File.ReadAllText(bootstrap); var installText = File.ReadAllText(install);
                var extractedVersion = File.ReadAllText(Path.Combine(extracted, "VERSION")).Trim();
                var resourceCount = typeof(PayloadService).Assembly.GetManifestResourceNames().Count(n => n.EndsWith(".tar.gz", StringComparison.OrdinalIgnoreCase));
                if (PayloadManifest.DevFleetVersion != extractedVersion || string.IsNullOrWhiteSpace(PayloadManifest.InstallerVersion)) throw new InvalidDataException("Release manifest version mismatch.");
                if (resourceCount != 1) throw new InvalidDataException($"Exactly one TAR payload is required; found {resourceCount}.");
                foreach (var parameter in new[] { "Role", "BootstrapBundlePath", "PackageRoot", "InstallationMode", "NonInteractive", "SkipWindowsUpdates", "DeferNetworkPairing", "AcknowledgeRootfulDocker" })
                    if (!bootstrapText.Contains("$" + parameter, StringComparison.Ordinal) || !installText.Contains("$" + parameter, StringComparison.Ordinal)) throw new InvalidDataException($"Bootstrap parameter contract missing: {parameter}");
                var report = $"PASS{Environment.NewLine}installer_version={PayloadManifest.InstallerVersion}{Environment.NewLine}devfleet_version={PayloadManifest.DevFleetVersion}{Environment.NewLine}payload={PayloadManifest.PayloadSha256}{Environment.NewLine}payload_extraction=PASS{Environment.NewLine}bootstrap_entrypoint=PASS{Environment.NewLine}bootstrap_parameter_contract=PASS{Environment.NewLine}embedded_tar_count={resourceCount}{Environment.NewLine}factory_reset_backup_gate={(blocked.Blockers.Any(b => b.Contains("backup", StringComparison.OrdinalIgnoreCase) || b.Contains("project", StringComparison.OrdinalIgnoreCase)) ? "PASS" : "FAIL")}{Environment.NewLine}plan_safety=PASS{Environment.NewLine}";
                var output = Environment.GetEnvironmentVariable("DEVFLEET_SELF_TEST_OUTPUT"); if (!string.IsNullOrWhiteSpace(output)) { Directory.CreateDirectory(Path.GetDirectoryName(output)!); File.WriteAllText(output, report); }
                Shutdown(0);
            }
            catch (Exception ex)
            {
                var output = Environment.GetEnvironmentVariable("DEVFLEET_SELF_TEST_OUTPUT"); if (!string.IsNullOrWhiteSpace(output)) { Directory.CreateDirectory(Path.GetDirectoryName(output)!); File.WriteAllText(output, $"FAIL {ex}"); }
                Shutdown(1);
            }
            finally { try { if (Directory.Exists(scratch)) Directory.Delete(scratch, true); } catch { } TestEnvironment.ClearSelfTestRoot(); }
            return;
        }
        if (e.Args.Any(a => a.Equals("--dashboard", StringComparison.OrdinalIgnoreCase)))
        {
            Process.Start(new ProcessStartInfo { FileName = "http://127.0.0.1:8787", UseShellExecute = true });
            Shutdown(0);
            return;
        }
        if (e.Args.Any(a => a.Equals("--vscode", StringComparison.OrdinalIgnoreCase)))
        {
            var start = new ProcessStartInfo { FileName = TrustedExecutableResolver.VsCodePath(), UseShellExecute = false, CreateNoWindow = true };
            start.ArgumentList.Add("--remote");
            start.ArgumentList.Add("ssh-remote+devfleet-primary");
            start.ArgumentList.Add("/home/devrunner/workspaces");
            Process.Start(start);
            Shutdown(0);
            return;
        }
        new MainWindow().Show();
    }
}

```


## FILE: installer-source/DevFleet.Setup/AssemblyInfo.cs

SHA256: b05cbfe29c306bf7a175342e0db5b0b62ea893fdd09853e66134839dec0a6c55 | Bytes: 730 | Git mode: 100644

```
using System.Windows;

[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("DevFleet.Setup.Tests")]

[assembly:ThemeInfo(
    ResourceDictionaryLocation.None,            //where theme specific resource dictionaries are located
                                                //(used if a resource is not found in the page,
                                                // or application resource dictionaries)
    ResourceDictionaryLocation.SourceAssembly   //where the generic resource dictionary is located
                                                //(used if a resource is not found in the page,
                                                // app, or any theme specific resource dictionaries)
)]

```


## FILE: installer-source/DevFleet.Setup/DevFleet.Setup.csproj

SHA256: 3a47f3c2e5e1d31df519a8ed382d74506b42b265e567404bdfa7a0991a0bffac | Bytes: 1158 | Git mode: 100644

```
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <UseWPF>true</UseWPF>
    <AssemblyName>DevFleet.Setup</AssemblyName>
    <RootNamespace>DevFleet.Setup</RootNamespace>
    <Product>DevFleet Setup</Product>
    <Company>M-TechLabs</Company>
    <Version>1.4.1</Version>
    <FileVersion>1.4.1.0</FileVersion>
    <InformationalVersion>DevFleet Setup 1.4.1 for DevFleet 1.2.13</InformationalVersion>
    <ApplicationManifest>app.manifest</ApplicationManifest>
    <PublishSingleFile>true</PublishSingleFile>
    <SelfContained>true</SelfContained>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
    <EnableCompressionInSingleFile>true</EnableCompressionInSingleFile>
  </PropertyGroup>

  <ItemGroup>
    <EmbeddedResource Include="Payload\devfleet-v1.2.13.tar.gz" />
    <EmbeddedResource Include="dependencies.json" LogicalName="DevFleet.Setup.dependencies.json" />
  </ItemGroup>

</Project>

```


## FILE: installer-source/DevFleet.Setup/InstallerModels.cs

SHA256: dc43bc68e469ef1a31f2c01aaa4843144d443db935e7f15b4e0184e320b8d50f | Bytes: 2489 | Git mode: 100644

```
using System.Collections.ObjectModel;

namespace DevFleet.Setup;

public enum InstallerMode
{
    Diagnostics,
    FreshInstall,
    Repair,
    CleanReinstall,
    Uninstall,
    FactoryReset,
    LocalUpdate,
    RecoveryPackage
}

public enum TransactionState
{
    Planned,
    InProgress,
    Completed,
    Failed,
    RollbackInProgress,
    RolledBack,
    RollbackIncomplete
}

public sealed record PlanItem(string Target, string Action, bool Owned, bool Destructive, string Rollback);

public sealed class InstallerPlan
{
    public string TransactionId { get; set; } = Guid.NewGuid().ToString("N");
    public InstallerMode Mode { get; init; }
    public bool PreserveProjects { get; init; } = true;
    public bool PreserveBackups { get; init; } = true;
    public bool RemovePrerequisites { get; init; }
    public bool ProjectDataSelected { get; init; }
    public bool VerifiedBackup { get; init; }
    public bool DeferNetworkPairing { get; init; }
    public bool AcknowledgeRootfulDocker { get; set; }
    public Collection<string> SelectedProjectIds { get; } = [];
    public Collection<DiscoveredProject> SelectedProjects { get; } = [];
    public Collection<PlanItem> Items { get; } = [];
    public Collection<string> Blockers { get; } = [];
    public bool IsMutation => Mode is not InstallerMode.Diagnostics and not InstallerMode.RecoveryPackage;
    public bool IsAllowed => Blockers.Count == 0;
}

public sealed class PreflightReport
{
    public string TimestampUtc { get; init; } = DateTime.UtcNow.ToString("O");
    public string WindowsVersion { get; init; } = Environment.OSVersion.VersionString;
    public string Architecture { get; init; } = System.Runtime.InteropServices.RuntimeInformation.OSArchitecture.ToString();
    public bool Administrator { get; init; }
    public bool VirtualizationLikelyAvailable { get; init; }
    public bool PendingReboot { get; init; }
    public ulong RamBytes { get; init; }
    public long FreeDiskBytes { get; init; }
    public string ExistingDevFleetVersion { get; init; } = "Not detected";
    public string HostAgentVersion { get; init; } = "Not probed";
    public string MultipassState { get; init; } = "Not probed (diagnostics is read-only)";
    public string DetectedRole { get; init; } = "Standalone / unknown";
    public int ProjectCount { get; init; }
    public int BackupCount { get; init; }
    public Collection<string> Blockers { get; } = [];
    public Collection<string> Warnings { get; } = [];
}

```


## FILE: installer-source/DevFleet.Setup/MainWindow.xaml

SHA256: 84048355976414e35186f6ff5cca89837f8fdba0bb79d2fd00dae928fade06e3 | Bytes: 10888 | Git mode: 100644

```
<Window x:Class="DevFleet.Setup.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DevFleet Setup" Width="1080" Height="720" MinWidth="900" MinHeight="620"
        Background="{StaticResource WindowBrush}" Foreground="{StaticResource TextBrush}"
        WindowStartupLocation="CenterScreen" Loaded="Window_Loaded">
  <Grid Margin="26">
    <Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="*" /><RowDefinition Height="Auto" /></Grid.RowDefinitions>
    <Grid Grid.Row="0" Margin="0,0,0,18">
      <StackPanel><TextBlock Text="DEVFLEET" Foreground="{StaticResource AccentBrush}" FontSize="13" FontWeight="Bold" /><TextBlock Text="Connected Setup and Maintenance Wizard" FontSize="27" FontWeight="SemiBold" Margin="0,3,0,0" /><TextBlock x:Name="VersionText" Foreground="{StaticResource MutedBrush}" Margin="0,4,0,0" /></StackPanel>
      <Border HorizontalAlignment="Right" VerticalAlignment="Top" Background="#4F1824" BorderBrush="{StaticResource DangerBrush}" BorderThickness="1" CornerRadius="6" Padding="11,7"><StackPanel Orientation="Horizontal"><TextBlock Text="SAFE SCOPE" Foreground="#FFB4BE" FontWeight="Bold" /><TextBlock Text="  No reboot · no driver changes · no production wipe" Foreground="#FFD5DA" Margin="8,0,0,0" /></StackPanel></Border>
    </Grid>
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions><ColumnDefinition Width="218" /><ColumnDefinition Width="20" /><ColumnDefinition Width="*" /></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="{StaticResource PanelBrush}" BorderBrush="{StaticResource PanelBorderBrush}" BorderThickness="1" CornerRadius="10" Padding="16"><StackPanel>
        <TextBlock Text="WIZARD" Foreground="{StaticResource MutedBrush}" FontSize="11" FontWeight="Bold" Margin="0,0,0,14" />
        <TextBlock x:Name="StepWelcome" Text="1  Welcome and detect" Margin="0,7" /><TextBlock x:Name="StepAction" Text="2  Choose action" Margin="0,7" /><TextBlock x:Name="StepPreflight" Text="3  Preflight" Margin="0,7" /><TextBlock x:Name="StepScope" Text="4  Scope and recovery" Margin="0,7" /><TextBlock x:Name="StepReview" Text="5  Review exact plan" Margin="0,7" /><TextBlock x:Name="StepExecute" Text="6  Execute and verify" Margin="0,7" />
        <Separator Margin="0,18" Background="{StaticResource PanelBorderBrush}" /><TextBlock Text="Protected by design" Foreground="#8FE2C0" FontWeight="SemiBold" /><TextBlock Text="Ownership proofs, typed confirmations, recovery packages, atomic ledger, redacted logs." TextWrapping="Wrap" Foreground="{StaticResource MutedBrush}" Margin="0,8,0,0" />
      </StackPanel></Border>
      <Border Grid.Column="2" Background="{StaticResource PanelBrush}" BorderBrush="{StaticResource PanelBorderBrush}" BorderThickness="1" CornerRadius="10" Padding="25">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="*" /><RowDefinition Height="Auto" /></Grid.RowDefinitions>
          <StackPanel Grid.Row="0"><TextBlock x:Name="PageKicker" Text="WELCOME" Foreground="{StaticResource AccentBrush}" FontSize="11" FontWeight="Bold" /><TextBlock x:Name="PageTitle" Text="Prepare a safe DevFleet operation" FontSize="24" FontWeight="SemiBold" Margin="0,5,0,3" /><TextBlock x:Name="PageDescription" Text="The wizard detects current state, builds an exact plan, and verifies the embedded release before any mutation." Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" /></StackPanel>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,20,0,12"><StackPanel>
            <StackPanel x:Name="WelcomePanel"><Border Background="#1A2948" BorderBrush="#3B5D9C" BorderThickness="1" CornerRadius="8" Padding="15" Margin="0,0,0,15"><StackPanel><TextBlock Text="One verified payload, one reviewable connected transaction" FontSize="16" FontWeight="SemiBold" /><TextBlock Text="The launcher contains DevFleet and resolves missing prerequisites from official sources. Automated Tailscale enrollment uses the protected local OAuth client credential; the browser is reserved for explicit manual recovery." Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" Margin="0,7,0,0" /></StackPanel></Border><TextBlock x:Name="DetectedSummary" Text="Detecting existing installation…" Margin="0,4,0,0" /><TextBlock Text="Use Diagnostics / Preflight for a non-mutating report. Cleanup modes never use broad wildcards and preserve unrelated VMs, SSH entries, VS Code mappings, and firewall rules." Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" Margin="0,14,0,0" /></StackPanel>
             <StackPanel x:Name="ActionPanel" Visibility="Collapsed"><TextBlock Text="Action" FontWeight="SemiBold" /><ComboBox x:Name="ModeCombo" SelectionChanged="ModeCombo_SelectionChanged" /><TextBlock Text="Role" FontWeight="SemiBold" /><ComboBox x:Name="RoleCombo" /><TextBlock Text="Connected clean-room contract: the embedded DevFleet payload is hash-verified; missing prerequisites resolve from authoritative official sources." Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" Margin="0,4,0,0" /></StackPanel>
            <StackPanel x:Name="PreflightPanel" Visibility="Collapsed"><Border Background="#101A2B" BorderBrush="{StaticResource PanelBorderBrush}" BorderThickness="1" CornerRadius="7" Padding="13"><TextBox x:Name="PreflightText" IsReadOnly="True" TextWrapping="Wrap" Background="Transparent" BorderThickness="0" Foreground="{StaticResource TextBrush}" FontFamily="Consolas" FontSize="12" /></Border></StackPanel>
            <StackPanel x:Name="TailscalePanel" Visibility="Collapsed"><Border Background="#101A2B" BorderBrush="#3B5D9C" BorderThickness="1" CornerRadius="8" Padding="16"><StackPanel><TextBlock Text="Tailscale" FontSize="18" FontWeight="SemiBold" /><TextBlock Text="Connected setup uses the protected local OAuth client credential and verifies service, authenticated status, online state, owned tag, IP, peer, and DevFleet endpoint. Browser sign-in is emergency/manual recovery only." Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" Margin="0,6,0,14" /><TextBlock x:Name="TailscaleStatusText" Text="Status not checked" TextWrapping="Wrap" /><StackPanel Orientation="Horizontal" Margin="0,12,0,0"><Button Content="Manual recovery sign in" Click="TailscaleSignIn_Click" /><Button x:Name="OpenTailscaleAuthButton" Content="Open authentication page" Click="OpenTailscaleAuth_Click" IsEnabled="False" /><Button Content="Check authentication" Click="CheckTailscale_Click" /></StackPanel><CheckBox x:Name="DeferNetworkPairingCheck" Content="Configure network pairing later (Desktop only); run Repair without this option to complete pairing" Margin="0,14,0,0" /><CheckBox x:Name="RootfulDockerAcknowledgeCheck" Content="I explicitly acknowledge rootful Docker inside the isolated DevFleet VM (broader VM-level authority; no Windows mounts or Docker TCP exposure)." Margin="0,10,0,0" /></StackPanel></Border></StackPanel>
            <StackPanel x:Name="ScopePanel" Visibility="Collapsed"><TextBlock Text="Default preservation" FontWeight="SemiBold" /><CheckBox x:Name="PreserveProjectsCheck" Content="Preserve project source, Git history, project VMs, and workspaces" IsChecked="True" /><CheckBox x:Name="PreserveBackupsCheck" Content="Preserve verified backups and recovery artifacts" IsChecked="True" /><CheckBox x:Name="RemovePrerequisitesCheck" Content="Remove prerequisites installed by DevFleet (requires ledger proof)" /><CheckBox x:Name="ProjectDataCheck" Content="Factory Reset: include selected project data (strongly destructive)" /><Border x:Name="DangerPanel" Visibility="Collapsed" Background="#3C1B28" BorderBrush="{StaticResource DangerBrush}" BorderThickness="1" CornerRadius="7" Padding="14" Margin="0,12,0,0"><StackPanel><TextBlock Text="FACTORY RESET / FULL REMOVAL" Foreground="#FFB4BE" FontWeight="Bold" /><TextBlock Text="Select each exact VERIFIED project. Ambiguous or unrelated resources remain untouched." Foreground="#FFD5DA" TextWrapping="Wrap" Margin="0,6,0,10" /><ListBox x:Name="ProjectList" SelectionMode="Multiple" MinHeight="120" MaxHeight="220" Background="#24131A" Foreground="#FFD5DA" BorderBrush="#8B4E5C" Margin="0,0,0,10"><ListBox.ItemTemplate><DataTemplate><StackPanel Margin="3"><TextBlock Text="{Binding Slug}" FontWeight="SemiBold" /><TextBlock Text="{Binding RuntimeId}" FontSize="11" /><TextBlock Text="{Binding OwnershipStatus}" FontSize="11" /></StackPanel></DataTemplate></ListBox.ItemTemplate></ListBox><TextBlock Text="Control-plane confirmation" Foreground="#FFD5DA" /><TextBox x:Name="ControlPhraseBox" Margin="0,4,0,8" /><TextBlock Text="Project-data confirmation" Foreground="#FFD5DA" /><TextBox x:Name="ProjectPhraseBox" Margin="0,4,0,8" /><CheckBox x:Name="VerifiedBackupCheck" Content="I verified the selected project's technical backup evidence (acknowledgement only)." Foreground="#FFD5DA" /></StackPanel></Border></StackPanel>
            <StackPanel x:Name="ReviewPanel" Visibility="Collapsed"><TextBlock Text="Exact plan" FontWeight="SemiBold" Margin="0,0,0,8" /><TextBox x:Name="PlanText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" MinHeight="220" Background="#101A2B" BorderBrush="{StaticResource PanelBorderBrush}" Foreground="{StaticResource TextBrush}" FontFamily="Consolas" FontSize="12" Padding="11" /><TextBlock x:Name="PlanStatus" Margin="0,12,0,0" FontWeight="SemiBold" /></StackPanel>
            <StackPanel x:Name="ExecutePanel" Visibility="Collapsed"><ProgressBar x:Name="OperationProgress" Height="8" Minimum="0" Maximum="100" /><TextBlock x:Name="OperationStatus" Text="Ready" Margin="0,12,0,0" /><TextBox x:Name="OperationLog" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" MinHeight="180" Margin="0,12,0,0" Background="#101A2B" BorderBrush="{StaticResource PanelBorderBrush}" Foreground="{StaticResource TextBrush}" FontFamily="Consolas" FontSize="11" Padding="11" /></StackPanel>
          </StackPanel></ScrollViewer>
          <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="ExportButton" Content="Export Preflight" Click="ExportButton_Click" /><Button x:Name="CopyButton" Content="Copy diagnostics" Click="CopyButton_Click" /><Button x:Name="BackButton" Content="Back" Click="BackButton_Click" /><Button x:Name="NextButton" Content="Next" Click="NextButton_Click" /><Button x:Name="ExecuteButton" Content="Execute verified plan" Click="ExecuteButton_Click" Visibility="Collapsed" Background="#2B8066" BorderBrush="#55B998" /><Button x:Name="CancelButton" Content="Cancel" Click="CancelButton_Click" Background="#4A2933" BorderBrush="#8B4E5C" /></StackPanel>
        </Grid>
      </Border>
    </Grid>
  </Grid>
</Window>

```


## FILE: installer-source/DevFleet.Setup/MainWindow.xaml.cs

SHA256: d0869b40c123a7082fbd3a7c4609503a35463c69366c8d0d4d84af94fc5a42dc | Bytes: 15527 | Git mode: 100644

```
using System.IO;
using System.Diagnostics;
using System.Text;
using System.Windows;
using System.Windows.Controls;

namespace DevFleet.Setup;

public partial class MainWindow : Window
{
    private readonly string[] _pages = ["Welcome", "Action", "Preflight", "Tailscale", "Scope", "Review", "Execute", "Finish"];
    private int _page;
    private PreflightReport _preflight = new();
    private InstallerPlan? _plan;
    private IReadOnlyList<DiscoveredProject> _projects = [];
    private bool _executing;
    private bool _tailscaleBusy;
    private CancellationTokenSource? _tailscaleCancellation;
    private int _progress;
    private bool _deferNetworkPairing;
    private Uri? _tailscaleAuthenticationUri;

    public MainWindow()
    {
        InitializeComponent();
        VersionText.Text = $"DevFleet {PayloadManifest.DevFleetVersion}  ·  Installer {PayloadManifest.InstallerVersion}  ·  Official-source connected setup";
        ModeCombo.ItemsSource = Enum.GetValues<InstallerMode>();
        ModeCombo.SelectedItem = InstallerMode.Diagnostics;
        RoleCombo.ItemsSource = new[] { "Primary / Desktop", "Laptop / Surrogate" };
        RoleCombo.SelectedIndex = 0;
    }

    private InstallerMode CurrentMode => ModeCombo.SelectedItem is InstallerMode mode ? mode : InstallerMode.Diagnostics;

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        NextButton.IsEnabled = false;
        DetectedSummary.Text = "Running read-only preflight off the UI thread…";
        try
        {
            var result = await Task.Run(() => (Report: PreflightService.Run(), Projects: (IReadOnlyList<DiscoveredProject>)new ProjectDiscoveryService().Discover()));
            _preflight = result.Report;
            _projects = result.Projects;
            ProjectList.ItemsSource = _projects;
            DetectedSummary.Text = $"Existing DevFleet: {_preflight.ExistingDevFleetVersion} · Role: {_preflight.DetectedRole} · Admin: {_preflight.Administrator}";
            PreflightText.Text = PreflightService.ToText(_preflight);
        }
        catch (Exception ex)
        {
            DetectedSummary.Text = "Preflight failed safely; no mutation was attempted.";
            PreflightText.Text = $"Read-only preflight failed: {ex.Message}";
        }
        var launchRequest = InstallerLaunchContract.Parse(Environment.GetCommandLineArgs());
        _deferNetworkPairing = launchRequest.DeferNetworkPairing;
        DeferNetworkPairingCheck.IsChecked = _deferNetworkPairing;
        RootfulDockerAcknowledgeCheck.IsChecked = launchRequest.AcknowledgeRootfulDocker;
        if (launchRequest.Action is { } action) ModeCombo.SelectedItem = action;
        if (!string.IsNullOrWhiteSpace(launchRequest.Role))
        {
            var index = Array.IndexOf((string[])RoleCombo.ItemsSource, launchRequest.Role);
            if (index >= 0) RoleCombo.SelectedIndex = index;
        }
        var elevatedResume = launchRequest.ElevatedResume;
        if (elevatedResume)
            DetectedSummary.Text += " · UAC elevation resumed with the reviewed action and role";
        NextButton.IsEnabled = true;
        RefreshPage();
        if (elevatedResume && CurrentMode != InstallerMode.Diagnostics)
        {
            _page = 5;
            RefreshPage();
            await ExecuteReviewedPlanAsync(requireConfirmation: false, elevatedResume: true);
        }
    }

    private void RefreshPage()
    {
        PageKicker.Text = $"STEP {_page + 1} OF {_pages.Length} · {_pages[_page].ToUpperInvariant()}";
        WelcomePanel.Visibility = _page == 0 ? Visibility.Visible : Visibility.Collapsed;
        ActionPanel.Visibility = _page == 1 ? Visibility.Visible : Visibility.Collapsed;
        PreflightPanel.Visibility = _page == 2 ? Visibility.Visible : Visibility.Collapsed;
        TailscalePanel.Visibility = _page == 3 ? Visibility.Visible : Visibility.Collapsed;
        ScopePanel.Visibility = _page == 4 ? Visibility.Visible : Visibility.Collapsed;
        ReviewPanel.Visibility = _page == 5 ? Visibility.Visible : Visibility.Collapsed;
        ExecutePanel.Visibility = _page >= 6 ? Visibility.Visible : Visibility.Collapsed;
        DangerPanel.Visibility = _page == 4 && CurrentMode == InstallerMode.FactoryReset ? Visibility.Visible : Visibility.Collapsed;
        BackButton.IsEnabled = _page > 0 && !_executing;
        NextButton.Visibility = _page < 6 ? Visibility.Visible : Visibility.Collapsed;
        ExecuteButton.Visibility = _page == 6 && CurrentMode != InstallerMode.Diagnostics ? Visibility.Visible : Visibility.Collapsed;
        ExportButton.Visibility = _page == 2 ? Visibility.Visible : Visibility.Collapsed;
        CopyButton.Visibility = _page is 2 or 5 or 6 ? Visibility.Visible : Visibility.Collapsed;
        PageTitle.Text = _page switch
        {
            0 => "Prepare a safe DevFleet operation",
            1 => "Choose the exact action and role",
            2 => "Review non-mutating preflight",
            3 => "Authenticate or deliberately defer Tailscale pairing",
            4 => CurrentMode == InstallerMode.FactoryReset ? "Select preservation and destructive scope" : "Confirm preservation and recovery",
            5 => "Review the exact transaction plan",
            6 => "Execute and verify",
            _ => "Operation complete"
        };
        PageDescription.Text = _page == 4 && CurrentMode == InstallerMode.FactoryReset ? "Factory Reset is visually distinct and requires exact typed confirmations. Ambiguous resources remain untouched." : "Every mutation is hash-verified, ownership-aware, logged, and recoverable where applicable.";
        foreach (var item in new[] { StepWelcome, StepAction, StepPreflight, StepScope, StepReview, StepExecute }) item.Foreground = (System.Windows.Media.Brush)FindResource("MutedBrush");
        var active = _page switch { 0 => StepWelcome, 1 => StepAction, 2 => StepPreflight, 3 or 4 => StepScope, 5 => StepReview, _ => StepExecute };
        active.Foreground = (System.Windows.Media.Brush)FindResource("AccentBrush"); active.FontWeight = FontWeights.Bold;
        if (_page == 5) BuildPlanAndShow();
    }

    private void ModeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (IsLoaded) RefreshPage();
    }

    private void NextButton_Click(object sender, RoutedEventArgs e)
    {
        if (_page == 5 && (_plan is null || !_plan.IsAllowed)) { BuildPlanAndShow(); return; }
        if (_page < 7) { _page++; RefreshPage(); }
    }

    private void BackButton_Click(object sender, RoutedEventArgs e)
    {
        if (_page > 0) { _page--; RefreshPage(); }
    }

    private void BuildPlanAndShow()
    {
        var selected = ProjectList.SelectedItems.Cast<DiscoveredProject>().Select(p => p.ProjectId).ToArray();
        _deferNetworkPairing = DeferNetworkPairingCheck.IsChecked == true;
        _plan = PlanService.Build(CurrentMode, PreserveProjectsCheck.IsChecked == true, PreserveBackupsCheck.IsChecked == true, RemovePrerequisitesCheck.IsChecked == true, ProjectDataCheck.IsChecked == true, VerifiedBackupCheck.IsChecked == true, ControlPhraseBox.Text, ProjectPhraseBox.Text, selected, _deferNetworkPairing, RootfulDockerAcknowledgeCheck.IsChecked == true, RoleCombo.SelectedItem?.ToString());
        RebootCheckpointService.BindPlanIfPresent(_plan, RoleCombo.SelectedItem?.ToString() ?? "Primary / Desktop");
        PlanText.Text = PlanService.ToText(_plan);
        PlanStatus.Text = _plan.IsAllowed ? "PASS — plan is eligible for execution after final review." : "BLOCKED — resolve every blocker before execution.";
        PlanStatus.Foreground = (System.Windows.Media.Brush)FindResource(_plan.IsAllowed ? "AccentBrush" : "DangerBrush");
    }

    private async void ExecuteButton_Click(object sender, RoutedEventArgs e)
    {
        await ExecuteReviewedPlanAsync(requireConfirmation: true, elevatedResume: false);
    }

    private async Task ExecuteReviewedPlanAsync(bool requireConfirmation, bool elevatedResume)
    {
        if (_executing) return;
        BuildPlanAndShow();
        if (_plan is null || !_plan.IsAllowed) { MessageBox.Show(this, PlanService.ToText(_plan ?? new InstallerPlan()), "Execution blocked", MessageBoxButton.OK, MessageBoxImage.Warning); return; }
        if (requireConfirmation && MessageBox.Show(this, "Execute the reviewed plan now? Diagnostics remains read-only; cleanup actions use only the displayed ownership scope.", "Confirm exact plan", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        if (!ElevationService.IsAdministrator && !TestEnvironment.IsTestProcess)
        {
            if (elevatedResume) throw new InvalidOperationException("The elevated resume continuation did not obtain an administrator token; refusing to relaunch recursively.");
            // The unelevated UI may validate the plan, but it must not create
            // protected staging. The elevated continuation reopens and
            // independently verifies the embedded payload.
            ElevationService.RelaunchVerified(RoleCombo.SelectedItem?.ToString() ?? "Primary / Desktop", CurrentMode, _deferNetworkPairing, _plan.AcknowledgeRootfulDocker);
            Close();
            return;
        }
            _executing = true; _progress = 0; _page = 6; RefreshPage(); ExecuteButton.IsEnabled = false; OperationLog.Clear();
            try
            {
                var plan = _plan;
                var role = RoleCombo.SelectedItem?.ToString() ?? "Standalone / unknown";
                var result = await Task.Run(() => InstallerEngine.Execute(plan!, role, ReportProgress));
            var rebootRequired = LifecycleEngine.LastExecution?.ExitCode == 3010 || File.Exists(RebootCheckpointService.Path);
            if (rebootRequired)
            {
                ReportProgress("REBOOT REQUIRED: the verified checkpoint is preserved; restart this same candidate after Windows reboots.");
                OperationStatus.Text = "Reboot required; checkpoint preserved";
                OperationProgress.Value = 95;
                _page = 6;
                RefreshPage();
                return;
            }
            ReportProgress($"VERIFIED COMPLETE: {result}"); OperationProgress.Value = 100; OperationStatus.Text = "Completed and verified"; _page = 7; RefreshPage();
        }
        catch (Exception ex)
        {
            ReportProgress($"FAILED — no unplanned continuation: {ex}"); OperationStatus.Text = "Failed; evidence preserved in the log"; OperationProgress.Value = 0;
        }
        finally { _executing = false; ExecuteButton.IsEnabled = true; BackButton.IsEnabled = true; }
    }

    private void ReportProgress(string message)
    {
        Dispatcher.Invoke(() => { _progress = Math.Min(95, _progress + 13); OperationProgress.Value = _progress; OperationStatus.Text = message; OperationLog.AppendText(message + Environment.NewLine); OperationLog.ScrollToEnd(); });
    }

    private void ExportButton_Click(object sender, RoutedEventArgs e)
    {
        var directory = Path.Combine(AppPaths.StateRoot, "Diagnostics"); Directory.CreateDirectory(directory); var stamp = DateTime.UtcNow.ToString("yyyyMMdd-HHmmss");
        var json = Path.Combine(directory, $"preflight-{stamp}.json"); var text = Path.Combine(directory, $"preflight-{stamp}.txt"); StateStore.WriteJsonAtomically(json, _preflight); File.WriteAllText(text, PreflightService.ToText(_preflight));
        MessageBox.Show(this, $"Preflight exported to:\n{text}\n{json}", "Read-only report exported", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void CopyButton_Click(object sender, RoutedEventArgs e)
    {
        var content = _page == 2 ? PreflightText.Text : _page == 5 ? PlanText.Text : OperationLog.Text; Clipboard.SetText(content); OperationStatus.Text = "Diagnostics copied to clipboard";
    }

    private async void TailscaleSignIn_Click(object sender, RoutedEventArgs e)
    {
        if (_tailscaleBusy) return;
        _tailscaleBusy = true; _tailscaleCancellation = new CancellationTokenSource(); var sourceButton = sender as Button; if (sourceButton is not null) sourceButton.IsEnabled = false;
        try
        {
        var dependency = DependencyService.Catalog.Single(x => x.Name == "Tailscale"); var detected = new DependencyService().Detect(dependency);
        if (!detected.Compatible) { TailscaleStatusText.Text = "Tailscale is missing or outdated. The Dependencies stage will install/update it from the official source before pairing."; return; }
        TailscaleStatusText.Text = "Starting bounded Tailscale authentication…";
        var auth = await TailscaleAuthenticationService.BeginAsync(new ProcessRunner(), detected.ExecutablePath, _tailscaleCancellation.Token); _tailscaleAuthenticationUri = auth.AuthenticationUri; OpenTailscaleAuthButton.IsEnabled = _tailscaleAuthenticationUri is not null; TailscaleStatusText.Text = $"{auth.State}: {auth.Detail}";
        }
        catch (OperationCanceledException) { TailscaleStatusText.Text = "Tailscale authentication cancelled."; }
        catch (Exception ex) { TailscaleStatusText.Text = $"Tailscale authentication failed: {ex.Message}"; }
        finally { _tailscaleBusy = false; _tailscaleCancellation?.Dispose(); _tailscaleCancellation = null; if (sourceButton is not null) sourceButton.IsEnabled = true; }
    }

    private void OpenTailscaleAuth_Click(object sender, RoutedEventArgs e)
    {
        if (_tailscaleAuthenticationUri is null || !_tailscaleAuthenticationUri.Host.Equals("login.tailscale.com", StringComparison.OrdinalIgnoreCase)) return;
        Process.Start(new ProcessStartInfo { FileName = _tailscaleAuthenticationUri.AbsoluteUri, UseShellExecute = true });
    }

    private async void CheckTailscale_Click(object sender, RoutedEventArgs e)
    {
        if (_tailscaleBusy) return;
        _tailscaleBusy = true; _tailscaleCancellation = new CancellationTokenSource(); var sourceButton = sender as Button; if (sourceButton is not null) sourceButton.IsEnabled = false;
        try
        {
        var dependency = DependencyService.Catalog.Single(x => x.Name == "Tailscale"); var detected = new DependencyService().Detect(dependency);
        if (!detected.Found) { TailscaleStatusText.Text = "Not installed yet."; return; }
        var result = await new ProcessRunner().RunAsync(detected.ExecutablePath, ["status", "--json"], cancellationToken: _tailscaleCancellation.Token); TailscaleStatusText.Text = result.ExitCode == 0 ? "Authenticated — Tailscale status returned successfully." : "Authentication required or Tailscale service unavailable.";
        }
        catch (OperationCanceledException) { TailscaleStatusText.Text = "Tailscale status check cancelled."; }
        catch (Exception ex) { TailscaleStatusText.Text = $"Tailscale status failed: {ex.Message}"; }
        finally { _tailscaleBusy = false; _tailscaleCancellation?.Dispose(); _tailscaleCancellation = null; if (sourceButton is not null) sourceButton.IsEnabled = true; }
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        if (_tailscaleBusy) { _tailscaleCancellation?.Cancel(); return; }
        if (_executing) { MessageBox.Show(this, "The current transaction is active. Wait for its bounded operation to finish; no forced reboot or blind cancellation is issued.", "Transaction in progress", MessageBoxButton.OK, MessageBoxImage.Information); return; }
        Close();
    }
}

```


## FILE: installer-source/DevFleet.Setup/Payload/devfleet-v1.2.13.tar.gz

SHA256: e3176c500f652d6023dcb611ccd580567ed9448da343a5fd4c3649214ca0b654 | Bytes: 530862 | Git mode: 100644

Binary file: retrieve the actual repository file at this path. It is not encoded into this reading document.


## FILE: installer-source/DevFleet.Setup/PayloadManifest.cs

SHA256: 3d59d604bf39f55204d33e3135ac256b0c4322458afd2e153ad2b61308c56e1d | Bytes: 345 | Git mode: 100644

```
namespace DevFleet.Setup;

internal static class PayloadManifest
{
    public const string DevFleetVersion = "1.2.13";
    public const string InstallerVersion = "1.4.1";
    public const string PayloadName = "devfleet-v1.2.13.tar.gz";
    public const string PayloadSha256 = "e3176c500f652d6023dcb611ccd580567ed9448da343a5fd4c3649214ca0b654";
}
```


## FILE: installer-source/DevFleet.Setup/Services/InstallerLifecycle.cs

SHA256: c6963a43398085968288e4b76fea4137e5790264c0fa827efd6afd9a0d2f556c | Bytes: 141135 | Git mode: 100644

```
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Text.Json;
using System.Threading;
using Microsoft.Win32;

namespace DevFleet.Setup;

public sealed record ProcessResult(int ExitCode, string StandardOutput, string StandardError, bool OutputComplete = true);
public sealed record ProcessInvocation(string FileName, IReadOnlyList<string> Arguments, string? WorkingDirectory);

public static class DeadlinePolicy
{
    public const string Version = "1.0.0";
    public const int TransactionTerminalizationMarginSeconds = 600;
    public const int BootstrapSeconds = 240;
    public const int PreflightSeconds = 120;
    public const int PrerequisiteDependencyCount = 6;
    public const int DependencyProbeSeconds = 60;
    public const int DependencyHealthSeconds = 180;
    public const int DependencyInstallSeconds = 1800;
    public const int DependencyVerificationSeconds = 60;
    public const int WindowsCapabilitySeconds = 900;
    public const int WindowsFeatureSeconds = 900;
    public const int MultipassConfigurationSeconds = 600;
    public const int VsCodeExtensionSeconds = 300;
    public static int PrerequisitesSeconds => PrerequisiteDependencyCount * (DependencyProbeSeconds + DependencyHealthSeconds + DependencyInstallSeconds + DependencyVerificationSeconds) + WindowsCapabilitySeconds + WindowsFeatureSeconds + (4 * MultipassConfigurationSeconds) + (3 * VsCodeExtensionSeconds);
    public const int WindowsTailscaleSeconds = 180;
    public const int HostAgentSeconds = 300;
    public const int MultipassLaunchSeconds = 900;
    public const int MultipassReadinessSeconds = 1200;
    public const int PayloadTransferSeconds = 900;
    public const int GuestBootstrapPackagePrerequisitesSeconds = 900;
    public const int GuestBootstrapDockerRepositoryAndInstallSeconds = 1200;
    public const int GuestBootstrapTailscaleRepositoryAndInstallSeconds = 1200;
    public const int GuestBootstrapRootlessRuntimeSeconds = 600;
    public const int GuestBootstrapNodeToolchainSeconds = 600;
    public const int GuestBootstrapPythonRuntimeSeconds = 1200;
    public const int GuestBootstrapServiceAndFirewallFinalizationSeconds = 600;
    public const int GuestBootstrapTerminalizationMarginSeconds = 300;
    public static int GuestBootstrapSeconds => GuestBootstrapPackagePrerequisitesSeconds + GuestBootstrapDockerRepositoryAndInstallSeconds + GuestBootstrapTailscaleRepositoryAndInstallSeconds + GuestBootstrapRootlessRuntimeSeconds + GuestBootstrapNodeToolchainSeconds + GuestBootstrapPythonRuntimeSeconds + GuestBootstrapServiceAndFirewallFinalizationSeconds + GuestBootstrapTerminalizationMarginSeconds;
    public const int VaultBootstrapPackagePrerequisitesSeconds = 900;
    public const int VaultBootstrapRestServerSeconds = 1200;
    public const int VaultBootstrapTailscaleSeconds = 600;
    public const int VaultBootstrapServiceConfigurationSeconds = 600;
    public const int VaultBootstrapFirewallFinalizationSeconds = 300;
    public const int VaultBootstrapTerminalizationMarginSeconds = 300;
    public static int VaultBootstrapSeconds => VaultBootstrapPackagePrerequisitesSeconds + VaultBootstrapRestServerSeconds + VaultBootstrapTailscaleSeconds + VaultBootstrapServiceConfigurationSeconds + VaultBootstrapFirewallFinalizationSeconds + VaultBootstrapTerminalizationMarginSeconds;
    public const int SshAndMarkerSeconds = 300;
    public const int VaultSnapshotSeconds = 300;
    public const int TailscaleSeconds = 900;
    public const int VaultClientSeconds = 300;
    public const int ShortcutsSeconds = 180;
    public const int ExportSeconds = 300;
    public const int VerificationSeconds = 300;

    public static int ComputeStageSeconds => MultipassLaunchSeconds + MultipassReadinessSeconds + PayloadTransferSeconds + GuestBootstrapSeconds + SshAndMarkerSeconds;
    public static int VaultStageSeconds => VaultSnapshotSeconds + MultipassLaunchSeconds + MultipassReadinessSeconds + PayloadTransferSeconds + VaultBootstrapSeconds + SshAndMarkerSeconds;
    public static int DesktopTransactionSeconds => BootstrapSeconds + PreflightSeconds + PrerequisitesSeconds + WindowsTailscaleSeconds + HostAgentSeconds + ComputeStageSeconds + TailscaleSeconds + ShortcutsSeconds + ExportSeconds + VerificationSeconds + TransactionTerminalizationMarginSeconds;
    public static int LaptopTransactionSeconds => BootstrapSeconds + PreflightSeconds + PrerequisitesSeconds + WindowsTailscaleSeconds + HostAgentSeconds + ComputeStageSeconds + VaultStageSeconds + (TailscaleSeconds * 2) + VaultClientSeconds + ShortcutsSeconds + ExportSeconds + VerificationSeconds + TransactionTerminalizationMarginSeconds;

    public static int GetConnectedTransactionBudgetSeconds(string role) => role.Contains("Laptop", StringComparison.OrdinalIgnoreCase) ? LaptopTransactionSeconds : DesktopTransactionSeconds;
}

public interface IProcessRunner
{
    ProcessResult Run(string fileName, IReadOnlyList<string> arguments, string? workingDirectory = null);
    Task<ProcessResult> RunAsync(string fileName, IReadOnlyList<string> arguments, string? workingDirectory = null, CancellationToken cancellationToken = default)
        => Task.Run(() => Run(fileName, arguments, workingDirectory), cancellationToken);
}

public sealed class ProcessRunner : IProcessRunner
{
    public int DefaultTimeoutSeconds { get; }
    public bool AllowEnvironmentOverride { get; }

    public ProcessRunner(int defaultTimeoutSeconds = 900, bool allowEnvironmentOverride = true)
    {
        if (defaultTimeoutSeconds <= 0) throw new ArgumentOutOfRangeException(nameof(defaultTimeoutSeconds));
        DefaultTimeoutSeconds = defaultTimeoutSeconds;
        AllowEnvironmentOverride = allowEnvironmentOverride;
    }

    public ProcessResult Run(string fileName, IReadOnlyList<string> arguments, string? workingDirectory = null)
        => RunAsync(fileName, arguments, workingDirectory).GetAwaiter().GetResult();

    public async Task<ProcessResult> RunAsync(string fileName, IReadOnlyList<string> arguments, string? workingDirectory = null, CancellationToken cancellationToken = default)
    {
        using var process = new Process { StartInfo = new ProcessStartInfo
        {
            FileName = fileName,
            WorkingDirectory = workingDirectory ?? Environment.CurrentDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        } };
        foreach (var argument in arguments) process.StartInfo.ArgumentList.Add(argument);
        process.Start();
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        var timeoutSeconds = AllowEnvironmentOverride && int.TryParse(Environment.GetEnvironmentVariable("DEVFLEET_SETUP_PROCESS_TIMEOUT_SECONDS"), out var configured) && configured > 0 ? configured : DefaultTimeoutSeconds;
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));
      