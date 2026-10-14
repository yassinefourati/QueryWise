"""Connection settings for the live stack in compose.test.yaml. Passwords come only from the environment
(generated per run by scripts/run_live_tests.ps1); nothing secret is stored in the repository."""
import os

ADMIN = os.environ.get('QW_ADMIN_PASSWORD', '')
READER = os.environ.get('QW_READER_PASSWORD', '')
ODBC = '?driver=ODBC+Driver+18+for+SQL+Server&Encrypt=yes&TrustServerCertificate=yes'
# admin = migrator/DBA account used by the pack; reader = the account Querywise connects with (password sent separately).
SQL_ENGINES = {
    'postgres': {'admin': f'postgresql+psycopg://postgres:{ADMIN}@postgres:5432/qw_complex_energy',
                 'reader': 'postgresql+psycopg://qw_app@postgres:5432/qw_complex_energy', 'schema': None},
    'mysql': {'admin': f'mysql+pymysql://root:{ADMIN}@mysql:3306/qw_complex_retail',
              'reader': 'mysql+pymysql://qw_app@mysql:3306/qw_complex_retail', 'schema': None},
    'mariadb': {'admin': f'mariadb+pymysql://root:{ADMIN}@mariadb:3306/qw_complex_freight',
                'reader': 'mariadb+pymysql://qw_app@mariadb:3306/qw_complex_freight', 'schema': None},
    'sqlserver': {'admin': f'mssql+pyodbc://sa:{ADMIN}@sqlserver:1433/qw_complex_clinic{ODBC}',
                  'master': f'mssql+pyodbc://sa:{ADMIN}@sqlserver:1433/master{ODBC}',
                  'reader': f'mssql+pyodbc://qw_app@sqlserver:1433/qw_complex_clinic{ODBC}', 'schema': 'dbo'},
    'oracle': {'admin': f'oracle+oracledb://QW_COMPLEX:{ADMIN}@oracle:1521/?service_name=FREEPDB1',
               'dba': f'oracle+oracledb://SYSTEM:{ADMIN}@oracle:1521/?service_name=FREEPDB1',
               'reader': 'oracle+oracledb://QW_READER@oracle:1521/?service_name=FREEPDB1', 'schema': 'QW_COMPLEX'},
    'db2': {'admin': f'ibm_db_sa://db2inst1:{ADMIN}@db2:50000/QWCMPLX',
            'reader': 'ibm_db_sa://qwreader@db2:50000/QWCMPLX', 'schema': 'DB2INST1'},
}
MONGO_ADMIN = f'mongodb://root:{ADMIN}@mongodb:27017/?authSource=admin'
MONGO_READER = 'mongodb://mongodb:27017/?authSource=qw_complex_learning'
ES_URL = 'http://elasticsearch:9200'
ES_ADMIN = f'http://elastic:{ADMIN}@elasticsearch:9200'
ES_KEY_FILE = '/tmp/querywise-live/es_reader_api_key'  # Container-local and ephemeral.
ES_INDICES = ['qw-complex-reliability-requests', 'qw-complex-reliability-requests-v2', 'qw-complex-reliability-deployments-v1', 'qw-complex-reliability-incidents-v1']
