# DevFleet source part 060

Full-source UTF-8 byte interval [2743500, 2790000); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: ba4842fd648fab7f1e05208344be0bf802e4334627c4e893069c919ae45f0289

<!-- BEGIN SOURCE SLICE -->
 = new BackupReference(
            reference.GetProperty("provider").GetString() ?? "",
            reference.GetProperty("backup_id").GetString() ?? "",
            reference.GetProperty("project_id").GetString() ?? "",
            reference.GetProperty("slug").GetString() ?? "",
            reference.GetProperty("runtime_id").GetString() ?? "",
            reference.GetProperty("host_id").GetString() ?? "",
            reference.GetProperty("archive_sha256").GetString() ?? "",
            reference.GetProperty("archive_bytes").GetInt64(),
            reference.GetProperty("manifest_sha256").GetString() ?? "",
            reference.GetProperty("created_at").GetString() ?? "",
            reference.GetProperty("consistency_level").GetString() ?? "");
        if (!providerReference.Provider.Equals("multipass-host-agent", StringComparison.OrdinalIgnoreCase) || !providerReference.BackupId.Equals(id, StringComparison.OrdinalIgnoreCase) || !providerReference.ProjectId.Equals(vm.ProjectId, StringComparison.OrdinalIgnoreCase) || !providerReference.Slug.Equals(vm.Slug, StringComparison.OrdinalIgnoreCase) || !providerReference.RuntimeId.Equals(vm.RuntimeId, StringComparison.OrdinalIgnoreCase) || !providerReference.ArchiveSha256.Equals(sha, StringComparison.OrdinalIgnoreCase) || providerReference.ArchiveBytes < 0 || !Regex.IsMatch(providerReference.ManifestSha256, "^[0-9a-fA-F]{64}$"))
            throw new InvalidDataException("Host Agent backup reference identity or hash binding is invalid.");
        return new BackupVerification(vm.ProjectId, id, "", sha, sha, true, true, DateTime.UtcNow, providerReference);
    }

    public void DeleteExact(VmRecord vm)
    {
        if (!vm.Owned || string.IsNullOrWhiteSpace(vm.Slug) || string.IsNullOrWhiteSpace(vm.BackupId) || string.IsNullOrWhiteSpace(vm.BackupSha256))
            throw new InvalidOperationException("Host Agent destruction requires an owned project, exact slug, and selected verified backup.");
        var configPath = Path.Combine(_root, "config.json");
        using var config = JsonDocument.Parse(File.ReadAllText(configPath));
        var prefix = config.RootElement.TryGetProperty("ListenPrefix", out var lp) ? lp.GetString() : "http://127.0.0.1:8791/";
        var tokenPath = config.RootElement.TryGetProperty("TokenPath", out var tp) ? tp.GetString() : null;
        if (string.IsNullOrWhiteSpace(tokenPath) || !File.Exists(tokenPath)) throw new InvalidOperationException("Host Agent token path is unavailable; destruction is blocked.");
        var destroyBody = JsonSerializer.SerializeToUtf8Bytes(new { operation = "destroy", slug = vm.Slug, project_id = vm.ProjectId, confirm_slug = vm.Slug, confirm_phrase = $"DESTROY {vm.Slug}", backup_verified = true, backup_id = vm.BackupId, backup_sha256 = vm.BackupSha256 });
        using var request = new HttpRequestMessage(HttpMethod.Delete, new Uri(BuildHostAgentBaseUri(prefix), $"v1/project-vms/{Uri.EscapeDataString(vm.RuntimeId)}/destroy"));
        request.Content = new ByteArrayContent(destroyBody);
        request.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
        AddRequestAuthentication(request, destroyBody, File.ReadAllText(tokenPath).Trim(), config.RootElement.TryGetProperty("HostName", out var hostName) ? hostName.GetString() ?? "" : "");
        using var response = _http.Send(request);
        var bodyBytes = response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
        VerifyResponseAuthentication(request, response, bodyBytes, File.ReadAllText(tokenPath).Trim(), config.RootElement.TryGetProperty("HostName", out var responseHostName) ? responseHostName.GetString() ?? "" : "");
        var body = Encoding.UTF8.GetString(bodyBytes);
        if (!response.IsSuccessStatusCode) throw new InvalidOperationException($"Host Agent rejected exact project destruction ({(int)response.StatusCode}): {body}");
        if (!body.Contains("\"state\":\"destroyed\"", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Host Agent destruction response did not prove destroyed state.");
    }

    private static Uri BuildHostAgentBaseUri(string? configuredPrefix)
    {
        var prefix = string.IsNullOrWhiteSpace(configuredPrefix) ? "http://127.0.0.1:8791/" : configuredPrefix.Trim();
        foreach (var scheme in new[] { "http://", "https://" })
        foreach (var wildcard in new[] { "+", "*" })
        {
            var marker = scheme + wildcard + ":";
            if (prefix.StartsWith(marker, StringComparison.OrdinalIgnoreCase))
            {
                prefix = scheme + "127.0.0.1:" + prefix[marker.Length..];
                break;
            }
        }
        if (!Uri.TryCreate(prefix.TrimEnd('/') + "/", UriKind.Absolute, out var uri) || uri is null || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) || !string.IsNullOrEmpty(uri.UserInfo))
            throw new InvalidOperationException("Host Agent listen prefix is not a valid local HTTP endpoint.");
        return uri;
    }

    private static void AddRequestAuthentication(HttpRequestMessage request, byte[] body, string key, string expectedHost)
    {
        if (string.IsNullOrWhiteSpace(key) || string.IsNullOrWhiteSpace(expectedHost)) throw new InvalidOperationException("Host Agent request authentication configuration is incomplete.");
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString(System.Globalization.CultureInfo.InvariantCulture);
        var nonce = Convert.ToHexString(RandomNumberGenerator.GetBytes(18)).ToLowerInvariant();
        var prefix = Encoding.UTF8.GetBytes($"{request.Method.Method.ToUpperInvariant()}\n{request.RequestUri!.AbsolutePath}\n{timestamp}\n{nonce}\n");
        var suffix = Encoding.UTF8.GetBytes($"\n{expectedHost}");
        var material = new byte[prefix.Length + body.Length + suffix.Length];
        Buffer.BlockCopy(prefix, 0, material, 0, prefix.Length);
        Buffer.BlockCopy(body, 0, material, prefix.Length, body.Length);
        Buffer.BlockCopy(suffix, 0, material, prefix.Length + body.Length, suffix.Length);
        var signature = Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(key), material)).ToLowerInvariant();
        request.Headers.TryAddWithoutValidation("X-DevFleet-Host-Timestamp", timestamp);
        request.Headers.TryAddWithoutValidation("X-DevFleet-Host-Nonce", nonce);
        request.Headers.TryAddWithoutValidation("X-DevFleet-Host-Expected", expectedHost);
        request.Headers.TryAddWithoutValidation("X-DevFleet-Host-Signature", signature);
    }

    private static void VerifyResponseAuthentication(HttpRequestMessage request, HttpResponseMessage response, byte[] body, string key, string expectedHost)
    {
        if (string.IsNullOrWhiteSpace(key) || string.IsNullOrWhiteSpace(expectedHost)) throw new InvalidOperationException("Host Agent response authentication configuration is incomplete.");
        var timestamp = request.Headers.GetValues("X-DevFleet-Host-Timestamp").Single();
        var nonce = request.Headers.GetValues("X-DevFleet-Host-Nonce").Single();
        var provided = response.Headers.TryGetValues("X-DevFleet-Host-Response-Signature", out var values) ? values.SingleOrDefault() : null;
        var material = BuildAuthMaterial(request.Method.Method, request.RequestUri!.AbsolutePath, timestamp, nonce, ((int)response.StatusCode).ToString(System.Globalization.CultureInfo.InvariantCulture), body, expectedHost);
        var expected = Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(key), material)).ToLowerInvariant();
        var left = Encoding.ASCII.GetBytes(expected); var right = Encoding.ASCII.GetBytes((provided ?? "").ToLowerInvariant());
        if (left.Length != right.Length || !CryptographicOperations.FixedTimeEquals(left, right)) throw new InvalidDataException("Host Agent response authentication failed.");
    }

    private static byte[] BuildAuthMaterial(string method, string path, string timestamp, string nonce, string status, byte[] body, string expectedHost)
    {
        var parts = new[] { Encoding.UTF8.GetBytes(method.ToUpperInvariant()), Encoding.UTF8.GetBytes("\n"), Encoding.UTF8.GetBytes(path), Encoding.UTF8.GetBytes("\n"), Encoding.UTF8.GetBytes(timestamp), Encoding.UTF8.GetBytes("\n"), Encoding.UTF8.GetBytes(nonce), Encoding.UTF8.GetBytes("\n"), Encoding.UTF8.GetBytes(status), Encoding.UTF8.GetBytes("\n") , body, Encoding.UTF8.GetBytes("\n"), Encoding.UTF8.GetBytes(expectedHost) };
        var length = parts.Sum(part => part.Length); var material = new byte[length]; var offset = 0;
        foreach (var part in parts) { Buffer.BlockCopy(part, 0, material, offset, part.Length); offset += part.Length; }
        return material;
    }

    private (string BackupId, string Sha256) FindLatestBackup(string projectId, string slug, string runtime)
    {
        var backupRoot = Path.Combine(_root, "backups");
        foreach (var manifest in Directory.Exists(backupRoot) ? Directory.EnumerateFiles(backupRoot, "*.json").OrderByDescending(File.GetLastWriteTimeUtc) : Enumerable.Empty<string>())
        {
            try
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(manifest)); var r = doc.RootElement;
                if (r.TryGetProperty("project_id", out var pid) && pid.GetString() == projectId && r.TryGetProperty("slug", out var sl) && sl.GetString() == slug && r.TryGetProperty("runtime_id", out var rt) && rt.GetString() == runtime)
                    return (r.TryGetProperty("backup_id", out var bid) ? bid.GetString() ?? "" : Path.GetFileNameWithoutExtension(manifest), r.TryGetProperty("archive_sha256", out var sh) ? sh.GetString() ?? "" : "");
            }
            catch (JsonException) { }
        }
        return ("", "");
    }
}

