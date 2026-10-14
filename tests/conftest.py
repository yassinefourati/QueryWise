"""Isolate tests from the developer's environment and app state before the backend is imported."""
import os, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
os.environ['QUERYWISE_STATE_DIR'] = tempfile.mkdtemp(prefix='querywise-test-state-')
for name in ('AI_PROVIDER', 'ANTHROPIC_API_KEY', 'ANTHROPIC_MODEL', 'ANTHROPIC_EFFORT', 'ANTHROPIC_FALLBACKS', 'OLLAMA_URL', 'OLLAMA_MODEL', 'OLLAMA_DEFAULT_URL',
             'DATABASE_URL', 'QUERYWISE_SOURCES_FILE', 'QUERYWISE_SECRET_KEY', 'QUERYWISE_DEFAULT_SOURCE', 'QUERYWISE_ALLOWED_HOSTS'):
    os.environ.pop(name, None)
if not (ROOT/'data/sample.db').exists():
    subprocess.run([sys.executable, str(ROOT/'scripts/seed.py')], check=True, cwd=ROOT)
