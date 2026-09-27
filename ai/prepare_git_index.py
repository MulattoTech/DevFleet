"""Stage the exported repository and restore original executable modes; never push."""
from pathlib import Path
import json, subprocess
root=Path(__file__).resolve().parents[1]
def git(*args):return subprocess.check_output(['git',*args],cwd=root,text=True).strip()
if Path(git('rev-parse','--show-toplevel')).resolve()!=root:
    raise SystemExit('Run git init inside this exported repository first; refusing a parent repository.')
git('add','--all')
rows=json.loads((root/'ai/ORIGINAL-SOURCE-INVENTORY.json').read_text(encoding='utf-8'))
for i in range(0,len(rows),100):
    git('add','-f','--',*[r['path'] for r in rows[i:i+100]])
for mode in ('100644','100755'):
    paths=[r['path'] for r in rows if r['gitMode']==mode]
    for i in range(0,len(paths),100):
        git('update-index','--chmod='+('+' if mode=='100755' else '-')+'x','--',*paths[i:i+100])
expected={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and '.git' not in p.relative_to(root).parts and '__pycache__' not in p.parts}
actual={p for p in git('ls-files','-z').split('\0') if p}
if expected!=actual:raise SystemExit('Staged paths differ: '+repr(sorted(expected^actual)))
print(json.dumps({'status':'PASS','stagedFiles':len(actual),'originalSourceFiles':len(rows),'pushed':False}))