public sealed class VmOwnershipService
{
    private readonly IVmProvider _provider;
    public VmOwnershipService(IVmProvider provider) => _provider = provider;
    public void DeleteOwnedExact(string projectId, string runtimeId, Action<string>? progress = null)
        => DeleteOwnedExact(projectId, runtimeId, null, progress);
    public void DeleteOwnedExact(string projectId, string runtimeId, BackupVerification? selectedBackup, Action<string>? progress = null)
    {
        var before = _provider.Discover().ToArray();
        var vm = before.SingleOrDefault(x => x.ProjectId.Equals(projectId, StringComparison.OrdinalIgnoreCase) && x.RuntimeId.Equals(runtimeId, StringComparison.OrdinalIgnoreCase));
        if (vm is null || !vm.Owned) throw new InvalidOperationException($"No independently owned VM matched project={projectId}, runtime={runtimeId}.");
        if (selectedBackup is not null)
        {
            if (!selectedBackup.IsVerified || !selectedBackup.ProjectId.Equals(projectId, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Exact selected backup binding is invalid.");
            vm = vm with { BackupId = selectedBackup.BackupId, BackupSha256 = selectedBackup.ActualSha256 };
            progress?.Invoke($"Exact selected backup bound: {selectedBackup.BackupId} sha256={selectedBackup.ActualSha256}");
        }
        _provider.DeleteExact(vm);
        progress?.Invoke($"Provider-aware exact deletion verified: {vm.Provider} {vm.RuntimeId}");
        var unrelated = before.Where(x => !x.RuntimeId.Equals(runtimeId, StringComparison.OrdinalIgnoreCase)).Select(x => x.RuntimeId).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (_provider.Discover().Where(x => unrelated.Contains(x.RuntimeId)).Count() != unrelated.Count) throw new InvalidOperationException("Unrelated VM inventory changed during exact deletion.");
    }

    public BackupVerification CreateFreshSafetyBackup(DiscoveredProject project, Action<string>? progress = null)
    {
        var vm = _provider.Discover().SingleOrDefault(x => x.ProjectId.Equals(project.ProjectId, StringComparison.OrdinalIgnoreCase) && x.RuntimeId.Equals(project.RuntimeId, StringComparison.OrdinalIgnoreCase));
        if (vm is null || !vm.Owned) throw new InvalidOperationException($"No independently owned VM matched project={project.ProjectId}, runtime={project.RuntimeId}.");
        var backup = _provider.CreateFreshBackup(vm);
        if (!backup.IsVerified || !backup.ProjectId.Equals(project.ProjectId, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Fresh safety backup identity verification failed.");
        progress?.Invoke($"Fresh Factory Reset safety backup bound: {backup.BackupId} sha256={backup.ActualSha256}");
        return backup;
    }
}

public sealed class TransactionService
{
    private readonly Stack<(string Name, Action Rollback)> _rollback = new();
    private readonly InstallerLogger _logger;
    public TransactionService(InstallerLogger logger) => _logger = logger;
    public void Execute(string name, Action action, Action rollback, Action<string>? progress = null)
    {
        _logger.Write($"step={name} state=planned"); progress?.Invoke($"Planned: {name}");
        action(); _rollback.Push((name, rollback)); _logger.Write($"step={name} state=verified"); progress?.Invoke($"Verified: {name}");
    }
    public void Rollback(Action<string>? progress = null)
    {
        while (_rollback.Count > 0)
        {
            var step = _rollback.Pop();
            try { step.Rollback(); _logger.Write($"step={step.Name} state=rolled-back"); progress?.Invoke($"Rolled back: {step.Name}"); }
            catch (Exception ex) { _logger.Write($"step={step.Name} state=rollback-incomplete error={ex.Message}"); progress?.Invoke($"Rollback incomplete: {step.Name}"); }
        }
    }
}

public static class RebootCheckpointService
{
    // The supported Windows prerequisite graph has at most three legitimate
    // reboot boundaries (PowerShell/servicing, Hyper-V, and final servicing).
    // Keep this explicit and bounded: an unexpected fourth boundary fails
    // closed instead of becoming an unbounded reboot loop.
    public const int MaxRebootBoundaries = 3;
    public static string Path => System.IO.Path.Combine(AppPaths.InstallerRoot, "resume-checkpoint.json");
    private static string ConsumedPath(string transactionId) => System.IO.Path.Combine(AppPaths.InstallerRoot, "resume-consumed", $"{transactionId}.json");
    private static string ScriptStateRoot => TestEnvironment.IsTestProcess
        ? AppPaths.StateRoot
        : System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "DevFleet");

    private static bool IsSameScriptTransaction(JsonElement existing, InstallerPlan plan, string role)
    {
        var normalizedRole = role.Contains("Laptop", StringComparison.OrdinalIgnoreCase) ? "Laptop" : "Desktop";
        return existing.TryGetProperty("transactionId", out var transactionId) &&
               existing.TryGetProperty("payloadSha256", out var payloadSha256) &&
               existing.TryGetProperty("action", out var action) &&
               existing.TryGetProperty("role", out var existingRole) &&
               existing.TryGetProperty("acknowledgeRootfulDocker", out var acknowledgement) &&
               acknowledgement.ValueKind is JsonValueKind.True or JsonValueKind.False &&
               transactionId.GetString() == plan.TransactionId &&
               payloadSha256.GetString() == PayloadManifest.PayloadSha256 &&
               action.GetString() == plan.Mode.ToString() &&
               existingRole.GetString() == normalizedRole &&
               acknowledgement.GetBoolean() == plan.AcknowledgeRootfulDocker;
    }

    private static void ClearStaleStageMarkers(string role, Action<string>? progress = null)
    {
        var roots = new[] { ScriptStateRoot, AppPaths.InstallerRoot }
            .Select(System.IO.Path.GetFullPath)
            .Distinct(StringComparer.OrdinalIgnoreCase);
        foreach (var root in roots)
        {
            if (!Directory.Exists(root)) continue;
            foreach (var marker in Directory.EnumerateFiles(root, "stage-*.complete", SearchOption.TopDirectoryOnly).ToArray())
            {
                var full = System.IO.Path.GetFullPath(marker);
                if (!full.StartsWith(root.TrimEnd(System.IO.Path.DirectorySeparatorChar) + System.IO.Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException($"Refusing to remove a stage marker outside the canonical DevFleet state root: {full}");
                File.Delete(full);
                if (File.Exists(full)) throw new IOException($"Stale DevFleet stage marker remains after transaction reset: {full}");
                progress?.Invoke($"Removed stale DevFleet stage marker for new {role} transaction: {full}");
            }
        }
    }

    public static string PrepareScriptTransaction(InstallerPlan plan, string role, Action<string>? progress = null)
    {
        var scriptRoot = ScriptStateRoot;
        Directory.CreateDirectory(scriptRoot);
        var activePath = System.IO.Path.Combine(scriptRoot, "active-transaction.json");
        var sameTransaction = false;
        if (File.Exists(activePath))
        {
            try
            {
                using var existingDocument = JsonDocument.Parse(File.ReadAllText(activePath));
                sameTransaction = IsSameScriptTransaction(existingDocument.RootElement, plan, role);
            }
            catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
            {
                throw new InvalidDataException("The existing DevFleet script transaction record is unreadable; refusing to replace it.", ex);
            }
        }
        if (!sameTransaction) ClearStaleStageMarkers(role, progress);
        var preparedUtc = DateTime.UtcNow.ToString("O");
        StateStore.WriteJsonAtomically(activePath, new
        {
            transactionId = plan.TransactionId,
            payloadSha256 = PayloadManifest.PayloadSha256,
            action = plan.Mode.ToString(),
            role = role.Contains("Laptop", StringComparison.OrdinalIgnoreCase) ? "Laptop" : "Desktop",
            acknowledgeRootfulDocker = plan.AcknowledgeRootfulDocker,
            preparedUtc
        });
        return preparedUtc;
    }

    private static void ValidateActiveTransaction(InstallerPlan plan, string role)
    {
        var normalizedRole = role.Contains("Laptop", StringComparison.OrdinalIgnoreCase) ? "Laptop" : "Desktop";
        var activePath = System.IO.Path.Combine(ScriptStateRoot, "active-transaction.json");
        if (!File.Exists(activePath)) throw new InvalidDataException("The active DevFleet transaction record is missing; refusing reboot resume.");
        using var activeDocument = JsonDocument.Parse(File.ReadAllText(activePath));
        var active = activeDocument.RootElement;
        if (!active.TryGetProperty("acknowledgeRootfulDocker", out var acknowledgement) || acknowledgement.ValueKind is not (JsonValueKind.True or JsonValueKind.False) ||
            active.GetProperty("transactionId").GetString() != plan.TransactionId || active.GetProperty("payloadSha256").GetString() != PayloadManifest.PayloadSha256 ||
            active.GetProperty("action").GetString() != plan.Mode.ToString() || active.GetProperty("role").GetString() != normalizedRole || acknowledgement.GetBoolean() != plan.AcknowledgeRootfulDocker)
            throw new InvalidDataException("The active DevFleet transaction record does not match the reviewed reboot plan.");
    }

    private static string[] ReadCompletedStages(InstallerPlan plan, string role)
    {
        var normalizedRole = role.Contains("Laptop", StringComparison.OrdinalIgnoreCase) ? "Laptop" : "Desktop";
        ValidateActiveTransaction(plan, role);
        var roots = new[] { AppPaths.StateRoot, ScriptStateRoot }
            .Where(Directory.Exists)
            .Distinct(StringComparer.OrdinalIgnoreCase);
        var allowed = normalizedRole == "Desktop"
            ? new Regex("^stage-(prereqs-Desktop|windows-tailscale|host-agent|compute-devfleet-primary)$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase)
            : new Regex("^stage-(prereqs-Laptop|windows-tailscale|host-agent|compute-devfleet-failover|vault)$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
        return roots.SelectMany(root => Directory.EnumerateFiles(root, "stage-*.complete", SearchOption.TopDirectoryOnly))
            .Select(path => (path, name: System.IO.Path.GetFileNameWithoutExtension(path)))
            .Where(item => allowed.IsMatch(item.name))
            .Where(item => {
                try {
                    using var marker = JsonDocument.Parse(File.ReadAllText(item.path));
                    var value = marker.RootElement;
                    return value.GetProperty("transactionId").GetString() == plan.TransactionId && value.GetProperty("payloadSha256").GetString() == PayloadManifest.PayloadSha256 && value.GetProperty("action").GetString() == plan.Mode.ToString() && value.GetProperty("role").GetString() == normalizedRole && value.GetProperty("stage").GetString() == item.name;
                } catch { return false; }
            })
            .Select(item => item.name)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(name => name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static string ResumeStage(IEnumerable<string> completedStages)
    {
        var completed = completedStages.ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (completed.Count == 0) return "bootstrap-entrypoint";
        if (!completed.Any(x => x.Equals("stage-prereqs-Desktop", StringComparison.OrdinalIgnoreCase) || x.Equals("stage-prereqs-Laptop", StringComparison.OrdinalIgnoreCase))) return "prerequisites";
        if (!completed.Contains("stage-host-agent")) return "host-agent";
        if (completed.Contains("stage-prereqs-Laptop"))
        {
            if (!completed.Contains("stage-compute-devfleet-failover")) return "compute-devfleet-failover";
            if (!completed.Contains("stage-vault")) return "vault";
        }
        else if (!completed.Contains("stage-compute-devfleet-primary")) return "compute-devfleet-primary";
        return "finalize";
    }

    private static void ValidateCompletedStages(JsonElement root, string role, out string[] completedStages)
    {
        completedStages = root.TryGetProperty("completedStages", out var stages)
            ? stages.EnumerateArray().Select(x => x.GetString() ?? "").ToArray()
            : [];
        var normalizedRole = role.Contains("Laptop", StringComparison.OrdinalIgnoreCase) ? "Laptop" : "Desktop";
        var allowed = normalizedRole == "Desktop"
            ? new Regex("^stage-(prereqs-Desktop|windows-tailscale|host-agent|compute-devfleet-primary)$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase)
            : new Regex("^stage-(prereqs-Laptop|windows-tailscale|host-agent|compute-devfleet-failover|vault)$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
        if (completedStages.Any(x => string.IsNullOrWhiteSpace(x) || !allowed.IsMatch(x) || x.Contains(System.IO.Path.DirectorySeparatorChar) || x.Contains(System.IO.Path.AltDirectorySeparatorChar)) ||
            completedStages.Length != completedStages.Distinct(StringComparer.OrdinalIgnoreCase).Count())
            throw new InvalidDataException("A reboot checkpoint contains invalid or duplicate completed stage identities.");
        var completed = completedStages.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var prereq = $"stage-prereqs-{normalizedRole}";
        if (completed.Contains("stage-host-agent") && !completed.Contains(prereq) ||
            completed.Any(x => x.StartsWith("stage-compute-", StringComparison.OrdinalIgnoreCase) || x.Equals("stage-vault", StringComparison.OrdinalIgnoreCase)) && !completed.Contains("stage-host-agent"))
            throw new InvalidDataException("A reboot checkpoint contains out-of-order completed stage progress.");
        var expected = ResumeStage(completedStages);
        var stored = root.TryGetProperty("resumeStage", out var stage) ? stage.GetString() : null;
        if (!string.Equals(stored, expected, StringComparison.Ordinal)) throw new InvalidDataException("A reboot checkpoint has inconsistent durable stage progress.");
    }

    private static void ValidateIdentity(JsonElement root, InstallerPlan plan, string role, bool requirePlanTransaction, out string transactionId, out int generation, out bool acknowledgeRootfulDocker)
    {
        var state = root.GetProperty("state").GetString();
        var action = root.GetProperty("action").GetString();
        var checkpointRole = root.GetProperty("role").GetString();
        var payload = root.GetProperty("payloadSha256").GetString();
        transactionId = root.GetProperty("transactionId").GetString() ?? "";
        generation = root.GetProperty("checkpointGeneration").GetInt32();
        var installerVersion = root.GetProperty("installerVersion").GetString();
        var devFleetVersion = root.GetProperty("devFleetVersion").GetString();
        var declaredMaximum = root.GetProperty("maxRebootBoundaries").GetInt32();
        if (!root.TryGetProperty("acknowledgeRootfulDocker", out var acknowledgement) || acknowledgement.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            throw new InvalidDataException("A reboot checkpoint omitted its reviewed rootful Docker acknowledgement state.");
        acknowledgeRootfulDocker = acknowledgement.GetBoolean();
        var generationOk = generation >= 1 && generation <= MaxRebootBoundaries;
        if (state != "waiting-for-reboot" || action != plan.Mode.ToString() || !string.Equals(checkpointRole, role, StringComparison.OrdinalIgnoreCase) || !string.Equals(payload, PayloadManifest.PayloadSha256, StringComparison.OrdinalIgnoreCase) || !string.Equals(installerVersion, PayloadManifest.InstallerVersion, StringComparison.Ordinal) || !string.Equals(devFleetVersion, PayloadManifest.DevFleetVersion, StringComparison.Ordinal) || declaredMaximum != MaxRebootBoundaries || !generationOk || !Regex.IsMatch(transactionId, "^[0-9a-f]{32}$", RegexOptions.CultureInvariant) || (requirePlanTransaction && (!string.Equals(transactionId, plan.TransactionId, StringComparison.Ordinal) || acknowledgeRootfulDocker != plan.AcknowledgeRootfulDocker)) || File.Exists(ConsumedPath(transactionId)))
            throw new InvalidDataException("A stale, tampered, or candidate-mismatched reboot checkpoint is present; refusing resume.");
        ValidateCompletedStages(root, role, out _);
    }

    public static void Write(InstallerPlan plan, string role, string? recovery, Action<string>? progress = null)
    {
        var generation = 1;
        var createdUtc = DateTime.UtcNow.ToString("O");
        if (File.Exists(Path))
        {
            using var prior = JsonDocument.Parse(File.ReadAllText(Path));
            ValidateIdentity(prior.RootElement, plan, role, requirePlanTransaction: true, out _, out var previousGeneration, out _);
            generation = previousGeneration + 1;
            if (prior.RootElement.TryGetProperty("createdUtc", out var created) && created.GetString() is { Length: > 0 } value) createdUtc = value;
        }
        if (generation > MaxRebootBoundaries) throw new InvalidOperationException($"DevFleet installation exceeded the supported reboot boundary limit ({MaxRebootBoundaries}); refusing another reboot.");
        var completedStages = ReadCompletedStages(plan, role);
        var resumeStage = ResumeStage(completedStages);
        StateStore.WriteJsonAtomically(Path, new { state = "waiting-for-reboot", action = plan.Mode.ToString(), plan.TransactionId, installerVersion = PayloadManifest.InstallerVersion, devFleetVersion = PayloadManifest.DevFleetVersion, payloadSha256 = PayloadManifest.PayloadSha256, role, acknowledgeRootfulDocker = plan.AcknowledgeRootfulDocker, completedStages, resumeStage, recoveryPath = recovery, checkpointGeneration = generation, maxRebootBoundaries = MaxRebootBoundaries, createdUtc, updatedUtc = DateTime.UtcNow.ToString("O") });
        progress?.Invoke($"Safe reboot checkpoint persisted: {Path}");
    }

    public static bool ValidateIfPresent(InstallerPlan plan, string role, Action<string>? progress = null)
    {
        if (!File.Exists(Path)) return false;
        using var document = JsonDocument.Parse(File.ReadAllText(Path));
        var root = document.RootElement;
        ValidateIdentity(root, plan, role, requirePlanTransaction: true, out _, out _, out _);
        ValidateActiveTransaction(plan, role);
        progress?.Invoke("Verified durable reboot checkpoint; resuming the same action and candidate without clearing recovery state.");
        return true;
    }

    public static bool BindPlanIfPresent(InstallerPlan plan, string role, Action<string>? progress = null)
    {
        if (!File.Exists(Path)) return false;
        using var document = JsonDocument.Parse(File.ReadAllText(Path));
        var root = document.RootElement;
        var transactionId = root.GetProperty("transactionId").GetString() ?? "";
        ValidateIdentity(root, plan, role, requirePlanTransaction: false, out _, out _, out var acknowledgeRootfulDocker);
        plan.TransactionId = transactionId;
        plan.AcknowledgeRootfulDocker = acknowledgeRootfulDocker;
        ValidateActiveTransaction(plan, role);
        progress?.Invoke("Bound the reviewed plan to the durable reboot transaction and generation.");
        return true;
    }

    public static void Consume(InstallerPlan plan, string role, Action<string>? progress = null)
    {
        if (!File.Exists(Path)) return;
        using var document = JsonDocument.Parse(File.ReadAllText(Path));
        var root = document.RootElement;
        var transactionId = root.GetProperty("transactionId").GetString() ?? "";
        var generation = root.GetProperty("checkpointGeneration").GetInt32();
        if (!Regex.IsMatch(transactionId, "^[0-9a-f]{32}$", RegexOptions.CultureInvariant) || generation < 1 || generation > MaxRebootBoundaries) throw new InvalidDataException("Refusing to consume an invalid reboot checkpoint identity.");
        ValidateIdentity(root, plan, role, requirePlanTransaction: true, out _, out _, out _);
        ValidateActiveTransaction(plan, role);
        var checkpointPayload = root.GetProperty("payloadSha256").GetString();
        if (!string.Equals(checkpointPayload, PayloadManifest.PayloadSha256, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Refusing to consume a checkpoint for a different payload.");
        StateStore.WriteJsonAtomically(ConsumedPath(transactionId), new { transactionId, checkpointGeneration = generation, action = root.GetProperty("action").GetString(), role = root.GetProperty("role").GetString(), installerVersion = root.GetProperty("installerVersion").GetString(), devFleetVersion = root.GetProperty("devFleetVersion").GetString(), payloadSha256 = checkpointPayload, acknowledgeRootfulDocker = root.GetProperty("acknowledgeRootfulDocker").GetBoolean(), completedStages = root.GetProperty("completedStages"), resumeStage = root.GetProperty("resumeStage").GetString(), consumedUtc = DateTime.UtcNow.ToString("O") });
        File.Delete(Path);
        var activePath = System.IO.Path.Combine(ScriptStateRoot, "active-transaction.json");
        if (File.Exists(activePath))
        {
            try { using var active = JsonDocument.Parse(File.ReadAllText(activePath)); if (active.RootElement.GetProperty("transactionId").GetString() == transactionId) File.Delete(activePath); } catch { }
        }
        progress?.Invoke("Durable reboot checkpoint consumed after verified completion.");
    }
}

public sealed record InstallerLaunchRequest(InstallerMode? Action, string? Role, bool ElevatedResume, bool DeferNetworkPairing, bool AcknowledgeRootfulDocker);

public static class InstallerLaunchContract
{
    public static InstallerLaunchRequest Parse(IEnumerable<string> arguments)
    {
        var args = arguments.ToArray();
        static string? ValueAfter(string[] values, string name)
        {
            var index = Array.FindIndex(values, value => value.Equals(name, StringComparison.OrdinalIgnoreCase));
            return index >= 0 && index + 1 < values.Length ? values[index + 1] : null;
        }

        var actionText = ValueAfter(args, "--action");
        InstallerMode? action = Enum.TryParse<InstallerMode>(actionText, true, out var parsedAction) ? parsedAction : null;
        return new InstallerLaunchRequest(
            action,
            ValueAfter(args, "--role"),
            args.Any(value => value.Equals("--elevated-resume", StringComparison.OrdinalIgnoreCase)),
            args.Any(value => value.Equals("--defer-network-pairing", StringComparison.OrdinalIgnoreCase)),
            args.Any(value => value.Equals("--acknowledge-rootful-docker", StringComparison.OrdinalIgnoreCase)));
    }

    public static IReadOnlyList<string> BuildElevatedResumeArguments(string role, InstallerMode mode, bool deferNetworkPairing, bool acknowledgeRootfulDocker)
    {
        var args = new List<string> { "--elevated-resume", "--action", mode.ToString(), "--role", role };
        if (deferNetworkPairing) args.Add("--defer-network-pairing");
        if (acknowledgeRootfulDocker) args.Add("--acknowledge-rootful-docker");
        return args;
    }
}

public static class ElevationService
{
    public static bool IsAdministrator => OperatingSystem.IsWindows() && new System.Security.Principal.WindowsPrincipal(System.Security.Principal.WindowsIdentity.GetCurrent()).IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
    public static Process? RelaunchVerified(string role, InstallerMode mode, bool deferNetworkPairing = false, bool acknowledgeRootfulDocker = false)
    {
        var exe = Environment.ProcessPath ?? throw new InvalidOperationException("The verified installer executable path is unavailable.");
        var startInfo = new ProcessStartInfo { FileName = exe, Verb = "runas", UseShellExecute = true };
        foreach (var argument in InstallerLaunchContract.BuildElevatedResumeArguments(role, mode, deferNetworkPairing, acknowledgeRootfulDocker)) startInfo.ArgumentList.Add(argument);
        return Process.Start(startInfo);
    }
}

public static class LifecycleEngine
{
    public static InstallerExecutionReport? LastExecution { get; private set; }
    private static void AssertExactFactoryResetSelection(InstallerPlan plan)
    {
        if (plan.Mode != InstallerMode.FactoryReset || !plan.ProjectDataSelected) return;
        var requested = plan.SelectedProjectIds.Select(x => x.Trim()).Where(x => x.Length > 0).ToArray();
        if (requested.Length != requested.Distinct(StringComparer.OrdinalIgnoreCase).Count()) throw new InvalidOperationException("Factory Reset blocked: the reviewed execution set contains duplicate project IDs.");
        var reviewedIds = plan.SelectedProjects.Select(x => x.ProjectId.Trim()).Where(x => x.Length > 0).ToArray();
        if (reviewedIds.Length != requested.Length || reviewedIds.Length != reviewedIds.Distinct(StringComparer.OrdinalIgnoreCase).Count() || !reviewedIds.ToHashSet(StringComparer.OrdinalIgnoreCase).SetEquals(requested))
            throw new InvalidOperationException("Factory Reset blocked: the reviewed project records do not exactly match the requested execution set. Review and confirm again.");
        var current = new ProjectDiscoveryService().Discover();
        var currentSelected = current.Where(x => requested.Contains(x.ProjectId, StringComparer.OrdinalIgnoreCase)).ToArray();
        if (currentSelected.Length != requested.Length || !currentSelected.Select(x => x.ProjectId).ToHashSet(StringComparer.OrdinalIgnoreCase).SetEquals(requested)) throw new InvalidOperationException("Factory Reset blocked: the exact reviewed project selection changed before execution. Review and confirm again.");
        foreach (var reviewed in plan.SelectedProjects)
        {
            var now = currentSelected.SingleOrDefault(x => x.ProjectId.Equals(reviewed.ProjectId, StringComparison.OrdinalIgnoreCase));
            if (now is null || !now.Slug.Equals(reviewed.Slug, StringComparison.Ordinal) || !now.RuntimeId.Equals(reviewed.RuntimeId, StringComparison.Ordinal) || !now.OwnershipStatus.Equals("VERIFIED", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException($"Factory Reset blocked: reviewed project identity or ownership drifted for {reviewed.ProjectId}. Review and confirm again.");
        }
    }
    public static string Execute(InstallerPlan plan, string role, Action<string>? progress = null)
    {
        if (!plan.IsAllowed) throw new InvalidOperationException(string.Join(Environment.NewLine, plan.Blockers));
        if (plan.IsMutation && !ElevationService.IsAdministrator && !TestEnvironment.IsTestProcess)
            throw new InvalidOperationException("Machine-wide mutation requires UAC elevation. Relaunch the same verified installer with runas before executing.");
        var logger = new InstallerLogger();
        var tx = new TransactionService(logger);
        var ledger = StateStore.ReadLedger();
        var previousLedger = ledger;
        string? recovery = null;
        string? controlPlaneSnapshot = null;
        try
        {
            var resumed = RebootCheckpointService.ValidateIfPresent(plan, role, progress);
            if (plan.Mode is InstallerMode.Diagnostics or InstallerMode.RecoveryPackage) return PreflightService.ToText(PreflightService.Run());
            if (plan.Mode is InstallerMode.CleanReinstall or InstallerMode.Uninstall or InstallerMode.FactoryReset)
                recovery = RecoveryService.Create(plan.TransactionId, progress);
            if (plan.Mode == InstallerMode.CleanReinstall)
                controlPlaneSnapshot = ControlPlaneSnapshotService.Capture(plan.TransactionId, progress);
            if (plan.Mode == InstallerMode.FactoryReset && plan.ProjectDataSelected)
            {
                if (plan.SelectedProjects.Count == 0) throw new InvalidOperationException("Factory Reset blocked: no individual project is selected.");
                AssertExactFactoryResetSelection(plan);
                var factoryReset = new FactoryResetService(new BackupVerificationService(), new VmOwnershipService(new MultipassHostAgentProvider()));
                foreach (var project in plan.SelectedProjects) factoryReset.DeleteSelected(project, progress);
            }
            if (plan.Mode is InstallerMode.Uninstall or InstallerMode.FactoryReset)
                CleanupJournalService.Execute(plan.Mode.ToString(), plan.TransactionId, BuildMonotonicCleanupStages(ledger, progress), progress, ledger.InstallTimestampUtc, ledger.PackageSha256);
            else if (plan.Mode == InstallerMode.CleanReinstall)
                progress?.Invoke("Clean Reinstall is staged transactionally; the previous control plane remains available until replacement verification.");
            if (plan.Mode is InstallerMode.FreshInstall or InstallerMode.Repair or InstallerMode.CleanReinstall or InstallerMode.LocalUpdate)
            {
                var preparedUtc = RebootCheckpointService.PrepareScriptTransaction(plan, role, progress);
                var staged = PayloadService.StageVerifiedPayload(plan.TransactionId, progress);
                var releaseRoot = PayloadService.ExtractVerifiedPayload(staged, plan.TransactionId, progress);
                var fixture = TestEnvironment.IsTestProcess && string.Equals(Environment.GetEnvironmentVariable("DEVFLEET_SETUP_FIXTURE_MODE"), "1", StringComparison.Ordinal);
                if (plan.Mode == InstallerMode.Repair)
                {
                    var report = new RepairService(new InstallService(fixture ? new RecordingProcessRunner() : null)).Repair(releaseRoot, role, progress, plan.DeferNetworkPairing, plan.AcknowledgeRootfulDocker, plan.TransactionId, PayloadManifest.PayloadSha256, plan.Mode.ToString(), role, preparedUtc);
                    LastExecution = report;
                    progress?.Invoke($"Real repair entry-point completion verified: {string.Join(" -> ", report.Stages)}");
                }
                else
                {
                    var report = new InstallService(fixture ? new RecordingProcessRunner() : null).Run(releaseRoot, role, plan.Mode.ToString(), progress, plan.DeferNetworkPairing, plan.AcknowledgeRootfulDocker, plan.TransactionId, PayloadManifest.PayloadSha256, plan.Mode.ToString(), role, preparedUtc);
                    LastExecution = report;
                    if (report.ExitCode == 3010) throw new RebootRequiredException("DevFleet installation reached a safe reboot checkpoint.");
                    progress?.Invoke($"Real installer stage map complete: {string.Join(" -> ", report.Stages)}");
                }
                ledger = BuildLedger(releaseRoot, role, recovery);
                InstallStableLauncher(ledger, progress);
                CreateInstalledAppEntry(ledger); CreateShortcuts(ledger, progress);
                StateStore.WriteLedger(ledger); progress?.Invoke("Ownership ledger committed after verification.");
            }
            if (plan.Mode is InstallerMode.Uninstall or InstallerMode.FactoryReset)
            {
                foreach (var key in ledger.RegistryEntriesCreated) RemoveExactRegistryEntry(key, progress);
                File.Delete(AppPaths.LedgerPath);
            }
            logger.Write($"transaction={plan.TransactionId} state=completed");
            if (controlPlaneSnapshot is not null) ControlPlaneSnapshotService.Delete(controlPlaneSnapshot);
            RebootCheckpointService.Consume(plan, role, progress);
            return recovery ?? logger.LogPath;
        }
        catch (RebootRequiredException ex)
        {
            RebootCheckpointService.Write(plan, role, recovery, progress);
            logger.Write($"transaction={plan.TransactionId} state=waiting-for-reboot");
            progress?.Invoke($"Waiting for reboot: {ex.Message} Rerun DevFleet Setup to resume.");
            return recovery ?? logger.LogPath;
        }
        catch (Exception ex)
        {
            logger.Write($"transaction={plan.TransactionId} state=failed error={ex.Message}");
            if (plan.Mode is not (InstallerMode.Uninstall or InstallerMode.FactoryReset)) tx.Rollback(progress);
            if (controlPlaneSnapshot is not null)
            {
                ControlPlaneSnapshotService.Restore(controlPlaneSnapshot, progress);
                StateStore.WriteLedger(previousLedger);
            }
            throw;
        }
    }

    private static string JsonString(JsonElement value, string name) => value.TryGetProperty(name, out var property) ? property.ToString() : "";

    private static void ImportWindowsIntegrationOwnership(InstallLedger ledger)
    {
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "DevFleetHostAgent", "integration-ownership.json");
        if (!File.Exists(path)) return;
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var root = document.RootElement;
        if (root.GetProperty("SchemaVersion").GetInt32() != 1) throw new InvalidDataException("Windows integration ownership schema is unsupported.");
        ledger.InstallationGeneration = JsonString(root, "InstallationGeneration");
        ledger.WindowsIntegrationOwnershipPath = path;
        var marker = JsonString(root, "Marker");
        foreach (var item in root.GetProperty("ScheduledTasks").EnumerateArray())
            ledger.WindowsIntegrations.Add(new OwnedWindowsIntegration("ScheduledTask", JsonString(item, "Name"), JsonString(item, "Generation"), JsonString(item, "Marker") is { Length: > 0 } taskMarker ? taskMarker : marker, Executable: JsonString(item, "Executable"), Arguments: JsonString(item, "Arguments"), Principal: JsonString(item, "Principal"), LogonType: JsonString(item, "LogonType"), RunLevel: JsonString(item, "RunLevel"), Description: JsonString(item, "Description")));
        foreach (var item in root.GetProperty("FirewallRules").EnumerateArray())
            ledger.WindowsIntegrations.Add(new OwnedWindowsIntegration("FirewallRule", JsonString(item, "Name"), JsonString(item, "Generation"), JsonString(item, "Marker") is { Length: > 0 } firewallMarker ? firewallMarker : marker, Description: JsonString(item, "Description"), DisplayName: JsonString(item, "DisplayName"), Group: JsonString(item, "Group"), Direction: JsonString(item, "Direction"), Action: JsonString(item, "Action"), Protocol: JsonString(item, "Protocol"), LocalPort: JsonString(item, "LocalPort"), InterfaceAlias: JsonString(item, "InterfaceAlias"), RemoteAddress: JsonString(item, "RemoteAddress"), Profile: JsonString(item, "Profile")));
        foreach (var item in root.GetProperty("Services").EnumerateArray())
            ledger.WindowsIntegrations.Add(new OwnedWindowsIntegration("Service", JsonString(item, "Name"), JsonString(item, "Generation"), JsonString(item, "Marker") is { Length: > 0 } serviceMarker ? serviceMarker : marker, ImagePath: JsonString(item, "ImagePath"), Account: JsonString(item, "Account"), StartMode: JsonString(item, "StartMode")));
    }

    private static InstallLedger BuildLedger(string releaseRoot, string role, string? recovery)
    {
        var ledger = new InstallLedger { Role = role, PackageSha256 = PayloadManifest.PayloadSha256, InstallTimestampUtc = DateTime.UtcNow.ToString("O") };
        ledger.FilesInstalled.AddRange(Directory.EnumerateFiles(releaseRoot, "*", SearchOption.AllDirectories));
        ledger.OwnedResources.Add(new OwnedResource("release", "DevFleet release payload", "DevFleetLedger", releaseRoot));
        if (recovery is not null) ledger.OwnedResources.Add(new OwnedResource("recovery", "Recovery package", "DevFleetLedger", recovery));
        foreach (var dependency in new DependencyService().DetectAll().Where(x => x.Found))
        {
            ledger.PreExistingPrerequisites.Add($"{dependency.Name} {dependency.Version}");
            ledger.ResolvedPrerequisitePaths.Add($"{dependency.Name}|{dependency.ExecutablePath}");
        }
        ledger.ManagedSshMarkers.Add("# BEGIN DEVFLEET MANAGED|# END DEVFL