import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tools.elastic_runner import main
if __name__=='__main__':
    sys.argv.insert(1,'seed')
    try: main()
    except Exception as error:
        print('FAIL ('+type(error).__name__+'); inspect locally, connection details redacted',file=sys.stderr)
        sys.exit(1)
