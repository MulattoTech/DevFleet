"""Bounded, non-executing reads of DevFleet audit snapshots. Standard library only."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import unicodedata
import zipfile

class AuditInputError(ValueError):
    """An input cannot be interpreted safely or unambiguously."""


def safe_relative(name: str) -> str:
    if not isinstance(name, str) or not name or name.startswith('/') or '\\' in name or ':' in name or any(c in name for c in '<>"|?*'):
        raise AuditInputError('Unsafe non-relative archive/evidence path')
    if any(ord(c) < 32 or ord(c) == 127 for c in name) or name != unicodedata.normalize('NFC', name):
        raise AuditInputError('Non-canonical archive/evidence path')
    parts=name.split('/')
    for part in parts:
        if part in ('', '.', '..') or part[-1:] in (' ', '.') or re.fullmatch(r'(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?',part):
            raise AuditInputError('Ambiguous archive/evidence path')
    return name


def hash_file(path: Path) -> str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024), b''):h.update(block)
    return h.hexdigest()


def _unique_object(pairs):
    d={}
    for k,v in pairs:
        if k in d:raise AuditInputError('Duplicate JSON property')
        d[k]=v
    return d


class Snapshot:
    """A read-only logical view. ZIP contents are never extracted or imported."""
    def __init__(self, path: Path, max_member_bytes=32*1024*1024, max_total_bytes=512*1024*1024):
        self.path=Path(path).resolve(strict=True)
        self.archive=self.path.is_file()
        self.limit=max_member_bytes
        self.records={}
        self.z=None
        self.members={}
        if not self.archive and not self.path.is_dir():raise AuditInputError('Snapshot is neither directory nor archive')
        if self.archive:
            self.z=zipfile.ZipFile(self.path)
            try:
                infos=self.z.infolist()
                if len(infos)>12000:raise AuditInputError('Archive entry limit exceeded')
                total=0; seen=set()
                for i in infos:
                    n=safe_relative(i.filename.rstrip('/') if i.is_dir() else i.filename)
                    alias=n.casefold()
                    if alias in seen:raise AuditInputError('Duplicate or case-alias archive entry')
                    seen.add(alias)
                    mode=i.external_attr>>16
                    if stat.S_ISLNK(mode) or i.flag_bits & 1:raise AuditInputError('Links/encrypted ZIP entries are not supported')
                    if not i.is_dir() and stat.S_IFMT(mode) not in (0,stat.S_IFREG):raise AuditInputError('Special archive entry rejected')
                    total+=i.file_size
                    if i.file_size>self.limit or total>max_total_bytes:raise AuditInputError('Archive uncompressed size limit exceeded')
                    if i.file_size>1024*1024 and i.file_size/max(1,i.compress_size)>1000:raise AuditInputError('Archive compression ratio limit exceeded')
                    if not i.is_dir():self.members[n]=i
            except Exception:
                self.z.close();raise
    def __enter__(self):return self
    def __exit__(self,*args):
        if self.z:self.z.close()
    def _local(self,name):
        name=safe_relative(name)
        p=self.path/name
        # Reject all symlink/reparse components, not merely an eventual escape.
        cur=self.path
        for part in name.split('/'):
            cur=cur/part
            if cur.exists() or cur.is_symlink():
                st=cur.lstat()
                if stat.S_ISLNK(st.st_mode) or getattr(st,'st_file_attributes',0)&0x400:
                    raise AuditInputError('Reparse/symlink input is not accepted')
        q=p.resolve()
        if not q.is_relative_to(self.path):raise AuditInputError('Evidence path escaped snapshot')
        return q
    def exists(self,name):
        safe_relative(name)
        return name in self.members if self.archive else self._local(name).is_file()
    def read(self,name,optional=False):
        safe_relative(name)
        if not self.exists(name):
            if optional:return None
            raise AuditInputError('Required snapshot member missing: '+name)
        if self.archive:
            with self.z.open(self.members[name]) as f:data=f.read(self.limit+1)
        else:
            p=self._local(name)
            if p.stat().st_size>self.limit:raise AuditInputError('Input file size limit exceeded: '+name)
            with p.open('rb') as f:data=f.read(self.limit+1)
        if len(data)>self.limit:raise AuditInputError('Input exceeded bounded read')
        self.records[name]={'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
        return data
    def text(self,name,optional=False):
        data=self.read(name,optional)
        if data is None:return None
        try:return data.decode('utf-8-sig')
        except UnicodeDecodeError as e:raise AuditInputError('Non-UTF8 text member: '+name) from e
    def json(self,name,optional=False):
        t=self.text(name,optional)
        if t is None:return None
        try:return json.loads(t,object_pairs_hook=_unique_object,parse_constant=lambda x:(_ for _ in ()).throw(AuditInputError('Non-finite JSON number')))
        except json.JSONDecodeError as e:raise AuditInputError('Malformed JSON member: '+name) from e
    def json_files(self,prefix):
        safe_relative(prefix)
        if self.archive:return sorted(n for n in self.members if n.startswith(prefix+'/') and n.endswith('.json'))
        folder=self._local(prefix)
        if not folder.is_dir():return []
        # Campaign metadata only: no generic recursive walk through user data.
        return sorted(p.relative_to(self.path).as_posix() for p in folder.glob('*.json') if p.is_file())
    def verify_inventory(self):
        if not self.archive:return {'status':'NOT_APPLICABLE','verifiedFiles':0,'note':'Workspace identity is checked by native validators.'}
        m=self.json('AUDIT-MANIFEST.json')
        if not isinstance(m,dict):raise AuditInputError('Audit manifest must be an object')
        errors=[];seen=set();verified=0
        for key in ('sourceInventory','evidenceInventory'):
            rows=m.get(key)
            if not isinstance(rows,list):raise AuditInputError('Audit manifest inventory missing: '+key)
            for row in rows:
                if not isinstance(row,dict):raise AuditInputError('Inventory row must be an object')
                n=safe_relative(row.get('path')); alias=n.casefold()
                if alias in seen:raise AuditInputError('Duplicate inventory path')
                seen.add(alias)
                expected=row.get('sha256');size=row.get('bytes')
                if not isinstance(expected,str) or not re.fullmatch('[0-9a-f]{64}',expected) or type(size) is not int or size<0:raise AuditInputError('Invalid inventory digest/size')
                data=self.read(n,optional=True)
                if data is None or len(data)!=size or hashlib.sha256(data).hexdigest()!=expected:errors.append(n)
                else:verified+=1
        rows=m['sourceInventory'];counts=[m.get('expectedSourceCount'),m.get('includedSourceCount')]
        if any(type(x) is not int or x!=len(rows) for x in counts):errors.append('source-count-consistency')
        meta={'AUDIT-MANIFEST.json','AUDIT-README.md','AUDIT-TREE.txt','SOURCE-MODES.json','EVIDENCE-MODES.json','SHA256SUMS.txt','EVIDENCE-SHA256SUMS.txt'}
        uncovered=sorted(n for n in self.members if n.casefold() not in seen and n not in meta)
        return {'status':'FAIL' if errors else 'PASS','verifiedFiles':verified,'sourceFiles':len(rows),
                'inventoryErrors':errors,'unindexedFiles':uncovered,'certificationCredit':False,
                'note':'Hashes verify declared inventory only; manifest is not a trusted signature or release authority.'}


def safe_output_dir(output: Path, repo: Path|None=None) -> Path:
    output=Path(output).resolve()
    if repo and output.is_relative_to(Path(repo).resolve()):raise AuditInputError('Reports must be outside the repository; avoid identity/evidence churn')
    return output


def save_report(output: Path, report: dict, markdown: str):
    output=Path(output);output.mkdir(parents=True,exist_ok=True)
    paths=[output/'analysis.json',output/'analysis.md']
    if any(p.exists() for p in paths):raise AuditInputError('Refusing to overwrite an existing analysis report; use a new output directory')
    for p,content in zip(paths,[json.dumps(report,indent=2,ensure_ascii=False)+'\n',markdown]):
        with p.open('x',encoding='utf-8',newline='\n') as f:f.write(content)
    return paths
