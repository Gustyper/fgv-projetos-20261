provider "aws" {
  region = "us-east-1"
}

# Busca a rede padrão
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
data "aws_subnet" "first" { id = data.aws_subnets.default.ids[0] }
data "aws_route_tables" "vpc_routes" { vpc_id = data.aws_vpc.default.id }

# Busca os recursos da task 1
data "aws_security_group" "rds_sg" { name = "classicmodels-sg" }
data "aws_db_instance" "rds" { db_instance_identifier = "classicmodels-instance" }

# Permissão do AWS Learner Lab
data "aws_iam_role" "lab_role" { name = "LabRole" }

# Gera um ID aleatório para evitar nomes de buckets duplicados
resource "random_id" "bucket_suffix" { byte_length = 4 }

resource "aws_s3_bucket" "datalake" {
  bucket        = "classicmodels-lake-${random_id.bucket_suffix.hex}"
  force_destroy = true
}

resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.vpc_routes.ids
}

resource "aws_s3_object" "etl_script" {
  bucket = aws_s3_bucket.datalake.bucket
  key    = "scripts/etl_script.py"
  source = "${path.module}/etl_script.py"
  etag   = filemd5("${path.module}/etl_script.py")
}

resource "aws_glue_connection" "rds_conn" {
  name = "classicmodels-glue-conn"
  connection_properties = {
    # Pega o endpoint automaticamente da Task 1
    JDBC_CONNECTION_URL = "jdbc:mysql://${data.aws_db_instance.rds.endpoint}/classicmodels"
    USERNAME            = "admin"
    PASSWORD            = var.db_password
  }

  physical_connection_requirements {
    availability_zone      = data.aws_subnet.first.availability_zone
    security_group_id_list = [data.aws_security_group.rds_sg.id]
    subnet_id              = data.aws_subnet.first.id
  }
}

resource "aws_glue_job" "etl_job" {
  name        = "classicmodels-star-schema-job"
  role_arn    = data.aws_iam_role.lab_role.arn
  connections = [aws_glue_connection.rds_conn.name]

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.datalake.bucket}/${aws_s3_object.etl_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"    = "python"
    "--TempDir"         = "s3://${aws_s3_bucket.datalake.bucket}/temp/"
    "--TARGET_BUCKET"   = aws_s3_bucket.datalake.bucket
    "--CONNECTION_NAME" = aws_glue_connection.rds_conn.name
  }

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
}

output "s3_bucket_name" {
  value = aws_s3_bucket.datalake.bucket
}

# Exporta o nome do bucket para o Python consumir automaticamente
resource "local_file" "bucket_name_export" {
  content  = aws_s3_bucket.datalake.bucket
  filename = "${path.module}/bucket_name.txt"
}


# ==============================================================================
# ASSIGNMENT 2 - TASK 2: INCREMENTAL ETL & SCHEDULING (NEW RESOURCES)
# ==============================================================================

# --- EVENTBRIDGE (Agendamento) ---

resource "aws_iam_role" "eventbridge_glue_role" {
  name = "EventBridgeGlueRole-${random_id.bucket_suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "eventbridge_glue_policy" {
  name = "EventBridgeGluePolicy-${random_id.bucket_suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "glue:StartJobRun"
        Effect   = "Allow"
        Resource = aws_glue_job.etl_job.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_glue_attach" {
  role       = aws_iam_role.eventbridge_glue_role.name
  policy_arn = aws_iam_policy.eventbridge_glue_policy.arn
}

resource "aws_cloudwatch_event_rule" "weekly_glue_trigger" {
  name                = "weekly-classicmodels-glue-trigger"
  description         = "Trigger semanal para rodar o Glue Job incremental (Task 2)"
  schedule_expression = "cron(0 12 ? * MON *)"
}

resource "aws_cloudwatch_event_target" "glue_job_target" {
  rule      = aws_cloudwatch_event_rule.weekly_glue_trigger.name
  target_id = "TriggerGlueJob"
  arn       = aws_glue_job.etl_job.arn
  role_arn  = aws_iam_role.eventbridge_glue_role.arn
}

# --- GLUE CATALOG ---

resource "aws_glue_catalog_database" "analytics_db" {
  name = "classicmodels_analytics"
}

resource "aws_glue_catalog_table" "fact_orders" {
  name          = "fact_orders"
  database_name = aws_glue_catalog_database.analytics_db.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL              = "TRUE"
    "parquet.compression" = "SNAPPY"
  }

  partition_keys {
    name = "order_year"
    type = "int"
  }

  partition_keys {
    name = "order_month"
    type = "int"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.datalake.bucket}/analytics/fact_orders/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "my-stream"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"

      parameters = {
        "serialization.format" = 1
      }
    }

    columns {
      name = "order_id"
      type = "int"
    }
    columns {
      name = "product_id"
      type = "string"
    }
    columns {
      name = "customer_id"
      type = "int"
    }
    columns {
      name = "order_date_key"
      type = "int"
    }
    columns {
      name = "country_key"
      type = "string"
    }
    columns {
      name = "quantity_ordered"
      type = "int"
    }
    columns {
      name = "price_each"
      type = "double"
    }
    columns {
      name = "sales_amount"
      type = "double"
    }
  }
}