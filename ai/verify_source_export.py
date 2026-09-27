"""Verify original source bytes, permitting only recorded CRLF materialization."""
from pathlib import Path
import hashlib, json, sys
root=Path(__file__).resolve().parents[1]
rows=json.loads((root/'ai/ORIGINAL-SOURCE-INVENTORY.json').read_text(encoding='utf-8'))
errors=[];normalized=[]
for row in rows:
    p=root/row['path']
    if not p.is_file():errors.append({'path':row['path'],'error':'missing'});continue
    b=p.read_bytes()
    if hashlib.sha256(b).hexdigest()==row['sha256']:continue
    if row.get('lfSha256') and hashlib.sha256(b.replace(b'\r\n',b'\n')).hexdigest()==row['lfSha256']:
        normalized.append(row['path'])
    else:errors.append({'path':row['path'],'error':'content changed'})
print(json.dumps({'status':'FAIL' if errors else 'PASS','sourceFilesChecked':len(rows),'crlfOnlyMaterializations':normalized,'errors':errors},indent=2))
sys.exit(1 if errors else 0)
