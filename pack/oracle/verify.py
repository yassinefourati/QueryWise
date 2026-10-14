import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tools.sql_runner import main
if __name__=='__main__':
    sys.argv[1:1]=['oracle','verify']
    sys.exit(main())
