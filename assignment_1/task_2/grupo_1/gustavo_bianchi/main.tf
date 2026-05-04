provider "aws" {
  region = var.aws_region
}

# Data Sources
#===========================================================================

# busca o Security Group pelo nome
data "aws_security_group" "rds_sg" {
  name = var.sg_name
}

# busca a VPC Padrão da conta
data "aws_vpc" "default" {
  default = true
}

# busca as Subnets dentro dessa VPC Padrão
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Pega informações da primeira Subnet encontrada (necessário para a AZ)
data "aws_subnet" "first" {
  id = data.aws_subnets.default.ids[0]
}

# Resources ETL
#===========================================================================

resource "aws_s3_bucket" "datalake" {
  bucket = var.bucket_name
  force_destroy = true 
}

# Busca a Role padrão fornecida pelo AWS Learner Lab
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# Conexão do Glue usando os Data Sources para preencher a rede
resource "aws_glue_connection" "rds_conn" {
  name = "classicmodels-rds-conn"
  connection_properties = {
    JDBC_CONNECTION_URL = "jdbc:mysql://${var.db_endpoint}:3306/${var.db_name}"
    USERNAME = var.db_username
    PASSWORD = var.db_password
  }

  physical_connection_requirements {
    availability_zone      = data.aws_subnet.first.availability_zone
    security_group_id_list = [data.aws_security_group.rds_sg.id]
    subnet_id              = data.aws_subnet.first.id
  }
}


# Automatization
#===========================================================================

# Faz o upload automático do script ETL local para o bucket S3
resource "aws_s3_object" "etl_script_upload" {
  bucket = aws_s3_bucket.datalake.bucket
  key    = "scripts/etl_script.py"
  source = "${path.module}/scripts/etl_script.py" # Caminho local do arquivo
  etag   = filemd5("${path.module}/scripts/etl_script.py") # Força update se o arquivo mudar
}

# Atualização do Glue Job para referenciar o upload e passar parâmetros
resource "aws_glue_job" "etl_job" {
  name        = "classicmodels-star-schema-job"
  role_arn = data.aws_iam_role.lab_role.arn
  connections = [aws_glue_connection.rds_conn.name]

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.datalake.bucket}/${aws_s3_object.etl_script_upload.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"      = "python"
    "--TempDir"           = "s3://${aws_s3_bucket.datalake.bucket}/temp/"
    "--TARGET_BUCKET"     = aws_s3_bucket.datalake.bucket
    "--CONNECTION_NAME"   = aws_glue_connection.rds_conn.name
  }

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
}

# Regra de Ingress obrigatória para o AWS Glue (Self-Referencing)
resource "aws_security_group_rule" "glue_self_referencing" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = data.aws_security_group.rds_sg.id
  source_security_group_id = data.aws_security_group.rds_sg.id
  description              = "AWS Glue worker to worker communication"
}