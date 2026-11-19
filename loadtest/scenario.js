// k6 сценарій: кожен віртуальний користувач за ітерацію робить 1 запис (POST) і 9 читань (GET)
// Запуск (одна команда):
//   k6 run -e BASE_URL=http://<alb-dns> -e VUS=60 loadtest/scenario.js
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL;
const VUS = parseInt(__ENV.VUS || '60');

if (!BASE_URL) {
  throw new Error('Вкажіть адресу: -e BASE_URL=http://<alb-dns>');
}

export const options = {
  scenarios: {
    scooters: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '3m', target: VUS }, // ramp-up
        { duration: '5m', target: VUS }, // steady
        { duration: '2m', target: 0 },   // ramp-down
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

const BRANDS = ['Xiaomi', 'Segway', 'Ninebot', 'Kugoo', 'Bolt'];
const JSON_HEADERS = { headers: { 'Content-Type': 'application/json' } };

export default function () {
  // 1 запис
  const body = JSON.stringify({
    brand: BRANDS[Math.floor(Math.random() * BRANDS.length)],
    battery_level: Math.floor(Math.random() * 101),
  });
  const w = http.post(`${BASE_URL}/scooters/`, body, JSON_HEADERS);
  check(w, { 'POST 200': (r) => r.status === 200 });

  // 9 читань: 6 разів найважчий звіт (його кешуємо), 3 рази простий список
  for (let i = 0; i < 6; i++) {
    const r = http.get(`${BASE_URL}/scooters/report`);
    check(r, { 'report 200': (x) => x.status === 200 });
  }
  for (let i = 0; i < 3; i++) {
    const r = http.get(`${BASE_URL}/scooters/`);
    check(r, { 'list 200': (x) => x.status === 200 });
  }

  sleep(0.5); // "think time" користувача
}

export function handleSummary(data) {
  const d = data.metrics.http_req_duration.values;
  const reqs = data.metrics.http_reqs.values;
  const failed = data.metrics.http_req_failed.values.rate;
  const text = [
    '',
    '===== ПІДСУМОК (скопіюйте в docs/LOADTEST.md) =====',
    `Запитів всього:   ${reqs.count}`,
    `Запитів/с (avg):  ${reqs.rate.toFixed(1)}`,
    `Частка помилок:   ${(failed * 100).toFixed(2)} %`,
    `Затримка p50:     ${d.med.toFixed(1)} мс`,
    `Затримка p95:     ${d['p(95)'].toFixed(1)} мс`,
    `Затримка p99:     ${d['p(99)'].toFixed(1)} мс`,
    `Затримка max:     ${d.max.toFixed(1)} мс`,
    '',
  ].join('\n');
  return {
    stdout: text,
    'loadtest/summary.json': JSON.stringify(data, null, 2),
  };
}
