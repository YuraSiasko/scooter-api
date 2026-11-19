locals {
  ecs_dims = {
    ClusterName = aws_ecs_cluster.app_cluster.name
    ServiceName = aws_ecs_service.app_service.name
  }
}

# ---------- Дашборд (завдання 3) ----------
resource "aws_cloudwatch_dashboard" "api" {
  dashboard_name = "scooter-api"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "1. Інстанси: бажана і фактична кількість"
          region = "eu-north-1"
          view   = "timeSeries"
          period = 60
          stat   = "Maximum"
          metrics = [
            ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", aws_ecs_cluster.app_cluster.name, "ServiceName", aws_ecs_service.app_service.name, { label = "Desired" }],
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", aws_ecs_cluster.app_cluster.name, "ServiceName", aws_ecs_service.app_service.name, { label = "Running" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "2. CPU сервісу, % (ціль автоскейлінгу 60, алерт 70)"
          region = "eu-north-1"
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.app_cluster.name, "ServiceName", aws_ecs_service.app_service.name],
          ]
          annotations = {
            horizontal = [
              { label = "Ціль скейлінгу", value = var.cpu_target },
              { label = "Поріг алерту", value = 70 },
            ]
          }
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "3. Запити за хвилину (ALB)"
          region = "eu-north-1"
          view   = "timeSeries"
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.api_alb.arn_suffix],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "4. Затримка p95, секунди"
          region = "eu-north-1"
          view   = "timeSeries"
          period = 60
          stat   = "p95"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.api_alb.arn_suffix, "TargetGroup", aws_lb_target_group.api_tg.arn_suffix],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          title  = "5. Помилки 5xx (від застосунку і від ALB)"
          region = "eu-north-1"
          view   = "timeSeries"
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.api_alb.arn_suffix, "TargetGroup", aws_lb_target_group.api_tg.arn_suffix, { label = "5xx від контейнерів" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.api_alb.arn_suffix, { label = "5xx від ALB" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6
        properties = {
          title  = "Додатково: навантаження на БД (для docs/CACHE.md)"
          region = "eu-north-1"
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.scooter_db.identifier, { label = "RDS CPU, %" }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.scooter_db.identifier, { label = "З'єднання", yAxis = "right" }],
          ]
        }
      },
    ]
  })
}

# ---------- Алерти (завдання 4) ----------
resource "aws_sns_topic" "alerts" {
  name = "scooter-api-alerts"
}

# Після apply на пошту прийде лист - підписку треба підтвердити, інакше листів з алертами не буде
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Перевантаження: CPU > 70% протягом 2 хвилин. ok_actions дає лист про відновлення.
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "scooter-api-cpu-high"
  alarm_description   = "Середній CPU сервісу > 70% протягом 2 хвилин"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = local.ecs_dims
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
