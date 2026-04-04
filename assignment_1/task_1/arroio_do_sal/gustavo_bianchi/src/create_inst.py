import boto3
import requests
import sys
import os

# Pra conseguir importar a config
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from config import CFG

def provision():
    session = boto3.Session(region_name=CFG.REGION)
    ec2 = session.client('ec2')
    rds = session.client('rds')

    # Criação do Security Group na Amazon
    ip = requests.get('https://checkip.amazonaws.com').text.strip()
    try:
        sg = ec2.create_security_group(GroupName=CFG.SG_NAME, Description='Acesso Local')
        sg_id = sg['GroupId']
        ec2.authorize_security_group_ingress(
            GroupId=sg_id, IpProtocol='tcp', FromPort=3306, ToPort=3306, CidrIp=f"{ip}/32"
        )
        print(f"Security Group criado: {sg_id}")
    except:
        sg_id = ec2.describe_security_groups(GroupNames=[CFG.SG_NAME])['SecurityGroups'][0]['GroupId']
        print(f"Security Group já existe: {sg_id}")

    # Cria a instância RDS
    try:
        rds.create_db_instance(
            DBInstanceIdentifier=CFG.DB_ID,
            MasterUsername=CFG.DB_USER,
            MasterUserPassword=CFG.DB_PASS,
            DBInstanceClass=CFG.DB_CLASS,
            Engine=CFG.DB_ENGINE,
            AllocatedStorage=CFG.DB_STORAGE,
            VpcSecurityGroupIds=[sg_id],
            PubliclyAccessible=True
        )
        print("Instância criada.")

    except Exception as e:
        print(f"Erro ao criar a instância: {e}")

        # Para pegar o endpoint da instância
        waiter = rds.get_waiter('db_instance_available')
        waiter.wait(DBInstanceIdentifier=CFG.DB_ID)
        response = rds.describe_db_instances(DBInstanceIdentifier=CFG.DB_ID)
        endpoint = response['DBInstances'][0]['Endpoint']['Address']
        print(f"Endpoint: {endpoint}")

if __name__ == "__main__":
    provision()