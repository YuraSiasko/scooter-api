variable "min_tasks" {
  description = "Мінімальна кількість інстансів API"
  type        = number
  default     = 1
}

variable "max_tasks" {
  description = "Максимальна кількість інстансів API (за умовою лаби не більше 4)"
  type        = number
  default     = 3

  validation {
    condition     = var.max_tasks >= 1 && var.max_tasks <= 4
    error_message = "max_tasks має бути від 1 до 4."
  }
}

variable "cpu_target" {
  description = "Цільове середнє завантаження CPU сервісу, %"
  type        = number
  default     = 60
}

variable "scale_out_cooldown" {
  description = "Секунди, які треба чекати після додавання інстансу перед наступним додаванням"
  type        = number
  default     = 60
}

variable "scale_in_cooldown" {
  description = "Секунди, які треба чекати після видалення інстансу перед наступним видаленням"
  type        = number
  default     = 300
}

resource "aws_appautoscaling_target" "api" {
  min_capacity       = var.min_tasks
  max_capacity       = var.max_tasks
  resource_id        = "service/${aws_ecs_cluster.app_cluster.name}/${aws_ecs_service.app_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Target tracking: AWS сам створює два CloudWatch-алярми (scale-out швидкий, scale-in повільний)
# і підтримує середній CPU сервісу біля cpu_target
resource "aws_appautoscaling_policy" "cpu" {
  name               = "scooter-api-cpu-target"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
