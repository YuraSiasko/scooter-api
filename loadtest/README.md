# Навантажувальний тест (k6)

Встановлення на Windows: `winget install k6` (або https://k6.io/docs/get-started/installation/).

Запуск (з кореня репозиторію):

```
k6 run -e BASE_URL=http://<alb-dns-name> -e VUS=60 loadtest/scenario.js
```

`<alb-dns-name>` - адреса з `terraform output website_url` (без `/docs`).
`VUS` - пікова кількість віртуальних користувачів (N). Тривалість: 3 хв ramp-up, 5 хв steady, 2 хв ramp-down = 10 хв.
Після завершення k6 друкує підсумок (запити, помилки, p50/p95/p99) і пише `loadtest/summary.json`.
