# DevFleet source part 075

Full-source UTF-8 byte interval [3441000, 3487500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 8c680a9bdd0fa8e5ece7fedaf92d701f1028946dcf96ce623ed20f64153a1483

<!-- BEGIN SOURCE SLICE -->
.get("backup_verified")), backup_id=str(kwargs.get("backup_id") or ""), backup_sha256=str(kwargs.get("backup_sha256") or ""), cleanup_only=bool(kwargs.get("cleanup_only")), runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def reconcile(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return self.inspect(slug, metadata)

    def refresh(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return refresh_project_vm_connection_state(slug, str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def command(self, slug: str, metadata: dict[str, Any], operation: str, *, command_key: str = "", tail: int = 150) -> dict[str, Any]:
        return project_vm_operation(slug, operation, runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""), command_key=command_key, tail=tail)

    def logs(self, slug: str, metadata: dict[str, Any], *, tail: int = 150) -> dict[str, Any]:
        return self.command(slug, metadata, "project-logs", tail=tail)

    def export(self, slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return export_project_workspace(slug, str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def list_backups(self, slug: str, metadata: dict[str, Any]) -> list[dict[str, Any]]:
        return list_project_vm_backups(slug, runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def inspect_backup(self, slug: str, metadata: dict[str, Any], backup_id: str) -> dict[str, Any]:
        return inspect_project_vm_backup(slug, backup_id, runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def restore_backup(self, slug: str, metadata: dict[str, Any], backup_id: str, *, confirm_restore: bool = False) -> dict[str, Any]:
        return restore_project_vm_backup(slug, backup_id, confirm_restore=confirm_restore, runtime_id=str(metadata.get("runtime_id") or ""), project_id=str(metadata.get("project_id") or ""))

    def export_to_source(self, slug: str, metadata: dict[str, Any], *, source_vm: str, replace_source: bool = False) -> dict[str, Any]:
        return export_project_workspace_to_source(slug, str(metadata.get("runtime_id") or ""), source_vm=source_vm, project_id=str(metadata.get("project_id") or ""), replace_source=replace_source)

    def restore_previous_source(self, slug: str, metadata: dict[str, Any], *, source_vm: str, previous_workspace_path: str) -> dict[str, Any]:
        return restore_previous_source_workspace(slug, str(metadata.get("runtime_id") or ""), source_vm=source_vm, project_id=str(metadata.get("project_id") or ""), previous_workspace_path=previous_workspace_path)


VM_RUNTIME = MultipassRuntimeProvider()


class VmRuntimeOperations:
    """Compatibility facade for existing project lifecycle code."""

    @staticmethod
    def ensure(slug: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return VM_RUNTIME.create(slug, metadata)

    @staticmethod
    def start(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.start(slug, metadata or {})

    @staticmethod
    def stop(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.stop(slug, metadata or {})

    @staticmethod
    def restart(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.restart(slug, metadata or {})

    @staticmethod
    def inspect(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.inspect(slug, metadata or {})

    @staticmethod
    def refresh(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.refresh(slug, metadata or {})

    @staticmethod
    def health(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.health(slug, metadata or {})

    @staticmethod
    def backup(slug: str, metadata: dict[str, Any] | None = None, *, consistency_level: str = "live-best-effort", destructive: bool = False) -> dict[str, Any]:
        return VM_RUNTIME.backup(slug, metadata or {}, consistency_level=consistency_level, destructive=destructive)

    @staticmethod
    def quarantine(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.quarantine(slug, metadata or {})

    @staticmethod
    def restore(slug: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        return VM_RUNTIME.restore(slug, metadata or {})

    @staticmethod
    def command(slug: str, metadata: dict[str, Any] | None, operation: str, *, command_key: str = "", tail: int = 150) -> dict[str, Any]:
        return VM_RUNTIME.command(slug, metadata or {}, operation, command_key=command_key, tail=tail)

    @staticmethod
    def destroy(slug: str, metadata: dict[str, Any], **kwargs: Any) -> dict[str, Any]:
        return VM_RUNTIME.destroy(slug, metadata, **kwargs)


def host_capacity() -> dict[str, Any]:
    return get_host_capacity()


def provider_status() -> dict[str, Any]:
    return get_provider_status()

```


## FILE: source/app/devfleet/status.py

SHA256: d5c260df7828b383aa6c7f1d6ff2735783430e5db5457bdd2d5989316164607c | Bytes: 14255 | Git mode: 100644

```
from __future__ import annotations
import json,os,shutil,socket,time,threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any
import httpx,psutil
from .core import SETTINGS,load_peer,run
from .projects import list_projects,list_project_catalog
from .ollama import ollama_health
from .operations import list_operations
from .containers import list_containers
from .host_control import get_host_capacity,get_provider_status,host_control_status
from .version import __version__
from .node_registry import NodeRegistry
from urllib.parse import urlsplit

_RUNTIME_CACHE: tuple[float,dict[str,Any]]|None=None
_SNAPSHOT_LOCK=threading.RLock()
_SNAPSHOT_EXECUTOR=ThreadPoolExecutor(max_workers=2,thread_name_prefix='devfleet-snapshot')
_SNAPSHOTS:dict[str,dict[str,Any]]={
 'runtime':{'value':None,'updated_at':0.0,'refreshing':False,'last_duration_ms':None,'error':'','retry_after':0.0,'failures':0},
 'cluster':{'value':None,'updated_at':0.0,'refreshing':False,'last_duration_ms':None,'error':'','retry_after':0.0,'failures':0},
}
_SNAPSHOT_TTLS={'runtime':5.0,'cluster':20.0}
_PEER_BACKOFF_BASE=2.0;_PEER_BACKOFF_MAX=60.0;_PEER_FAILURE_WINDOW=300.0
_PEER_STATE={'failures':0,'last_failure':0.0,'retry_after':0.0,'circuit_until':0.0,'value':None,'inflight':False}

def _node_identity()->dict[str,Any]:
 try:
  registry=NodeRegistry().load();nodes=registry.get('nodes',[]) if isinstance(registry,dict) else []
  local=next((item for item in nodes if isinstance(item,dict) and item.get('node_name')==SETTINGS.node_name),None)
  return {'deployment_id':registry.get('deployment_id',''),'node_id':(local or {}).get('node_id',''),'node_role':(local or {}).get('node_role',SETTINGS.node_role),'coordinator_node_id':(local or {}).get('coordinator_node_id')}
 except (OSError,ValueError,TypeError):
  return {'deployment_id':'','node_id':'','node_role':SETTINGS.node_role,'coordinator_node_id':None}

_BACKUP_STATUS_PATH=Path('/var/lib/devfleet/backup-status/latest.json')
_BACKUP_CONFIG_PATH=Path('/var/lib/devfleet/backup-status/config.json')

def _backup_snapshot()->dict[str,Any]:
 try:
  data=json.loads(_BACKUP_STATUS_PATH.read_text(encoding='utf-8'))
  return data if isinstance(data,dict) else {}
 except (OSError,json.JSONDecodeError): return {}

def _cheap_runtime()->dict[str,Any]:
 hour=time.localtime().tm_hour;greeting='Good morning' if hour < 12 else 'Good afternoon' if hour < 18 else 'Good evening'
 return {'node':SETTINGS.node_name,'friendly_name':SETTINGS.friendly_name,'role':SETTINGS.node_role,'version':__version__,'greeting':f'{greeting}, developer','profile':SETTINGS.development_profile,'docker':{},'containers':[],'backup':backup_status(),'ollama':{'status':'not-yet-refreshed'},'system':{},'vault':{'status':'not-yet-refreshed'},'host_agent':{'status':'not-yet-refreshed'},'host_capacity':{'status':'not-yet-refreshed'},'vm_provider':{'status':'not-yet-refreshed'}}

def _refresh_snapshot(name:str)->None:
 with _SNAPSHOT_LOCK:
  state=_SNAPSHOTS[name]
  state['refreshing']=True
 started=time.monotonic()
 try:
  value=runtime_status() if name=='runtime' else cluster_status()
  error=''
 except Exception as exc:
  value=None;error=str(exc)[-500:]
 with _SNAPSHOT_LOCK:
   state=_SNAPSHOTS[name];state['refreshing']=False;state['last_duration_ms']=round((time.monotonic()-started)*1000,2);state['error']=error;now=time.monotonic()
   if value is not None:state['value']=value;state['updated_at']=now;state['retry_after']=0.0;state['failures']=0
   else:
    state['failures']=min(int(state.get('failures',0))+1,8);delay=min(60.0,2.0*(2**(state['failures']-1)));state['retry_after']=now+delay;state['updated_at']=now

def _schedule_snapshot(name:str)->None:
 with _SNAPSHOT_LOCK:
  if _SNAPSHOTS[name]['refreshing']:return
  # Reserve the refresh before submitting: concurrent readers can never queue
  # duplicate work between the check and executor.submit().
  _SNAPSHOTS[name]['refreshing']=True
 try:
  _SNAPSHOT_EXECUTOR.submit(_refresh_snapshot,name)
 except Exception:
  with _SNAPSHOT_LOCK:_SNAPSHOTS[name]['refreshing']=False

def _snapshot(name:str)->dict[str,Any]:
 now=time.monotonic()
 with _SNAPSHOT_LOCK:
  state=dict(_SNAPSHOTS[name]);value=state.get('value') or (_cheap_runtime() if name=='runtime' else {'updated_at':'','nodes':[],'containers':[]})
  age=(now-state['updated_at']) if state['updated_at'] else None
  stale=age is None or age>_SNAPSHOT_TTLS[name]
  refreshing=bool(state['refreshing']);retry_after=float(state.get('retry_after',0.0) or 0.0)
  if stale and now>=retry_after:_schedule_snapshot(name)
 result=dict(value);result['snapshot']={'last_updated':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime(time.time()-age)) if age is not None else None,'age_seconds':round(age,3) if age is not None else None,'stale':stale,'refreshing':refreshing,'last_duration_ms':state.get('last_duration_ms'),'error':state.get('error','')}
 return result

def runtime_snapshot()->dict[str,Any]:return _snapshot('runtime')
def cluster_snapshot()->dict[str,Any]:return _snapshot('cluster')
def docker_status()->dict[str,Any]:
 try:r=run(['docker','info','--format','{{json .}}'],check=False,timeout=3)
 except Exception as exc:return {'ok':False,'mode':SETTINGS.docker_mode,'error':f'Docker status probe timed out: {exc}'}
 if r.returncode:return {'ok':False,'mode':SETTINGS.docker_mode,'error':r.stderr[-500:]}
 try:
  d=json.loads(r.stdout);return {'ok':True,'mode':SETTINGS.docker_mode,'rootless':any('rootless' in str(x) for x in d.get('SecurityOptions') or []),'containers':d.get('Containers'),'images':d.get('Images'),'driver':d.get('Driver'),'docker_root_dir':d.get('DockerRootDir')}
 except Exception as exc:return {'ok':False,'mode':SETTINGS.docker_mode,'error':str(exc)}

def system_status()->dict[str,Any]:
 disk=shutil.disk_usage(SETTINGS.workspaces)
 return {'cpu_percent':psutil.cpu_percent(interval=.05),'memory_percent':psutil.virtual_memory().percent,'disk_free_gb':round(disk.free/1024**3,1),'load':list(os.getloadavg()) if hasattr(os,'getloadavg') else []}

def vault_status()->dict[str,Any]:
 """Probe the append-only vault listener without requiring Docker or exposing credentials."""
 config_path=_BACKUP_CONFIG_PATH
 if not config_path.is_file():return {'configured':False,'status':'not-configured'}
 repository=''
 try: repository=str((json.loads(config_path.read_text(encoding='utf-8')) or {}).get('repository') or '')
 except (OSError,json.JSONDecodeError): return {'configured':True,'reachable':False,'status':'invalid-status-record'}
 if repository.startswith('rest:'):repository=repository[5:]
 parsed=urlsplit(repository)
 if parsed.scheme not in {'http','https'} or not parsed.hostname or not parsed.port:
  return {'configured':True,'reachable':False,'status':'invalid-repository-url'}
 started=time.monotonic()
 try:
  with socket.create_connection((parsed.hostname,parsed.port),timeout=1.5):pass
  return {'configured':True,'reachable':True,'status':'reachable','host':parsed.hostname,'port':parsed.port,'probe_ms':round((time.monotonic()-started)*1000)}
 except OSError as exc:
  return {'configured':True,'reachable':False,'status':'unreachable','host':parsed.hostname,'port':parsed.port,'error':str(exc)[-500:]}

def runtime_status()->dict[str,Any]:
 global _RUNTIME_CACHE
 now=time.monotonic()
 if _RUNTIME_CACHE and now-_RUNTIME_CACHE[0] < 2.0:return _RUNTIME_CACHE[1]
 docker=docker_status()
 try:containers=list_containers()
 except Exception as exc:containers=[];docker={**docker,'container_probe_error':str(exc)[-500:]}
 agent=host_control_status()
 capacity={'configured':False,'status':'not-configured'}
 provider={'configured':False,'status':'not-configured'}
 if agent.get('configured'):
  if agent.get('reachable'):
   try:capacity={'configured':True,'status':'ok',**get_host_capacity()}
   except Exception as exc:capacity={'configured':True,'status':'unavailable','error':str(exc)[-500:]}
   try:provider={'configured':True,'status':'ok',**get_provider_status()}
   except Exception as exc:provider={'configured':True,'status':'unavailable','error':str(exc)[-500:]}
  else:
   capacity={'configured':True,'status':'unreachable','error':agent.get('error','Host agent is unreachable.')}
   provider={'configured':True,'status':'unreachable','error':agent.get('error','Host agent is unreachable.')}
 raw_capacity=capacity.get('capacity',capacity) if isinstance(capacity,dict) else {}
 normalized_capacity={**raw_capacity,'configured':capacity.get('configured',False),'status':capacity.get('status',raw_capacity.get('health','unavailable')),'available':bool(capacity.get('ok',False) and raw_capacity),'reason':capacity.get('error','') or ('' if raw_capacity else 'Host capacity has not been checked.')}
 hour=time.localtime().tm_hour;greeting='Good morning' if hour < 12 else 'Good afternoon' if hour < 18 else 'Good evening'
 value={'node':SETTINGS.node_name,'friendly_name':SETTINGS.friendly_name,'role':SETTINGS.node_role,'node_identity':_node_identity(),'version':__version__,'greeting':f'{greeting}, developer','profile':SETTINGS.development_profile,'docker':docker,'containers':containers,'backup':backup_status(),'ollama':ollama_health(),'system':system_status(),'vault':vault_status(),'host_agent':agent,'host_capacity':normalized_capacity,'vm_provider':provider}
 _RUNTIME_CACHE=(now,value)
 return value
def backup_status()->dict[str,Any]:
 snapshot=_backup_snapshot()
 if not snapshot:return {'configured':_BACKUP_CONFIG_PATH.exists(),'status':'not-yet-refreshed'}
 # Restic may wait on repository/network state for many seconds. Do not make
 # every dashboard render wait on that probe; the backup action/diagnostics
 # remain responsible for authoritative backup verification.
 return {'configured':True,**snapshot}
def local_status(*,live:bool=False)->dict[str,Any]:
 runtime=runtime_status() if live else runtime_snapshot()
 return {**runtime,'projects':list_projects() if live else list_project_catalog(),'operations':list_operations(20)}

def peer_node_status()->dict[str,Any]:
 peer=load_peer()
 if not peer.get('Url') or not peer.get('Token'):return {'configured':False,'status':'not-configured'}
 now=time.monotonic()
 with _SNAPSHOT_LOCK:
   if _PEER_STATE.get('last_failure') and now-_PEER_STATE['last_failure']>_PEER_FAILURE_WINDOW:_PEER_STATE.update({'failures':0,'retry_after':0.0,'circuit_until':0.0})
   if now < _PEER_STATE['retry_after']:
    cached=_PEER_STATE.get('value');return cached if isinstance(cached,dict) else {'configured':True,'ok':False,'status':'backoff','retry_after':round(_PEER_STATE['retry_after']-now,2)}
   if now < _PEER_STATE['circuit_until']:
    cached=_PEER_STATE.get('value');return cached if isinstance(cached,dict) else {'configured':True,'ok':False,'status':'circuit-open'}
   if _PEER_STATE.get('inflight'):
    cached=_PEER_STATE.get('value');return cached if isinstance(cached,dict) else {'configured':True,'ok':False,'status':'refreshing'}
   _PEER_STATE['inflight']=True
 try:
  base=peer['Url'].rstrip('/');headers={'X-DevFleet-Token':peer['Token']};started=time.monotonic()
  r=httpx.get(base+'/api/node/status',headers=headers,timeout=2.5)
  if r.status_code==404:
   # v1.1 peers expose /api/status, which includes project and container
   # inventory and is slower than the lightweight node endpoint. Do not
   # classify a healthy peer as offline merely because this fallback needs
   # a few seconds to assemble its inventory.
   legacy=httpx.get(base+'/api/status',headers=headers,timeout=4.5);legacy.raise_for_status();data=legacy.json();data.setdefault('containers',[]);data['compatibility']='legacy';data['probe_ms']=round((time.monotonic()-started)*1000)
  else:
   r.raise_for_status();data=r.json();data['probe_ms']=round((time.monotonic()-started)*1000)
  result={'configured':True,'ok':True,'node':data}
  with _SNAPSHOT_LOCK:_PEER_STATE.update({'failures':0,'last_failure':0.0,'retry_after':0.0,'circuit_until':0.0,'value':result,'inflight':False})
  return result
 except Exception as exc:
  with _SNAPSHOT_LOCK:
   failures=_PEER_STATE['failures']+1;_PEER_STATE['failures']=failures;_PEER_STATE['last_failure']=now
   delay=min(_PEER_BACKOFF_MAX,_PEER_BACKOFF_BASE*(2**min(failures-1,5)));_PEER_STATE['retry_after']=time.monotonic()+delay
   if failures>=3:_PEER_STATE['circuit_until']=time.monotonic()+min(_PEER_BACKOFF_MAX,delay*2)
   _PEER_STATE['inflight']=False
  return {'configured':True,'ok':False,'status':'unreachable','error':str(exc)[-500:],'retry_after':round(delay,2)}

def cluster_status()->dict[str,Any]:
 local=runtime_status();peer=peer_node_status();nodes=[{**local,'id':local['node'],'status':'online','reachable':True,'destination_selectable':True}]
 if peer.get('ok'):
  remote=peer.get('node') or {};nodes.append({**remote,'id':remote.get('node','devfleet-failover'),'status':'online','reachable':True,'destination_selectable':True})
 else:
  nodes.append({'id':'devfleet-failover','node':'devfleet-failover','friendly_name':'DevFleetFailover','role':'failover','status':'offline','reachable':False,'destination_selectable':False,'error':peer.get('error') or peer.get('status','unavailable'),'containers':[],'docker':{'ok':False},'system':{}})
 vault=vault_status();nodes.append({'id':'devfleet-vault','node':'devfleet-vault','friendly_name':'DevFleetVault','role':'vault','status':'online' if vault.get('reachable') else 'offline','reachable':bool(vault.get('reachable')),'vault':vault,'containers':[],'docker':{'ok':False,'mode':'not-applicable'},'system':{}})
 containers=[]
 for node in nodes:
  for item in node.get('containers') or []:
   containers.append({**item,'node_id':node['id'],'node_name':node.get('friendly_name') or node['id'],'control_scope':'peer' if node['id']=='devfleet-failover' else 'local'})
 return {'updated_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'nodes':nodes,'containers':containers}
def peer_status()->dict[str,Any]:
 peer=load_peer()
 if not peer.get('Url') or not peer.get('Token'):return {'configured':False}
 try:
  r=httpx.get(peer['Url'].rstrip('/')+'/api/status',headers={'X-DevFleet-Token':peer['Token']},timeout=4.5);r.raise_for_status();return {'configured':True,'ok':True,'peer':r.json()}
 except Exception as exc:return {'configured':True,'ok':False,'error':str(exc)}

```


## FILE: source/app/devfleet/version.py

SHA256: a0a9c477ebd09f6fa0713427174d3f86c685de2004badcd8f0c8dfc039dd4251 | Bytes: 744 | Git mode: 100644

```
"""Single package-version source shared by API, UI, and release tooling."""
from __future__ import annotations

import os
from pathlib import Path


def package_version() -> str:
    configured = str(os.environ.get("DEVFLEET_VERSION", "")).strip()
    candidates = [Path(configured)] if configured else []
    here = Path(__file__).resolve()
    candidates.extend((here.parents[1] / "VERSION", here.parents[2] / "VERSION"))
    for path in candidates:
        try:
            value = path.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if value:
            return value
    raise RuntimeError("DevFleet VERSION file is missing or empty; refusing a stale fallback.")


__version__ = package_version()

```


## FILE: source/app/devfleet/workspace_archives.py

SHA256: fcc44f267e3c4d0e8f9a674fa52a1675d46a5cb9877af27f8bc3868643605c0f | Bytes: 52391 | Git mode: 100644

```
"""Verified workspace archives used by migration, backup, and deletion gates.

The archive format is deliberately boring: a gzip tar with one top-level
project directory.  We validate the source before writing and validate the
archive again after writing so a backup is never reported as verified merely
because a command returned zero.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import tarfile
import tempfile
import shutil
import uuid
import contextlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from .core import atomic_json, now_iso, validate_slug


GENERATED_DIR_NAMES = {
    "node_modules", ".next", "build", "dist", ".venv", "venv",
    ".pytest_cache", "__pycache__", ".test-runtime",
}


# Linux is the deployed control-plane target.  Its openat/no-follow primitives
# let the archive code bind authorization to an already-open object instead of
# asking tarfile to reopen a mutable pathname.  Windows retains the historical
# compatibility implementation below; it is not promoted as Linux identity
# evidence.
POSIX_FD_HARDENING = os.name == "posix" and hasattr(os, "O_NOFOLLOW") and hasattr(os, "supports_dir_fd")


def _object_identity(result: os.stat_result) -> dict[str, int]:
    return {
        "st_dev": int(result.st_dev),
        "st_ino": int(result.st_ino),
        "st_type": int(stat.S_IFMT(result.st_mode)),
    }


def _identity_matches(result: os.stat_result, expected: dict[str, int] | None) -> bool:
    return expected is not None and _object_identity(result) == expected


def _fd_directory_flags() -> int:
    return os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)


def _fd_regular_flags() -> int:
    return os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)


def _open_verified_child(parent_fd: int, name: str, kind: int) -> tuple[int, os.stat_result]:
    observed = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if stat.S_IFMT(observed.st_mode) != kind:
        raise ValueError(f"Workspace entry changed type before it could be opened: {name}")
    if kind == stat.S_IFREG and observed.st_nlink != 1:
        raise ValueError(f"Workspace entry has an unexpected hard-link count: {name}")
    flags = _fd_directory_flags() if kind == stat.S_IFDIR else _fd_regular_flags()
    try:
        fd = os.open(name, flags, dir_fd=parent_fd)
    except OSError as exc:
        raise ValueError(f"Workspace entry could not be opened without following aliases: {name}") from exc
    try:
        actual = os.fstat(fd)
        if not _identity_matches(actual, _object_identity(observed)):
            raise ValueError(f"Workspace entry identity changed before it could be authorized: {name}")
        return fd, actual
    except Exception:
        os.close(fd)
        raise


def _open_verified_root(root: Path) -> tuple[int, os.stat_result, Path]:
    lexical = Path(os.path.abspath(os.fspath(root)))
    observed = os.lstat(lexical)
    if stat.S_IFMT(observed.st_mode) != stat.S_IFDIR:
        raise ValueError("Workspace must be a real directory.")
    try:
        fd = os.open(lexical, _fd_directory_flags())
    except OSError as exc:
        raise ValueError("Workspace root could not be opened without following aliases.") from exc
    try:
        actual = os.fstat(fd)
        if not _identity_matches(actual, _object_identity(observed)):
            raise ValueError("Workspace root identity changed before it could be authorized.")
        return fd, actual, lexical
    except Exception:
        os.close(fd)
        raise


@dataclass
class _AuthorizedEntry:
    name: str
    kind: int
    result: os.stat_result
    fd: int | None


def _scan_generated_fd(fd: int) -> tuple[int, int]:
    count = 0
    total = 0
    for name in sorted(os.listdir(fd)):
        result = os.stat(name, dir_fd=fd, follow_symlinks=False)
        kind = stat.S_IFMT(result.st_mode)
        if kind == stat.S_IFLNK:
            continue
        if kind == stat.S_IFDIR:
            child_fd, _ = _open_verified_child(fd, name, stat.S_IFDIR)
            try:
                child_count, child_total = _scan_generated_fd(child_fd)
                count += child_count
                total += child_total
            finally:
                os.close(child_fd)
        elif kind == stat.S_IFREG:
            child_fd, child_result = _open_verified_child(fd, name, stat.S_IFREG)
            os.close(child_fd)
            count += 1
            total += int(child_result.st_size)
        else:
            raise ValueError(f"Unsupported generated workspace entry: {name}")
    return count, total


def _capture_workspace_posix(root: Path, *, include_generated: bool) -> tuple[dict[str, Any], list[_AuthorizedEntry]]:
    root_fd, root_result, lexical_root = _open_verified_root(root)
    entries: list[_AuthorizedEntry] = [_AuthorizedEntry("", stat.S_IFDIR, root_result, root_fd)]
    symlinks: list[str] = []
    symlink_targets: dict[str, str] = {}
    generated: list[str] = []
    generated_details: list[dict[str, Any]] = []
    files = 0
    bytes_total = 0

    def walk(parent_fd: int, prefix: str) -> None:
        nonlocal files, bytes_total
        for name in sorted(os.listdir(parent_fd)):
            rel = f"{prefix}/{name}" if prefix else name
            result = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
            kind = stat.S_IFMT(result.st_mode)
            if kind == stat.S_IFLNK:
                symlinks.append(rel)
                symlink_targets[rel] = os.readlink(name, dir_fd=parent_fd)
                continue
            if kind == stat.S_IFDIR:
                child_fd, child_result = _open_verified_child(parent_fd, name, stat.S_IFDIR)
                if name in GENERATED_DIR_NAMES and not include_generated:
                    try:
                        excluded_files, excluded_bytes = _scan_generated_fd(child_fd)
                    finally:
                        os.close(child_fd)
                    generated.append(rel)
                    generated_details.append({"path": rel, "files": excluded_files, "bytes": excluded_bytes})
                    continue
                entries.append(_AuthorizedEntry(rel, kind, child_result, child_fd))
                walk(child_fd, rel)
                continue
            if kind != stat.S_IFREG:
                raise ValueError(f"Unsupported workspace entry: {rel}")
            child_fd, child_result = _open_verified_child(parent_fd, name, stat.S_IFREG)
            entries.append(_AuthorizedEntry(rel, kind, child_result, child_fd))
            files += 1
            bytes_total += int(child_result.st_size)

    try:
        walk(root_fd, "")
        included_paths = len(entries) - 1
        inspection = {
            "workspace": str(lexical_root),
            "files": files,
            "bytes": bytes_total,
            "symlinks": sorted(symlinks),
            "symlink_targets": dict(sorted(symlink_targets.items())),
            "generated_dirs": sorted(generated),
            "generated_details": sorted(generated_details, key=lambda item: item["path"]),
            "generated_bytes": sum(item["bytes"] for item in generated_details),
            "estimated_archive_bytes": bytes_total + (files * 512),
            "safe_for_archive": not symlinks,
            "included_path_count": included_paths,
            "included_file_count": files,
            "included_byte_count": bytes_total,
            "omitted_paths": sorted(generated),
            "omission_policy_source": "routine-generated-directory-policy" if generated else "none",
        }
        return inspection, entries
    except Exception:
        for entry in reversed(entries):
            if entry.fd is not None:
                with contextlib.suppress(OSError):
                    os.close(entry.fd)
        raise


def _close_authorized_entries(entries: list[_AuthorizedEntry]) -> None:
    for entry in reversed(entries):
        if entry.fd is not None:
            with contextlib.suppress(OSError):
                os.close(entry.fd)


def _tarinfo_from_authorized(entry: _AuthorizedEntry, name: str) -> tarfile.TarInfo:
    info = tarfile.TarInfo(name)
    info.mode = stat.S_IMODE(entry.result.st_mode)
    info.mtime = int(entry.result.st_mtime)
    info.uid = int(entry.result.st_uid)
    info.gid = int(entry.result.st_gid)
    info.uname = ""
    info.gname = ""
    if entry.kind == stat.S_IFDIR:
        info.type = tarfile.DIRTYPE
    else:
        info.type = tarfile.REGTYPE
        info.size = int(entry.result.st_size)
    return info


def _write_authorized_tar(path: Path, slug: str, entries: list[_AuthorizedEntry]) -> None:
    with tarfile.open(path, "w:gz", dereference=False) as archive:
        for entry in entries:
            name = slug if not entry.name else f"{slug}/{entry.name}"
            info = _tarinfo_from_authorized(entry, name)
            if entry.kind == stat.S_IFREG:
                if entry.fd is None:
                    raise ValueError(f"Authorized file has no stable descriptor: {name}")
                current = os.fstat(entry.fd)
                if not _identity_matches(current, _object_identity(entry.result)):
                    raise ValueError(f"Authorized file identity changed before archive read: {name}")
                with os.fdopen(os.dup(entry.fd), "rb") as stream:
                    archive.addfile(info, stream)
            else:
                archive.addfile(info)


def _relative_path(root: Path, candidate: Path) -> str:
    try:
        relative = candidate.resolve(strict=False).relative_to(root.resolve())
    except ValueError as exc:
        raise ValueError("Workspace entry escapes the workspace root.") from exc
    text = relative.as_posix()
    if not text or text == "." or text.startswith("../") or "/../" in f"/{text}":
        raise ValueError("Workspace entry has an unsafe relative path.")
    return text


def inspect_workspace(root: Path, *, include_generated: bool = False) -> dict[str, Any]:
    if POSIX_FD_HARDENING:
        inspection, entries = _capture_workspace_posix(root, include_generated=include_generated)
        _close_authorized_entries(entries)
        return inspection
    root = root.resolve()
    if not root.is_dir() or root.is_symlink():
        raise ValueError("Workspace must be a real directory.")
    symlinks: list[str] = []
    symlink_targets: dict[str, str] = {}
    generated: list[str] = []
    generated_details: list[dict[str, Any]] = []
    generated_bytes = 0
    files = 0
    bytes_total = 0
    included_paths = 0
    for current, dirs, names in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        kept_dirs: list[str] = []
        for name in dirs:
            path = current_path / name
            rel = _relative_path(root, path)
            if path.is_symlink():
                symlinks.append(rel)
                symlink_targets[rel] = os.readlink(path)
                continue
            if name in GENERATED_DIR_NAMES and not include_generated:
                generated.append(rel)
                excluded_files = 0
                excluded_bytes = 0
                for excluded_current, _, excluded_names in os.walk(path, topdown=True, followlinks=False):
                    for excluded_name in excluded_names:
                        excluded_path = Path(excluded_current) / excluded_name
                        if excluded_path.is_symlink():
                            continue
                        if excluded_path.is_file():
                            excluded_files += 1
                            excluded_bytes += excluded_path.stat().st_size
                generated_bytes += excluded_bytes
                generated_details.append({"path": rel, "files": excluded_files, "bytes": excluded_bytes})
                continue
            kept_dirs.append(name)
            included_paths += 1
        dirs[:] = kept_dirs
        for name in names:
            path = current_path / name
            rel = _relative_path(root, path)
            if path.is_symlink():
                symlinks.append(rel)
                symlink_targets[rel] = os.readlink(path)
                continue
            if not path.is_file():
                raise ValueError(f"Unsupported workspace entry: {rel}")
            files += 1
            bytes_total += path.stat().st_size
    return {
        "workspace": str(root),
        "files": files,
        "bytes": bytes_total,
        "symlinks": sorted(symlinks),
        "symlink_targets": dict(sorted(symlink_targets.items())),
        "generated_dirs": sorted(generated),
        "generated_details": sorted(generated_details, key=lambda item: item["path"]),
        "generated_bytes": generated_bytes,
        "estimated_archive_bytes": bytes_total + (files * 512),
        "safe_for_archive": not symlinks,
        "included_path_count": included_paths + files,
        "included_file_count": files,
        "included_byte_count": bytes_total,
        "omitted_paths": sorted(generated),
        "omission_policy_source": "routine-generated-directory-policy" if generated else "none",
    }


def _validate_members(archive: tarfile.TarFile, slug: str) -> list[str]:
    names: list[str] = []
    prefix = f"{slug}/"
    for member in archive.getmembers():
        name = member.name.replace("\\", "/")
        parts = name.split("/")
        if name.startswith("/") or name.startswith("../") or "/../" in f"/{name}" or "\x00" in name or any(part in {"", ".", ".."} for part in parts):
            raise ValueError(f"Archive contains an unsafe path: {member.name}")
        if not name.startswith(prefix) and name != slug:
            raise ValueError("Archive must contain exactly one project-root directory.")
        if member.issym() or member.islnk() or member.isdev() or not (member.isdir() or member.isfile()):
            raise ValueError(f"Archive contains an unsupported entry type: {member.name}")
        names.append(name)
    if not any(name == slug for name in names):
        raise ValueError("Archive is missing its project-root directory.")
    return names


def validate_archive(path: Path, slug: str) -> dict[str, Any]:
    slug = validate_slug(slug)
    digest = hashlib.sha256()
    size = path.stat().st_size
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    with tarfile.open(path, "r:gz") as archive:
        members = _validate_members(archive, slug)
        if not any(name.startswith(f"{slug}/.devfleet/") for name in members):
            raise ValueError("Archive is missing .devfleet metadata.")
    return {"archive_sha256": digest.hexdigest(), "archive_bytes": size, "entries": len(members), "verified": True}


def _assert_same_filesystem(staging: Path, destination_parent: Path) -> None:
    """Require atomic rename topology before moving an existing workspace."""
    try:
        staging_device = os.stat(staging).st_dev
        destination_device = os.stat(destination_parent).st_dev
    except OSError as exc:
        raise ValueError("Workspace restore cannot verify same-filesystem atomic promotion.") from exc
    if staging_device != destination_device:
        raise ValueError("Workspace restore refused: staging and destination are on different filesystems.")


def _restore_journal_path(destination: Path) -> Path:
    return destination.parent / f".{destination.name}.restore-transaction.json"


RESTORE_JOURNAL_SCHEMA_VERSION = 1
RESTORE_JOURNAL_PHASES = frozenset({
    "PREPARED",
    "OLD_MOVED_TO_ROLLBACK",
    "NEW_PROMOTED",
    "POSTCHECK_PASSED",
    "COMMITTED",
})


@dataclass(frozen=True)
class _RestoreJournal:
    schema_version: int
    slug: str
    destination: Path
    staging_root: Path
    rollback: Path
    phase: str


def _is_reparse_point(path: Path) -> bool:
    """Return true for symlinks and Windows junction/reparse objects."""
    if path.is_symlink():
        return True
    try:
        attributes = getattr(path.lstat(), "st_file_attributes", 0)
    except OSError:
        return False
    return bool(attributes & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))


def _canonical_journal_path(value: Any, field: str) -> tuple[Path, Path]:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Restore journal {field} must be a non-empty absolute path.")
    raw = Path(value)
    if not raw.is_absolute() or value.strip() in {".", ".."}:
        raise ValueError(f"Restore journal {field} must be an absolute path.")
    lexical = Path(os.path.abspath(os.fspath(raw)))
    canonical = raw.resolve(strict=False)
    if os.path.normcase(os.fspath(lexical)) != os.path.normcase(os.fspath(canonical)):
        raise ValueError(f"Restore journal {field} uses a symlink, reparse point, or alias path.")
    return lexical, canonical


def _require_direct_safe_transaction_child(path: Path, parent: Path, field: str) -> None:
    if path == parent or path.parent != parent:
        raise ValueError(f"Restore journal {field} is not a direct transaction sibling.")
    if path.exists() or path.is_symlink():
        if _is_reparse_point(path):
            raise ValueError(f"Restore journal {field} is a symlink or reparse point.")


def _parse_restore_journal(journal: Any, requested_destination: Path) -> _RestoreJournal:
    if not isinstance(journal, dict):
        raise ValueError("Restore journal must be a JSON object.")
    schema_version = journal.get("schema_version")
    if type(schema_version) is not int or schema_version != RESTORE_JOURNAL_SCHEMA_VERSION:
        raise ValueError("Restore journal schema version is unsupported.")

    expected_slug = validate_slug(requested_destination.name)
    slug = journal.get("slug")
    if not isinstance(slug, str) or slug != expected_slug:
        raise ValueError("Restore journal slug does not match the requested workspace.")

    destination_lexical, destination = _canonical_journal_path(journal.get("destination"), "destination")
    staging_lexical, staging_root = _canonical_journal_path(journal.get("staging_root"), "staging_root")
    rollback_lexical, rollback = _canonical_journal_path(journal.get("rollback"), "rollback")
    if destination != requested_destination or destination_lexical != requested_destination:
        raise ValueError("Restore journal destination does not match the requested workspace.")

    parent = requested_destination.parent
    for path, field in ((staging_root, "staging_root"), (rollback, "rollback")):
        if path in {requested_destination, parent}:
            raise ValueError(f"Restore journal {field} aliases the destination or transaction parent.")
        _require_direct_safe_transaction_child(path, parent, field)

    stage_pattern = re.compile(rf"^\.{re.escape(expected_slug)}-restore-[A-Za-z0-9_-]{{6,64}}$")
    rollback_pattern = re.compile(rf"^\.{re.escape(expected_slug)}\.rollback-[0-9a-f]{{32}}$")
    if not stage_pattern.fullmatch(staging_lexical.name):
        raise ValueError("Restore journal staging_root has an invalid transaction identity.")
    if not rollback_pattern.fullmatch(rollback_lexical.name):
        raise ValueError("Restore journal rollback has an invalid transaction identity.")
    if staging_root == rollback:
        raise ValueError("Restore journal staging and rollback identities overlap.")

    phase = journal.get("phase")
    if not isinstance(phase, str) or phase not in RESTORE_JOURNAL_PHASES:
        raise ValueError("Restore journal phase is unsupported.")
    return _RestoreJournal(schema_version, slug, destination, staging_root, rollback, phase)


def _write_restore_manual_recovery(destination: Path, journal_path: Path, reason: str) -> None:
    evidence_path = destination.parent / f".{destination.name}.restore-manual-recovery.json"
    atomic_json(evidence_path, {
        "schema_version": 1,
        "status": "MANUAL_RECOVERY_REQUIRED",
        "destination": str(destination),
        "journal": str(journal_path),
        "reason": reason,
        "detected_at": now_iso(),
    })


POSIX_RESTORE_JOURNAL_SCHEMA_VERSION = 2
TRANSACTION_ROOT_NAME = ".devfleet-transactions"


def _absolute_path(path: Path) -> Path:
    return Path(os.path.abspath(os.fspath(path)))


def _open_directory_path(path: Path) -> tuple[int, os.stat_result]:
    lexical = _absolute_path(path)
    observed = os.lstat(lexical)
    if stat.S_IFMT(observed.st_mode) != stat.S_IFDIR:
        raise ValueError(f"Restore path is not a real directory: {lexical}")
    fd = os.open(lexical, _fd_directory_flags())
    try:
        actual = os.fstat(fd)
        if not _identity_matches(actual, _object_identity(observed)):
            raise ValueError(f"Restore directory identity changed before authorization: {lexical}")
        return fd, actual
    except Exception:
        os.close(fd)
        raise


def _identity_at(parent_fd: int, name: str) -> dict[str, int] | None:
    try:
        return _object_identity(os.stat(name, dir_fd=parent_fd, follow_symlinks=False))
    except FileNotFoundError:
        return None


def _mkdir_verified_at(parent_fd: int, name: str, mode: int = 0o700) -> tuple[int, os.stat_result]:
    try:
        os.mkdir(name, mode, dir_fd=parent_fd)
    except FileExistsError:
        pass
    return _open_verified_child(parent_fd, name, stat.S_IFDIR)


def _remove_tree_at(parent_fd: int, name: str, expected: dict[str, int], field: str) -> None:
    current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if not _identity_matches(current, expected):
        raise RuntimeError(f"Restore transaction {field} changed before cleanup; manual recovery required.")
    kind = stat.S_IFMT(current.st_mode)
    if kind == stat.S_IFLNK:
        raise RuntimeError(f"Restore transaction {field} is an alias; manual recovery required.")
    if kind == stat.S_IFREG:
        os.unlink(name, dir_fd=parent_fd)
        return
    if kind != stat.S_IFDIR:
        raise RuntimeError(f"Restore transaction {field} has an unsupported type; manual recovery required.")
    fd, _ = _open_verified_child(parent_fd, name, stat.S_IFDIR)
    try:
        for child in sorted(os.listdir(fd)):
            child_identity = _identity_at(fd, child)
            if child_identity is None:
                raise RuntimeError(f"Restore transaction {field} changed during cleanup; manual recovery required.")
            _remove_tree_at(fd, child, child_identity, f"{field}/{child}")
    finally:
        os.close(fd)
    # The transaction parent is service-owned in the deployed Linux layout;
    # verify the named object one final time before removing the directory.
    current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if not _identity_matches(current, expected):
        raise RuntimeError(f"Restore transaction {field} changed before directory removal; manual recovery required.")
    os.rmdir(name, dir_fd=parent_fd)


def _extract_archive_at_fd(archive: tarfile.TarFile, slug: str, staging_fd: int) -> None:
    # The archive contract is <slug>/<descendants>.  Keep that root object
    # beneath the protected transaction directory so promotion can rename the
    # exact descriptor-bound staging/<slug> object.  Descendants are then
    # created relative to the already-open verified slug descriptor.
    slug_fd, _ = _mkdir_verified_at(staging_fd, slug)
    try:
        for member in archive.getmembers():
            safe_name = member.name.replace("\\", "/")
            parts = safe_name.split("/")
            if parts[0] != slug:
                raise ValueError(f"Archive member is outside the requested project: {member.name}")
            relative = parts[1:]
            if not relative:
                if member.isdir():
                    os.fchmod(slug_fd, member.mode & 0o777)
                continue
            current_fd = slug_fd
            opened: list[int] = []
            try:
                for component in relative[:-1]:
                    try:
                        child_fd, _ = _open_verified_child(current_fd, component, stat.S_IFDIR)
                    except FileNotFoundError:
                        os.mkdir(component, 0o700, dir_fd=current_fd)
                        child_fd, _ = _open_verified_child(current_fd, component, stat.S_IFDIR)
                    opened.append(child_fd)
                    current_fd = child_fd
                leaf = relative[-1]
                if member.isdir():
                    try:
                        leaf_fd, _ = _open_verified_child(current_fd, leaf, stat.S_IFDIR)
                    except FileNotFoundError:
                        os.mkdir(leaf, member.mode & 0o777, dir_fd=current_fd)
                        leaf_fd, _ = _open_verified_child(current_fd, leaf, stat.S_IFDIR)
                    os.fchmod(leaf_fd, member.mode & 0o777)
                    os.close(leaf_fd)
                else:
                    fd = os.open(leaf, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0), member.mode & 0o777, dir_fd=current_fd)
                    try:
                        source = archive.extractfile(member)
                        if source is None:
                            raise ValueError(f"Archive member could not be read: {member.name}")
                        with source, os.fdopen(fd, "wb", closefd=False) as target:
                            shutil.copyfileobj(source, target)
                        os.fchmod(fd, member.mode & 0o777)
                    finally:
                        os.close(fd)
            finally:
                for fd in reversed(