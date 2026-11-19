# Scooter Rental API

FastAPI + PostgreSQL (RDS) на AWS ECS Fargate за ALB. Інфраструктура в `terraform/`, деплой через GitHub Actions (`.github/workflows/deploy.yml`).

## Лабораторна 2

| Завдання | Де |
|---|---|
| Автоскейлінг (1-3 інстанси, CPU 60 %) | `terraform/autoscaling.tf`, `docs/AUTOSCALING.md` |
| Навантажувальний тест (k6) | `loadtest/`, `docs/LOADTEST.md` |
| Дашборд CloudWatch | `terraform/monitoring.tf`, `docs/AUTOSCALING.md` |
| Алерти e-mail (CPU > 70 % 2 хв) | `terraform/monitoring.tf`, `docs/ALERTS.md` |
| Кеш читань (ElastiCache Redis, cache-aside, TTL 45 с) | `terraform/cache.tf`, `main.py`, `docs/CACHE.md` |

Запуск інфраструктури:

```
cd terraform
terraform apply                         # кеш увімкнено
terraform apply -var cache_enabled=false  # для порівняння без кешу
terraform destroy                       # після захисту!
```

## Примітка про OIDC

Умова вимагає CI/CD через OIDC. Спроба створити `aws_iam_openid_connect_provider` для GitHub завершується `AccessDenied ... with an explicit deny in a service control policy`: навчальний AWS-акаунт входить в організацію університету, і SCP забороняє `iam:CreateOpenIDConnectProvider`. Тому CI лишився на ключах IAM-користувача в GitHub Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), як у лабораторній 1; у репозиторії секретів немає.
