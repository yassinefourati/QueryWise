from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
ROOT=Path(__file__).resolve().parents[1]
output=ROOT/'dist/querywise-source.zip'
allowed=['backend','scripts','dist','tests','evals','pack']
root_files=['README.md','requirements.txt','requirements-dev.txt','requirements-connectors.txt','pytest.ini','Dockerfile','compose.yaml','.dockerignore','.env.example','.gitignore','package.json','package-lock.json']
# Never package generated data, app state or secrets.
excluded={'__pycache__','.pytest_cache','output','.querywise','data'}
with ZipFile(output,'w',ZIP_DEFLATED) as archive:
    for name in root_files: archive.write(ROOT/name,name)
    for folder in allowed:
        for path in sorted((ROOT/folder).rglob('*')):
            if path.is_file() and path!=output and not excluded&set(path.relative_to(ROOT).parts) and path.name not in {'.env','secret.key','querywise-sources.json'}:
                archive.write(path,path.relative_to(ROOT))
print(f'Created {output.name} ({output.stat().st_size:,} bytes)')
