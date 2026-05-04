import os
import sys

class CFG:
    # Database Auth & Data
    DB_USER = 'admin'
    DB_PASS = 'SenhaForteBemDificil123456789'
    DB_NAME = 'classicmodels'
    SQL_PATH = 'assignment_1/task_1/data/mysqlsampledatabase.sql'
    
    # Leitura dinâmica do endpoint gerado pelo Terraform
    @classmethod
    def get_db_host(cls):
        current_dir = os.path.dirname(os.path.abspath(__file__))
        endpoint_file = os.path.join(current_dir, 'rds_endpoint.txt')
        
        try:
            with open(endpoint_file, 'r') as f:
                return f.read().strip()
        except FileNotFoundError:
            print("Erro: rds_endpoint.txt não encontrado. Rode o Terraform primeiro.")
            sys.exit(1)

    DB_HOST = property(get_db_host)