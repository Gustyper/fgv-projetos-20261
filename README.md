# Projetos de Engenharia de Dados

Este repositório contém as entregas desenvolvidas durante a disciplina de Projetos em Ciência de Dados da FGV. Ao longo do semestre, foi implementado um pipeline de dados completo, abordando todas as etapas do ciclo de vida da engenharia de dados.

## Aprendizados e Implementações

O objetivo principal foi construir uma solução analítica a partir de um sistema transacional (OLTP). Para isso, implementou-se:

- **Sistema de Origem:** Provisionamento de um banco de dados relacional e desenvolvimento de scripts para simular a chegada de novos registros.
- **Pipelines ETL:** Construção de rotinas de extração, transformação e carga, modelando os dados transacionais para um esquema estrela (Star Schema).
- **Carga Incremental e Watermark:** Implementação de controle de estado para identificar e processar exclusivamente os dados novos desde a última execução, garantindo a eficiência do pipeline.
- **Armazenamento e Particionamento:** Gravação de dados no formato colunar Parquet, aplicando particionamento lógico (por ano e mês) para otimizar as consultas e reduzir custos de leitura.
- **Análise e Visualização:** Consumo dos dados transformados através de consultas SQL distribuídas e criação de um dashboard interativo estruturado em um notebook Jupyter.
- **Automação:** Agendamento de execuções automáticas e recorrentes para os jobs de processamento.

## Tecnologias Utilizadas

A arquitetura do projeto foi integralmente construída na nuvem da Amazon (AWS) e gerenciada como código.

- **Amazon Web Services (AWS):** O ecossistema de dados foi baseado em serviços gerenciados da AWS. Utilizei o Amazon RDS (MySQL) como origem dos dados, o AWS Glue (PySpark) para a execução do ETL, o Amazon S3 para o armazenamento do Data Lake, o Amazon Athena para a camada de consultas serverless e o Amazon EventBridge para o agendamento dos jobs.
- **Terraform:** Toda a infraestrutura necessária na AWS (buckets, IAM roles, jobs do Glue, conexões e regras do EventBridge) foi provisionada através do Terraform. A aplicação de Infraestrutura como Código (IaC) assegurou a padronização, versionamento e reprodutibilidade de todo o ambiente.
- **Python:** Linguagem base para os scripts de validação, controle de watermark, simulação de cargas e desenvolvimento do dashboard (utilizando bibliotecas como Pandas e AWS Data Wrangler).
