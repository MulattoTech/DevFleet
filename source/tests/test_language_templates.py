import json
from pathlib import Path
from devfleet.language_policy import TEMPLATES,recommend_template
from devfleet import analyzer, projects
import yaml
ROOT=Path(__file__).resolve().parents[1]
CORE={'generic','python','python-fastapi','node','typescript-node','typescript-next','go-service','dotnet-service','java-spring','rust-service'}
def test_legacy_and_new_templates_exist():
 assert {'generic','python','node'}<=set(TEMPLATES);assert len(TEMPLATES)==20
 for name in TEMPLATES:
  d=ROOT/'templates'/name;assert (d/'compose.yaml').is_file();assert (d/'.devcontainer/devcontainer.json').is_file();assert (d/'.devfleet/codexpro-bootstrap.sh').is_file();assert (d/'README.md').is_file();assert (d/'docs/architecture.md').is_file()
def test_core_metadata_commands():
 for name in CORE:
  data=json.loads((ROOT/'templates'/name/'.devfleet/template.json').read_text())
  for key in ('bootstrap_command','format_command','lint_command','test_command','health_command'):assert data[key]
def test_recommendations():assert recommend_template('python','fastapi')=='python-fastapi' and recommend_template('go')=='go-service'
def test_language_metadata_documented():
 for name in CORE:
  assert 'Language:' in (ROOT/'templates'/name/'README.md').read_text();assert 'Rationale:' in (ROOT/'templates'/name/'docs/architecture.md').read_text()

def test_generated_templates_satisfy_strict_security_contract(tmp_path,monkeypatch):
 monkeypatch.setattr(projects,'TEMPLATE_ROOT',ROOT/'templates')
 for name in TEMPLATES:
  project=tmp_path/name
  project.mkdir()
  projects._copy_template(project,name)
  compose=yaml.safe_load((project/'compose.yaml').read_text())
  services=compose['services']
  assert services
  for service in services.values():
   assert 'ALL' in [str(value).upper() for value in (service.get('cap_drop') or [])]
   assert any('no-new-privileges:true' in str(value).lower() for value in (service.get('security_opt') or []))
  findings=analyzer.analyze_project(project,'strict',force=True)
  assert not analyzer.has_blockers(findings), (name, findings)
